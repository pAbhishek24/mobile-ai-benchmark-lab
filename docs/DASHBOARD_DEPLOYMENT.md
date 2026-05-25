# Dashboard Deployment Guide

## Overview

The AI Lab benchmark dashboard is a fully static site — no server, no build step, no backend.
It consists of plain HTML, vanilla JS, Chart.js, and a JSON data file.

**Publish directory:** `dashboards/`  
**Entry point:** `dashboards/index.html`  
**Data file:** `dashboards/data/dashboard-data.json`

---

## Local Preview

Open the dashboard directly in a browser:

```bash
# Option 1 — Python 3 (recommended, needed for fetch() to work with data/*)
cd dashboards/
python3 -m http.server 8080
# Open http://localhost:8080

# Option 2 — Node (if installed)
cd dashboards/
npx serve .
# Open http://localhost:3000

# Option 3 — Direct file open (limited — fetch() blocked by browser CORS on file://)
open dashboards/index.html
```

> **Note:** Options 1 or 2 are required for the charts to load because the dashboard
> fetches `data/dashboard-data.json` via `fetch()`. Opening via `file://` will block
> the JSON load in most browsers due to CORS restrictions.

---

## Regenerate Dashboard Data

Before deploying, regenerate the canonical data file from the latest benchmark results:

```bash
# From repo root
python3 ai-lab/analytics/generate_dashboard_data.py
```

This reads all runs under `ai-lab/results/`, computes weighted scores, and writes:
- `dashboards/data/dashboard-data.json` — canonical aggregated dataset

Optionally run individual pipeline steps:

```bash
# Step 1: Aggregate runs only
python3 ai-lab/analytics/aggregate_results.py

# Step 2: Compute scores only
python3 ai-lab/analytics/compute_scores.py

# Step 3: Full pipeline (aggregates + scores + writes dashboard-data.json)
python3 ai-lab/analytics/generate_dashboard_data.py
```

---

## Netlify Deployment

### First-time setup

1. Push the `phase-3-ai-lab` branch (or merge to `main`)
2. Log in to Netlify (netlify.com)
3. Click **"Add new site" → "Import an existing project"**
4. Connect your GitHub repository
5. Configure:
   - **Branch to deploy:** `main` (or `phase-3-ai-lab` for preview)
   - **Publish directory:** `dashboards`
   - **Build command:** *(leave empty — no build needed)*
6. Click **Deploy**

### netlify.toml (already committed)

The `netlify.toml` at repo root configures:
- Publish directory: `dashboards/`
- Cache headers for HTML (5 min), JSON (5 min), JS/CSS (1 day)
- Security headers: `X-Frame-Options`, `X-Content-Type-Options`
- Redirect: `/` → `/index.html`

### Updating the dashboard

After running new benchmarks:

```bash
# 1. Run new benchmark on device (Termux)
# 2. Copy results to ai-lab/results/<device>/<model>/<timestamp>/
# 3. Regenerate data
python3 ai-lab/analytics/generate_dashboard_data.py

# 4. Commit and push
git add dashboards/data/dashboard-data.json
git commit -m "update: regenerate dashboard data with new benchmark run"
git push
```

Netlify auto-deploys on push to the configured branch.

---

## Dashboard Pages

| Page | URL | Purpose |
|---|---|---|
| Overview | `/index.html` | KPIs, composite scores, radar chart, summary table |
| Models | `/models.html` | Per-model latency, size, RAM, output length deep dive |
| Thermals | `/thermals.html` | Temperature before/after, thermal rise, zone details |
| Prompts | `/prompts.html` | Per-prompt duration, tok/s, output words (P01–P20) |
| Devices | `/devices.html` | Device hardware profiles, future device roadmap |
| Historical | `/historical.html` | Run-over-run trend tracking, regression detection |

---

## Data Architecture

```
dashboards/
├── index.html           ← Overview page
├── models.html          ← Model deep dive
├── thermals.html        ← Thermal analysis
├── prompts.html         ← Prompt-level latency
├── devices.html         ← Device profiles
├── historical.html      ← Historical trends
├── assets/
│   ├── chart.min.js     ← Vendored Chart.js (offline-ready)
│   ├── style.css        ← Dark theme, mobile-responsive
│   └── dash.js          ← All page logic (vanilla JS)
└── data/
    ├── dashboard-data.json  ← Canonical aggregated dataset (auto-generated)
    └── scores.json          ← Weighted scores by device (auto-generated)
```

### dashboard-data.json structure

```json
{
  "generated_at": "2026-05-25T...",
  "generated_by": "generate_dashboard_data.py",
  "benchmark_context": {
    "background_apps_estimate": true,
    "charging": false,
    "screen_on": true,
    "power_mode": "optimized",
    "benchmark_mode": "real_world"
  },
  "runs": [...],           // all individual runs
  "model_summaries": [...], // one per (device, model) — best/latest run merged
  "scores_by_device": {...} // weighted scores keyed by device
}
```

---

## Future Low-End Device Strategy

When expanding benchmarks to low-end devices (Redmi Note, Realme, budget Samsungs):

1. Run benchmark on new device using same Termux + llama.cpp setup
2. Results land in `ai-lab/results/<device-slug>/<model>/<timestamp>/`
3. Run `generate_dashboard_data.py` — it auto-discovers all devices
4. The dashboard device filter will automatically include the new device
5. Historical page will show cross-device comparisons

Recommended model candidates for low-end devices:
- **Primary:** `qwen2.5-0.5b-q4km` (468 MB, 47 tok/s on S24 Ultra)
- **Fallback:** `tinyllama-1.1b-q4km` (637 MB — pending quality validation)

---

## Offline Compatibility

The dashboard works offline after initial load because:
- `chart.min.js` is vendored (no CDN dependency)
- `style.css` and `dash.js` are local
- `dashboard-data.json` is a local file served from the same origin

The only requirement is running a local HTTP server (Python `http.server` works).
