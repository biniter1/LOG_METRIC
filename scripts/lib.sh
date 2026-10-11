#!/usr/bin/env bash
# Thư viện hàm dùng chung cho mọi script. Được "source", không chạy trực tiếp.
set -euo pipefail

NS="${NS:-observability}"
DEMO_NS="${DEMO_NS:-demo}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cổng local khi port-forward
VMAUTH_PORT="${VMAUTH_PORT:-18427}"   # vmauth: metrics + logs (endpoint đọc chính)
VLA_PORT="${VLA_PORT:-19428}"         # vlogs-a trực tiếp
VLB_PORT="${VLB_PORT:-29428}"         # vlogs-b trực tiếp

c_green=$'\e[32m'; c_red=$'\e[31m'; c_yel=$'\e[33m'; c_blu=$'\e[36m'; c_off=$'\e[0m'
log()  { echo "${c_blu}[$(date +%H:%M:%S)]${c_off} $*"; }
ok()   { echo "${c_green}  ✔ $*${c_off}"; }
warn() { echo "${c_yel}  ! $*${c_off}"; }
fail() { echo "${c_red}  ✘ $*${c_off}"; }
die()  { fail "$*"; exit 1; }

need() { for b in "$@"; do command -v "$b" >/dev/null || die "thiếu công cụ: $b"; done; }
need kubectl curl jq

# ---------- port-forward tự quản lý ----------
_PF_PIDS=()
_pf_cleanup() { for p in "${_PF_PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap _pf_cleanup EXIT

# pf <svc> <local-port> <remote-port>
pf() {
  local svc=$1 lport=$2 rport=$3
  if curl -s -o /dev/null "http://127.0.0.1:${lport}/health"; then return 0; fi
  kubectl -n "$NS" port-forward "svc/${svc}" "${lport}:${rport}" >/dev/null 2>&1 &
  _PF_PIDS+=($!)
  for _ in $(seq 1 30); do
    curl -s -o /dev/null "http://127.0.0.1:${lport}/health" && return 0
    sleep 0.5
  done
  die "không port-forward được svc/${svc}"
}
pf_all() {
  pf vmauth  "$VMAUTH_PORT" 8427
  pf vlogs-a "$VLA_PORT" 9428 || true
  pf vlogs-b "$VLB_PORT" 9428 || true
}

# ---------- metrics ----------
# promq '<MetricsQL>' -> in giá trị scalar đầu tiên (hoặc "none")
promq() {
  curl -s "http://127.0.0.1:${VMAUTH_PORT}/select/0/prometheus/api/v1/query" \
    --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "none"'
}
promq_raw() {
  curl -s "http://127.0.0.1:${VMAUTH_PORT}/select/0/prometheus/api/v1/query" \
    --data-urlencode "query=$1"
}

# ---------- logs ----------
# logsq <port> '<LogsQL>' -> JSON lines
logsq() {
  curl -s "http://127.0.0.1:$1/select/logsql/query" --data-urlencode "query=$2"
}
# Ép flush buffer RAM để log vừa ghi query được ngay (dùng trong test)
vl_flush() { curl -s -X POST "http://127.0.0.1:$1/internal/force_flush" >/dev/null || true; }

# flow_stats <port> -> "rows uniq min max" cho log của pod flow-generator HIỆN TẠI.
# Lọc theo tên pod vì seq đếm lại từ 1 mỗi khi pod khởi động lại.
flow_pod() {
  kubectl -n "$DEMO_NS" get pod -l app=flow-generator \
    -o jsonpath='{.items[0].metadata.name}'
}
flow_stats() {
  local port=$1 pod; pod="${2:-$(flow_pod)}"
  vl_flush "$port"
  logsq "$port" "_time:7d kubernetes.pod_name:=${pod} seq:* | stats count() as rows, count_uniq(seq) as uniq, min(seq) as mn, max(seq) as mx" \
    | jq -r '"\(.rows) \(.uniq) \(.mn) \(.mx)"'
}
# check_flow <port> <label>: in kết quả và trả về 0 nếu không trùng, không mất
check_flow() {
  local port=$1 label=$2 rows uniq mn mx
  read -r rows uniq mn mx < <(flow_stats "$port") || true
  if [[ -z "${mx:-}" || "$mx" == "null" ]]; then fail "${label}: không có log flow-generator"; return 1; fi
  local expect=$(( mx - mn + 1 ))
  echo "    ${label}: rows=${rows} uniq_seq=${uniq} seq=[${mn}..${mx}] expected=${expect}"
  if [[ "$rows" == "$uniq" && "$uniq" == "$expect" ]]; then
    ok "${label}: đủ ${rows} dòng, không trùng, không mất"; return 0
  fi
  [[ "$rows" != "$uniq" ]] && fail "${label}: có $((rows - uniq)) dòng TRÙNG"
  [[ "$uniq" != "$expect" ]] && fail "${label}: MẤT $((expect - uniq)) dòng"
  return 1
}

# ---------- k8s helpers ----------
wait_ready() { # wait_ready <kind/name> [timeout]
  kubectl -n "$NS" rollout status "$1" --timeout="${2:-300s}"
}
pod_node() { kubectl -n "$NS" get pod "$1" -o jsonpath='{.spec.nodeName}'; }
now_s() { date +%s; }
# wait_pod_ready <pod> [timeout_s]: chờ pod được tạo rồi Ready (kubectl wait lỗi nếu pod chưa tồn tại)
wait_pod_ready() {
  local pod=$1 t=${2:-600}
  for _ in $(seq 1 60); do kubectl -n "$NS" get pod "$pod" >/dev/null 2>&1 && break; sleep 2; done
  kubectl -n "$NS" wait --for=condition=Ready "pod/${pod}" --timeout="${t}s"
}
