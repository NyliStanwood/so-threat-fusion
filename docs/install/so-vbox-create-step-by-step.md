# `1.so-vbox-create.sh`, Step by Step (Validate and Undo for Every Change)

**Script:** [scripts/1.so-vbox-create.sh](scripts/1.so-vbox-create.sh)  
**Guide:** [SO-plan-for-upm-server-VirtualBox.md](SO-plan-for-upm-server-VirtualBox.md) (this file replaces its Step 2 when you'd rather go one command at a time)  
**Where:** on the server, `ssh marylin@b5g-bigtwin02.dit.upm.es`, as `marylin`, **no `sudo`**

This file runs the script's commands one at a time. Each step changes one thing, shows how to check it, and shows how to undo it.

## Legend

| Emoji | Meaning |
|---|---|
| ℹ️ | What the step does |
| ▶️ | Command to run |
| ✅ | Check the result (expected output) |
| ↩️ | Undo the step |
| ⚠️ | Caution |
| 🔍 | Read-only: nothing changes, so there is nothing to undo |

## Change log

Tick each step as you go. If something breaks, undo in **reverse order**, starting at the last ticked step (or use the [full rollback](#full-rollback)).

| Step | Change | Done | Undone |
|---|---|---|---|
| 0 | Shell variables (session only) | ☐ | — |
| 1 | Pre-checks | ☐ | — |
| 2 | NAT Network `so-net` created | ☐ | ☐ |
| 3 | NAT Network started | ☐ | ☐ |
| 4 | VM registered | ☐ | ☐ |
| 5 | CPU / RAM / chipset / boot order | ☐ | ☐ |
| 6 | Network adapters | ☐ | ☐ |
| 7 | Disk image created | ☐ | ☐ |
| 8 | SATA controller added | ☐ | ☐ |
| 9 | Disk attached | ☐ | ☐ |
| 10 | IDE controller + ISO attached | ☐ | ☐ |
| 10b | Serial port → `~/so-serial.log` | ☐ | ☐ |
| 11 | VNC console enabled | ☐ | ☐ |
| 12 | Final summary | ☐ | — |

---

## Step 0 — Set the variables

ℹ️ The rest of the commands use these names. They only last as long as the SSH session. **After reconnecting, run this block again before continuing.**

▶️
```bash
VM_NAME="so-standalone"
OS_TYPE="Oracle_64"
CPUS=16
MEMORY_MB=65536
DISK_GB=400
BASE_FOLDER="$HOME/VirtualBox VMs"
ISO="$HOME/isos/securityonion-2.4.211-20260407.iso"
NATNET="so-net"
NATNET_CIDR="10.0.2.0/24"
INTNET="internal-net"
VRDE_PORT=5901
DISK="$BASE_FOLDER/$VM_NAME/$VM_NAME.vdi"
```

✅
```bash
echo "$VM_NAME | $ISO | $DISK"
```
Expected: three values, none empty.

↩️ Nothing to undo. The variables disappear when you log out.

⚠️ `BASE_FOLDER` contains a space (`VirtualBox VMs`). Always keep the double quotes around `"$BASE_FOLDER"` and `"$DISK"`.

---

## Step 1 — Pre-checks 🔍

ℹ️ Confirms VirtualBox works, the ISO is where the script expects it, and no VM with this name exists yet.

▶️ / ✅
```bash
VBoxManage --version                              # → 6.1.50_Ubuntur161033
ls -lh "$ISO"                                     # → the ISO, several GB
VBoxManage showvminfo "$VM_NAME" >/dev/null 2>&1 && echo "EXISTS" || echo "free"   # → free
VBoxManage list extpacks | grep "^Pack no"        # → Pack no. 0:   VNC
```

If the VM already `EXISTS`, see the [full rollback](#full-rollback) or choose another `VM_NAME`.

↩️ Read-only, nothing to undo.

---

## Step 2 — Create the NAT Network `so-net`

ℹ️ Creates the management network: `10.0.2.0/24`, with DHCP, NAT to the internet, and port-forwards later. It's the same network as the laptop setup.

✅ **Before:** check whether it already exists.
```bash
VBoxManage natnetwork list
```
If `so-net` is already listed, **skip this step** and don't undo it later: it was there before you started.

▶️
```bash
VBoxManage natnetwork add --netname "$NATNET" --network "$NATNET_CIDR" --enable --dhcp on
```

✅
```bash
VBoxManage natnetwork list
```
Expected: an entry with `Name: so-net`, `Network: 10.0.2.0/24`, `DHCP Enabled: Yes`.

↩️
```bash
VBoxManage natnetwork remove --netname "$NATNET"
```

⚠️ Undo only after Step 3's undo (stop it first), and only if no VM still uses it.

---

## Step 3 — Start the NAT Network

ℹ️ Starts the NAT service (`VBoxNetNAT`) and the DHCP server for `so-net`. The script ignores an error here, because the network may already be running.

▶️
```bash
VBoxManage natnetwork start --netname "$NATNET"
```
An error like "already running" is fine.

✅
```bash
ps aux | grep [V]BoxNetNAT
```
Expected: a `VBoxNetNAT` process for `so-net`, owned by `marylin`.

↩️
```bash
VBoxManage natnetwork stop --netname "$NATNET"
```

---

## Step 4 — Create and register the VM

ℹ️ Creates an empty VM definition in `~/VirtualBox VMs/so-standalone/` and registers it with your VirtualBox. It has no disk, no network and no hardware settings yet.

▶️
```bash
VBoxManage createvm --name "$VM_NAME" --ostype "$OS_TYPE" --basefolder "$BASE_FOLDER" --register
```

✅
```bash
VBoxManage list vms                                  # → "so-standalone" {uuid}
ls "$BASE_FOLDER/$VM_NAME/"                          # → so-standalone.vbox
```

↩️
```bash
VBoxManage unregistervm "$VM_NAME" --delete
```

⚠️ `--delete` also deletes every disk attached to the VM. Once Steps 7–9 are done, that includes the 400 GB VDI. Undo those steps first if you want to keep the disk.

---

## Step 5 — CPU, RAM, chipset and boot order

ℹ️ Sets the following:

| Setting | Meaning |
|---|---|
| `--cpus 16 --memory 65536` | 16 vCPU, 64 GB RAM |
| `--ioapic on` | Required for more than one CPU |
| `--pae on` | Exposes PAE/NX to the guest |
| `--rtcuseutc on` | Hardware clock in UTC (Linux standard) |
| `--paravirtprovider kvm` | Linux guests use KVM-style paravirtual clocks (faster, more accurate) |
| `--graphicscontroller vmsvga --vram 16` | Standard Linux display, 16 MB is plenty for a text installer |
| `--boot1 dvd --boot2 disk` | Boot the ISO first; once the disk has an OS, detach the ISO (guide Step 6) |

✅ **Before:** record the current values, so undo has something to go back to.
```bash
VBoxManage showvminfo "$VM_NAME" --machinereadable \
  | grep -E '^(cpus|memory|ioapic|pae|rtcuseutc|paravirtprovider|graphicscontroller|vram|boot[1-4])=' \
  | tee ~/so-step5-before.txt
```

▶️
```bash
VBoxManage modifyvm "$VM_NAME" \
  --cpus "$CPUS" --memory "$MEMORY_MB" \
  --ioapic on --pae on --rtcuseutc on \
  --paravirtprovider kvm \
  --graphicscontroller vmsvga --vram 16 \
  --boot1 dvd --boot2 disk --boot3 none --boot4 none
```

✅
```bash
VBoxManage showvminfo "$VM_NAME" --machinereadable \
  | grep -E '^(cpus|memory|ioapic|pae|rtcuseutc|paravirtprovider|graphicscontroller|vram|boot[1-4])='
```
Expected: `cpus=16`, `memory=65536`, `ioapic="on"`, `pae="on"`, `rtcuseutc="on"`, `paravirtprovider="kvm"`, `graphicscontroller="vmsvga"`, `vram=16`, `boot1="dvd"`, `boot2="disk"`, `boot3="none"`, `boot4="none"`.

↩️ Set each value back to what `~/so-step5-before.txt` shows. For a fresh VM, these were the defaults:
```bash
cat ~/so-step5-before.txt
VBoxManage modifyvm "$VM_NAME" --cpus 1 --memory 128 --ioapic off --pae off --rtcuseutc off \
  --paravirtprovider default --graphicscontroller vboxvga --vram 8 \
  --boot1 floppy --boot2 dvd --boot3 disk --boot4 none
```
Adjust the command if your before-file shows other values. To change only one setting (e.g. less RAM), re-run `modifyvm` with just that option, e.g. `--memory 32768`.

⚠️ `modifyvm` only works while the VM is **powered off**.

---

## Step 6 — Network adapters

ℹ️ Configures two adapters:

| | NIC 1 | NIC 2 |
|---|---|---|
| Attached to | NAT Network `so-net` | Internal Network `internal-net` |
| Role | Management + internet | Monitor (Zeek/Suricata) |
| Type | virtio | virtio |
| Promiscuous | `deny` | `allow-all` (sees all traffic between the lab VMs) |
| Cable | connected | connected |

`internal-net` doesn't need to be created: VirtualBox creates an internal network the first time a VM uses its name.

▶️
```bash
VBoxManage modifyvm "$VM_NAME" \
  --nic1 natnetwork --nat-network1 "$NATNET" --nictype1 virtio --nicpromisc1 deny     --cableconnected1 on \
  --nic2 intnet     --intnet2 "$INTNET"      --nictype2 virtio --nicpromisc2 allow-all --cableconnected2 on
```

✅
```bash
VBoxManage showvminfo "$VM_NAME" | grep -E '^NIC [12]:'
```
Expected:
- `NIC 1: MAC: …, Attachment: NAT Network 'so-net', Cable connected: on, …, Type: virtio, … Promisc Policy: deny`
- `NIC 2: MAC: …, Attachment: Internal Network 'internal-net', …, Type: virtio, … Promisc Policy: allow-all`

📝 Write down both **MAC addresses**. The SO setup wizard asks you to pick NICs by MAC.

↩️ Disable both adapters (a fresh VM has only NIC 1, as NAT):
```bash
VBoxManage modifyvm "$VM_NAME" --nic1 nat --nic2 none
```

---

## Step 7 — Create the disk image

ℹ️ Creates a 400 GB VDI. It's **dynamically allocated**: the file starts at a few MB and grows as SO writes data. It isn't attached to anything yet.

✅ **Before:**
```bash
df -h "$HOME"          # → enough free space on / (877 GB at the survey)
```

▶️
```bash
VBoxManage createmedium disk --filename "$DISK" --size $((DISK_GB * 1024)) --format VDI
```

✅
```bash
VBoxManage showmediuminfo disk "$DISK" | grep -E 'Location|Capacity|Format|Storage format|In use'
ls -lh "$DISK"
```
Expected: `Capacity: 409600 MBytes`, `Format variant: dynamic default`, and a small file size on disk.

↩️ (only while it's **not attached**: undo Step 9 first if needed)
```bash
VBoxManage closemedium disk "$DISK" --delete
```

---

## Step 8 — Add the SATA controller

ℹ️ Adds a SATA (AHCI) controller for the disk (port 0). The DVD goes on a separate IDE controller in Step 10.

▶️
```bash
VBoxManage storagectl "$VM_NAME" --name SATA --add sata --controller IntelAhci --portcount 1
```

✅
```bash
VBoxManage showvminfo "$VM_NAME" | grep -A5 "^Storage Controller Name"
```
Expected: `Name (0): SATA`, `Type (0): IntelAhci`, `Port Count (0): 1`, `Bootable (0): on`. `Max Port Count (0): 30` is the most ports the AHCI type supports, not the number you set. (The first run on 2026-11-07 used `--portcount 2`: harmless, port 1 just stays empty.)

↩️ (removes anything still attached to it)
```bash
VBoxManage storagectl "$VM_NAME" --name SATA --remove
```

---

## Step 9 — Attach the disk

ℹ️ Plugs the VDI into SATA port 0. `--nonrotational on` tells the guest it's an SSD, so Oracle Linux schedules I/O accordingly.

▶️
```bash
VBoxManage storageattach "$VM_NAME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$DISK" --nonrotational on
```

✅
```bash
VBoxManage showvminfo "$VM_NAME" --machinereadable | grep '"SATA-0-0"'
```
Expected: `"SATA-0-0"="/home/marylin/VirtualBox VMs/so-standalone/so-standalone.vdi"`

↩️ (detaches only; the VDI file stays)
```bash
VBoxManage storageattach "$VM_NAME" --storagectl SATA --port 0 --device 0 --medium none
```

⚠️ **Re-check this step before the first boot.** On 2026-11-07 the disk ended up detached (`"SATA-0-0"="none"`). The SO installer then fails with `/tmp/part-include: No such file or directory`, hidden behind the boot splash, which looks like a hang. See the guide's [Troubleshooting](SO-plan-for-upm-server-VirtualBox.md#installer-terminates-tmppart-include-no-such-file-or-directory).

---

## Step 10 — Attach the ISO

ℹ️ Adds an IDE controller and inserts the Security Onion ISO into a virtual DVD drive on it (IDE port 1, device 0, the "secondary master"). Thanks to the Step 5 boot order, the VM boots the installer. IDE matches the laptop install and is the layout that installed successfully on bigtwin02.

▶️
```bash
VBoxManage storagectl "$VM_NAME" --name IDE --add ide --controller PIIX4
VBoxManage storageattach "$VM_NAME" --storagectl IDE --port 1 --device 0 --type dvddrive --medium "$ISO"
```

✅
```bash
VBoxManage showvminfo "$VM_NAME" --machinereadable | grep -E '"(SATA|IDE)-[01]-0"'
```
Expected: `"SATA-0-0"="…/so-standalone.vdi"` (disk, Step 9) and `"IDE-1-0"="/home/marylin/isos/securityonion-2.4.211-20260407.iso"`.

↩️ Eject the ISO but keep the empty drive (this is also what you do **before the reboot** at the end of the OS install):
```bash
VBoxManage storageattach "$VM_NAME" --storagectl IDE --port 1 --device 0 --type dvddrive --medium emptydrive
```
Or remove the drive and the IDE controller completely:
```bash
VBoxManage storageattach "$VM_NAME" --storagectl IDE --port 1 --device 0 --medium none
VBoxManage storagectl "$VM_NAME" --name IDE --remove
```

---

## Step 10b — Serial port to a log file

ℹ️ Connects the VM's first serial port (COM1) to a file on the host. When the installer is booted with `console=ttyS0` (the boot script does this), every kernel message lands in `~/so-serial.log`. Commands run inside the installer can also write there (`… > /dev/ttyS0`). It's the debugging channel that found the missing-disk problem.

▶️
```bash
VBoxManage modifyvm "$VM_NAME" --uart1 0x3F8 4 --uartmode1 file "$HOME/so-serial.log"
```

✅
```bash
VBoxManage showvminfo "$VM_NAME" --machinereadable | grep -E '^(uart1|uartmode1)='
```
Expected: `uart1="0x03f8,4"` and `uartmode1="file,/home/marylin/so-serial.log"`.

↩️
```bash
VBoxManage modifyvm "$VM_NAME" --uart1 off
```

---

## Step 11 — Enable the VNC console

ℹ️ Turns on VRDE (the remote console) using the server's **VNC** Extension Pack, only on `127.0.0.1:5901`, protected by a password. It's reached from the laptop through `ssh -L 5901:127.0.0.1:5901 …` and a VNC viewer.

✅ **Before:**
```bash
VBoxManage list extpacks | grep -A6 "^Pack no"     # → VNC, Usable: true
ss -tln | grep ":$VRDE_PORT "                      # → nothing (port free)
```

▶️ Type the password at the prompt. It isn't shown, and it doesn't stay in your shell history.
```bash
read -rsp "VNC console password (not your server password): " VNC_PASSWORD; echo
VBoxManage modifyvm "$VM_NAME" --vrde on --vrdeextpack VNC \
  --vrdeaddress 127.0.0.1 --vrdeport "$VRDE_PORT" \
  --vrdeproperty VNCPassword="$VNC_PASSWORD"
unset VNC_PASSWORD
```

⚠️ VNC uses only the first 8 characters of the password.

🔑 **Lab credential (shared with the tutor on purpose):** VNC password `1q2w3e4r`

> ⚠️ **Security warning: lab only.** This password is written here so the tutor can open the console, and the setup is meant to be fully transparent. It's acceptable only because the console listens on `127.0.0.1` (only someone with an SSH login on bigtwin02 can reach it) and the VM holds lab data only. `1q2w3e4r` is a keyboard pattern found in every password wordlist. VNC's password check is weak (8 characters at most, an old DES-based challenge), and VNC traffic isn't encrypted. Here the SSH tunnel provides the encryption.
>
> 🏢 **In a corporate or secure environment:**
> - Don't use VNC for VM consoles. Use the hypervisor's authenticated, encrypted console. With Oracle's Extension Pack, that's VRDP with host login (PAM) and TLS:
>   ```bash
>   VBoxManage modifyvm "$VM_NAME" --vrde on --vrdeextpack "Oracle VM VirtualBox Extension Pack" \
>     --vrdeaddress 127.0.0.1 --vrdeport 3389 --vrdeauthtype external \
>     --vrdeproperty "Security/Method=TLS" \
>     --vrdeproperty "Security/ServerCertificate=/path/server_cert.pem" \
>     --vrdeproperty "Security/ServerPrivateKey=/path/server_key_private.pem" \
>     --vrdeproperty "Security/CACertificate=/path/ca_cert.pem"
>   ```
>   Alternatives: libvirt with SPICE over TLS, or the server's out-of-band console (iDRAC/iLO/IPMI) behind the management network.
> - Never write a password in a document or a git repository. Store it in a password manager or secrets vault (e.g. HashiCorp Vault, Bitwarden), type it at a prompt (`read -rsp`, as above), and scan repositories for leaked secrets (`gitleaks detect`).
> - Generate passwords randomly, e.g. `openssl rand -base64 24`, and rotate them when someone leaves the project.
> - Give each person their own credential instead of sharing one, so every access can be traced to a person.

👀 **Watching together with the tutor:** by default the console accepts **one viewer at a time** (`MultiConn: off`). With the VM powered off, allow several viewers at once:
```bash
VBoxManage modifyvm "$VM_NAME" --vrdemulticon on
```
↩️ `VBoxManage modifyvm "$VM_NAME" --vrdemulticon off`

✅
```bash
VBoxManage showvminfo "$VM_NAME" | grep -i vrde
```
Expected: `VRDE: enabled (Address 127.0.0.1, Ports 5901, … Authentication type: null)`. `null` is expected: it's the RDP login setting, which VNC doesn't use (VNC uses `VNCPassword`). This output doesn't show the password or the pack.

✅ Check the password and the pack in the VM's settings file:
```bash
grep -A6 "<RemoteDisplay" "$BASE_FOLDER/$VM_NAME/$VM_NAME.vbox"
ls -l "$BASE_FOLDER/$VM_NAME/$VM_NAME.vbox"        # → -rw------- (only you can read it)
```
Expected: a reference to the `VNC` extension pack and a `VNCPassword` property with the value `1q2w3e4r` (stored in plain text, so the file must be `-rw-------`; fix with `chmod 600`). If `VNCPassword` is missing or empty, set it again: `VBoxManage modifyvm "$VM_NAME" --vrdeproperty VNCPassword=<new>`.

ℹ️ `ss -tln | grep 5901` stays empty until the VM is **running**: the console only listens while the VM is on.

✅ **After you start the VM** (guide Step 3), check that the console isn't open to the network:
```bash
ss -tln | grep ":$VRDE_PORT "                      # → 127.0.0.1:5901, NOT 0.0.0.0:5901
```

↩️ Turn off the console and clear the password:
```bash
VBoxManage modifyvm "$VM_NAME" --vrde off --vrdeproperty VNCPassword=
```

---

## Step 12 — Final summary 🔍

ℹ️ Shows the whole configuration in one go before you start the VM for the first time.

▶️ / ✅
```bash
VBoxManage showvminfo "$VM_NAME" --machinereadable \
  | grep -E '^(cpus|memory|nic[12]|nat-network1|intnet2|nictype[12]|nicpromisc[12]|vrde|vrdeport|vrdeaddress|boot[12]|uartmode1|"SATA-0-0"|"IDE-1-0")='
```
Expected, among others: `cpus=16`, `memory=65536`, `nic1="natnetwork"`, `nat-network1="so-net"`, `nic2="intnet"`, `intnet2="internal-net"`, `nicpromisc2="allow-all"`, `vrde="on"`, `vrdeport=5901`, `vrdeaddress="127.0.0.1"`, `uartmode1="file,…/so-serial.log"`, plus `SATA-0-0` pointing to the VDI and `IDE-1-0` to the ISO. **If `SATA-0-0` is `"none"`, redo Step 9 before booting.**

Next: boot with the guide's [Step 3](SO-plan-for-upm-server-VirtualBox.md#step-3--boot-the-installer-and-open-the-console) (`2.so-vbox-boot-installer.sh`), not a plain `startvm`.

↩️ Read-only.

---

## Full Rollback

⚠️ Deletes the VM, **its 400 GB disk**, and the NAT Network. Run Step 0 first so the variables are set.

▶️ In reverse order:
```bash
VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null          # if it is running
VBoxManage unregistervm "$VM_NAME" --delete                   # undoes Steps 4–11 (VM + attached disk)
[ -f "$DISK" ] && VBoxManage closemedium disk "$DISK" --delete   # Step 7, if the disk was never attached
VBoxManage natnetwork stop   --netname "$NATNET"              # Step 3
VBoxManage natnetwork remove --netname "$NATNET"              # Step 2: skip if so-net existed before
```

✅
```bash
VBoxManage list vms                       # → so-standalone gone
VBoxManage list hdds | grep -c "$VM_NAME" # → 0
VBoxManage natnetwork list                # → so-net gone
ls "$BASE_FOLDER"                         # → no so-standalone folder
```

If `unregistervm` leaves the folder behind (e.g. after a failed step), remove it by hand once the checks above are clean:
```bash
rm -rf "$BASE_FOLDER/$VM_NAME"
```
