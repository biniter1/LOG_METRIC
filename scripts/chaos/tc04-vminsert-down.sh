#!/usr/bin/env bash
# TC04 - Toàn bộ vminsert down 2 phút (tầng ghi mất hẳn).
# Kỳ vọng: vmagent buffer xuống PVC; vminsert lên lại thì gửi bù -> KHÔNG gap.
source "$(dirname "$0")/_common.sh"
DOWN=${DOWN:-120}
header "TC04 vminsert down ${DOWN}s"
pf vmauth "$VMAUTH_PORT" 8427

kubectl -n "$NS" scale deployment/vminsert --replicas=0
countdown "$DOWN" "vminsert = 0"
log "Kích thước buffer trên vmagent trong lúc vminsert down:"
for p in vmagent-0 vmagent-1; do
  echo "    $p: $(kubectl -n "$NS" exec "$p" -- du -sh /buffer 2>/dev/null | cut -f1)"
done
kubectl -n "$NS" scale deployment/vminsert --replicas=2
wait_ready deployment/vminsert
log "Đợi vmagent đẩy bù buffer..."
sleep 60
metric_gap_check $(( DOWN + 90 ))
