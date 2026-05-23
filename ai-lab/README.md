# AI Lab — PersonalFinanceAssistant

This directory contains the Phase 3 AI benchmarking lab. It is completely isolated from the Android app. No model files, no app code changes, no cloud dependencies.

**Goal:** Evaluate quantized local LLMs on a real Android device (Samsung S24 Ultra + mid-range baseline) before any integration into the app.

---

## Directory Structure

```
ai-lab/
├── prompts/
│   └── finance-benchmark-prompts.json   ← 20 Indian finance prompts
├── scripts/
│   ├── run_llama_benchmark.sh           ← main benchmark runner
│   └── device_snapshot.sh              ← device state capture
├── results/                             ← gitignored output (JSONL, logs)
│   └── .gitkeep
├── models/                              ← gitignored model files
└── MODEL_EVALUATION_TEMPLATE.md        ← fill one per model tested
```

---

## Part 1 — Termux Setup

### Install Termux

**Do NOT use Google Play.** Install from F-Droid only:
1. Open [https://f-droid.org](https://f-droid.org) on your device
2. Search **Termux** → install
3. Open Termux

### Install required packages

```bash
pkg update -y && pkg upgrade -y
pkg install -y git clang cmake make python wget curl
```

Verify:
```bash
clang --version
python3 --version
cmake --version
```

### Grant storage access (required once)

```bash
termux-setup-storage
```

Tap **Allow** when Android prompts. This lets Termux access `/sdcard/`.

---

## Part 2 — Build llama.cpp from Source

Building from source gives CPU-optimized binaries for your specific SoC.

```bash
cd ~
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

This takes 10–20 minutes on S24 Ultra. Grab a coffee.

Verify build:
```bash
~/llama.cpp/build/bin/llama-cli --version
```

---

## Part 3 — Model Folder Convention

Store models here (gitignored):
```
ai-lab/models/<model-name>.gguf
```

Or in Termux home (also fine):
```
~/llama.cpp/models/<model-name>.gguf
```

### Recommended evaluation order

| Priority | Model | Download size | Why |
|---|---|---|---|
| 1 | Qwen2.5-1.5B-Instruct-Q4_K_M | ~986MB | Best quality/size ratio — start here |
| 2 | Llama-3.2-1B-Instruct-Q4_K_M | ~730MB | Meta's small model |
| 3 | TinyLlama-1.1B-Chat-v1.0-Q4_K_M | ~670MB | Smallest viable candidate |
| 4 | Qwen2.5-0.5B-Instruct-Q4_K_M | ~400MB | Low-end device candidate |
| 5 | Gemma-2-2B-IT-Q4_K_M | ~1.5GB | Benchmark only — likely too large |

### Download a model (example — Qwen2.5 1.5B)

```bash
mkdir -p ~/llama.cpp/models
cd ~/llama.cpp/models

wget "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf"
```

---

## Part 4 — Clone the Repo in Termux (optional but recommended)

```bash
cd ~
git clone https://github.com/pAbhishek24/personal-finance-assistant.git
cd personal-finance-assistant
git checkout phase-3-ai-lab
```

This gives you access to the prompt file and scripts directly on the device.

---

## Part 5 — Run the Benchmark

### Make scripts executable

```bash
chmod +x ~/personal-finance-assistant/ai-lab/scripts/run_llama_benchmark.sh
chmod +x ~/personal-finance-assistant/ai-lab/scripts/device_snapshot.sh
```

### Step 1: Capture device snapshot before benchmark

```bash
~/personal-finance-assistant/ai-lab/scripts/device_snapshot.sh \
  -l before \
  -o ~/personal-finance-assistant/ai-lab/results/snapshot_before_$(date +%Y%m%d_%H%M%S).json
```

### Step 2: Run benchmark

```bash
~/personal-finance-assistant/ai-lab/scripts/run_llama_benchmark.sh \
  -m ~/llama.cpp/models/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf \
  -p ~/personal-finance-assistant/ai-lab/prompts/finance-benchmark-prompts.json \
  -n 256
```

### Step 3: Capture device snapshot after benchmark

```bash
~/personal-finance-assistant/ai-lab/scripts/device_snapshot.sh \
  -l after \
  -o ~/personal-finance-assistant/ai-lab/results/snapshot_after_$(date +%Y%m%d_%H%M%S).json
```

---

## Part 6 — Collect Results

After the benchmark completes, results are in `ai-lab/results/`:

```
benchmark_<model>_<timestamp>.jsonl   ← one JSON line per prompt (metrics)
benchmark_<model>_<timestamp>.log     ← full raw llama.cpp output
snapshot_before_<timestamp>.json      ← device state before
snapshot_after_<timestamp>.json       ← device state after
```

### Share results back

Option A — copy file content:
```bash
cat ~/personal-finance-assistant/ai-lab/results/benchmark_*.jsonl
```

Option B — transfer via USB/ADB:
```bash
adb pull /data/data/com.termux/files/home/personal-finance-assistant/ai-lab/results/ ./results/
```

Option C — Termux share:
```bash
termux-share ~/personal-finance-assistant/ai-lab/results/benchmark_Qwen2.5-1.5B-Instruct-Q4_K_M_<timestamp>.jsonl
```

---

## Part 7 — Avoid Committing Model Files

The following are in `.gitignore` and will never be committed:
```
ai-lab/models/
ai-lab/results/*.jsonl
ai-lab/results/*.txt
ai-lab/results/*.csv
*.gguf
```

**Never run `git add ai-lab/models/` or `git add *.gguf`.**

Check what git sees:
```bash
git status ai-lab/
```

Models should never appear in `git status` output.

---

## Samsung S24 Ultra Notes

### Battery optimization (must do before benchmark)

```
Settings → Battery → Background usage limits → Never sleeping apps → Add → Termux
Settings → Battery → Power mode → High performance  (during benchmark only)
```

### Prevent CPU throttle during benchmark

```bash
termux-wake-lock   # keeps CPU from sleeping mid-benchmark
```

Run this before starting the benchmark script. Termux will show a persistent notification while the wake lock is held.

### Thermal monitoring (separate Termux session)

Open a second Termux window and run:
```bash
watch -n 3 'for f in /sys/class/thermal/thermal_zone*/temp; do echo "$f: $(cat $f)"; done'
```

### Expected S24 Ultra performance targets

| Metric | Expected |
|---|---|
| Qwen2.5 1.5B first token | 800–1,200ms |
| Qwen2.5 1.5B tokens/sec | 18–30 tok/s |
| RAM usage (model + Termux) | 1.2–1.8GB |
| Thermal throttle | None in first 5 queries |
| Battery per 20-prompt run | 1–2% |

---

## Low-End Device Notes

If running on a 4–6GB RAM device (Snapdragon 695, Dimensity 1080):

- Use Qwen2.5 0.5B or TinyLlama 1.1B as first candidate
- Reduce max tokens: add `-n 128` to the benchmark command
- Disable battery optimization in the same way as S24 Ultra
- Do NOT use High Performance mode — measure under normal conditions to reflect real-world use
- Expected tokens/sec: 6–12 (vs 18–30 on S24 Ultra)
- If device throttles before prompt 5, note the prompt number and stop — this model fails on this device

---

## What to Paste Back After Running

After running the benchmark, share these with the project:

1. **Full `.jsonl` results file** — contains all 20 prompt results with timing
2. **Device snapshot JSON** (before + after) — shows RAM, battery drain, thermal
3. **Any unusual llama.cpp output** (errors, warnings, crash logs)
4. **Subjective notes** — did any answers look wrong? Any hallucinations noticed?

Paste results back in the Claude Code session for analysis and model selection decision.
