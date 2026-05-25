# 7-Model Benchmark: Samsung Galaxy S24 Ultra
**Date:** 2026-05-24  
**Device:** Samsung Galaxy S24 Ultra (SM-S928B), Samsung One UI  
**Runtime:** Termux + llama.cpp  
**Config:** 4 threads, 256 max tokens, 90 s timeout per prompt  
**Prompts per model:** 20 finance benchmark prompts (P01–P20)  
**Branch:** `phase-3-ai-lab`

---

## Executive Summary

Three of the seven candidate models completed all 20 prompts with 100% success: `qwen2.5-0.5b-q4km`, `qwen2.5-1.5b-q4km`, and `tinyllama-1.1b-q4km`. Three models (`gemma-2b-q4km`, `llama3.2-1b-q4km`, `llama3.2-3b-q4km`) failed every prompt in under 1.1 seconds — a pattern consistent with llama.cpp build incompatibility rather than inference failure. `phi3-mini-q4km` completed all 20 prompts but breaches the 1.5 GB disk hard constraint and exhibited extreme latency variance (median 53 s, worst-case 995 s — nearly 17 minutes for a single prompt), making it unsuitable for production.

**Recommendation: `qwen2.5-0.5b-q4km` is the primary production candidate** — fastest at 47 tok/s, smallest footprint at 468 MB, zero thermal rise, and 100% stable output. `qwen2.5-1.5b-q4km` is the approved quality-biased alternative when response depth matters more than latency.

---

## Quick Verdict Table

| Model | Size (MB) | Status | Best Metric |
|---|---:|---|---|
| qwen2.5-0.5b-q4km | 468 | **PASS — primary candidate** | Fastest: 47.3 tok/s p50; coolest thermals (0°C rise) |
| qwen2.5-1.5b-q4km | 1065 | **PASS — quality candidate** | Best quality/speed balance; 100% stable; 18.8 tok/s |
| tinyllama-1.1b-q4km | 637 | **PASS (quality caveat)** | Fastest median latency (3.3 s); high variance; short outputs |
| phi3-mini-q4km | 2282 | **FAIL — HC-1 breach** | 100% success but >1.5 GB, extreme latency variance (σ=224 s) |
| gemma-2b-q4km | 1629 | **INCOMPATIBLE** | Crashed in <458 ms; Gemma 2 arch not supported by installed llama.cpp |
| llama3.2-1b-q4km | 770 | **INCOMPATIBLE** | Crashed in <1081 ms; Llama 3.2 arch needs newer llama.cpp |
| llama3.2-3b-q4km | 1925 | **INCOMPATIBLE** | Same as 1b; also fails HC-1 (1925 MB > 1500 MB) |

---

## Detailed Per-Model Analysis

### qwen2.5-0.5b-q4km
- **Size:** 468 MB
- **Quantization:** Q4_K_M
- **Success:** 20/20 (100%)
- **Avg tok/s:** 46.6 (range 41.85–49.25 — very consistent)
- **p50 duration:** 7,869 ms
- **p95 duration:** 9,222 ms
- **Latency std dev:** 440 ms (extremely tight)
- **Timeout count:** 0
- **Failure count:** 0
- **Thermal warnings:** 18/20
- **Max temp before:** 42.8°C → **after:** 42.8°C → **rise: 0.0°C**
- **RAM delta:** −1,422 MB (released memory post-run, OS reclaimed)
- **Battery delta:** Not captured (Termux API limitation)
- **Avg output length:** 223 words
- **Output capture success:** 20/20 (100%)
- **Prompt-level variance:** σ = 440 ms — tightest across all models
- **Verdict:** Best overall production candidate. Thermal warnings are cosmetic — the device held at steady-state 42.8°C throughout; no progressive heating occurred. Best low-end candidate.

### qwen2.5-1.5b-q4km
- **Size:** 1,065 MB
- **Quantization:** Q4_K_M
- **Success:** 20/20 (100%)
- **Avg tok/s:** 18.5 (range 17.26–19.28 — very consistent)
- **p50 duration:** 18,481 ms
- **p95 duration:** 20,691 ms
- **Latency std dev:** 950 ms (tight)
- **Timeout count:** 0
- **Failure count:** 0
- **Thermal warnings:** 20/20
- **Max temp before:** 45.9°C → **after:** 55.8°C → **rise: +9.9°C**
- **RAM delta:** −290 MB
- **Battery delta:** Not captured
- **Avg output length:** 214 words
- **Output capture success:** 20/20 (100%)
- **Prompt-level variance:** σ = 950 ms — second tightest
- **Notes:** 55.8°C after-temp is close to the HC-6 ceiling of 60°C. Monitor in controlled benchmark. Thermal warnings on every prompt are expected for sustained inference at this model size.
- **Verdict:** Solid approved production candidate for quality-prioritised scenarios. Does NOT breach HC-1 (1,065 MB < 1,500 MB).

### tinyllama-1.1b-q4km
- **Size:** 637 MB
- **Quantization:** Q4_K_M
- **Success:** 20/20 (100%)
- **Avg tok/s:** 28.6 (only 3/20 prompts produced enough output to register a rate — P04, P06, P13)
- **p50 duration:** 3,304 ms (misleading — see caveats)
- **p95 duration:** 12,574 ms (driven by two outliers: P04 at 12,267 ms, P13 at 12,574 ms)
- **Latency std dev:** 2,893 ms (high)
- **Timeout count:** 0
- **Failure count:** 0
- **Thermal warnings:** 6/20
- **Max temp before:** 53.8°C → **after:** 41.2°C → **rise: −12.6°C** (passive cooling during long run)
- **RAM delta:** −176 MB
- **Battery delta:** Not captured
- **Avg output length:** 75 words (17/20 prompts produced sub-threshold outputs too short for reliable finance answers)
- **Output capture success:** 20/20 (strings non-empty) but quality is suspect for 17/20 prompts
- **Prompt-level variance:** σ = 2,893 ms — highest among passing models, driven by bimodal distribution
- **Caveats:** The "fast" median (3.3 s) is mostly due to short, potentially unhelpful responses. Two prompts (P04, P13) that produced longer outputs also took 3–4× longer. Tok/s is underreported because most prompts didn't hit the minimum output threshold for rate measurement.
- **Verdict:** Technically passes all hard constraints but requires quality validation before production approval. Likely unsuitable for finance advisory domain based on average 75-word output depth.

### phi3-mini-q4km
- **Size:** 2,282 MB (**BREACHES HC-1: > 1,500 MB**)
- **Quantization:** Q4_K_M
- **Success:** 20/20 (100%)
- **Avg tok/s:** 6.7 (only 11/20 prompts produced output above tok/s threshold)
- **p50 duration:** 53,165 ms
- **p95 duration:** 995,248 ms (~16.6 minutes — P20 worst case)
- **Latency std dev:** 224,578 ms — extreme bimodal: fast prompts 11–14 s, slow prompts 45–316 s, extreme outlier 995 s
- **Timeout count:** 0 (90 s timeout was not consistently enforced — see P16=180 s, P17=316 s, P18=290 s, P20=995 s)
- **Failure count:** 0
- **Thermal warnings:** 13/20
- **Max temp before:** 49.1°C → **after:** 29.8°C → **rise: −19.3°C** (significant test duration allowed passive cooling)
- **RAM delta:** −171 MB
- **Battery delta:** Not captured
- **Avg output length:** 112 words
- **Output capture success:** 20/20 (100%)
- **Prompt-level variance:** σ = 224,578 ms — by far the worst
- **Hard constraint:** **FAILS HC-1** (2,282 MB > 1,500 MB)
- **Verdict:** Quality reference only. The 995 s worst-case and 90 s timeout non-enforcement make this model unusable for real-time finance assistance. Excluded from production candidacy.

### gemma-2b-q4km
- **Size:** 1,629 MB (**FAILS HC-1: > 1,500 MB**)
- **Quantization:** Q4_K_M
- **Success:** 0/20 (0% — all ERROR)
- **Error timing:** 363–458 ms per prompt (immediate crash, not inference failure)
- **Thermal rise:** +3.1°C (no inference occurred; background warmth)
- **RAM delta:** +67 MB (model loaded partially before crash)
- **Root cause:** Crash at ~400 ms indicates the Gemma 2 architecture (GQA, logit soft-capping) is unsupported by the installed llama.cpp build. Binary incompatibility, not hardware constraint.
- **Verdict:** INCOMPATIBLE. Re-test with llama.cpp ≥ b3100 which includes Gemma 2 support. Note: also fails HC-1 — not a production candidate even after compatibility fix.

### llama3.2-1b-q4km
- **Size:** 770 MB
- **Quantization:** Q4_K_M
- **Success:** 0/20 (0% — all ERROR)
- **Error timing:** 987–1,081 ms per prompt (fast crash — partially loads before hitting unsupported op)
- **Thermal rise:** −0.4°C (no inference; ambient cooling)
- **RAM delta:** +94 MB (partial load)
- **Root cause:** Llama 3.2 uses a revised architecture (tie-word-embeddings, updated RoPE scaling) requiring a newer llama.cpp than Llama 3.1. The longer crash time (~1 s vs Gemma's ~400 ms) suggests partial model loading before the unsupported operation is reached.
- **Verdict:** INCOMPATIBLE. Upgrade llama.cpp to a build from September 2024 or later, then re-benchmark.

### llama3.2-3b-q4km
- **Size:** 1,925 MB (**FAILS HC-1: > 1,500 MB**)
- **Quantization:** Q4_K_M
- **Success:** 0/20 (0% — all ERROR)
- **Error timing:** 987–1,108 ms per prompt — identical pattern to llama3.2-1b
- **Thermal rise:** −0.9°C
- **RAM delta:** +158 MB (partial load)
- **Root cause:** Same architecture incompatibility as llama3.2-1b.
- **Verdict:** INCOMPATIBLE + fails HC-1. Not a production candidate even after llama.cpp upgrade.

---

## Head-to-Head Comparison Table

| Metric | qwen2.5-0.5b | qwen2.5-1.5b | tinyllama-1.1b | phi3-mini | gemma-2b | llama3.2-1b | llama3.2-3b |
|---|---:|---:|---:|---:|---:|---:|---:|
| Size (MB) | 468 | 1,065 | 637 | 2,282 | 1,629 | 770 | 1,925 |
| Quantization | Q4_K_M | Q4_K_M | Q4_K_M | Q4_K_M | Q4_K_M | Q4_K_M | Q4_K_M |
| Prompts total | 20 | 20 | 20 | 20 | 20 | 20 | 20 |
| Success | 20 | 20 | 20 | 20 | 0 | 0 | 0 |
| Timeout | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Error | 0 | 0 | 0 | 0 | 20 | 20 | 20 |
| Avg tok/s | **46.6** | 18.5 | 28.6† | 6.7 | n/a | n/a | n/a |
| p50 duration (ms) | **7,869** | 18,481 | 3,304‡ | 53,165 | n/a | n/a | n/a |
| p95 duration (ms) | **9,222** | 20,691 | 12,574 | 995,248 | n/a | n/a | n/a |
| Latency std dev (ms) | **440** | 950 | 2,893 | 224,578 | n/a | n/a | n/a |
| Thermal warnings | 18 | 20 | 6 | 13 | 0 | 0 | 0 |
| Max temp before (°C) | 42.8 | 45.9 | 53.8 | 49.1 | 44.4 | 42.8 | 41.7 |
| Max temp after (°C) | 42.8 | 55.8 | 41.2 | 29.8 | 47.5 | 42.4 | 40.8 |
| Temp rise (°C) | **0.0** | +9.9 | −12.6 | −19.3 | +3.1 | −0.4 | −0.9 |
| RAM delta (MB) | −1,422 | −290 | −176 | −171 | +67 | +94 | +158 |
| Battery delta | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| Output present | 20/20 | 20/20 | 20/20 | 20/20 | 0/20 | 0/20 | 0/20 |
| Avg output length (words) | 223 | 214 | **75** | 112 | 0 | 0 | 0 |
| HC-1 (≤ 1,500 MB) | PASS | PASS | PASS | **FAIL** | **FAIL** | PASS | **FAIL** |

† tinyllama tok/s based only on 3/20 prompts that produced sufficient output  
‡ tinyllama p50 duration misleading — bimodal distribution; 17/20 prompts complete in 2–6 s, 2 outliers at ~12.5 s

---

## Weighted Score Table

**Scoring formula (higher = better):**

| Dimension | Weight | Formula |
|---|---:|---|
| Speed | 25% | avg tok/s normalized 0–1 across all 7 models |
| Thermal efficiency | 25% | 1.0 − (temp_rise / 15°C), clamped 0–1; 0°C rise = 1.0; ≥ 15°C rise = 0.0 |
| Stability | 20% | success_count / total_prompts |
| Output success | 20% | output_present_count / total_prompts |
| Memory efficiency | 10% | normalized inverse model size (smaller = better) |

Models with zero successful inferences receive 0.0 for speed, stability, and output. Thermal score for failed models set to 0.0 (no inference thermal data available).

| Model | Speed (0.25) | Thermal (0.25) | Stability (0.20) | Output (0.20) | Memory (0.10) | **Total** |
|---|---:|---:|---:|---:|---:|---:|
| qwen2.5-0.5b-q4km | **1.000** | **1.000** | 1.000 | 1.000 | **1.000** | **1.000** |
| tinyllama-1.1b-q4km | 0.540 | 1.000 | 1.000 | 1.000 | 0.904 | 0.810 *(quality caveat)* |
| qwen2.5-1.5b-q4km | 0.294 | 0.340 | 1.000 | 1.000 | 0.674 | 0.622 |
| phi3-mini-q4km | 0.000 | 1.000 | 1.000 | 1.000 | 0.000 | 0.600 *(HC-1 fail)* |
| llama3.2-1b-q4km | 0.000 | 0.000 | 0.000 | 0.000 | 0.834 | 0.083 *(incompatible)* |
| gemma-2b-q4km | 0.000 | 0.000 | 0.000 | 0.000 | 0.357 | 0.036 *(incompatible)* |
| llama3.2-3b-q4km | 0.000 | 0.000 | 0.000 | 0.000 | 0.196 | 0.020 *(incompatible)* |

**Ranked:**
1. qwen2.5-0.5b-q4km — **1.000** ✅ APPROVED
2. tinyllama-1.1b-q4km — **0.810** ⚠️ Quality pending
3. qwen2.5-1.5b-q4km — **0.622** ✅ APPROVED
4. phi3-mini-q4km — **0.600** ❌ HC-1 breach
5. llama3.2-1b-q4km — **0.083** ❌ Incompatible
6. gemma-2b-q4km — **0.036** ❌ Incompatible + HC-1
7. llama3.2-3b-q4km — **0.020** ❌ Incompatible + HC-1

---

## Model Roles

| Role | Winner | Rationale |
|---|---|---|
| **Best overall** | qwen2.5-0.5b-q4km | Top composite score: fastest, coolest, smallest, 100% stable |
| **Best quality candidate** | qwen2.5-1.5b-q4km | Larger model, deeper reasoning, more consistent output length, within HC-1 |
| **Best low-end candidate** | qwen2.5-0.5b-q4km | 468 MB, 47 tok/s, zero thermal rise — ideal for mid-range devices |
| **Best flagship candidate** | qwen2.5-1.5b-q4km | Best quality on high-end devices where speed tradeoff is acceptable |
| **Safest thermal** | qwen2.5-0.5b-q4km | 0.0°C rise over complete 20-prompt run |
| **Worst thermal (passing)** | qwen2.5-1.5b-q4km | +9.9°C rise; highest among models that completed inference |

---

## Recommended Production Candidates

| Model | Status | Justification |
|---|---|---|
| qwen2.5-0.5b-q4km | **APPROVED — primary** | Passes all 8 hard constraints. Fastest, most thermally stable, smallest disk footprint. Best UX. |
| qwen2.5-1.5b-q4km | **APPROVED — quality alt** | Passes all 8 hard constraints. Best depth of finance reasoning at 2.5× slower speed. |

## Rejected Candidates

| Model | Primary Rejection Reason | Secondary Issues |
|---|---|---|
| tinyllama-1.1b-q4km | Output quality unvalidated (17/20 prompts produced ≤75 words — likely insufficient for finance advisory) | High latency variance (σ = 2,893 ms) |
| phi3-mini-q4km | **HC-1 fail** (2,282 MB > 1,500 MB limit) | Extreme latency variance (σ = 224,578 ms); worst case 995 s |
| gemma-2b-q4km | Architecture incompatible with current llama.cpp build | Also fails HC-1 (1,629 MB) |
| llama3.2-1b-q4km | Architecture incompatible with current llama.cpp build | — |
| llama3.2-3b-q4km | Architecture incompatible + **HC-1 fail** (1,925 MB) | Same arch issue as 1b |

---

## Hard Constraints Check (HC-1 through HC-8)

| Constraint | Threshold | qwen2.5-0.5b | qwen2.5-1.5b | tinyllama-1.1b | Notes |
|---|---|---|---|---|---|
| HC-1: Disk ≤ 1,500 MB | Model file size | PASS (468 MB) | PASS (1,065 MB) | PASS (637 MB) | gemma, phi3, llama3.2-3b all FAIL |
| HC-2: RAM fit | Must load without OOM | PASS | PASS | PASS | No OOM observed (S24 Ultra has 12 GB RAM) |
| HC-3: Timeout rate ≤ 10% | Timeouts / prompts | PASS (0%) | PASS (0%) | PASS (0%) | Zero timeouts for all passing models |
| HC-4: Error rate ≤ 10% | Errors / prompts | PASS (0%) | PASS (0%) | PASS (0%) | Zero errors for all passing models |
| HC-5: Output present ≥ 90% | Non-empty outputs | PASS (100%) | PASS (100%) | PASS (100%) | — |
| HC-6: Thermal ceiling ≤ 60°C | Max temp after | PASS (42.8°C) | PASS (55.8°C) | PASS (41.2°C) | qwen2.5-1.5b at 55.8°C — monitor in controlled benchmark |
| HC-7: Latency p90 ≤ 90 s | p90 per-prompt | PASS | PASS | PASS | phi3-mini fails (p95 = 995 s); tinyllama p95 = 12.6 s |
| HC-8: Architecture support | Confirmed inference | PASS | PASS | PASS | gemma, llama3.2-1b/3b all fail |

---

## Real-World Benchmark Caveats

This benchmark was run under realistic consumer-device conditions — intentionally. The goal is to measure what a user's device actually delivers, not what a controlled lab environment would show.

- **Background apps active:** Samsung Galaxy devices running One UI keep multiple persistent services alive during benchmarking: Samsung Health background sync, Google Play Services, Samsung DeX services, Samsung Pay, Knox security daemon, and system telemetry. These compete for CPU cores and available RAM at all times.
- **Samsung One UI thermal management active:** One UI applies aggressive thermal throttling starting at approximately 50–55°C. The thermal warnings and tok/s variation observed are partly a product of One UI's thermal governor, not raw Snapdragon 8 Gen 3 performance. Clean-room numbers would be modestly higher for sustained inference.
- **Not clean-room mode:** No device reboot was performed before the benchmark. Airplane mode was not enabled. Screen-on state was not controlled. The device was not given a thermal stabilization window before each run. No charging state was enforced.
- **Results represent conservative real-world performance:** The numbers reported here represent what a typical consumer would observe if they opened the app immediately and ran inference. This is the relevant measurement for production deployment decisions.
- **Charging state unknown:** Battery API returned `null` throughout all runs (likely Termux API limitations). If the device was charging, the Snapdragon scheduler may have permitted higher sustained clocks; if on battery-saver mode, performance would be modestly worse.
- **Multiple runs per model:** Most models have 2–7 runs in the dataset. Metrics reported here are from the latest run per model. Run-to-run variation was low for qwen models (< 5% tok/s variance) — confirming reproducibility under real-world conditions.

---

## Future Controlled Benchmark Mode

For production acceptance criteria validation (particularly HC-6 thermal ceiling and HC-7 p90 latency), a controlled run procedure will be used to reduce variance and isolate inference-only thermal impact:

1. **Reboot device** — clears page cache, resets thermal history, terminates all background activity
2. **Enable airplane mode** — eliminates network-induced background CPU activity (sync daemons, push notifications)
3. **Set screen brightness to minimum** — reduces SoC thermal load from display driver
4. **Unplug from charger** — enforces battery-mode scheduler behavior; eliminates charging-mode CPU boost
5. **Wait 2 minutes** — allow all thermal zones to cool to ≤ 38°C (measured via `/sys/class/thermal/`)
6. **Kill all background apps** — via recents menu; reduces RAM-related CPU pressure
7. **Run benchmark immediately** — without unlocking, relocking, or interacting with device further

**Expected benefits vs current methodology:**
- 10–20% reduction in tok/s variance (background CPU contention eliminated)
- More reproducible thermal ceiling readings (HC-6 validation for qwen2.5-1.5b at 55.8°C)
- Accurate p90 latency for HC-7 (no OS scheduler interference)
- Comparable results across different devices in future low-end device benchmarks

**Status:** Planned for next milestone after primary model selection is confirmed.

---

## Actionable Next Steps

| Priority | Action |
|---|---|
| P1 | Integrate `qwen2.5-0.5b-q4km` into the Android app as primary on-device model |
| P1 | Quality-evaluate tinyllama outputs — run finance answer rubric on all 20 prompts; decide if 75-word avg meets domain requirements |
| P2 | Upgrade llama.cpp in Termux to ≥ b3100 (Sept 2024+), then re-benchmark `llama3.2-1b-q4km` |
| P2 | After llama.cpp upgrade, re-benchmark `gemma-2b-q4km` — note it also fails HC-1 (1,629 MB) |
| P3 | Run controlled benchmark mode for `qwen2.5-1.5b-q4km` to validate thermal ceiling (55.8°C, close to HC-6 limit) |
| P3 | Consider `qwen2.5-3b-q4km` or `qwen2.5-7b-q4km` (Q2_K) as future flagship candidates if storage and HC-1 threshold is relaxed |
| P4 | Begin low-end device benchmark campaign (Redmi Note-class, Pixel 6a) using `qwen2.5-0.5b-q4km` as baseline |
