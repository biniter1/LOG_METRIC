#!/usr/bin/env bash
# Liệt kê nội dung bucket backup. Dùng rclone có sẵn trong sidecar backup của vlogs-a.
source "$(dirname "$0")/../lib.sh"
X="kubectl -n $NS exec vlogs-a-0 -c backup --"

log "s3:vm-backups (mỗi vmstorage một thư mục)"
$X rclone size s3:vm-backups/ 2>/dev/null || true
for i in 0 1 2; do
  echo "  vmstorage-${i}/latest: $($X rclone size "s3:vm-backups/vmstorage-${i}/latest" --json 2>/dev/null | jq -r '"\(.count) files, \(.bytes) bytes"')"
done

log "s3:vl-backups (mỗi instance -> mỗi ngày một thư mục partition)"
for r in a b; do
  echo "  vlogs-${r}-0: $($X rclone lsf "s3:vl-backups/vlogs-${r}-0/" --dirs-only 2>/dev/null | tr '\n' ' ')"
done
