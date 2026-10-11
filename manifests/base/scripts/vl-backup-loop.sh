#!/bin/sh
# Sidecar chạy cạnh VictoriaLogs: backup từng per-day partition lên S3.
#
# Dùng API snapshot của VictoriaLogs (có từ v1.44): snapshot là "ảnh chụp" tức thời
# và nhất quán của partition -> KHÔNG cần dừng VictoriaLogs.
#
# Mỗi vòng:
#   1. POST /internal/partition/list                       -> ["20261010","20261011",...]
#   2. với mỗi partition p:
#        POST /internal/partition/snapshot/create?partition_prefix=p -> ["<đường dẫn snapshot>"]
#        rclone sync <snapshot>  s3:vl-backups/<pod>/<p>
#        POST /internal/partition/snapshot/delete?path=<snapshot>
#
# Partition các ngày cũ không còn thay đổi -> rclone thấy giống hệt và bỏ qua rất nhanh.
# Sidecar mount PVC ở CÙNG đường dẫn (/vlogs) với VictoriaLogs, nên đường dẫn snapshot
# trả về từ API dùng được trực tiếp.
set -u

VL="http://127.0.0.1:9428"
INTERVAL="${BACKUP_INTERVAL_SECONDS:-900}"
INITIAL_DELAY="${BACKUP_INITIAL_DELAY_SECONDS:-120}"
DEST="s3:${BACKUP_BUCKET}/${POD_NAME}"

post() { wget -qO- --post-data='' "$1"; }
json_list() { tr -d '[]" \n' | tr ',' ' '; }

echo "[vl-backup] pod=${POD_NAME} dest=${DEST} interval=${INTERVAL}s"
# ONCE=1: chạy đúng 1 vòng rồi thoát (dùng cho "backup ngay" bằng kubectl exec)
[ "${ONCE:-0}" = 1 ] || sleep "${INITIAL_DELAY}"

while true; do
  echo "[vl-backup] $(date -u +%FT%TZ) start"
  ok=1
  parts=$(post "${VL}/internal/partition/list" | json_list)
  if [ -z "${parts}" ]; then
    echo "[vl-backup] no partitions yet"
  fi
  for p in ${parts}; do
    snap=$(post "${VL}/internal/partition/snapshot/create?partition_prefix=${p}" | json_list | cut -d' ' -f1)
    if [ -z "${snap}" ]; then
      echo "[vl-backup] snapshot FAILED for ${p}"; ok=0; continue
    fi
    if rclone sync "${snap}" "${DEST}/${p}" --s3-no-check-bucket --log-level ERROR; then
      echo "[vl-backup] partition ${p} -> ${DEST}/${p} OK"
    else
      echo "[vl-backup] partition ${p} upload FAILED"; ok=0
    fi
    post "${VL}/internal/partition/snapshot/delete?path=${snap}" >/dev/null || true
  done
  # Dọn snapshot mồ côi (nếu vòng trước bị kill giữa chừng)
  post "${VL}/internal/partition/snapshot/delete_stale?max_age=1h" >/dev/null || true
  [ "${ok}" = 1 ] && date -u +%FT%TZ > /tmp/last-backup-ok
  echo "[vl-backup] $(date -u +%FT%TZ) done ok=${ok}"
  [ "${ONCE:-0}" = 1 ] && exit 0
  sleep "${INTERVAL}"
done
