#!/usr/bin/env bash
# 建立 Ubuntu-array30-install 測試 VM（Cloud Image + 全自動）
# 踩坑修正紀錄：見腳本底部 CHANGELOG
set -euo pipefail

# === 設定 ===
VM_NAME="ubuntu-array30-install"
VM_USER="array30"
VM_PASS="@1234567"
VM_RAM=4096
VM_CPUS=2
VM_DISK_SIZE=25G
DISK_PATH="/home/deck/VMs/${VM_NAME}.qcow2"
CLOUD_IMG_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
CLOUD_IMG_CACHE="/home/deck/Downloads/ubuntu-24.04-server-cloudimg-amd64.img"
USERDATA_PATH="/tmp/${VM_NAME}-user-data.yaml"
SSH_PUBKEY_FILE="$HOME/.ssh/id_ed25519.pub"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=30 -o LogLevel=ERROR"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# === 全域變數 ===
VM_IP=""

# === 工具函式 ===

# 從 DHCP leases 查 VM 最新 IP（用 MAC 比對）
refresh_vm_ip() {
    local mac
    mac=$(sudo virsh domiflist "$VM_NAME" 2>/dev/null | awk '/default/{print $NF}' || true)
    if [[ -n "$mac" ]]; then
        local new_ip
        # 方法1: ARP neighbor table（即時，反映 VM 目前實際 IP，不受舊 DHCP 租約干擾）
        new_ip=$(ip neigh show 2>/dev/null \
            | grep -i "$mac" \
            | grep -v 'FAILED\|INCOMPLETE' \
            | awk '{print $1}' | head -1 || true)
        # 方法2: DHCP leases fallback（取最新租約，以到期時間排序）
        if [[ -z "$new_ip" ]]; then
            new_ip=$(sudo virsh net-dhcp-leases default 2>/dev/null \
                | grep -i "$mac" \
                | sort -k1,2 \
                | awk '{print $5}' | cut -d/ -f1 | tail -1 || true)
        fi
        if [[ -n "$new_ip" && "$new_ip" != "$VM_IP" ]]; then
            [[ -n "$VM_IP" ]] && echo "  IP 變更: $VM_IP → $new_ip"
            VM_IP="$new_ip"
        fi
    fi
}

# 嘗試 SSH 連線（自動刷新 IP）
try_ssh() {
    refresh_vm_ip
    if [[ -n "$VM_IP" ]]; then
        ssh $SSH_OPTS "$VM_USER@$VM_IP" "$@" 2>/dev/null
        return $?
    fi
    return 1
}

# 等待 SSH 就緒（含自動重啟關機的 VM、自動重新查 IP）
wait_for_ssh() {
    local max_wait=$1
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        # 偵測 VM 狀態
        local vm_state
        vm_state=$(sudo virsh domstate "$VM_NAME" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

        # VM 關機 → 自動重啟
        if [[ "$vm_state" == "shutoff" || "$vm_state" == "關機" ]]; then
            echo "  [${elapsed}s] VM 已關機，自動重新啟動…"
            sudo virsh start "$VM_NAME" &>/dev/null || true
            VM_IP=""  # 重啟後 IP 可能改變
            sleep 5
            elapsed=$((elapsed + 5))
            continue
        fi

        # 刷新 IP + 嘗試 SSH
        refresh_vm_ip
        if [[ -n "$VM_IP" ]]; then
            if ssh $SSH_OPTS "$VM_USER@$VM_IP" "echo ok" &>/dev/null; then
                echo "  [${elapsed}s] SSH 連線成功（$VM_IP）"
                return 0
            fi
        fi

        sleep 5
        elapsed=$((elapsed + 5))
        # 每 10 秒顯示等待狀態
        if (( elapsed % 10 == 0 )); then
            echo "  [${elapsed}s] 等待中… VM:${vm_state} IP:${VM_IP:-尚未取得}"
        fi
    done

    echo "  [${elapsed}s] 等待逾時"
    return 1
}

# === 快照工具函式 ===

SNAP_A="snap-phase-a"  # 基礎 Ubuntu（Phase A 完成後）
SNAP_B="snap-phase-b"  # Ubuntu + 桌面（Phase B 完成後）

ask_yn() {
    local prompt="$1"
    local ans
    read -rp "$prompt (y/N) " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

snapshot_exists() {
    local snap="$1"
    sudo virsh snapshot-info "$VM_NAME" "$snap" &>/dev/null
}

vm_shutdown_wait() {
    echo "  關機中…"
    sudo virsh shutdown "$VM_NAME" &>/dev/null || true
    local i=0
    while [[ $i -lt 60 ]]; do
        local state
        state=$(sudo virsh domstate "$VM_NAME" 2>/dev/null | tr -d '[:space:]')
        [[ "$state" == "shutoff" || "$state" == "關機" ]] && return 0
        sleep 3; i=$((i + 3))
    done
    echo "  警告：關機逾時，強制關閉"
    sudo virsh destroy "$VM_NAME" &>/dev/null || true
    sleep 2
}

create_snapshot() {
    local snap="$1" desc="$2"
    echo "  建立快照「$snap」…"
    vm_shutdown_wait
    sudo virsh snapshot-create-as "$VM_NAME" "$snap" "$desc" --atomic
    echo "  快照建立完成：$snap"
    echo "  重新啟動 VM…"
    sudo virsh start "$VM_NAME" &>/dev/null
    wait_for_ssh 120
}

restore_snapshot() {
    local snap="$1"
    echo "  還原快照「$snap」…"
    sudo virsh snapshot-revert "$VM_NAME" "$snap"
    echo "  啟動 VM…"
    sudo virsh start "$VM_NAME" &>/dev/null || true
    VM_IP=""
    wait_for_ssh 120
}

# === 前置檢查 ===

# 確保 SSH key 存在
if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
    echo "產生 SSH 金鑰…"
    ssh-keygen -t ed25519 -f "${SSH_PUBKEY_FILE%.pub}" -N "" -q
fi
SSH_KEY=$(cat "$SSH_PUBKEY_FILE")

# 快照感知啟動：偵測現有快照，決定從哪個 Phase 開始
START_FROM_PHASE="A"

if snapshot_exists "$SNAP_B"; then
    echo ""
    echo "偵測到快照：$SNAP_B（Ubuntu + 桌面）"
    if ask_yn "從此快照還原，直接跑 Phase C（測試 array30-install）？"; then
        restore_snapshot "$SNAP_B"
        START_FROM_PHASE="C"
    else
        echo "略過快照，繼續下一個選項…"
    fi
fi

if [[ "$START_FROM_PHASE" != "C" ]] && snapshot_exists "$SNAP_A"; then
    echo ""
    echo "偵測到快照：$SNAP_A（基礎 Ubuntu）"
    if ask_yn "從此快照還原，直接跑 Phase B+C？"; then
        restore_snapshot "$SNAP_A"
        START_FROM_PHASE="B"
    fi
fi

# =========================================================
# Phase A: 建立 VM
# =========================================================

if [[ "$START_FROM_PHASE" == "A" ]]; then

    # 檢查 VM 或 disk 殘留，確認是否重建
    VM_EXISTS=false
    sudo virsh dominfo "$VM_NAME" &>/dev/null && VM_EXISTS=true
    [[ -f "$DISK_PATH" ]] && VM_EXISTS=true

    if [[ "$VM_EXISTS" == true ]]; then
        echo ""
        echo "偵測到 VM「$VM_NAME」殘留（無可用快照）。"
        if ! ask_yn "要刪除後從頭重建？"; then
            echo "取消。"
            exit 0
        fi
    fi

echo "=== Phase A: 建立 VM ==="

echo "[A1] 清理殘留…"
virsh --connect qemu:///session destroy "$VM_NAME" 2>/dev/null || true
virsh --connect qemu:///session undefine "$VM_NAME" --nvram 2>/dev/null || true
sudo virsh destroy "$VM_NAME" 2>/dev/null || true
sudo virsh undefine "$VM_NAME" --nvram 2>/dev/null || true
rm -f "$DISK_PATH"
sudo rm -f "/var/lib/libvirt/qemu/nvram/${VM_NAME}_VARS.fd"

echo "[A2] 確保 libvirtd + default 網路…"
sudo systemctl start libvirtd
sudo virsh net-start default 2>/dev/null || true

if [[ -f "$CLOUD_IMG_CACHE" ]]; then
    echo "[A3] Cloud Image 已快取：$CLOUD_IMG_CACHE"
else
    echo "[A3] 下載 Cloud Image…"
    wget -c -O "$CLOUD_IMG_CACHE" "$CLOUD_IMG_URL"
fi

echo "[A4] 建立 VM 磁碟（${VM_DISK_SIZE}）…"
mkdir -p /home/deck/VMs
cp "$CLOUD_IMG_CACHE" "$DISK_PATH"
qemu-img resize "$DISK_PATH" "$VM_DISK_SIZE"

echo "[A5] 產生 cloud-init user-data…"
cat > "$USERDATA_PATH" << EOF
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true

users:
  - name: ${VM_USER}
    plain_text_passwd: "${VM_PASS}"
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${SSH_KEY}

locale: en_US.UTF-8

packages:
  - openssh-server

write_files:
  - path: /etc/netplan/01-netcfg.yaml
    permissions: '0600'
    content: |
      network:
        version: 2
        ethernets:
          enp1s0:
            dhcp4: true

runcmd:
  - netplan apply
  - systemctl enable ssh --now
  - ufw disable
  - touch /var/lib/cloud/instance/boot-finished-marker

EOF

echo "[A6] 建立 VM: $VM_NAME"
echo "  磁碟: $DISK_PATH (${VM_DISK_SIZE})"
echo "  記憶體: $((VM_RAM))MB / CPU: ${VM_CPUS} 核"
echo "  開機模式: Cloud Image (UEFI, no Secure Boot)"
echo ""

sudo virt-install \
    --connect qemu:///system \
    --name "$VM_NAME" \
    --ram "$VM_RAM" --vcpus "$VM_CPUS" \
    --disk "path=$DISK_PATH,format=qcow2" \
    --os-variant ubuntu24.04 \
    --network network=default \
    --graphics spice \
    --video qxl \
    --boot loader=/usr/share/edk2/x64/OVMF_CODE.4m.fd,loader.readonly=yes,loader.type=pflash,loader.secure=no,nvram.template=/usr/share/edk2/x64/OVMF_VARS.4m.fd,hd \
    --features smm.state=off \
    --cloud-init "user-data=$USERDATA_PATH" \
    --noautoconsole

echo "[A7] 等待 VM 就緒…"
if ! wait_for_ssh 300; then
    echo "  等待 5 分鐘後 SSH 仍未就緒"
    read -rp "  要繼續等待嗎？(y/N) " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        if ! wait_for_ssh 300; then
            echo "錯誤：仍無法連線，中止。"
            exit 1
        fi
    else
        exit 1
    fi
fi

echo ""
echo "=== Phase A 完成 ==="
echo "  VM: $VM_NAME / IP: $VM_IP / SSH: ssh $VM_USER@$VM_IP"
echo ""

if ask_yn "要建立還原點 1（基礎 Ubuntu，$SNAP_A）？"; then
    create_snapshot "$SNAP_A" "Base Ubuntu 24.04 (post cloud-init)"
fi

fi  # end: if [[ "$START_FROM_PHASE" == "A" ]]

# =========================================================
# Phase B: 安裝桌面環境
# =========================================================

if [[ "$START_FROM_PHASE" != "C" ]]; then

echo "=== Phase B: 安裝桌面環境 ==="

echo "[B1] 等待 cloud-init 完成…"
B1_WAIT=0
while [[ $B1_WAIT -lt 300 ]]; do
    if try_ssh "test -f /var/lib/cloud/instance/boot-finished-marker"; then
        echo "  [${B1_WAIT}s] cloud-init 已完成"
        break
    fi
    sleep 5
    B1_WAIT=$((B1_WAIT + 5))
    (( B1_WAIT % 15 == 0 )) && echo "  [${B1_WAIT}s] 等待 cloud-init…"
done

echo "[B2] 等待 apt lock 釋放…"
for i in $(seq 1 30); do
    if try_ssh "! fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend 2>/dev/null"; then
        break
    fi
    sleep 5
done

echo "[B3] apt update…"
try_ssh "sudo apt-get update -qq" 2>&1 | tail -3 || true

echo "[B4] install ubuntu-desktop-minimal（約 10-15 分鐘）…"
set +e
ssh $SSH_OPTS "$VM_USER@$VM_IP" \
    "sudo NEEDRESTART_SUSPEND=1 DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-desktop-minimal" 2>&1 \
    | while IFS= read -r line; do
        case "$line" in
            Get:*|Unpacking*|Setting\ up*|Fetched*|Processing*)
                printf "\r\033[K  %s" "${line:0:100}"
                ;;
        esac
    done
B4_EXIT=${PIPESTATUS[0]}
set -e
echo ""

# SSH 斷線或失敗 → 重新等待連線再繼續
if [[ $B4_EXIT -ne 0 ]]; then
    if [[ $B4_EXIT -eq 255 ]]; then
        echo "  SSH 斷線（安裝可能已完成），重新等待連線…"
    else
        echo "  警告：exit code $B4_EXIT，嘗試繼續…"
    fi
    VM_IP=""
    # 等待 NetworkManager 接管網路後穩定（桌面安裝後網路介面重啟需時）
    echo "  等待 60 秒讓網路穩定…"
    sleep 60
    # 明確重查 VM IP（VM 可能重開機，IP 可能改變）
    echo "  重新查詢 VM IP…"
    for _i in $(seq 1 12); do
        refresh_vm_ip
        if [[ -n "$VM_IP" ]]; then
            echo "  VM IP: $VM_IP"
            break
        fi
        echo "  [${_i}] 等待 DHCP 租約…"
        sleep 5
    done
    if ! wait_for_ssh 360; then
        echo "錯誤：桌面安裝後無法重新連線"
        exit 1
    fi
fi

# 驗證安裝結果
if try_ssh "dpkg -l ubuntu-desktop-minimal 2>/dev/null | grep -q '^ii'"; then
    echo "  桌面環境安裝確認成功"
else
    echo "  警告：ubuntu-desktop-minimal 未正確安裝"
fi

echo "[B5] 確保 SSH 永久啟用…"
try_ssh "sudo systemctl enable ssh; sudo ufw disable" || true

echo "[B6] 重開機…"
try_ssh "sudo reboot" || true

echo "[B7] 等待重開機完成…"
VM_IP=""
sleep 20
if ! wait_for_ssh 360; then
    echo "錯誤：重開機後無法連線"
    exit 1
fi

echo ""
echo "=== Phase B 完成 ==="
echo ""

if ask_yn "要建立還原點 2（Ubuntu + 桌面，$SNAP_B）？"; then
    create_snapshot "$SNAP_B" "Ubuntu 24.04 + GNOME Desktop (pre-array30)"
fi

fi  # end: if [[ "$START_FROM_PHASE" != "C" ]]

# =========================================================
# Phase C: 測試 array30-install.sh
# =========================================================

echo "=== Phase C: 測試 array30-install.sh ==="

echo "[C1] 複製 array30-install.sh 到 VM…"
scp $SSH_OPTS "$SCRIPT_DIR/array30-install.sh" "$VM_USER@$VM_IP:~/"

echo "[C2] 執行 array30-install.sh install…"
echo "---------- 安裝輸出 ----------"

set +e
ssh $SSH_OPTS "$VM_USER@$VM_IP" "bash ~/array30-install.sh install" 2>&1 | tee /tmp/array30-install-result.log
INSTALL_EXIT=${PIPESTATUS[0]}
set -e

echo "---------- 安裝結束 ----------"
echo ""

if [[ $INSTALL_EXIT -eq 0 ]]; then
    echo "[C3] 執行 array30-install.sh diagnose…"
    echo "---------- 診斷輸出 ----------"
    ssh $SSH_OPTS "$VM_USER@$VM_IP" "bash ~/array30-install.sh diagnose" 2>&1 | tee /tmp/array30-diagnose-result.log
    echo "---------- 診斷結束 ----------"
else
    echo "[C3] 安裝失敗（exit code: $INSTALL_EXIT），跳過診斷"
    echo "  安裝 log 已存到 /tmp/array30-install-result.log"
fi

echo "[C4] 重新開機，讓 fcitx5 完整載入…"
try_ssh "sudo reboot" || true
VM_IP=""
sleep 20
if ! wait_for_ssh 300; then
    echo "  警告：重開機後無法重新連線，但安裝已完成"
fi

echo ""
echo "========================================="
echo " 全部完成！"
echo "========================================="
echo ""
echo "  VM:   $VM_NAME"
echo "  IP:   $VM_IP"
echo "  SSH:  ssh $VM_USER@$VM_IP （免密碼）"
echo "  安裝結果: $([ $INSTALL_EXIT -eq 0 ] && echo '成功' || echo '失敗')"
echo ""
echo "  下一步：開啟 Virt-Manager 登入桌面，手動測試行列30輸入"
echo "  帳號：$VM_USER / $VM_PASS"
echo ""

rm -f "$USERDATA_PATH"

# =========================================================
# CHANGELOG — 踩坑修正紀錄
# =========================================================
# #1  virt-install 沒 sudo → qemu:///session 找不到 default 網路
#     → 加 sudo + --connect qemu:///system
# #2  --boot uefi 自動選 secboot → 擋 CDROM 開機
#     → Cloud Image 不需 CDROM，用非 secboot OVMF
# #3  改 XML 關 secboot → firmware/NVRAM mismatch
#     → 一開始就指定正確 firmware
# #4  --video virtio → Ubuntu 桌面黑畫面
#     → 改用 --video qxl
# #5  Cloud Image 用 BIOS (--boot hd) → 開不了
#     → Cloud Image 是 GPT+EFI，必須用 UEFI
# #6  cloud-init power_state:reboot → on_reboot=destroy → VM 關機
#     → 不加 power_state:reboot，腳本偵測關機後自動 virsh start
# #7  set -euo pipefail → 等待循環中 pipeline 失敗中斷腳本
#     → 等待函式用 || true 保護，Phase C 用 set +e
# #8  重開機後網路斷線（cloud-init 預設 netplan 不含 DHCP）
#     → cloud-init write_files 寫入永久 netplan (enp1s0 dhcp4)
# #9  apt -qq + 導到 log → 無進度 + SSH 斷線
#     → 即時顯示進度行 + ServerAliveInterval=30
# #10 IP 重開機後改變
#     → refresh_vm_ip() 每次 SSH 前自動重查 DHCP leases
# #11 SSH 免密碼
#     → 自動偵測/產生 SSH key，cloud-init ssh_authorized_keys 注入
# #12 Phase B apt lock 衝突（cloud-init 還在跑 apt）
#     → Phase B 開始前先等 cloud-init 完成 + 確認 apt lock 已釋放
# #13 重開機後 VM_IP 仍是舊值
#     → reboot 後 VM_IP="" 強制重查
# #14 桌面安裝後 SSH 被關閉或 UFW 擋住
#     → B5 確保 systemctl enable ssh + ufw disable
# #15 B4 apt install SSH 斷線 (exit 255)
#     → 斷線後清 IP、重新 wait_for_ssh 再繼續
# #16 統一 IP 刷新機制
#     → refresh_vm_ip() + try_ssh() 取代分散的 IP 查詢
