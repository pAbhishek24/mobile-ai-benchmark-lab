#!/usr/bin/env bash
set -euo pipefail

# push_benchmark_report.sh
#
# Adds and pushes a benchmark report directory under ai-lab/results/.
# It will NOT add any model binaries.
#
# Usage:
#   ./ai-lab/scripts/push_benchmark_report.sh \
#     --result-dir ai-lab/results/samsung-s24-ultra/qwen2.5-1.5b-q4km/<timestamp>
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RESULT_DIR=""

usage() {
  echo "Usage: $0 --result-dir <path>"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --result-dir) RESULT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -n "$RESULT_DIR" ]] || usage
cd "$REPO_ROOT"

[[ -d "$RESULT_DIR" ]] || { echo "ERROR: result dir not found: $RESULT_DIR"; exit 1; }

# Basic guardrails: must live under ai-lab/results/
case "$RESULT_DIR" in
  ai-lab/results/*) ;;
  */ai-lab/results/*) ;;
  *)
    echo "ERROR: --result-dir must be under ai-lab/results/"
    exit 1
    ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: not a git repo"; exit 1; }

DEVICE="$(echo "$RESULT_DIR" | awk -F'/' '{print $(NF-2)}')"
MODEL="$(echo "$RESULT_DIR" | awk -F'/' '{print $(NF-1)}')"

echo "Result dir: $RESULT_DIR"
echo "Device    : $DEVICE"
echo "Model     : $MODEL"

# Only add the known report artifacts.
git add \
  "$RESULT_DIR/benchmark.jsonl" \
  "$RESULT_DIR/summary.csv" \
  "$RESULT_DIR/summary.md" \
  "$RESULT_DIR/snapshot_before.json" \
  "$RESULT_DIR/snapshot_after.json"

# Ensure we didn't accidentally stage model files.
if git diff --cached --name-only | grep -E '\.gguf$' >/dev/null 2>&1; then
  echo "ERROR: attempted to stage a .gguf model file. Aborting."
  git reset
  exit 1
fi

if git diff --cached --quiet; then
  echo "Nothing staged. Did you run the evaluation runner?"
  exit 0
fi

git commit -m "ai-lab: add benchmark report for $DEVICE $MODEL"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "phase-3-ai-lab" ]]; then
  echo "WARNING: current branch is '$CURRENT_BRANCH' (expected phase-3-ai-lab)."
fi

git push origin "$CURRENT_BRANCH"

echo "Pushed report commit to $CURRENT_BRANCH"

