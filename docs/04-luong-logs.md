# 04 — Luồng logs: nhân bản ở tầng ingest

![Luồng logs](images/04-logs-replication.png)

## 1. Khác biệt so với metrics

| | Metrics | Logs |
|---|---|---|
| Cách lấy | Scrape (chủ động kéo theo chu kỳ) | Tail file (đọc nối tiếp) |
| HA tầng thu thập | 2 agent cùng scrape | 1 collector/node + checkpoint; file log là bộ đệm |
| Replication | Ở storage (RF=2) | Ở ingest (vlagent gửi đôi) |
| Duplicate có hệ thống | Có, nên cần dedup | Không |

## 2. vlagent làm gì

Cấu hình trong `manifests/base/21-vlagent.yaml`:

```
-kubernetesCollector                         # đọc /var/log/containers, gắn metadata k8s
-tmpDataPath=/var/lib/vlagent                # checkpoint + buffer (hostPath)
-remoteWrite.url=http://vlogs-a:9428/insert/native
-remoteWrite.url=http://vlogs-b:9428/insert/native
-remoteWrite.maxDiskUsagePerURL=1GB          # giới hạn buffer cho MỖI đích
-kubernetesCollector.excludeFilter=kubernetes.pod_name:=%{HOSTNAME}   # bỏ log của chính nó
```

Mỗi dòng log được gắn các field `kubernetes.pod_name`, `kubernetes.pod_namespace`, `kubernetes.container_name`, label của pod, và `output_stream`. Log dạng JSON được tách field tự động. Ví dụ `{"seq":12,"src":"cart","dst":"redis","port":6379}` trở thành các field `seq`, `src`, `dst`, `port`, và query được ngay.

## 3. Hành vi khi có lỗi

| Sự cố | Điều xảy ra |
|---|---|
| `vlogs-b` down | Buffer → B tích lũy trên đĩa node; A vẫn nhận bình thường. B lên lại thì vlagent đẩy bù. |
| `vlogs-b` down lâu hơn mức buffer chứa được | Log **cũ nhất** trong buffer của B bị bỏ (theo docs). B thiếu đoạn đó, A vẫn đủ. Cần cảnh báo trên `vlagent_remotewrite_pending_data_bytes`. |
| vlagent restart | Đọc tiếp từ checkpoint, không gửi lại. |
| vlagent chết lâu | Log vẫn nằm trên node (kubelet giữ tối đa 5 file × 10MB mỗi container theo mặc định). Vượt mức này thì mất. |
| Đọc khi A down | vmauth `first_available` tự chuyển sang B. |

## 4. Vì sao không cần dedup

Bản trùng chỉ có thể sinh ra khi:
- vlagent gửi xong nhưng chết trước khi lưu checkpoint, rồi gửi lại vài dòng khi lên lại (hiếm, số lượng nhỏ).

Trường hợp "hai collector cùng đọc một file" **không tồn tại** trong thiết kế này. Nếu Tier 1 cần chính xác tuyệt đối, hãy tính theo **khóa flow** (`src, dst, port`) hoặc dùng `count_uniq`, không cộng thô số dòng.

## 5. Đo chính xác bằng flow-generator

`demo/flow-generator` in mỗi giây 5 dòng JSON với `seq` tăng dần. Với mỗi instance, chạy:

```
_time:7d kubernetes.pod_name:=<pod> seq:*
| stats count() as rows, count_uniq(seq) as uniq, min(seq) as mn, max(seq) as mx
```

- `rows == uniq` → **không trùng**.
- `uniq == mx - mn + 1` → **không mất** dòng nào.

Hàm `check_flow` trong `scripts/lib.sh` thực hiện đúng phép kiểm tra này và được dùng trong TC07–TC09.

## 6. Tier 1 đọc logs thế nào

```bash
# Các cặp flow trong 1 giờ qua, đếm số lần quan sát
curl -s http://vmauth:8427/select/logsql/query --data-urlencode \
  'query=_time:1h kubernetes.container_name:=flow-generator | stats by (src, dst, port) count() as hits'
```
