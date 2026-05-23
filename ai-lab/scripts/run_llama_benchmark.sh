#!/usr/bin/env bash
# run_llama_benchmark.sh
# Runs each prompt in a JSON prompt file through llama.cpp CLI and records results.
#
# Usage:
#   ./run_llama_benchmark.sh -m <model_path> -p <prompts_json> [-n <max_tokens>] [-t <threads>]
#
# Example:
#   ./run_llama_benchmark.sh \
#     -m ~/llama.cpp/models/qwen2.5-1.5b-q4_k_m.gguf \
#     -p ~/personal-finance-assistant/ai-lab/prompts/finance-benchmark-prompts.json
#
# Output:
#   ai-lab/results/benchmark_<model_name>_<timestamp>.jsonl  — one JSON line per prompt
#   ai-lab/results/benchmark_<model_name>_<timestamp>.log    — raw llama.cpp output

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
MAX_TOKENS=256
THREADS=$(nproc 2>/dev/null || echo 4)
TEMPERATURE=0.1
RESULTS_DIR="$(cd "$(dirname "$0")/../results" && pwd)"
LLAMA_CLI="${LLAMA_CLI:-$(command -v llama-cli 2>/dev/null || echo "$HOME/llama.cpp/build/bin/llama-cli")}"

# ── Argument parsing ──────────────────────────────────────────────────────────
MODEL_PATH=""
PROMPTS_FILE=""

usage() {
  echo "Usage: $0 -m <model_path> -p <prompts_json> [-n <max_tokens>] [-t <threads>]"
  echo ""
  echo "  -m  Path to GGUF model file (required)"
  echo "  -p  Path to prompts JSON file (required)"
  echo "  -n  Max tokens to generate per prompt (default: $MAX_TOKENS)"
  echo "  -t  CPU threads (default: all available)"
  exit 1
}

while getopts "m:p:n:t:h" opt; do
  case $opt in
    m) MODEL_PATH="$OPTARG" ;;
    p) PROMPTS_FILE="$OPTARG" ;;
    n) MAX_TOKENS="$OPTARG" ;;
    t) THREADS="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

[ -z "$MODEL_PATH" ] && { echo "ERROR: -m <model_path> is required"; usage; }
[ -z "$PROMPTS_FILE" ] && { echo "ERROR: -p <prompts_json> is required"; usage; }
[ ! -f "$MODEL_PATH" ] && { echo "ERROR: Model file not found: $MODEL_PATH"; exit 1; }
[ ! -f "$PROMPTS_FILE" ] && { echo "ERROR: Prompts file not found: $PROMPTS_FILE"; exit 1; }
[ ! -x "$LLAMA_CLI" ] && { echo "ERROR: llama-cli not found at $LLAMA_CLI"; echo "Set LLAMA_CLI env var or build llama.cpp first."; exit 1; }

# ── Setup ─────────────────────────────────────────────────────────────────────
MODEL_NAME=$(basename "$MODEL_PATH" .gguf)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$RESULTS_DIR"

RESULTS_FILE="$RESULTS_DIR/benchmark_${MODEL_NAME}_${TIMESTAMP}.jsonl"
LOG_FILE="$RESULTS_DIR/benchmark_${MODEL_NAME}_${TIMESTAMP}.log"

echo "======================================================================"
echo "  PersonalFinanceAssistant — AI Benchmark"
echo "======================================================================"
echo "  Model      : $MODEL_NAME"
echo "  Model path : $MODEL_PATH"
echo "  Prompts    : $PROMPTS_FILE"
echo "  Max tokens : $MAX_TOKENS"
echo "  Threads    : $THREADS"
echo "  Results    : $RESULTS_FILE"
echo "  Log        : $LOG_FILE"
echo "======================================================================"
echo ""

# ── Device snapshot (best-effort) ─────────────────────────────────────────────
DEVICE_MODEL=$(getprop ro.product.model 2>/dev/null || cat /proc/cpuinfo 2>/dev/null | grep "Hardware" | head -1 | cut -d: -f2 | xargs || echo "unknown")
ANDROID_VER=$(getprop ro.build.version.release 2>/dev/null || echo "unknown")
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))
MEM_AVAIL_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
MEM_AVAIL_MB=$((MEM_AVAIL_KB / 1024))
STORAGE_FREE=$(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4}' || echo "unknown")

# Battery (Termux API or fallback)
if command -v termux-battery-status &>/dev/null; then
  BATTERY_PCT=$(termux-battery-status 2>/dev/null | grep -o '"percentage": [0-9]*' | grep -o '[0-9]*' || echo "unknown")
else
  BATTERY_PCT=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "unknown")
fi

# Thermal (best-effort)
TEMP_START="unknown"
if ls /sys/class/thermal/thermal_zone0/temp &>/dev/null; then
  RAW_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
  TEMP_START="${RAW_TEMP:0:-3}.${RAW_TEMP: -3:1}°C"
fi

echo "Device     : $DEVICE_MODEL"
echo "Android    : $ANDROID_VER"
echo "RAM total  : ${MEM_TOTAL_MB}MB  |  RAM available: ${MEM_AVAIL_MB}MB"
echo "Storage    : $STORAGE_FREE free"
echo "Battery    : ${BATTERY_PCT}%"
echo "Temp start : $TEMP_START"
echo ""

# Write session header to log
{
  echo "=== Benchmark Session: $TIMESTAMP ==="
  echo "Model: $MODEL_NAME"
  echo "Device: $DEVICE_MODEL  Android: $ANDROID_VER"
  echo "RAM: ${MEM_TOTAL_MB}MB total / ${MEM_AVAIL_MB}MB available"
  echo "Battery at start: ${BATTERY_PCT}%  Temp: $TEMP_START"
  echo ""
} >> "$LOG_FILE"

# ── Read prompts from JSON ─────────────────────────────────────────────────────
# Use python3 (available in Termux via: pkg install python) for JSON parsing
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required to parse prompts JSON."
  echo "Install it with: pkg install python"
  exit 1
fi

PROMPT_COUNT=$(python3 -c "
import json, sys
data = json.load(open('$PROMPTS_FILE'))
print(len(data['prompts']))
")

echo "Running $PROMPT_COUNT prompts..."
echo ""

# ── Run each prompt ────────────────────────────────────────────────────────────
PASS=0
FAIL=0

for i in $(seq 0 $((PROMPT_COUNT - 1))); do

  PROMPT_ID=$(python3 -c "
import json
data = json.load(open('$PROMPTS_FILE'))
print(data['prompts'][$i]['id'])
")
  CATEGORY=$(python3 -c "
import json
data = json.load(open('$PROMPTS_FILE'))
print(data['prompts'][$i]['category'])
")
  PROMPT_TEXT=$(python3 -c "
import json
data = json.load(open('$PROMPTS_FILE'))
print(data['prompts'][$i]['prompt'])
")

  echo "[$PROMPT_ID] $CATEGORY"

  # Capture temp before run
  TEMP_BEFORE="unknown"
  if ls /sys/class/thermal/thermal_zone0/temp &>/dev/null; then
    RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    TEMP_BEFORE="${RAW:0:-3}.${RAW: -3:1}"
  fi

  # Memory before
  MEM_BEFORE=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")

  START_EPOCH=$(date +%s%N 2>/dev/null || date +%s)

  # Run llama-cli and capture full output
  LLAMA_OUTPUT=$("$LLAMA_CLI" \
    --model "$MODEL_PATH" \
    --prompt "$PROMPT_TEXT" \
    --n-predict "$MAX_TOKENS" \
    --threads "$THREADS" \
    --temp "$TEMPERATURE" \
    --log-disable \
    2>&1 || true)

  END_EPOCH=$(date +%s%N 2>/dev/null || date +%s)

  # Duration in ms (nanosecond precision if available)
  if [[ ${#START_EPOCH} -gt 10 ]]; then
    DURATION_MS=$(( (END_EPOCH - START_EPOCH) / 1000000 ))
  else
    DURATION_MS=$(( (END_EPOCH - START_EPOCH) * 1000 ))
  fi

  # Extract tokens/sec from llama.cpp output
  TOKENS_PER_SEC=$(echo "$LLAMA_OUTPUT" | grep -o '[0-9]*\.[0-9]* tokens per second' | grep -o '[0-9]*\.[0-9]*' | tail -1 || echo "")
  if [ -z "$TOKENS_PER_SEC" ]; then
    TOKENS_PER_SEC=$(echo "$LLAMA_OUTPUT" | grep -o 'eval time.*tokens per second' | grep -o '[0-9]*\.[0-9]* tokens' | grep -o '[0-9]*\.[0-9]*' | tail -1 || echo "unknown")
  fi

  # Extract first token latency
  FIRST_TOKEN_MS=$(echo "$LLAMA_OUTPUT" | grep -o 'prompt eval time.*ms per token' | grep -o '[0-9]*\.[0-9]* ms' | head -1 | grep -o '[0-9]*\.[0-9]*' || echo "unknown")

  # Temp after
  TEMP_AFTER="unknown"
  if ls /sys/class/thermal/thermal_zone0/temp &>/dev/null; then
    RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    TEMP_AFTER="${RAW:0:-3}.${RAW: -3:1}"
  fi

  # Memory after
  MEM_AFTER=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
  MEM_DELTA_MB=$(( (MEM_BEFORE - MEM_AFTER) / 1024 ))

  # Extract response text (strip timing lines from llama output)
  RESPONSE_TEXT=$(echo "$LLAMA_OUTPUT" | grep -v "^llama_" | grep -v "^ggml_" | grep -v "^main:" | grep -v "^Log " | grep -v "^system_info" | head -20 | tr '\n' ' ' | xargs)

  # Determine status
  if [ -n "$RESPONSE_TEXT" ] && [ ${#RESPONSE_TEXT} -gt 20 ]; then
    STATUS="ok"
    PASS=$((PASS + 1))
    echo "    ✓ ${DURATION_MS}ms  |  ${TOKENS_PER_SEC} tok/s  |  temp: ${TEMP_BEFORE}→${TEMP_AFTER}°C"
  else
    STATUS="error"
    FAIL=$((FAIL + 1))
    echo "    ✗ FAILED or empty response"
  fi

  # Write JSONL result
  python3 -c "
import json, sys
result = {
    'session': '$TIMESTAMP',
    'model': '$MODEL_NAME',
    'prompt_id': '$PROMPT_ID',
    'category': '$CATEGORY',
    'status': '$STATUS',
    'duration_ms': $DURATION_MS,
    'tokens_per_sec': '${TOKENS_PER_SEC}',
    'first_token_ms': '${FIRST_TOKEN_MS}',
    'temp_before_c': '${TEMP_BEFORE}',
    'temp_after_c': '${TEMP_AFTER}',
    'mem_delta_mb': $MEM_DELTA_MB,
    'response_preview': '${RESPONSE_TEXT:0:200}'.replace(\"'\", '')
}
print(json.dumps(result))
" >> "$RESULTS_FILE"

  # Append to full log
  {
    echo "--- [$PROMPT_ID] $CATEGORY ---"
    echo "Duration: ${DURATION_MS}ms  Tokens/s: ${TOKENS_PER_SEC}  First token: ${FIRST_TOKEN_MS}ms"
    echo "Temp: ${TEMP_BEFORE}°C → ${TEMP_AFTER}°C  |  RAM delta: ${MEM_DELTA_MB}MB"
    echo "PROMPT: $PROMPT_TEXT"
    echo "RESPONSE:"
    echo "$LLAMA_OUTPUT"
    echo ""
  } >> "$LOG_FILE"

done

# ── Final battery reading ──────────────────────────────────────────────────────
BATTERY_END="unknown"
if command -v termux-battery-status &>/dev/null; then
  BATTERY_END=$(termux-battery-status 2>/dev/null | grep -o '"percentage": [0-9]*' | grep -o '[0-9]*' || echo "unknown")
else
  BATTERY_END=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "unknown")
fi

TEMP_END="unknown"
if ls /sys/class/thermal/thermal_zone0/temp &>/dev/null; then
  RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
  TEMP_END="${RAW:0:-3}.${RAW: -3:1}°C"
fi

echo ""
echo "======================================================================"
echo "  BENCHMARK COMPLETE"
echo "======================================================================"
echo "  Passed     : $PASS / $PROMPT_COUNT"
echo "  Failed     : $FAIL / $PROMPT_COUNT"
echo "  Battery    : ${BATTERY_PCT}% → ${BATTERY_END}%"
echo "  Temp end   : $TEMP_END"
echo "  Results    : $RESULTS_FILE"
echo "  Log        : $LOG_FILE"
echo "======================================================================"

# Append summary to log
{
  echo ""
  echo "=== Session Summary ==="
  echo "Passed: $PASS / $PROMPT_COUNT"
  echo "Battery: ${BATTERY_PCT}% → ${BATTERY_END}%"
  echo "Temp end: $TEMP_END"
} >> "$LOG_FILE"

echo ""
echo "Paste the contents of $RESULTS_FILE back for analysis."
