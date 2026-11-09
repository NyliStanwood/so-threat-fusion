#!/usr/bin/env bash
# Create the Security Onion Standalone VM on bigtwin02 with VBoxManage (headless).
# Creates the NAT Network, the VM, its disk, both NICs and the console (VRDE);
# it does NOT start the VM. Edit the variables below, then run:  bash 1.so-vbox-create.sh
# (the VNC console password is asked for, or pass it as VNC_PASSWORD=... bash 1.so-vbox-create.sh)
# Guide: docs/install/SO-plan-for-upm-server-VirtualBox.md
set -euo pipefail

# --- Settings ---------------------------------------------------------------
VM_NAME="so-standalone"
OS_TYPE="Oracle_64"            # list options: VBoxManage list ostypes | grep -i oracle
CPUS=16
MEMORY_MB=65536                # 64 GB
DISK_GB=400
BASE_FOLDER="$HOME/VirtualBox VMs"
ISO="$HOME/isos/securityonion-2.4.211-20260407.iso"   # no sudo for /mnt/hdd-group1

NATNET="so-net"                # management + internet (same as the laptop setup)
NATNET_CIDR="10.0.2.0/24"
INTNET="internal-net"          # monitor / sniffing, isolated

VRDE_PORT=5901                 # installer console (VNC), bound to 127.0.0.1 only
VNC_PASSWORD="${VNC_PASSWORD:-}"   # console password; asked for below if not set

# --- Checks -----------------------------------------------------------------
command -v VBoxManage >/dev/null || { echo "VBoxManage not found: is VirtualBox installed?"; exit 1; }
[ -f "$ISO" ] || { echo "ISO not found: $ISO"; exit 1; }
if VBoxManage showvminfo "$VM_NAME" >/dev/null 2>&1; then
  echo "VM '$VM_NAME' already exists. Remove it first with:"
  echo "  VBoxManage unregistervm $VM_NAME --delete"
  exit 1
fi
echo "VirtualBox $(VBoxManage --version)"

# --- 1. NAT Network (management) --------------------------------------------
if VBoxManage natnetwork list | grep -qw "$NATNET"; then
  echo "NAT Network '$NATNET' already exists, reusing it"
else
  VBoxManage natnetwork add --netname "$NATNET" --network "$NATNET_CIDR" --enable --dhcp on
fi
VBoxManage natnetwork start --netname "$NATNET" 2>/dev/null || true   # fails harmlessly if running

# --- 2. VM ------------------------------------------------------------------
VBoxManage createvm --name "$VM_NAME" --ostype "$OS_TYPE" --basefolder "$BASE_FOLDER" --register

VBoxManage modifyvm "$VM_NAME" \
  --cpus "$CPUS" --memory "$MEMORY_MB" \
  --ioapic on --pae on --rtcuseutc on \
  --paravirtprovider kvm \
  --graphicscontroller vmsvga --vram 16 \
  --boot1 dvd --boot2 disk --boot3 none --boot4 none

# --- 3. Network adapters ----------------------------------------------------
# NIC 1: management (SO setup → management interface, DHCP)
# NIC 2: monitor (SO setup → monitor interface; promiscuous so Zeek/Suricata see all traffic)
VBoxManage modifyvm "$VM_NAME" \
  --nic1 natnetwork --nat-network1 "$NATNET" --nictype1 virtio --nicpromisc1 deny     --cableconnected1 on \
  --nic2 intnet     --intnet2 "$INTNET"      --nictype2 virtio --nicpromisc2 allow-all --cableconnected2 on

# --- 4. Disk (SATA) + ISO (IDE) ---------------------------------------------
# Disk on SATA port 0 (guest: sda). DVD on IDE, as on the laptop: this layout
# is the one that installed successfully on bigtwin02 (2026-11-07).
DISK="$BASE_FOLDER/$VM_NAME/$VM_NAME.vdi"
VBoxManage createmedium disk --filename "$DISK" --size $((DISK_GB * 1024)) --format VDI   # dynamically allocated
VBoxManage storagectl "$VM_NAME" --name SATA --add sata --controller IntelAhci --portcount 1
VBoxManage storageattach "$VM_NAME" --storagectl SATA --port 0 --device 0 --type hdd      --medium "$DISK" --nonrotational on
VBoxManage storagectl "$VM_NAME" --name IDE --add ide --controller PIIX4
VBoxManage storageattach "$VM_NAME" --storagectl IDE  --port 1 --device 0 --type dvddrive --medium "$ISO"

# --- 4b. Serial port → log file (kernel/installer messages for debugging) -----
# Only filled when the kernel is booted with console=ttyS0 (see 2.so-vbox-boot-installer.sh).
VBoxManage modifyvm "$VM_NAME" --uart1 0x3F8 4 --uartmode1 file "$HOME/so-serial.log"

# --- 5. Console (VRDE via the VNC Extension Pack) ---------------------------
# bigtwin02 has the open-source "VNC" pack (not Oracle's RDP pack): use a VNC viewer.
# RDP variant of this script: so-vbox-create(USES ORACLE RDP EXTTENSION PACK).sh
if VBoxManage list extpacks | grep -q "^Pack no.*VNC"; then
  if [ -z "$VNC_PASSWORD" ]; then
    read -rsp "create a VNC console password (8 characters): " VNC_PASSWORD; echo
  fi
  VBoxManage modifyvm "$VM_NAME" --vrde on --vrdeextpack VNC \
    --vrdeaddress 127.0.0.1 --vrdeport "$VRDE_PORT" \
    --vrdeproperty VNCPassword="$VNC_PASSWORD"
  echo "Console: VNC on 127.0.0.1:$VRDE_PORT (reach it through an SSH tunnel)"
else
  echo "WARNING: no VNC Extension Pack, so no console."
  echo "         Use the screenshot/keyboard fallback in the guide (section 7)."
fi

# --- Summary ----------------------------------------------------------------
echo
echo "Created '$VM_NAME':"
VBoxManage showvminfo "$VM_NAME" --machinereadable \
  | grep -E '^(cpus|memory|nic[12]|nat-network1|intnet2|nicpromisc[12]|vrde|vrdeport|vrdeaddress|uartmode1|"SATA-0-0"|"IDE-1-0")='

# Without a disk the SO installer stops with "/tmp/part-include: No such file" (hidden behind the boot splash)
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable | grep -q "^\"SATA-0-0\"=\"$DISK\""; then
  echo "ERROR: the disk is not attached to SATA port 0. Fix this before booting."; exit 1
fi
echo
echo "Boot the installer with:  bash 2.so-vbox-boot-installer.sh"
