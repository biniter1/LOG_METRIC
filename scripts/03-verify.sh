#!/usr/bin/env bash
# Kiểm tra sức khỏe end-to-end (= Test case TC01 trong docs/08-test-cases.md).
source "$(dirname "$0")/lib.sh"
pf_all
rc=0

log "1. Pod"
notready=$(kubectl -n "$NS" get pods --no-headers | awk '$3!="Running" && $3!="Completed"' || true)
if [[ -z "$notready" ]]; then ok "mọi pod Running"; else fail "pod chưa Running:"; echo "$notready"; rc=1; fi

log "2. vmagent scrape được target"
up=$(promq 'sum(up)'); total=$(promq 'count(up)')
echo "    up=${up} / targets=${total}"
[[ "$up" != "none" && "$up" == "$total" ]] && ok "mọi target UP" || { warn "có target DOWN: $(promq_raw 'up==0' | jq -c '[.data.result[].metric.pod]')"; }

log "3. Dedup hoạt động (2 vmagent nhưng chỉ 1 sample / 15s)"
# 5 phút / 15s = 20 sample. Không dedup sẽ ra ~40.
n=$(promq 'max(count_over_time(up{app="podinfo"}[5m]))')
echo "    samples/5m của up{app=podinfo} = ${n} (kỳ vọng ~20, KHÔNG phải ~40)"
if [[ "$n" != "none" ]] && (( ${n%.*} <= 22 )); then ok "dedup OK"; else fail "dedup sai hoặc chưa đủ dữ liệu"; rc=1; fi

log "4. Mỗi vmstorage đều có dữ liệu (replication)"
for i in 0 1 2; do
  rows=$(promq "sum(vm_rows{type=~\"storage/.*\", pod=\"vmstorage-${i}\"})")
  echo "    vmstorage-${i}: rows=${rows}"
done

log "5. Logs có ở CẢ A và B, không trùng, không mất"
check_flow "$VLA_PORT" "vlogs-a" || rc=1
check_flow "$VLB_PORT" "vlogs-b" || rc=1

log "6. Đọc logs qua vmauth"
c=$(logsq "$VMAUTH_PORT" '_time:5m | stats count() as c' | jq -r .c)
[[ "${c:-0}" -gt 0 ]] && ok "vmauth -> VictoriaLogs: ${c} dòng trong 5 phút" || { fail "vmauth không trả logs"; rc=1; }

log "7. Backup gần nhất"
for p in vmstorage-0 vmstorage-1 vmstorage-2; do
  t=$(kubectl -n "$NS" exec "$p" -c vmbackup -- cat /tmp/last-backup-ok 2>/dev/null || echo "chưa có")
  echo "    ${p}: ${t}"
done
for p in vlogs-a-0 vlogs-b-0; do
  t=$(kubectl -n "$NS" exec "$p" -c backup -- cat /tmp/last-backup-ok 2>/dev/null || echo "chưa có")
  echo "    ${p}: ${t}"
done

[[ $rc == 0 ]] && ok "TẤT CẢ KIỂM TRA ĐẠT" || fail "CÓ KIỂM TRA KHÔNG ĐẠT"
exit $rc
