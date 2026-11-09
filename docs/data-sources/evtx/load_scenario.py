#!/usr/bin/env python3
"""
Parse a selected EVTX scenario file and index it into Security Onion's Elasticsearch.

Timestamps found anywhere in the event (System/TimeCreated, Sysmon UtcTime, etc.)
are rewritten to today's date while the original hour/minute/second/fraction is
kept untouched, so replayed events land inside SO's normal time-window correlation
without losing their relative timing.

See docs/data-sources/1.EVTX-ATTACK-SAMPLES.md for background and index conventions.

Usage:
    python3 load_scenario.py --list
    python3 load_scenario.py --list --scenario T1003
    python3 load_scenario.py --scenario T1003_LSASS --es-password '***'
    python3 load_scenario.py --file revshell_cmd_svchost_sysmon_1.evtx --dry-run
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path

_TECHNIQUE_RE = re.compile(r"T\d{4}(?:\.\d{3})?", re.IGNORECASE)
_DATE_PREFIX_RE = re.compile(r"^\d{4}-\d{2}-\d{2}")


def extract_technique_id(filename: str) -> str | None:
    m = _TECHNIQUE_RE.search(filename)
    return m.group(0).upper() if m else None


def rewrite_timestamp(value: str, target_date: date) -> str:
    """Replace only the YYYY-MM-DD prefix of a timestamp string, keeping the
    time-of-day, fractional seconds and timezone suffix exactly as they were."""
    if not isinstance(value, str) or not _DATE_PREFIX_RE.match(value):
        return value
    return _DATE_PREFIX_RE.sub(target_date.strftime("%Y-%m-%d"), value, count=1)


def rewrite_timestamps_in_obj(obj, target_date: date):
    if isinstance(obj, dict):
        return {k: rewrite_timestamps_in_obj(v, target_date) for k, v in obj.items()}
    if isinstance(obj, list):
        return [rewrite_timestamps_in_obj(v, target_date) for v in obj]
    if isinstance(obj, str):
        return rewrite_timestamp(obj, target_date)
    return obj


def _extract_event_id(system: dict):
    eid = system.get("EventID")
    if isinstance(eid, dict):
        return eid.get("#text") or eid.get("#attributes", {}).get("Qualifiers")
    return eid


def _extract_provider(system: dict):
    prov = system.get("Provider")
    if isinstance(prov, dict):
        attrs = prov.get("#attributes", prov)
        return attrs.get("Name")
    return prov


def _extract_system_time(system: dict):
    tc = system.get("TimeCreated")
    if isinstance(tc, dict):
        attrs = tc.get("#attributes", tc)
        return attrs.get("SystemTime")
    return tc


def build_doc(record: dict, parsed_event: dict, technique_id: str | None,
              source_filename: str, target_date: date) -> dict:
    original_ts = record.get("timestamp")
    rewritten_event = rewrite_timestamps_in_obj(parsed_event, target_date)

    event_block = rewritten_event.get("Event", {})
    system = event_block.get("System", {})

    # System/TimeCreated is clean ISO-8601; record["timestamp"] from the evtx
    # crate carries a trailing " UTC" that Elasticsearch's date type rejects,
    # so prefer TimeCreated for @timestamp and keep the raw value for reference.
    new_ts = _extract_system_time(system) or (
        rewrite_timestamp(original_ts, target_date) if original_ts else None
    )

    return {
        "@timestamp": new_ts or datetime.now(timezone.utc).isoformat(),
        "event.kind": "event",
        "event.original.timestamp": original_ts,
        "event.provider": _extract_provider(system),
        "winlog.channel": system.get("Channel"),
        "winlog.event_id": _extract_event_id(system),
        "winlog.computer_name": system.get("Computer"),
        "winlog.record_id": record.get("event_record_id"),
        "winlog.event_data": event_block.get("EventData") or event_block.get("UserData"),
        "host.name": system.get("Computer"),
        "labels.attack_technique": technique_id,
        "labels.scenario_file": source_filename,
        "tags": ["evtx-lab-injection"],
        "event.original.raw": json.dumps(rewritten_event, ensure_ascii=False),
    }


def parse_evtx_file(evtx_path: Path, target_date: date, limit: int | None = None):
    from evtx import PyEvtxParser

    parser = PyEvtxParser(str(evtx_path))
    technique_id = extract_technique_id(evtx_path.name)
    count = 0
    for record in parser.records_json():
        if limit and count >= limit:
            break
        try:
            parsed_event = json.loads(record["data"])
        except (KeyError, json.JSONDecodeError) as exc:
            print(f"    [!] Skipping malformed record: {exc}", file=sys.stderr)
            continue
        yield build_doc(record, parsed_event, technique_id, evtx_path.name, target_date)
        count += 1


def find_scenarios(script_dir: Path, samples_dir: Path, term: str | None = None) -> list[Path]:
    candidates = list(sorted(script_dir.glob("*.evtx")))
    if samples_dir.is_dir():
        candidates.extend(sorted(samples_dir.rglob("*.evtx")))
    if term:
        term_lower = term.lower()
        candidates = [c for c in candidates if term_lower in str(c).lower()]
    return candidates


def print_scenario_list(paths: list[Path]) -> None:
    if not paths:
        print("No scenarios found. Run download_evtx_samples.sh first, or check --scenario spelling.")
        return
    for p in paths:
        tid = extract_technique_id(p.name)
        tag = f" [{tid}]" if tid else ""
        print(f"  {p}{tag}")


def index_docs(es, index: str, docs: list[dict]):
    from elasticsearch import helpers

    actions = ({"_index": index, "_source": doc} for doc in docs)
    success, errors = helpers.bulk(es, actions, raise_on_error=False, stats_only=False)
    return success, errors


def parse_args():
    parser = argparse.ArgumentParser(
        description="Load a Windows EVTX scenario into Security Onion's Elasticsearch.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    selection = parser.add_argument_group("scenario selection")
    selection.add_argument("--file", help="Path to a specific .evtx file to load")
    selection.add_argument("--scenario", help="Search term to find a scenario (matches filename/path, case-insensitive)")
    selection.add_argument("--samples-dir", help="Directory of downloaded samples (default: <script_dir>/samples)")
    selection.add_argument("--list", action="store_true", help="List matching scenarios instead of loading one")
    selection.add_argument("--yes", "-y", action="store_true", help="Auto-pick the first match when --scenario matches multiple files")

    timing = parser.add_argument_group("timestamp rewrite")
    timing.add_argument("--date", help="Target date to rewrite events to, YYYY-MM-DD (default: today, UTC)")
    timing.add_argument("--limit", type=int, help="Max number of events to load from the file")

    es_group = parser.add_argument_group("elasticsearch")
    es_group.add_argument("--es-host", default=os.environ.get("SO_ES_HOST", "https://localhost:9200"))
    es_group.add_argument("--es-user", default=os.environ.get("SO_ES_USER", "elastic"))
    es_group.add_argument("--es-password", default=os.environ.get("SO_ES_PASSWORD"))
    es_group.add_argument("--ca-cert", default=os.environ.get("SO_ES_CA_CERT", "/etc/ssl/certs/intca.crt"))
    es_group.add_argument("--no-verify-certs", action="store_true", help="Disable TLS cert verification (lab use only)")
    es_group.add_argument("--index", default="logs-windows-lab")

    dry = parser.add_argument_group("dry run")
    dry.add_argument("--dry-run", action="store_true", help="Parse and rewrite but do not index; print/save JSON instead")
    dry.add_argument("--output", help="When --dry-run, write JSON docs to this file instead of stdout")

    return parser.parse_args()


def main():
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    samples_dir = Path(args.samples_dir) if args.samples_dir else script_dir / "samples"
    target_date = date.fromisoformat(args.date) if args.date else datetime.now(timezone.utc).date()

    if args.list:
        print_scenario_list(find_scenarios(script_dir, samples_dir, args.scenario))
        return

    if args.file:
        evtx_path = Path(args.file)
        if not evtx_path.is_file():
            sys.exit(f"File not found: {evtx_path}")
    elif args.scenario:
        matches = find_scenarios(script_dir, samples_dir, args.scenario)
        if not matches:
            sys.exit(
                f"No scenario matched '{args.scenario}'. Run with --list to see options, "
                "or run download_evtx_samples.sh first."
            )
        if len(matches) > 1 and not args.yes:
            print_scenario_list(matches)
            sys.exit(
                f"{len(matches)} scenarios matched '{args.scenario}'. "
                "Narrow the search term or pass --yes to use the first match."
            )
        evtx_path = matches[0]
    else:
        sys.exit("Specify --file <path>, --scenario <term>, or --list.")

    print(f"[+] Loading {evtx_path.name} -> target date {target_date.isoformat()}")

    docs = list(parse_evtx_file(evtx_path, target_date, limit=args.limit))
    if not docs:
        sys.exit("No events parsed from file.")

    if args.dry_run:
        output = json.dumps(docs, indent=2, default=str)
        if args.output:
            Path(args.output).write_text(output, encoding="utf-8")
            print(f"[+] Wrote {len(docs)} docs to {args.output}")
        else:
            print(output)
        return

    if not args.es_password:
        sys.exit("Elasticsearch password required: set SO_ES_PASSWORD or pass --es-password.")

    from elasticsearch import Elasticsearch

    es = Elasticsearch(
        args.es_host,
        basic_auth=(args.es_user, args.es_password),
        ca_certs=None if args.no_verify_certs else args.ca_cert,
        verify_certs=not args.no_verify_certs,
    )
    success, errors = index_docs(es, args.index, docs)
    print(f"[+] Indexed {success} events into '{args.index}' (errors: {len(errors) if errors else 0})")
    if errors:
        for err in errors[:5]:
            print("    ", err)


if __name__ == "__main__":
    main()
