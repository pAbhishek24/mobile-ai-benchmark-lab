# Termux AI Lab Setup Guide

Last updated: May 2026

This guide sets up a local AI benchmarking environment on an Android device using Termux and llama.cpp. The goal is to evaluate quantized GGUF models without touching the production app.

---

## Prerequisites

- Android device with at least 6GB RAM (8GB+ recommended for initial benchmarks)
- At least 8GB free storage
- USB cable or Wi-Fi for file transfer
- Device charged to >80% before running benchmarks (battery drain test requires stable starting %)

---

## Part 1 — Termux Installation

**Do NOT install Termux from Google Play.** The Play Store version is outdated and no longer receives updates.

### Steps
1. Go to **[F-Droid](https://f-droid.org)** on your device
2. Search for **Termux** and install it from F-Droid
3. Open Termux

### First-time Termux setup
```bash
# Update package index
pkg update -y && pkg upgrade -y

# Install essential tools
pkg install -y wget curl git python clang cmake make

# Confirm compiler works
clang --version
```

---

## Part 2 — llama.cpp Setup

### Option A — Build from source (recommended for accurate benchmarks)
Building from source ensures the binary is optimized for your specific device's CPU.

```bash
# Install build dependencies
pkg install -y git clang cmake make

# Clone llama.cpp
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp

# Build (this takes 5-15 minutes depending on device)
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Verify binary exists
ls -la bin/llama-cli
ls -la bin/llama-server
```

### Option B — Pre-built binary (faster setup, less optimal)
```bash
# Check llama.cpp releases for Android arm64 binaries
# https://github.com/ggerganov/llama.cpp/releases
# Download the latest llama-*-android.zip, extract, chmod +x
```

### Verify llama.cpp works
```bash
# Run with no model to confirm binary executes
./build/bin/llama-cli --version
```

---

## Part 3 — GGUF Model Structure

GGUF is the file format used by llama.cpp. All models in this lab use Q4_K_M quantization.

### What Q4_K_M means
- **Q4**: 4-bit quantization (each weight stored as 4 bits instead of 16 or 32)
- **K_M**: k-quant medium — balances quality and size better than plain Q4
- Result: ~4x smaller than the original float16 model, ~10-15% quality loss vs full precision

### Downloading models
Models are available from Hugging Face. Use the `bartowski` or `TheBloke` namespaces for reliable Q4_K_M GGUF files.

```bash
# Example: Qwen2.5 1.5B Q4_K_M
wget https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf

# Example: TinyLlama 1.1B Q4_K_M
wget https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf

# Example: Llama 3.2 1B Q4_K_M
wget https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf

# Example: Qwen2.5 0.5B Q4_K_M
wget https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf
```

### Recommended directory structure
```
~/llama.cpp/
├── build/
│   └── bin/
│       ├── llama-cli
│       └── llama-server
└── models/
    ├── qwen2.5-1.5b-q4_k_m.gguf
    ├── qwen2.5-0.5b-q4_k_m.gguf
    ├── tinyllama-1.1b-q4_k_m.gguf
    ├── llama-3.2-1b-q4_k_m.gguf
    └── gemma-2b-q4_k_m.gguf
```

---

## Part 4 — Storage Recommendations

### Where to store models
```bash
# Option A: Internal Termux home (private, faster)
~/llama.cpp/models/

# Option B: External SD card (if device supports it, may be slower)
/sdcard/llama_models/
```

Models in internal Termux storage are not accessible to other apps, which is the correct behavior — model files are private to the AI lab session.

### Storage budget
| Model | Size | Storage left after (8GB budget) |
|---|---|---|
| Qwen2.5 0.5B | ~400MB | 7.6GB |
| TinyLlama 1.1B | ~670MB | 6.9GB |
| Llama 3.2 1B | ~730MB | 6.2GB |
| Qwen2.5 1.5B | ~986MB | 5.2GB |
| Gemma 2B | ~1.5GB | 3.7GB |
| llama.cpp build | ~200MB | 3.5GB |

Do not store all models simultaneously. Download one, benchmark, record results, then delete before downloading the next. See model cleanup strategy below.

---

## Part 5 — Android Permission Considerations

Termux requires specific permissions to function correctly for this lab.

### Required permissions
- **Storage access** (for /sdcard paths): `termux-setup-storage` — run once after install
- **Wake lock** (prevent CPU throttle during benchmark): Termux can acquire via Android notification

### Battery optimization — critical for benchmarks
Samsung and most OEMs aggressively kill background processes. Termux must be excluded from battery optimization for benchmarks to run without interruption.

See Samsung-specific guidance in Part 6 below.

### No network permission needed
All model inference runs offline. No Termux network calls are made during benchmarking. Models are downloaded once via `wget` before the benchmark session begins. After that, disable Wi-Fi during thermal tests to eliminate interference.

---

## Part 6 — Samsung-Specific Battery Guidance

Samsung's battery optimization (including Knox and Game Booster interference) can terminate Termux mid-benchmark, corrupt timing measurements, and cause artificially poor tok/s results.

### Steps to configure Samsung S24 Ultra for benchmarking

**Step 1 — Exclude Termux from battery optimization**
```
Settings → Battery → Background usage limits → Never sleeping apps → Add → Termux
```

**Step 2 — Disable adaptive battery for benchmark sessions**
```
Settings → Battery → More battery settings → Adaptive battery → Off (during benchmark)
```

**Step 3 — Set performance mode**
```
Settings → Battery → Power mode → High performance
```
Only use High Performance mode during benchmarks. Do NOT use this for production app testing — it inflates performance numbers.

**Step 4 — Disable Game Booster interference**
If Game Booster activates during high CPU usage:
```
Game Booster → Settings → Auto run → Off
```

**Step 5 — Keep screen on during benchmarks**
```
Settings → Display → Screen timeout → 10 minutes
```
Or run this in Termux before starting:
```bash
termux-wake-lock
```

### Note on benchmark validity
Always run two sets of benchmarks:
1. **Clean baseline** — device at rest, no other apps open, High Performance mode
2. **Real-world baseline** — PersonalFinanceAssistant running in background, normal battery mode

The second set represents what users will actually experience.

---

## Part 7 — Benchmark Execution Workflow

### Pre-benchmark checklist
```bash
# 1. Check available RAM
cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable"

# 2. Check storage
df -h ~/

# 3. Check CPU temperature
for zone in /sys/class/thermal/thermal_zone*/temp; do echo "$zone: $(cat $zone)"; done

# 4. Check battery
termux-battery-status  # requires termux-api package: pkg install termux-api

# 5. Kill other processes
# Close all apps except Termux on the device manually
```

### Running a benchmark
```bash
# Standard benchmark run — replace MODEL with your model file
MODEL=~/llama.cpp/models/qwen2.5-1.5b-q4_k_m.gguf
PROMPT="I spent ₹8,200 on food, ₹3,500 on transport, ₹12,000 on rent, and ₹2,800 on utilities this month. What percentage of my ₹40,000 salary went to each category? Which category should I try to reduce?"

# Run with timing output
~/llama.cpp/build/bin/llama-cli \
  -m "$MODEL" \
  -p "$PROMPT" \
  -n 200 \
  --temp 0.1 \
  --threads $(nproc) \
  2>&1 | tee ~/benchmark_results/$(date +%Y%m%d_%H%M%S)_output.txt
```

### Key flags
| Flag | Purpose |
|---|---|
| `-n 200` | Generate up to 200 tokens |
| `--temp 0.1` | Low temperature for consistent, deterministic output |
| `--threads $(nproc)` | Use all available CPU threads |
| `-c 2048` | Context window (use 2048 for these prompts) |
| `--no-mmap` | Disable memory-mapped files (more accurate RAM measurement) |

### Capturing tok/s
llama.cpp prints timing at the end of each run:
```
llama_print_timings: eval time = 12345.67 ms / 156 tokens (  79.14 ms per token,  12.64 tokens per second)
```
Record the "tokens per second" value.

---

## Part 8 — Logging Strategy

### Directory structure for results
```bash
mkdir -p ~/benchmark_results/
# One subdirectory per model
mkdir -p ~/benchmark_results/qwen2.5-1.5b/
mkdir -p ~/benchmark_results/tinyllama-1.1b/
mkdir -p ~/benchmark_results/llama-3.2-1b/
```

### Log file naming convention
```
{YYYYMMDD}_{model}_{run_number}_{metric}.txt

Examples:
20260525_qwen2.5-1.5b_run01_generation.txt
20260525_qwen2.5-1.5b_run01_temperature.txt
20260525_qwen2.5-1.5b_run01_ram.txt
```

### What to log per run
```bash
# Before run: system state
echo "=== PRE-RUN $(date) ===" >> ~/benchmark_results/session_log.txt
cat /proc/meminfo | grep MemAvailable >> ~/benchmark_results/session_log.txt
cat /sys/class/thermal/thermal_zone0/temp >> ~/benchmark_results/session_log.txt

# Run the model (output already tee'd to file)

# After run: system state
echo "=== POST-RUN $(date) ===" >> ~/benchmark_results/session_log.txt
cat /proc/meminfo | grep MemAvailable >> ~/benchmark_results/session_log.txt
cat /sys/class/thermal/thermal_zone0/temp >> ~/benchmark_results/session_log.txt
```

### Transfer logs to desktop
```bash
# Start Termux SSH server (pkg install openssh)
sshd
# From desktop: scp -P 8022 user@device_ip:~/benchmark_results/ ./

# Or use termux-share for individual files
termux-share ~/benchmark_results/session_log.txt
```

---

## Part 9 — Model Cleanup Strategy

Storage is limited. Follow this workflow to keep the device usable.

### After benchmarking a model
```bash
# 1. Verify results are saved and transferred to desktop/cloud
ls -la ~/benchmark_results/

# 2. Delete the model file
rm ~/llama.cpp/models/qwen2.5-1.5b-q4_k_m.gguf

# 3. Confirm storage freed
df -h ~/

# 4. Only then download the next model
```

### Never delete
- `~/benchmark_results/` — all recorded results
- `~/llama.cpp/build/` — compiled binaries (takes 15+ minutes to rebuild)

### Rebuild llama.cpp when needed
```bash
cd ~/llama.cpp
git pull
cd build && cmake .. && make -j$(nproc)
```

---

## Part 10 — Thermal Testing Guidance

Thermal testing determines whether a model causes sustained device overheating that would degrade user experience.

### Setup
```bash
# Install thermal monitoring (run in a separate Termux session)
watch -n 2 'cat /sys/class/thermal/thermal_zone*/temp | paste - - | awk "{print NR\": \"$1/1000\"°C\"}"'
```

### Thermal test protocol
```bash
# Run 10 consecutive queries back-to-back
# Use this script:
MODEL=~/llama.cpp/models/qwen2.5-1.5b-q4_k_m.gguf
PROMPT="I spent ₹8,200 on food, ₹3,500 on transport, ₹12,000 on rent. Total budget ₹40,000. Analyse my spending."

for i in {1..10}; do
  echo "=== Query $i at $(date) ===" 
  cat /sys/class/thermal/thermal_zone0/temp
  ~/llama.cpp/build/bin/llama-cli -m "$MODEL" -p "$PROMPT" -n 150 --temp 0.1 --threads $(nproc) 2>&1 | grep "tokens per second"
done
```

### Throttle detection
If `tokens per second` drops by >30% from run 1 to run 5+, the device is thermally throttling. Record the query number at which throttle began.

### Pass criteria
- No throttle detected in first 5 queries: **PASS**
- Throttle begins at query 6+: **MARGINAL** (note in results, flag for user-facing rate limiting)
- Throttle begins at query 1–5: **FAIL**

### Post-test cooldown
After thermal testing, wait at least 5 minutes before the next model test. Record temperature return to baseline.
