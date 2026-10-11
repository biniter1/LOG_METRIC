#!/usr/bin/env bash
# Chạy lần lượt mọi test case và in bảng tổng kết. Mất ~25-30 phút.
cd "$(dirname "$0")" || exit 1
results=()
run() {
  local name=$1 script=$2
  if bash "$script"; then results+=("PASS  $name"); else results+=("FAIL  $name"); fi
  sleep 20
}
run "TC01 health"                 ../03-verify.sh
run "TC02 dedup"                  tc02-dedup-proof.sh
run "TC03 vmagent down"           tc03-vmagent-down.sh
run "TC04 vminsert down"          tc04-vminsert-down.sh
run "TC05 vmstorage down"         tc05-vmstorage-down.sh
run "TC06 vmstorage lose PVC"     tc06-vmstorage-lose-pvc.sh
run "TC07 vlogs-a down"           tc07-vlogs-a-down.sh
run "TC08 vlagent restart"        tc08-vlagent-restart.sh
run "TC09 vlogs-b lose PVC"       tc09-vlogs-lose-pvc.sh
run "TC10 node drain + PDB"       tc10-node-drain.sh
echo; echo "========== KẾT QUẢ =========="
printf '%s\n' "${results[@]}"
