#!/usr/bin/env bash
# Downloads and extracts sbousseaden/EVTX-ATTACK-SAMPLES for use with load_scenario.py
# See docs/data-sources/1.EVTX-ATTACK-SAMPLES.md for background.
set -euo pipefail

REPO_URL="https://github.com/sbousseaden/EVTX-ATTACK-SAMPLES.git"
ZIP_URL="https://github.com/sbousseaden/EVTX-ATTACK-SAMPLES/archive/refs/heads/master.zip"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLES_DIR="${SAMPLES_DIR:-$SCRIPT_DIR/samples}"
FORCE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [-d DEST_DIR] [-f]

Downloads and extracts the EVTX-ATTACK-SAMPLES repository
(https://github.com/sbousseaden/EVTX-ATTACK-SAMPLES) for use with
load_scenario.py.

  -d DEST_DIR   Destination directory (default: $SAMPLES_DIR)
  -f            Force re-download even if the destination already has samples
  -h            Show this help
EOF
}

while getopts "d:fh" opt; do
    case "$opt" in
        d) SAMPLES_DIR="$OPTARG" ;;
        f) FORCE=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

if [ -d "$SAMPLES_DIR" ] && [ "$FORCE" -ne 1 ]; then
    existing=$(find "$SAMPLES_DIR" -iname "*.evtx" 2>/dev/null | wc -l)
    if [ "$existing" -gt 0 ]; then
        echo "[+] $SAMPLES_DIR already has $existing .evtx files. Use -f to force a re-download."
        exit 0
    fi
fi

mkdir -p "$SAMPLES_DIR"

if command -v git >/dev/null 2>&1; then
    echo "[+] Cloning EVTX-ATTACK-SAMPLES via git (shallow) into $SAMPLES_DIR"
    rm -rf "$SAMPLES_DIR"
    git clone --depth 1 "$REPO_URL" "$SAMPLES_DIR"
else
    echo "[+] git not found, falling back to zip download"
    TMP_ZIP="$(mktemp --suffix=.zip)"
    TMP_EXTRACT="$(mktemp -d)"
    curl -fL "$ZIP_URL" -o "$TMP_ZIP"
    unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT"
    rm -rf "$SAMPLES_DIR"
    mv "$TMP_EXTRACT"/EVTX-ATTACK-SAMPLES-* "$SAMPLES_DIR"
    rm -f "$TMP_ZIP"
    rm -rf "$TMP_EXTRACT"
fi

count=$(find "$SAMPLES_DIR" -iname "*.evtx" | wc -l)
echo "[+] Done. $count .evtx files available under $SAMPLES_DIR"
echo "[+] List scenarios with: python3 load_scenario.py --list"
echo "[+] Search scenarios with: python3 load_scenario.py --list --scenario T1003"
echo "[+] Load one with:       python3 load_scenario.py --scenario T1003"
