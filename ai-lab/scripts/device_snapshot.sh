#!/usr/bin/env bash
# device_snapshot.sh
# Captures device state before/during/after AI benchmarking.
# Works in Termux on Android. Outputs JSON to stdout and optionally to a file.
#
# Usage:
#   ./device_snapshot.sh                        # print JSON to stdout
#   ./device_snapshot.sh -o snapshot.json       # save to file
#   ./device_snapshot.sh -l before              # label the snapshot (before/during/after)
#
# Example (capture before benchmark):
#   ./device_snapshot.sh -l before -o ../results/snapshot_$(date +%Y%m%d_%H%M%S).json

set -euo pipefail

LABEL="snapshot"
OUTPUT_FILE=""

while getopts "l:o:h" opt; do
  case $opt in
    l) LABEL="$OPTARG" ;;
    o) OUTPUT_FILE="$OPTARG" ;;
    h)
      echo "Usage: $0 [-l <label>] [-o <output_file>]"
      exit 0
      ;;
    *) ;;
  esac
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Device identity ────────────────────────────────────────────────────────────
DEVICE_MODEL=$(getprop ro.product.model 2>/dev/null || echo "unknown")
DEVICE_BRAND=$(getprop ro.product.brand 2>/dev/null || echo "unknown")
DEVICE_BOARD=$(getprop ro.product.board 2>/dev/null || echo "unknown")
ANDROID_VER=$(getprop ro.build.version.release 2>/dev/null || echo "unknown")
ANDROID_SDK=$(getprop ro.build.version.sdk 2>/dev/null || echo "unknown")
BUILD_FINGERPRINT=$(getprop ro.build.fingerprint 2>/dev/null | cut -c1-80 || echo "unknown")

# ── CPU info ──────────────────────────────────────────────────────────────────
CPU_HARDWARE=$(grep -m1 "Hardware" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")
CPU_CORES=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "unknown")
CPU_MAX_FREQ="unknown"
if ls /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq &>/dev/null; then
  FREQ_KHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo "0")
  CPU_MAX_FREQ="${FREQ_KHZ}kHz"
fi
CPU_CUR_FREQ="unknown"
if ls /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq &>/dev/null; then
  FREQ_KHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo "0")
  CPU_CUR_FREQ="${FREQ_KHZ}kHz"
fi

# ── Memory ────────────────────────────────────────────────────────────────────
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
MEM_FREE_KB=$(grep MemFree /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
MEM_AVAIL_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
MEM_CACHED_KB=$(grep "^Cached:" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))
MEM_AVAIL_MB=$((MEM_AVAIL_KB / 1024))
MEM_USED_MB=$(( (MEM_TOTAL_KB - MEM_AVAIL_KB) / 1024 ))

# ── Storage ───────────────────────────────────────────────────────────────────
STORAGE_HOME_FREE=$(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4}' || echo "unknown")
STORAGE_HOME_TOTAL=$(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $2}' || echo "unknown")
STORAGE_HOME_USED=$(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $3}' || echo "unknown")

# ── Battery ───────────────────────────────────────────────────────────────────
BATTERY_LEVEL="unknown"
BATTERY_STATUS="unknown"
BATTERY_TEMP="unknown"
BATTERY_VOLTAGE="unknown"

# Try termux-api first (most reliable)
if command -v termux-battery-status &>/dev/null; then
  BATT_JSON=$(termux-battery-status 2>/dev/null || echo "{}")
  BATTERY_LEVEL=$(echo "$BATT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('percentage','unknown'))" 2>/dev/null || echo "unknown")
  BATTERY_STATUS=$(echo "$BATT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
  BATTERY_TEMP=$(echo "$BATT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('temperature','unknown'))" 2>/dev/null || echo "unknown")
fi

# Fallback: sysfs
if [ "$BATTERY_LEVEL" = "unknown" ]; then
  BATTERY_LEVEL=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "unknown")
fi
if [ "$BATTERY_STATUS" = "unknown" ]; then
  BATTERY_STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "unknown")
fi
if [ "$BATTERY_TEMP" = "unknown" ]; then
  RAW_BATT_TEMP=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo "")
  if [ -n "$RAW_BATT_TEMP" ] && [ "$RAW_BATT_TEMP" != "0" ]; then
    BATTERY_TEMP=$(echo "$RAW_BATT_TEMP" | awk '{printf "%.1f", $1/10}')
  fi
fi

# ── Thermal zones ─────────────────────────────────────────────────────────────
THERMAL_JSON="[]"
if ls /sys/class/thermal/thermal_zone*/temp &>/dev/null 2>&1; then
  THERMAL_JSON=$(python3 -c "
import os, json
zones = []
base = '/sys/class/thermal'
for zone in sorted(os.listdir(base)):
    zpath = os.path.join(base, zone)
    temp_file = os.path.join(zpath, 'temp')
    type_file = os.path.join(zpath, 'type')
    if not os.path.isfile(temp_file):
        continue
    try:
        raw = int(open(temp_file).read().strip())
        zone_type = open(type_file).read().strip() if os.path.isfile(type_file) else zone
        temp_c = raw / 1000.0 if raw > 1000 else raw / 10.0 if raw > 100 else float(raw)
        zones.append({'zone': zone, 'type': zone_type, 'temp_c': round(temp_c, 1)})
    except Exception:
        pass
print(json.dumps(zones[:8]))  # cap at 8 zones
" 2>/dev/null || echo "[]")
fi

# Android thermal status via getprop (API 29+)
THERMAL_STATUS=$(getprop android.thermal.status 2>/dev/null || echo "unknown")

# ── System load ───────────────────────────────────────────────────────────────
LOAD_AVG=$(cat /proc/loadavg 2>/dev/null | awk '{print $1","$2","$3}' || echo "unknown")

# ── Build output (JSON-safe; never interpolate into Python source) ─────────────
SNAPSHOT_RAW_OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw-out) SNAPSHOT_RAW_OUT="${2:-}"; shift 2 ;;
    *) shift 1 ;;
  esac
done

if [ -n "$SNAPSHOT_RAW_OUT" ]; then
  mkdir -p "$(dirname "$SNAPSHOT_RAW_OUT")"
  {
    echo "timestamp=$DATE_ISO"
    echo "label=$LABEL"
    echo "device_model=$DEVICE_MODEL"
    echo "device_brand=$DEVICE_BRAND"
    echo "device_board=$DEVICE_BOARD"
    echo "android_version=$ANDROID_VER"
    echo "android_sdk=$ANDROID_SDK"
    echo "build_fingerprint=$BUILD_FINGERPRINT"
    echo "cpu_hardware=$CPU_HARDWARE"
    echo "cpu_cores=$CPU_CORES"
    echo "cpu_max_freq=$CPU_MAX_FREQ"
    echo "cpu_current_freq=$CPU_CUR_FREQ"
    echo "load_avg=$LOAD_AVG"
    echo "mem_total_mb=$MEM_TOTAL_MB"
    echo "mem_avail_mb=$MEM_AVAIL_MB"
    echo "mem_used_mb=$MEM_USED_MB"
    echo "storage_home_total=$STORAGE_HOME_TOTAL"
    echo "storage_home_used=$STORAGE_HOME_USED"
    echo "storage_home_free=$STORAGE_HOME_FREE"
    echo "battery_level=$BATTERY_LEVEL"
    echo "battery_status=$BATTERY_STATUS"
    echo "battery_temp=$BATTERY_TEMP"
    echo "thermal_status=$THERMAL_STATUS"
    echo "thermal_zones_json=$THERMAL_JSON"
  } > "$SNAPSHOT_RAW_OUT"
fi

export PFA_SNAP_TIMESTAMP="$DATE_ISO"
export PFA_SNAP_LABEL="$LABEL"
export PFA_SNAP_DEVICE_MODEL="$DEVICE_MODEL"
export PFA_SNAP_DEVICE_BRAND="$DEVICE_BRAND"
export PFA_SNAP_DEVICE_BOARD="$DEVICE_BOARD"
export PFA_SNAP_ANDROID_VER="$ANDROID_VER"
export PFA_SNAP_ANDROID_SDK="$ANDROID_SDK"
export PFA_SNAP_BUILD_FINGERPRINT="$BUILD_FINGERPRINT"
export PFA_SNAP_CPU_HARDWARE="$CPU_HARDWARE"
export PFA_SNAP_CPU_CORES="$CPU_CORES"
export PFA_SNAP_CPU_MAX_FREQ="$CPU_MAX_FREQ"
export PFA_SNAP_CPU_CUR_FREQ="$CPU_CUR_FREQ"
export PFA_SNAP_LOAD_AVG="$LOAD_AVG"
export PFA_SNAP_MEM_TOTAL_MB="$MEM_TOTAL_MB"
export PFA_SNAP_MEM_AVAIL_MB="$MEM_AVAIL_MB"
export PFA_SNAP_MEM_USED_MB="$MEM_USED_MB"
export PFA_SNAP_STORAGE_HOME_TOTAL="$STORAGE_HOME_TOTAL"
export PFA_SNAP_STORAGE_HOME_USED="$STORAGE_HOME_USED"
export PFA_SNAP_STORAGE_HOME_FREE="$STORAGE_HOME_FREE"
export PFA_SNAP_BATTERY_LEVEL="$BATTERY_LEVEL"
export PFA_SNAP_BATTERY_STATUS="$BATTERY_STATUS"
export PFA_SNAP_BATTERY_TEMP="$BATTERY_TEMP"
export PFA_SNAP_THERMAL_STATUS="$THERMAL_STATUS"
export PFA_SNAP_THERMAL_ZONES_JSON="$THERMAL_JSON"

OUTPUT="$(python3 - <<'PY'
import json, os

def getenv(key, default="unknown"):
    v = os.environ.get(key)
    if v is None or v == "":
        return default
    return v

def int_or_unknown(v):
    try:
        return int(v)
    except Exception:
        return "unknown"

def int_or_zero(v):
    try:
        return int(v)
    except Exception:
        return 0

zones_raw = getenv("PFA_SNAP_THERMAL_ZONES_JSON", "[]")
try:
    zones = json.loads(zones_raw)
    if not isinstance(zones, list):
        zones = []
except Exception:
    zones = []

snapshot = {
  "timestamp": getenv("PFA_SNAP_TIMESTAMP"),
  "label": getenv("PFA_SNAP_LABEL"),
  "device": {
    "model": getenv("PFA_SNAP_DEVICE_MODEL"),
    "brand": getenv("PFA_SNAP_DEVICE_BRAND"),
    "board": getenv("PFA_SNAP_DEVICE_BOARD"),
    "android_version": getenv("PFA_SNAP_ANDROID_VER"),
    "android_sdk": getenv("PFA_SNAP_ANDROID_SDK"),
    "build_fingerprint": getenv("PFA_SNAP_BUILD_FINGERPRINT")
  },
  "cpu": {
    "hardware": getenv("PFA_SNAP_CPU_HARDWARE"),
    "cores": int_or_unknown(getenv("PFA_SNAP_CPU_CORES")),
    "max_freq": getenv("PFA_SNAP_CPU_MAX_FREQ"),
    "current_freq": getenv("PFA_SNAP_CPU_CUR_FREQ"),
    "load_avg_1_5_15": getenv("PFA_SNAP_LOAD_AVG")
  },
  "memory": {
    "total_mb": int_or_zero(getenv("PFA_SNAP_MEM_TOTAL_MB")),
    "available_mb": int_or_zero(getenv("PFA_SNAP_MEM_AVAIL_MB")),
    "used_mb": int_or_zero(getenv("PFA_SNAP_MEM_USED_MB"))
  },
  "storage": {
    "home_total": getenv("PFA_SNAP_STORAGE_HOME_TOTAL"),
    "home_used": getenv("PFA_SNAP_STORAGE_HOME_USED"),
    "home_free": getenv("PFA_SNAP_STORAGE_HOME_FREE")
  },
  "battery": {
    "level_pct": getenv("PFA_SNAP_BATTERY_LEVEL"),
    "status": getenv("PFA_SNAP_BATTERY_STATUS"),
    "temp_c": getenv("PFA_SNAP_BATTERY_TEMP")
  },
  "thermal": {
    "android_status": getenv("PFA_SNAP_THERMAL_STATUS"),
    "zones": zones
  }
}

print(json.dumps(snapshot, ensure_ascii=False, indent=2))
PY
)"

# Validate JSON (fail fast if snapshot is invalid)
echo "$OUTPUT" | python3 -m json.tool >/dev/null

# ── Output ────────────────────────────────────────────────────────────────────
if [ -n "$OUTPUT_FILE" ]; then
  mkdir -p "$(dirname "$OUTPUT_FILE")"
  echo "$OUTPUT" > "$OUTPUT_FILE"
  echo "Snapshot saved: $OUTPUT_FILE" >&2
else
  echo "$OUTPUT"
fi
