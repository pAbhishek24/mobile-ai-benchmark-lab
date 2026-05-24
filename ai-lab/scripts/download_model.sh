#!/usr/bin/env bash
set -euo pipefail

# download_model.sh
#
# Downloads a GGUF model based on ai-lab/models/model-registry.json into:
#   ~/llama.cpp/models/<expectedFilename>
#
# The model binary must never be stored inside the git repo.
#
# Usage:
#   ./ai-lab/scripts/download_model.sh --model qwen2.5-1.5b-q4km
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY_PATH="$REPO_ROOT/ai-lab/models/model-registry.json"
MODEL_ID=""

usage() {
  echo "Usage: $0 --model <model-id>"
  echo ""
  echo "Example:"
  echo "  $0 --model qwen2.5-1.5b-q4km"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_ID="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -z "$MODEL_ID" ]] && usage
[[ -f "$REGISTRY_PATH" ]] || { echo "ERROR: missing registry: $REGISTRY_PATH"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1"; exit 1; }
}

bytes_of_file() {
  local f="$1"
  if command -v stat >/dev/null 2>&1; then
    # Linux/Termux: stat -c%s ; macOS: stat -f%z
    stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || wc -c <"$f"
  else
    wc -c <"$f"
  fi
}

json_get_model_field_py() {
  local model_id="$1"
  local field="$2"
  python3 - "$REGISTRY_PATH" "$model_id" "$field" <<'PY'
import json, sys
path, model_id, field = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
for m in data.get("models", []):
    if m.get("id") == model_id:
        v = m.get(field, "")
        if v is None:
            v = ""
        print(v)
        sys.exit(0)
print("")
sys.exit(0)
PY
}

if command -v jq >/dev/null 2>&1; then
  HF_URL="$(jq -r --arg id "$MODEL_ID" '.models[] | select(.id==$id) | .huggingfaceUrl' "$REGISTRY_PATH")"
  FILENAME="$(jq -r --arg id "$MODEL_ID" '.models[] | select(.id==$id) | .expectedFilename' "$REGISTRY_PATH")"
  SIZE_MB="$(jq -r --arg id "$MODEL_ID" '.models[] | select(.id==$id) | .sizeEstimateMb' "$REGISTRY_PATH")"
else
  need_cmd python3
  HF_URL="$(json_get_model_field_py "$MODEL_ID" "huggingfaceUrl")"
  FILENAME="$(json_get_model_field_py "$MODEL_ID" "expectedFilename")"
  SIZE_MB="$(json_get_model_field_py "$MODEL_ID" "sizeEstimateMb")"
fi

[[ -n "$HF_URL" && "$HF_URL" != "null" ]] || { echo "ERROR: model not found in registry: $MODEL_ID"; exit 1; }
[[ -n "$FILENAME" && "$FILENAME" != "null" ]] || { echo "ERROR: expectedFilename missing for: $MODEL_ID"; exit 1; }

DEST_DIR="$HOME/llama.cpp/models"
mkdir -p "$DEST_DIR"
DEST_PATH="$DEST_DIR/$FILENAME"

echo "Model id     : $MODEL_ID"
echo "Registry     : $REGISTRY_PATH"
echo "HF URL       : $HF_URL"
echo "Destination  : $DEST_PATH"
echo "Size (est MB): ${SIZE_MB:-unknown}"

if [[ -f "$DEST_PATH" ]]; then
  existing_bytes="$(bytes_of_file "$DEST_PATH")"
  existing_mb=$(( existing_bytes / 1024 / 1024 ))
  if [[ "$existing_mb" -gt 100 ]]; then
    echo "Already present (size=${existing_mb}MB). Skipping download."
    exit 0
  fi
  echo "File exists but looks too small (${existing_mb}MB). Re-downloading..."
fi

if command -v curl >/dev/null 2>&1; then
  curl -L --fail --retry 3 --retry-delay 2 -o "$DEST_PATH" "$HF_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$DEST_PATH" "$HF_URL"
else
  echo "ERROR: need curl or wget"
  exit 1
fi

[[ -f "$DEST_PATH" ]] || { echo "ERROR: download failed: $DEST_PATH"; exit 1; }
bytes="$(bytes_of_file "$DEST_PATH")"
mb=$(( bytes / 1024 / 1024 ))
if [[ "$mb" -le 100 ]]; then
  echo "ERROR: downloaded file is too small (${mb}MB). Check URL / HuggingFace access."
  exit 1
fi

echo "Download OK: ${mb}MB"

