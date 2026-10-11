# 08 — Test cases

Mỗi test case có ba phần: **mục đích**, **cách chạy**, và **kỳ vọng kèm tiêu chí đạt**. Toàn bộ được tự động hóa trong `scripts/chaos/`. Kết quả nên được ghi lại (số liệu thật) để đưa vào báo cáo.

**Hai thước đo dùng xuyên suốt:**
- **Metrics gap**: `min(count_over_time(up{app="podinfo"}[W]))` so với `W/15`. Thiếu nhiều hơn 1 sample nghĩa là có gap.
- **Logs**: `check_flow`, với `rows == count_uniq(seq) == max(seq) - min(seq) + 1`.

| TC | Kịch bản | Lệnh | Thời gian |
|---|---|---|---|
| 01 | Sức khỏe end-to-end | `make verify` | 1 phút |
| 02 | Chứng minh dedup | `make tc02` | 1 phút |
| 03 | Mất 1 vmagent | `make tc03` | 4 phút |
| 04 | Mất toàn bộ vminsert | `make tc04` | 5 phút |
| 05 | Mất 1 vmstorage | `make tc05` | 5 phút |
| 06 | vmstorage mất PVC | `make tc06` | 3 phút |
| 07 | VictoriaLogs A down | `make tc07` | 5 phút |
| 08 | Restart vlagent | `make tc08` | 1 phút |
| 09 | VictoriaLogs B mất PVC | `make tc09` | 3 phút |
| 10 | Drain node + PDB | `make tc10` | 3 phút |

Chạy tất cả: `make test-all`. Cuối cùng script in bảng PASS/FAIL.

> Trước TC06 và TC09, script tự gọi backup ngay để RPO nhỏ nhất. Muốn đo RPO "tự nhiên", hãy bỏ dòng backup trong script.

---

## TC01 — Sức khỏe end-to-end
**Mục đích:** xác nhận baseline trước khi phá.
**Kỳ vọng:** mọi pod Running; mọi target UP; dedup ≈ 20 sample / 5 phút; A và B đều đủ log; vmauth trả cả metrics lẫn logs.

## TC02 — Chứng minh dedup
**Mục đích:** chứng minh 2 vmagent ghi nhưng dữ liệu không bị nhân đôi.
**Kỳ vọng:**
- vminsert nhận khoảng 2 × tốc độ scrape của 1 agent (2 agent đều đang ghi).
- `count_over_time(up[1m|5m|15m])` ≈ 4 / 20 / 60. Nếu gấp đôi thì dedup đang hỏng.

## TC03 — Mất 1 vmagent (2 phút)
**Cách làm:** `scale sts/vmagent --replicas=1`, chờ 120 giây, scale lại 2.
**Kỳ vọng:** **0 gap**. Không có bước failover nào, agent còn lại vẫn đang ghi.
**Đây là test trả lời trực tiếp câu hỏi ban đầu** (active-active so với active-passive). Có thể chạy thêm biến thể: scale về 0 trong 60 giây để thấy gap thật xuất hiện, làm đối chứng.

## TC04 — Mất toàn bộ vminsert (2 phút)
**Cách làm:** `scale deploy/vminsert --replicas=0`, chờ 120 giây, rồi scale lại 2.
**Kỳ vọng:**
- Trong lúc down, `du -sh /buffer` trên vmagent tăng dần.
- Sau khi hồi phục khoảng 60 giây: **0 gap** (buffer đã được đẩy bù).
**Giới hạn:** buffer 1GB. Down quá lâu thì dữ liệu cũ nhất bị bỏ, nên cần cảnh báo.

## TC05 — Mất 1 vmstorage (3 phút)
**Cách làm:** cordon node của vmstorage-1 rồi xóa pod. PVC local-path gắn với node nên pod nằm `Pending`.
**Kỳ vọng:**
- Query trong lúc down: `isPartial=false`, kết quả đủ.
- Ghi vẫn tiếp tục, vminsert chuyển dữ liệu sang 2 node còn lại.
- Sau khi uncordon: 0 gap.

## TC06 — vmstorage mất PVC (self-recovery)
**Cách làm:** backup ngay → scale 3→2 → xóa PVC `storage-vmstorage-2` → scale 2→3.
**Kỳ vọng:**
- Log initContainer có `[vm-restore] restore OK`.
- `vm_rows` của vmstorage-2 > 0 ngay sau khi khởi động.
- Query trong suốt quá trình vẫn đủ (RF=2).
**Ý nghĩa:** chứng minh tự phục hồi không cần thao tác tay, và đưa dữ liệu cũ về lại đủ 2 bản.

## TC07 — VictoriaLogs A down (3 phút)
**Cách làm:** cordon node của vlogs-a-0 rồi xóa pod.
**Kỳ vọng:**
- Query qua vmauth vẫn trả logs (đọc từ B).
- `vlagent_remotewrite_pending_data_bytes` tăng.
- Sau hồi phục khoảng 60 giây: **A và B đều** `rows = uniq = max-min+1`.

## TC08 — Restart vlagent
**Cách làm:** `rollout restart ds/vlagent`.
**Kỳ vọng:** A và B đều không trùng, không mất (nhờ checkpoint trên hostPath).
**Nếu thấy trùng vài dòng:** đó là trường hợp "gửi xong nhưng chưa lưu checkpoint", hành vi at-least-once đã nêu ở [04](04-luong-logs.md). Ghi lại số dòng trùng.

## TC09 — VictoriaLogs B mất PVC (self-recovery) {#tc09}
**Cách làm:** backup ngay → scale B về 0 → xóa PVC `data-vlogs-b-0` → scale lên 1.
**Kỳ vọng:**
- initContainer liệt kê các partition đã restore.
- **A đủ.**
- **B có thể thiếu một ít dòng**, đúng bằng log ghi vào B trong khoảng từ lúc backup tới lúc mất PVC. Script in ra khoảng thời gian này và số dòng dự kiến (5 dòng/giây). Số dòng thiếu thực tế phải ≤ số dự kiến. **Đây là hành vi đúng (RPO)**, không phải lỗi.
- Bù partition các ngày đã qua: `scripts/backup/vl-resync-partition.sh <YYYYMMDD> a b`.

## TC10 — Drain node + PDB
**Cách làm:** drain node chứa vmstorage-0, sau đó thử drain node chứa vmstorage-1.
**Kỳ vọng:** lần drain thứ hai **bị chặn**, vì PDB `maxUnavailable=1` đã dùng hết. vmstorage-1 vẫn Running.

---

## Mẫu ghi kết quả (đưa vào báo cáo)

| TC | Thời gian down | Dữ liệu mất (metrics: sample, logs: dòng) | Thời gian phục hồi | Kết quả |
|---|---|---|---|---|
| 03 | 120s | 0 | 0s (không cần failover) | PASS |
| 04 | 120s | | | |
| 05 | 180s | | | |
| 06 | — | | RTO = ...s | |
| 07 | 180s | A: , B: | | |
| 08 | — | trùng: , mất: | | |
| 09 | — | B thiếu: (dự kiến ≤ ...) | RTO = ...s | |
| 10 | — | — | — | |

## Đối chứng nên chạy thêm (để báo cáo thuyết phục)

1. **Không dedup:** bỏ `-dedup.minScrapeInterval` ở vmselect và vmstorage, chạy lại TC02. Số sample gần gấp đôi.
2. **Gắn label replica:** thêm `external_labels: {replica: X}` khác nhau cho 2 agent. Series bị nhân đôi, chứng minh ràng buộc ở D1.
3. **Không có agent dự phòng:** `kubectl -n observability scale sts/vmagent --replicas=0`, chờ 60 giây, scale lại 2, rồi đo `metric_gap_check 120`. Gap khoảng 4 sample xuất hiện. Đây là thứ một hệ chỉ có 1 agent (hoặc active-passive đang failover) sẽ gặp, làm đối chứng cho active-active.
