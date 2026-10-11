#!/usr/bin/env bash
# Kiểm tra công cụ trên máy + tài nguyên Docker + image có pull được không.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Công cụ =="
for b in docker kind kubectl curl jq; do
  if command -v "$b" >/dev/null; then echo "  ✔ $b"; else echo "  ✘ thiếu $b"; MISSING=1; fi
done
[[ "${MISSING:-0}" == 1 ]] && { echo "Cài các công cụ còn thiếu rồi chạy lại."; exit 1; }

echo "== Tài nguyên Docker (khuyến nghị >= 4 CPU, >= 8 GB RAM) =="
docker info --format '  CPUs={{.NCPU}}  Mem={{.MemTotal}}' || true

echo "== Kiểm tra image tồn tại (docker manifest inspect) =="
imgs=$(kubectl kustomize manifests/base | awk '/image:/ {print $2}' | sort -u)
imgs+=$'\n'"ghcr.io/stefanprodan/podinfo:6.7.1"$'\n'"busybox:1.36"
bad=0
while read -r img; do
  [[ -z "$img" ]] && continue
  if docker manifest inspect "$img" >/dev/null 2>&1; then echo "  ✔ $img"
  else echo "  ✘ $img  (đổi tag trong manifests/base/kustomization.yaml)"; bad=1; fi
done <<< "$imgs"
exit $bad
