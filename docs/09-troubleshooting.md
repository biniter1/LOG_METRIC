# 09 — Xử lý sự cố và lên production

## 1. Lỗi thường gặp

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| vmstorage `Pending` ngay khi deploy | Không đủ 3 worker cho required anti-affinity | Dùng đúng `kind/kind-config.yaml` (3 worker) |
| Pod `ImagePullBackOff` | Tag không tồn tại | `make prereqs`, sửa `images:` trong `kustomization.yaml` |
| `minio-create-buckets` không Complete | MinIO chưa Ready | `k -n observability logs job/minio-create-buckets`; job tự retry |
| `make verify` bước 3 ra `none` | Chưa đủ 5 phút dữ liệu | Đợi rồi chạy lại |
| Dedup ra ~40 thay vì ~20 | Thiếu `-dedup.minScrapeInterval` hoặc 2 agent có label khác nhau | Kiểm tra args vmselect/vmstorage; không dùng `external_labels` khác nhau |
| Target trùng lặp trong `/targets` | Pod có nhiều container port | Relabel `keep_if_equal` đã xử lý; kiểm tra annotation `prometheus.io/port` khớp `containerPort` |
| Logs không có `seq` | flow-generator restart, hoặc vlagent chưa đọc | `k -n demo logs deploy/flow-generator`; `k -n observability logs ds/vlagent` |
| vlagent báo `skipping invalid CRI log line` | File log hỏng do node tắt đột ngột | Bỏ qua; xem log containerd |
| Grafana không Ready | Không tải được plugin (không có Internet) | Bỏ `GF_INSTALL_PLUGINS`, dùng VMUI thay thế |
| Pod mới kẹt `Pending` sau khi xóa PVC | Xóa PVC khi pod còn chạy → PVC Terminating | Xóa pod thêm lần nữa; lần sau dùng quy trình scale ở runbook §5 |
| `vl-backup` báo `snapshot FAILED` | Phiên bản VictoriaLogs < v1.44 (chưa có API snapshot) | Nâng VictoriaLogs |
| `vmrestore` lỗi credential | Thiếu `AWS_REGION` hoặc sai endpoint | Kiểm tra secret `s3-credentials` |

Lệnh chẩn đoán nhanh:

```bash
k -n observability describe pod <pod> | tail -20
k -n observability logs <pod> -c <container> --previous
k -n observability get events --sort-by=.lastTimestamp | tail
```

## 2. Giới hạn đã biết của lab

- **MinIO single-node**: không HA. Chỉ đóng vai S3.
- **local-path PV gắn với node**: pod stateful không di chuyển được khi node chết. Đây cũng là lý do TC05 và TC07 dùng cordon. Trên EKS với EBS thì PV gắn với AZ, không gắn với node, nên pod có thể chuyển sang node khác trong cùng AZ.
- **Không có TLS/auth** giữa các thành phần.
- **Buffer vlagent nằm trên hostPath**: mất node thì mất cả buffer của node đó. Log phát sinh trên node đó cũng mất theo, vì file log nằm chính trên node ấy.
- **Partition logs hôm nay** không resync được giữa A và B khi đang chạy.

## 3. Checklist chuyển lên EKS (cho kiến trúc KLTN)

| Hạng mục | Lab | EKS |
|---|---|---|
| S3 | MinIO + access key | S3 thật + **IRSA** (bỏ `AWS_ACCESS_KEY_ID`, gắn IAM role vào ServiceAccount) |
| Endpoint S3 | `-customS3Endpoint=http://minio:9000` | Bỏ flag này, đặt `AWS_REGION` |
| Bucket | Không versioning | Bật versioning + lifecycle (chuyển Glacier sau N ngày) + mã hóa SSE-KMS |
| StorageClass | local-path | `gp3` EBS, `volumeBindingMode: WaitForFirstConsumer` |
| Topology | `kubernetes.io/hostname` | Thêm anti-affinity theo `topology.kubernetes.io/zone`; 3 vmstorage ở 3 AZ |
| VictoriaLogs | 2 single-node | A và B ở 2 AZ khác nhau; scale lên VictoriaLogs cluster nếu cần |
| Bảo mật | Không | NetworkPolicy chỉ cho vmagent → vminsert, vlagent → vlogs, vmauth → select; vmauth có auth; `-partitionManageAuthKey` |
| Quản lý | `kubectl apply -k` | ArgoCD Application trỏ vào `manifests/` |
| Cảnh báo | Không | vmalert + các rule ở runbook §7 |
| Backup metrics | Chỉ `latest` | Thêm daily/weekly bằng `-origin` |

## 4. Gợi ý trình bày trong báo cáo KLTN

1. **Vấn đề:** Tier 1 cần dữ liệu đầy đủ, vì thiếu dữ liệu dẫn tới NetworkPolicy sai.
2. **Thiết kế ban đầu và lý do loại** (active-passive), dùng hình 01.
3. **Kiến trúc chọn**, dùng hình 02, kèm bảng D1–D9.
4. **Cơ chế chống trùng và chống mất**, dùng hình 03 và 04.
5. **Tự phục hồi**, dùng hình 05.
6. **Thực nghiệm**: bảng kết quả TC03–TC10 với số liệu thật, cùng các phép đối chứng (không dedup, không agent dự phòng).
7. **Giới hạn và hướng mở rộng** (mục 2, 3 ở trên).
