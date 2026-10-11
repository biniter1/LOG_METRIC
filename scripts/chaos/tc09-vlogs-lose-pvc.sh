#!/usr/bin/env bash
# TC09 - SELF-RECOVERY logs: vlogs-b mất trắng PVC.
# Kỳ vọng:
#   - initContainer tải partition từ s3:vl-backups/vlogs-b-0/ về.
#   - Log phát sinh lúc B down: vlagent buffer rồi đẩy bù.
#   - Log ghi vào B trong khoảng [lần backup cuối -> lúc mất PVC]: KHÔNG có trong backup
#     -> B thiếu đúng khoảng đó (= RPO). A vẫn đủ, nên query qua vmauth vẫn đủ.
source "$(dirname "$0")/_common.sh"
POD=vlogs-b-0
header "TC09 ${POD} mất PVC"
pf vlogs-a "$VLA_PORT" 9428

log "Backup ngay để RPO nhỏ nhất"
kubectl -n "$NS" exec "$POD" -c backup -- env ONCE=1 /bin/sh /scripts/vl-backup-loop.sh | tail -2
t_backup=$(now_s)

log "Xóa PVC + pod"
kubectl -n "$NS" scale statefulset/vlogs-b --replicas=0
kubectl -n "$NS" wait --for=delete "pod/${POD}" --timeout=180s
t_lost=$(now_s)
kubectl -n "$NS" delete pvc "data-${POD}" --wait=true
kubectl -n "$NS" scale statefulset/vlogs-b --replicas=1
sleep 5
echo "    khoảng hở backup -> mất PVC: $(( t_lost - t_backup ))s (~$(( (t_lost - t_backup) * 5 )) dòng flow dự kiến thiếu trên B)"

wait_pod_ready "$POD" 600
kubectl -n "$NS" logs "$POD" -c restore-if-empty | sed 's/^/    /'
sleep 60
pf vlogs-b "$VLB_PORT" 9428
rc=0
check_flow "$VLA_PORT" "vlogs-a" || rc=1
check_flow "$VLB_PORT" "vlogs-b" || warn "B thiếu đúng khoảng RPO là KỲ VỌNG; xem docs/08-test-cases.md#tc09"
exit $rc
