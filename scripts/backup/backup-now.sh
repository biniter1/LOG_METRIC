#!/usr/bin/env bash
# Chạy backup NGAY (không đợi chu kỳ 15 phút) cho toàn bộ vmstorage và VictoriaLogs.
# Dùng trước các test phá dữ liệu (TC06, TC10) để RPO nhỏ nhất.
source "$(dirname "$0")/../lib.sh"

for i in 0 1 2; do
  log "vmbackup vmstorage-${i}"
  kubectl -n "$NS" exec "vmstorage-${i}" -c vmbackup -- \
    env ONCE=1 /bin/sh /scripts/vm-backup-loop.sh | tail -2
done
for r in a b; do
  log "vl-backup vlogs-${r}-0"
  kubectl -n "$NS" exec "vlogs-${r}-0" -c backup -- \
    env ONCE=1 /bin/sh /scripts/vl-backup-loop.sh | tail -4
done
ok "backup xong. Xem: make list-backups"
