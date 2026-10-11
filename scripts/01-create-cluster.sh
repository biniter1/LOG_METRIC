#!/usr/bin/env bash
# Tạo cụm kind 1 control-plane + 3 worker.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=vmvl-lab
if kind get clusters | grep -qx "$NAME"; then
  echo "Cluster $NAME đã tồn tại -> bỏ qua."
else
  kind create cluster --config kind/kind-config.yaml
fi
kubectl cluster-info --context "kind-$NAME"
kubectl get nodes -L lab/zone
