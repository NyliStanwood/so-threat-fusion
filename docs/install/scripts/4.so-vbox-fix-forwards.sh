#!/usr/bin/env bash
# Detect the SO VM's current IP and dashboard port, repoint the port-forwards and test them.
# The IP comes from VirtualBox's DHCP lease for the VM's NIC 1 (no Guest Additions needed).
# If the forwards don't answer, restarts the NAT Network, clearing a stuck DHCP process.
# Run on bigtwin02:  bash 4.so-vbox-fix-forwards.sh
# To skip detection:  SO_IP=10.0.2.x bash 4.so-vbox-fix-forwards.sh
# Guide: docs/install/SO-install-[upm-server-virtualbox].md
set -euo pipefail

# --- Settings ---------------------------------------------------------------
VM_NAME="so-standalone"
NATNET="so-net"
WEB_HOST_PORT=8443
SSH_HOST_PORT=2222
WEB_GUEST_PORTS="${WEB_GUEST_PORTS:-443 8443}"   # dashboard ports to try, in order
LEASES="$HOME/.config/VirtualBox/$NATNET-Dhcpd.leases"

# --- Checks -----------------------------------------------------------------
VBoxManage list runningvms | grep -q "^\"$VM_NAME\" " \
  || { echo "ERROR: VM '$VM_NAME' is not running. Start it with:"; echo "  VBoxManage startvm $VM_NAME --type headless"; exit 1; }

# --- 1. Find the VM's IP ------------------------------------------------------
mac=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | sed -n 's/^macaddress1="\(.*\)"/\1/p' \
  | tr 'A-F' 'a-f' | sed 's/../&:/g; s/:$//')

detect_ip() {
  local ip
  ip=$(VBoxManage dhcpserver findlease --network="$NATNET" --mac-address="$mac" 2>/dev/null \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
  if [ -z "$ip" ] && [ -f "$LEASES" ]; then
    ip=$(tr '\n' ' ' < "$LEASES" | grep -oiE "mac=\"$mac\"[^>]*>[[:space:]]*<Address value=\"[0-9.]+" \
      | tail -1 | grep -oE '[0-9.]+$' || true)
  fi
  echo "$ip"
}

SO_IP="${SO_IP:-$(detect_ip)}"
if [ -z "$SO_IP" ]; then
  echo "ERROR: no DHCP lease found for MAC $mac on '$NATNET'."
  echo "Run 'ip -br a' in the VM console, then:  SO_IP=<ip> bash $0"
  exit 1
fi
echo "VM IP: $SO_IP (MAC $mac)"

# --- 2. Forwards and tests ----------------------------------------------------
# Always delete first: 'natnetwork list' on VirtualBox 6.1 doesn't show the rules
forward() {
  local name="$1" host_port="$2" guest_port="$3"
  VBoxManage natnetwork modify --netname "$NATNET" --port-forward-4 delete "$name" 2>/dev/null || true
  VBoxManage natnetwork modify --netname "$NATNET" --port-forward-4 "$name:tcp:[127.0.0.1]:$host_port:[$SO_IP]:$guest_port"
}

ssh_answers() {
  timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/$SSH_HOST_PORT; head -1 <&3" 2>/dev/null | grep -q '^SSH-'
}

web_answers() {
  local code
  code=$(curl -sk --max-time 5 -o /dev/null -w '%{http_code}' "https://127.0.0.1:$WEB_HOST_PORT/" || true)
  [ -n "$code" ] && [ "$code" != "000" ]
}

retry() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    sleep 2
  done
  return 1
}

web_port=""
apply_forwards() {
  local port
  web_port=""
  forward so-ssh "$SSH_HOST_PORT" 22
  for port in $WEB_GUEST_PORTS; do
    forward so-web "$WEB_HOST_PORT" "$port"
    if retry web_answers; then
      web_port="$port"
      break
    fi
  done
  [ -n "$web_port" ] && retry ssh_answers
}

# 'natnetwork stop' can leave VBoxNetDHCP running, and then 'start' fails
restart_natnet() {
  local pids
  echo "Forwards not answering: restarting NAT Network '$NATNET' (the VM's network drops briefly)..."
  VBoxManage natnetwork stop --netname "$NATNET" || true
  sleep 2
  pids=$(pgrep -u "$(id -un)" -f "VBoxNetDHCP --comment $NATNET( |\$)" || true)
  if [ -n "$pids" ]; then
    echo "Stopping leftover DHCP process: $pids"
    # shellcheck disable=SC2086
    kill $pids
    sleep 3
  fi
  VBoxManage natnetwork start --netname "$NATNET"
  sleep 3
}

if ! apply_forwards; then
  restart_natnet
  if ! apply_forwards; then
    echo "ERROR: still not answering (dashboard port: ${web_port:-none found}). Is SO still starting? Check 'sudo so-status' in the VM."
    exit 1
  fi
fi

# --- 3. Summary ---------------------------------------------------------------
# SO's redirects carry the address it was installed with, if they carry one
so_ip=$(curl -skI --max-time 5 "https://127.0.0.1:$WEB_HOST_PORT/" \
  | grep -i '^location:' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
if [ -n "$so_ip" ] && [ "$so_ip" != "127.0.0.1" ] && [ "$so_ip" != "$SO_IP" ]; then
  echo "WARNING: SO redirects to $so_ip but the VM now has $SO_IP. SO may need its IP updated."
fi

cat <<EOF

Forwards OK:
  Dashboard check  127.0.0.1:$WEB_HOST_PORT → $SO_IP:$web_port
  SSH              127.0.0.1:$SSH_HOST_PORT → $SO_IP:22

From the laptop (UPM VPN on):
  Web UI:     ssh -J $(id -un)@b5g-bigtwin02.dit.upm.es -p $SSH_HOST_PORT -D 1080 onionsec@127.0.0.1
              Firefox: manual proxy, SOCKS v5 localhost:1080, Proxy DNS on
              then browse to https://$SO_IP
  SSH to SO:  ssh -J $(id -un)@b5g-bigtwin02.dit.upm.es -p $SSH_HOST_PORT onionsec@127.0.0.1
EOF
