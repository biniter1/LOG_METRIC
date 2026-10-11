#!/usr/bin/env bash
# TC02 - Chứng minh dedup: 2 vmagent cùng gửi nhưng mỗi 15s chỉ còn 1 sample.
source "$(dirname "$0")/_common.sh"
header "TC02 dedup"
pf vmauth "$VMAUTH_PORT" 8427

log "Số vmagent đang scrape:"
promq_raw 'up{app="vmagent"}' | jq -r '.data.result[].metric.pod' | sed 's/^/    /'

log "Mỗi vmagent tự scrape bao nhiêu sample/giây (trước khi ghi):"
promq_raw 'sum by (pod) (rate(vm_promscrape_scraped_samples_sum{app="vmagent"}[5m]))' \
  | jq -r '.data.result[] | "    \(.metric.pod): \(.value[1]) samples/s"'

log "vminsert nhận vào (tổng 2 agent):"
echo "    $(promq 'sum(rate(vm_rows_inserted_total{app="vminsert"}[5m]))') rows/s  (~ 2 x mỗi agent)"

log "Sau dedup khi đọc: số sample của 1 series trong các cửa sổ"
for w in 1m 5m 15m; do
  n=$(promq "max(count_over_time(up{app=\"podinfo\"}[$w]))")
  echo "    count_over_time(up[$w]) = $n"
done
echo "    Kỳ vọng: 1m≈4, 5m≈20, 15m≈60. Nếu ≈ gấp đôi => dedup KHÔNG hoạt động."
