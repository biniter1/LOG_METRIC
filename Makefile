SHELL := /bin/bash
.DEFAULT_GOAL := help
NS ?= observability

help: ## Liệt kê lệnh
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------- Dựng lab ----------
prereqs: ## Kiểm tra công cụ, tài nguyên, image
	bash scripts/00-check-prereqs.sh
cluster: ## Tạo cụm kind 1 control-plane + 3 worker
	bash scripts/01-create-cluster.sh
render: ## In toàn bộ manifest đã render (không apply)
	kubectl kustomize manifests/base
deploy: ## Triển khai toàn bộ stack + demo, chờ từng tầng Ready
	bash scripts/02-deploy.sh
verify: ## Kiểm tra end-to-end (TC01)
	bash scripts/03-verify.sh
up: cluster deploy ## cluster + deploy
ui: ## Port-forward Grafana / VMUI / MinIO
	bash scripts/port-forward.sh
status: ## Trạng thái pod theo node
	kubectl -n $(NS) get pods -o wide --sort-by=.spec.nodeName

# ---------- Backup ----------
backup-now: ## Backup ngay toàn bộ vmstorage + VictoriaLogs
	bash scripts/backup/backup-now.sh
list-backups: ## Liệt kê backup trên S3 (MinIO)
	bash scripts/backup/list-backups.sh

# ---------- Test cases ----------
tc02: ## Chứng minh dedup
	bash scripts/chaos/tc02-dedup-proof.sh
tc03: ## Mất 1 vmagent
	bash scripts/chaos/tc03-vmagent-down.sh
tc04: ## Mất toàn bộ vminsert (buffer vmagent)
	bash scripts/chaos/tc04-vminsert-down.sh
tc05: ## Mất 1 vmstorage (RF=2)
	bash scripts/chaos/tc05-vmstorage-down.sh
tc06: ## vmstorage mất PVC -> tự restore từ S3
	bash scripts/chaos/tc06-vmstorage-lose-pvc.sh
tc07: ## VictoriaLogs A down -> failover + buffer
	bash scripts/chaos/tc07-vlogs-a-down.sh
tc08: ## Restart vlagent -> checkpoint
	bash scripts/chaos/tc08-vlagent-restart.sh
tc09: ## VictoriaLogs B mất PVC -> tự restore
	bash scripts/chaos/tc09-vlogs-lose-pvc.sh
tc10: ## Drain node + PDB
	bash scripts/chaos/tc10-node-drain.sh
test-all: ## Chạy toàn bộ test case (~30 phút)
	bash scripts/chaos/run-all.sh

# ---------- Dọn dẹp ----------
down: ## Xóa stack (giữ cụm)
	-kubectl delete -f manifests/demo/demo.yaml
	-kubectl delete -k manifests/base
destroy: ## Xóa hẳn cụm kind
	kind delete cluster --name vmvl-lab

.PHONY: help prereqs cluster render deploy verify up ui status backup-now list-backups \
	tc02 tc03 tc04 tc05 tc06 tc07 tc08 tc09 tc10 test-all down destroy
