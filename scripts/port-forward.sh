#!/usr/bin/env bash
# Mở các UI để thao tác bằng tay. Ctrl+C để dừng tất cả.
set -euo pipefail
NS="${NS:-observability}"
pids=()
fwd() { kubectl -n "$NS" port-forward "svc/$1" "$2:$3" >/dev/null 2>&1 & pids+=($!); }
trap 'kill "${pids[@]}" 2>/dev/null' EXIT

fwd grafana 3000 3000
fwd vmauth  8427 8427
fwd vlogs-a 19428 9428
fwd vlogs-b 29428 9428
fwd minio   9001 9001

cat <<EOF
Grafana            http://localhost:3000            (admin/admin)
VMUI (metrics)     http://localhost:8427/select/0/vmui/
VMUI (logs, qua vmauth) http://localhost:8427/select/vmui/
vlogs-a trực tiếp  http://localhost:19428/select/vmui/
vlogs-b trực tiếp  http://localhost:29428/select/vmui/
MinIO console      http://localhost:9001            (labadmin/labadmin-secret-123)
Ctrl+C để dừng.
EOF
wait
