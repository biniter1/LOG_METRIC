#!/usr/bin/env bash
# TC05 - Mất 1 vmstorage (vmstorage-1) trong 3 phút.
# Kỳ vọng:
#   - Ghi vẫn chạy (vminsert dồn sang 2 node còn lại).
#   - Query trả kết quả ĐẦY ĐỦ, isPartial=false (nhờ RF=2 + vmselect -replicationFactor=2).
#   - Node lên lại: không gap ở dữ liệu MỚI.
source "$(dirname "$0")/_common.sh"
DOWN=${DOWN:-180}
POD=vmstorage-1
header "TC05 ${POD} down ${DOWN}s"
pf vmauth "$VMAUTH_PORT" 8427

before=$(promq 'count(up)')
node=$(cordon_and_kill "$POD")
log "Đã cordon ${node} và xóa ${POD}"
sleep 20
kubectl -n "$NS" get pod "$POD" --no-headers 2>/dev/null | sed 's/^/    /' || true

log "Query trong lúc ${POD} down:"
r=$(promq_raw 'count(up)')
echo "    count(up)=$(jq -r '.data.result[0].value[1]' <<<"$r") (trước: ${before})  isPartial=$(jq -r '.isPartial // false' <<<"$r")"
[[ "$(jq -r '.isPartial // false' <<<"$r")" == "false" ]] && ok "kết quả đầy đủ, không partial" || fail "kết quả partial"

countdown "$DOWN" "${POD} đang down"
uncordon "$node"
wait_ready statefulset/vmstorage 300s
sleep 30
metric_gap_check $(( DOWN + 60 ))
