#!/usr/bin/env bash
set -euo pipefail

# run_model_evaluation.sh
#
# End-to-end benchmark runner for Termux + llama.cpp:
# - Ensures tools exist
# - Downloads model if missing (via download_model.sh)
# - Captures device snapshots before/after
# - Runs all prompts in ai-lab/prompts/finance-benchmark-prompts.json
# - Writes per-prompt JSONL + summary CSV/MD
#
# Usage:
#   ./ai-lab/scripts/run_model_evaluation.sh \
#     --model qwen2.5-1.5b-q4km \
#     --device-label samsung-s24-ultra \
#     --max-tokens 256
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODEL_ID=""
DEVICE_LABEL=""
MAX_TOKENS=256
THREADS="${THREADS:-}"
PROMPTS_FILE="$REPO_ROOT/ai-lab/prompts/finance-benchmark-prompts.json"

usage() {
  echo "Usage: $0 --model <model-id> --device-label <label> [--max-tokens N] [--threads N] [--prompts path]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_ID="${2:-}"; shift 2 ;;
    --device-label) DEVICE_LABEL="${2:-}"; shift 2 ;;
    --max-tokens) MAX_TOKENS="${2:-}"; shift 2 ;;
    --threads) THREADS="${2:-}"; shift 2 ;;
    --prompts) PROMPTS_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -n "$MODEL_ID" ]] || usage
[[ -n "$DEVICE_LABEL" ]] || usage
[[ -f "$PROMPTS_FILE" ]] || { echo "ERROR: prompts file not found: $PROMPTS_FILE"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1"; exit 1; }
}

bytes_of_file() {
  local f="$1"
  stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || wc -c <"$f"
}

now_ms() {
  # date +%s%3N is not always available; python fallback is consistent.
  if date +%s%3N >/dev/null 2>&1; then
    date +%s%3N
  else
    python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
  fi
}

json_quote() {
  # Reads stdin and prints a JSON string literal.
  python3 - <<'PY'
import json, sys
print(json.dumps(sys.stdin.read()))
PY
}

detect_llama_bin() {
  if command -v llama-cli >/dev/null 2>&1; then
    echo "$(command -v llama-cli)"
    return 0
  fi
  if [[ -x "$HOME/llama.cpp/build/bin/llama-cli" ]]; then
    echo "$HOME/llama.cpp/build/bin/llama-cli"
    return 0
  fi
  if command -v llava-cli >/dev/null 2>&1; then
    echo "$(command -v llava-cli)"
    return 0
  fi
  if [[ -x "$HOME/llama.cpp/build/bin/llava-cli" ]]; then
    echo "$HOME/llama.cpp/build/bin/llava-cli"
    return 0
  fi
  if command -v main >/dev/null 2>&1; then
    echo "$(command -v main)"
    return 0
  fi
  if [[ -x "$HOME/llama.cpp/main" ]]; then
    echo "$HOME/llama.cpp/main"
    return 0
  fi
  echo ""
}

need_cmd python3

LLAMA_BIN="$(detect_llama_bin)"
[[ -n "$LLAMA_BIN" ]] || {
  echo "ERROR: Could not find llama.cpp CLI binary."
  echo "Expected one of: llama-cli (preferred), or main."
  echo "Tip (Termux): build llama.cpp and ensure llama-cli is in PATH, or placed in ~/llama.cpp/build/bin/llama-cli"
  exit 1
}

if [[ -z "$THREADS" ]]; then
  THREADS="$(nproc 2>/dev/null || echo 4)"
fi

# 1) Download model if missing
"$SCRIPT_DIR/download_model.sh" --model "$MODEL_ID"

# Resolve actual model path from registry (expected filename).
REGISTRY_PATH="$REPO_ROOT/ai-lab/models/model-registry.json"
if command -v jq >/dev/null 2>&1; then
  MODEL_FILE="$(jq -r --arg id "$MODEL_ID" '.models[] | select(.id==$id) | .expectedFilename' "$REGISTRY_PATH")"
else
  MODEL_FILE="$(python3 - "$REGISTRY_PATH" "$MODEL_ID" <<'PY'
import json, sys
path, model_id = sys.argv[1], sys.argv[2]
data=json.load(open(path,"r",encoding="utf-8"))
for m in data.get("models", []):
    if m.get("id")==model_id:
        print(m.get("expectedFilename",""))
        break
PY
  )"
fi

MODEL_PATH="$HOME/llama.cpp/models/$MODEL_FILE"
[[ -f "$MODEL_PATH" ]] || { echo "ERROR: model file missing after download: $MODEL_PATH"; exit 1; }
MODEL_BYTES="$(bytes_of_file "$MODEL_PATH")"
MODEL_MB=$(( MODEL_BYTES / 1024 / 1024 ))

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="$REPO_ROOT/ai-lab/results/$DEVICE_LABEL/$MODEL_ID/$TIMESTAMP"
mkdir -p "$RESULT_DIR"

SNAP_BEFORE="$RESULT_DIR/snapshot_before.json"
SNAP_AFTER="$RESULT_DIR/snapshot_after.json"
JSONL_OUT="$RESULT_DIR/benchmark.jsonl"
CSV_OUT="$RESULT_DIR/summary.csv"
MD_OUT="$RESULT_DIR/summary.md"

echo "============================================================"
echo "AI Lab Evaluation"
echo "Device label : $DEVICE_LABEL"
echo "Model id     : $MODEL_ID"
echo "Model path   : $MODEL_PATH (${MODEL_MB}MB)"
echo "Prompts      : $PROMPTS_FILE"
echo "llama.cpp    : $LLAMA_BIN"
echo "Threads      : $THREADS"
echo "Max tokens   : $MAX_TOKENS"
echo "Results dir  : $RESULT_DIR"
echo "============================================================"

"$SCRIPT_DIR/device_snapshot.sh" -l before -o "$SNAP_BEFORE" || true

# Extract prompts as TSV: id \t prompt
PROMPTS_TSV="$RESULT_DIR/prompts.tsv"
python3 - "$PROMPTS_FILE" >"$PROMPTS_TSV" <<'PY'
import json, sys
data=json.load(open(sys.argv[1], "r", encoding="utf-8"))
for p in data.get("prompts", []):
    pid = p.get("id", "")
    prompt = p.get("prompt", "").replace("\n", " ").strip()
    if pid and prompt:
        sys.stdout.write(f"{pid}\t{prompt}\n")
PY

TOTAL_PROMPTS="$(wc -l <"$PROMPTS_TSV" | tr -d ' ')"
echo "Prompts count: $TOTAL_PROMPTS"

echo "" >"$JSONL_OUT"

run_one_prompt() {
  local prompt_id="$1"
  local prompt_text="$2"

  local start_ms end_ms duration_ms ok exit_code output tokps
  start_ms="$(now_ms)"

  # Most llama.cpp CLIs accept: -m model -p prompt -n max_tokens -t threads
  # Keep temperature low for deterministic-ish answers.
  set +e
  output="$("$LLAMA_BIN" -m "$MODEL_PATH" -p "$prompt_text" -n "$MAX_TOKENS" -t "$THREADS" --temp 0.1 2>&1)"
  exit_code=$?
  set -e

  end_ms="$(now_ms)"
  duration_ms=$(( end_ms - start_ms ))
  ok="true"
  if [[ $exit_code -ne 0 ]]; then
    ok="false"
  fi

  # Best-effort tokens/sec parse from llama.cpp output
  tokps="$(printf "%s\n" "$output" | grep -Eo '([0-9]+(\.[0-9]+)?) *tok/s' | tail -n1 | awk '{print $1}' || true)"
  if [[ -z "$tokps" ]]; then
    tokps="$(printf "%s\n" "$output" | grep -Ei 'tokens per second' | tail -n1 | grep -Eo '([0-9]+(\.[0-9]+)?)' | tail -n1 || true)"
  fi

  printf "%s" "$output" | python3 - "$prompt_id" "$ok" "$exit_code" "$duration_ms" "$tokps" "$MODEL_ID" "$MODEL_PATH" "$DEVICE_LABEL" <<'PY' >>"$JSONL_OUT"
import json, sys
prompt_id, ok, exit_code, duration_ms, tokps, model_id, model_path, device_label = sys.argv[1:9]
output = sys.stdin.read()
rec = {
  "timestamp_ms": int(__import__("time").time() * 1000),
  "device_label": device_label,
  "model_id": model_id,
  "model_path": model_path,
  "prompt_id": prompt_id,
  "success": ok == "true",
  "exit_code": int(exit_code),
  "duration_ms": int(duration_ms),
  "tokens_per_sec": float(tokps) if tokps else None,
  "output": output
}
print(json.dumps(rec, ensure_ascii=False))
PY
}

i=0
while IFS=$'\t' read -r pid prompt; do
  i=$((i+1))
  echo "[$i/$TOTAL_PROMPTS] $pid"
  run_one_prompt "$pid" "$prompt"
done <"$PROMPTS_TSV"

"$SCRIPT_DIR/device_snapshot.sh" -l after -o "$SNAP_AFTER" || true

# Build summary CSV + MD from JSONL using Python
python3 - "$JSONL_OUT" "$CSV_OUT" "$MD_OUT" "$DEVICE_LABEL" "$MODEL_ID" "$MODEL_MB" "$MAX_TOKENS" "$THREADS" "$LLAMA_BIN" <<'PY'
import csv, json, sys, statistics
jsonl, csv_out, md_out, device, model, model_mb, max_tokens, threads, llama_bin = sys.argv[1:10]
rows=[]
with open(jsonl, "r", encoding="utf-8") as f:
    for line in f:
        line=line.strip()
        if not line: continue
        rows.append(json.loads(line))

durations=[r["duration_ms"] for r in rows if r.get("success")]
tokps=[r["tokens_per_sec"] for r in rows if r.get("tokens_per_sec") is not None and r.get("success")]
successes=sum(1 for r in rows if r.get("success"))
fails=len(rows)-successes

def p50(xs):
    if not xs: return None
    xs=sorted(xs)
    return xs[len(xs)//2]

with open(csv_out, "w", newline="", encoding="utf-8") as f:
    w=csv.writer(f)
    w.writerow(["device_label","model_id","model_mb","prompts","success","fail","p50_duration_ms","p50_tokens_per_sec","max_tokens","threads","llama_bin"])
    w.writerow([device, model, model_mb, len(rows), successes, fails, p50(durations), p50(tokps), max_tokens, threads, llama_bin])
    w.writerow([])
    w.writerow(["prompt_id","success","duration_ms","tokens_per_sec"])
    for r in rows:
        w.writerow([r.get("prompt_id"), r.get("success"), r.get("duration_ms"), r.get("tokens_per_sec")])

lines=[]
lines.append(f"# AI Lab Benchmark Summary")
lines.append("")
lines.append(f"- Device: `{device}`")
lines.append(f"- Model: `{model}` ({model_mb} MB)")
lines.append(f"- llama.cpp binary: `{llama_bin}`")
lines.append(f"- Prompts: {len(rows)}")
lines.append(f"- Success: {successes}  Fail: {fails}")
lines.append(f"- Max tokens: {max_tokens}  Threads: {threads}")
if durations:
    lines.append(f"- p50 duration: {p50(durations)} ms")
if tokps:
    lines.append(f"- p50 tokens/sec: {p50(tokps)}")
lines.append("")
lines.append("## Per-Prompt Results")
lines.append("")
lines.append("| Prompt | Success | Duration (ms) | Tok/s |")
lines.append("|---|---:|---:|---:|")
for r in rows:
    lines.append(f"| {r.get('prompt_id')} | {str(r.get('success')).lower()} | {r.get('duration_ms')} | {r.get('tokens_per_sec') if r.get('tokens_per_sec') is not None else ''} |")
lines.append("")
with open(md_out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
PY

echo ""
echo "DONE"
echo "JSONL : $JSONL_OUT"
echo "CSV   : $CSV_OUT"
echo "MD    : $MD_OUT"
echo "Before: $SNAP_BEFORE"
echo "After : $SNAP_AFTER"
