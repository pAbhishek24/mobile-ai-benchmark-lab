#!/usr/bin/env bash
set -euo pipefail

# run_model_evaluation.sh
#
# End-to-end benchmark runner for Termux + llama.cpp.
# Never blocks forever — every prompt has a hard per-prompt timeout.
#
# Usage (full run):
#   ./ai-lab/scripts/run_model_evaluation.sh \
#     --model qwen2.5-1.5b-q4km \
#     --device-label samsung-s24-ultra \
#     --max-tokens 256
#
# Smoke test (2 prompts, 64 tokens — runs in ~2 minutes):
#   ./ai-lab/scripts/run_model_evaluation.sh \
#     --model qwen2.5-1.5b-q4km \
#     --device-label samsung-s24-ultra \
#     --smoke
#
# Flags:
#   --prompt-timeout 90   kill a hanging prompt after N seconds (default: 90)
#   --smoke               run only first 2 prompts with max-tokens=64
#   --resume              skip prompt IDs already in benchmark.jsonl
#   --debug               write bash xtrace to logs/debug_trace.log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODEL_ID=""
DEVICE_LABEL=""
MAX_TOKENS=256
THREADS="${THREADS:-}"
PROMPTS_FILE="$REPO_ROOT/ai-lab/prompts/finance-benchmark-prompts.json"
PROMPT_TIMEOUT=90
COOLDOWN_SECONDS=30
THERMAL_WARN_C=60.0
EXTRA_COOLDOWN_ON_WARN_SECONDS=60
SMOKE=0
DEBUG=0
RESUME=0

usage() {
  cat <<EOF
Usage: $0 --model <model-id> --device-label <label> [options]

Required:
  --model <id>             Model ID from model-registry.json
  --device-label <label>   Device label for result path (e.g. samsung-s24-ultra)

Options:
  --max-tokens N           Max tokens per prompt (default: 256; --smoke overrides to 64)
  --threads N              CPU threads (default: 4; use 8 only for stress testing)
  --prompt-timeout N       Kill prompt after N seconds (default: 90)
  --cooldown-seconds N     Sleep N seconds between prompts (default: 30)
  --smoke                  Run first 2 prompts only, max-tokens=48 (thermal-safe sanity check)
  --prompts <path>         Override prompts JSON file
  --resume                 Skip prompt IDs already in benchmark.jsonl
  --debug                  Write bash xtrace to logs dir
  -h, --help               Show this help
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)          MODEL_ID="${2:-}";        shift 2 ;;
    --device-label)   DEVICE_LABEL="${2:-}";    shift 2 ;;
    --max-tokens)     MAX_TOKENS="${2:-}";       shift 2 ;;
    --threads)        THREADS="${2:-}";          shift 2 ;;
    --prompt-timeout) PROMPT_TIMEOUT="${2:-}";  shift 2 ;;
    --cooldown-seconds) COOLDOWN_SECONDS="${2:-}"; shift 2 ;;
    --prompts)        PROMPTS_FILE="${2:-}";     shift 2 ;;
    --smoke)          SMOKE=1;                  shift 1 ;;
    --debug)          DEBUG=1;                  shift 1 ;;
    --resume)         RESUME=1;                 shift 1 ;;
    -h|--help)        usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -n "$MODEL_ID" ]]     || { echo "ERROR: --model is required";        usage; }
[[ -n "$DEVICE_LABEL" ]] || { echo "ERROR: --device-label is required"; usage; }
[[ -f "$PROMPTS_FILE" ]] || { echo "ERROR: prompts file not found: $PROMPTS_FILE"; exit 1; }

if [[ "$SMOKE" -eq 1 ]]; then
  MAX_TOKENS=48
  THREADS="${THREADS:-4}"
  COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-30}"
  echo "[smoke] Smoke mode: 2 prompts, max-tokens=48, threads=${THREADS}, cooldown=${COOLDOWN_SECONDS}s"
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

bytes_of_file() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || wc -c <"$1"; }

now_ms() {
  if date +%s%3N >/dev/null 2>&1; then date +%s%3N
  else python3 -c "import time; print(int(time.time()*1000))"; fi
}

iso_ts() {
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))"
}

sanitize_label() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9._-'
}

detect_llama_bin() {
  for candidate in \
    "$(command -v llama-cli 2>/dev/null || true)" \
    "$HOME/llama.cpp/build/bin/llama-cli" \
    "$(command -v main 2>/dev/null || true)" \
    "$HOME/llama.cpp/main"; do
    [[ -n "$candidate" && -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  echo ""
}

# Fast thermal read (max temp across thermal_zone*/temp). Returns empty if unavailable.
max_temp_c() {
  python3 - <<'PY' 2>/dev/null || true
import os
base="/sys/class/thermal"
temps=[]
try:
    for name in os.listdir(base):
        p=os.path.join(base,name,"temp")
        if not os.path.isfile(p): 
            continue
        try:
            raw=int(open(p).read().strip())
            c=raw/1000.0 if raw>1000 else raw/10.0 if raw>100 else float(raw)
            temps.append(c)
        except Exception:
            pass
except Exception:
    pass
if temps:
    print(f"{max(temps):.1f}")
PY
}

# run_with_timeout: run command with a time limit.
# Returns via temp files (avoids subshell variable scope issues):
#   _TO_FILE  — "1" if timed out, else "0"
#   _EC_FILE  — exit code
#   _STDOUT_FILE — stdout
#   _STDERR_FILE — stderr
_TO_FILE=""
_EC_FILE=""
_STDOUT_FILE=""
_STDERR_FILE=""

init_timeout_files() {
  _TO_FILE=$(mktemp)
  _EC_FILE=$(mktemp)
  _STDOUT_FILE=$(mktemp)
  _STDERR_FILE=$(mktemp)
  echo "0"   >"$_TO_FILE"
  echo "0"   >"$_EC_FILE"
}

run_with_timeout() {
  local timeout_secs="$1"; shift
  echo "0" >"$_TO_FILE"
  : >"$_STDOUT_FILE"
  : >"$_STDERR_FILE"

  if command -v timeout >/dev/null 2>&1; then
    set +e
    timeout "$timeout_secs" "$@" >"$_STDOUT_FILE" 2>"$_STDERR_FILE"
    local ec=$?
    set -e
    echo "$ec" >"$_EC_FILE"
    if [[ $ec -eq 124 ]]; then echo "1" >"$_TO_FILE"; fi
  else
    # Fallback: background + manual kill loop
    "$@" >"$_STDOUT_FILE" 2>"$_STDERR_FILE" &
    local bg_pid=$! elapsed=0
    while kill -0 "$bg_pid" 2>/dev/null; do
      sleep 1; elapsed=$((elapsed+1))
      if [[ $elapsed -ge $timeout_secs ]]; then
        kill -TERM "$bg_pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$bg_pid" 2>/dev/null || true
        echo "1" >"$_TO_FILE"
        break
      fi
    done
    set +e; wait "$bg_pid" 2>/dev/null; local ec=$?; set -e
    echo "$ec" >"$_EC_FILE"
  fi
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required (pkg install python)"; exit 1; }
command -v awk     >/dev/null 2>&1 || { echo "ERROR: awk required"; exit 1; }
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || \
  { echo "ERROR: curl or wget required"; exit 1; }

SAFE_DEVICE_LABEL="$(sanitize_label "$DEVICE_LABEL")"
SAFE_MODEL_ID="$(sanitize_label "$MODEL_ID")"

LLAMA_BIN="$(detect_llama_bin)"
[[ -n "$LLAMA_BIN" ]] || {
  echo "ERROR: llama.cpp binary not found."
  echo "Build llama.cpp and place llama-cli in PATH or ~/llama.cpp/build/bin/llama-cli"
  exit 1
}

# Thermal-safe default: 4 threads unless explicitly overridden.
[[ -z "$THREADS" ]] && THREADS="4"

# ── Model download ────────────────────────────────────────────────────────────

"$SCRIPT_DIR/download_model.sh" --model "$MODEL_ID"

REGISTRY_PATH="$REPO_ROOT/ai-lab/models/model-registry.json"
if command -v jq >/dev/null 2>&1; then
  MODEL_FILE="$(jq -r --arg id "$MODEL_ID" '.models[] | select(.id==$id) | .expectedFilename' "$REGISTRY_PATH")"
else
  MODEL_FILE="$(python3 - "$REGISTRY_PATH" "$MODEL_ID" <<'PY'
import json, sys
path, mid = sys.argv[1], sys.argv[2]
for m in json.load(open(path)).get("models", []):
    if m.get("id") == mid:
        print(m.get("expectedFilename", ""))
        break
PY
)"
fi

MODEL_PATH="$HOME/llama.cpp/models/$MODEL_FILE"
[[ -f "$MODEL_PATH" ]] || { echo "ERROR: model file missing: $MODEL_PATH"; exit 1; }
MODEL_MB=$(( $(bytes_of_file "$MODEL_PATH") / 1024 / 1024 ))

# ── Output dirs ───────────────────────────────────────────────────────────────

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="$REPO_ROOT/ai-lab/results/$SAFE_DEVICE_LABEL/$SAFE_MODEL_ID/$TIMESTAMP"
LOG_DIR="$REPO_ROOT/ai-lab/logs/$SAFE_DEVICE_LABEL/$SAFE_MODEL_ID/$TIMESTAMP"
mkdir -p "$RESULT_DIR" "$LOG_DIR"

if [[ "$DEBUG" -eq 1 ]]; then
  exec 3>"$LOG_DIR/debug_trace.log"
  export BASH_XTRACEFD=3
  set -x
fi

SNAP_BEFORE="$RESULT_DIR/snapshot_before.json"
SNAP_AFTER="$RESULT_DIR/snapshot_after.json"
JSONL_OUT="$RESULT_DIR/benchmark.jsonl"
CSV_OUT="$RESULT_DIR/summary.csv"
MD_OUT="$RESULT_DIR/summary.md"
RAW_BENCH_LOG="$LOG_DIR/benchmark_raw.log"
RAW_SNAP_BEFORE="$LOG_DIR/snapshot_before.raw.txt"
RAW_SNAP_AFTER="$LOG_DIR/snapshot_after.raw.txt"
COUNT_FILE="$LOG_DIR/counts.txt"

printf "debug=%s resume=%s smoke=%s\nprompt_timeout=%s\ndevice_label=%s\nmodel_id=%s\nllama_bin=%s\nmodel_path=%s\nprompts_file=%s\nmax_tokens=%s\nthreads=%s\n" \
  "$DEBUG" "$RESUME" "$SMOKE" "$PROMPT_TIMEOUT" "$DEVICE_LABEL" "$MODEL_ID" \
  "$LLAMA_BIN" "$MODEL_PATH" "$PROMPTS_FILE" "$MAX_TOKENS" "$THREADS" >"$LOG_DIR/run_flags.txt"
printf "cooldown_seconds=%s\nthermal_warn_c=%s\nextra_cooldown_on_warn_seconds=%s\n" \
  "$COOLDOWN_SECONDS" "$THERMAL_WARN_C" "$EXTRA_COOLDOWN_ON_WARN_SECONDS" >>"$LOG_DIR/run_flags.txt"

echo "0 0 0" >"$COUNT_FILE"   # success fail timeout

echo "============================================================"
echo "AI Lab Evaluation"
echo "Device label   : $DEVICE_LABEL"
echo "Model          : $MODEL_ID (${MODEL_MB}MB)"
echo "Model path     : $MODEL_PATH"
echo "llama.cpp      : $LLAMA_BIN"
echo "Threads        : $THREADS"
echo "Max tokens     : $MAX_TOKENS"
echo "Prompt timeout : ${PROMPT_TIMEOUT}s"
echo "Cooldown       : ${COOLDOWN_SECONDS}s"
echo "Thermal warn   : > ${THERMAL_WARN_C}°C (extra cooldown: ${EXTRA_COOLDOWN_ON_WARN_SECONDS}s)"
if [[ "$SMOKE" -eq 1 ]]; then
  echo "Mode           : SMOKE (2 prompts)"
else
  echo "Mode           : FULL"
fi
echo "Results        : $RESULT_DIR"
echo "Logs           : $LOG_DIR"
echo "============================================================"
echo ""

# ── Snapshot before ───────────────────────────────────────────────────────────

"$SCRIPT_DIR/device_snapshot.sh" -l before -o "$SNAP_BEFORE" --raw-out "$RAW_SNAP_BEFORE"

# ── Load prompts → TSV ────────────────────────────────────────────────────────

PROMPTS_TSV="$RESULT_DIR/prompts.tsv"
python3 - "$PROMPTS_FILE" "$SMOKE" >"$PROMPTS_TSV" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
smoke = sys.argv[2] == "1"
prompts = data.get("prompts", [])
if smoke:
    prompts = prompts[:2]
for p in prompts:
    pid = p.get("id", "")
    prompt = p.get("prompt", "").replace("\n", " ").strip()
    if pid and prompt:
        sys.stdout.write(f"{pid}\t{prompt}\n")
PY

TOTAL_PROMPTS="$(wc -l <"$PROMPTS_TSV" | tr -d ' ')"
echo "Prompts to run : $TOTAL_PROMPTS"
echo ""

if [[ "$RESUME" -eq 1 && -f "$JSONL_OUT" ]]; then
  echo "Resume enabled: appending to existing results"
else
  : >"$JSONL_OUT"
fi
: >"$RAW_BENCH_LOG"

DONE_IDS_FILE="$LOG_DIR/done_prompt_ids.txt"
python3 - "$JSONL_OUT" >"$DONE_IDS_FILE" 2>/dev/null <<'PY' || true
import json, sys, os
done = set()
path = sys.argv[1]
if os.path.isfile(path):
    for line in open(path, "r", encoding="utf-8"):
        line = line.strip()
        if line:
            try:
                pid = json.loads(line).get("prompt_id")
                if pid: done.add(pid)
            except Exception: pass
print("\n".join(sorted(done)))
PY

# ── Initialize timeout temp files (created once, reused per prompt) ───────────

init_timeout_files

# ── Per-prompt runner ─────────────────────────────────────────────────────────

run_one_prompt() {
  local prompt_id="$1"
  local prompt_text="$2"

  local start_ts end_ts start_ms end_ms duration_ms status exit_code tok_per_sec
  local t_before t_after thermal_warning extra_pause
  t_before="$(max_temp_c)"

  start_ts="$(iso_ts)"
  start_ms="$(now_ms)"

  local cmd_str="$LLAMA_BIN -m $MODEL_PATH -p \"<prompt>\" -n $MAX_TOKENS -t $THREADS --temp 0.1"
  echo "  start      : $start_ts"
  echo "  binary     : $LLAMA_BIN"
  echo "  command    : $LLAMA_BIN -m ... -n $MAX_TOKENS -t $THREADS --temp 0.1"
  echo "  timeout    : ${PROMPT_TIMEOUT}s"

  run_with_timeout "$PROMPT_TIMEOUT" \
    "$LLAMA_BIN" -m "$MODEL_PATH" -p "$prompt_text" \
    -n "$MAX_TOKENS" -t "$THREADS" --temp 0.1

  local timed_out exit_code_val
  timed_out="$(cat "$_TO_FILE")"
  exit_code_val="$(cat "$_EC_FILE")"
  local out_stdout out_stderr
  out_stdout="$(cat "$_STDOUT_FILE")"
  out_stderr="$(cat "$_STDERR_FILE")"
  t_after="$(max_temp_c)"

  end_ts="$(iso_ts)"
  end_ms="$(now_ms)"
  duration_ms=$(( end_ms - start_ms ))

  if [[ "$timed_out" -eq 1 ]]; then
    status="timeout"
    exit_code=124
  elif [[ "$exit_code_val" -ne 0 ]]; then
    status="error"
    exit_code="$exit_code_val"
  else
    status="ok"
    exit_code=0
  fi

  echo "  end        : $end_ts"
  case "$status" in
    ok)      echo "  duration   : ${duration_ms}ms" ;;
    timeout) echo "  duration   : ${duration_ms}ms  *** TIMEOUT after ${PROMPT_TIMEOUT}s ***" ;;
    error)   echo "  duration   : ${duration_ms}ms  (exit=$exit_code)" ;;
  esac

  # Parse tokens/sec from llama.cpp output
  tok_per_sec=""
  tok_per_sec="$(printf "%s\n" "$out_stderr\n$out_stdout" | grep -Eo '([0-9]+(\.[0-9]+)?) *tok/s' | tail -n1 | awk '{print $1}' 2>/dev/null || true)"
  if [[ -z "$tok_per_sec" ]]; then
    tok_per_sec="$(printf "%s\n" "$out_stderr\n$out_stdout" | grep -Ei 'tokens per second' | grep -Eo '([0-9]+(\.[0-9]+)?)' | tail -n1 2>/dev/null || true)"
  fi
  [[ -n "$tok_per_sec" ]] && echo "  tok/s      : $tok_per_sec"

  # Per-prompt raw logs
  local prompt_log_dir="$LOG_DIR/prompts"
  mkdir -p "$prompt_log_dir"
  local stdout_path="$prompt_log_dir/${prompt_id}.stdout.txt"
  local stderr_path="$prompt_log_dir/${prompt_id}.stderr.txt"
  printf "%s" "$out_stdout" >"$stdout_path"
  printf "%s" "$out_stderr" >"$stderr_path"

  # Combined raw log (human readable)
  {
    echo "----- $prompt_id START ($start_ts) -----"
    echo "CMD: $cmd_str"
    echo "--- STDOUT ---"
    printf "%s\n" "$out_stdout"
    echo "--- STDERR ---"
    printf "%s\n" "$out_stderr"
    echo "--- THERMAL ---"
    echo "temp_before_c=${t_before:-}"
    echo "temp_after_c=${t_after:-}"
    echo "----- $prompt_id END status=$status exit=$exit_code dur=${duration_ms}ms tokps=${tok_per_sec:-} ($end_ts) -----"
    echo ""
  } >>"$RAW_BENCH_LOG"

  thermal_warning="false"
  extra_pause="0"
  if [[ -n "${t_after:-}" ]]; then
    python3 - "$t_after" "$THERMAL_WARN_C" <<'PY' >/dev/null && thermal_warning="true" || true
import sys
after=float(sys.argv[1]); warn=float(sys.argv[2])
raise SystemExit(0 if after > warn else 1)
PY
  fi

  # Write JSONL using Python reading the stdout/stderr files (never via shell string interpolation)
  python3 - \
    "$JSONL_OUT" \
    "$prompt_id" "$status" "$exit_code" "$duration_ms" \
    "${tok_per_sec:-}" "$MODEL_ID" "$MODEL_PATH" \
    "$DEVICE_LABEL" "$start_ts" "$end_ts" "$cmd_str" \
    "$timed_out" "$PROMPT_TIMEOUT" \
    "$stdout_path" "$stderr_path" \
    "${t_before:-}" "${t_after:-}" "$thermal_warning" \
    <<'PY'
import json, sys, time, re

(jsonl_out,
 prompt_id, status, exit_code, duration_ms,
 tokps, model_id, model_path, device_label,
 start_ts, end_ts, cmd_executed, timed_out, prompt_timeout,
 stdout_path, stderr_path,
 temp_before_c, temp_after_c, thermal_warning) = sys.argv[1:20]

def read_text(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return ""

raw_stdout = read_text(stdout_path)
raw_stderr = read_text(stderr_path)

# Heuristic: attempt to strip obvious timing/system logs if they appear in stdout.
# Keep it conservative: we prefer returning more text rather than accidentally removing content.
def strip_llama_logs(text: str) -> str:
    lines = text.splitlines()
    out = []
    for ln in lines:
        l = ln.strip().lower()
        if not l:
            out.append(ln)
            continue
        if "llama_print_timings" in l:
            continue
        if "tokens per second" in l or "tok/s" in l:
            continue
        if l.startswith("prompt eval time") or l.startswith("eval time") or l.startswith("total time"):
            continue
        out.append(ln)
    return "\n".join(out).strip()

answer = strip_llama_logs(raw_stdout)

rec = {
  "timestamp_ms": int(time.time() * 1000),
  "start_ts": start_ts,
  "end_ts": end_ts,
  "device_label": device_label,
  "model_id": model_id,
  "model_path": model_path,
  "prompt_id": prompt_id,
  "status": status,
  "timed_out": timed_out == "1",
  "prompt_timeout_s": int(prompt_timeout),
  "exit_code": int(exit_code),
  "duration_ms": int(duration_ms),
  "tokens_per_sec": float(tokps) if tokps else None,
  "cmd": cmd_executed,
  "output": answer,
  "stderr": raw_stderr,
  "raw_stdout_path": stdout_path,
  "raw_stderr_path": stderr_path,
  "temp_before_c": float(temp_before_c) if temp_before_c else None,
  "temp_after_c": float(temp_after_c) if temp_after_c else None,
  "thermal_warning": (thermal_warning == "true"),
}

with open(jsonl_out, "a", encoding="utf-8") as f:
  f.write(json.dumps(rec, ensure_ascii=False) + "\n")
PY

  # Validate JSONL line is parseable
  tail -n 1 "$JSONL_OUT" | python3 -m json.tool >/dev/null

  # Update counters (file-based to survive function scope)
  local sc fc tc
  read -r sc fc tc <"$COUNT_FILE"
  case "$status" in
    ok)      sc=$((sc+1)) ;;
    timeout) tc=$((tc+1)) ;;
    *)       fc=$((fc+1)) ;;
  esac
  echo "$sc $fc $tc" >"$COUNT_FILE"

  # Thermal-aware cooldown
  if [[ "$thermal_warning" == "true" ]]; then
    echo "  thermal    : WARNING (temp_after_c=${t_after} > ${THERMAL_WARN_C})"
    extra_pause="$EXTRA_COOLDOWN_ON_WARN_SECONDS"
  fi

  if [[ "$COOLDOWN_SECONDS" -gt 0 ]]; then
    sleep "$COOLDOWN_SECONDS"
  fi
  if [[ "$extra_pause" -gt 0 ]]; then
    sleep "$extra_pause"
  fi
}

# ── Prompt loop ───────────────────────────────────────────────────────────────

i=0
while IFS=$'\t' read -r pid prompt; do
  i=$(( i+1 ))
  echo "[$i/$TOTAL_PROMPTS] $pid"

  if [[ "$RESUME" -eq 1 ]] && grep -qx "$pid" "$DONE_IDS_FILE" 2>/dev/null; then
    echo "  skipping (already done)"
    echo ""
    continue
  fi

  run_one_prompt "$pid" "$prompt"
  echo ""
done <"$PROMPTS_TSV"

# ── Cleanup timeout temp files ────────────────────────────────────────────────
# FIX: _OUT_FILE was split into _STDOUT_FILE + _STDERR_FILE; old name was unbound under set -u.

rm -f "$_TO_FILE" "$_EC_FILE" "$_STDOUT_FILE" "$_STDERR_FILE"

# ── Snapshot after ────────────────────────────────────────────────────────────

"$SCRIPT_DIR/device_snapshot.sh" -l after -o "$SNAP_AFTER" --raw-out "$RAW_SNAP_AFTER"

# ── Build summary ─────────────────────────────────────────────────────────────

python3 - "$JSONL_OUT" "$CSV_OUT" "$MD_OUT" \
  "$DEVICE_LABEL" "$MODEL_ID" "$MODEL_MB" "$MAX_TOKENS" "$THREADS" "$LLAMA_BIN" "$PROMPT_TIMEOUT" \
  <<'PY'
import csv, json, sys

jsonl, csv_out, md_out, device, model, model_mb, max_tokens, threads, llama_bin, prompt_timeout = sys.argv[1:11]

rows = []
with open(jsonl, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

def p50(xs):
    if not xs: return None
    return sorted(xs)[len(xs) // 2]

durations  = [r["duration_ms"]    for r in rows if r.get("status") == "ok"]
tokps_vals = [r["tokens_per_sec"] for r in rows if r.get("status") == "ok" and r.get("tokens_per_sec")]
success_n  = sum(1 for r in rows if r.get("status") == "ok")
timeout_n  = sum(1 for r in rows if r.get("status") == "timeout")
error_n    = sum(1 for r in rows if r.get("status") not in ("ok", "timeout"))
output_present_n = sum(1 for r in rows if (r.get("output") or "").strip())
thermal_warn_n = sum(1 for r in rows if r.get("thermal_warning") is True)

def max_temp_from_snapshot(path):
    try:
        snap=json.load(open(path,"r",encoding="utf-8"))
        zones=snap.get("thermal",{}).get("zones",[])
        if not zones: return None
        return max(z.get("temp_c",0) for z in zones)
    except Exception:
        return None

snap_before = None
snap_after = None
try:
    # The runner always places snapshots in the same folder as JSONL.
    # Derive snapshot paths from csv_out parent.
    import os
    result_dir = os.path.dirname(csv_out)
    sb=os.path.join(result_dir,"snapshot_before.json")
    sa=os.path.join(result_dir,"snapshot_after.json")
    snap_before=max_temp_from_snapshot(sb)
    snap_after=max_temp_from_snapshot(sa)
except Exception:
    pass

with open(csv_out, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["device_label","model_id","model_mb","prompts","success","timeout","error",
                "p50_duration_ms","p50_tokens_per_sec","max_tokens","threads","prompt_timeout_s",
                "output_present","thermal_warning_count","max_temp_before_c","max_temp_after_c","llama_bin"])
    w.writerow([device, model, model_mb, len(rows), success_n, timeout_n, error_n,
                p50(durations), p50(tokps_vals), max_tokens, threads, prompt_timeout,
                output_present_n, thermal_warn_n, snap_before, snap_after, llama_bin])
    w.writerow([])
    w.writerow(["prompt_id","status","duration_ms","tokens_per_sec","timed_out","start_ts","end_ts"])
    for r in rows:
        w.writerow([r.get("prompt_id"), r.get("status"), r.get("duration_ms"),
                    r.get("tokens_per_sec"), r.get("timed_out"),
                    r.get("start_ts"), r.get("end_ts")])

icon = {"ok": "✅", "timeout": "⏱", "error": "❌"}
lines = [
    "# AI Lab Benchmark Summary", "",
    "| Field | Value |", "|---|---|",
    f"| Device | `{device}` |",
    f"| Model | `{model}` ({model_mb} MB) |",
    f"| llama.cpp | `{llama_bin}` |",
    f"| Max tokens | {max_tokens} |",
    f"| Threads | {threads} |",
    f"| Prompt timeout | {prompt_timeout}s |",
    f"| Output capture | {output_present_n}/{len(rows)} prompts have non-empty output |",
    (f"| Max temp (snapshot before) | {snap_before} °C |" if snap_before is not None else "| Max temp (snapshot before) | — |"),
    (f"| Max temp (snapshot after) | {snap_after} °C |" if snap_after is not None else "| Max temp (snapshot after) | — |"),
    "", "## Results", "",
    "| Metric | Value |", "|---|---|",
    f"| Total prompts | {len(rows)} |",
    f"| ✅ Success | {success_n} |",
    f"| ⏱ Timeout | {timeout_n} |",
    f"| ❌ Error | {error_n} |",
    f"| 🌡 Thermal warnings | {thermal_warn_n} |",
    (f"| p50 duration | {p50(durations)} ms |" if durations else "| p50 duration | — |"),
    (f"| p50 tokens/sec | {p50(tokps_vals)} |" if tokps_vals else "| p50 tokens/sec | — |"),
    "", "## Per-Prompt", "",
    "| Prompt | Status | Duration (ms) | Tok/s | Timed out |",
    "|---|---|---:|---:|:---:|",
]
for r in rows:
    s = r.get("status", "?")
    lines.append(
        f"| {r.get('prompt_id')} | {icon.get(s,'?')} {s} "
        f"| {r.get('duration_ms')} | {r.get('tokens_per_sec') or ''} "
        f"| {'yes' if r.get('timed_out') else 'no'} |"
    )
lines.append("")
open(md_out, "w", encoding="utf-8").write("\n".join(lines))
print("summary_ok")
PY

# ── Validate outputs ──────────────────────────────────────────────────────────

python3 - "$JSONL_OUT" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line: json.loads(line)
print("jsonl_ok")
PY

python3 -m json.tool "$SNAP_BEFORE" >/dev/null
python3 -m json.tool "$SNAP_AFTER"  >/dev/null
[[ -s "$CSV_OUT" ]] || { echo "ERROR: summary.csv is empty"; exit 1; }
[[ -s "$MD_OUT"  ]] || { echo "ERROR: summary.md is empty";  exit 1; }

python3 - "$CSV_OUT" <<'PY'
import csv, sys
rows = list(csv.reader(open(sys.argv[1], "r", newline="", encoding="utf-8")))
if not rows or not rows[0]: raise SystemExit("csv_invalid")
print("csv_ok")
PY

# ── Final summary ─────────────────────────────────────────────────────────────

read -r SUCCESS_COUNT FAIL_COUNT TIMEOUT_COUNT <"$COUNT_FILE"
TOTAL_RAN=$(( SUCCESS_COUNT + FAIL_COUNT + TIMEOUT_COUNT ))

echo ""
echo "============================================================"
echo "  BENCHMARK COMPLETE"
echo "============================================================"
echo "  Prompts run  : $TOTAL_RAN / $TOTAL_PROMPTS"
echo "  ✅ Success   : $SUCCESS_COUNT"
echo "  ⏱ Timeout   : $TIMEOUT_COUNT  (limit: ${PROMPT_TIMEOUT}s each)"
echo "  ❌ Error     : $FAIL_COUNT"
echo "------------------------------------------------------------"
echo "  JSONL        : $JSONL_OUT"
echo "  CSV          : $CSV_OUT"
echo "  MD           : $MD_OUT"
echo "  Snapshot ▶   : $SNAP_BEFORE"
echo "  Snapshot ◀   : $SNAP_AFTER"
echo "  Raw logs     : $LOG_DIR"
echo "============================================================"

if [[ "$TIMEOUT_COUNT" -gt 0 ]]; then
  echo ""
  echo "NOTE: $TIMEOUT_COUNT prompt(s) timed out after ${PROMPT_TIMEOUT}s."
  echo "      Try --prompt-timeout 120 or check llama.cpp output for stuck state."
fi

echo ""
echo "Paste $JSONL_OUT contents back for analysis."
