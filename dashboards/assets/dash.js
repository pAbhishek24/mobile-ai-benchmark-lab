/* AI Lab Dashboard — vanilla JS, no framework, no build step */
"use strict";

// ── Colours ──────────────────────────────────────────────
const PALETTE = [
  "#4f8ef7","#2ecc71","#f1c40f","#e74c3c",
  "#9b59b6","#1abc9c","#e67e22","#34495e",
];

// Assign a stable colour to each model name
const _MODEL_COLOR_MAP = {};
function modelColor(name) {
  if (!_MODEL_COLOR_MAP[name]) {
    const idx = Object.keys(_MODEL_COLOR_MAP).length;
    _MODEL_COLOR_MAP[name] = PALETTE[idx % PALETTE.length];
  }
  return _MODEL_COLOR_MAP[name];
}

// Pre-seed colours in scoring order so they're always consistent
["qwen2.5-0.5b-q4km","tinyllama-1.1b-q4km","phi3-mini-q4km","qwen2.5-1.5b-q4km",
 "llama3.2-1b-q4km","llama3.2-3b-q4km","gemma-2b-q4km"].forEach(modelColor);

// ── Chart.js global defaults ──────────────────────────────
Chart.defaults.color = "#8892a4";
Chart.defaults.borderColor = "#1e2640";
Chart.defaults.font.family = "ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif";
Chart.defaults.plugins.tooltip.backgroundColor = "#161b2e";
Chart.defaults.plugins.tooltip.borderColor = "#1e2640";
Chart.defaults.plugins.tooltip.borderWidth = 1;
Chart.defaults.plugins.tooltip.titleColor = "#e2e8f4";
Chart.defaults.plugins.tooltip.bodyColor = "#8892a4";

// ── Data loading ──────────────────────────────────────────
async function loadDashboardData(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error("Failed to load " + url + " (" + r.status + ")");
  return r.json();
}

// ── Formatting helpers ────────────────────────────────────
function fmt(v, dec = 1) {
  if (v === null || v === undefined) return "—";
  if (typeof v === "number") return v.toFixed(dec);
  return String(v);
}

function fmtMs(v) {
  if (v === null || v === undefined) return "—";
  if (v >= 60000) return (v / 60000).toFixed(1) + " min";
  if (v >= 1000) return (v / 1000).toFixed(1) + "s";
  return Math.round(v) + "ms";
}

function shortName(n) { return (n || "").replace(/-q4km$/, ""); }

function pill(label, cls) {
  return `<span class="pill ${cls}">${label}</span>`;
}

function statusPill(m) {
  const d = m.derived || {};
  const size = m.size_mb || 0;
  if (d.success === 0 && (d.error || 0) > 0) return pill("INCOMPAT", "pill-incompat");
  if (size > 1500) return pill("HC-1 FAIL", "pill-fail");
  if ((d.success || 0) > 0) return pill("PASS", "pill-pass");
  return pill("?", "pill-warn");
}

function scoreBar(score) {
  if (score === null || score === undefined) return "—";
  const pct = Math.round(score * 100);
  return `<div class="score-bar-wrap">
    <div class="score-bar"><div class="score-bar-fill" style="width:${pct}%"></div></div>
    <span class="score-num">${score.toFixed(3)}</span>
  </div>`;
}

function tempClass(rise) {
  if (rise === null) return "muted";
  if (rise > 8) return "text-bad";
  if (rise > 3) return "text-warn";
  return "text-good";
}

// ── Chart helpers ─────────────────────────────────────────
function newChart(id, type, data, options = {}) {
  const el = document.getElementById(id);
  if (!el) return null;
  const existing = Chart.getChart(el);
  if (existing) existing.destroy();
  return new Chart(el, {
    type,
    data,
    options: { responsive: true, maintainAspectRatio: true, ...options },
  });
}

const SCALE_OPTS = {
  y: { grid: { color: "#1e2640" } },
  x: { grid: { color: "#1e2640" } },
};

// ── Sortable table helper ─────────────────────────────────
function bindSort(table) {
  let sortCol = null, sortDir = "desc";
  const tbody = table.querySelector("tbody");

  table.querySelectorAll("thead th[data-col]").forEach(th => {
    th.addEventListener("click", () => {
      const col = th.getAttribute("data-col");
      if (sortCol === col) sortDir = sortDir === "asc" ? "desc" : "asc";
      else { sortCol = col; sortDir = "desc"; }
      table.querySelectorAll("thead th").forEach(t => t.classList.remove("sort-asc", "sort-desc"));
      th.classList.add("sort-" + sortDir);

      const rows = [...tbody.querySelectorAll("tr")];
      rows.sort((a, b) => {
        const av = a.dataset[col], bv = b.dataset[col];
        if (av === undefined && bv === undefined) return 0;
        if (av === undefined) return 1;
        if (bv === undefined) return -1;
        const an = parseFloat(av), bn = parseFloat(bv);
        const d = isNaN(an) || isNaN(bn) ? av.localeCompare(bv) : an - bn;
        return sortDir === "asc" ? d : -d;
      });
      rows.forEach(r => tbody.appendChild(r));
    });
  });
}

// ── Filter helpers ────────────────────────────────────────
function populateSel(sel, values, allLabel = "All") {
  if (!sel) return;
  sel.innerHTML = "";
  [allLabel, ...values].forEach(v => {
    const o = document.createElement("option");
    o.value = v; o.textContent = v;
    sel.appendChild(o);
  });
}

function uniq(arr) { return [...new Set(arr)].sort(); }

function filterSummaries(summaries, deviceVal, modelVal) {
  return summaries.filter(m => {
    if (deviceVal && deviceVal !== "All" && m.device !== deviceVal) return false;
    if (modelVal && modelVal !== "All" && m.model !== modelVal) return false;
    return true;
  });
}

function filterRuns(runs, deviceVal, modelVal) {
  return runs.filter(r => {
    if (deviceVal && deviceVal !== "All" && r.device !== deviceVal) return false;
    if (modelVal && modelVal !== "All" && r.model !== modelVal) return false;
    return true;
  });
}

// ── Thermal rise util ─────────────────────────────────────
function thermalRise(m) {
  const d = m.derived || {};
  return d.max_temp_before_c != null && d.max_temp_after_c != null
    ? d.max_temp_after_c - d.max_temp_before_c
    : null;
}

// ──────────────────────────────────────────────────────────
// OVERVIEW PAGE
// ──────────────────────────────────────────────────────────
function initOverviewPage(data) {
  const allSummaries = data.model_summaries || [];
  const allRuns = data.runs || [];

  const deviceSel = document.getElementById("deviceFilter");
  const modelSel = document.getElementById("modelFilter");
  const chip = document.getElementById("filterChip");

  // Populate filters from model_summaries
  populateSel(deviceSel, uniq(allSummaries.map(m => m.device)));
  populateSel(modelSel, allSummaries.map(m => shortName(m.model)));

  function getFilters() {
    // model filter compares shortName
    const dv = deviceSel ? deviceSel.value : "All";
    const mv = modelSel ? modelSel.value : "All";
    return { dv, mv };
  }

  function render() {
    const { dv, mv } = getFilters();

    // Filter summaries — model filter uses shortName comparison
    const sums = allSummaries.filter(m => {
      if (dv !== "All" && m.device !== dv) return false;
      if (mv !== "All" && shortName(m.model) !== mv) return false;
      return true;
    });

    if (chip) chip.textContent = `${sums.length} model${sums.length !== 1 ? "s" : ""} · ${allRuns.length} runs`;

    renderKpis(sums, allRuns);
    renderOverviewCharts(sums);
    renderSummaryTable(sums);
  }

  if (deviceSel) deviceSel.addEventListener("change", render);
  if (modelSel) modelSel.addEventListener("change", render);

  render();
}

function renderKpis(sums, allRuns) {
  const kpiRow = document.getElementById("kpiRow");
  if (!kpiRow) return;
  kpiRow.innerHTML = "";

  const totalRuns = allRuns.length;
  const passingModels = sums.filter(m => (m.derived || {}).success > 0 && (m.size_mb || 0) <= 1500).length;
  const topModel = [...sums].sort((a, b) => (b.scoring?.weighted_score || 0) - (a.scoring?.weighted_score || 0))[0] || {};
  const topScore = topModel.scoring?.weighted_score ?? null;
  const maxRise = Math.max(-99, ...sums.map(m => thermalRise(m) ?? -99));

  const kpis = [
    ["Total Runs", totalRuns, "across all models"],
    ["Shown Models", sums.length + "/" + (allRuns ? new Set(allRuns.map(r=>r.model)).size : 7), "matching filters"],
    ["Passing HC-1", passingModels, "≤ 1500 MB + success > 0"],
    ["Top Score", topScore !== null ? topScore.toFixed(3) : "—", shortName(topModel.model || "")],
    ["Best tok/s", fmt(topModel.derived?.avg_tokens_per_sec), shortName(topModel.model || "")],
    ["Max Temp Rise", maxRise > -99 ? (maxRise > 0 ? "+" : "") + maxRise.toFixed(1) + "°C" : "—", "worst inference delta"],
  ];
  kpis.forEach(([label, val, sub]) => {
    kpiRow.insertAdjacentHTML("beforeend",
      `<div class="kpi-box"><div class="kpi-label">${label}</div><div class="kpi-value">${val}</div><div class="kpi-sub">${sub}</div></div>`);
  });
}

function renderOverviewCharts(sums) {
  if (!sums.length) return;

  const labels = sums.map(m => shortName(m.model));

  // tok/s
  newChart("chartTokPerSec", "bar", {
    labels,
    datasets: [{
      label: "Avg tok/s",
      data: sums.map(m => m.derived?.avg_tokens_per_sec || 0),
      backgroundColor: sums.map(m => modelColor(m.model) + "99"),
      borderColor: sums.map(m => modelColor(m.model)),
      borderWidth: 1,
    }]
  }, {
    plugins: { legend: { display: false }, tooltip: { callbacks: { label: ctx => " " + ctx.raw.toFixed(1) + " tok/s" } } },
    scales: { y: { beginAtZero: true, ...SCALE_OPTS.y }, x: SCALE_OPTS.x },
  });

  // weighted score
  const scores = sums.map(m => m.scoring?.weighted_score || 0);
  newChart("chartScore", "bar", {
    labels,
    datasets: [{
      label: "Weighted Score",
      data: scores,
      backgroundColor: scores.map(s => s > 0.7 ? "#2ecc7199" : s > 0.4 ? "#f1c40f99" : "#e74c3c99"),
      borderColor: scores.map(s => s > 0.7 ? "#2ecc71" : s > 0.4 ? "#f1c40f" : "#e74c3c"),
      borderWidth: 1,
    }]
  }, {
    plugins: { legend: { display: false } },
    scales: { y: { beginAtZero: true, max: 1.05, ...SCALE_OPTS.y }, x: SCALE_OPTS.x },
  });

  // thermal rise
  const rises = sums.map(m => thermalRise(m));
  newChart("chartThermal", "bar", {
    labels,
    datasets: [{
      label: "Temp rise (°C)",
      data: rises,
      backgroundColor: rises.map(v => v === null ? "#8892a499" : v > 8 ? "#e74c3c99" : v > 3 ? "#f1c40f99" : "#2ecc7199"),
      borderColor: rises.map(v => v === null ? "#8892a4" : v > 8 ? "#e74c3c" : v > 3 ? "#f1c40f" : "#2ecc71"),
      borderWidth: 1,
    }]
  }, {
    plugins: { legend: { display: false }, tooltip: { callbacks: { label: ctx => ctx.raw !== null ? " " + (ctx.raw > 0 ? "+" : "") + ctx.raw.toFixed(1) + "°C" : " —" } } },
    scales: { y: { ...SCALE_OPTS.y }, x: SCALE_OPTS.x },
  });

  // size vs speed scatter
  const scatterPoints = sums.filter(m => (m.derived?.avg_tokens_per_sec || 0) > 0);
  newChart("chartSizeVsSpeed", "scatter", {
    datasets: scatterPoints.map(m => ({
      label: shortName(m.model),
      data: [{ x: m.size_mb || 0, y: m.derived.avg_tokens_per_sec }],
      backgroundColor: modelColor(m.model) + "cc",
      pointRadius: 10,
      pointHoverRadius: 13,
    }))
  }, {
    plugins: {
      legend: { position: "right", labels: { font: { size: 11 }, boxWidth: 10 } },
      tooltip: { callbacks: { label: ctx => `${ctx.dataset.label}: ${ctx.raw.x}MB, ${ctx.raw.y.toFixed(1)} tok/s` } },
    },
    scales: {
      x: { title: { display: true, text: "Model Size (MB)", color: "#8892a4" }, ...SCALE_OPTS.x },
      y: { title: { display: true, text: "Avg tok/s", color: "#8892a4" }, beginAtZero: true, ...SCALE_OPTS.y },
    },
  });

  // radar — passing models only
  const passSums = sums.filter(m => m.scoring && (m.derived?.success || 0) > 0);
  if (passSums.length > 0) {
    newChart("chartRadar", "radar", {
      labels: ["Speed", "Thermal", "Stability", "Output", "Memory"],
      datasets: passSums.map(m => ({
        label: shortName(m.model),
        data: [
          m.scoring.components.speed,
          m.scoring.components.thermal_efficiency,
          m.scoring.components.stability,
          m.scoring.components.output_success,
          m.scoring.components.memory_efficiency,
        ],
        borderColor: modelColor(m.model),
        backgroundColor: modelColor(m.model) + "22",
        borderWidth: 2,
        pointRadius: 3,
      }))
    }, {
      plugins: { legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } } },
      scales: {
        r: {
          beginAtZero: true, max: 1,
          ticks: { stepSize: 0.25, font: { size: 10 } },
          grid: { color: "#1e2640" },
          angleLines: { color: "#1e2640" },
          pointLabels: { color: "#8892a4", font: { size: 11 } },
        }
      },
    });
  }

  // stability stacked bar
  newChart("chartStability", "bar", {
    labels,
    datasets: [
      { label: "Success", data: sums.map(m => m.derived?.success || 0), backgroundColor: "#2ecc7199", borderColor: "#2ecc71", borderWidth: 1 },
      { label: "Error",   data: sums.map(m => m.derived?.error || 0),   backgroundColor: "#e74c3c99", borderColor: "#e74c3c", borderWidth: 1 },
      { label: "Timeout", data: sums.map(m => m.derived?.timeout || 0), backgroundColor: "#f1c40f99", borderColor: "#f1c40f", borderWidth: 1 },
    ]
  }, {
    plugins: { legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } } },
    scales: { x: { stacked: true, ...SCALE_OPTS.x }, y: { stacked: true, beginAtZero: true, ...SCALE_OPTS.y } },
  });
}

function renderSummaryTable(sums) {
  const table = document.getElementById("summaryTable");
  if (!table) return;
  const tbody = table.querySelector("tbody");
  tbody.innerHTML = "";

  sums.forEach((m, i) => {
    const d = m.derived || {};
    const sc = m.scoring || {};
    const rank = sc.rank || (i + 1);
    const rise = thermalRise(m);
    const tr = document.createElement("tr");
    // Store numeric values in data-* for sort
    tr.dataset.rank = rank;
    tr.dataset.model = m.model;
    tr.dataset.size_mb = m.size_mb || 0;
    tr.dataset.avg_tok = d.avg_tokens_per_sec || 0;
    tr.dataset.p50_dur = d.p50_duration_ms || 0;
    tr.dataset.p95_dur = d.p95_duration_ms || 0;
    tr.dataset.success = d.success || 0;
    tr.dataset.temp_rise = rise ?? "";
    tr.dataset.score = sc.weighted_score || 0;
    tr.innerHTML = `
      <td class="mono">${rank}</td>
      <td><strong>${shortName(m.model)}</strong><br><span class="muted" style="font-size:11px">${m.provider || ""}</span></td>
      <td class="mono">${m.size_mb || "—"}</td>
      <td class="mono">${fmt(d.avg_tokens_per_sec)}</td>
      <td class="mono">${d.p50_duration_ms != null ? fmtMs(d.p50_duration_ms) : "—"}</td>
      <td class="mono">${d.p95_duration_ms != null ? fmtMs(d.p95_duration_ms) : "—"}</td>
      <td class="mono">${d.success || 0} / ${d.prompts || 20}</td>
      <td class="mono ${tempClass(rise)}">${rise !== null ? (rise > 0 ? "+" : "") + rise.toFixed(1) + "°C" : "—"}</td>
      <td>${scoreBar(sc.weighted_score)}</td>
      <td>${statusPill(m)}</td>
    `;
    tbody.appendChild(tr);
  });

  bindSort(table);
}

// ──────────────────────────────────────────────────────────
// MODELS PAGE
// ──────────────────────────────────────────────────────────
function initModelsPage(data) {
  const allSummaries = data.model_summaries || [];

  const deviceSel = document.getElementById("deviceFilter");
  const modelSel = document.getElementById("modelFilter");

  populateSel(deviceSel, uniq(allSummaries.map(m => m.device)));
  populateSel(modelSel, allSummaries.map(m => shortName(m.model)));

  function getSums() {
    const dv = deviceSel?.value || "All";
    const mv = modelSel?.value || "All";
    return allSummaries.filter(m => {
      if (dv !== "All" && m.device !== dv) return false;
      if (mv !== "All" && shortName(m.model) !== mv) return false;
      return true;
    });
  }

  function render() {
    const sums = getSums();
    if (!sums.length) return;
    const labels = sums.map(m => shortName(m.model));

    // tok/s
    newChart("chartTokSec", "bar", {
      labels,
      datasets: [{
        label: "Avg tok/s",
        data: sums.map(m => m.derived?.avg_tokens_per_sec || 0),
        backgroundColor: sums.map(m => modelColor(m.model) + "99"),
        borderColor: sums.map(m => modelColor(m.model)),
        borderWidth: 1,
      }]
    }, { plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true, ...SCALE_OPTS.y }, x: SCALE_OPTS.x } });

    // p50 vs p95 latency (log scale)
    newChart("chartLatency", "bar", {
      labels,
      datasets: [
        { label: "p50 (ms)", data: sums.map(m => m.derived?.p50_duration_ms || 0), backgroundColor: "#4f8ef799", borderColor: "#4f8ef7", borderWidth: 1 },
        { label: "p95 (ms)", data: sums.map(m => m.derived?.p95_duration_ms || 0), backgroundColor: "#e74c3c99", borderColor: "#e74c3c", borderWidth: 1 },
      ]
    }, {
      plugins: { legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } }, tooltip: { callbacks: { label: ctx => ` ${fmtMs(ctx.raw)}` } } },
      scales: {
        y: { type: "logarithmic", ticks: { callback: v => fmtMs(v) }, ...SCALE_OPTS.y },
        x: SCALE_OPTS.x,
      },
    });

    // model size
    newChart("chartSize", "bar", {
      labels,
      datasets: [{
        label: "Size (MB)",
        data: sums.map(m => m.size_mb || 0),
        backgroundColor: sums.map(m => (m.size_mb || 0) > 1500 ? "#e74c3c99" : "#2ecc7199"),
        borderColor: sums.map(m => (m.size_mb || 0) > 1500 ? "#e74c3c" : "#2ecc71"),
        borderWidth: 1,
      }]
    }, {
      plugins: { legend: { display: false } },
      scales: { y: { beginAtZero: true, ...SCALE_OPTS.y }, x: SCALE_OPTS.x },
    });

    // RAM delta
    newChart("chartRamDelta", "bar", {
      labels,
      datasets: [{
        label: "RAM delta (MB)",
        data: sums.map(m => m.derived?.ram_delta_mb ?? null),
        backgroundColor: sums.map(m => (m.derived?.ram_delta_mb || 0) > 0 ? "#e74c3c99" : "#2ecc7199"),
        borderColor: sums.map(m => (m.derived?.ram_delta_mb || 0) > 0 ? "#e74c3c" : "#2ecc71"),
        borderWidth: 1,
      }]
    }, { plugins: { legend: { display: false } }, scales: { y: { ...SCALE_OPTS.y }, x: SCALE_OPTS.x } });

    // avg output words
    newChart("chartOutputLen", "bar", {
      labels,
      datasets: [{
        label: "Avg output words",
        data: sums.map(m => m.derived?.avg_output_words || 0),
        backgroundColor: "#9b59b699", borderColor: "#9b59b6", borderWidth: 1,
      }]
    }, { plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true, ...SCALE_OPTS.y }, x: SCALE_OPTS.x } });

    // score components stacked (weights applied)
    newChart("chartScoreComponents", "bar", {
      labels,
      datasets: [
        { label: "Speed (25%)",    data: sums.map(m => (m.scoring?.components.speed || 0) * 0.25),              backgroundColor: "#4f8ef799", borderColor: "#4f8ef7", borderWidth: 1 },
        { label: "Thermal (25%)",  data: sums.map(m => (m.scoring?.components.thermal_efficiency || 0) * 0.25), backgroundColor: "#2ecc7199", borderColor: "#2ecc71", borderWidth: 1 },
        { label: "Stability (20%)",data: sums.map(m => (m.scoring?.components.stability || 0) * 0.20),          backgroundColor: "#f1c40f99", borderColor: "#f1c40f", borderWidth: 1 },
        { label: "Output (20%)",   data: sums.map(m => (m.scoring?.components.output_success || 0) * 0.20),     backgroundColor: "#e67e2299", borderColor: "#e67e22", borderWidth: 1 },
        { label: "Memory (10%)",   data: sums.map(m => (m.scoring?.components.memory_efficiency || 0) * 0.10),  backgroundColor: "#9b59b699", borderColor: "#9b59b6", borderWidth: 1 },
      ]
    }, {
      plugins: { legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } } },
      scales: { x: { stacked: true, ...SCALE_OPTS.x }, y: { stacked: true, beginAtZero: true, max: 1.05, ...SCALE_OPTS.y } },
    });

    // table
    const table = document.getElementById("modelTable");
    if (!table) return;
    const tbody = table.querySelector("tbody");
    tbody.innerHTML = "";
    sums.forEach(m => {
      const d = m.derived || {};
      const sc = m.scoring || {};
      const rise = thermalRise(m);
      const hc1 = (m.size_mb || 0) > 1500 ? pill("FAIL", "pill-fail") : pill("PASS", "pill-pass");
      const tr = document.createElement("tr");
      tr.dataset.model = m.model;
      tr.dataset.provider = m.provider || "";
      tr.dataset.size_mb = m.size_mb || 0;
      tr.dataset.avg_tok = d.avg_tokens_per_sec || 0;
      tr.dataset.p50_dur = d.p50_duration_ms || 0;
      tr.dataset.p95_dur = d.p95_duration_ms || 0;
      tr.dataset.success = d.success || 0;
      tr.dataset.errors = d.error || 0;
      tr.dataset.out_words = d.avg_output_words || 0;
      tr.dataset.temp_rise = rise ?? "";
      tr.dataset.ram_delta = d.ram_delta_mb ?? "";
      tr.dataset.score = sc.weighted_score || 0;
      tr.innerHTML = `
        <td><strong>${shortName(m.model)}</strong></td>
        <td>${m.provider || "—"}</td>
        <td class="mono">${m.size_mb || "—"}</td>
        <td class="mono">${fmt(d.avg_tokens_per_sec)}</td>
        <td class="mono">${d.p50_duration_ms != null ? fmtMs(d.p50_duration_ms) : "—"}</td>
        <td class="mono">${d.p95_duration_ms != null ? fmtMs(d.p95_duration_ms) : "—"}</td>
        <td class="mono">${d.success || 0}</td>
        <td class="mono ${(d.error || 0) > 0 ? "text-bad" : ""}">${d.error || 0}</td>
        <td class="mono">${d.avg_output_words != null ? d.avg_output_words.toFixed(0) : "—"}</td>
        <td class="mono ${tempClass(rise)}">${rise !== null ? (rise > 0 ? "+" : "") + rise.toFixed(1) : "—"}</td>
        <td class="mono">${d.ram_delta_mb != null ? (d.ram_delta_mb > 0 ? "+" : "") + d.ram_delta_mb : "—"}</td>
        <td>${scoreBar(sc.weighted_score)}</td>
        <td>${hc1}</td>
      `;
      tbody.appendChild(tr);
    });
    bindSort(table);
  }

  if (deviceSel) deviceSel.addEventListener("change", render);
  if (modelSel) modelSel.addEventListener("change", render);
  render();
}

// ──────────────────────────────────────────────────────────
// THERMALS PAGE
// ──────────────────────────────────────────────────────────
function initThermalsPage(data) {
  const allSummaries = data.model_summaries || [];

  const deviceSel = document.getElementById("deviceFilter");
  const modelSel = document.getElementById("modelFilter");

  // thermals.html may not have filter elements — fall back gracefully
  if (deviceSel) populateSel(deviceSel, uniq(allSummaries.map(m => m.device)));
  if (modelSel) populateSel(modelSel, allSummaries.map(m => shortName(m.model)));

  function getSums() {
    const dv = deviceSel?.value || "All";
    const mv = modelSel?.value || "All";
    return allSummaries.filter(m => {
      if (dv !== "All" && m.device !== dv) return false;
      if (mv !== "All" && shortName(m.model) !== mv) return false;
      return true;
    });
  }

  function render() {
    const sums = getSums();
    if (!sums.length) return;

    const labels = sums.map(m => shortName(m.model));
    const before = sums.map(m => m.derived?.max_temp_before_c ?? null);
    const after  = sums.map(m => m.derived?.max_temp_after_c ?? null);
    const rises  = sums.map(m => thermalRise(m));

    newChart("chartBeforeAfter", "bar", {
      labels,
      datasets: [
        { label: "Before (°C)", data: before, backgroundColor: "#4f8ef799", borderColor: "#4f8ef7", borderWidth: 1 },
        { label: "After (°C)",  data: after,  backgroundColor: "#e74c3c99", borderColor: "#e74c3c", borderWidth: 1 },
      ]
    }, {
      plugins: { legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } }, tooltip: { callbacks: { label: ctx => ` ${ctx.raw?.toFixed(1) ?? "—"}°C` } } },
      scales: { y: { suggestedMin: 25, suggestedMax: 65, ...SCALE_OPTS.y }, x: SCALE_OPTS.x },
    });

    newChart("chartThermalRise", "bar", {
      labels,
      datasets: [{
        label: "Temp rise (°C)",
        data: rises,
        backgroundColor: rises.map(v => v === null ? "#8892a499" : v > 8 ? "#e74c3c99" : v > 3 ? "#f1c40f99" : "#2ecc7199"),
        borderColor: rises.map(v => v === null ? "#8892a4" : v > 8 ? "#e74c3c" : v > 3 ? "#f1c40f" : "#2ecc71"),
        borderWidth: 1,
      }]
    }, {
      plugins: { legend: { display: false }, tooltip: { callbacks: { label: ctx => ctx.raw !== null ? ` ${ctx.raw > 0 ? "+" : ""}${ctx.raw.toFixed(1)}°C` : " —" } } },
      scales: { y: { ...SCALE_OPTS.y }, x: SCALE_OPTS.x },
    });

    newChart("chartWarnCount", "bar", {
      labels,
      datasets: [{
        label: "Thermal warnings",
        data: sums.map(m => m.derived?.thermal_warning_count || 0),
        backgroundColor: "#f1c40f99", borderColor: "#f1c40f", borderWidth: 1,
      }]
    }, {
      plugins: { legend: { display: false } },
      scales: { y: { beginAtZero: true, max: 22, ...SCALE_OPTS.y }, x: SCALE_OPTS.x },
    });

    // thermal vs speed scatter
    const scatter = sums.filter(m => (m.derived?.avg_tokens_per_sec || 0) > 0 && thermalRise(m) !== null);
    newChart("chartThermalVsSpeed", "scatter", {
      datasets: scatter.map(m => ({
        label: shortName(m.model),
        data: [{ x: thermalRise(m), y: m.derived.avg_tokens_per_sec }],
        backgroundColor: modelColor(m.model) + "cc",
        pointRadius: 10,
        pointHoverRadius: 13,
      }))
    }, {
      plugins: {
        legend: { position: "right", labels: { font: { size: 11 }, boxWidth: 10 } },
        tooltip: { callbacks: { label: ctx => `${ctx.dataset.label}: ${ctx.raw.x > 0 ? "+" : ""}${ctx.raw.x.toFixed(1)}°C, ${ctx.raw.y.toFixed(1)} tok/s` } },
      },
      scales: {
        x: { title: { display: true, text: "Temp rise (°C)", color: "#8892a4" }, ...SCALE_OPTS.x },
        y: { title: { display: true, text: "Avg tok/s", color: "#8892a4" }, beginAtZero: true, ...SCALE_OPTS.y },
      },
    });

    // thermal table
    const table = document.getElementById("thermalTable");
    if (!table) return;
    const tbody = table.querySelector("tbody");
    tbody.innerHTML = "";
    sums.forEach(m => {
      const d = m.derived || {};
      const rise = thermalRise(m);
      const bucket = d.thermal_after_bucket || "—";
      const hc6 = (d.max_temp_after_c || 0) <= 60 ? pill("PASS", "pill-pass") : pill("FAIL", "pill-fail");
      const tr = document.createElement("tr");
      tr.dataset.model = m.model;
      tr.dataset.before = d.max_temp_before_c ?? "";
      tr.dataset.after = d.max_temp_after_c ?? "";
      tr.dataset.rise = rise ?? "";
      tr.dataset.warnings = d.thermal_warning_count ?? 0;
      tr.innerHTML = `
        <td><strong>${shortName(m.model)}</strong></td>
        <td class="mono">${d.max_temp_before_c != null ? d.max_temp_before_c.toFixed(1) + "°C" : "—"}</td>
        <td class="mono ${bucket === "red" ? "text-bad" : bucket === "yellow" ? "text-warn" : "text-good"}">${d.max_temp_after_c != null ? d.max_temp_after_c.toFixed(1) + "°C" : "—"}</td>
        <td class="mono ${tempClass(rise)}">${rise !== null ? (rise > 0 ? "+" : "") + rise.toFixed(1) + "°C" : "—"}</td>
        <td class="mono">${d.thermal_warning_count ?? "—"} / 20</td>
        <td><span class="badge ${bucket === "red" ? "badge-red" : bucket === "yellow" ? "badge-yellow" : "badge-green"}">${bucket}</span></td>
        <td>${hc6}</td>
      `;
      tbody.appendChild(tr);
    });
    bindSort(table);

    // thermal zones for top model
    renderThermalZones(data);
  }

  if (deviceSel) deviceSel.addEventListener("change", render);
  if (modelSel) modelSel.addEventListener("change", render);
  render();
}

function renderThermalZones(data) {
  const zoneDiv = document.getElementById("thermalZoneTable");
  if (!zoneDiv) return;
  const topModel = data.model_summaries?.find(m => m.model === "qwen2.5-0.5b-q4km");
  const zones = topModel?.snapshot_after?.thermal?.zones || [];
  if (zones.length > 0) {
    let html = `<div class="table-wrap"><table><thead><tr><th>Zone</th><th>Temp After (°C)</th></tr></thead><tbody>`;
    zones.forEach(z => {
      const tc = z.temp_c != null ? parseFloat(z.temp_c) : null;
      const cls = tc !== null ? (tc > 55 ? "text-bad" : tc > 45 ? "text-warn" : "text-good") : "muted";
      html += `<tr><td class="mono">${z.type || z.zone || "zone"}</td><td class="mono ${cls}">${tc != null ? tc.toFixed(1) + "°C" : "—"}</td></tr>`;
    });
    html += "</tbody></table></div>";
    zoneDiv.innerHTML = html;
  } else {
    zoneDiv.innerHTML = `<p class="muted" style="font-size:13px">Zone detail data not available.</p>`;
  }
}

// ──────────────────────────────────────────────────────────
// PROMPTS PAGE
// ──────────────────────────────────────────────────────────
function initPromptsPage(data) {
  const allSummaries = data.model_summaries || [];

  // Only include models that have per-prompt data and had successes
  const passingModels = allSummaries.filter(m =>
    (m.derived?.prompt_results || []).some(r => r.status === "ok")
  );

  const modelSel = document.getElementById("modelFilter");
  if (!modelSel) return;

  passingModels.forEach(m => {
    const o = document.createElement("option");
    o.value = m.model;
    o.textContent = shortName(m.model);
    modelSel.appendChild(o);
  });

  const chip = document.getElementById("promptChip");

  function render() {
    const modelName = modelSel.value;
    const modelData = passingModels.find(m => m.model === modelName);
    const promptData = modelData?.derived?.prompt_results || [];

    if (chip) chip.textContent = `${promptData.length} prompts · ${shortName(modelName)}`;

    if (!promptData.length) return;

    const ids = promptData.map(r => r.prompt_id);
    const durs = promptData.map(r => r.duration_ms || 0);
    const toks = promptData.map(r => r.tokens_per_sec || 0);
    const outw = promptData.map(r => r.out_words || 0);

    newChart("chartPromptDuration", "bar", {
      labels: ids,
      datasets: [{
        label: "Duration",
        data: durs,
        backgroundColor: durs.map(d => d > 60000 ? "#e74c3c99" : d > 20000 ? "#f1c40f99" : "#4f8ef799"),
        borderColor: durs.map(d => d > 60000 ? "#e74c3c" : d > 20000 ? "#f1c40f" : "#4f8ef7"),
        borderWidth: 1,
      }]
    }, {
      plugins: { legend: { display: false }, tooltip: { callbacks: { label: ctx => " " + fmtMs(ctx.raw) } } },
      scales: {
        y: { beginAtZero: true, ticks: { callback: v => fmtMs(v) }, ...SCALE_OPTS.y },
        x: SCALE_OPTS.x,
      },
    });

    newChart("chartPromptTokSec", "bar", {
      labels: ids,
      datasets: [{ label: "Tok/s", data: toks, backgroundColor: "#2ecc7199", borderColor: "#2ecc71", borderWidth: 1 }]
    }, { plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true, ...SCALE_OPTS.y }, x: SCALE_OPTS.x } });

    newChart("chartPromptOutLen", "bar", {
      labels: ids,
      datasets: [{ label: "Output words", data: outw, backgroundColor: "#9b59b699", borderColor: "#9b59b6", borderWidth: 1 }]
    }, { plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true, ...SCALE_OPTS.y }, x: SCALE_OPTS.x } });

    // table
    const tbody = document.querySelector("#promptTable tbody");
    if (!tbody) return;
    tbody.innerHTML = "";
    promptData.forEach(r => {
      const tr = document.createElement("tr");
      tr.dataset.prompt_id = r.prompt_id;
      tr.dataset.status = r.status;
      tr.dataset.duration_ms = r.duration_ms || 0;
      tr.dataset.tokens_per_sec = r.tokens_per_sec || 0;
      tr.dataset.out_words = r.out_words || 0;
      tr.innerHTML = `
        <td class="mono"><strong>${r.prompt_id}</strong></td>
        <td>${r.status === "ok" ? pill("ok", "pill-pass") : pill(r.status, "pill-fail")}</td>
        <td class="mono">${fmtMs(r.duration_ms)}</td>
        <td class="mono">${r.tokens_per_sec ? r.tokens_per_sec.toFixed(1) : "—"}</td>
        <td class="mono">${r.out_words || 0}</td>
        <td>${r.thermal_warning ? '<span class="text-warn">⚠ yes</span>' : '<span class="muted">no</span>'}</td>
      `;
      tbody.appendChild(tr);
    });
    const pt = document.getElementById("promptTable");
    if (pt) bindSort(pt);
  }

  // Cross-model variance chart (log scale)
  const P_IDS = Array.from({ length: 20 }, (_, i) => "P" + String(i + 1).padStart(2, "0"));
  newChart("chartVariance", "bar", {
    labels: P_IDS,
    datasets: passingModels.map(m => ({
      label: shortName(m.model),
      data: P_IDS.map(pid => {
        const r = (m.derived?.prompt_results || []).find(p => p.prompt_id === pid);
        return r?.duration_ms ?? null;
      }),
      backgroundColor: modelColor(m.model) + "99",
      borderColor: modelColor(m.model),
      borderWidth: 1,
    }))
  }, {
    plugins: {
      legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } },
      tooltip: { callbacks: { label: ctx => ctx.raw != null ? ` ${fmtMs(ctx.raw)}` : " —" } },
    },
    scales: {
      y: { type: "logarithmic", ticks: { callback: v => fmtMs(v) }, ...SCALE_OPTS.y },
      x: SCALE_OPTS.x,
    },
  });

  modelSel.addEventListener("change", render);
  if (passingModels.length > 0) render();
}

// ──────────────────────────────────────────────────────────
// DEVICES PAGE
// ──────────────────────────────────────────────────────────
function initDevicesPage(data) {
  const allRuns = data.runs || [];
  const allSummaries = data.model_summaries || [];

  // Build device profile cards
  const deviceProfiles = {};
  allRuns.forEach(run => {
    if (!deviceProfiles[run.device] && run.snapshot_before) {
      const dev = run.snapshot_before.device || {};
      const mem = run.snapshot_before.memory || {};
      deviceProfiles[run.device] = {
        model_name: dev.model || "Unknown",
        manufacturer: dev.manufacturer || "Unknown",
        android_version: dev.android_version || dev.release || "Unknown",
        sdk: dev.sdk_version || dev.sdk || "Unknown",
        cores: dev.cpu_cores || "Unknown",
        total_ram_mb: mem.total_mb,
        board: dev.board || "Unknown",
      };
    }
  });

  const container = document.getElementById("deviceCards");
  if (container) {
    const grid = document.createElement("div");
    grid.className = "device-card-grid";
    Object.entries(deviceProfiles).forEach(([device, info]) => {
      const totalRuns = allRuns.filter(r => r.device === device).length;
      const modelsTested = new Set(allRuns.filter(r => r.device === device).map(r => r.model)).size;
      const ramGB = info.total_ram_mb ? (info.total_ram_mb / 1024).toFixed(1) + " GB" : "—";
      grid.insertAdjacentHTML("beforeend", `
        <div class="device-card">
          <h3>${info.manufacturer} ${info.model_name}</h3>
          <div class="muted" style="font-size:12px;margin-bottom:10px">${device}</div>
          <div class="spec-list">
            <span class="spec-key">Android</span><span class="spec-val">${info.android_version} (SDK ${info.sdk})</span>
            <span class="spec-key">CPU Cores</span><span class="spec-val">${info.cores}</span>
            <span class="spec-key">Total RAM</span><span class="spec-val">${ramGB}</span>
            <span class="spec-key">Board/SoC</span><span class="spec-val">${info.board}</span>
            <span class="spec-key">Runs</span><span class="spec-val">${totalRuns}</span>
            <span class="spec-key">Models Tested</span><span class="spec-val">${modelsTested} / 7</span>
          </div>
        </div>
      `);
    });
    container.appendChild(grid);
  }

  // Top model per device
  const tbody = document.querySelector("#deviceTopTable tbody");
  if (tbody) {
    const scoresByDevice = data.scores_by_device || {};
    Object.entries(scoresByDevice).forEach(([device, models]) => {
      const top = (models || [])[0];
      if (!top) return;
      const d = top.derived || {};
      const rise = thermalRise(top);
      const deviceRuns = allRuns.filter(r => r.device === device).length;
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${device}</td>
        <td><strong>${shortName(top.model)}</strong></td>
        <td>${scoreBar(top.scoring?.weighted_score)}</td>
        <td class="mono">${fmt(d.avg_tokens_per_sec)}</td>
        <td class="mono ${tempClass(rise)}">${rise !== null ? (rise > 0 ? "+" : "") + rise.toFixed(1) + "°C" : "—"}</td>
        <td class="mono">${deviceRuns}</td>
      `;
      tbody.appendChild(tr);
    });
  }

  // Run matrix chart
  const allModels = [...new Set(allRuns.map(r => r.model))].sort();
  const devices = Object.keys(deviceProfiles);
  newChart("chartRunMatrix", "bar", {
    labels: devices,
    datasets: allModels.map((model, i) => ({
      label: shortName(model),
      data: devices.map(d => allRuns.filter(r => r.device === d && r.model === model).length),
      backgroundColor: modelColor(model) + "99",
      borderColor: modelColor(model),
      borderWidth: 1,
    }))
  }, {
    plugins: { legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } } },
    scales: { x: { stacked: true, ...SCALE_OPTS.x }, y: { stacked: true, beginAtZero: true, ...SCALE_OPTS.y } },
  });
}

// ──────────────────────────────────────────────────────────
// HISTORICAL PAGE
// ──────────────────────────────────────────────────────────
function initHistoricalPage(data) {
  const allRuns = data.runs || [];

  const modelSel = document.getElementById("modelFilter");
  const metricSel = document.getElementById("metricFilter");

  // Populate model filter
  const allModels = [...new Set(allRuns.map(r => r.model))].sort();
  populateSel(modelSel, allModels.map(shortName));
  // Fix option values to be the full model name for lookup
  if (modelSel) {
    [...modelSel.options].forEach((opt, i) => {
      if (opt.value === "All") return;
      opt.value = allModels.find(m => shortName(m) === opt.value) || opt.value;
    });
  }

  const metricFns = {
    avg_tok:    r => r.derived?.avg_tokens_per_sec ?? null,
    p50_dur:    r => r.derived?.p50_duration_ms ?? null,
    temp_after: r => r.derived?.max_temp_after_c ?? null,
    success:    r => r.derived?.success ?? null,
  };

  const allTs = [...new Set(allRuns.map(r => r.timestamp))].sort();

  // Group runs by model
  const byModel = {};
  allRuns.forEach(r => {
    if (!byModel[r.model]) byModel[r.model] = [];
    byModel[r.model].push(r);
  });
  Object.values(byModel).forEach(rs => rs.sort((a, b) => String(a.timestamp).localeCompare(String(b.timestamp))));

  function renderTrend() {
    const modelFilter = modelSel?.value || "All";
    const metric = metricSel?.value || "avg_tok";
    const getter = metricFns[metric] || metricFns.avg_tok;

    const filteredRuns = allRuns.filter(r => modelFilter === "All" || r.model === modelFilter)
                                .sort((a, b) => String(a.timestamp).localeCompare(String(b.timestamp)));
    const filtByModel = {};
    filteredRuns.forEach(r => {
      if (!filtByModel[r.model]) filtByModel[r.model] = [];
      filtByModel[r.model].push(r);
    });
    const ts = [...new Set(filteredRuns.map(r => r.timestamp))].sort();

    newChart("chartTrend", "line", {
      labels: ts,
      datasets: Object.entries(filtByModel).map(([model, rs]) => ({
        label: shortName(model),
        data: ts.map(t => { const run = rs.find(r => r.timestamp === t); return run ? getter(run) : null; }),
        borderColor: modelColor(model),
        backgroundColor: modelColor(model) + "22",
        tension: 0.2, pointRadius: 5, spanGaps: false,
      }))
    }, {
      plugins: { legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } } },
      scales: { y: { ...SCALE_OPTS.y }, x: { ...SCALE_OPTS.x, ticks: { maxRotation: 45 } } },
    });
  }

  // tok/s history (always all models)
  newChart("chartTokHistory", "line", {
    labels: allTs,
    datasets: Object.entries(byModel).map(([model, rs]) => ({
      label: shortName(model),
      data: allTs.map(t => { const r = rs.find(r => r.timestamp === t); return r ? (r.derived?.avg_tokens_per_sec ?? null) : null; }),
      borderColor: modelColor(model), backgroundColor: modelColor(model) + "22",
      tension: 0.2, pointRadius: 5, spanGaps: false,
    }))
  }, {
    plugins: { legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } } },
    scales: { y: { beginAtZero: true, ...SCALE_OPTS.y }, x: { ...SCALE_OPTS.x, ticks: { maxRotation: 45 } } },
  });

  // thermal history
  newChart("chartThermalHistory", "line", {
    labels: allTs,
    datasets: Object.entries(byModel).map(([model, rs]) => ({
      label: shortName(model),
      data: allTs.map(t => { const r = rs.find(r => r.timestamp === t); return r ? (r.derived?.max_temp_after_c ?? null) : null; }),
      borderColor: modelColor(model), backgroundColor: modelColor(model) + "22",
      tension: 0.2, pointRadius: 5, spanGaps: false,
    }))
  }, {
    plugins: { legend: { position: "bottom", labels: { font: { size: 11 }, boxWidth: 10 } } },
    scales: { y: { suggestedMin: 25, ...SCALE_OPTS.y }, x: { ...SCALE_OPTS.x, ticks: { maxRotation: 45 } } },
  });

  // history table
  const table = document.getElementById("historyTable");
  if (table) {
    const tbody = table.querySelector("tbody");
    [...allRuns].sort((a,b) => String(b.timestamp).localeCompare(String(a.timestamp))).forEach(r => {
      const d = r.derived || {};
      const sc = r.scoring;
      const tr = document.createElement("tr");
      tr.dataset.timestamp = r.timestamp;
      tr.dataset.device = r.device;
      tr.dataset.model = r.model;
      tr.dataset.avg_tok = d.avg_tokens_per_sec || 0;
      tr.dataset.p50_dur = d.p50_duration_ms || 0;
      tr.dataset.success = d.success || 0;
      tr.dataset.errors = d.error || 0;
      tr.dataset.temp_after = d.max_temp_after_c || 0;
      tr.dataset.score = sc?.weighted_score || 0;
      tr.innerHTML = `
        <td class="mono">${r.timestamp}</td>
        <td>${r.device}</td>
        <td>${shortName(r.model)}</td>
        <td class="mono">${fmt(d.avg_tokens_per_sec)}</td>
        <td class="mono">${d.p50_duration_ms != null ? fmtMs(d.p50_duration_ms) : "—"}</td>
        <td class="mono">${d.success || 0}</td>
        <td class="mono ${(d.error || 0) > 0 ? "text-bad" : ""}">${d.error || 0}</td>
        <td class="mono">${d.max_temp_after_c != null ? d.max_temp_after_c.toFixed(1) + "°C" : "—"}</td>
        <td>${scoreBar(sc?.weighted_score)}</td>
      `;
      tbody.appendChild(tr);
    });
    bindSort(table);
  }

  // Regression detection
  const regressionDiv = document.getElementById("regressionList");
  if (regressionDiv) {
    const regressions = [];
    Object.entries(byModel).forEach(([model, rs]) => {
      if (rs.length < 2) return;
      for (let i = 1; i < rs.length; i++) {
        const prev = rs[i - 1].derived?.avg_tokens_per_sec;
        const curr = rs[i].derived?.avg_tokens_per_sec;
        if (prev && curr && (prev - curr) / prev > 0.10) {
          regressions.push({ model, from: rs[i - 1].timestamp, to: rs[i].timestamp, prev, curr });
        }
      }
    });
    if (regressions.length === 0) {
      regressionDiv.innerHTML = `<div class="badge badge-green">✓ No regressions detected across ${allRuns.length} runs</div>`;
    } else {
      regressionDiv.innerHTML = regressions.map(r =>
        `<div class="callout-warn" style="margin-bottom:8px;padding:10px;border-radius:8px">
          ⚠ ${shortName(r.model)}: tok/s dropped from ${r.prev.toFixed(1)} → ${r.curr.toFixed(1)}
          (${((r.prev - r.curr) / r.prev * 100).toFixed(0)}% decline) between ${r.from} and ${r.to}
        </div>`
      ).join("");
    }
  }

  if (modelSel) modelSel.addEventListener("change", renderTrend);
  if (metricSel) metricSel.addEventListener("change", renderTrend);
  renderTrend();
}
