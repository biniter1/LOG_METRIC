#!/usr/bin/env bash
# TC07 - VictoriaLogs A down 3 phút.
# Kỳ vọng:
#   - Query qua vmauth vẫn trả logs (failover sang B).
#   - vlagent buffer phần log của A; A lên lại -> đẩy bù.
#   - Sau khi hồi phục: A và B ĐỀU đủ, không trùng, không mất.
source "$(dirname "$0")/_common.sh"
DOWN=${DOWN:-180}
POD=vlogs-a-0
header "TC07 ${POD} down ${DOWN}s"
pf vmauth "$VMAUTH_PORT" 8427
pf vlogs-b "$VLB_PORT" 9428

node=$(cordon_and_kill "$POD")
log "Đã cordon ${node}, xóa ${POD}"
sleep 15

log "Query qua vmauth khi A down:"
c=$(logsq "$VMAUTH_PORT" '_time:2m | stats count() as c' | jq -r .c)
[[ "${c:-0}" -gt 0 ]] && ok "vmauth vẫn trả ${c} dòng (đang đọc từ B)" || fail "vmauth không trả logs"

countdown "$DOWN" "${POD} đang down"
log "Buffer của vlagent (pending bytes):"
promq_raw 'sum by (pod) (vlagent_remotewrite_pending_data_bytes)' \
  | jq -r '.data.result[] | "    \(.metric.pod): \(.value[1]) bytes"' || true

uncordon "$node"
wait_ready statefulset/vlogs-a
log "Đợi vlagent đẩy bù..."
sleep 60
pf vlogs-a "$VLA_PORT" 9428
rc=0
check_flow "$VLA_PORT" "vlogs-a" || rc=1
check_flow "$VLB_PORT" "vlogs-b" || rc=1
exit $rc
