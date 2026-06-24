# Teaching SO Laboratory — Plan

**Companion to:** [Planning.md](Planning.md)  
**Goal:** Produce a reusable university cybersecurity teaching lab built on Security Onion, with consistent data, documented exercises, and deployment instructions suited to academic infrastructure.

---

## How This Relates to Planning.md

The TFM and the Teaching Lab share large overlapping work. Rather than doing both separately, the phases below are designed to **absorb or extend** the original Planning.md phases wherever possible. Phases that can be fully merged are marked **[MERGE → Planning PhaseX]**; phases that run in parallel are marked **[PARALLEL]**; phases that are net new are marked **[NEW]**.

| Lab Phase | Merges With | Relationship |
|---|---|---|
| L0 — Deployment Research | Planning Phase 0 | Full merge — deployment research IS lab setup |
| L1 — SO Feature Research | Planning Phase 1 | Full merge — feature survey IS gap analysis context |
| L2 — Data Injection | Planning Phase 0 + Phase 5 | Partial merge — share scenario selection; lab adds PCAP/offline path |
| L3 — Lab Instructions | Planning Phase 6 | Parallel — write lab guide while writing thesis; same material, different audience |

---

## Phase L0 — Deployment Research
**[MERGE → Planning Phase 0]**  
**Duration: 1–2 weeks (no additional time beyond Planning Phase 0)**

The original Phase 0 covers standing up a standalone SO VM for the TFM. This phase extends that work to answer the question: *how would we replicate this in a university environment?*

### The Core University Constraint

University lab computers typically have 8–16 GB RAM and shared storage. A full SO standalone node needs 16–24 GB RAM. This means a single student per machine running a full SO node is **not viable** in most labs. The viable options are:

| Deployment Model | RAM Needed | Students per Node | Viable? | Notes |
|---|---|---|---|---|
| Full standalone per student | 16–24 GB | 1 | Only with high-spec machines | Each student has own data, most flexible |
| Shared standalone, browser access | 16–24 GB | 5–15 | **Yes — preferred** | SO web UI is browser-based; one shared node works well |
| SO Import node per student | 4 GB | 1 | **Yes** | Offline PCAP/EVTX analysis only; no live traffic; great for structured exercises |
| Cloud-hosted node (AWS/Azure) | n/a | 5–15 | Yes if budget allows | SO has AWS AMI; good for remote/hybrid courses |
| Proxmox cluster (university server) | 32–64 GB total | 10–20 | **Yes — best long-term** | One powerful server, multiple lightweight VMs via Proxmox |

**Recommended approach for most universities:** One shared SO Standalone VM running on a department server (Proxmox or ESXi), with students accessing the SOC web UI via browser. Pre-loaded with injected attack scenarios (Phase L2).

### Can SO Be Dockerized?

**No — not officially.** Security Onion is a full Linux distribution that manages itself with Salt (a configuration management system). The entire stack (Elasticsearch, Logstash, Zeek, Suricata, the SOC UI, etc.) is orchestrated by Salt running as root. Containerizing the full platform is not supported and not practical.

**What CAN be run in Docker:**
- OpenTAXII (already in the TFM plan)
- MISP (optional SO integration)
- Individual components for development/testing (Elasticsearch alone, Kibana alone)
- A mock data generator that produces ECS-format events and pushes to a standalone ES

**For teaching purposes:** running individual components in Docker is valuable as a learning exercise even if the full SO is not Dockerized.

### Can Features Be Selectively Disabled?

**Yes.** SO uses Salt for all configuration. From the SOC web UI (Administration → Configuration), you can enable or disable:
- Suricata (detection engine)
- Zeek (protocol metadata)
- Strelka (file analysis) — high CPU, safe to disable in low-traffic labs
- Elastic Agent fleet (required for host telemetry)
- MISP, TheHive integrations
- Full PCAP storage (huge disk saver — disable to cut storage by 80%)

**For a lightweight lab deployment**, disabling Strelka and full PCAP reduces RAM and disk pressure significantly while keeping all alert/log functionality intact.

### Hypervisor Compatibility

| Hypervisor | Notes |
|---|---|
| **VMware Workstation/ESXi** | Officially supported; best performance |
| **VirtualBox** | Supported; works but slower; virtio drivers recommended |
| **Proxmox VE** | Supported; ideal for a shared lab server |
| **Hyper-V** | Supported in v2.4; enable Enhanced Session Mode |
| **KVM/QEMU** | Supported on Linux hosts |

### Deliverables for L0
- [ ] Document the chosen university deployment model with hardware requirements
- [ ] Test the SO Import node deployment (4 GB RAM path) — confirm students can load PCAP/EVTX and see data in SOC
- [ ] Document which SO components to disable for a resource-constrained environment
- [ ] Write a one-page "university sysadmin setup guide": hypervisor, VM specs, network config, firewall rules, how to create student accounts in SOC

---

## Phase L1 — SO Feature & Capability Research
**[MERGE → Planning Phase 1]**  
**Duration: 1–2 weeks (adds ~1 week to original Phase 1)**

The original Phase 1 (Gap Analysis) focuses on what SO *misses*. This phase broadens that to also document what SO *does well* — so students get a complete picture before being shown the gap.

### What to Research and Document

#### Network Visibility Layer
- **Zeek:** What protocol metadata it generates by default (conn.log, dns.log, http.log, ssl.log, files.log, x509.log). What each log field means. When it appears and when it doesn't.
- **Suricata:** How IDS rules work, what a Suricata alert record contains, how to read rule syntax, how to add/modify rules via SOC UI (not manual file edits). The Suricata ET Open ruleset included by default.
- **Full PCAP:** How SO stores PCAPs (Suricata writes them with lz4 compression), how to retrieve a PCAP for a specific alert via the SOC UI, how to open in Wireshark.
- **Strelka:** What file types it analyzes (PE, PDF, Office documents extracted from network traffic), what a Strelka result looks like in Elasticsearch.

#### Host Visibility Layer
- **Elastic Agent:** How it's deployed to endpoints, what the Fleet UI looks like, what data it ships.
- **Sysmon:** The 29 event IDs and which matter for detection (Event ID 1 process creation, 3 network connection, 7 DLL load, 10 process access, 13 registry value set). The Sysmon config XML and how it controls verbosity.
- **osquery:** How to run live queries via SO (osquery pack integration), what tables are available, example queries (running processes, open sockets, logged-in users).

#### The SOC Web UI
- **Alerts view:** How to triage an alert, escalate to a case, add a comment.
- **Hunt view:** Free-form log search with filters — the analyst workbench.
- **PCAP retrieval:** Pivot from an alert to the raw PCAP for that connection.
- **Cases:** Basic case management — create a case, link alerts, assign to analyst.
- **Dashboards (Kibana):** Pre-built SO dashboards vs. custom Kibana dashboards.
- **CyberChef:** What it is, built-in examples (base64 decode, XOR, regex extraction).
- **Grid (SO's Elasticsearch query tool):** Direct ES query UI without leaving SOC.

#### Detection Engineering
- **Suricata rule syntax:** `alert`, `content`, `pcre`, `metadata`, `threshold` directives. How to write a basic rule.
- **Sigma rules:** How SO ingests Sigma, what the conversion pipeline looks like, how to add a community Sigma rule.
- **YARA rules:** If Strelka is enabled, how SO applies YARA signatures to extracted files.

#### What SO Does NOT Do (Gap Section)
This is the original Phase 1 content — cross-source correlation absence, no ATT&CK stage inference, no confidence scoring, no STIX/TAXII native export. See [SecurityOnion-Overview.md](docs/SecurityOnion-Overview.md#what-security-onion-does-not-do).

### Deliverables for L1
- [ ] SO Feature Survey document (~5 pages): one section per major component with screenshots, example log records, key ECS fields students will query
- [ ] Gap analysis document (2–3 pages, originally Phase 1 deliverable) — now framed as "here's what SO gives you, and here's where it stops"
- [ ] Student-facing "SO Component Quick Reference" — one-page cheat sheet: component name, what it does, where to find it in SOC, example query

---

## Phase L2 — Data Injection Strategy
**[MERGE PARTIAL → Planning Phase 0 + Phase 5]**  
**Duration: 1–2 weeks (adds ~1 week to original Phase 0)**

For a teaching lab to work, students need consistent, pre-loaded data. They cannot wait for organic attack traffic or run their own attack VMs. This phase designs and implements the data injection pipeline.

### Two Paths: Live vs. Offline

| Path | How | When to Use |
|---|---|---|
| **Live simulation** | Atomic Red Team / Caldera on an attack VM in the lab network; SO captures live | TFM evaluation (Planning Phase 5), advanced lab sessions |
| **Offline import** | Pre-captured PCAPs + EVTX files replayed into SO Import node | Standard classroom labs — consistent, repeatable, no live malware |

**For the teaching lab, the offline path is primary.** It is:
- Safe (no live malware/exploits on university networks)
- Consistent (every student sees identical data)
- Reproducible (re-inject any time without re-running attacks)
- Fast to reset (snapshot the clean VM, restore, re-inject)

### Offline Data Sources (Curated, Free, ATT&CK-Mapped)

| Dataset | Contents | ATT&CK Coverage | Best For |
|---|---|---|---|
| **EVTX-ATTACK-SAMPLES** (sbousseaden/GitHub) | ~250 Windows EVTX files, one per ATT&CK technique | Excellent — one file = one technique | Sysmon/Windows host exercises |
| **Malware Traffic Analysis PCAPs** (malware-traffic-analysis.net) | Real malware C2, lateral movement, exfil PCAPs | Good | Suricata alert analysis |
| **CICIDS2017** (Univ. of New Brunswick) | Labeled network attack dataset (DDoS, brute force, web attacks) | Moderate | Network detection baseline comparison |
| **UNSW-NB15** | Modern hybrid attack dataset | Good | Anomaly detection context |
| **Atomic Red Team PCAP captures** | Capture from your own ART runs (Planning Phase 0) | Excellent — mapped to your thesis scenarios | Ties lab data to TFM evaluation |

**Most valuable combination:** Run 3–4 Atomic Red Team scenarios (Planning Phase 0), capture the PCAPs and export the EVTX logs, annotate them, and use them as the canonical teaching dataset. This ties your TFM evaluation data to the lab data — one effort, two outputs.

### Injection Methods

#### PCAP Injection (Network Telemetry)
SO includes a built-in tool: `so-import-pcap`
```bash
# On the SO node — import a PCAP file into the pipeline
sudo so-import-pcap /path/to/attack-scenario-01.pcap
```
This feeds the PCAP through Zeek and Suricata exactly as if the traffic were live, populating `logs-zeek-so` and `logs-suricata-so` in Elasticsearch. Perfect for lab use.

For the Import node deployment type, this is the primary workflow.

#### EVTX Injection (Windows Host Telemetry)
Windows Event Log (EVTX) files can be shipped to the SO Elastic Agent pipeline:
```bash
# Install the Elastic Agent on a Windows VM and point it at your SO fleet server
# OR use winlogbeat to ship EVTX files directly to the SO Elasticsearch
winlogbeat -e -c winlogbeat.yml  # config: ES output = SO host:9200
```
For offline classroom use, a small Windows VM (or even Wine on Linux) can be used solely to "replay" pre-collected EVTX files through Winlogbeat.

#### Direct Elasticsearch Bulk Load (Synthetic Events)
For fully synthetic/reproducible scenarios:
```python
# Push pre-generated ECS-format JSON directly to SO's Elasticsearch
from elasticsearch import Elasticsearch
import json

es = Elasticsearch("https://SO_HOST:9200", basic_auth=("elastic", "PASSWORD"), verify_certs=False)
with open("scenario_01_events.json") as f:
    for event in json.load(f):
        es.index(index="logs-fusion-lab-so", document=event)
```
This bypasses Zeek/Suricata entirely — useful for exercises focused on Kibana querying and hunting rather than detection.

### Recommended Scenario Catalog for Teaching

| Scenario | ATT&CK Techniques | Sources Involved | Difficulty |
|---|---|---|---|
| **01 — Port Scan & Banner Grab** | T1595 (Recon), T1046 (Network Service Discovery) | Zeek conn.log, Suricata | Beginner |
| **02 — SSH Brute Force** | T1110.001 (Brute Force: Password Guessing) | Zeek, Suricata ET rules | Beginner |
| **03 — Web Exploit (CVE/SQLi)** | T1190 (Exploit Public-Facing App), T1059 | Suricata HTTP alerts, Zeek http.log | Intermediate |
| **04 — Lateral Movement via PsExec** | T1021.002 (SMB/Windows Admin Shares), T1569.002 | Zeek, Sysmon (if Windows endpoint) | Intermediate |
| **05 — C2 Beaconing (Cobalt Strike-style)** | T1071.001 (Web Protocols), T1071.004 (DNS) | Zeek dns.log + http.log, Suricata | Intermediate |
| **06 — Data Exfiltration over DNS** | T1048.003 (Exfil: Non-App Layer Protocol) | Zeek dns.log, Suricata | Advanced |
| **07 — Multi-Stage Attack (01+03+04+05)** | Multiple | All sources | Advanced — ties fusion engine need |

Scenario 07 is intentionally multi-stage and multi-source — it is the scenario where SO shows its gap (no cross-source correlation) and where the fusion engine (Planning Phase 2) adds value. This scenario serves double duty: teaching lab capstone AND TFM evaluation benchmark.

### Deliverables for L2
- [ ] Download, annotate, and store the 3 primary datasets in `scenarios/lab-data/`
- [ ] Test `so-import-pcap` for each PCAP dataset — confirm events appear in SOC dashboard
- [ ] Write injection scripts for each scenario (`scenarios/inject-scenario-XX.sh`)
- [ ] Document expected output for each scenario: "after injecting Scenario 02, students should see X Suricata alerts, Y Zeek conn.log entries, alert rule name Z"
- [ ] Create a lab reset script (`lab-reset.sh`): restores ES to clean state and re-injects all scenarios in order

---

## Phase L3 — Laboratory Instructions & Exercises
**[PARALLEL → Planning Phase 6]**  
**Duration: 2–3 weeks, overlaps with thesis write-up**

This phase produces the actual teaching materials. Write these in parallel with the TFM write-up — much of the Phase 6 thesis content (architecture, component descriptions, gap analysis) can be reused in simplified form for students.

### Core Learning Objectives

A university cybersecurity class using this lab should be able to:

| # | Objective | SO Component | Difficulty |
|---|---|---|---|
| 1 | Navigate the SOC web UI and interpret an alert | SOC Alerts view | Beginner |
| 2 | Correlate a Suricata alert to its underlying Zeek connection log | SOC Hunt + Kibana | Beginner |
| 3 | Retrieve the PCAP for a suspicious connection and analyze it | SOC PCAP + CyberChef | Beginner |
| 4 | Write a basic Suricata detection rule and validate it fires | Suricata, SOC Detections | Intermediate |
| 5 | Hunt for IOCs (IP, domain, hash) across multiple log sources | SOC Hunt | Intermediate |
| 6 | Map observed events to MITRE ATT&CK techniques manually | SOC + ATT&CK Navigator | Intermediate |
| 7 | Identify what SO alone cannot correlate (the gap) | All sources, manual review | Intermediate |
| 8 | Understand what automated fusion adds (run `fusion_engine.py` output) | Fusion engine output, ES | Advanced |
| 9 | Read and validate a STIX bundle produced from correlated events | STIX JSON + stix2-validator | Advanced |
| 10 | Publish and retrieve a STIX bundle via TAXII | OpenTAXII | Advanced |

### Lab Structure (Suggested Curriculum)

**Lab 1 — SO Orientation (Objectives 1–3)**
- Navigate the SOC UI: Alerts, Hunt, PCAP, Cases, Dashboards
- Scenario: Scenario 01 (Port Scan) pre-loaded
- Task: Find all alerts, identify the source IP, retrieve the PCAP, confirm the scan pattern in Wireshark/CyberChef
- Key insight: SO gives you the alert and the packet — but only per-event

**Lab 2 — Detection Engineering (Objective 4)**
- Scenario: Scenario 02 (SSH Brute Force) pre-loaded
- Task 1: Find the existing Suricata rule that fired
- Task 2: Write a custom Suricata rule for a threshold (>10 failed SSH attempts in 60s)
- Task 3: Inject the scenario again, confirm your rule fires
- Key insight: detection is rule-based, not behavioral

**Lab 3 — Threat Hunting (Objectives 5–6)**
- Scenario: Scenarios 03 + 04 pre-loaded (Web Exploit + Lateral Movement)
- Task 1: Given an IOC (IP address), hunt across Zeek, Suricata, and Sysmon for all events involving it
- Task 2: Map each event to an ATT&CK technique using the ATT&CK Navigator
- Task 3: Manually construct a timeline of the attack (which step came first, what the attacker did)
- Key insight: you can reconstruct the attack, but SO doesn't do it for you

**Lab 4 — The Fusion Gap (Objective 7)**
- Scenario: Scenario 07 (Multi-Stage Attack) pre-loaded
- Task 1: Count how many ATT&CK techniques SO generates alerts for vs. how many the ground truth contains
- Task 2: Identify which techniques produce zero SO alerts (detectable only from Zeek metadata or Sysmon, not Suricata rules)
- Task 3: Write a one-paragraph analysis: "What would an analyst miss if relying only on SO alerts?"
- Key insight: SO is necessary but not sufficient for multi-stage attack detection

**Lab 5 (Advanced) — Fusion Engine Output (Objectives 8–9)**
- Pre-run `fusion_engine.py` on Scenario 07, provide the output JSON to students
- Task 1: Read the fused cluster JSON — identify entities, time range, confidence score, ATT&CK tags
- Task 2: Compare the fusion output to what SO's raw alerts showed in Lab 4 — what did fusion add?
- Task 3: Read the STIX bundle generated by `stix_exporter.py` — identify the Indicator, AttackPattern, and ObservedData objects
- Task 4: Validate the bundle with `stix2-validator`, interpret the output
- Key insight: structured data sharing (STIX/TAXII) enables interoperability between security tools

### Replicability Requirements

For consistent results across all students and across semesters:

- **VM snapshot discipline:** Maintain three named snapshots: `clean-install`, `data-loaded`, `post-lab-N`. Always restore from `clean-install` before re-injecting data.
- **Injection is scripted:** Every scenario injected via a script, never manually. See `scenarios/inject-scenario-XX.sh`.
- **Expected output is documented:** Each lab exercise has a "correct answer" document showing what queries to run, what results to expect, and screenshots of the expected SOC state.
- **Student accounts:** Create one read-only SOC account per student (or per group). They can hunt and view, but cannot modify rules or configuration. One privileged account for the instructor.
- **Lab reset takes < 5 minutes:** The `lab-reset.sh` script should restore ES to clean state and re-inject all scenarios in one command. Verify this before the semester.

### SO Account Roles for Teaching

| Role | Permissions | Who Gets It |
|---|---|---|
| `analyst` (read-only) | View alerts, hunt, view PCAPs, view cases | Students |
| `engineer` | Add/modify detection rules, manage detections | Students in Lab 2 only (or under instructor supervision) |
| `admin` | Full SO administration | Instructor only |

SOC user management is at: Administration → Users.

### Deliverables for L3
- [ ] Lab 1–5 exercise sheets (PDF/Markdown), each with: setup steps, tasks, expected outputs, discussion questions
- [ ] Instructor guide: how to reset and prepare the lab, common student mistakes, how to extend exercises
- [ ] "SO Lab Quick Start" — one-page student handout: how to access SOC, default credentials, key UI sections
- [ ] Lab dataset README (`scenarios/lab-data/README.md`): what each dataset is, where it came from, license, ATT&CK coverage
- [ ] `lab-reset.sh` script tested and documented

---

## Combined Timeline

| Phase | Lab Work | Original Planning Phase | Combined Duration |
|---|---|---|---|
| **L0 + P0** | Deployment Research | Lab Setup | 2 weeks |
| **L1 + P1** | Feature Research | Gap Analysis | 2 weeks |
| **L2 + P0/P5** | Data Injection | Scenario selection | 2 weeks (overlaps P0) |
| **P2** | Fusion Engine | (no lab equivalent) | 3–4 weeks |
| **P3** | LLM Evaluation | (no lab equivalent) | 2–3 weeks |
| **P4** | STIX/TAXII Export | (no lab equivalent) | 1–2 weeks |
| **P5** | TFM Evaluation | (lab Scenario 07 doubles as P5 benchmark) | 1–2 weeks |
| **L3 + P6** | Lab Instructions | Write-Up | 3–4 weeks (parallel) |
| **Total** | | | **~18–22 weeks** |

The lab adds approximately 3–4 weeks of work beyond the original TFM plan, concentrated in L0/L1/L2. Most of that work produces artifacts that improve the thesis anyway (richer gap analysis, tested scenarios, deployment documentation).

---

## Key Decisions and Trade-offs to Confirm With Professor

1. **Shared node vs. per-student VM** — depends on university server infrastructure. Confirm which is available before designing the deployment.

2. **Import mode vs. Standalone for the teaching node** — Import mode (4 GB RAM) is vastly cheaper but supports only offline PCAP/EVTX, no live traffic. Standalone (16 GB) supports live capture. Labs 1–4 work on Import mode; Labs 5 (advanced) may need Standalone.

3. **Windows endpoint requirement** — Sysmon data (Objectives 6–7, Scenario 04) requires a Windows VM. If the university infrastructure is Linux-only, substitute with EVTX replay via Winlogbeat, or skip Sysmon exercises and focus on network-only scenarios.

4. **Lab 5 dependency on TFM deliverables** — Lab 5 requires `fusion_engine.py` and `stix_exporter.py` to be complete and tested. Sequence carefully: don't schedule Lab 5 exercises until Planning Phase 4 is done.

5. **Dataset licensing** — CICIDS2017 and UNSW-NB15 require attribution and are for research/education use. Malware Traffic Analysis PCAPs are CC BY-SA. Verify university policy on using real malware samples in teaching.

---

## Relevant Existing Files

| File | Relationship to This Plan |
|---|---|
| [Planning.md](Planning.md) | Original TFM phase plan — this document extends it |
| [docs/SecurityOnion-Overview.md](docs/SecurityOnion-Overview.md) | SO component reference — feeds directly into L1 feature research |
| [docs/SO download](docs/SO%20download) | ISO download source for lab VM deployment |
| [download-so.sh](download-so.sh) | Automates ISO download and verification for L0 |
| [download-so.ps1](download-so.ps1) | PowerShell equivalent |
