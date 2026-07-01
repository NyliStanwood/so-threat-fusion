# Security Onion 2.4 — Feature & Capability Survey
## Lab Reference Document — Draft 3 (Organized by Layers)

**SO version:** 2.4.211  
**Audience:** University cybersecurity lab students (introductory–intermediate level)  
**Purpose:** Familiarise students with each major SO component before working through lab exercises.

---

## What Is Security Onion?

Security Onion is an open-source Linux distribution for network security monitoring (NSM), intrusion detection, and log management. It bundles multiple best-of-breed tools under a single unified web interface — the **Security Onion Console (SOC)**.

In this lab, SO runs as a **standalone node**: all components (sensors, storage, and UI) are on one virtual machine.

### How the Layers Fit Together

```
┌─────────────────────────────────────────────────────────┐
│  LAYER 4 — DETECTION ENGINEERING                        │
│  Detections · ATT&CK Navigator · CyberChef · Kibana     │
├─────────────────────────────────────────────────────────┤
│  LAYER 3 — SOC WEB UI                                   │
│  Alerts · Hunt · Dashboards · Cases · PCAP · Onion AI   │
├───────────────────────┬─────────────────────────────────┤
│  LAYER 1              │  LAYER 2                        │
│  NETWORK VISIBILITY   │  HOST VISIBILITY                │
│  Zeek · Suricata      │  Elastic Agent · Sysmon         │
│  Logstash · ES        │  Osquery · Elastic Fleet        │
└───────────────────────┴─────────────────────────────────┘
              ↑                        ↑
         Wire traffic           Endpoint telemetry
```

All data — from every layer — lands in **Elasticsearch**, normalized to the **Elastic Common Schema (ECS)**, and is queryable through Hunt.

---

# LAYER 1 — Network Visibility

This layer captures and analyzes everything that crosses the monitored network interface. SO's monitoring interface (`enp0s8` in this lab) runs in **promiscuous mode** — it receives all packets on the internal network segment, not just those addressed to the SO VM.

---

## 1.1 — Zeek (Network Analysis Framework)

**Origin:** Corelight / open-source community  
**Role:** Passive network protocol metadata logging — no alerts, pure observation.

Zeek inspects every packet and produces structured **log files** for each protocol it recognizes. It answers the question *"what happened on the network?"* without making any judgement about whether it was malicious.

`<Insert Screenshot: Hunt view filtered to event.dataset: zeek.conn, showing flow records with source/destination IP, port, and bytes>`

### Log Types (Elasticsearch index: `logs-zeek-so`)

| Log file | `event.dataset` | What it records |
|---|---|---|
| `conn.log` | `zeek.conn` | Every TCP/UDP/ICMP flow: duration, bytes transferred, connection state |
| `dns.log` | `zeek.dns` | DNS queries and responses: domain, record type, answer |
| `http.log` | `zeek.http` | HTTP requests: method, URI, status code, user-agent, response size |
| `ssl.log` | `zeek.ssl` | TLS handshake metadata: SNI hostname, cipher suite, certificate validity |
| `files.log` | `zeek.files` | File transfers observed in-stream: MIME type, MD5/SHA1 hash, source |
| `weird.log` | `zeek.weird` | Protocol anomalies Zeek cannot parse cleanly |
| `notice.log` | `zeek.notice` | Zeek's own behavioral detections (e.g. detected port scanning) |

### Key ECS Fields

| ECS Field | Log | Typical query use |
|---|---|---|
| `source.ip` / `destination.ip` | conn, dns, http… | Who talked to whom |
| `destination.port` | conn | What service was targeted |
| `network.protocol` | conn | `tcp`, `udp`, `icmp` |
| `network.bytes` | conn | Total bytes in the flow |
| `dns.question.name` | dns | Domain name queried |
| `dns.question.type` | dns | `A`, `AAAA`, `MX`, `TXT`… |
| `http.request.method` | http | `GET`, `POST`, `PUT`… |
| `http.request.body.uri` | http | Requested URI path |
| `http.response.status_code` | http | `200`, `404`, `500`… |
| `user_agent.original` | http | Browser or tool user-agent string |
| `tls.server_name` | ssl | SNI hostname from TLS handshake |
| `file.hash.md5` | files | File hash for threat intelligence lookups |

### Sample Hunt Queries

```
# All DNS queries in the last hour
event.dataset: zeek.dns AND @timestamp > now-1h

# All connections to port 445 (SMB — lateral movement indicator)
event.dataset: zeek.conn AND destination.port: 445

# HTTP requests containing a suspicious URI pattern
event.dataset: zeek.http AND http.request.body.uri: *passwd*

# TLS connections where the certificate was self-signed or expired
event.dataset: zeek.ssl AND tls.established: false
```

---

## 1.2 — Suricata (Intrusion Detection System)

**Origin:** Open Information Security Foundation (OISF)  
**Role:** Signature-based IDS — matches traffic against known-bad patterns and fires alerts.

Suricata is the **alerting** counterpart to Zeek's passive logging. Where Zeek records everything it sees, Suricata fires when traffic matches a detection rule. SO ships with the **Emerging Threats Open** ruleset pre-loaded. Suricata also writes **full packet captures (PCAP)** for each alert, enabling retrospective packet-level analysis.

`<Insert Screenshot: Alerts view showing a list of Suricata alerts with severity badges, rule names, and source/destination fields>`

### Alert Structure

Each Suricata alert includes:

| ECS Field | Meaning |
|---|---|
| `rule.name` | Human-readable rule description (e.g. `ET SCAN Nmap -sS window 2048`) |
| `rule.id` | Numeric Suricata SID |
| `rule.category` | Alert category (e.g. `Attempted Reconnaissance`) |
| `event.severity` | 1 = Critical · 2 = Major · 3 = Minor · 4 = Informational |
| `source.ip` / `destination.ip` | Attacker / target |
| `destination.port` | Targeted service port |
| `network.transport` | `tcp` or `udp` |

### Severity Scale

| `event.severity` | Label | Meaning |
|---|---|---|
| 1 | Critical | Active exploit or confirmed malware traffic |
| 2 | Major | High-confidence suspicious activity |
| 3 | Minor | Policy violations, low-confidence suspicious patterns |
| 4 | Informational | Scanning, reconnaissance, general visibility |

### Sample Hunt Queries

```
# All Suricata alerts
event.dataset: suricata.alert

# Critical and Major alerts only
event.dataset: suricata.alert AND event.severity <= 2

# Alerts from a specific attacker IP
event.dataset: suricata.alert AND source.ip: 10.0.2.100

# Alerts matching a keyword in the rule name
event.dataset: suricata.alert AND rule.name: *scan*
```

---

## 1.3 — Logstash + Elasticsearch (Data Pipeline & Storage)

**Origin:** Elastic  
**Role:** Parse, normalize, and index all events from all sources.

Students rarely interact with Logstash or Elasticsearch directly — they are the invisible plumbing that makes everything else work.

**Logstash** receives raw log data from Zeek, Suricata, and Elastic Agent, applies parsing rules, and maps every field to the **Elastic Common Schema (ECS)**. This normalization step is why a single Hunt query like `source.ip: 10.0.2.100` returns results from Zeek, Suricata, and Sysmon at the same time.

**Elasticsearch** stores the normalized events in time-ordered **data streams**:

| Data stream | Contents |
|---|---|
| `logs-zeek-so` | All Zeek logs (conn, dns, http, ssl, files…) |
| `logs-suricata-so` | Suricata alerts and network stats |
| `logs-windows-so` | Windows event logs + Sysmon events |
| `logs-so.*` | SO internal management and health events |

In Hunt, select **All Indices** to search across all streams, or narrow to one to reduce noise.

---

# LAYER 2 — Host Visibility

Network sensors only see traffic crossing the wire. To observe what is happening **inside an endpoint** — which processes ran, which files were written, which registry keys changed — SO deploys agents onto the monitored hosts. This layer covers those endpoint telemetry tools.

---

## 2.1 — Elastic Agent (Data Shipper)

**Origin:** Elastic  
**Role:** Unified agent installed on endpoint VMs; collects and ships telemetry to SO's Elasticsearch.

Elastic Agent replaces the older Beats agents (Winlogbeat, Filebeat) with a single deployable binary. On Windows endpoints in this lab it collects Windows Event Logs, Sysmon events, and optionally performance metrics. It communicates back to SO over an encrypted channel.

**Deployment:** Students obtain the installer from **Downloads** in the SOC sidebar, enroll the Windows VM, and verify connectivity in **Elastic Fleet**.

`<Insert Screenshot: Elastic Fleet main view showing enrolled agents table with hostname, OS, status, and policy columns>`

---

## 2.2 — Sysmon (System Monitor)

**Origin:** Microsoft Sysinternals  
**Role:** Deep Windows event logging — process creation, network connections, file operations, registry changes, and more.

Sysmon is a Windows service that logs detailed OS-level activity to the Windows Event Log. Elastic Agent picks these events up and ships them to SO. Sysmon fills the gap that standard Windows Event Logs leave: without it, you see login events and application errors but not which processes spawned which child processes or which DLLs were loaded.

`<Insert Screenshot: Hunt view showing a Sysmon Event ID 1 (Process Create) record with process.name, process.command_line, and process.parent.name visible>`

### Sysmon Event IDs

| Event ID | Name | What it records |
|---|---|---|
| 1 | Process Create | New process: name, PID, parent, full command line, image hash |
| 3 | Network Connection | Outbound network connection initiated by a process |
| 5 | Process Terminate | Process exit (paired with Event ID 1) |
| 7 | Image Load | DLL loaded by a process (detects DLL hijacking) |
| 8 | CreateRemoteThread | Thread injected into another process |
| 10 | ProcessAccess | Process reading another process's memory (credential dumping indicator) |
| 11 | File Create | File created or overwritten |
| 13 | Registry Value Set | Registry key value modified |
| 22 | DNS Query | DNS name resolution made by a specific process |

### Key ECS Fields

| ECS Field | Event IDs | Meaning |
|---|---|---|
| `event.dataset` | all | `windows.sysmon_operational` |
| `event.code` | all | Sysmon Event ID (e.g. `1`, `3`, `22`) |
| `process.name` | 1, 3, 7… | Executable filename |
| `process.command_line` | 1 | Full command line with all arguments |
| `process.executable` | 1 | Full path to the executable |
| `process.parent.name` | 1 | Parent process name |
| `process.hash.sha256` | 1 | Image hash for threat intel lookup |
| `user.name` | 1, 11, 13 | OS user who triggered the event |
| `host.name` | all | Endpoint hostname |
| `network.destination.ip` | 3 | Outbound connection target IP |
| `network.destination.port` | 3 | Outbound connection target port |
| `dns.question.name` | 22 | Domain name resolved by the process |
| `file.path` | 11 | Created or modified file path |
| `registry.path` | 13 | Registry key path modified |

### Sample Hunt Queries

```
# All process creation events
event.dataset: windows.sysmon_operational AND event.code: 1

# PowerShell launched from a suspicious parent (e.g. Word)
event.dataset: windows.sysmon_operational AND event.code: 1
  AND process.name: powershell.exe AND process.parent.name: winword.exe

# Outbound connections to port 4444 (common reverse shell port)
event.dataset: windows.sysmon_operational AND event.code: 3
  AND network.destination.port: 4444

# DNS queries made by cmd.exe (potential C2 beaconing)
event.dataset: windows.sysmon_operational AND event.code: 22
  AND process.name: cmd.exe
```

---

## 2.3 — Elastic Fleet

**Origin:** Elastic  
**Role:** Centralized management console for all Elastic Agent deployments.

Elastic Fleet is the control plane for the host visibility layer. It shows every enrolled endpoint, its health status, the integration policy applied (including which log sources are collected), and the agent version. Students use it to confirm that the Windows victim VM is enrolled and actively shipping data.

`<Insert Screenshot: Elastic Fleet agent detail view showing integration policy, last check-in time, and enrolled integrations>`

**Key tasks:**
- Verify the Windows agent shows **Healthy** status before starting a lab exercise
- Confirm the Sysmon integration is active in the agent's policy
- Check last check-in time — a stale timestamp means the agent is not sending data

---

## 2.4 — Osquery Manager

**Origin:** osquery (Meta/Facebook, now open-source)  
**Role:** Live host interrogation — query current OS state using SQL.

Osquery exposes the operating system as a relational database. Every OS concept — running processes, open sockets, logged-in users, installed software, scheduled tasks, loaded kernel modules — is a SQL table you can query in real time. The SO Osquery Manager dispatches queries to enrolled endpoints and returns results directly in the browser.

`<Insert Screenshot: Osquery Manager interface showing a query input box and tabular results from an enrolled endpoint>`

### Example Queries

```sql
-- What is listening on the network right now?
SELECT pid, family, protocol, local_address, local_port, remote_address, remote_port, state
FROM process_open_sockets
WHERE state = 'LISTEN';

-- Which processes are running and who started them?
SELECT pid, name, path, cmdline, parent
FROM processes
ORDER BY start_time DESC
LIMIT 20;

-- Any suspicious scheduled tasks? (Windows)
SELECT name, action, path, enabled
FROM scheduled_tasks
WHERE enabled = 1;

-- What software is installed? (Windows)
SELECT name, version, install_date
FROM programs
ORDER BY install_date DESC;
```

### Sysmon vs. Osquery — When to Use Each

| | Sysmon | Osquery |
|---|---|---|
| **Data type** | Historical event log | Current OS state snapshot |
| **Question it answers** | What happened, and when? | What is true right now? |
| **Best for** | Attack timeline reconstruction | Live triage and IOC checking |
| **Stored in Elasticsearch?** | Yes | Query results only, on demand |

---

# LAYER 3 — The SOC Web UI

The **Security Onion Console (SOC)** is the unified browser-based interface for interacting with all data collected by Layers 1 and 2. It is built on Kibana but extensively customized by the SO team.

**Access:** `https://<SO_MANAGEMENT_IP>` — log in with the admin credentials set during SO installation.

`<Insert Screenshot: SOC landing page showing the full navigation sidebar and Overview summary widgets>`

---

## 3.1 — Overview

The SOC home page. Shows at-a-glance metrics: alert counts by severity, sensor health, recent detections, and active cases. It is the fastest way to assess current threat posture without running a query.

`<Insert Screenshot: Overview page with alert count widgets, sensor status indicators, and a summary of recent activity>`

---

## 3.2 — Alerts

The primary triage view for Suricata IDS alerts. Alerts are grouped by severity and rule name. Expanding an alert row reveals the full ECS record and exposes action buttons: open in Hunt, retrieve PCAP, attach to a Case, or ask Onion AI.

`<Insert Screenshot: Alerts view showing alert rows with severity badges, rule names, source/destination IPs, and the row expansion panel>`

**Typical triage workflow:**
1. Filter to high severity (`event.severity <= 2`)
2. Identify the source IP and rule category
3. Pivot to Hunt to see what else that IP was doing
4. Retrieve PCAP if protocol-level detail is needed
5. Open a Case to document findings

---

## 3.3 — Hunt

Free-form search across all Elasticsearch data streams. Hunt is the primary investigation workspace — the analyst's query interface for correlating events across Zeek, Suricata, Sysmon, and any other indexed source.

`<Insert Screenshot: Hunt interface showing the query bar with KQL mode selected, the index picker, time picker, and results table>`

### Query Languages

| Language | Best for |
|---|---|
| **KQL** (Kibana Query Language) | Simple `field: value` filtering — recommended starting point |
| **EQL** (Event Query Language) | Sequence detection — "process A, then within 30s process B on the same host" |
| **Lucene** | Advanced text matching with regex and fuzzy operators |

### KQL Syntax

```
field: value                        # exact match
field: value*                       # wildcard suffix
field: value1 OR field: value2      # logical OR
field1: v1 AND field2: v2           # logical AND
NOT field: value                    # negation
field >= 100                        # numeric comparison
```

### Cross-Source Investigation Patterns

**Alert → network context pivot**
```
# 1. Find the alert
event.dataset: suricata.alert AND source.ip: 10.0.2.100

# 2. What other connections did that IP make?
event.dataset: zeek.conn AND source.ip: 10.0.2.100

# 3. Did it resolve suspicious domains?
event.dataset: zeek.dns AND source.ip: 10.0.2.100
```

**Endpoint process → network correlation**
```
# 1. Suspicious process on the endpoint
event.dataset: windows.sysmon_operational AND event.code: 1 AND process.name: mshta.exe

# 2. What network connections did that process make?
event.dataset: windows.sysmon_operational AND event.code: 3 AND process.name: mshta.exe

# 3. Validate against Zeek — did SO see the same destination?
event.dataset: zeek.conn AND destination.ip: <IP from step 2>
```

**Temporal window — all events in a 2-minute attack window**
```
@timestamp >= "2026-06-22T12:05:00" AND @timestamp <= "2026-06-22T12:07:00"
```

---

## 3.4 — Dashboards

Pre-built read-only visualizations aggregating data from all sources. Dashboards reveal trends and distributions at a glance — top source IPs, alert volume over time, DNS query frequency, HTTP status code distribution. They complement Hunt (which answers specific questions) by surfacing patterns you were not specifically looking for.

`<Insert Screenshot: Dashboards landing page showing the list of available dashboards (Network Overview, DNS, HTTP, Suricata Alerts, Endpoint Activity)>`

Common dashboards include: Network Overview, DNS Analysis, HTTP Traffic, Suricata Alert Trends, Endpoint Activity Summary.

---

## 3.5 — Cases

Lightweight case management built into SOC. Analysts create cases to document an investigation — attach relevant alerts, add timestamped notes, set status (Open / In Progress / Closed), and assign to a team member. Cases do not require an external ticketing system.

`<Insert Screenshot: Cases view showing an open case with attached alerts, analyst notes, and status indicator>`

**Typical use:** After Hunt confirms suspicious activity, open a Case, attach the correlated alerts, document the attack chain, and record the recommended remediation steps.

---

## 3.6 — PCAP

Raw packet capture retrieval. Suricata captures full packet data for every alert. The PCAP view lets analysts retrieve a capture by alert action or by manually specifying a flow (source IP, destination IP, ports, time window) and download it as a `.pcap` file for Wireshark analysis.

`<Insert Screenshot: PCAP retrieval panel showing flow filter fields and a download button>`

**Retrieval from an alert:**
1. Expand an alert row in **Alerts**.
2. Click the PCAP icon.
3. SO locates the stored packets for that flow and offers a download.
4. Open in Wireshark for protocol-level inspection.

---

## 3.7 — Onion AI

An LLM-assisted analysis panel native to SOC. Onion AI can summarize an alert in plain English, explain what a Suricata rule detects, suggest follow-up Hunt queries, and provide ATT&CK technique context for observed behavior. It operates on data already in Elasticsearch — nothing leaves the SO instance unless a remote LLM backend is configured.

`<Insert Screenshot: Onion AI panel open alongside an expanded alert, showing a generated plain-English summary>`

> **TFM note:** Onion AI enriches individual alerts one at a time. The TFM fusion layer enriches **correlated multi-source clusters** — a Zeek conn record, a Sysmon network event, and a Suricata alert that all share the same IP and time window, fused into a single object before LLM enrichment. The difference is the unit of analysis: single event vs. correlated cluster.

---

## 3.8 — Grid

Displays the operational health and configuration state of all SO nodes. In a standalone lab deployment there is one node. The navigation warning indicator (⚠) signals a degraded component or configuration issue. Students should check Grid at the start of each session and flag any warnings to the instructor before proceeding.

`<Insert Screenshot: Grid view showing node list with component status indicators and any active warnings highlighted>`

---

## 3.9 — Downloads

Provides installer packages for Elastic Agent — the binary students deploy on the Windows victim VM to enroll it into host visibility. Available as `.exe` for Windows and `.rpm`/`.deb` for Linux.

---

## 3.10 — Administration

SO system configuration surface: user management, sensor tuning, Salt-based component configuration, and license management. Students do not normally enter Administration during lab exercises — it is the instructor's setup panel.

---

# LAYER 4 — Detection Engineering

Detection Engineering in SO means understanding, tuning, and extending the detection capability — knowing what rules exist, why they fire, how to suppress noise, how to decode attacker payloads, and how to map observed techniques to the ATT&CK framework. This layer covers the tools that support that workflow.

---

## 4.1 — Detections

The SO-native rule management interface. The Detections view lists all active detection rules (Suricata signatures and Sigma rules), allows enabling or disabling individual rules, adjusting thresholds, suppressing false positives for known-good traffic, and importing custom rules.

`<Insert Screenshot: Detections view showing rule list with enable/disable toggles, rule name, source ruleset, and last-updated timestamp>`

**Key operations:**
- **Enable/disable rules** — reduce noise from irrelevant rules for the lab environment
- **Suppress** — whitelist a specific source IP or rule + IP combination to eliminate a known false positive
- **Import custom rules** — add a Sigma rule (automatically converted to an ES query) or a raw Suricata `.rules` file
- **Rule updates** — applied via `sudo soup` on the SO manager node; updates both Emerging Threats rules and SO's own detections

### Rule Sources in SO

| Source | Format | Purpose |
|---|---|---|
| Emerging Threats Open | Suricata `.rules` | Network IDS signatures for known malware, exploits, C2 |
| SO Community rules | Sigma / ES Query | Endpoint and log-based behavioral detections |
| Custom imported | Suricata or Sigma | Lab-specific or organization-specific rules |

---

## 4.2 — ATT&CK Navigator (MITRE)

**Origin:** MITRE Corporation  
**Role:** Visual annotation of the MITRE ATT&CK technique matrix.

ATT&CK Navigator is a browser-based tool for mapping which ATT&CK techniques have been observed, detected, or remain blind spots. Analysts color-code technique cells to show coverage, gaps, or incident scope.

`<Insert Screenshot: ATT&CK Navigator showing a partially annotated enterprise matrix with several techniques highlighted in different colors>`

**In detection engineering:**
- Mark which techniques SO's current ruleset covers (green)
- Mark which techniques were observed in a lab attack scenario (red)
- Identify coverage gaps — techniques used in the scenario but not detected by any rule

**Lab use:** After running an Atomic Red Team scenario, map every observed technique to the matrix. Compare against SO's detection coverage. The gap is the answer to: *"what would an attacker do that SO would miss?"*

> **TFM connection:** The TFM fusion engine tags each fused event cluster with ATT&CK technique IDs. Navigator is the natural visualization layer for displaying a multi-stage attack chain produced by the fusion engine.

---

## 4.3 — CyberChef (GCHQ)

**Origin:** GCHQ (UK Government Communications Headquarters), open source  
**Role:** Browser-based data transformation and decoding workbench.

Detection engineering frequently involves decoding attacker payloads found in logs — Base64-encoded PowerShell commands in Sysmon events, hex-encoded shellcode in HTTP POST bodies, compressed scripts, XOR-obfuscated C2 traffic. CyberChef chains transformation operations into a "recipe" to decode these step by step.

`<Insert Screenshot: CyberChef showing a recipe with "From Base64" → "Remove null bytes" applied to an encoded PowerShell command, revealing plaintext>`

### Common Recipe Operations

| Operation | Use case |
|---|---|
| From Base64 | Decode Base64-encoded PowerShell `-enc` arguments |
| URL Decode | Decode percent-encoded characters in HTTP URIs |
| From Hex | Decode hex-represented shellcode or file content |
| Gunzip / Inflate | Decompress compressed payloads delivered in-stream |
| To/From Charcode | Decode character-code obfuscation |
| XOR Brute Force | Attempt to recover XOR-obfuscated payloads |
| Extract IP addresses | Parse IPs out of a raw log block |
| Magic | Auto-detect encoding — useful when you do not know the encoding scheme |

**Workflow:** A Sysmon Event ID 1 shows `process.command_line: powershell.exe -enc SQBuAHYAbwBrAGU...`. Paste the encoded value into CyberChef → apply `From Base64` → `Remove null bytes` → read the plaintext command. This tells you what the attacker actually executed without running the payload.

---

## 4.4 — Kibana (Raw Interface)

**Origin:** Elastic  
**Role:** Full-featured Elasticsearch analytics and visualization UI — the engine underneath SOC.

The SOC UI is itself built on Kibana, but SO's customization hides many of Kibana's native features. The raw Kibana link (in the Tools section of the sidebar) bypasses those customizations and exposes:

- **Discover** — direct field-by-field document browser with the complete field list
- **Lens** — drag-and-drop visualization builder for custom dashboards
- **Dev Tools** — Elasticsearch REST API console for running raw ES queries (`_search`, `_mapping`, `_stats`)
- **Index Management** — view data stream sizes, shard health, and retention policies

`<Insert Screenshot: Kibana Dev Tools console showing a raw _search query and its JSON response>`

**When to use raw Kibana over Hunt:**
- Inspecting field mappings when a Hunt query returns no results (field may be `keyword` vs. `text`)
- Building a visualization that is not available in the SO Dashboards view
- Running aggregation queries (e.g. "count of alerts by rule category over the last 7 days") via the ES REST API

---

## 4.5 — InfluxDB

**Origin:** InfluxData  
**Role:** Time-series database for SO system performance metrics.

InfluxDB stores SO's own operational telemetry: CPU and memory consumption per component, disk I/O, network throughput. It powers the node health indicators visible in Grid. Lab students do not query InfluxDB directly — it is a system administration tool used to diagnose performance issues in the SO node.

`<Insert Screenshot: InfluxDB UI showing SO node CPU and memory metrics over the last 24 hours>`

---

# Appendix A — ECS Quick Reference Card

All events from all sources land in Elasticsearch normalized to ECS. The fields below appear across Zeek, Suricata, and Sysmon records.

| Field | Type | Primary source | Example value |
|---|---|---|---|
| `@timestamp` | date | all | `2026-06-22T12:06:33.000Z` |
| `event.dataset` | keyword | all | `zeek.dns`, `suricata.alert`, `windows.sysmon_operational` |
| `event.code` | keyword | Sysmon | `1`, `3`, `22` |
| `event.severity` | long | Suricata | `1` (critical) – `4` (info) |
| `source.ip` | ip | network | `10.0.2.100` |
| `source.port` | long | network | `54321` |
| `destination.ip` | ip | network | `93.184.216.34` |
| `destination.port` | long | network | `443` |
| `network.protocol` | keyword | Zeek conn | `tcp` |
| `network.transport` | keyword | Suricata | `tcp` |
| `dns.question.name` | keyword | Zeek dns, Sysmon 22 | `evil.example.com` |
| `http.request.body.uri` | keyword | Zeek http | `/admin/upload.php` |
| `tls.server_name` | keyword | Zeek ssl | `api.example.com` |
| `rule.name` | keyword | Suricata | `ET SCAN Nmap -sS` |
| `rule.id` | keyword | Suricata | `2000537` |
| `process.name` | keyword | Sysmon 1, 3… | `powershell.exe` |
| `process.command_line` | keyword | Sysmon 1 | `powershell.exe -enc SQBu…` |
| `process.parent.name` | keyword | Sysmon 1 | `winword.exe` |
| `user.name` | keyword | Sysmon | `VICTIM\jsmith` |
| `host.name` | keyword | Sysmon | `VICTIM-PC` |
| `file.path` | keyword | Sysmon 11 | `C:\Users\jsmith\evil.exe` |
| `registry.path` | keyword | Sysmon 13 | `HKLM\Software\Microsoft\…` |

---

# Appendix B — Gap Summary (Student Reading)

Security Onion is a powerful platform. Understanding its limitations is as important as understanding its capabilities — these gaps define where additional tooling (including the TFM fusion layer) adds value.

| Gap | Detail |
|---|---|
| **No cross-source correlation** | A Zeek `conn` event and a Sysmon process event involving the same IP at the same time are stored as independent records. SO does not automatically link them. |
| **No temporal attack chain reconstruction** | SO shows individual events chronologically but does not group them into "this sequence = stage 1 → stage 2 → stage 3 of an attack." |
| **No ATT&CK stage tagging** | Suricata rules may reference ATT&CK in metadata, but there is no automatic mapping of a correlated event cluster to a complete ATT&CK tactic sequence. |
| **No structured threat intelligence export** | SO does not produce STIX 2.1 bundles or publish intelligence to a TAXII server. |
| **Single-event LLM enrichment** | Onion AI enriches one alert at a time. There is no mechanism to fuse related events into a cluster and enrich the cluster as a whole. |

These gaps are the starting point for Lab Exercise 4 (Cross-Source Correlation) and Lab Exercise 5 (Fusion Output), and form the core motivation for the TFM architecture.
