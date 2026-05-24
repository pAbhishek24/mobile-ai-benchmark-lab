# AI Lab Dashboard (GitHub Pages)

This dashboard is generated from benchmark artifacts under `ai-lab/results/`.

## How It Works

1. `ai-lab/analytics/aggregate_results.py` scans `ai-lab/results/**` and writes:
   - `dashboards/data/runs.json`
2. `ai-lab/analytics/generate_dashboard.py` generates:
   - `dashboards/index.html` (offline-friendly; embeds aggregated JSON in the HTML)
   - `dashboards/assets/chart.min.js` (vendored Chart.js)

## Run Locally (Offline)

```bash
python3 ai-lab/analytics/aggregate_results.py
python3 ai-lab/analytics/generate_dashboard.py
open dashboards/index.html
```

## Enable GitHub Pages (Repo Settings)

1. Go to GitHub repo → `Settings` → `Pages`
2. Under **Build and deployment**, set:
   - Source: **GitHub Actions**
3. Push benchmark results under `ai-lab/results/` and the workflow will publish `dashboards/`.

## Expected URL

If the repository is `https://github.com/<owner>/<repo>`, the Pages site is typically:

`https://<owner>.github.io/<repo>/`

## Screenshots

Add screenshots here after first publish:
- `dashboards/screenshots/latest-runs.png`
- `dashboards/screenshots/thermal-analysis.png`

