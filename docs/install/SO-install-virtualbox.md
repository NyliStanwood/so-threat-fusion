# Security Onion 2.4 — Standalone Installation on VirtualBox

**SO version:** 2.4.211  
**Deployment type:** Standalone (all components on one VM)  
**Reference:** https://docs.securityonion.net/en/2.4/installation.html  
**Hardware requirements:** https://docs.securityonion.net/en/2.4/hardware.html

---

## 1. Minimum VM Specifications

| Resource | Minimum | Recommended for lab |
|---|---|---|
| RAM | 16 GB = 16384 MB | 24 GB |
| CPU cores | 4 | 4–6 |
| Disk | 200 GB | 250 GB |
| Network adapters | 2 | 2 |

> **Why 2 NICs on a NAT Network:** SO needs a management interface (internet + analyst access) and a separate monitoring interface (promiscuous capture). Using VirtualBox **NAT Network** (not plain NAT) for management gives the VM internet access AND allows a Kali VM on the same NAT Network to reach the SO web UI directly — no port forwarding needed. A Host-Only management adapter fails because Linux's default route goes through the NAT adapter, not Host-Only, and SO rejects this routing mismatch during setup.

---

## 2. Prerequisites — VirtualBox NAT Network

Before creating any VMs, create the shared NAT Network that SO and Kali will both use.

VirtualBox → **Tools → Network Manager → NAT Networks tab → Create**

| Field | Value |
|---|---|
| Name | `so-net` |
| IPv4 Prefix | `10.0.2.0/24` |
| Enable DHCP | ✓ |

Click **Apply**. This network provides internet access and allows VMs on it to communicate with each other.

---

## 3. VirtualBox VM Configuration

### 3.1 Create the VM

1. Open VirtualBox → **New**
2. **Name:** `SecurityOnion-2.4`
3. **ISO Image:** select `securityonion-2.4.211-20260407.iso`
4. Check **Skip Unattended Installation** → **Next**
5. **Memory:** 16384 MB minimum
6. **Processors:** 4
7. **Hard disk:** 200 GB, dynamically allocated → **Finish**

### 3.2 CPU Settings

Settings → **System → Processor**

- **Processors:** 4 (minimum)
- Enable **PAE/NX**

### 3.3 Display

Settings → **Display → Screen**

- **Video Memory:** 64 MB (prevents graphical glitches during install)

### 3.4 Network Adapters

Two adapters total. Power off the VM before changing network settings.

| Adapter | Mode | Name | Role | Promiscuous | Linux interface |
|---|---|---|---|---|---|
| Adapter 1 | NAT Network | `so-net` | Management + internet | Deny | `enp0s3` |
| Adapter 2 | Internal Network | `internal-net` | Monitoring (capture) | Allow All | `enp0s8` |

**Adapter 1 — Management + Internet**

Settings → **Network → Adapter 1**

| Field | Value |
|---|---|
| Enable Network Adapter | ✓ |
| Attached to | **NAT Network** |
| Name | `so-net` |
| Adapter Type | Paravirtualized Network (virtio-net) |
| Promiscuous Mode | Deny |

SO gets a DHCP address on `10.0.2.0/24` (typically `10.0.2.15`). This adapter handles internet access for package downloads and rule updates, and is selected as SO's management NIC during setup.

**Adapter 2 — Monitoring interface**

Settings → **Network → Adapter 2**

| Field | Value |
|---|---|
| Enable Network Adapter | ✓ |
| Attached to | **Internal Network** |
| Name | `internal-net` |
| Adapter Type | Paravirtualized Network (virtio-net) |
| Promiscuous Mode | **Allow All** |

SO puts this interface into promiscuous mode so Zeek and Suricata capture all traffic on `internal-net`, not only traffic addressed to this VM.

### 3.5 Storage — Attach the ISO

Settings → **Storage → Controller: IDE → Empty (CD icon)**

- Click the CD icon on the right → **Choose a disk file**
- Select: `securityonion-2.4.211-20260407.iso`

### 3.6 Accessing SO from Outside the VM

SO's web UI and Elasticsearch API are on the `so-net` NAT Network (`10.0.2.x`). Your Windows host cannot reach this network directly — only VMs on `so-net` can. Use the **Kali Linux VM** (section 6) as your analyst workstation to reach the SO web UI and run Python scripts against the Elasticsearch API.

---

## 4. Installation

### 4.1 Boot and Install the OS

1. Start the VM.
2. The SO installer screen appears. Type `yes` and press Enter when warned that all data will be erased.
3. Create a Linux OS user (e.g. `onionsec`) and password. This is the console login — separate from the SOC web UI account created later.
4. The OS installs (~10–15 min). When prompted, **Restart**.
5. After restart, log in with the OS user. The SO setup wizard launches automatically.

### 4.2 SO Setup Wizard

Work through each screen using arrow keys and Enter.

**Step 1 — Installation type**
- Select: **STANDALONE**

**Step 2 — Agree**
- Type: `AGREE`

**Step 3 — Hostname**
- Enter a hostname, e.g. `securityonion-ms`

**Step 4 — Management Interface**
- Select the NIC whose MAC matches **Adapter 1** (NAT Network `so-net`). It appears as `enp0s3`.
- Note: MAC addresses are shown in both the VirtualBox adapter settings and the NIC selection screen — match them to pick the right one.

**Step 5 — Address assignment**
- Select: **DHCP**
- SO will receive an address on `10.0.2.0/24` (typically `10.0.2.15`)

**Step 6 — Internet access**
- Select: **Direct** (no proxy)
- Keep default Docker IP range: **Yes**

**Step 7 — Monitoring interface**
- Select the NIC matching **Adapter 2** (Internal Network). It appears as `enp0s8`.
- Use Space to select it, then Enter to confirm.
- This interface goes into promiscuous mode — no IP is assigned.

**Step 8 — SOC web UI admin account**
- Enter the admin email (e.g. `yourname@example.com`) — used to log in to the SOC web UI
- Enter and confirm the admin password

**Step 9 — Web interface access method**
- Select: **IP** (use IP address to access the web interface)
- Allow access via web interface: **Yes**

**Step 10 — Access control**
- Enter the subnet allowed to reach the web UI:
  ```
  10.0.2.0/24
  ```
  This covers the entire NAT Network, including the Kali VM.

**Step 11 — Review and confirm**
- Review the summary. Verify:
  - Management NIC: `enp0s3`
  - Management IP: `10.0.2.15` (or similar)
  - Allowed subnet: `10.0.2.0/24`
- Confirm with **Yes**.
- SO installs all services via Salt. This takes **20–30 minutes**. High CPU activity is normal.

When complete, SO displays the web UI URL and login info. **Note the management IP** — you will use it from Kali.

---

## 5. Post-Install Verification

### 5.1 Check SO services on the console

```bash
sudo so-status
```

All major services should show `running`:

| Service | What it does |
|---|---|
| `so-elasticsearch` | Core indexed storage |
| `so-kibana` | Visualization |
| `so-logstash` | Log parsing pipeline |
| `so-zeek` | Network protocol metadata |
| `so-suricata` | IDS alerts + PCAP |
| `so-soc` | The SOC web UI |
| `so-fleet` | Elastic Agent fleet manager |

If any service shows `failed`:
```bash
sudo so-restart
# Wait 2–3 minutes, then:
sudo so-status
```

### 5.2 Access the SOC web UI

From the **Kali VM** (see section 6), open a browser and navigate to:
```
https://<SO_MANAGEMENT_IP>
```
where `<SO_MANAGEMENT_IP>` is the IP shown at the end of the SO setup wizard (typically `10.0.2.15`).

- Accept the self-signed certificate warning.
- Log in with the admin email and password set in the wizard.
- You should see the Security Onion Console with Alerts, Hunt, and Dashboards views.

### 5.3 Test Elasticsearch API access

From the **Kali VM** terminal:
```bash
curl -k -u elastic:<PASSWORD> https://<SO_MANAGEMENT_IP>:9200/_cat/indices?v
```

If you need to retrieve the Elasticsearch password:
```bash
# On the SO node console
sudo so-secrets
```

You should see data stream entries like `logs-zeek-so`, `logs-suricata-so` once traffic is flowing.

In Python (`elasticsearch-py`):
```python
es = Elasticsearch(
    "https://<SO_MANAGEMENT_IP>:9200",
    basic_auth=("elastic", "<PASSWORD>"),
    verify_certs=False   # self-signed cert in lab
)
```

### 5.4 Generate test telemetry

From the **Kali VM**, generate traffic on the monitored interface:
```bash
# On Kali — traffic on eth1 (internal-net) is captured by SO
sudo nmap -sV 10.0.2.0/24   # generates connection/port events in Zeek
```

In the SOC web UI → **Hunt**, search:
```
event.dataset: zeek.dns
```

Events should appear within 30–60 seconds.

### 5.5 Update rules and take a snapshot

```bash
sudo soup
```

Then take a clean baseline snapshot: **Machine → Take Snapshot** → name it `clean-install`.

> This is the snapshot you restore before every fresh lab run.

---

## 6. Kali Linux VM Setup

Kali serves two roles: **analyst workstation** (web UI + API access via `so-net`) and **attacker/injector VM** (traffic generation on `internal-net` captured by SO).

### 6.1 Create the Kali VM

Download the Kali VirtualBox image from kali.org → Installer Images → VirtualBox. Import the `.ova` file.

### 6.2 Network Adapters for Kali

| Adapter | Mode | Name | Adapter Type | Promiscuous | Role |
|---|---|---|---|---|---|
| Adapter 1 | NAT Network | `so-net` | Paravirtualized Network (virtio-net) | Deny | Internet + SO web UI access |
| Adapter 2 | Internal Network | `internal-net` | Paravirtualized Network (virtio-net) | **Allow All** | Traffic injection + Wireshark capture |

Traffic Kali sends on **Adapter 2** (`internal-net` → typically `eth1`) is captured by SO's monitoring interface. Traffic on **Adapter 1** (`so-net` → `eth0`) reaches the SO management interface for web UI and API access.

Adapter 2 does not need promiscuous mode to inject traffic (Kali is sending, not sniffing), but Allow All lets you run Wireshark on `eth1` to verify what SO is actually receiving from tcpreplay or live attacks.

### 6.3 Traffic Injection Tools

| Tool | Purpose |
|---|---|
| `tcpreplay` | Replay saved PCAPs into `internal-net` (Lab L2 scenarios) |
| Metasploit | Live ATT&CK-mapped exploitation against a target VM |
| `nmap`, `hping3`, `scapy` | Reconnaissance and custom packet generation |
| `invoke-atomicredteam` (via `pwsh`) | Atomic Red Team technique execution on Linux |

**Replay a PCAP into the monitored interface:**
```bash
# eth1 = internal-net adapter on Kali
sudo tcpreplay -i eth1 scenario.pcap
```

SO will see the replayed traffic and generate Zeek/Suricata events.

**Verify which interface is `internal-net`:**
```bash
ip addr show   # check MACs against VirtualBox adapter settings
```

---

## 7. VM Snapshot Discipline

| Snapshot name | When to take |
|---|---|
| `clean-install` | After section 5.5 (rules updated, telemetry verified) |
| `data-loaded` | After injecting all lab scenarios (Phase L2) |
| `post-lab-N` | After each lab session that modifies SO config |

Always restore from `clean-install` before re-injecting data for a fresh lab run.

---

## 8. Recommended Post-Install Tweaks for Lab Use

### 8.1 Disable Strelka (file analysis engine)

Strelka is RAM and CPU intensive and unnecessary for core lab scenarios:

**SOC → Administration → Configuration → strelka → enabled → set to `false`**

Click **Synchronize grid** to apply via Salt.

### 8.2 Disable full PCAP storage

Suricata writes full packet captures to disk by default, filling storage quickly:

**SOC → Administration → Configuration → suricata → pcap → enabled → set to `false`**

> Keep PCAP enabled if lab exercises require raw PCAP retrieval.

### 8.3 Set Elasticsearch index retention

Shorten from 30 days to 7 days to reduce disk pressure:

**SOC → Administration → Configuration → elasticsearch → index lifecycle settings**

### 8.4 VirtualBox Guest Additions (optional)

Enables shared clipboard and better display resolution on the SO console:

```bash
sudo yum install -y kernel-devel gcc make perl
# Mount Guest Additions ISO: VirtualBox Devices → Insert Guest Additions CD
sudo /run/media/<user>/VBox_GAs_*/VBoxLinuxAdditions.run
```

---

## 9. Credentials Reference

| Component | Username | Where to set/find |
|---|---|---|
| SOC web UI | Admin email from wizard | SOC → Administration → Users |
| Elasticsearch API | `elastic` | Set during wizard; retrieve via `sudo so-secrets` |
| OS (Linux) | User created during install | Standard Linux console login |

```bash
sudo so-secrets   # lists all SO-managed credentials
```
