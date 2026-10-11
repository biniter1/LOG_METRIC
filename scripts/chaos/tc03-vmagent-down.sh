#!/usr/bin/env bash
# TC03 - Mất 1 vmagent trong 2 phút. Kỳ vọng: metrics KHÔNG có gap
# (vmagent còn lại vẫn scrape + ghi; không cần failover).
source "$(dirname "$0")/_common.sh"
DOWN=${DOWN:-120}
header "TC03 vmagent-1 down ${DOWN}s"
pf vmauth "$VMAUTH_PORT" 8427

log "Scale vmagent 2 -> 1 (vmagent-1 biến mất)"
kubectl -n "$NS" scale statefulset/vmagent --replicas=1
countdown "$DOWN" "vmagent-1 đang down"
log "Scale lại 2"
kubectl -n "$NS" scale statefulset/vmagent --replicas=2
wait_ready statefulset/vmagent
sleep 30
metric_gap_check $(( DOWN + 60 ))
