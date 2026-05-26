# Mobile AI Benchmark Lab

**Real benchmarks. Real devices. Real thermal constraints.**

An open-source framework for benchmarking local large language models on Android devices — measuring latency, token throughput, thermal behaviour, and real-world accuracy across quantised model variants.

---

## CI

| Workflow | Runs on | Purpose |
|---|---|---|
| **AI Lab CI** | every push / PR | Validates JSON, benchmark schema, regenerates dashboard, uploads artifact |
| **Dashboard & GitHub Pages** | push to `main` | Generates `dashboard-data.json`, deploys `dashboards/` to GitHub Pages |

Download the latest dashboard: **Actions → Dashboard & GitHub Pages → Artifacts → dashboard**

---

## What this is

Most LLM benchmarks run on high-end GPUs or cloud VMs. This project benchmarks small, quantised models (0.5B–7B parameters) running **entirely on-device** via [llama.cpp](https://github.com/ggerganov/llama.cpp) in [Termux](https://termux.dev) — no network, no server, no cloud.

The goal: find which models actually work on a real Android phone in your pocket, with real battery and thermal constraints.

---

## Current results — Samsung Galaxy S24 Ultra

| Model | Quant | Tokens/s | TTFT (s) | Score | Thermal |
|---|---|---|---|---|---|
| Qwen2.5-1.5B | Q4_K_M | 38.2 | 1.8 | 78/100 | Warm |
| Gemma-2B | Q4_K_M | 29.4 | 2.1 | 71/100 | Warm |
| Llama3.2-3B | Q4_K_M | 22.1 | 2.9 | 69/100 | Hot |
| Phi3-Mini | Q4_K_M | 18.7 | 3.4 | 65/100 | Hot |
| TinyLlama-1.1B | Q4_K_M | 44.1 | 1.4 | 52/100 | Cool |
| Llama3.2-1B | Q4_K_M | 41.3 | 1.6 | 54/100 | Cool |
| Qwen2.5-0.5B | Q4_K_M | 51.8 | 1.1 | 48/100 | Cool |

Full reports: [`ai-lab/reports/`](ai-lab/reports/)
Interactive dashboard: [`dashboards/`](dashboards/)

---

## Dashboard

The interactive benchmark dashboard runs as a static HTML site (no server needed).

**Regenerate dashboard data locally** (stdlib only, no pip required):

```bash
python3 ai-lab/analytics/generate_dashboard_data.py
open dashboards/index.html          # macOS
xdg-open dashboards/index.html      # Linux
```

**Serve locally** (needed for the multi-page fetch calls):

```bash
python3 -m http.server 8080 --directory dashboards
# Open http://localhost:8080
```

Pages:
- `index.html` — overview & leaderboard
- `models.html` — side-by-side model comparison
- `devices.html` — per-device breakdown
- `prompts.html` — per-prompt latency analysis
- `thermals.html` — thermal throttling heatmaps
- `historical.html` — benchmark history over time
- `quality.html` — finance quality leaderboard (correctness, hallucination, JSON)
- `quality-overview.html` — quality vs latency, consistency, production readiness
- `hallucinations.html` — hallucination and safety analysis
- `prompt-analysis.html` — per-prompt drilldown by difficulty/category
- `recommendations.html` — automated model recommendation engine

---

## Repository structure

```
ai-lab/
  scripts/          # Termux benchmark runner scripts
  prompts/          # Finance-domain benchmark prompt set
  models/           # Model registry (name, quant, size, source)
  results/          # Raw benchmark results (JSONL + CSV + snapshots)
    samsung-s24-ultra/
      qwen2.5-1.5b-q4km/
        20260524_132317/
          benchmark.jsonl
          summary.csv
          summary.md
          snapshot_before.json   # device state before run
          snapshot_after.json    # device state after run
  reports/          # Human-readable analysis and comparisons
  analytics/        # Python scripts to aggregate and score results
  quality/          # Finance quality benchmarking framework
    quality_benchmark_dataset.json  # 20 prompts with ground truth + rubric
    evaluate_quality.py             # Per-run quality scorer
    aggregate_quality.py            # Cross-run aggregator → quality-data.json
    manual_review.md                # Representative output analysis

dashboards/
  index.html              # Leaderboard overview
  models.html             # Model comparison
  quality.html            # Finance quality leaderboard
  quality-overview.html   # Quality vs latency, production readiness
  hallucinations.html     # Hallucination & safety analysis
  prompt-analysis.html    # Per-prompt drilldown
  recommendations.html    # Model recommendation engine
  data/                   # Pre-generated JSON for charts (Chart.js)
  assets/                 # chart.min.js, dash.js, style.css

docs/
  TERMUX_AI_LAB_SETUP.md          # Step-by-step Termux setup guide
  AI_BENCHMARK_PROTOCOL.md        # Methodology and scoring criteria
  PHASE_3_AI_LAB.md               # Research goals and constraints
  LOW_END_DEVICE_STRATEGY.md      # Strategy for 4GB RAM devices
  FUTURE_LOCAL_AI_ARCHITECTURE.md # Roadmap for on-device AI
  DASHBOARD_DEPLOYMENT.md         # Deploying the dashboard
  AI_STRATEGY.md                  # AI philosophy and principles
```

---

## Running a benchmark yourself

### Prerequisites

- Android device with Termux installed
- llama.cpp compiled in Termux (see [`docs/TERMUX_AI_LAB_SETUP.md`](docs/TERMUX_AI_LAB_SETUP.md))
- A GGUF model file

### Quick start

```bash
# On your Android device in Termux
git clone https://github.com/pAbhishek24/mobile-ai-benchmark-lab
cd mobile-ai-benchmark-lab

# Systems benchmark (fast — measures throughput, 128 max tokens)
./ai-lab/scripts/run_model_evaluation.sh \
  --model qwen2.5-0.5b-q4km \
  --device-label samsung-s24-ultra \
  --profile systems

# Quality benchmark (thorough — measures finance accuracy, 512 max tokens)
./ai-lab/scripts/run_model_evaluation.sh \
  --model qwen2.5-0.5b-q4km \
  --device-label samsung-s24-ultra \
  --profile quality \
  --debug

# Smoke test (2 prompts, 48 tokens — runs in ~2 minutes)
./ai-lab/scripts/run_model_evaluation.sh \
  --model qwen2.5-0.5b-q4km \
  --device-label samsung-s24-ultra \
  --smoke

# Results saved to ai-lab/results/<device>/<model>/<timestamp>/
```

### Benchmark profiles

| Profile | Max tokens | Cooldown | Prompt timeout | Purpose |
|---|---|---|---|---|
| `systems` | 128 | 15s | 90s | Throughput, latency, thermal — fast runs |
| `quality` | 512 | 30s | 180s | Finance accuracy — complete response analysis |
| (default) | 256 | 30s | 90s | Balanced — backwards compatible |

### Official quality rerun commands (focus models)

Run these on your Android device to get production-quality accuracy scores:

```bash
for MODEL in qwen2.5-0.5b-q4km qwen2.5-1.5b-q4km tinyllama-1.1b-q4km; do
  ./ai-lab/scripts/run_model_evaluation.sh \
    --model $MODEL \
    --device-label samsung-s24-ultra \
    --profile quality \
    --debug
done
```

After running, regenerate the dashboard:

```bash
python3 ai-lab/analytics/generate_dashboard_data.py
```

---

## Benchmark methodology

Each run measures:

| Metric | Description |
|---|---|
| **TTFT** | Time to first token (seconds) |
| **Tokens/s** | Sustained throughput after first token |
| **Total time** | Full response completion time |
| **Thermal state** | Device temp before/after (°C) |
| **RAM delta** | Memory consumed by the model process |
| **Battery delta** | % battery consumed during run |
| **Accuracy score** | Rubric-scored correctness (0–100) |

Scoring weights: accuracy 40%, speed 30%, thermal 20%, memory 10%.

See [`docs/AI_BENCHMARK_PROTOCOL.md`](docs/AI_BENCHMARK_PROTOCOL.md) for full methodology.

---

## Prompt set

The benchmark uses a finance-domain prompt set covering:
- Expense categorisation
- Budget reasoning
- Debt/EMI calculations
- Savings rate analysis
- Anomaly detection
- Natural language queries over financial data

Prompts: [`ai-lab/prompts/finance-benchmark-prompts.json`](ai-lab/prompts/finance-benchmark-prompts.json)

---

## Benchmark Methodology

### Methodology Versions

| Version | Description |
|---|---|
| v1 | Legacy runs. No explicit mode tag. Real-world conditions assumed. |
| v2 | Current standard. Explicit `benchmark_mode`, environment metadata, and `post_reboot`/`airplane_mode` flags. |

### Benchmark Modes

**real_world** (default): Background apps active, no reboot, screen on. Represents realistic consumer device performance.

**controlled**: Airplane mode, fresh reboot, minimal background activity. For isolated model performance comparison.

### Run Flags (v2)

| Flag | Default | Description |
|---|---|---|
| `--benchmark-mode` | `real_world` | `real_world` or `controlled` |
| `--post-reboot` | `false` | Device was freshly rebooted before this run |
| `--airplane-mode` | `false` | Airplane mode enabled during run |
| `--background-apps` | `true` | Background apps running |
| `--notes` | `""` | Free-text notes for this run |

### Official Rerun Procedure

To generate a valid v2 dataset for a model:

1. **real_world run**: Use device in normal state, run with `--benchmark-mode real_world`
2. **controlled run**: Reboot → airplane mode → 5min cooldown → run with `--benchmark-mode controlled --post-reboot true --airplane-mode true --background-apps false`
3. Push results and regenerate dashboard data: `python3 ai-lab/analytics/generate_dashboard_data.py`

See [`ai-lab/reports/methodology-v2-notes.md`](ai-lab/reports/methodology-v2-notes.md) for the full methodology specification.

---

## Contributing

New device results, model variants, and prompt additions welcome.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for guidelines.

---

## License

Apache 2.0 — see [`LICENSE`](LICENSE)
