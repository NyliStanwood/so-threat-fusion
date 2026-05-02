# TFM Planning: Data Fusion System for Advanced Intrusion Detection

**Title:** Sistema de Fusión de Datos para Detección Avanzada de Intrusiones e Interoperabilidad de datos (Estándares). Utilizando Security Onion

**Approach:** Security Onion handles ingestion, storage, normalization, and dashboards. This project builds a thin but novel layer on top: cross-source fusion → LLM enrichment → STIX/TAXII export.

**Total estimated time (MVP):** ~14–16 weeks part-time  
**Total estimated time (MVP + all optional):** ~20–24 weeks part-time

---

## Phase 0 — Lab Setup
**Duration: 1–2 weeks**

### MVP
- [ ] Deploy Security Onion standalone node in a VM (VMware / VirtualBox / Proxmox)
  - Minimum specs: 16 GB RAM, 4 cores, 200 GB disk
  - Use the standalone deployment (not distributed — overkill for TFM)
- [ ] Confirm Zeek and Suricata are running and feeding Elasticsearch
  - Verify index patterns exist: `logs-zeek-*`, `logs-suricata-*`
- [ ] Install and run **Atomic Red Team** on an attack VM in an isolated network segment
  - Run 2–3 basic techniques (e.g., T1059 Command & Scripting, T1110 Brute Force) to confirm telemetry flows end-to-end
- [ ] Confirm you can query Elasticsearch from outside the SO VM via API (`curl` or Python)

### Optional (extra points)
- [ ] Add a **Windows endpoint with Sysmon** to the lab for hybrid network + endpoint telemetry
  - This significantly enriches Phase 2 — process creation, network connections, and registry events correlate with Zeek/Suricata
- [ ] Enable **MISP integration** in Security Onion
  - Gives you a threat intel feed baseline to compare against your STIX output in Phase 4

### Deliverable
Working SO instance generating multi-source telemetry, confirmed by seeing events in the Kibana/SOC dashboard.

---

## Phase 1 — Gap Analysis
**Duration: 1 week**

### MVP
- [ ] Document the Elasticsearch index structure SO exposes: index names, key ECS fields, what is and isn't normalized
- [ ] Run 3–4 Atomic Red Team attack scenarios and manually trace which events SO natively correlates vs. which it misses
  - Focus on: **multi-stage lateral movement**, **low-and-slow attacks**, events that are individually low-severity but collectively indicate compromise
- [ ] Write the gap analysis document (2–3 pages): *"SO detects X individually, but misses Y because it lacks cross-source correlation"*
  - This gap is your primary research justification — make it concrete and cite specific log fields

### Optional (extra points)
- [ ] **Quantify the gap** — don't just describe it, measure it
  - Count: how many ATT&CK techniques from your Atomic Red Team runs produce SO alerts vs. how many produce zero alerts (detected only by your fusion layer later)
  - This gives you a baseline metric for the Phase 5 evaluation chapter

### Deliverable
Gap analysis document. Becomes Section 3 of the thesis (justification for the fusion layer).

---

## Phase 2 — Fusion Engine
**Duration: 3–4 weeks**

This is the core technical contribution of the TFM.

### MVP
**Script:** `fusion_engine.py`

- [ ] Connect to SO's Elasticsearch via `elasticsearch-py`
- [ ] Query across multiple indices simultaneously: Zeek connection logs, Suricata alerts, auth/system logs
- [ ] Implement **entity extraction**: pull source IP, destination IP, hostname, username from each event type
- [ ] Implement **temporal correlation**: group events sharing an entity within a configurable time window (default: 15 min, configurable via CLI flag)
- [ ] Build an **entity graph** using `networkx`: nodes = IPs/hostnames/users, edges = co-occurrence within time window
- [ ] Assign each connected component a **fusion confidence score** based on:
  - Number of distinct data sources contributing
  - Presence of high-severity SO alerts in the cluster
  - Temporal density of events
- [ ] Tag each cluster with the most likely **MITRE ATT&CK technique(s)** (map common Suricata/Zeek patterns to ATT&CK — a static lookup table is sufficient for MVP)
- [ ] Write results back to a dedicated Elasticsearch index (`fusion-clusters-*`) — no external DB needed
- [ ] Produce output as JSON: `{ cluster_id, entities, events[], confidence_score, att&ck_tags[], time_range }`

### Optional (extra points)
- [ ] **Sliding time windows**: instead of fixed windows, implement overlapping windows to avoid missing events split across a boundary
- [ ] **Sigma rule integration**: parse a small set of Sigma rules and apply them over fused clusters (strengthens the ATT&CK mapping beyond a static lookup table)
- [ ] **Neo4j backend** instead of NetworkX: more powerful graph queries, better visualization, and academically more interesting to discuss — but adds infrastructure complexity
- [ ] **Kill chain stage inference**: classify each cluster's ATT&CK techniques into Lockheed Martin kill chain stages and score progression (Initial Access → Execution → Lateral Movement), making the output more narrative-friendly for Phase 3

### Deliverable
`fusion_engine.py` on GitHub, documented, producing fused cluster JSON for a set of test scenarios.

---

## Phase 3 — LLM Evaluation
**Duration: 2–3 weeks**

### MVP
**Script:** `llm_evaluator.py`

- [ ] Define the prompting task: given a fused cluster JSON, ask the LLM to produce:
  1. A human-readable threat narrative (2–3 sentences)
  2. MITRE ATT&CK technique mapping (list of technique IDs)
  3. One recommended response action
- [ ] Implement a prompt template with the fused cluster as structured context
- [ ] Connect to **GPT-4o** via the OpenAI API
- [ ] Connect to **Mistral 7B** via **Ollama** running locally (zero cost, no API key)
- [ ] Run both models on the same set of 5–10 fused clusters from your Atomic Red Team scenarios
- [ ] Score each response on 3 metrics:
  - **ATT&CK accuracy**: does the model correctly identify the technique(s) you know are present (from Atomic Red Team ground truth)?
  - **Hallucination rate**: does the model claim facts not present in the input JSON? (Manual review per response)
  - **Format compliance**: does the output follow the requested structure?
- [ ] Produce a results table: model × metric × cluster

### Optional (extra points)
- [ ] **RAG-augmented prompting**: before sending to the LLM, retrieve the relevant MITRE ATT&CK technique description from a local STIX bundle and include it in the context — compare RAG vs. zero-shot accuracy
- [ ] **Few-shot prompting comparison**: add 1–2 worked examples to the prompt and measure improvement vs. zero-shot — this is a clean ablation study for the evaluation chapter
- [ ] **Third model**: add Claude (Anthropic API) or a fine-tuned security-specific model (e.g., SecureBERT or CyberSecEval) for a more robust comparison
- [ ] **Automated hallucination detection**: instead of manual review, use a second LLM call to fact-check the first model's response against the input JSON — adds rigor to the evaluation methodology

### Deliverable
`llm_evaluator.py`, results table (CSV), and analysis text. Becomes the evaluation chapter's LLM section.

---

## Phase 4 — STIX/TAXII Export
**Duration: 1–2 weeks**

### MVP
**Script:** `stix_exporter.py`

- [ ] Map fused cluster fields to STIX 2.1 objects using the `stix2` Python library:
  - `ObservedData` — the raw correlated events
  - `Indicator` — network patterns (IPs, domains) from the cluster
  - `AttackPattern` — MITRE ATT&CK techniques tagged in the cluster
  - Bundle the above into a `Bundle`
- [ ] If Phase 3 ran: include LLM-generated narrative as a `Note` or `Report` STIX object
- [ ] Validate the bundle with `stix2-validator`
- [ ] Stand up **OpenTAXII** locally via Docker:
  ```bash
  docker run -p 9000:9000 eclecticiq/opentaxii
  ```
- [ ] Publish the bundle to OpenTAXII and confirm you can retrieve it via the TAXII 2.1 API
- [ ] Document the round-trip: SO event → fusion → STIX bundle → TAXII publish → TAXII retrieve

### Optional (extra points)
- [ ] **MISP push**: push your STIX bundles to the MISP instance you configured in Phase 0 — closes the loop with SO's own threat intel integration and demonstrates a real SOC sharing workflow
- [ ] **CourseOfAction objects**: serialize the LLM-recommended response actions as STIX `CourseOfAction` objects linked to the `AttackPattern` — more complete STIX model
- [ ] **Automated validation CI**: add a GitHub Actions workflow that runs `stix2-validator` on every exported bundle — demonstrates software engineering rigor

### Deliverable
`stix_exporter.py`, sample STIX bundle JSON file, validation evidence screenshot. Becomes the interoperability chapter.

---

## Phase 5 — Evaluation
**Duration: 1–2 weeks**

### MVP
Run the full pipeline end-to-end against structured attack scenarios and measure what matters.

- [ ] Execute 3–4 Atomic Red Team attack scenarios (choose techniques that span multiple data sources, e.g., T1078 Valid Accounts + T1021 Remote Services + T1059 Command Execution)
- [ ] For each scenario, compare:
  - **Baseline**: raw SO alerts generated
  - **With fusion**: clusters surfaced by `fusion_engine.py`
  - Metric: *detection coverage delta* — how many ATT&CK techniques were detected by fusion that were missed by SO alone?
- [ ] Record false positive rate for the fusion engine (clusters that don't map to any real attack)
- [ ] Report LLM comparison results from Phase 3 in the context of these scenarios
- [ ] Validate STIX bundle schema compliance (pass/fail per bundle)

### Optional (extra points)
- [ ] **Caldera scenarios**: replace or supplement Atomic Red Team with MITRE Caldera for more complex, multi-agent, automated adversary emulations — produces richer multi-stage attack graphs that stress-test the fusion engine
- [ ] **Public dataset comparison**: run the fusion engine against a subset of CICIDS2017 or UNSW-NB15 (import into a test ES instance) — allows comparison against published detection baselines and strengthens external validity claims

### Deliverable
Results chapter: metrics tables (coverage delta, FP rate, LLM scoring), honest failure analysis. This is the academic heart of the thesis.

---

## Phase 6 — Write-Up
**Duration: 3–4 weeks**

### MVP
Standard TFM structure:

1. **Introduction** — problem statement, research question, scope
2. **State of the Art** — Security Onion, data fusion in SIEM/SOC, STIX/TAXII standards, LLMs in cybersecurity
3. **Architecture & Design** — system design decisions, component diagram, what SO provides vs. what you built
4. **Implementation** — the three scripts, key algorithms, configuration parameters
5. **Evaluation & Results** — Phase 5 metrics, LLM comparison table, STIX validation results
6. **Conclusions & Future Work** — what worked, what didn't, what full production deployment would require

### Optional (extra points)
- [ ] **C4 architecture diagrams** (Context → Container → Component → Code) — well-regarded in academic CS work, easy to generate with Structurizr or draw.io
- [ ] **JC3IEDM theoretical appendix** — a partial mapping of your STIX objects to JC3IEDM entities as a theoretical discussion (no implementation required) — adds the defense/NATO angle that was in the original brief without the implementation cost
- [ ] **Prepare a conference paper draft** — the LLM evaluation methodology and results are likely publishable at a workshop (IEEE S&P workshops, USENIX security workshops) — supervisors often encourage this

### Deliverable
Submitted TFM document.

---

## Summary Timeline

| Phase | Scope | MVP Duration | With Optional |
|---|---|---|---|
| 0 | Lab Setup | 1–2 weeks | 2 weeks |
| 1 | Gap Analysis | 1 week | 1–2 weeks |
| 2 | Fusion Engine | 3–4 weeks | 4–5 weeks |
| 3 | LLM Evaluation | 2–3 weeks | 3–4 weeks |
| 4 | STIX/TAXII Export | 1–2 weeks | 2 weeks |
| 5 | Evaluation | 1–2 weeks | 2–3 weeks |
| 6 | Write-Up | 3–4 weeks | 4–5 weeks |
| **Total** | | **~14–16 weeks** | **~20–24 weeks** |

---

## Custom Code Inventory

All custom code fits in approximately 3 scripts + supporting files:

```
so-threat-fusion/
├── fusion_engine.py        # Phase 2 — core contribution
├── llm_evaluator.py        # Phase 3 — LLM comparison
├── stix_exporter.py        # Phase 4 — standards output
├── config.yaml             # time windows, ES host, model names, ATT&CK mappings
├── docker-compose.yml      # OpenTAXII server
├── requirements.txt        # elasticsearch-py, networkx, stix2, openai, etc.
└── scenarios/              # Atomic Red Team run configs + expected ground truth
```

Everything else — ingestion, normalization, storage, alerting, dashboards — is Security Onion.
