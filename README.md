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

dashboards/
  index.html        # Leaderboard overview
  models.html       # Model comparison page
  data/             # Pre-generated JSON for charts (Chart.js)
  assets/           # chart.min.js, dash.js, style.css

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
cd mobile-ai-benchmark-lab/ai-lab/scripts

# Run a full benchmark
bash run_llama_benchmark.sh \
  --model ~/models/qwen2.5-1.5b-q4_k_m.gguf \
  --device "samsung-s24-ultra" \
  --prompts ../prompts/finance-benchmark-prompts.json

# Results saved to ai-lab/results/<device>/<model>/<timestamp>/
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

## Contributing

New device results, model variants, and prompt additions welcome.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for guidelines.

---

## License

Apache 2.0 — see [`LICENSE`](LICENSE)
