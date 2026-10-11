#!/usr/bin/env bash
# TC08 - Restart toàn bộ vlagent.
# Kỳ vọng: checkpoint trên hostPath -> đọc tiếp đúng offset -> không trùng, không mất.
source "$(dirname "$0")/_common.sh"
header "TC08 restart vlagent"
pf vlogs-a "$VLA_PORT" 9428
pf vlogs-b "$VLB_PORT" 9428

kubectl -n "$NS" rollout restart daemonset/vlagent
wait_ready daemonset/vlagent
sleep 30
rc=0
check_flow "$VLA_PORT" "vlogs-a" || rc=1
check_flow "$VLB_PORT" "vlogs-b" || rc=1
exit $rc
