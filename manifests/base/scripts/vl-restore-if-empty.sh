#!/bin/sh
# initContainer của VictoriaLogs = SELF-RECOVERY.
#
# /vlogs/partitions còn dữ liệu -> bỏ qua.
# Trống (PVC mới) -> tải mọi partition từ s3:vl-backups/<pod>/ về /vlogs/partitions/.
# VictoriaLogs tự nạp các thư mục partition này khi khởi động.
#
# Dữ liệu từ lần backup cuối -> lúc instance chết: KHÔNG có trong backup.
#   - Khoảng này vẫn còn đầy đủ ở replica kia (A hoặc B) -> query qua vmauth vẫn đủ.
#   - Có thể bù bằng scripts/backup/vl-resync-partition.sh (copy partition từ replica kia).
# Log phát sinh TRONG LÚC instance down: vlagent đã buffer, sẽ tự đẩy bù khi lên lại.
set -u

if [ -d /vlogs/partitions ] && [ -n "$(ls -A /vlogs/partitions 2>/dev/null)" ]; then
  echo "[vl-restore] partitions exist -> skip restore"
  exit 0
fi

SRC="s3:${BACKUP_BUCKET}/${POD_NAME}"
echo "[vl-restore] empty volume -> restoring from ${SRC}"
mkdir -p /vlogs/partitions

if rclone lsf "${SRC}/" --dirs-only >/tmp/parts 2>/dev/null && [ -s /tmp/parts ]; then
  rclone copy "${SRC}/" /vlogs/partitions/ --log-level INFO
  echo "[vl-restore] restored partitions:"; cat /tmp/parts
else
  echo "[vl-restore] no backup found (fresh cluster?) -> start empty"
fi
exit 0
