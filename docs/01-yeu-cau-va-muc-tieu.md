# 01 — Yêu cầu và mục tiêu

## 1. Bối cảnh

Tier 1 của KLTN suy luận dependency giữa các service từ **bằng chứng runtime**: flow traffic (dạng metrics và logs) thu được trong cluster. Kết quả cuối cùng là Kubernetes NetworkPolicy.

Điều này đặt ra một ràng buộc khác thường cho tầng lưu trữ:

> **Thiếu dữ liệu nguy hiểm hơn chậm dữ liệu.**
> Nếu một khoảng thời gian bị mất, các cạnh `A → B` chỉ xuất hiện trong khoảng đó sẽ biến mất khỏi đồ thị dependency. NetworkPolicy sinh ra sẽ **chặn traffic hợp lệ**, gây sự cố ở production.

Vì vậy lab này không chỉ cần "chạy được", mà phải **chứng minh bằng số liệu** rằng dữ liệu không mất khi có lỗi.

## 2. Yêu cầu chức năng

| ID | Yêu cầu |
|---|---|
| F1 | Thu thập metrics từ mọi pod có annotation `prometheus.io/scrape` |
| F2 | Thu thập log stdout/stderr của mọi container, kèm metadata Kubernetes |
| F3 | Một endpoint đọc duy nhất cho cả metrics và logs (Grafana, Tier 1) |
| F4 | Backup định kỳ lên object storage (S3) |
| F5 | Tự động khôi phục khi một instance mất volume |

## 3. Yêu cầu phi chức năng

| ID | Yêu cầu | Cách đạt |
|---|---|---|
| N1 | Mất **bất kỳ 1** thành phần → không mất dữ liệu, không gián đoạn đọc | Mọi tầng ≥ 2 bản; anti-affinity |
| N2 | Failover tầng thu thập = **0 giây** | Active-active, không leader election |
| N3 | Tầng ghi/storage tạm down → không mất dữ liệu | Buffer trên đĩa ở vmagent/vlagent |
| N4 | Không đếm đôi dữ liệu | Dedup (metrics), single-collector-per-file (logs) |
| N5 | Mất đĩa → tự phục hồi, không thao tác tay | initContainer restore từ S3 |
| N6 | Bảo trì node không phá vỡ đảm bảo replication | PodDisruptionBudget |
| N7 | Đơn giản, chạy được trên laptop | kind, manifest thuần + kustomize |

## 4. Tiêu chí thành công (đo được)

| Kịch bản | Tiêu chí |
|---|---|
| Mất 1 vmagent | `count_over_time(up[W])` = W/15 ± 1 → **0 gap** |
| Mất toàn bộ vminsert 2 phút | 0 gap sau khi hồi phục (nhờ buffer) |
| Mất 1 vmstorage | Query `isPartial=false`, kết quả đầy đủ |
| vmstorage mất PVC | Tự restore từ S3, dữ liệu cũ trở lại |
| VictoriaLogs A down 3 phút | Đọc vẫn có (qua B); sau hồi phục A và B **bằng nhau**: `rows = uniq(seq) = max-min+1` |
| Restart vlagent | Không trùng, không mất dòng nào |
| VictoriaLogs B mất PVC | Tự restore; phần thiếu ≤ RPO và vẫn có ở A |
| Drain 2 node liên tiếp | PDB chặn lần drain thứ 2 |

Các tiêu chí này được kiểm tra tự động bởi `scripts/chaos/*` (xem [08-test-cases](08-test-cases.md)).

## 5. Ngoài phạm vi

- HA cho chính MinIO (trong lab là single-node; trên AWS dùng S3 thật, vốn đã có độ bền 11 số 9).
- Multi-region / multi-cluster.
- Xác thực/TLS giữa các thành phần (ghi chú cách bật ở [09](09-troubleshooting.md)).
- Alerting (vmalert) — chỉ ghi chú các metric nên đặt cảnh báo.
