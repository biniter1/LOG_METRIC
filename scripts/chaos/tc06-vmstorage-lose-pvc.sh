#!/usr/bin/env bash
# TC06 - SELF-RECOVERY: vmstorage-2 mất trắng PVC (giả lập hỏng đĩa).
# Kỳ vọng:
#   - StatefulSet tạo PVC mới (trống) -> initContainer phát hiện trống -> vmrestore từ S3.
#   - vmstorage-2 lên lại với dữ liệu cũ (tới lần backup cuối).
#   - Query trong suốt quá trình vẫn đầy đủ (RF=2 còn 1 bản ở node khác).
source "$(dirname "$0")/_common.sh"
POD=vmstorage-2
header "TC06 ${POD} mất PVC"
pf vmauth "$VMAUTH_PORT" 8427

log "Backup ngay để RPO nhỏ nhất"
kubectl -n "$NS" exec "$POD" -c vmbackup -- env ONCE=1 /bin/sh /scripts/vm-backup-loop.sh | tail -1

rows_before=$(promq "sum(vm_rows{type=~\"storage/.*\",pod=\"${POD}\"})")
log "rows trên ${POD} trước sự cố: ${rows_before}"

log "Xóa pod + PVC (mất trắng dữ liệu)"
# Scale 3 -> 2 để StatefulSet gỡ đúng ordinal cao nhất (vmstorage-2), xóa PVC, rồi scale lại 3.
# (Xóa PVC khi pod còn chạy sẽ kẹt Terminating và pod mới tham chiếu PVC đang bị xóa.)
kubectl -n "$NS" scale statefulset/vmstorage --replicas=2
kubectl -n "$NS" wait --for=delete "pod/${POD}" --timeout=180s
kubectl -n "$NS" delete pvc "storage-${POD}" --wait=true
kubectl -n "$NS" scale statefulset/vmstorage --replicas=3
log "Chờ pod mới (initContainer restore)..."
wait_pod_ready "$POD" 600

log "Log của initContainer:"
kubectl -n "$NS" logs "$POD" -c restore-if-empty | grep -E "vm-restore" | sed 's/^/    /'
kubectl -n "$NS" logs "$POD" -c restore-if-empty | grep -q "restore OK" \
  && ok "đã tự restore từ S3" || fail "không thấy restore OK"

sleep 45
rows_after=$(promq "sum(vm_rows{type=~\"storage/.*\",pod=\"${POD}\"})")
echo "    rows trên ${POD}: trước=${rows_before} sau=${rows_after}"
[[ "$rows_after" != "none" ]] && (( ${rows_after%.*} > 0 )) && ok "dữ liệu cũ đã về" || fail "node trống"
