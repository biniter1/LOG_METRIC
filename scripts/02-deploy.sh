#!/usr/bin/env bash
# Triển khai toàn bộ stack THEO THỨ TỰ PHỤ THUỘC và chờ từng tầng Ready.
#   1. Namespace + Secret + MinIO + bucket   (S3 phải có trước để initContainer restore được)
#   2. vmstorage -> vminsert/vmselect         (storage trước, rồi tầng stateless)
#   3. vmagent                                (bắt đầu ghi metrics)
#   4. VictoriaLogs A/B -> vlagent            (đích phải sẵn sàng trước collector)
#   5. vmauth + Grafana                       (tầng đọc)
#   6. demo workload                          (sinh dữ liệu)
# Lệnh "kubectl apply -k" áp TOÀN BỘ manifest 1 lần (idempotent), sau đó script chỉ
# chờ theo đúng thứ tự để dễ thấy tầng nào bị kẹt.
source "$(dirname "$0")/lib.sh"

log "Apply manifests (kustomize)"
kubectl apply -k "$REPO_ROOT/manifests/base"

log "1/6 MinIO + bucket"
wait_ready statefulset/minio
kubectl -n "$NS" wait --for=condition=complete job/minio-create-buckets --timeout=180s
ok "MinIO sẵn sàng, bucket vm-backups & vl-backups đã tạo"

log "2/6 VictoriaMetrics cluster"
wait_ready statefulset/vmstorage 600s
wait_ready deployment/vminsert
wait_ready deployment/vmselect
ok "vmstorage x3, vminsert x2, vmselect x2"

log "3/6 vmagent x2 (active-active)"
wait_ready statefulset/vmagent
ok "vmagent sẵn sàng"

log "4/6 VictoriaLogs A/B + vlagent"
wait_ready statefulset/vlogs-a
wait_ready statefulset/vlogs-b
wait_ready daemonset/vlagent
ok "vlogs-a, vlogs-b, vlagent"

log "5/6 vmauth + Grafana"
wait_ready deployment/vmauth
wait_ready deployment/grafana 600s || warn "Grafana chưa Ready (thường do tải plugin chậm) - không ảnh hưởng đường dữ liệu"

log "6/6 Demo workload"
kubectl apply -f "$REPO_ROOT/manifests/demo/demo.yaml"
kubectl -n "$DEMO_NS" rollout status deploy/podinfo --timeout=180s
kubectl -n "$DEMO_NS" rollout status deploy/flow-generator --timeout=180s
kubectl -n "$DEMO_NS" rollout status deploy/load-generator --timeout=180s

log "Phân bố pod theo node:"
kubectl -n "$NS" get pods -o wide --sort-by=.spec.nodeName \
  | awk 'NR==1 || /vmstorage|vmagent|vlogs/ {print $1, $3, $7}' | column -t
ok "Triển khai xong. Đợi ~1-2 phút cho dữ liệu chảy rồi chạy: make verify"
