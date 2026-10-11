#!/usr/bin/env bash
# Copy 1 partition ngày (YYYYMMDD) từ instance nguồn sang instance đích, qua S3.
# Dùng để BÙ khoảng thiếu sau khi 1 instance được restore từ backup cũ.
#
#   scripts/backup/vl-resync-partition.sh 20261010 a b     # copy ngày 10/10 từ A sang B
#
# Các bước:
#   nguồn : snapshot partition -> rclone lên s3:vl-backups/resync/<day> -> xóa snapshot
#   đích  : detach partition -> rclone về /vlogs/partitions/<day> -> attach partition
#
# CHỈ dùng cho ngày ĐÃ KẾT THÚC. Partition của hôm nay vẫn đang nhận log mới, detach nó
# sẽ làm lỗi ghi; script từ chối trừ khi có FORCE=1.
source "$(dirname "$0")/../lib.sh"

day=${1:?"cần YYYYMMDD"}; src=${2:?"nguồn a|b"}; dst=${3:?"đích a|b"}
today=$(date -u +%Y%m%d)
if [[ "$day" == "$today" && "${FORCE:-0}" != 1 ]]; then
  die "partition hôm nay (${day}) đang nhận ghi. Đợi qua ngày hoặc đặt FORCE=1 nếu hiểu rủi ro."
fi

S="kubectl -n $NS exec vlogs-${src}-0 -c backup --"
D="kubectl -n $NS exec vlogs-${dst}-0 -c backup --"
VL=http://127.0.0.1:9428

log "1. Snapshot partition ${day} trên vlogs-${src}"
snap=$($S wget -qO- --post-data='' "${VL}/internal/partition/snapshot/create?partition_prefix=${day}" | tr -d '[]" \n' | cut -d, -f1)
[[ -n "$snap" ]] || die "không tạo được snapshot (partition không tồn tại trên nguồn?)"
echo "    snapshot: $snap"

log "2. Upload snapshot lên s3:vl-backups/resync/${day}"
$S rclone sync "$snap" "s3:vl-backups/resync/${day}" --s3-no-check-bucket
$S wget -qO- --post-data='' "${VL}/internal/partition/snapshot/delete?path=${snap}" >/dev/null || true

log "3. Detach partition ${day} trên vlogs-${dst} (bỏ qua lỗi nếu chưa có)"
$D wget -qO- --post-data='' "${VL}/internal/partition/detach?name=${day}" >/dev/null 2>&1 || true

log "4. Tải partition về vlogs-${dst}"
$D rclone sync "s3:vl-backups/resync/${day}" "/vlogs/partitions/${day}"

log "5. Attach partition ${day} trên vlogs-${dst}"
$D wget -qO- --post-data='' "${VL}/internal/partition/attach?name=${day}" >/dev/null
ok "partition ${day}: vlogs-${src} -> vlogs-${dst} xong"
