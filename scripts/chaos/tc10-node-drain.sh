#!/usr/bin/env bash
# TC10 - Bảo trì node: drain 1 worker, rồi thử drain worker thứ 2.
# Kỳ vọng:
#   - Drain node 1 thành công; pod stateful của node đó Pending (PVC gắn node).
#   - Drain node 2 bị PDB CHẶN (vmstorage maxUnavailable=1 đã dùng hết) -> bảo vệ RF=2.
source "$(dirname "$0")/_common.sh"
header "TC10 node drain + PDB"

n1=$(pod_node vmstorage-0); n2=$(pod_node vmstorage-1)
log "Drain ${n1} (đang chứa vmstorage-0)"
kubectl drain "$n1" --ignore-daemonsets --delete-emptydir-data --timeout=120s || true
kubectl -n "$NS" get pods -o wide | awk -v n="$n1" 'NR==1 || $3=="Pending" || $7==n' | sed 's/^/    /'

log "Thử drain ${n2} (chứa vmstorage-1) - kỳ vọng BỊ CHẶN bởi PDB"
if timeout 60 kubectl drain "$n2" --ignore-daemonsets --delete-emptydir-data --timeout=50s 2>&1 | tail -3; then :; fi
if kubectl -n "$NS" get pod vmstorage-1 -o jsonpath='{.status.phase}' | grep -q Running; then
  ok "vmstorage-1 vẫn Running -> PDB đã bảo vệ"
else
  fail "vmstorage-1 bị evict"
fi

log "Khôi phục"
kubectl uncordon "$n1" "$n2"
wait_ready statefulset/vmstorage 300s
ok "đã uncordon"
