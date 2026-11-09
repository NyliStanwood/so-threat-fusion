# EVTX Ingestion Workflow

Automates the workflow described in [1.EVTX-ATTACK-SAMPLES.md](../1.EVTX-ATTACK-SAMPLES.md) Path 1:
parse `.evtx` files to JSON with `evtx`, rewrite timestamps to today, and POST directly into
Security Onion's Elasticsearch. Runs on the SO Linux node (or any box with network access to
its Elasticsearch on port 9200).

```
download_evtx_samples.sh   → fetches EVTX-ATTACK-SAMPLES into samples/
load_scenario.py           → parses a chosen scenario, rewrites timestamps, indexes into ES
requirements.txt           → evtx, elasticsearch (pip)
revshell_cmd_svchost_sysmon_1.evtx → bundled example scenario (no download needed)
```

---

## 1. Install dependencies

On the SO node (or wherever you run this):

```bash
pip install -r requirements.txt
```

## 2. Download the sample library (optional)

Only needed if you want the full ~250-file EVTX-ATTACK-SAMPLES catalog. The bundled
`revshell_cmd_svchost_sysmon_1.evtx` works without this step.

```bash
./download_evtx_samples.sh
```

Clones (shallow) into `samples/`; falls back to a zip download if `git` isn't installed.
Re-run with `-f` to force a fresh download, or `-d <dir>` to change the destination.

## 3. Find a scenario

```bash
python3 load_scenario.py --list                  # everything available
python3 load_scenario.py --list --scenario T1003  # filter by ATT&CK ID or keyword
```

Each line shows the file path and, if the filename encodes one, its ATT&CK technique ID.

## 4. Load it into Elasticsearch

```bash
export SO_ES_PASSWORD='<elastic-user-password>'

python3 load_scenario.py --scenario T1003_LSASS
# or, for the bundled example:
python3 load_scenario.py --file revshell_cmd_svchost_sysmon_1.evtx
```

What happens:
- The `.evtx` file is parsed record-by-record with `evtx`.
- Every timestamp found in the event (`System/TimeCreated`, Sysmon `EventData/UtcTime`, etc.)
  is rewritten to **today's date**, keeping the original **hour/minute/second/fraction**
  untouched — so multi-event scenarios keep their relative timing and land inside SO's normal
  time-window correlation.
- Events are bulk-indexed into the `logs-windows-lab` index (override with `--index`).

If `--scenario` matches more than one file, the script lists the matches and exits — narrow
the search term or add `--yes` to load the first match.

### Dry run first

Parse and rewrite without touching Elasticsearch, to sanity-check output:

```bash
python3 load_scenario.py --file revshell_cmd_svchost_sysmon_1.evtx --dry-run
python3 load_scenario.py --file revshell_cmd_svchost_sysmon_1.evtx --dry-run --output preview.json
```

---

## Elasticsearch connection

Defaults match a standalone SO node queried locally (see
[../../SecurityOnion-Overview.md](../../SecurityOnion-Overview.md#querying-elasticsearch-from-python)).
All can be set via flag or environment variable:

| Flag | Env var | Default |
|---|---|---|
| `--es-host` | `SO_ES_HOST` | `https://localhost:9200` |
| `--es-user` | `SO_ES_USER` | `elastic` |
| `--es-password` | `SO_ES_PASSWORD` | *(required, no default)* |
| `--ca-cert` | `SO_ES_CA_CERT` | `/etc/ssl/certs/intca.crt` |
| `--index` | — | `logs-windows-lab` |

Use `--no-verify-certs` to skip TLS verification for quick lab testing instead of pointing at
the SO CA cert.

---

## Other flags

- `--date YYYY-MM-DD` — rewrite to a specific date instead of today (useful for reproducible test runs).
- `--limit N` — only load the first N events from the file.
- `--samples-dir DIR` — point at a samples checkout in a non-default location.

---

## Gotchas

- **Elastic Agent is not involved.** This path POSTs straight to Elasticsearch, so events won't
  go through SO's normal ingest pipelines/parsers. Field names are a hand-picked ECS-ish subset
  (`@timestamp`, `host.name`, `winlog.*`, `labels.*`) — good enough for fusion-engine queries, but
  don't expect it to look identical to a live Sysmon-via-Elastic-Agent event. If you need
  byte-for-byte identical shape, use Path 2 (Winlogbeat) from
  [1.EVTX-ATTACK-SAMPLES.md](../1.EVTX-ATTACK-SAMPLES.md) instead.
- **`event.original.raw`** on every doc holds the full parsed-and-rewritten event as a JSON
  string, and **`event.original.timestamp`** holds the un-rewritten capture time — both are kept
  for debugging/ground-truth comparison even though `@timestamp` is what SO/Kibana will use.
- **Filename is the ground truth label.** `labels.attack_technique` is extracted from the
  filename (`T\d{4}` pattern); files without a technique ID in the name (like the bundled
  revshell example) get `null` and rely on `labels.scenario_file` instead.
- **Dedicated index, not the live SO streams.** Indexing into `logs-windows-lab` (not
  `logs-sysmon-so`) keeps replayed/simulated events separate from anything a real Elastic Agent
  reports, matching this project's "dedicated index" design decision.
