#!/usr/bin/env bash
# Hàm dùng chung cho các test chaos.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# metric_gap_check <window_seconds>
# Đếm số sample của up{app=podinfo} trong cửa sổ W giây gần nhất (sau dedup).
# Kỳ vọng ~ W/15. Thiếu nhiều hơn 1 sample => có GAP.
metric_gap_check() {
  local w=$1 expected n
  expected=$(( w / 15 ))
  n=$(promq "min(count_over_time(up{app=\"podinfo\"}[${w}s]))")
  echo "    min samples trong ${w}s = ${n} (kỳ vọng ~${expected})"
  if [[ "$n" != "none" ]] && (( ${n%.*} >= expected - 1 )); then
    ok "metrics KHÔNG có gap"; return 0
  fi
  fail "metrics CÓ gap (thiếu $(( expected - ${n%.*} )) sample)"; return 1
}

# cordon_and_kill <pod>: giữ pod "chết" thật sự bằng cách cordon node của nó.
# Pod dùng PVC local-path bị gắn với node => không thể chạy ở node khác => Pending.
cordon_and_kill() {
  local pod=$1 node
  node=$(pod_node "$pod")
  kubectl cordon "$node" >/dev/null
  kubectl -n "$NS" delete pod "$pod" --wait=false >/dev/null
  echo "$node"
}
uncordon() { kubectl uncordon "$1" >/dev/null; }

countdown() { # countdown <seconds> <message>
  local s=$1; shift
  for ((i=s; i>0; i-=10)); do printf "\r    %s: còn %3ss " "$*" "$i"; sleep $(( i<10 ? i : 10 )); done; echo
}

header() { echo; echo "================ $* ================"; }
