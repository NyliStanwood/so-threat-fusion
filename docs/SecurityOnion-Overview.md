# Security Onion Overview

---


Security Onion is a free, open-source Linux distribution for network security monitoring (NSM) and log management. It bundles and integrates open-source tools into a single deployable platform used in home labs, SOCs, and enterprises.

Includes: network visibility, host visivility, intrusion, detection honeypots, log management and case management.

It is a **data collection and alerting platform** it doesn't do correlation or response engine. That gap is the research justification for this project.

**Current version:** 2.4.211 (March 2026) — version 3.0 planned for later 2026  
**Official docs:** https://docs.securityonion.net/en/2.4/  
**GitHub:** https://github.com/Security-Onion-Solutions/securityonion

---



## Key Documentation Pages

| Topic | URL |
|---|---|
| Introduction | https://docs.securityonion.net/en/2.4/introduction.html |
| Architecture | https://docs.securityonion.net/en/2.4/architecture.html |
| Hardware requirements | https://docs.securityonion.net/en/2.4/hardware.html |
| Installation | https://docs.securityonion.net/en/2.4/installation.html |
| Elasticsearch | https://docs.securityonion.net/en/2.4/elasticsearch.html |
| so-elasticsearch-query | https://docs.securityonion.net/en/2.4/so-elasticsearch-query.html |
| Zeek | https://docs.securityonion.net/en/2.4/zeek.html |
| Suricata | https://docs.securityonion.net/en/2.4/suricata.html |
| Elastic Agent | https://docs.securityonion.net/en/2.4/elastic-agent.html |
| Firewall management | https://docs.securityonion.net/en/2.4/firewall.html |
| Performance tuning | https://docs.securityonion.net/en/2.4/performance.html |
| Release notes | https://docs.securityonion.net/en/2.4/release-notes.html |
| MISP integration | https://docs.securityonion.net/en/2.4/misp.html |

---


## Bundled Components

### Network Visibility
| Tool | Role |
|---|---|
| **Zeek** | Protocol metadata extraction (conn logs, DNS, HTTP, SSL, files, etc.) |
| **Suricata** | Signature-based NIDS; also performs full packet capture (PCAP) with lz4 compression |
| **Strelka** | Automated file analysis and malware detection on files extracted by Zeek/Suricata |

### Host Visibility
| Tool | Role |
|---|---|
| **Elastic Agent** | Endpoint telemetry collection and log shipping |
| **osquery** | Live SQL-like queries on endpoint state |
| **Sysmon** | Windows event log collection (process creation, network events, registry) |

### Log Pipeline & Storage
| Tool | Role |
|---|---|
| **Logstash** | Parsing, transformation, enrichment |
| **Redis** | Message queue / buffer between Logstash stages |
| **Elasticsearch** | Central indexed storage |
| **Kibana** | Visualization and ad-hoc querying |

### Other
| Tool | Role |
|---|---|
| **Security Onion Console (SOC)** | Custom web UI: alerting, hunting, PCAP retrieval, case management |
| **CyberChef** | In-browser data encoding/decoding utility |
| **TheHive / MISP** | Optional integrations for case management and threat intel feeds |

---

## Deployment Types

| Type | Min RAM | Min Cores | Storage | Use Case |
|---|---|---|---|---|
| **Import** | 4 GB | 2 | 50 GB | Offline PCAP/EVTX forensics only — no live traffic |
| **Evaluation** | 8 GB | 4 | 200 GB | Short-term testing with a live TAP/SPAN port |
| **Standalone** | 16–24 GB | 4 | 200 GB+ | Lab, POC, TFM — all components on one machine |
| **Sensor node** | 12 GB | 4 | 200 GB | Distributed: capture + detection only |
| **Search node** | 16 GB | 4 | 200 GB | Distributed: Elasticsearch indexing |
| **Manager node** | 16–128 GB | 4–8 | 200 GB–2 TB | Distributed: SOC UI, Kibana, cluster management |

**For this TFM:** standalone is the right choice. Use at least 16 GB RAM; 24 GB is more comfortable under load.

Scaling reference: each Suricata/Zeek worker handles ~200 Mbps. A saturated 1 Gbps link needs ~10+ workers.

---

## Data Sources and Elasticsearch Index Patterns

All data lands in Elasticsearch as **data streams** (abstraction above traditional indices).

| Data source | Index pattern |
|---|---|
| Zeek | `logs-zeek-so` |
| Suricata alerts | `logs-suricata-so` |
| Sysmon / Windows | `logs-sysmon-so` |
| Elastic Agent / endpoint | `logs-elastic_agent-so` |
| PCAP metadata | `logs-strelka-so` |

Data streams back individual time-partitioned indices like `.ds-logs-zeek-so-2025-11-01.0001`. Always query via the stream name, not the backing index.

SO uses **ECS (Elastic Common Schema)** for normalization. Key fields to know:
- `@timestamp` — normalized event time (always present)
- `source.ip`, `destination.ip` — network endpoints
- `source.port`, `destination.port`
- `host.name` — originating sensor or endpoint
- `user.name` — authenticated user identity where available
- `network.protocol`, `network.transport`
- `event.category`, `event.type`, `event.action`
- `rule.name`, `rule.id` — Suricata alert signature details

**Field limit:** 5,000 fields per index by default. Configurable via Administration → Configuration → elasticsearch.

---

## Querying Elasticsearch from Python

Elasticsearch is locked down by default. Access uses the same credentials as the SOC web UI.

### Authentication options
- **Username/password** (basic auth) over HTTPS, port 9200
- Certificate CA is at `/etc/ssl/certs/intca.crt` on the SO node (copy it out for trusted connections)

### Python example (`elasticsearch-py`)
```python
from elasticsearch import Elasticsearch

es = Elasticsearch(
    "https://<SO_HOST>:9200",
    basic_auth=("elastic", "<PASSWORD>"),
    ca_certs="/path/to/intca.crt",   # or verify_certs=False for lab use
)

# Cross-index query: Zeek + Suricata events in the last 15 minutes
resp = es.search(
    index="logs-zeek-so,logs-suricata-so",
    body={
        "query": {
            "range": {"@timestamp": {"gte": "now-15m"}}
        },
        "_source": ["@timestamp", "source.ip", "destination.ip", "event.category", "rule.name"],
        "size": 500
    }
)
```

### Useful shell tool (on the SO node itself)
```bash
sudo so-elasticsearch-query logs-zeek-so/_search \
  -d '{"query": {"match_all": {}}, "size": 1}' | jq
```

---

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


