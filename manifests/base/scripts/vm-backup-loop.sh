#!/bin/sh
# Sidecar chạy cạnh vmstorage: backup incremental định kỳ lên S3.
#
# - vmbackup tự gọi /snapshot/create trên vmstorage (localhost:8482) -> snapshot
#   tức thời, nhất quán, KHÔNG cần dừng vmstorage.
# - Đích: s3://vm-backups/<pod-name>/latest  (mỗi node một thư mục riêng vì mỗi
#   vmstorage giữ một tập dữ liệu khác nhau).
# - Lần đầu upload toàn bộ, các lần sau chỉ upload part mới (incremental).
# - Sau khi upload xong, vmbackup tự xóa snapshot.
set -u

INTERVAL="${BACKUP_INTERVAL_SECONDS:-900}"
INITIAL_DELAY="${BACKUP_INITIAL_DELAY_SECONDS:-120}"
DST="s3://${BACKUP_BUCKET}/${POD_NAME}/latest"

echo "[vm-backup] pod=${POD_NAME} dst=${DST} interval=${INTERVAL}s"
# ONCE=1: chạy đúng 1 vòng rồi thoát (dùng cho "backup ngay" bằng kubectl exec)
[ "${ONCE:-0}" = 1 ] || sleep "${INITIAL_DELAY}"

while true; do
  start=$(date +%s)
  echo "[vm-backup] $(date -u +%FT%TZ) start backup"
  if /vmbackup-prod \
      -storageDataPath=/storage \
      -snapshot.createURL=http://127.0.0.1:8482/snapshot/create \
      -dst="${DST}" \
      -customS3Endpoint="${S3_ENDPOINT}" \
      -loggerLevel=WARN; then
    end=$(date +%s)
    echo "[vm-backup] $(date -u +%FT%TZ) OK in $((end - start))s"
    # Đánh dấu thời điểm backup thành công gần nhất (dùng cho kiểm tra RPO).
    date -u +%FT%TZ > /tmp/last-backup-ok
  else
    echo "[vm-backup] $(date -u +%FT%TZ) FAILED, retry next round"
  fi
  [ "${ONCE:-0}" = 1 ] && exit 0
  sleep "${INTERVAL}"
done
