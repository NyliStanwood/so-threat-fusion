# Security Onion 2.4 — Feature & Capability Survey
## Lab Reference Document — Draft 2 (Organized by the SO web-UI)

**SO version:** 2.4.211  
**Audience:** University cybersecurity lab students (introductory–intermediate level)  
**Purpose:** Familiarise students with each major SO component before working through lab exercises.

---

## What Is Security Onion?

Security Onion is an open-source Linux distribution designed for network security monitoring (NSM), intrusion detection, and log management. It integrates multiple best-of-breed tools under a single unified web interface — the Security Onion Console (SOC).

In this lab, SO runs as a **standalone node**: all components (sensors, storage, and UI) are on one virtual machine.

```
Traffic on internal-network
        ↓
  [ Zeek ]      → network protocol metadata (conn, DNS, HTTP, SSL…)
  [ Suricata ]  → IDS signature alerts + PCAP
        ↓
  [ Logstash ]  → parsing and ECS normalization
        ↓
  [ Elasticsearch ] → indexed storage
        ↓
  [ SOC Web UI ]    → Alerts · Hunt · Dashboards · PCAP · Cases
```

Endpoint telemetry (Windows event logs, Sysmon) flows through **Elastic Agent**, deployed on monitored hosts, and lands in the same Elasticsearch storage.

All log data is normalized to the **Elastic Common Schema (ECS)** — a standardized field naming convention that makes querying consistent regardless of the original log source.

---

# PART 1 — Security Onion Native Tools

These are components designed and maintained by the Security Onion Solutions team. They form the SOC web interface and the SO-specific management and detection layers.

---

## 1.1 — Overview

The SOC home page. Displays high-level metrics at a glance: alert counts by severity, active sensor status, recent detections, and system health indicators. It is the landing page after login and the fastest way to assess the current threat posture of the monitored network.

**Access:** `https://<SO_MANAGEMENT_IP>` — displayed immediately after login.

`<Insert Screenshot: SOC Overview page showing summary widgets, alert counts, and sensor status>`

---

## 1.2 — Onion AI

An LLM-assisted analysis feature native to SOC. Onion AI can summarize alerts, explain rule logic, suggest pivot queries, and provide context on observed techniques. It operates on the event data already in Elasticsearch — no external data leaves the SO instance unless a cloud LLM backend is configured.

`<Insert Screenshot: Onion AI panel open alongside an alert, showing a generated summary or explanation>`

> **TFM note:** Onion AI is SO's built-in LLM integration. The TFM project independently evaluates GPT-4o and Mistral 7B against fused cluster outputs — a complementary but distinct workflow. Comparing Onion AI's single-event summaries against TFM's multi-source fused cluster enrichment is a useful framing for the thesis gap analysis.

---

## 1.3 — Alerts

The primary triage view for Suricata IDS alerts. Alerts are grouped by severity and rule name, with source/destination IP, port, and timestamp visible per row. Expanding a row reveals the full ECS record and provides action buttons for PCAP retrieval, Hunt pivot, and case attachment.

`<Insert Screenshot: Alerts view showing a list of Suricata alerts with severity badges, rule names, and source/destination fields>`

### Alert Severity Scale (Suricata)

| `event.severity` value | Label | Meaning |
|---|---|---|
| 1 | Critical | Active exploit or confirmed malware traffic |
| 2 | Major | High-confidence suspicious activity |
| 3 | Minor | Policy violations, low-confidence suspicious patterns |
| 4 | Informational | Scanning, reconnaissance, general visibility |

### Key Alert Fields

| ECS Field | Meaning |
|---|---|
| `rule.name` | Human-readable rule description (e.g. `ET SCAN Nmap -sS`) |
| `rule.id` | Numeric Suricata SID |
| `rule.category` | Alert category (e.g. `Attempted Reconnaissance`) |
| `event.severity` | 1–4 severity scale |
| `source.ip` / `destination.ip` | Network endpoints |
| `destination.port` | Targeted service port |

### Sample Queries

```
# All Suricata alerts
event.dataset: suricata.alert

# High-severity alerts only (1 or 2)
event.dataset: suricata.alert AND event.severity <= 2

# Alerts from a specific source IP
event.dataset: suricata.alert AND source.ip: 10.0.2.100

# Alerts matching a keyword in the rule name
event.dataset: suricata.alert AND rule.name: *scan*
```

---

## 1.4 — Dashboards

Pre-built visualizations surfacing aggregated views of Zeek, Suricata, and endpoint data. Dashboards are read-only summary views — useful for identifying trends, top talkers, and unusual protocol distributions. Unlike Hunt, they do not support arbitrary free-form queries.

`<Insert Screenshot: Dashboards landing page showing available dashboard tiles (Zeek, Suricata, Overview)>`

Common dashboards include network overview, DNS analysis, HTTP traffic, Suricata alert trends, and endpoint activity summaries.

---

## 1.5 — Hunt

Free-form search across all Elasticsearch indices. Hunt is the primary investigation workspace — it supports KQL, EQL, and Lucene query languages and allows pivoting between log sources within a single session.

`<Insert Screenshot: Hunt interface showing the query bar, index selector, time picker, and results table with ECS fields>`

### Supported Query Languages

| Language | Best for |
|---|---|
| **KQL** (Kibana Query Language) | Simple `field: value` filtering — recommended for beginners |
| **EQL** (Event Query Language) | Sequence detection — "process A then process B within 5 seconds" |
| **Lucene** | Advanced text search with regex and fuzzy matching |

### KQL Syntax Reference

```
field: value                        # exact match
field: value*                       # wildcard
field: value1 OR field: value2      # logical OR
field1: value1 AND field2: value2   # logical AND
NOT field: value                    # negation
field >= 100                        # numeric comparison
```

### Index Structure

| Data stream | Contents |
|---|---|
| `logs-zeek-so` | All Zeek logs (conn, dns, http, ssl…) |
| `logs-suricata-so` | Suricata alerts and stats |
| `logs-windows-so` | Windows event logs + Sysmon |
| `logs-so.*` | SO internal management events |

### Common Investigation Patterns

**Pattern 1 — Alert → context pivot**
```
# Find the alert
event.dataset: suricata.alert AND source.ip: 10.0.2.100

# What else was that IP doing?
event.dataset: zeek.conn AND source.ip: 10.0.2.100

# Did it resolve any suspicious domains?
event.dataset: zeek.dns AND source.ip: 10.0.2.100
```

**Pattern 2 — Follow a suspicious process on the endpoint**
```
# Find the suspicious process creation
event.dataset: windows.sysmon_operational AND event.code: 1 AND process.name: mshta.exe

# What network connections did it make?
event.dataset: windows.sysmon_operational AND event.code: 3 AND process.name: mshta.exe

# Cross-reference with Zeek on the same destination IP
event.dataset: zeek.conn AND destination.ip: <IP from step 2>
```

**Pattern 3 — Temporal scoping (all events in a 2-minute window)**
```
@timestamp >= "2026-06-22T12:05:00" AND @timestamp <= "2026-06-22T12:07:00"
```

---

## 1.6 — Cases

Lightweight case management built into SOC. Analysts attach alerts, add investigation notes, assign status labels, and track findings across a session. Cases do not require an external ticketing system.

`<Insert Screenshot: Cases view showing an open case with attached alerts and analyst notes>`

Typical workflow: once an investigation in Hunt or Alerts identifies a confirmed or suspected incident, the analyst creates a Case, attaches the relevant alert records, and documents findings and recommended remediation steps.

---

## 1.7 — Detections

The Detections view manages SO's local detection rule sets. Analysts can review enabled rules, modify rule thresholds, suppress false positives, and import custom Sigma or Suricata rules. This is the configuration surface for what triggers alerts in Section 1.3.

`<Insert Screenshot: Detections view showing rule list with enable/disable toggles and rule metadata>`

SO ships with the **Emerging Threats Open** ruleset pre-loaded. Updates are applied via `sudo soup`.

---

## 1.8 — PCAP

Raw packet capture retrieval. For any Suricata alert, SO stores the associated network packets. The PCAP view lets analysts retrieve a capture by flow (source IP, destination IP, port, timestamp) or directly from an alert action.

`<Insert Screenshot: PCAP retrieval dialog showing flow parameters and download button>`

**Retrieval workflow:**
1. Expand an alert row in the Alerts view.
2. Click the PCAP icon.
3. SO retrieves packets for that flow and offers a `.pcap` download.
4. Open in Wireshark for protocol-level inspection.

---

## 1.9 — Grid

The Grid view displays the health and configuration of all SO nodes (sensors, search nodes, manager). In a standalone lab deployment there is only one node. The warning indicator visible in the navigation (⚠) signals a configuration issue or degraded component — students should note any Grid warnings at the start of each lab session.

`<Insert Screenshot: Grid view showing node list, component status, and any active warnings>`

---

## 1.10 — Downloads

Provides downloads for SO agent installers and configuration files — primarily the Elastic Agent installer packages for deploying endpoint monitoring on Windows or Linux VMs. Students use this when enrolling the Windows victim VM into Elastic Fleet.

`<Insert Screenshot: Downloads page showing available agent packages>`

---

## 1.11 — Administration

SO system configuration and management panel. Covers user management, license status, sensor configuration, and Salt-based configuration management for SO components. Lab exercises do not normally require students to enter Administration; it is the instructor's configuration surface.

---

# PART 2 — External Tools Bundled with Security Onion

These are independent open-source projects that SO ships as part of its distribution. They are accessible from the **Tools** section in the SOC navigation sidebar. Each tool has its own upstream community and documentation independent of Security Onion.

---

## 2.1 — Kibana (Elastic)

**Origin:** Elastic (elastic.co)  
**Role:** Full-featured analytics and visualization UI for Elasticsearch.

The SOC web interface (Part 1) is itself built on Kibana but with substantial SO customization layered on top. The raw Kibana link in Tools bypasses the SOC customizations and exposes Kibana's native interface — including Discover, Lens visualizations, and the full index management console.

`<Insert Screenshot: Kibana Discover view showing raw Elasticsearch documents and the full field list>`

**When students use raw Kibana:**
- Building custom visualizations not available in Dashboards
- Accessing field statistics and index mappings
- Advanced query debugging with the Kibana Dev Tools console (REST API access to Elasticsearch)

> SO uses Kibana's Discover as the engine behind Hunt. Understanding both surfaces helps when troubleshooting why a Hunt query returns unexpected results.

---

## 2.2 — Elastic Fleet

**Origin:** Elastic  
**Role:** Centralized management console for Elastic Agent deployments across all enrolled endpoints.

Elastic Fleet is the control plane for endpoint monitoring. It shows which hosts have Elastic Agent installed, their enrollment status, the integration policies applied (including Sysmon log collection), and agent version information.

`<Insert Screenshot: Elastic Fleet main view showing enrolled agents table with hostname, status, version, and policy columns>`

**Key tasks in Elastic Fleet for lab setup:**
- Verifying that the Windows victim VM agent is enrolled and sending data
- Checking integration policy to confirm Sysmon log collection is active
- Reviewing agent health and connectivity status

---

## 2.3 — Osquery Manager

**Origin:** osquery (originally developed by Facebook/Meta, now open source)  
**Role:** Live host interrogation using SQL queries against the operating system.

Osquery exposes the OS state (running processes, open network connections, loaded modules, user accounts, scheduled tasks, etc.) as SQL-queryable tables. The SO Osquery Manager provides a web interface to write and dispatch queries to enrolled hosts and view results in near-real time.

`<Insert Screenshot: Osquery Manager query interface showing a sample query and tabular results from an enrolled endpoint>`

**Example queries:**

```sql
-- List all listening network sockets
SELECT pid, family, protocol, local_address, local_port, remote_address, remote_port, state
FROM process_open_sockets
WHERE state = 'LISTEN';

-- List running processes with their parent
SELECT pid, name, path, cmdline, parent
FROM processes
ORDER BY start_time DESC
LIMIT 20;

-- Check for suspicious scheduled tasks (Windows)
SELECT name, action, path, enabled
FROM scheduled_tasks;
```

**Difference from Sysmon:** Sysmon records historical events (what happened). Osquery answers current-state questions (what is happening right now). Both are valuable in an investigation — Sysmon for timeline reconstruction, Osquery for live triage.

---

## 2.4 — InfluxDB

**Origin:** InfluxData  
**Role:** Time-series database storing SO system performance metrics.

InfluxDB holds SO's internal operational telemetry: CPU, memory, disk I/O, and network throughput per node. It powers SO's internal health monitoring rather than security event data. Lab students do not normally query InfluxDB directly; it is primarily used by SO administrators to identify performance bottlenecks or resource constraints.

`<Insert Screenshot: InfluxDB dashboard showing SO node performance metrics over time>`

---

## 2.5 — CyberChef (GCHQ)

**Origin:** GCHQ (UK Government Communications Headquarters), open source  
**Role:** Browser-based data transformation and decoding toolkit.

CyberChef is a multi-step data manipulation workbench. Analysts paste raw data (Base64-encoded payloads, hex strings, encoded URLs, obfuscated scripts) and chain transformation operations to decode or decode it.

`<Insert Screenshot: CyberChef interface showing a recipe chain decoding a Base64 payload to reveal a PowerShell command>`

**Common operations in investigation workflows:**

| Operation | Use case |
|---|---|
| From Base64 | Decode Base64-encoded payloads in PowerShell commands |
| URL Decode | Decode percent-encoded URLs from HTTP logs |
| From Hex | Decode hex-encoded shellcode or file content |
| Extract IP addresses | Pull IPs out of a block of log text |
| Gunzip / Inflate | Decompress compressed payloads |
| To/From Charcode | Decode character-code obfuscation |
| XOR Brute Force | Attempt to break simple XOR-encoded payloads |

**Lab use:** When a Sysmon Process Create event shows a heavily encoded PowerShell command line, paste the encoded string into CyberChef, apply `From Base64` → `Remove null bytes`, and recover the plaintext command.

---

## 2.6 — Navigator (MITRE ATT&CK Navigator)

**Origin:** MITRE Corporation  
**Role:** Visual mapping of observed techniques to the MITRE ATT&CK framework matrix.

ATT&CK Navigator is a web-based tool for annotating and comparing technique coverage on the ATT&CK matrix. Analysts color-code techniques to show which are observed in an incident, which are covered by current detections, or which are in scope for a given threat actor profile.

`<Insert Screenshot: ATT&CK Navigator showing a partially annotated ATT&CK matrix with highlighted techniques>`

**Lab use:**
- Map techniques observed in a lab attack scenario to the ATT&CK matrix
- Compare SO's detection coverage against the techniques used in an Atomic Red Team test
- Visualize lateral movement chains as a sequence of ATT&CK sub-techniques

**TFM use:** The TFM fusion engine will tag fused event clusters with ATT&CK technique IDs. Navigator is the natural visualization layer for displaying fusion output as an attack chain on the ATT&CK matrix.

---

# Appendix A — Zeek (Network Analysis Framework)

`Origin: Corelight / open-source community | Managed by: Security Onion`

Zeek runs on SO's monitoring interface in promiscuous mode. It does **not** generate alerts — instead it produces structured **metadata logs** for every observed network connection and protocol interaction.

### Log Types (Index: `logs-zeek-so`)

| Log | `event.dataset` value | What it captures |
|---|---|---|
| `conn.log` | `zeek.conn` | Every TCP/UDP/ICMP flow: duration, bytes, state |
| `dns.log` | `zeek.dns` | DNS queries and responses |
| `http.log` | `zeek.http` | HTTP requests: method, URI, status code, user-agent |
| `ssl.log` | `zeek.ssl` | TLS handshake metadata: SNI, cipher, certificate validity |
| `files.log` | `zeek.files` | File transfers: MIME type, MD5/SHA1 hash, source |
| `weird.log` | `zeek.weird` | Protocol anomalies Zeek cannot parse cleanly |
| `notice.log` | `zeek.notice` | Zeek's own detection notices (e.g. scanning behavior) |

`<Insert Screenshot: Hunt view filtered to event.dataset: zeek.dns, showing several DNS query records>`

### Key ECS Fields

| ECS Field | Log | Typical query use |
|---|---|---|
| `source.ip` / `destination.ip` | conn, dns, http… | Who talked to whom |
| `destination.port` | conn | What service was targeted |
| `network.protocol` | conn | `tcp`, `udp`, `icmp` |
| `network.bytes` | conn | Total bytes transferred |
| `dns.question.name` | dns | Domain queried |
| `dns.question.type` | dns | `A`, `AAAA`, `MX`, `TXT`… |
| `http.request.method` | http | `GET`, `POST`, `PUT`… |
| `http.request.body.uri` | http | Requested URI path |
| `http.response.status_code` | http | `200`, `404`, `500`… |
| `user_agent.original` | http | Browser or tool user-agent string |
| `tls.server_name` | ssl | SNI hostname in TLS handshake |
| `file.hash.md5` | files | File hash for threat intel lookups |

### Sample Queries

```
# All DNS queries in the last hour
event.dataset: zeek.dns AND @timestamp > now-1h

# Connections to port 445 (SMB)
event.dataset: zeek.conn AND destination.port: 445

# HTTP requests to a suspicious URI
event.dataset: zeek.http AND http.request.body.uri: *passwd*
```

---

# Appendix B — Suricata (IDS)

`Origin: Open Information Security Foundation (OISF) | Managed by: Security Onion`

Suricata is a signature-based **Intrusion Detection System**. It inspects packets against a ruleset and generates an alert when traffic matches a known-bad pattern. SO ships with the **Emerging Threats Open** ruleset and also writes full packet captures (PCAP) for each alert.

`<Insert Screenshot: Alerts view showing a list of Suricata alerts with severity, rule name, and source/destination fields>`

### Key ECS Fields

| ECS Field | Meaning |
|---|---|
| `event.dataset` | `suricata.alert` for IDS alerts |
| `rule.name` | The Suricata rule description |
| `rule.id` | Numeric signature ID (SID) |
| `rule.category` | Alert category |
| `event.severity` | 1 = Critical, 2 = Major, 3 = Minor, 4 = Info |
| `source.ip` / `destination.ip` | Attacker / target |
| `destination.port` | Targeted service port |
| `network.transport` | `tcp`, `udp` |

---

# Appendix C — Elastic Agent + Sysmon (Endpoint Telemetry)

`Origin: Elastic (Agent) + Microsoft Sysinternals (Sysmon) | Managed by: Security Onion via Elastic Fleet`

Elastic Agent deployed on endpoint VMs ships host telemetry to SO's Elasticsearch. On Windows hosts, it works alongside **Sysmon**, which logs detailed process, file, network, and registry activity to the Windows Event Log.

### Sysmon Event IDs

| Event ID | Name | What it records |
|---|---|---|
| 1 | Process Create | New process: name, PID, parent, command line, hash |
| 3 | Network Connection | Process making a network connection: IP, port, process |
| 5 | Process Terminate | Process exit |
| 7 | Image Load | DLL loaded by a process |
| 8 | CreateRemoteThread | Thread injection indicator |
| 10 | ProcessAccess | Process accessing another process's memory (credential dumping) |
| 11 | File Create | File created or overwritten |
| 13 | Registry Value Set | Registry modification |
| 22 | DNS Query | DNS resolution by a process (which process queried what domain) |

### Key ECS Fields

| ECS Field | Sysmon Event ID | Meaning |
|---|---|---|
| `event.dataset` | all | `windows.sysmon_operational` |
| `event.code` | all | Sysmon Event ID (e.g. `1`, `3`, `22`) |
| `process.name` | 1, 3, 7… | Executable filename |
| `process.command_line` | 1 | Full command line with arguments |
| `process.parent.name` | 1 | Parent process name |
| `process.hash.sha256` | 1 | Process image hash |
| `user.name` | 1, 11, 13 | OS user who triggered the event |
| `host.name` | all | Endpoint hostname |
| `network.destination.ip` | 3 | Outbound connection target |
| `network.destination.port` | 3 | Outbound connection port |
| `dns.question.name` | 22 | Domain queried by a specific process |
| `file.path` | 11 | Created or modified file path |
| `registry.path` | 13 | Registry key path modified |

### Sample Queries

```
# All Sysmon process creation events
event.dataset: windows.sysmon_operational AND event.code: 1

# PowerShell executions
event.dataset: windows.sysmon_operational AND event.code: 1 AND process.name: powershell.exe

# Process making a network connection to port 4444 (common reverse shell)
event.dataset: windows.sysmon_operational AND event.code: 3 AND network.destination.port: 4444

# DNS queries made by a specific process
event.dataset: windows.sysmon_operational AND event.code: 22 AND process.name: cmd.exe
```

---

# Appendix D — ECS Quick Reference Card

The fields below are used across all log sources in this lab.

| Field | Type | Source | Example value |
|---|---|---|---|
| `@timestamp` | date | all | `2026-06-22T12:06:33.000Z` |
| `event.dataset` | keyword | all | `zeek.dns`, `suricata.alert` |
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
| `process.command_line` | keyword | Sysmon 1 | `powershell.exe -enc …` |
| `process.parent.name` | keyword | Sysmon 1 | `winword.exe` |
| `user.name` | keyword | Sysmon | `VICTIM\jsmith` |
| `host.name` | keyword | Sysmon | `VICTIM-PC` |
| `file.path` | keyword | Sysmon 11 | `C:\Users\jsmith\evil.exe` |

---

# Appendix E — Gap Summary (Student Reading)

Security Onion is a powerful platform, but students should understand what it does **not** do natively — these gaps are precisely where the TFM fusion layer adds value:

| Gap | Why it matters |
|---|---|
| **No cross-source correlation** | A Zeek conn event and a Sysmon process event at the same time involving the same IP are stored separately; SO does not link them automatically. |
| **No temporal attack chain reconstruction** | SO shows individual events but does not group them into "stage 1 → stage 2 → stage 3 of an attack." |
| **No ATT&CK stage tagging** | Alerts are rule-based; there is no automatic mapping of observed behaviour to MITRE ATT&CK tactics and techniques. |
| **No structured threat intelligence export** | SO does not produce STIX 2.1 bundles or publish to a TAXII server. |

These gaps are explored in Lab Exercise 4 (Cross-Source Correlation) and Lab Exercise 5 (Fusion Output).
