# 06 — Hướng dẫn triển khai từng bước

## Bước 0. Chuẩn bị máy

| Công cụ | Ghi chú |
|---|---|
| Docker | ≥ 4 CPU, ≥ 8 GB RAM cấp cho Docker Desktop/Engine |
| kind ≥ 0.23 | `go install sigs.k8s.io/kind@latest` hoặc tải binary |
| kubectl ≥ 1.29 | Có sẵn `kubectl kustomize` |
| jq, curl, make | |

```bash
make prereqs
```

Kết quả mong đợi: mọi dòng đều `✔`. Nếu image nào báo `✘`, hãy đổi tag trong `manifests/base/kustomization.yaml` (mục `images:`).

## Bước 1. Tạo cụm

```bash
make cluster
```

Mong đợi: 4 node `Ready`, ba worker có label `lab/zone=zone-a|b|c`.

```
NAME                     STATUS   ROLES           ZONE
vmvl-lab-control-plane   Ready    control-plane
vmvl-lab-worker          Ready    <none>          zone-a
vmvl-lab-worker2         Ready    <none>          zone-b
vmvl-lab-worker3         Ready    <none>          zone-c
```

## Bước 2. Xem trước manifest (tùy chọn)

```bash
make render | less
```

## Bước 3. Triển khai

```bash
make deploy
```

Script apply toàn bộ bằng `kubectl apply -k` rồi **chờ theo thứ tự phụ thuộc**:

| # | Tầng | Vì sao phải trước |
|---|---|---|
| 1 | MinIO + job tạo bucket | initContainer restore của vmstorage/VL cần S3 |
| 2 | vmstorage → vminsert, vmselect | Storage trước, tầng stateless sau |
| 3 | vmagent | Bắt đầu ghi khi đích đã sẵn sàng |
| 4 | vlogs-a, vlogs-b → vlagent | Đích log trước collector |
| 5 | vmauth, Grafana | Tầng đọc |
| 6 | demo (podinfo, load-generator, flow-generator) | Sinh dữ liệu |

Lần đầu mất khoảng 3–6 phút (kéo image). Cuối script in phân bố pod theo node. Hãy kiểm tra **vmstorage-0/1/2 nằm trên 3 node khác nhau**, và vlogs-a, vlogs-b cũng khác node.

## Bước 4. Kiểm tra end-to-end

Đợi khoảng 2 phút để dữ liệu chảy, rồi chạy:

```bash
make verify
```

Kết quả mong đợi (rút gọn):

```
1. Pod                               ✔ mọi pod Running
2. vmagent scrape được target        ✔ mọi target UP
3. Dedup                             samples/5m = 20 (kỳ vọng ~20, KHÔNG phải ~40)  ✔
4. Mỗi vmstorage đều có dữ liệu       vmstorage-0/1/2: rows=...
5. Logs ở CẢ A và B                  ✔ vlogs-a: đủ N dòng...  ✔ vlogs-b: đủ N dòng...
6. Đọc logs qua vmauth               ✔
7. Backup gần nhất                   (sau ~2 phút đầu sẽ có timestamp)
✔ TẤT CẢ KIỂM TRA ĐẠT
```

Nếu bước 3 ra "none" thì chưa đủ dữ liệu 5 phút, đợi thêm rồi chạy lại.

## Bước 5. Mở UI

```bash
make ui
```

| UI | URL | Dùng để |
|---|---|---|
| Grafana | http://localhost:3000 (admin/admin) | Explore → chọn datasource VictoriaMetrics / VictoriaLogs |
| VMUI metrics | http://localhost:8427/select/0/vmui/ | Thử MetricsQL |
| VMUI logs | http://localhost:8427/select/vmui/ | Thử LogsQL (qua vmauth) |
| vlogs-a / b trực tiếp | :19428 / :29428 `/select/vmui/` | So sánh hai bản |
| MinIO | http://localhost:9001 | Xem bucket backup |

Gợi ý query đầu tiên:

```
# MetricsQL
sum by (pod) (rate(http_requests_total{namespace="demo"}[1m]))
# LogsQL
kubernetes.container_name:=flow-generator | stats by (src, dst, port) count() as hits
```

## Bước 6. Backup thử

```bash
make backup-now
make list-backups
```

Mong đợi: mỗi `vmstorage-N/latest` có file; mỗi `vlogs-X-0/` có thư mục ngày hôm nay (UTC).

## Bước 7. Chạy test case

```bash
make tc03        # từng case
make test-all    # tất cả, khoảng 30 phút
```

Xem chi tiết kỳ vọng trong [08-test-cases](08-test-cases.md).

## Bước 8. Dọn dẹp

```bash
make down        # xóa stack, giữ cụm
make destroy     # xóa cụm kind
```

## Triển khai bằng ArgoCD (tùy chọn)

Repo là kustomize thuần, nên tạo Application trỏ thẳng vào `manifests/base`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: vm-vl-ha-lab, namespace: argocd}
spec:
  project: default
  source:
    repoURL: https://github.com/<you>/vm-vl-ha-lab.git
    targetRevision: main
    path: manifests/base
  destination: {server: https://kubernetes.default.svc, namespace: observability}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true]
```

Lưu ý: test chaos dùng `kubectl scale`. Khi bật `selfHeal`, ArgoCD sẽ scale lại ngay. Hãy tắt selfHeal trước khi chạy TC03, TC04, TC06, TC09.
