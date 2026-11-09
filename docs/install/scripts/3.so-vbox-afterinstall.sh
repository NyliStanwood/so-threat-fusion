#!/usr/bin/env bash
# After the Security Onion install and setup wizard: port-forwards, then clean snapshot.
#   bash 3.so-vbox-afterinstall.sh             → Step 5: web UI + SSH port-forwards (safe to re-run)
#   bash 3.so-vbox-afterinstall.sh snapshot    → Step 6: power off, eject ISO, snapshot, start again
# Run the snapshot stage only once 'sudo so-status' inside the VM is healthy: it is the lab's reset point.
# If the wizard showed another management IP:  SO_IP=10.0.2.x bash 3.so-vbox-afterinstall.sh
# Run on bigtwin02. Guide: docs/install/SO-plan-for-upm-server-VirtualBox.md (Steps 5-6)
set -euo pipefail

# --- Settings ---------------------------------------------------------------
VM_NAME="so-standalone"
NATNET="so-net"
SO_IP="${SO_IP:-10.0.2.4}"    # management IP shown at the end of the SO setup wizard
SNAPSHOT="clean-install"
SHUTDOWN_TIMEOUT=600           # seconds to wait for a clean shutdown

is_running() { VBoxManage list runningvms | grep -q "^\"$VM_NAME\" "; }

# (Re)create a port-forward. Always delete first: 'natnetwork list' on VirtualBox 6.1
# doesn't show the rules, so an existing one (e.g. old IP) can't be detected
forward() {
  local name="$1" host_port="$2" guest_port="$3"
  VBoxManage natnetwork modify --netname "$NATNET" --port-forward-4 delete "$name" 2>/dev/null || true
  VBoxManage natnetwork modify --netname "$NATNET" --port-forward-4 "$name:tcp:[127.0.0.1]:$host_port:[$SO_IP]:$guest_port"
}

# --- Step 5: port-forwards --------------------------------------------------
setup_forwards() {
  forward so-web 8443 443
  forward so-ssh 2222 22
  sleep 1
  ss -tln | grep -E ':(8443|2222) ' || echo "WARNING: ports 8443/2222 are not listening yet"

  cat <<EOF

Port-forwards point to $SO_IP. From the laptop (UPM VPN on):
  Web UI:     ssh -J marylin@b5g-bigtwin02.dit.upm.es -p 2222 -D 1080 onionsec@127.0.0.1
              Firefox: manual proxy, SOCKS v5 localhost:1080, Proxy DNS on
              then browse to https://$SO_IP
  SSH to SO:  ssh -J marylin@b5g-bigtwin02.dit.upm.es -p 2222 onionsec@127.0.0.1

Inside SO, check the services:  sudo so-status
When they are healthy, run:     bash $0 snapshot
EOF
}

# --- Step 6: eject ISO + snapshot of the powered-off VM -----------------------
take_snapshot() {
  if VBoxManage showvminfo "$VM_NAME" --machinereadable | grep -q "^SnapshotName[-0-9]*=\"$SNAPSHOT\"$"; then
    echo "Snapshot '$SNAPSHOT' already exists, nothing to do:"
    VBoxManage snapshot "$VM_NAME" list
    exit 0
  fi

  read -rp "Did 'sudo so-status' show all services OK? This powers off the VM. [y/N] " answer
  [ "$answer" = "y" ] || { echo "Cancelled."; exit 1; }

  if is_running; then
    echo "Shutting down cleanly (up to $SHUTDOWN_TIMEOUT s)..."
    VBoxManage controlvm "$VM_NAME" acpipowerbutton
    waited=0
    while is_running; do
      if [ "$waited" -ge "$SHUTDOWN_TIMEOUT" ]; then
        echo "ERROR: VM still running after $SHUTDOWN_TIMEOUT s. No snapshot taken; check the console."
        exit 1
      fi
      sleep 5; waited=$((waited + 5))
    done
  fi

  # Harmless if the ISO was already ejected in Step 4
  VBoxManage storageattach "$VM_NAME" --storagectl IDE --port 1 --device 0 --type dvddrive --medium emptydrive
  VBoxManage snapshot "$VM_NAME" take "$SNAPSHOT" --description "SO 2.4.211 standalone, fresh setup"
  VBoxManage snapshot "$VM_NAME" list
  VBoxManage startvm "$VM_NAME" --type headless
}

case "${1:-}" in
  "")       setup_forwards ;;
  snapshot) take_snapshot ;;
  *)        echo "Usage: bash $0 [snapshot]"; exit 1 ;;
esac
