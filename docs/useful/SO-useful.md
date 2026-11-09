## 7. VM Snapshot Discipline

| Snapshot name | When to take |
|---|---|
| `clean-install` | After section 5.5 (rules updated, telemetry verified) |
| `data-loaded` | After injecting all lab scenarios (Phase L2) |
| `post-lab-N` | After each lab session that modifies SO config |

Always restore from `clean-install` before re-injecting data for a fresh lab run.


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


## Gotchas

### Firewall is Salt-managed — do not touch iptables manually
SO manages iptables via Salt. Any manual `iptables` change will be overwritten on the next Salt run. All firewall changes must go through:
**SOC → Administration → Configuration → firewall → hostgroups**

If you lock yourself out, you have to use the physical console or a direct management interface. Add your analysis machine's IP to the allowed hosts before you start querying ES remotely.

### Elasticsearch heap and OOM crashes
Default heap = 25% of RAM, capped at 25 GB. On an 8 GB machine that's 2 GB — Elasticsearch will crash under load. On a 16 GB standalone node, ES gets 4 GB heap by default. This is borderline.

- Rule of thumb: heap × 2 should not exceed total RAM minus 4 GB for OS
- Never exceed 31 GB heap (JVM performance cliff above compressed OOP boundary)
- If ES keeps crashing: increase RAM or reduce retention/index count

### Never manually edit Logstash or ES configs directly
All configuration is managed by Salt and lives under `/opt/so/saltstack/`. Direct edits to `/etc/logstash/` or ES config files will be overwritten. Use the SOC UI or edit Salt pillar files.

### Sysmon data requires a Windows endpoint
Zeek and Suricata run on the SO sensor and generate data automatically. Sysmon data only appears if you have a Windows host with Elastic Agent + Sysmon installed and pointed at the SO fleet server. If your lab is Linux-only, you will not see `logs-sysmon-so` events.

### Data volume grows fast
Even in a lab, full PCAP + Zeek + Suricata generates gigabytes per hour depending on traffic. Set retention policies early. By default, SO manages index lifecycle (ILM) automatically but storage can fill quickly during attack simulations.

### Salt auth change after 7 days (v2.4.210+)
Security Onion 2.4.210 introduced a Salt authentication update. After initial install, the system sets `minimum_auth_version: 0` for compatibility. After 7 days, it automatically bumps to version 3. If you have any older minions or custom Salt configurations, they will stop communicating. Not relevant for a single standalone node, but worth knowing.

### Suricata custom rulesets pause syncing (v2.4.200+)
If you add a custom Suricata ruleset, it will pause all detection syncing until you explicitly review the "Sync Block" in the UI. Your new rules won't load silently — check the detections page.

---

## What Security Onion Does Not Do

This is the research justification for the fusion layer.

| Gap | Why it matters for this project |
|---|---|
| **No cross-source event correlation** | Zeek, Suricata, and Sysmon alerts are siloed — SO has no engine to link a Zeek conn log, a Suricata alert, and a Sysmon process event that all involve the same attacker IP | 
| **No kill-chain or ATT&CK stage inference** | Individual alerts are not grouped into attack narratives; an analyst must do this manually |
| **No confidence scoring** | Low-severity events that collectively indicate compromise are not surfaced; each event is evaluated in isolation |
| **No automated threat report generation** | All narrative and documentation work falls to human analysts |
| **No structured STIX/TAXII export** | MISP integration exists, but there is no native STIX 2.1 serialization or TAXII publishing pipeline |
| **No anomaly/behavioral detection** | SO is signature-based (Suricata rules, Sigma). Low-and-slow attacks and novel techniques that lack signatures are missed |
| **Basic case management** | TheHive integration exists but is not SOAR-level automation; no playbook-driven response |

---