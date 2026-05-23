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

# ── Build output ──────────────────────────────────────────────────────────────
OUTPUT=$(python3 -c "
import json
snapshot = {
    'timestamp': '$DATE_ISO',
    'label': '$LABEL',
    'device': {
        'model': '$DEVICE_MODEL',
        'brand': '$DEVICE_BRAND',
        'board': '$DEVICE_BOARD',
        'android_version': '$ANDROID_VER',
        'android_sdk': '$ANDROID_SDK',
        'build_fingerprint': '$BUILD_FINGERPRINT'
    },
    'cpu': {
        'hardware': '$CPU_HARDWARE',
        'cores': '$CPU_CORES',
        'max_freq': '$CPU_MAX_FREQ',
        'current_freq': '$CPU_CUR_FREQ',
        'load_avg_1_5_15': '$LOAD_AVG'
    },
    'memory': {
        'total_mb': $MEM_TOTAL_MB,
        'available_mb': $MEM_AVAIL_MB,
        'used_mb': $MEM_USED_MB
    },
    'storage': {
        'home_total': '$STORAGE_HOME_TOTAL',
        'home_used': '$STORAGE_HOME_USED',
        'home_free': '$STORAGE_HOME_FREE'
    },
    'battery': {
        'level_pct': '$BATTERY_LEVEL',
        'status': '$BATTERY_STATUS',
        'temp_c': '$BATTERY_TEMP'
    },
    'thermal': {
        'android_status': '$THERMAL_STATUS',
        'zones': $THERMAL_JSON
    }
}
print(json.dumps(snapshot, indent=2))
")

# ── Output ────────────────────────────────────────────────────────────────────
if [ -n "$OUTPUT_FILE" ]; then
  mkdir -p "$(dirname "$OUTPUT_FILE")"
  echo "$OUTPUT" > "$OUTPUT_FILE"
  echo "Snapshot saved: $OUTPUT_FILE" >&2
else
  echo "$OUTPUT"
fi
