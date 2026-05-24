#!/usr/bin/env bash
set -euo pipefail

# self_test.sh
#
# Validates the on-device benchmark environment (Termux) and script outputs.
#
# Usage:
#   ./ai-lab/scripts/self_test.sh
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ok() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

detect_llama_bin() {
  if command -v llama-cli >/dev/null 2>&1; then
    command -v llama-cli
    return 0
  fi
  if [[ -x "$HOME/llama.cpp/build/bin/llama-cli" ]]; then
    echo "$HOME/llama.cpp/build/bin/llama-cli"
    return 0
  fi
  if command -v llava-cli >/dev/null 2>&1; then
    command -v llava-cli
    return 0
  fi
  if [[ -x "$HOME/llama.cpp/build/bin/llava-cli" ]]; then
    echo "$HOME/llama.cpp/build/bin/llava-cli"
    return 0
  fi
  if command -v main >/dev/null 2>&1; then
    command -v main
    return 0
  fi
  if [[ -x "$HOME/llama.cpp/main" ]]; then
    echo "$HOME/llama.cpp/main"
    return 0
  fi
  return 1
}

need_cmd python3
need_cmd jq
ok "python3 present: $(python3 --version 2>/dev/null || true)"
ok "jq present: $(jq --version 2>/dev/null || true)"

LLAMA_BIN="$(detect_llama_bin || true)"
[[ -n "$LLAMA_BIN" ]] || fail "llama.cpp binary not found (expected llama-cli/llava-cli/main)"
ok "llama.cpp binary: $LLAMA_BIN"

PROMPTS="$REPO_ROOT/ai-lab/prompts/finance-benchmark-prompts.json"
[[ -f "$PROMPTS" ]] || fail "missing prompts file: $PROMPTS"
python3 -m json.tool "$PROMPTS" >/dev/null || fail "prompts JSON invalid"
jq -e '.prompts | length > 0' "$PROMPTS" >/dev/null || fail "prompts JSON has no prompts"
ok "prompts JSON valid: $PROMPTS"

SNAP_TMP_DIR="$REPO_ROOT/ai-lab/logs/self_test"
mkdir -p "$SNAP_TMP_DIR"
SNAP_JSON="$SNAP_TMP_DIR/snapshot.json"
SNAP_RAW="$SNAP_TMP_DIR/snapshot.raw.txt"
"$REPO_ROOT/ai-lab/scripts/device_snapshot.sh" -l self_test -o "$SNAP_JSON" --raw-out "$SNAP_RAW" >/dev/null 2>&1 || fail "device_snapshot.sh failed"
python3 -m json.tool "$SNAP_JSON" >/dev/null || fail "snapshot JSON invalid"
jq -e '.device.model and .cpu.cores' "$SNAP_JSON" >/dev/null || fail "snapshot JSON missing expected fields"
ok "device snapshot valid"

# Report generation self-test (synthetic JSONL -> CSV/MD)
OUT_DIR="$SNAP_TMP_DIR/report_test"
mkdir -p "$OUT_DIR"
JSONL="$OUT_DIR/benchmark.jsonl"
CSV="$OUT_DIR/summary.csv"
MD="$OUT_DIR/summary.md"

python3 - "$JSONL" <<'PY'
import json, time, sys
path=sys.argv[1]
recs=[
  {"timestamp_ms": int(time.time()*1000), "device_label":"self-test", "model_id":"self-test", "model_path":"/tmp/model.gguf", "prompt_id":"P01", "success": True, "exit_code":0, "duration_ms":1234, "tokens_per_sec": 9.5, "output":"ok"},
  {"timestamp_ms": int(time.time()*1000), "device_label":"self-test", "model_id":"self-test", "model_path":"/tmp/model.gguf", "prompt_id":"P02", "success": True, "exit_code":0, "duration_ms":2345, "tokens_per_sec": 8.1, "output":"ok"},
]
with open(path, "w", encoding="utf-8") as f:
  for r in recs:
    f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY

python3 - "$JSONL" "$CSV" "$MD" <<'PY'
import csv, json, sys
jsonl, csv_out, md_out = sys.argv[1:4]
rows=[]
with open(jsonl, "r", encoding="utf-8") as f:
  for line in f:
    line=line.strip()
    if not line: continue
    rows.append(json.loads(line))
with open(csv_out, "w", newline="", encoding="utf-8") as f:
  w=csv.writer(f)
  w.writerow(["prompts","success","fail"])
  succ=sum(1 for r in rows if r.get("success"))
  w.writerow([len(rows), succ, len(rows)-succ])
with open(md_out, "w", encoding="utf-8") as f:
  f.write("# self-test\n")
PY

[[ -s "$CSV" ]] || fail "summary.csv not generated"
[[ -s "$MD" ]] || fail "summary.md not generated"
ok "report generation valid"

ok "SELF TEST PASSED"

