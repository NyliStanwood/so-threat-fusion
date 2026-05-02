# so-threat-fusion

TFM project. A data fusion and threat intelligence layer built on top of [Security Onion](https://securityonionsolutions.com/).

Security Onion handles ingestion, normalization, storage, and alerting. This project adds:
1. **Cross-source event correlation** — links Zeek, Suricata, and Sysmon events by shared entity and time window into fused attack clusters
2. **LLM enrichment** — evaluates GPT-4o vs. Mistral 7B for automated threat narrative and ATT&CK mapping generation
3. **STIX/TAXII export** — serializes enriched clusters to STIX 2.1 and publishes via a TAXII 2.1 server

## Requirements

- Security Onion standalone node with Elasticsearch accessible via API
- Python 3.11+
- Docker (for OpenTAXII)
- Ollama with Mistral 7B pulled locally
- OpenAI API key (for GPT-4o comparison)

## Proposed Repository Structure

```
so-threat-fusion/
│
├── fusion_engine.py        # Queries ES, correlates events, writes clusters to ES
├── llm_evaluator.py        # Sends fused clusters to LLMs, scores responses
├── stix_exporter.py        # Serializes clusters to STIX 2.1, publishes to TAXII
│
├── config.yaml             # ES host, time windows, ATT&CK mappings, model names
├── docker-compose.yml      # OpenTAXII server
├── requirements.txt
│
├── scenarios/              # Atomic Red Team run configs and ground-truth labels
│   └── lateral_movement/
│
├── output/                 # Generated STIX bundles (gitignored if sensitive)
│
├── evaluation/             # LLM scoring results, metrics tables
│
├── docs/                   # Architecture diagrams, gap analysis, thesis chapters
│
├── Planning.md
└── CLAUDE.md
```

## Status

Planning complete. Implementation not started. See [Planning.md](Planning.md) for the phase-by-phase plan.
