# 07 — Runbook lệnh

Tra cứu nhanh. Mặc định `NS=observability`. Đặt alias cho gọn:

```bash
alias k=kubectl
export NS=observability
```

Các lệnh `curl` bên dưới giả định đang chạy `make ui` (hoặc tự port-forward): vmauth ở `:8427`, vlogs-a ở `:19428`, vlogs-b ở `:29428`.

---

## 1. Trạng thái chung

```bash
make status                                          # pod theo node
k -n $NS get pods -o wide -l app=vmstorage           # vị trí 3 vmstorage
k -n $NS get pvc                                     # PVC của vmstorage/vmagent/vlogs/minio
k -n $NS get pdb                                     # PodDisruptionBudget
k -n $NS get events --sort-by=.lastTimestamp | tail -20
k get nodes -L lab/zone
```

## 2. Metrics (VictoriaMetrics)

```bash
# Query nhanh qua vmauth
q() { curl -s localhost:8427/select/0/prometheus/api/v1/query --data-urlencode "query=$1" | jq '.data.result'; }

q 'up == 0'                                          # target đang DOWN
q 'count(up)'                                        # số target
q 'max(count_over_time(up{app="podinfo"}[5m]))'      # kiểm tra dedup (~20)
q 'sum by (pod) (vm_rows{type=~"storage/.*"})'       # rows trên từng vmstorage
q 'sum(rate(vm_rows_inserted_total{app="vminsert"}[1m]))'     # tốc độ ghi
q 'sum by (pod) (vmagent_remotewrite_pending_data_bytes)'      # buffer vmagent (nếu metric có)
q 'sum by (pod) (vm_persistentqueue_bytes_pending)'            # buffer persistent queue vmagent

# Kiểm tra partial response khi có vmstorage down
curl -s localhost:8427/select/0/prometheus/api/v1/query --data-urlencode 'query=count(up)' | jq '{isPartial, r: .data.result}'

# Xem target vmagent đang scrape
k -n $NS port-forward pod/vmagent-0 8429:8429 &  ;  curl -s localhost:8429/targets | head -30

# Reload cấu hình scrape sau khi sửa configmap
k -n $NS apply -k manifests/base
k -n $NS exec vmagent-0 -- wget -qO- --post-data='' http://127.0.0.1:8429/-/reload
k -n $NS exec vmagent-1 -- wget -qO- --post-data='' http://127.0.0.1:8429/-/reload

# Log thành phần
k -n $NS logs vmstorage-0 -c vmstorage --tail=50
k -n $NS logs deploy/vminsert --tail=50
k -n $NS logs vmagent-0 --tail=50
```

## 3. Logs (VictoriaLogs)

```bash
lq() { curl -s localhost:${2:-8427}/select/logsql/query --data-urlencode "query=$1"; }

lq '_time:5m | stats count() as c'                                          # qua vmauth
lq '_time:5m | stats count() as c' 19428                                    # A trực tiếp
lq '_time:5m | stats count() as c' 29428                                    # B trực tiếp
lq '_time:10m kubernetes.pod_namespace:=demo | stats by (kubernetes.container_name) count()'
lq '_time:1h kubernetes.container_name:=flow-generator | stats by (src,dst,port) count() as hits'
lq '_time:5m error' | head                                                  # tìm full-text

# So sánh A và B bằng seq (không trùng / không mất)
source scripts/lib.sh && pf_all && check_flow $VLA_PORT vlogs-a && check_flow $VLB_PORT vlogs-b

# Partition & snapshot
k -n $NS exec vlogs-a-0 -c backup -- wget -qO- --post-data='' http://127.0.0.1:9428/internal/partition/list
k -n $NS exec vlogs-a-0 -c backup -- wget -qO- --post-data='' http://127.0.0.1:9428/internal/partition/snapshot/list

# Ép flush để log vừa ghi query được ngay
curl -s -X POST localhost:19428/internal/force_flush

# vlagent
k -n $NS logs ds/vlagent --tail=50
q 'sum by (pod) (vlagent_remotewrite_pending_data_bytes)'          # buffer theo node
q 'sum(rate(vlagent_remotewrite_packets_dropped_total[5m]))'       # gói bị drop (phải = 0)
```

## 4. Backup

```bash
make backup-now                      # backup ngay tất cả
make list-backups                    # liệt kê S3

# Backup ngay một instance
k -n $NS exec vmstorage-1 -c vmbackup -- env ONCE=1 /bin/sh /scripts/vm-backup-loop.sh
k -n $NS exec vlogs-b-0   -c backup   -- env ONCE=1 /bin/sh /scripts/vl-backup-loop.sh

# Lần backup thành công gần nhất
k -n $NS exec vmstorage-0 -c vmbackup -- cat /tmp/last-backup-ok
k -n $NS exec vlogs-a-0   -c backup   -- cat /tmp/last-backup-ok

# Log của sidecar backup
k -n $NS logs vmstorage-0 -c vmbackup --tail=20
k -n $NS logs vlogs-a-0   -c backup   --tail=20

# Duyệt S3 bằng rclone có sẵn trong sidecar
k -n $NS exec vlogs-a-0 -c backup -- rclone lsd s3:vm-backups/
k -n $NS exec vlogs-a-0 -c backup -- rclone lsf s3:vl-backups/vlogs-a-0/
```

## 5. Restore

**Tự động:** xóa PVC đúng cách và để initContainer lo phần còn lại.

```bash
# vmstorage-2 (ordinal cao nhất): scale xuống, xóa PVC, scale lên
k -n $NS scale sts/vmstorage --replicas=2
k -n $NS wait --for=delete pod/vmstorage-2 --timeout=180s
k -n $NS delete pvc storage-vmstorage-2
k -n $NS scale sts/vmstorage --replicas=3
k -n $NS logs vmstorage-2 -c restore-if-empty -f

# vlogs-b
k -n $NS scale sts/vlogs-b --replicas=0
k -n $NS delete pvc data-vlogs-b-0
k -n $NS scale sts/vlogs-b --replicas=1
k -n $NS logs vlogs-b-0 -c restore-if-empty -f
```

> Với vmstorage-0 hoặc vmstorage-1 thì không scale được riêng lẻ. Hãy cordon node, xóa pod, xóa PVC, rồi uncordon. Hoặc xóa PVC trước (`--wait=false`), sau đó xóa pod. Nếu pod mới kẹt `Pending` vì PVC đang Terminating, xóa pod thêm một lần nữa.

**Bù partition logs từ replica kia:**

```bash
scripts/backup/vl-resync-partition.sh 20261010 a b     # ngày 10/10 từ A sang B
```

## 6. Bảo trì

```bash
k drain <node> --ignore-daemonsets --delete-emptydir-data       # PDB tự chặn nếu vi phạm
k uncordon <node>
k -n $NS rollout restart deploy/vminsert deploy/vmselect deploy/vmauth   # rolling, không downtime
k -n $NS rollout restart sts/vmagent                                     # lần lượt từng agent
k -n $NS rollout restart ds/vlagent
```

Nâng cấp phiên bản: sửa `images:` trong `manifests/base/kustomization.yaml`, rồi chạy `kubectl apply -k manifests/base`. StatefulSet sẽ rolling từng pod một.

## 7. Bảng metric nên đặt cảnh báo

| Metric / biểu thức | Ý nghĩa | Ngưỡng gợi ý |
|---|---|---|
| `up == 0` | Target down | > 2 phút |
| `vm_persistentqueue_bytes_pending` (vmagent) | Buffer metrics đang tích lũy | > 100MB |
| `vlagent_remotewrite_pending_data_bytes` | Buffer logs đang tích lũy | > 500MB (gần mức 1GB thì bắt đầu mất) |
| `vlagent_remotewrite_packets_dropped_total` | vlagent bỏ dữ liệu | rate > 0 |
| `rate(vl_rows_dropped_total[5m]) > 0` | VictoriaLogs từ chối log (timestamp ngoài retention) | > 0 |
| `time() - <lần backup cuối>` | Backup bị kẹt | > 2 × chu kỳ |
| `count(up{app="vmstorage"} == 1) < 3` | Mất vmstorage | ngay lập tức |
