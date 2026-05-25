#!/usr/bin/env python3
"""
Generate a fully static dashboard (dashboards/index.html) from dashboards/data/runs.json.

Offline-friendly:
- Embed the aggregated data directly into the HTML (no fetch()) so opening the file via file:// works.
- Use a vendored Chart.js bundle from dashboards/assets/chart.min.js.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict


REPO_ROOT = Path(__file__).resolve().parents[2]
DASHBOARD_DIR = REPO_ROOT / "dashboards"
ASSETS_DIR = DASHBOARD_DIR / "assets"
DATA_DIR = DASHBOARD_DIR / "data"


def main() -> None:
    runs_path = DATA_DIR / "runs.json"
    if not runs_path.exists():
        raise SystemExit(f"missing {runs_path}. Run aggregate_results.py first.")

    payload = json.loads(runs_path.read_text(encoding="utf-8"))
    data_js = json.dumps(payload, ensure_ascii=False)

    DASHBOARD_DIR.mkdir(parents=True, exist_ok=True)
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    index_path = DASHBOARD_DIR / "index.html"
    index_path.write_text(_render_index_html(data_js), encoding="utf-8")
    print(f"Wrote {index_path}")


def _render_index_html(data_js: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>AI Lab Benchmarks</title>
  <style>
    :root {{
      --bg: #0b0d12;
      --panel: #121626;
      --text: #e8ecf1;
      --muted: #a9b2c3;
      --line: #232a3d;
      --good: #2ecc71;
      --warn: #f1c40f;
      --bad: #e74c3c;
      --chip: #1b2236;
      --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
    }}
    body {{
      margin: 0; background: radial-gradient(1200px 600px at 20% 10%, #171c31 0%, var(--bg) 55%);
      color: var(--text); font-family: var(--sans);
    }}
    header {{
      padding: 18px 18px 6px 18px;
    }}
    h1 {{ margin: 0; font-size: 20px; letter-spacing: 0.2px; }}
    .sub {{ color: var(--muted); font-size: 13px; margin-top: 6px; }}
    .wrap {{ padding: 14px 18px 30px 18px; display: grid; gap: 14px; grid-template-columns: 1fr; max-width: 1100px; margin: 0 auto; }}
    .row {{ display: grid; gap: 14px; grid-template-columns: 1fr; }}
    @media (min-width: 900px) {{
      .row {{ grid-template-columns: 1.2fr 0.8fr; }}
    }}
    .card {{
      background: linear-gradient(180deg, rgba(255,255,255,0.04), rgba(255,255,255,0.02));
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 14px;
      box-shadow: 0 10px 25px rgba(0,0,0,0.25);
      overflow: hidden;
    }}
    .card h2 {{ margin: 0 0 10px 0; font-size: 14px; color: var(--muted); font-weight: 600; }}
    .filters {{ display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }}
    select {{
      background: var(--chip); color: var(--text); border: 1px solid var(--line);
      border-radius: 10px; padding: 8px 10px; font-size: 13px;
    }}
    .kpi {{ display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }}
    @media (min-width: 900px) {{ .kpi {{ grid-template-columns: repeat(4, 1fr); }} }}
    .kpi .box {{ background: rgba(0,0,0,0.18); border: 1px solid var(--line); border-radius: 12px; padding: 10px; }}
    .kpi .label {{ color: var(--muted); font-size: 12px; }}
    .kpi .value {{ font-family: var(--mono); font-size: 16px; margin-top: 6px; }}
    table {{ width: 100%; border-collapse: collapse; }}
    th, td {{ padding: 10px 8px; border-bottom: 1px solid var(--line); font-size: 13px; text-align: left; }}
    th {{ color: var(--muted); font-weight: 600; cursor: pointer; user-select: none; }}
    tr:hover td {{ background: rgba(255,255,255,0.03); }}
    .chip {{ display:inline-block; padding: 3px 8px; border-radius: 999px; background: var(--chip); border: 1px solid var(--line); font-size: 12px; color: var(--muted); }}
    .heat-green {{ color: var(--good); }}
    .heat-yellow {{ color: var(--warn); }}
    .heat-red {{ color: var(--bad); }}
    .muted {{ color: var(--muted); }}
    .mono {{ font-family: var(--mono); }}
    .grid2 {{ display: grid; grid-template-columns: 1fr; gap: 14px; }}
    @media (min-width: 900px) {{ .grid2 {{ grid-template-columns: 1fr 1fr; }} }}
    canvas {{ max-height: 280px; }}
  </style>
</head>
<body>
  <header>
    <h1>AI Lab Benchmarks</h1>
    <div class="sub">Static dashboard generated from <span class="mono">ai-lab/results/</span>. Thermal warning: yellow &gt;55°C, red &gt;60°C. Quality score placeholder: <span class="mono">null</span>.</div>
  </header>

  <div class="wrap">
    <div class="card">
      <h2>Filters</h2>
      <div class="filters">
        <label class="muted">Device</label>
        <select id="deviceSelect"></select>
        <label class="muted">Model</label>
        <select id="modelSelect"></select>
        <span class="chip" id="runCountChip"></span>
      </div>
    </div>

    <div class="row">
      <div class="card">
        <h2>Latest Runs</h2>
        <div class="kpi" id="kpis"></div>
        <div style="height: 12px;"></div>
        <table id="runsTable">
          <thead>
            <tr>
              <th data-key="timestamp">Timestamp</th>
              <th data-key="device">Device</th>
              <th data-key="model">Model</th>
              <th data-key="success">Success</th>
              <th data-key="timeout">Timeout</th>
              <th data-key="error">Error</th>
              <th data-key="avg_tokens_per_sec">Avg tok/s</th>
              <th data-key="max_temp_after_c">Max °C (after)</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </div>

      <div class="card">
        <h2>Failures / Timeouts</h2>
        <canvas id="failChart"></canvas>
      </div>
    </div>

    <div class="grid2">
      <div class="card">
        <h2>Thermal Analysis (Max After Temp)</h2>
        <canvas id="thermalChart"></canvas>
      </div>
      <div class="card">
        <h2>Model Comparison (Avg tok/s)</h2>
        <canvas id="modelChart"></canvas>
      </div>
    </div>

    <div class="card">
      <h2>Historical Trend (Avg tok/s over time)</h2>
      <canvas id="trendChart"></canvas>
    </div>
  </div>

  <script src="assets/chart.min.js"></script>
  <script>
    window.__PFA_DASH_DATA__ = {data_js};
  </script>
  <script>
    const RAW = window.__PFA_DASH_DATA__ || {{ runs: [] }};
    const runs = (RAW.runs || []).map(r => {{
      const d = r.derived || {{}};
      return {{
        device: r.device,
        model: r.model,
        timestamp: r.timestamp,
        run_dir: r.run_dir,
        success: d.success ?? 0,
        timeout: d.timeout ?? 0,
        error: d.error ?? 0,
        avg_tokens_per_sec: d.avg_tokens_per_sec,
        p50_tokens_per_sec: d.p50_tokens_per_sec,
        max_temp_before_c: d.max_temp_before_c,
        max_temp_after_c: d.max_temp_after_c,
        thermal_after_bucket: d.thermal_after_bucket || "unknown",
        output_present: d.output_present ?? 0,
        prompts: d.prompts ?? null,
      }};
    }});

    const uniq = (xs) => Array.from(new Set(xs)).sort();
    const deviceSelect = document.getElementById("deviceSelect");
    const modelSelect = document.getElementById("modelSelect");
    const runCountChip = document.getElementById("runCountChip");

    function option(el, value) {{
      const o = document.createElement("option");
      o.value = value;
      o.textContent = value;
      el.appendChild(o);
    }}

    function initFilters() {{
      const devices = ["All"].concat(uniq(runs.map(r => r.device)));
      const models = ["All"].concat(uniq(runs.map(r => r.model)));
      devices.forEach(v => option(deviceSelect, v));
      models.forEach(v => option(modelSelect, v));
      deviceSelect.value = "All";
      modelSelect.value = "All";
      deviceSelect.addEventListener("change", render);
      modelSelect.addEventListener("change", render);
    }}

    function filtRuns() {{
      return runs.filter(r => {{
        if (deviceSelect.value !== "All" && r.device !== deviceSelect.value) return false;
        if (modelSelect.value !== "All" && r.model !== modelSelect.value) return false;
        return true;
      }});
    }}

    function fmt(v, digits=2) {{
      if (v === null || v === undefined) return "—";
      if (typeof v === "number") return v.toFixed(digits);
      return String(v);
    }}

    function heatClass(bucket) {{
      if (bucket === "red") return "heat-red";
      if (bucket === "yellow") return "heat-yellow";
      if (bucket === "green") return "heat-green";
      return "muted";
    }}

    function renderKpis(rs) {{
      const k = document.getElementById("kpis");
      k.innerHTML = "";
      const total = rs.length;
      const succ = rs.reduce((a,b)=>a+(b.success||0),0);
      const err  = rs.reduce((a,b)=>a+(b.error||0),0);
      const tout = rs.reduce((a,b)=>a+(b.timeout||0),0);
      const avgTok = (() => {{
        const vals = rs.map(r => r.avg_tokens_per_sec).filter(v => typeof v === "number");
        if (!vals.length) return null;
        return vals.reduce((a,b)=>a+b,0)/vals.length;
      }})();
      const maxTemp = (() => {{
        const vals = rs.map(r => r.max_temp_after_c).filter(v => typeof v === "number");
        if (!vals.length) return null;
        return Math.max(...vals);
      }})();

      const items = [
        ["Runs", total],
        ["Success", succ],
        ["Timeout", tout],
        ["Errors", err],
        ["Avg tok/s", avgTok !== null ? fmt(avgTok,2) : "—"],
        ["Max after °C", maxTemp !== null ? fmt(maxTemp,1) : "—"],
        ["Filters", deviceSelect.value + " / " + modelSelect.value],
        ["Quality score", "null"],
      ];
      items.forEach(([label, value]) => {{
        const box = document.createElement("div");
        box.className = "box";
        box.innerHTML = `<div class="label">${{label}}</div><div class="value">${{value}}</div>`;
        k.appendChild(box);
      }});
    }}

    let tableSortKey = "timestamp";
    let tableSortDir = "desc";

    function renderTable(rs) {{
      const tbody = document.querySelector("#runsTable tbody");
      tbody.innerHTML = "";

      rs.sort((a,b)=> {{
        const av = a[tableSortKey];
        const bv = b[tableSortKey];
        const dir = tableSortDir === "asc" ? 1 : -1;
        if (av === bv) return 0;
        if (av === null || av === undefined) return 1;
        if (bv === null || bv === undefined) return -1;
        if (typeof av === "number" && typeof bv === "number") return (av - bv) * dir;
        return String(av).localeCompare(String(bv)) * dir;
      }});

      // Show latest first by timestamp string.
      rs.slice().reverse();

      rs.slice(-25).reverse().forEach(r => {{
        const tr = document.createElement("tr");
        const temp = r.max_temp_after_c;
        const bucket = r.thermal_after_bucket;
        tr.innerHTML = `
          <td class="mono">${{r.timestamp}}</td>
          <td>${{r.device}}</td>
          <td>${{r.model}}</td>
          <td class="mono">${{r.success}}</td>
          <td class="mono">${{r.timeout}}</td>
          <td class="mono">${{r.error}}</td>
          <td class="mono">${{r.avg_tokens_per_sec !== null && r.avg_tokens_per_sec !== undefined ? fmt(r.avg_tokens_per_sec,2) : "—"}}</td>
          <td class="mono ${{heatClass(bucket)}}">${{temp !== null && temp !== undefined ? fmt(temp,1) : "—"}}</td>
        `;
        tbody.appendChild(tr);
      }});
    }}

    function groupBy(xs, keyFn) {{
      const m = new Map();
      xs.forEach(x => {{
        const k = keyFn(x);
        if (!m.has(k)) m.set(k, []);
        m.get(k).push(x);
      }});
      return m;
    }}

    let failChart, thermalChart, modelChart, trendChart;

    function renderCharts(rs) {{
      // Fail chart
      const totalErr = rs.reduce((a,b)=>a+(b.error||0),0);
      const totalTout = rs.reduce((a,b)=>a+(b.timeout||0),0);
      const totalOk = rs.reduce((a,b)=>a+(b.success||0),0);

      const failCtx = document.getElementById("failChart");
      const failData = {{
        labels: ["Success", "Timeout", "Error"],
        datasets: [{{
          label: "Count",
          data: [totalOk, totalTout, totalErr],
          backgroundColor: ["#2ecc71", "#f1c40f", "#e74c3c"],
          borderColor: "#1b2236",
          borderWidth: 1,
        }}]
      }};
      if (failChart) failChart.destroy();
      failChart = new Chart(failCtx, {{ type: "bar", data: failData, options: {{
        responsive: true,
        plugins: {{ legend: {{ display: false }} }},
        scales: {{ y: {{ beginAtZero: true }} }}
      }}}});

      // Thermal chart: max after temp per run
      const thermalCtx = document.getElementById("thermalChart");
      const sorted = rs.slice().sort((a,b)=> String(a.timestamp).localeCompare(String(b.timestamp)));
      const thermalVals = sorted.map(r => r.max_temp_after_c);
      if (thermalChart) thermalChart.destroy();
      thermalChart = new Chart(thermalCtx, {{
        type: "line",
        data: {{
          labels: sorted.map(r => r.timestamp),
          datasets: [{{
            label: "Max after °C",
            data: thermalVals,
            borderColor: "#8ab4ff",
            backgroundColor: "rgba(138,180,255,0.15)",
            tension: 0.25,
            pointRadius: 2,
          }}]
        }},
        options: {{
          responsive: true,
          plugins: {{ legend: {{ display: true }} }},
          scales: {{
            y: {{
              beginAtZero: false,
              suggestedMin: 35,
              suggestedMax: 70,
            }}
          }}
        }}
      }});

      // Model comparison: avg tok/s per model
      const modelCtx = document.getElementById("modelChart");
      const byModel = groupBy(rs, r => r.model);
      const labels = Array.from(byModel.keys()).sort();
      const vals = labels.map(m => {{
        const v = (byModel.get(m) || []).map(r => r.avg_tokens_per_sec).filter(x => typeof x === "number");
        if (!v.length) return null;
        return v.reduce((a,b)=>a+b,0)/v.length;
      }});
      if (modelChart) modelChart.destroy();
      modelChart = new Chart(modelCtx, {{
        type: "bar",
        data: {{
          labels,
          datasets: [{{
            label: "Avg tok/s",
            data: vals,
            backgroundColor: "rgba(46,204,113,0.35)",
            borderColor: "rgba(46,204,113,0.9)",
            borderWidth: 1,
          }}]
        }},
        options: {{
          responsive: true,
          scales: {{ y: {{ beginAtZero: true }} }}
        }}
      }});

      // Trend chart: avg tok/s by timestamp (all models/devices in filter)
      const trendCtx = document.getElementById("trendChart");
      const trend = sorted.map(r => r.avg_tokens_per_sec);
      if (trendChart) trendChart.destroy();
      trendChart = new Chart(trendCtx, {{
        type: "line",
        data: {{
          labels: sorted.map(r => r.timestamp),
          datasets: [{{
            label: "Avg tok/s",
            data: trend,
            borderColor: "#f39c12",
            backgroundColor: "rgba(243,156,18,0.12)",
            tension: 0.25,
            pointRadius: 2,
          }}]
        }},
        options: {{
          responsive: true,
          scales: {{ y: {{ beginAtZero: true }} }}
        }}
      }});
    }}

    function bindTableSort() {{
      document.querySelectorAll("#runsTable th").forEach(th => {{
        th.addEventListener("click", () => {{
          const key = th.getAttribute("data-key");
          if (!key) return;
          if (tableSortKey === key) {{
            tableSortDir = (tableSortDir === "asc") ? "desc" : "asc";
          }} else {{
            tableSortKey = key;
            tableSortDir = "desc";
          }}
          render();
        }});
      }});
    }}

    function render() {{
      const rs = filtRuns();
      runCountChip.textContent = `${{rs.length}} run(s)`;
      renderKpis(rs);
      renderTable(rs);
      renderCharts(rs);
    }}

    initFilters();
    bindTableSort();
    render();
  </script>
</body>
</html>
"""


if __name__ == "__main__":
    main()
