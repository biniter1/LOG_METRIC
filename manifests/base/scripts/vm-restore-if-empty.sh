#!/bin/sh
# initContainer của vmstorage = cơ chế SELF-RECOVERY.
#
# Volume còn dữ liệu  -> bỏ qua, khởi động bình thường.
# Volume trống (PVC mới/mất PVC) -> thử vmrestore từ s3://vm-backups/<pod>/latest.
# Không có backup (cụm mới tinh) -> khởi động với volume trống.
#
# Vì sao cần restore dù đã có RF=2?
#   VictoriaMetrics cluster KHÔNG tự "re-replicate" dữ liệu cũ sang node thay thế.
#   Node mới chỉ nhận dữ liệu MỚI. Dữ liệu cũ của node đó chỉ còn 1 bản ở node khác
#   -> mất thêm 1 node nữa là mất dữ liệu. Restore đưa số bản về lại 2.
set -u

if [ -d /storage/data ] && [ -n "$(ls -A /storage/data 2>/dev/null)" ]; then
  echo "[vm-restore] /storage has data -> skip restore"
  exit 0
fi

SRC="s3://${BACKUP_BUCKET}/${POD_NAME}/latest"
echo "[vm-restore] empty volume -> trying restore from ${SRC}"

if /vmrestore-prod \
    -src="${SRC}" \
    -storageDataPath=/storage \
    -customS3Endpoint="${S3_ENDPOINT}"; then
  echo "[vm-restore] restore OK"
else
  echo "[vm-restore] no usable backup (fresh cluster?) -> start with empty storage"
  # Dọn file đánh dấu restore dở dang (nếu có) để vmstorage khởi động sạch.
  rm -rf /storage/* 2>/dev/null || true
fi
exit 0
