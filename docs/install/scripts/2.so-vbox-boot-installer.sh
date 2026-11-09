#!/usr/bin/env bash
# Boot the Security Onion ISO installer on the headless VM, with readable output.
# Stops the boot menu countdown, opens the boot line (Tab), adds debug options and boots.
#   plymouth.enable=0  → no "dots" splash screen hiding the installer and its errors
#   console=ttyS0      → kernel messages also go to ~/so-serial.log (serial port set by 1.so-vbox-create.sh)
# Run on bigtwin02:  bash 2.so-vbox-boot-installer.sh   then watch TigerVNC (localhost:5901).
# Guide: docs/install/SO-plan-for-upm-server-VirtualBox.md (Step 3)
set -euo pipefail

VM_NAME="so-standalone"
BOOT_OPTS=' console=ttyS0,115200 console=tty0 loglevel=7 plymouth.enable=0'

key() { VBoxManage controlvm "$VM_NAME" keyboardputscancode "$@"; }

# Disk must be attached, or the SO pre-install script fails (no disk → /tmp/part-include missing)
VBoxManage showvminfo "$VM_NAME" --machinereadable | grep -q '^"SATA-0-0"="/' \
  || { echo "ERROR: no disk on SATA port 0 (see guide, Troubleshooting)."; exit 1; }

: > "$HOME/so-serial.log"                      # start with an empty serial log
VBoxManage startvm "$VM_NAME" --type headless

echo "Stopping the boot menu countdown..."
for i in $(seq 1 16); do key e0 48 e0 c8; sleep 0.5; done   # Up arrow: stops "Automatic boot in 10 seconds"

echo "Adding boot options:$BOOT_OPTS"
key 0f 8f                                       # Tab: edit the boot line of the default entry
sleep 1
VBoxManage controlvm "$VM_NAME" keyboardputstring "$BOOT_OPTS"
VBoxManage controlvm "$VM_NAME" screenshotpng "$HOME/so-bootline.png"   # proof of what was typed
key 1c 9c                                       # Enter: boot

cat <<EOF

Booting. In about 30-60 s TigerVNC shows the SO warning: type 'yes'.
- Only dots or a black screen?  Switch to the installer console (Ctrl+Alt+F1):
    VBoxManage controlvm $VM_NAME keyboardputscancode 1d 38 3b bb b8 9d
- Kernel messages:              tail -f ~/so-serial.log
- Boot line that was used:      ~/so-bootline.png
BEFORE the reboot at the end of the install, eject the ISO:
    VBoxManage storageattach $VM_NAME --storagectl IDE --port 1 --device 0 --type dvddrive --medium emptydrive
EOF
