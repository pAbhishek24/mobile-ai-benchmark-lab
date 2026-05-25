#!/usr/bin/env bash
set -euo pipefail

# debug_snapshot.sh
#
# Captures a snapshot and prints detailed diagnostics for path/JSON issues.
#
# Usage:
#   ./ai-lab/scripts/debug_snapshot.sh
#   ./ai-lab/scripts/debug_snapshot.sh --out-dir /tmp/pfa_debug_snapshot
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

OUT_DIR=""

usage() {
  echo "Usage: $0 [--out-dir <dir>]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  TS="$(date +%Y%m%d_%H%M%S)"
  OUT_DIR="$REPO_ROOT/ai-lab/logs/debug/snapshot_$TS"
fi

SNAP_JSON="$OUT_DIR/snapshot.json"
SNAP_RAW="$OUT_DIR/snapshot.raw.txt"

echo "Repo root : $REPO_ROOT"
echo "Script dir: $SCRIPT_DIR"
echo "Out dir   : $OUT_DIR"
echo "JSON path : $SNAP_JSON"
echo "RAW path  : $SNAP_RAW"

mkdir -p "$OUT_DIR"

echo ""
echo "Running device_snapshot.sh..."
"$REPO_ROOT/ai-lab/scripts/device_snapshot.sh" -l debug -o "$SNAP_JSON" --raw-out "$SNAP_RAW"

echo ""
echo "Validating snapshot.json exists and is non-empty..."
[[ -f "$SNAP_JSON" ]] || { echo "FAIL: snapshot.json missing"; exit 1; }
[[ -s "$SNAP_JSON" ]] || { echo "FAIL: snapshot.json empty"; exit 1; }

echo "Validating snapshot.json is valid JSON..."
python3 -m json.tool "$SNAP_JSON" >/dev/null
echo "OK: snapshot.json valid"

echo ""
echo "Snapshot content:"
cat "$SNAP_JSON"

echo ""
echo "RAW capture (first 60 lines):"
head -n 60 "$SNAP_RAW" || true

echo ""
echo "DONE"

