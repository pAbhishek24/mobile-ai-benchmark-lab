/* AI Lab Dashboard — vanilla JS, no framework, no build step */
"use strict";

// ── Colours ──────────────────────────────────────────────
const PALETTE = [
  "#4f8ef7","#2ecc71","#f1c40f","#e74c3c",
  "#9b59b6","#1abc9c","#e67e22","#34495e",
];

const MODEL_COLORS = {};
function modelColor(name, idx) {
  if (!MODEL_COLORS[name]) MODEL_COLORS[name] = PALETTE[Object.keys(MODEL_COLORS).length % PALETTE.length];
  return MODEL_COLORS[name];
}

// ── Shared Chart.js defaults ──────────────────────────────
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
  if (!r.ok) throw new Error("Failed to load " + url);
  return r.json();
}

// ── Helpers ───────────────────────────────────────────────
function fmt(v, dec = 1) {
  if (v === null || v === undefined) return "—";
  if (typeof v === "number") return v.toFixed(dec);
  return String(v);
}

function fmtMs(v) {
  if (v === null || v === undefined) return "—";
  if (v >= 60000) return (v / 60000).toFixed(1) + " min";
  if (v >= 1000) return (v / 1000).toFixed(1) + "s";
  return v.toFixed(0) + "ms";
}

function pill(label, cls) {
  return `<span class="pill ${cls}">${label}</span>`;
}

function statusPill(model) {
  const d = model.derived || {};
  const size = model.size_mb;
  if (d.success === 0 && d.error > 0) return pill("INCOMPAT", "pill-incompat");
  if (size && size > 1500) return pill("HC-1 FAIL", "pill-fail");
  if (d.success === d.prompts && d.prompts > 0) return pill("PASS", "pill-pass");
  return pill("?", "pill-warn");
}

function scoreBar(score) {
  if (score === undefined || score === null) return "—";
  const pct = (score * 100).toFixed(0);
  return `<div class="score-bar-wrap">
    <div class="score-bar"><div class="score-bar-fill" style="width:${pct}%"></div></div>
    <span class="score-num">${score.toFixed(3)}</span>
  </div>`;
}

function sortTable(tbody, rows, col, dir) {
  rows.sort((a, b) => {
    const av = a[col], bv = b[col];
    if (av === null || av === undefined) return 1;
    if (bv === null || bv === undefined) return -1;
    const d = typeof av === "number" ? av - bv : String(av).localeCompare(String(bv));
    return dir === "asc" ? d : -d;
  });
  tbody.innerHTML = "";
  rows.forEach(r => tbody.appendChild(r._tr));
}

function bindSort(table, rows) {
  let col = null, dir = "desc";
  table.querySelectorAll("thead th[data-col]").forEach(th => {
    th.addEventListener("click", () => {
      const c = th.getAttribute("data-col");
      if (col === c) dir = dir === "asc" ? "desc" : "asc";
      else { col = c; dir = "desc"; }
      table.querySelectorAll("thead th").forEach(t => t.classList.remove("sort-asc","sort-desc"));
      th.classList.add("sort-" + dir);
      sortTable(table.querySelector("tbody"), rows, col, dir);
    });
  });
}

function newChart(id, type, data, options = {}) {
  const el = document.getElementById(id);
  if (!el) return null;
  const existing = Chart.getChart(el);
  if (existing) existing.destroy();
  return new Chart(el, { type, data, options: { responsive: true, maintainAspectRatio: true, ...options } });
}

// ── Shared filter init ─────────────────────────────────────
function initFilters(data, deviceSelId, modelSelId, onUpdate) {
  const runs = data.runs || [];
  const deviceSel = document.getElementById(deviceSelId);
  const modelSel = document.getElementById(modelSelId);
  if (!deviceSel && !modelSel) return () => runs;

  function uniq(arr) { return [...new Set(arr)].sort(); }

  if (deviceSel) {
    ["All", ...uniq(runs.map(r => r.device))].forEach(v => {
      const o = document.createElement("option"); o.value = o.textContent = v;
      deviceSel.appendChild(o);
    });
    deviceSel.addEventListener("change", onUpdate);
  }
  if (modelSel) {
    ["All", ...uniq(runs.map(r => r.model))].forEach(v => {
      const o = document.createElement("option"); o.value = o.textContent = v;
      modelSel.appendChild(o);
    });
    modelSel.addEventListener("change", onUpdate);
  }

  return () => runs.filter(r => {
    if (deviceSel && deviceSel.value !== "All" && r.device !== deviceSel.value) return false;
    if (modelSel && modelSel.value !== "All" && r.model !== modelSel.value) return false;
    return true;
  });
}

// ── Per-prompt data embedded in each run ──────────────────
// The dashboard-data.json "runs" don't have per-prompt rows by default,
// but we embed them in dashboard-data-extended.json via Python.
// For now we rely on model_summaries derived metrics.

// ── OVERVIEW PAGE ─────────────────────────────────────────
function initOverviewPage(data) {
  const summaries = data.model_summaries || [];
  const runs = data.runs || [];

  // KPI row
  const kpiRow = document.getElementById("kpiRow");
  const totalRuns = runs.length;
  const passingModels = summaries.filter(m => (m.derived || {}).success > 0 && !((m.size_mb||0) > 1500)).length;
  const topModel = summaries[0] || {};
  const topScore = topModel.scoring ? topModel.scoring.weighted_score : null;
  const avgTok = summaries.filter(m => (m.derived||{}).avg_tokens_per_sec).map(m => m.derived.avg_tokens_per_sec);
  const overallAvgTok = avgTok.length ? avgTok.reduce((a,b)=>a+b,0)/avgTok.length : null;
  const maxRise = Math.max(...summaries.map(m => {
    const d = m.derived||{};
    const r = d.max_temp_before_c != null && d.max_temp_after_c != null ? d.max_temp_after_c - d.max_temp_before_c : -99;
    return r;
  }));

  const kpis = [
    ["Total Runs", totalRuns, "across all models"],
    ["Passing Models", passingModels + "/7", "all hard constraints"],
    ["Top Score", topScore !== null ? topScore.toFixed(3) : "—", topModel.model || ""],
    ["Best Avg tok/s", fmt(topModel.derived?.avg_tokens_per_sec), topModel.model || ""],
    ["Max Temp Rise", (maxRise > 0 ? "+" : "") + maxRise.toFixed(1) + "°C", "worst inference delta"],
    ["Dataset Date", (data.generated_at||"").slice(0,10), "last pipeline run"],
  ];
  kpis.forEach(([label, val, sub]) => {
    kpiRow.insertAdjacentHTML("beforeend",
      `<div class="kpi-box"><div class="kpi-label">${label}</div><div class="kpi-value">${val}</div><div class="kpi-sub">${sub}</div></div>`);
  });

  // Model names in scoring order
  const models = summaries.map(m => m.model);
  const shortName = n => n.replace(/-q4km$/,"");

  // Chart: tok/s
  const tokData = summaries.map(m => m.derived?.avg_tokens_per_sec || 0);
  newChart("chartTokPerSec","bar",{
    labels: models.map(shortName),
    datasets:[{
      label:"Avg tok/s",
      data: tokData,
      backgroundColor: summaries.map((m,i) => modelColor(m.model,i) + "88"),
      borderColor: summaries.map((m,i) => modelColor(m.model,i)),
      borderWidth:1,
    }]
  },{
    plugins:{legend:{display:false},tooltip:{callbacks:{label:ctx=>" "+ctx.raw.toFixed(1)+" tok/s"}}},
    scales:{y:{beginAtZero:true,grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}
  });

  // Chart: score
  const scoreData = summaries.map(m => m.scoring?.weighted_score || 0);
  newChart("chartScore","bar",{
    labels: models.map(shortName),
    datasets:[{
      label:"Weighted Score",
      data: scoreData,
      backgroundColor: scoreData.map(s => s > 0.7 ? "#2ecc7188" : s > 0.4 ? "#f1c40f88" : "#e74c3c88"),
      borderColor: scoreData.map(s => s > 0.7 ? "#2ecc71" : s > 0.4 ? "#f1c40f" : "#e74c3c"),
      borderWidth:1,
    }]
  },{
    plugins:{legend:{display:false}},
    scales:{y:{beginAtZero:true,max:1.05,grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}
  });

  // Chart: thermal rise
  const thermalRise = summaries.map(m => {
    const d = m.derived||{};
    return (d.max_temp_before_c != null && d.max_temp_after_c != null) ? d.max_temp_after_c - d.max_temp_before_c : null;
  });
  newChart("chartThermal","bar",{
    labels: models.map(shortName),
    datasets:[{
      label:"Temp rise (°C)",
      data: thermalRise,
      backgroundColor: thermalRise.map(v => v === null ? "#8892a488" : v > 8 ? "#e74c3c88" : v > 3 ? "#f1c40f88" : "#2ecc7188"),
      borderColor: thermalRise.map(v => v === null ? "#8892a4" : v > 8 ? "#e74c3c" : v > 3 ? "#f1c40f" : "#2ecc71"),
      borderWidth:1,
    }]
  },{
    plugins:{legend:{display:false},tooltip:{callbacks:{label:ctx=>ctx.raw !== null ? " "+ctx.raw.toFixed(1)+"°C" : " —"}}},
    scales:{y:{grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}
  });

  // Chart: size vs speed (scatter)
  const scatterData = summaries
    .filter(m => m.derived?.avg_tokens_per_sec > 0)
    .map(m => ({
      x: m.size_mb || 0,
      y: m.derived.avg_tokens_per_sec,
      label: shortName(m.model),
    }));
  newChart("chartSizeVsSpeed","scatter",{
    datasets: scatterData.map((pt,i) => ({
      label: pt.label,
      data: [{x: pt.x, y: pt.y}],
      backgroundColor: PALETTE[i % PALETTE.length] + "cc",
      pointRadius: 10,
      pointHoverRadius: 13,
    }))
  },{
    plugins:{
      legend:{position:"right",labels:{font:{size:11}}},
      tooltip:{callbacks:{label:ctx=>`${ctx.dataset.label}: ${ctx.raw.x}MB, ${ctx.raw.y.toFixed(1)} tok/s`}}
    },
    scales:{
      x:{title:{display:true,text:"Model Size (MB)",color:"#8892a4"},grid:{color:"#1e2640"}},
      y:{title:{display:true,text:"Avg tok/s",color:"#8892a4"},grid:{color:"#1e2640"},beginAtZero:true}
    }
  });

  // Radar — passing models only
  const passModels = summaries.filter(m => m.scoring && (m.derived||{}).success > 0);
  if (passModels.length > 0) {
    newChart("chartRadar","radar",{
      labels:["Speed","Thermal","Stability","Output","Memory"],
      datasets: passModels.map((m,i) => ({
        label: shortName(m.model),
        data: [
          m.scoring.components.speed,
          m.scoring.components.thermal_efficiency,
          m.scoring.components.stability,
          m.scoring.components.output_success,
          m.scoring.components.memory_efficiency,
        ],
        borderColor: PALETTE[i % PALETTE.length],
        backgroundColor: PALETTE[i % PALETTE.length] + "22",
        borderWidth:2,
        pointRadius:3,
      }))
    },{
      plugins:{legend:{position:"bottom",labels:{font:{size:11}}}},
      scales:{r:{beginAtZero:true,max:1,ticks:{stepSize:0.25,font:{size:10}},grid:{color:"#1e2640"},angleLines:{color:"#1e2640"},pointLabels:{color:"#8892a4",font:{size:11}}}}
    });
  }

  // Stability chart
  newChart("chartStability","bar",{
    labels: models.map(shortName),
    datasets:[
      {label:"Success",data:summaries.map(m=>(m.derived||{}).success||0),backgroundColor:"#2ecc7188",borderColor:"#2ecc71",borderWidth:1},
      {label:"Error",data:summaries.map(m=>(m.derived||{}).error||0),backgroundColor:"#e74c3c88",borderColor:"#e74c3c",borderWidth:1},
      {label:"Timeout",data:summaries.map(m=>(m.derived||{}).timeout||0),backgroundColor:"#f1c40f88",borderColor:"#f1c40f",borderWidth:1},
    ]
  },{
    plugins:{legend:{position:"bottom",labels:{font:{size:11}}}},
    scales:{x:{stacked:true,grid:{color:"#1e2640"}},y:{stacked:true,beginAtZero:true,grid:{color:"#1e2640"}}}
  });

  // Summary table
  const table = document.getElementById("summaryTable");
  const tbody = table.querySelector("tbody");
  const tableRows = summaries.map((m, i) => {
    const d = m.derived || {};
    const sc = m.scoring || {};
    const rank = sc.rank || (i+1);
    const rise = (d.max_temp_before_c != null && d.max_temp_after_c != null) ? d.max_temp_after_c - d.max_temp_before_c : null;
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td class="mono">${rank}</td>
      <td><strong>${shortName(m.model)}</strong></td>
      <td class="mono">${m.size_mb || "—"}</td>
      <td class="mono">${fmt(d.avg_tokens_per_sec)}</td>
      <td class="mono">${d.p50_duration_ms != null ? fmtMs(d.p50_duration_ms) : "—"}</td>
      <td class="mono">${d.p50_duration_ms != null ? "—" : "—"}</td>
      <td class="mono">${d.success || 0}/${d.prompts || 20}</td>
      <td class="mono ${rise===null?'muted':rise>8?'text-bad':rise>3?'text-warn':'text-good'}">${rise !== null ? (rise>0?"+":"")+rise.toFixed(1)+"°C" : "—"}</td>
      <td>${scoreBar(sc.weighted_score)}</td>
      <td>${statusPill(m)}</td>
    `;
    const row = {
      rank,model:m.model,size_mb:m.size_mb||0,
      avg_tok:d.avg_tokens_per_sec||0,
      p50_dur:d.p50_duration_ms||0,
      p95_dur:0,
      success:d.success||0,
      temp_rise:rise,
      score:sc.weighted_score||0,
      status:"",
      _tr:tr
    };
    tbody.appendChild(tr);
    return row;
  });
  bindSort(table, tableRows);

  // Filter chip
  const chip = document.getElementById("filterChip");
  if (chip) chip.textContent = `${summaries.length} models · ${runs.length} runs`;
}

// ── MODELS PAGE ──────────────────────────────────────────
function initModelsPage(data) {
  const summaries = data.model_summaries || [];
  const shortName = n => n.replace(/-q4km$/,"");

  // p95 per model — compute from scores_by_device or use placeholder
  // We store p95 in the extended data; fall back to "—"
  const getP95 = (m) => m.derived?.p95_duration_ms || null;
  const getAvgWords = (m) => m.derived?.avg_output_words || null;
  const getRamDelta = (m) => m.derived?.ram_delta_mb || null;

  const models = summaries.map(m => m.model);

  newChart("chartTokSec","bar",{
    labels: models.map(shortName),
    datasets:[{
      label:"Avg tok/s",
      data: summaries.map(m => m.derived?.avg_tokens_per_sec || 0),
      backgroundColor: summaries.map((m,i) => modelColor(m.model,i) + "88"),
      borderColor: summaries.map((m,i) => modelColor(m.model,i)),
      borderWidth:1,
    }]
  },{plugins:{legend:{display:false}},scales:{y:{beginAtZero:true,grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}});

  // p50 vs p95 latency
  newChart("chartLatency","bar",{
    labels: models.map(shortName),
    datasets:[
      {label:"p50 (ms)",data:summaries.map(m=>m.derived?.p50_duration_ms||0),backgroundColor:"#4f8ef788",borderColor:"#4f8ef7",borderWidth:1},
      {label:"p95 (ms)",data:summaries.map(m=>m.derived?.p95_duration_ms||0),backgroundColor:"#e74c3c88",borderColor:"#e74c3c",borderWidth:1},
    ]
  },{
    plugins:{legend:{position:"bottom",labels:{font:{size:11}}}},
    scales:{y:{beginAtZero:true,grid:{color:"#1e2640"},type:"logarithmic"},x:{grid:{color:"#1e2640"}}}
  });

  newChart("chartSize","bar",{
    labels: models.map(shortName),
    datasets:[{
      label:"Size (MB)",
      data: summaries.map(m=>m.size_mb||0),
      backgroundColor: summaries.map(m => (m.size_mb||0)>1500 ? "#e74c3c88" : "#2ecc7188"),
      borderColor: summaries.map(m => (m.size_mb||0)>1500 ? "#e74c3c" : "#2ecc71"),
      borderWidth:1,
    }]
  },{
    plugins:{legend:{display:false},annotation:{annotations:{line1:{type:"line",yMin:1500,yMax:1500,borderColor:"#e74c3c",borderWidth:1,borderDash:[4,4],label:{content:"HC-1 limit",enabled:true}}}}},
    scales:{y:{beginAtZero:true,grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}
  });

  newChart("chartRamDelta","bar",{
    labels: models.map(shortName),
    datasets:[{
      label:"RAM delta (MB)",
      data: summaries.map(m => m.derived?.ram_delta_mb || null),
      backgroundColor: summaries.map(m => {
        const v = m.derived?.ram_delta_mb || 0;
        return v > 0 ? "#e74c3c88" : "#2ecc7188";
      }),
      borderColor: summaries.map(m => {
        const v = m.derived?.ram_delta_mb || 0;
        return v > 0 ? "#e74c3c" : "#2ecc71";
      }),
      borderWidth:1,
    }]
  },{plugins:{legend:{display:false}},scales:{y:{grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}});

  newChart("chartOutputLen","bar",{
    labels: models.map(shortName),
    datasets:[{
      label:"Avg output words",
      data: summaries.map(m => m.derived?.avg_output_words || 0),
      backgroundColor:"#9b59b688",
      borderColor:"#9b59b6",
      borderWidth:1,
    }]
  },{plugins:{legend:{display:false}},scales:{y:{beginAtZero:true,grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}});

  // Score components stacked
  newChart("chartScoreComponents","bar",{
    labels: summaries.map(m => shortName(m.model)),
    datasets:[
      {label:"Speed (25%)",      data:summaries.map(m=>m.scoring?.components.speed||0), backgroundColor:"#4f8ef788",borderColor:"#4f8ef7",borderWidth:1},
      {label:"Thermal (25%)",    data:summaries.map(m=>m.scoring?.components.thermal_efficiency||0), backgroundColor:"#2ecc7188",borderColor:"#2ecc71",borderWidth:1},
      {label:"Stability (20%)",  data:summaries.map(m=>(m.scoring?.components.stability||0)*0.8),backgroundColor:"#f1c40f88",borderColor:"#f1c40f",borderWidth:1},
      {label:"Output (20%)",     data:summaries.map(m=>(m.scoring?.components.output_success||0)*0.8),backgroundColor:"#e67e2288",borderColor:"#e67e22",borderWidth:1},
      {label:"Memory (10%)",     data:summaries.map(m=>(m.scoring?.components.memory_efficiency||0)*0.4),backgroundColor:"#9b59b688",borderColor:"#9b59b6",borderWidth:1},
    ]
  },{
    plugins:{legend:{position:"bottom",labels:{font:{size:11}}}},
    scales:{x:{stacked:true,grid:{color:"#1e2640"}},y:{stacked:true,beginAtZero:true,max:1.1,grid:{color:"#1e2640"}}}
  });

  // Table
  const table = document.getElementById("modelTable");
  const tbody = table.querySelector("tbody");
  const tableRows = summaries.map(m => {
    const d = m.derived || {};
    const sc = m.scoring || {};
    const rise = (d.max_temp_before_c != null && d.max_temp_after_c != null) ? d.max_temp_after_c - d.max_temp_before_c : null;
    const hc1 = (m.size_mb||0) > 1500 ? pill("FAIL","pill-fail") : pill("PASS","pill-pass");
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><strong>${shortName(m.model)}</strong></td>
      <td>${m.provider || "—"}</td>
      <td class="mono">${m.size_mb || "—"}</td>
      <td class="mono">${fmt(d.avg_tokens_per_sec)}</td>
      <td class="mono">${d.p50_duration_ms != null ? fmtMs(d.p50_duration_ms) : "—"}</td>
      <td class="mono">${d.p95_duration_ms != null ? fmtMs(d.p95_duration_ms) : "—"}</td>
      <td class="mono">${d.success||0}</td>
      <td class="mono ${(d.error||0)>0?'text-bad':''}">${d.error||0}</td>
      <td class="mono">${fmt(d.avg_output_words, 0)}</td>
      <td class="mono ${rise===null?'muted':rise>8?'text-bad':rise>3?'text-warn':'text-good'}">${rise !== null ? (rise>0?"+":"")+rise.toFixed(1) : "—"}</td>
      <td class="mono">${d.ram_delta_mb != null ? (d.ram_delta_mb>0?"+":"")+d.ram_delta_mb : "—"}</td>
      <td>${scoreBar(sc.weighted_score)}</td>
      <td>${hc1}</td>
    `;
    const row = {model:m.model,provider:m.provider||"",size_mb:m.size_mb||0,avg_tok:d.avg_tokens_per_sec||0,p50_dur:d.p50_duration_ms||0,p95_dur:d.p95_duration_ms||0,success:d.success||0,errors:d.error||0,out_words:d.avg_output_words||0,temp_rise:rise,ram_delta:d.ram_delta_mb,score:sc.weighted_score||0,hc1:"",_tr:tr};
    tbody.appendChild(tr);
    return row;
  });
  bindSort(table, tableRows);
}

// ── THERMALS PAGE ─────────────────────────────────────────
function initThermalsPage(data) {
  const summaries = data.model_summaries || [];
  const shortName = n => n.replace(/-q4km$/,"");

  const models = summaries.map(m => shortName(m.model));
  const before = summaries.map(m => m.derived?.max_temp_before_c || null);
  const after  = summaries.map(m => m.derived?.max_temp_after_c || null);
  const rise   = summaries.map(m => {
    const d = m.derived||{};
    return (d.max_temp_before_c!=null && d.max_temp_after_c!=null) ? d.max_temp_after_c - d.max_temp_before_c : null;
  });

  // Before/After grouped bar
  newChart("chartBeforeAfter","bar",{
    labels: models,
    datasets:[
      {label:"Before (°C)",data:before,backgroundColor:"#4f8ef788",borderColor:"#4f8ef7",borderWidth:1},
      {label:"After (°C)", data:after, backgroundColor:"#e74c3c88",borderColor:"#e74c3c",borderWidth:1},
    ]
  },{
    plugins:{legend:{position:"bottom",labels:{font:{size:11}}},tooltip:{callbacks:{label:ctx=>` ${ctx.raw?.toFixed(1) ?? "—"}°C`}}},
    scales:{y:{grid:{color:"#1e2640"},suggestedMin:25,suggestedMax:65},x:{grid:{color:"#1e2640"}}}
  });

  // Thermal rise bar
  newChart("chartThermalRise","bar",{
    labels: models,
    datasets:[{
      label:"Temp rise (°C)",
      data: rise,
      backgroundColor: rise.map(v=>v===null?"#8892a488":v>8?"#e74c3c88":v>3?"#f1c40f88":"#2ecc7188"),
      borderColor: rise.map(v=>v===null?"#8892a4":v>8?"#e74c3c":v>3?"#f1c40f":"#2ecc71"),
      borderWidth:1,
    }]
  },{
    plugins:{legend:{display:false},tooltip:{callbacks:{label:ctx=>ctx.raw!==null?(ctx.raw>0?"+":"")+ctx.raw.toFixed(1)+"°C":"—"}}},
    scales:{y:{grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}
  });

  // Warning count
  newChart("chartWarnCount","bar",{
    labels: models,
    datasets:[{
      label:"Thermal warnings",
      data: summaries.map(m=>m.derived?.thermal_warning_count||0),
      backgroundColor:"#f1c40f88",
      borderColor:"#f1c40f",
      borderWidth:1,
    }]
  },{plugins:{legend:{display:false}},scales:{y:{beginAtZero:true,max:22,grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}});

  // Thermal vs Speed scatter
  const scatter = summaries
    .filter(m => (m.derived||{}).avg_tokens_per_sec > 0 && rise[summaries.indexOf(m)] !== null)
    .map((m,_) => ({x: rise[summaries.indexOf(m)], y: m.derived.avg_tokens_per_sec, label: shortName(m.model)}));

  newChart("chartThermalVsSpeed","scatter",{
    datasets: scatter.map((pt,i) => ({
      label: pt.label,
      data: [{x:pt.x, y:pt.y}],
      backgroundColor: PALETTE[i%PALETTE.length]+"cc",
      pointRadius:10,
      pointHoverRadius:13,
    }))
  },{
    plugins:{
      legend:{position:"right",labels:{font:{size:11}}},
      tooltip:{callbacks:{label:ctx=>`${ctx.dataset.label}: +${ctx.raw.x.toFixed(1)}°C, ${ctx.raw.y.toFixed(1)} tok/s`}}
    },
    scales:{
      x:{title:{display:true,text:"Temp rise (°C)",color:"#8892a4"},grid:{color:"#1e2640"}},
      y:{title:{display:true,text:"Avg tok/s",color:"#8892a4"},grid:{color:"#1e2640"},beginAtZero:true}
    }
  });

  // Thermal table
  const table = document.getElementById("thermalTable");
  const tbody = table.querySelector("tbody");
  const tableRows = summaries.map((m,i) => {
    const d = m.derived||{};
    const r = rise[i];
    const bucket = d.thermal_after_bucket || "—";
    const hc6 = (d.max_temp_after_c||0) <= 60 ? pill("PASS","pill-pass") : pill("FAIL","pill-fail");
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><strong>${shortName(m.model)}</strong></td>
      <td class="mono">${d.max_temp_before_c != null ? d.max_temp_before_c.toFixed(1) : "—"}</td>
      <td class="mono ${bucket==="red"?"text-bad":bucket==="yellow"?"text-warn":"text-good"}">${d.max_temp_after_c != null ? d.max_temp_after_c.toFixed(1) : "—"}</td>
      <td class="mono ${r===null?"muted":r>8?"text-bad":r>3?"text-warn":"text-good'}">${r!==null?(r>0?"+":"")+r.toFixed(1)+"°C":"—"}</td>
      <td class="mono">${d.thermal_warning_count ?? "—"} / 20</td>
      <td><span class="badge ${bucket==="red"?"badge-red":bucket==="yellow"?"badge-yellow":"badge-green"}">${bucket}</span></td>
      <td>${hc6}</td>
    `;
    const row = {model:m.model,before:d.max_temp_before_c,after:d.max_temp_after_c,rise:r,warnings:d.thermal_warning_count,bucket,hc6:"",_tr:tr};
    tbody.appendChild(tr);
    return row;
  });
  bindSort(table, tableRows);

  // Zone details
  const zoneDiv = document.getElementById("thermalZoneTable");
  if (zoneDiv) {
    // Pull zone data from latest run snapshot_after for top model
    const topModel = data.model_summaries?.find(m => m.model === "qwen2.5-0.5b-q4km");
    const zones = topModel?.snapshot_after?.thermal?.zones || [];
    if (zones.length > 0) {
      let html = `<table><thead><tr><th>Zone Type</th><th>Temp (°C)</th></tr></thead><tbody>`;
      zones.forEach(z => {
        html += `<tr><td class="mono">${z.type||z.zone||"zone"}</td><td class="mono">${z.temp_c != null ? z.temp_c.toFixed(1) : "—"}</td></tr>`;
      });
      html += "</tbody></table>";
      zoneDiv.innerHTML = html;
    } else {
      zoneDiv.innerHTML = `<p class="muted" style="font-size:13px">Zone detail data not available in current export.</p>`;
    }
  }
}

// ── PROMPTS PAGE ──────────────────────────────────────────
function initPromptsPage(data) {
  const summaries = data.model_summaries || [];
  const shortName = n => n.replace(/-q4km$/,"");

  // Populate model filter
  const modelSel = document.getElementById("modelFilter");
  const passingModels = summaries.filter(m => (m.derived||{}).success > 0);
  passingModels.forEach(m => {
    const o = document.createElement("option");
    o.value = m.model; o.textContent = shortName(m.model);
    modelSel.appendChild(o);
  });

  function getPromptData(modelName) {
    const m = summaries.find(s => s.model === modelName);
    return m?.derived?.prompt_results || [];
  }

  function renderPromptCharts() {
    const modelName = modelSel.value;
    const promptData = getPromptData(modelName);
    const chip = document.getElementById("promptChip");
    if (chip) chip.textContent = promptData.length > 0 ? `${promptData.length} prompts` : "No per-prompt data";

    if (promptData.length === 0) return;

    const ids = promptData.map(r => r.prompt_id);
    const durs = promptData.map(r => r.duration_ms || 0);
    const toks = promptData.map(r => r.tokens_per_sec || 0);
    const outw = promptData.map(r => r.out_words || 0);
    const twarn = promptData.map(r => r.thermal_warning ? 1 : 0);

    newChart("chartPromptDuration","bar",{
      labels:ids,
      datasets:[{
        label:"Duration (ms)",
        data:durs,
        backgroundColor: durs.map(d=>d>60000?"#e74c3c88":d>20000?"#f1c40f88":"#4f8ef788"),
        borderColor: durs.map(d=>d>60000?"#e74c3c":d>20000?"#f1c40f":"#4f8ef7"),
        borderWidth:1,
      }]
    },{
      plugins:{legend:{display:false},tooltip:{callbacks:{label:ctx=>` ${fmtMs(ctx.raw)}`}}},
      scales:{y:{beginAtZero:true,grid:{color:"#1e2640"},ticks:{callback:v=>fmtMs(v)}},x:{grid:{color:"#1e2640"}}}
    });

    newChart("chartPromptTokSec","bar",{
      labels:ids,
      datasets:[{
        label:"Tok/s",data:toks,
        backgroundColor:"#2ecc7188",borderColor:"#2ecc71",borderWidth:1,
      }]
    },{plugins:{legend:{display:false}},scales:{y:{beginAtZero:true,grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}});

    newChart("chartPromptOutLen","bar",{
      labels:ids,
      datasets:[{
        label:"Output words",data:outw,
        backgroundColor:"#9b59b688",borderColor:"#9b59b6",borderWidth:1,
      }]
    },{plugins:{legend:{display:false}},scales:{y:{beginAtZero:true,grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"}}}});

    // Table
    const tbody = document.querySelector("#promptTable tbody");
    tbody.innerHTML = "";
    promptData.forEach(r => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td class="mono">${r.prompt_id}</td>
        <td>${r.status === "ok" ? pill("ok","pill-pass") : pill(r.status,"pill-fail")}</td>
        <td class="mono">${fmtMs(r.duration_ms)}</td>
        <td class="mono">${r.tokens_per_sec > 0 ? r.tokens_per_sec.toFixed(1) : "—"}</td>
        <td class="mono">${r.out_words || 0}</td>
        <td>${r.thermal_warning ? '<span class="text-warn">⚠ yes</span>' : '<span class="muted">no</span>'}</td>
      `;
      tbody.appendChild(tr);
    });
  }

  // All-model variance chart (using summary p50 data)
  const P_IDS = Array.from({length:20},(_,i)=>"P"+String(i+1).padStart(2,"0"));
  newChart("chartVariance","bar",{
    labels: P_IDS,
    datasets: passingModels.map((m,i) => {
      const prs = m.derived?.prompt_results || [];
      return {
        label: shortName(m.model),
        data: P_IDS.map(pid => {
          const r = prs.find(p => p.prompt_id === pid);
          return r ? r.duration_ms : null;
        }),
        backgroundColor: PALETTE[i % PALETTE.length] + "88",
        borderColor: PALETTE[i % PALETTE.length],
        borderWidth:1,
      };
    })
  },{
    plugins:{legend:{position:"bottom",labels:{font:{size:11}}},tooltip:{callbacks:{label:ctx=>ctx.raw!=null?` ${fmtMs(ctx.raw)}`:" —"}}},
    scales:{y:{beginAtZero:true,grid:{color:"#1e2640"},type:"logarithmic",ticks:{callback:v=>fmtMs(v)}},x:{grid:{color:"#1e2640"}}}
  });

  modelSel.addEventListener("change", renderPromptCharts);
  if (passingModels.length > 0) renderPromptCharts();
}

// ── DEVICES PAGE ──────────────────────────────────────────
function initDevicesPage(data) {
  const runs = data.runs || [];
  const summaries = data.model_summaries || [];

  // Build device profiles from first run snapshot
  const deviceProfiles = {};
  runs.forEach(run => {
    if (!deviceProfiles[run.device] && run.snapshot_before) {
      const dev = run.snapshot_before.device || {};
      const mem = run.snapshot_before.memory || {};
      deviceProfiles[run.device] = {
        model_name: dev.model || "Unknown",
        manufacturer: dev.manufacturer || "Unknown",
        android_version: dev.android_version || dev.release || "Unknown",
        sdk: dev.sdk_version || dev.sdk || "Unknown",
        cores: dev.cpu_cores || "Unknown",
        total_ram_mb: mem.total_mb || "Unknown",
        board: dev.board || "Unknown",
      };
    }
  });

  const container = document.getElementById("deviceCards");
  if (container) {
    const grid = document.createElement("div");
    grid.className = "device-card-grid";
    Object.entries(deviceProfiles).forEach(([device, info]) => {
      const total_runs = runs.filter(r => r.device === device).length;
      const models_tested = [...new Set(runs.filter(r => r.device === device).map(r => r.model))].length;
      grid.insertAdjacentHTML("beforeend", `
        <div class="device-card">
          <h3>${device}</h3>
          <div class="spec-list">
            <span class="spec-key">Model</span><span class="spec-val">${info.model_name}</span>
            <span class="spec-key">Manufacturer</span><span class="spec-val">${info.manufacturer}</span>
            <span class="spec-key">Android</span><span class="spec-val">${info.android_version} (SDK ${info.sdk})</span>
            <span class="spec-key">CPU Cores</span><span class="spec-val">${info.cores}</span>
            <span class="spec-key">Total RAM</span><span class="spec-val">${info.total_ram_mb ? Math.round(info.total_ram_mb/1024)+"GB approx" : "—"}</span>
            <span class="spec-key">Board/SoC</span><span class="spec-val">${info.board}</span>
            <span class="spec-key">Runs</span><span class="spec-val">${total_runs} runs, ${models_tested} models</span>
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
      const top = models[0];
      if (!top) return;
      const d = top.derived || {};
      const rise = (d.max_temp_before_c!=null && d.max_temp_after_c!=null) ? d.max_temp_after_c - d.max_temp_before_c : null;
      const deviceRuns = runs.filter(r => r.device === device).length;
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${device}</td>
        <td><strong>${top.model?.replace(/-q4km$/,"")}</strong></td>
        <td>${scoreBar(top.scoring?.weighted_score)}</td>
        <td class="mono">${(d.avg_tokens_per_sec||0).toFixed(1)}</td>
        <td class="mono ${rise===null?"muted":rise>8?"text-bad":rise>3?"text-warn":"text-good'}">${rise!==null?(rise>0?"+":"")+rise.toFixed(1)+"°C":"—"}</td>
        <td class="mono">${deviceRuns}</td>
      `;
      tbody.appendChild(tr);
    });
  }

  // Run matrix bar chart
  const deviceModels = {};
  runs.forEach(r => {
    if (!deviceModels[r.device]) deviceModels[r.device] = {};
    deviceModels[r.device][r.model] = (deviceModels[r.device][r.model]||0)+1;
  });
  const allModels = [...new Set(runs.map(r=>r.model))].sort().map(n=>n.replace(/-q4km$/,""));
  const devices = Object.keys(deviceModels);

  newChart("chartRunMatrix","bar",{
    labels: devices,
    datasets: allModels.map((m,i) => ({
      label:m,
      data: devices.map(d => {
        const fullName = Object.keys(deviceModels[d]||{}).find(k=>k.includes(m.split("-")[0]))||null;
        return fullName ? deviceModels[d][fullName] : 0;
      }),
      backgroundColor: PALETTE[i%PALETTE.length]+"88",
      borderColor: PALETTE[i%PALETTE.length],
      borderWidth:1,
    }))
  },{
    plugins:{legend:{position:"bottom",labels:{font:{size:11}}}},
    scales:{x:{stacked:true,grid:{color:"#1e2640"}},y:{stacked:true,beginAtZero:true,grid:{color:"#1e2640"}}}
  });
}

// ── HISTORICAL PAGE ───────────────────────────────────────
function initHistoricalPage(data) {
  const runs = data.runs || [];
  const shortName = n => n.replace(/-q4km$/,"");

  // Populate model filter
  const modelSel = document.getElementById("modelFilter");
  const metricSel = document.getElementById("metricFilter");
  ["All", ...new Set(runs.map(r=>r.model))].sort().forEach(v => {
    const o = document.createElement("option"); o.value = o.textContent = v === "All" ? "All" : shortName(v);
    o.value = v;
    modelSel.appendChild(o);
  });

  const metricFns = {
    avg_tok:   r => r.derived?.avg_tokens_per_sec || null,
    p50_dur:   r => r.derived?.p50_duration_ms || null,
    temp_after:r => r.derived?.max_temp_after_c || null,
    success:   r => r.derived?.success || null,
  };

  function renderTrend() {
    const modelFilter = modelSel.value;
    const metric = metricSel.value;
    const getter = metricFns[metric] || metricFns.avg_tok;

    const filtered = runs
      .filter(r => modelFilter === "All" || r.model === modelFilter)
      .sort((a,b) => String(a.timestamp).localeCompare(String(b.timestamp)));

    // Group by model
    const byModel = {};
    filtered.forEach(r => {
      if (!byModel[r.model]) byModel[r.model] = [];
      byModel[r.model].push(r);
    });

    // Build labels = all timestamps in order
    const allTs = [...new Set(filtered.map(r=>r.timestamp))].sort();

    newChart("chartTrend","line",{
      labels: allTs,
      datasets: Object.entries(byModel).map(([model,rs],i) => ({
        label: shortName(model),
        data: allTs.map(ts => {
          const run = rs.find(r=>r.timestamp===ts);
          return run ? getter(run) : null;
        }),
        borderColor: PALETTE[i%PALETTE.length],
        backgroundColor: PALETTE[i%PALETTE.length]+"22",
        tension:0.2,
        pointRadius:4,
        spanGaps:false,
      }))
    },{
      plugins:{legend:{position:"bottom",labels:{font:{size:11}}}},
      scales:{y:{grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"},ticks:{maxRotation:45}}}
    });
  }

  // tok/s history
  const byModel = {};
  runs.forEach(r => {
    if (!byModel[r.model]) byModel[r.model] = [];
    byModel[r.model].push(r);
  });

  Object.entries(byModel).forEach(([model,rs]) => rs.sort((a,b)=>String(a.timestamp).localeCompare(String(b.timestamp))));

  const allTs = [...new Set(runs.map(r=>r.timestamp))].sort();

  newChart("chartTokHistory","line",{
    labels: allTs,
    datasets: Object.entries(byModel).map(([model,rs],i)=>({
      label:shortName(model),
      data:allTs.map(ts=>{const r=rs.find(r=>r.timestamp===ts);return r?r.derived?.avg_tokens_per_sec||null:null;}),
      borderColor:PALETTE[i%PALETTE.length],backgroundColor:PALETTE[i%PALETTE.length]+"22",
      tension:0.2,pointRadius:4,spanGaps:false,
    }))
  },{
    plugins:{legend:{position:"bottom",labels:{font:{size:11}}}},
    scales:{y:{beginAtZero:true,grid:{color:"#1e2640"}},x:{grid:{color:"#1e2640"},ticks:{maxRotation:45}}}
  });

  newChart("chartThermalHistory","line",{
    labels: allTs,
    datasets: Object.entries(byModel).map(([model,rs],i)=>({
      label:shortName(model),
      data:allTs.map(ts=>{const r=rs.find(r=>r.timestamp===ts);return r?r.derived?.max_temp_after_c||null:null;}),
      borderColor:PALETTE[i%PALETTE.length],backgroundColor:PALETTE[i%PALETTE.length]+"22",
      tension:0.2,pointRadius:4,spanGaps:false,
    }))
  },{
    plugins:{legend:{position:"bottom",labels:{font:{size:11}}}},
    scales:{y:{grid:{color:"#1e2640"},suggestedMin:25},x:{grid:{color:"#1e2640"},ticks:{maxRotation:45}}}
  });

  // History table
  const table = document.getElementById("historyTable");
  const tbody = table.querySelector("tbody");
  const tableRows = runs.map(r => {
    const d = r.derived||{};
    const sc = r.scoring;
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td class="mono">${r.timestamp}</td>
      <td>${r.device}</td>
      <td>${shortName(r.model)}</td>
      <td class="mono">${fmt(d.avg_tokens_per_sec)}</td>
      <td class="mono">${d.p50_duration_ms!=null?fmtMs(d.p50_duration_ms):"—"}</td>
      <td class="mono">${d.success||0}</td>
      <td class="mono ${(d.error||0)>0?"text-bad":""}">${d.error||0}</td>
      <td class="mono">${d.max_temp_after_c!=null?d.max_temp_after_c.toFixed(1)+"°C":"—"}</td>
      <td>${scoreBar(sc?.weighted_score)}</td>
    `;
    const row = {timestamp:r.timestamp,device:r.device,model:r.model,avg_tok:d.avg_tokens_per_sec||0,p50_dur:d.p50_duration_ms||0,success:d.success||0,errors:d.error||0,temp_after:d.max_temp_after_c||0,score:sc?.weighted_score||0,_tr:tr};
    tbody.appendChild(tr);
    return row;
  });
  bindSort(table, tableRows);

  // Regression detection
  const regressionDiv = document.getElementById("regressionList");
  if (regressionDiv) {
    const regressions = [];
    Object.entries(byModel).forEach(([model,rs]) => {
      if (rs.length < 2) return;
      for (let i=1; i<rs.length; i++) {
        const prev = rs[i-1].derived?.avg_tokens_per_sec;
        const curr = rs[i].derived?.avg_tokens_per_sec;
        if (prev && curr && (prev - curr) / prev > 0.10) {
          regressions.push({model, from:rs[i-1].timestamp, to:rs[i].timestamp, prev, curr});
        }
      }
    });
    if (regressions.length === 0) {
      regressionDiv.innerHTML = `<div class="badge badge-green">✓ No regressions detected across ${runs.length} runs</div>`;
    } else {
      regressionDiv.innerHTML = regressions.map(r =>
        `<div class="callout-warn" style="margin-bottom:8px;padding:10px;border-radius:8px">⚠ ${shortName(r.model)}: tok/s dropped from ${r.prev.toFixed(1)} → ${r.curr.toFixed(1)} (${((r.prev-r.curr)/r.prev*100).toFixed(0)}% decline) between ${r.from} and ${r.to}</div>`
      ).join("");
    }
  }

  modelSel.addEventListener("change", renderTrend);
  metricSel.addEventListener("change", renderTrend);
  renderTrend();
}
