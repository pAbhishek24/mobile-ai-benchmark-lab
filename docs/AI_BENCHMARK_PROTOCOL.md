# AI Benchmark Protocol — Phase 3 AI Lab

Last updated: May 2026

---

## Lab Directory

The active benchmarking lab lives in [`ai-lab/`](../ai-lab/):

| Path | Purpose |
|---|---|
| [`ai-lab/README.md`](../ai-lab/README.md) | Setup guide — Termux, llama.cpp, running benchmarks |
| [`ai-lab/prompts/finance-benchmark-prompts.json`](../ai-lab/prompts/finance-benchmark-prompts.json) | 20 Indian finance prompts (the standard test set) |
| [`ai-lab/scripts/run_llama_benchmark.sh`](../ai-lab/scripts/run_llama_benchmark.sh) | Automated benchmark runner — captures timing, tok/s, thermal |
| [`ai-lab/scripts/device_snapshot.sh`](../ai-lab/scripts/device_snapshot.sh) | Device state capture — RAM, battery, thermal zones |
| [`ai-lab/MODEL_EVALUATION_TEMPLATE.md`](../ai-lab/MODEL_EVALUATION_TEMPLATE.md) | Fill one per model evaluated |
| `ai-lab/results/` | Gitignored — JSONL results, logs, snapshots |
| `ai-lab/models/` | Gitignored — GGUF model files |

**Start here:** [`ai-lab/README.md`](../ai-lab/README.md) has the complete setup and execution guide for Samsung S24 Ultra and mid-range devices.

---

## Goals

The Phase 3 AI lab has one purpose: **determine whether a quantized local LLM can meet production quality bars on a real mid-range Android device before any AI code touches the production app.**

We are not building a prototype. We are running a structured evaluation to answer:

1. Which model, at which quantization, fits within 1.5GB disk and 800MB RAM?
2. Which model achieves ≥8 tokens/sec on Snapdragon 695 and ≥12 tok/s on Snapdragon 8 Gen 2?
3. Which model correctly answers Indian personal finance questions without hallucinating transactions, account numbers, or rupee amounts?
4. Which model survives 10 consecutive queries without thermal throttle?
5. Which model, when loaded, does not meaningfully degrade app responsiveness?

No model ships until all 8 hard criteria pass. No AI code merges to `main` until all 16 production acceptance criteria in this document pass on the target device.

---

## Mobile-First AI Philosophy

Most LLM benchmarks are run on cloud GPUs or developer laptops. Those numbers are irrelevant here.

Every measurement in this lab is taken on real Android hardware — specifically the Samsung Galaxy S24 Ultra (Snapdragon 8 Gen 3, 12GB RAM) as the flagship baseline, and a Snapdragon 695 device as the mid-range gate. A model that passes on S24 Ultra but fails on Snapdragon 695 does not ship for mid-range users.

**Guiding principles:**

- **Battery over speed.** A model that runs at 6 tokens/sec without throttling is better than one that hits 15 tok/s then thermal-limits after 3 queries.
- **RAM headroom over model quality.** The app needs to stay alive alongside the model. A model that uses 750MB RAM is preferred over one that uses 900MB even if the latter scores higher on benchmarks.
- **Correct > fast.** A model that answers slowly but correctly is always preferred over one that answers fast but hallucinates.
- **Offline is mandatory.** Any model that makes network calls during inference is immediately disqualified.
- **Graceful failure.** If a device can't run a model, the app behaves identically to a device with no AI at all. No error states, no degraded UX — the AI screen is simply hidden.

---

## Hard Constraints (any failure = model rejected)

| # | Constraint | Threshold |
|---|---|---|
| HC-1 | Disk size (Q4_K_M GGUF) | ≤ 1.5GB |
| HC-2 | Peak RAM (model + app combined) | ≤ 800MB |
| HC-3 | First token latency (Snapdragon 695) | ≤ 2,500ms |
| HC-4 | Generation speed (Snapdragon 695) | ≥ 8 tokens/sec |
| HC-5 | No thermal throttle in first 3 queries | Pass / Fail |
| HC-6 | Finance answer quality | ≥ 4/5 on standard set |
| HC-7 | Rupee amount handling | Correct ₹/Rs. in all outputs |
| HC-8 | No hallucination of transactions/account numbers | Pass / Fail |

---

## Model Evaluation Matrix

### Candidates

| Model | Quantization | Est. Disk | Est. RAM | Target Device | Priority |
|---|---|---|---|---|---|
| TinyLlama 1.1B | Q4_K_M | ~670MB | ~450MB | Low-end/Mid | High — smallest viable |
| Qwen2.5 0.5B | Q4_K_M | ~400MB | ~300MB | Low-end | High — low-end candidate |
| Qwen2.5 1.5B | Q4_K_M | ~986MB | ~650MB | Mid-range | High — best quality/size ratio |
| Llama 3.2 1B | Q4_K_M | ~730MB | ~500MB | Low-end/Mid | High — Meta's small model |
| Gemma 2B | Q4_K_M | ~1.5GB | ~900MB* | Mid/Flagship | Medium — may exceed RAM limit |
| Phi-3 Mini 3.8B | Q4_K_M | ~2.2GB* | ~1.4GB* | Flagship only | Low — likely too large |

*Estimated to exceed one or more hard constraints — benchmark anyway to confirm.

### Measurement Protocol Per Model

Run each model through all phases in sequence. Record every number. Do not skip phases.

#### Phase A — Resource Baseline (before model loads)
```
1. Record device free RAM
2. Record device storage available
3. Record device temperature (°C) via Termux: cat /sys/class/thermal/thermal_zone*/temp
4. Record battery % and charging state
```

#### Phase B — Model Load
```
1. Start timer
2. Load model via llama.cpp: ./llama-cli -m <model.gguf> -p "" -n 1
3. Record: model load time (ms)
4. Record: RAM consumed by llama-server process (ps -o pid,rss,vsz,cmd)
5. Record: device temperature change after load
```

#### Phase C — First Token Latency
```
Prompt: "What is my total spending this month?"
Repeat 3 times, record median.
Metric: time from prompt submit to first token output (ms)
```

#### Phase D — Generation Speed
```
Prompt: "I spent ₹8,200 on food, ₹3,500 on transport, ₹12,000 on rent, and ₹2,800 on utilities this month. What percentage of my ₹40,000 salary went to each category? Which category should I try to reduce?"
Target: 150+ token response
Record: tokens/second
Repeat: 5 runs, take median
```

#### Phase E — Finance Domain Quality
Run the 20-question standard Indian finance question set (defined below).
Score each answer 1–5 on the quality rubric.
Required: average ≥ 4.0, no single answer below 2.

#### Phase F — Thermal Stress
```
1. Record starting temperature
2. Run 10 consecutive generation queries (Phase D prompt, back-to-back)
3. Record temperature after each query
4. Record: did device throttle? (token rate dropped >30% from baseline)
5. Record: did device show thermal warning?
```

#### Phase G — App Responsiveness Impact
```
1. With model loaded (llama-server running), open PersonalFinanceAssistant
2. Navigate: Dashboard → Transactions → Review Queue → Reports → Settings
3. Observe: any jank, slow loads, dropped frames?
4. Record: subjective impact (None / Minor / Significant / Unusable)
```

#### Phase H — Battery Drain
```
1. Note battery % at start of thermal stress test (Phase F)
2. Note battery % at end of 10 queries
3. Record: % drain for 10 queries
4. Extrapolate: estimated % drain per query
```

---

## Standard Finance Question Set (20 questions)

These questions simulate real user queries. All answers are scored 1–5 (5 = perfect, 1 = hallucination or complete failure).

**Category 1 — Arithmetic and tracking (must be correct, no hallucination)**
1. "I spent ₹8,200 on food and ₹3,500 on transport this month. What is my total spend?"
2. "My salary is ₹75,000. I spend ₹45,000. What is my savings rate as a percentage?"
3. "I have an EMI of ₹12,500 per month and my salary is ₹60,000. What is my EMI burden percentage?"
4. "I invested ₹5,000 per month in SIP for 3 years at 12% annual return. What is the approximate corpus?"
5. "My home loan outstanding is ₹28 lakhs at 8.5% interest. What is the approximate annual interest cost?"

**Category 2 — Budgeting advice (India-aware)**
6. "I earn ₹80,000/month. How should I allocate my budget across rent, food, EMI, savings, and discretionary?"
7. "My food spend is ₹12,000 this month vs ₹8,000 last month. What might explain this and should I be concerned?"
8. "I have ₹50,000 surplus this month. Should I prepay my home loan EMI or invest in SIP?"
9. "My credit card bill is ₹35,000 due in 5 days and I have ₹20,000 in savings. What should I do?"
10. "I want to save ₹2 lakhs for an emergency fund. I can save ₹15,000/month. How long will it take?"

**Category 3 — Indian finance instruments (LIC, NPS, SIP)**
11. "What is the difference between SIP and lump sum investment in mutual funds?"
12. "My LIC premium is ₹18,000 per year. Is this a good investment or just insurance?"
13. "I contribute ₹5,000/month to NPS. What are the tax benefits I get?"
14. "What is the difference between equity mutual funds and debt mutual funds for someone earning ₹60,000/month?"
15. "I have 3 credit cards with outstanding ₹15,000, ₹8,000, and ₹22,000. Which should I pay first?"

**Category 4 — Debt management**
16. "Explain the avalanche method for paying off debt with three loans of different interest rates."
17. "My personal loan is at 18% interest and my home loan is at 8.5%. Which one should I prepay?"
18. "I have a ₹5 lakh personal loan at 14% for 5 years. What is the approximate total interest I'll pay?"
19. "Should I use my bonus of ₹1 lakh to close my personal loan or invest in mutual funds?"
20. "What is an overdraft facility and is it better than a personal loan for short-term needs?"

### Scoring Rubric
| Score | Description |
|---|---|
| 5 | Correct, India-aware, practical, no hallucination |
| 4 | Correct with minor omissions, no hallucination |
| 3 | Partially correct, some useful content |
| 2 | Mostly incorrect but no fabricated data |
| 1 | Hallucinated transactions/amounts/account numbers, or completely wrong |

---

## Metrics Tracking Sheet

For each model, record the following (one row per model):

| Metric | TinyLlama 1.1B | Qwen2.5 0.5B | Qwen2.5 1.5B | Llama 3.2 1B | Gemma 2B | Phi-3 Mini |
|---|---|---|---|---|---|---|
| Disk size (MB) | | | | | | |
| Peak RAM (MB) | | | | | | |
| Model load time (ms) | | | | | | |
| First token latency — median (ms) | | | | | | |
| Generation speed — median (tok/s) | | | | | | |
| CPU utilization during gen (%) | | | | | | |
| Battery drain per 10 queries (%) | | | | | | |
| Temp rise during 10 queries (°C) | | | | | | |
| Thermal throttle in 10 queries? | | | | | | |
| App responsiveness impact | | | | | | |
| Finance quality score (/5 avg) | | | | | | |
| Hallucination incidents | | | | | | |
| Rupee handling correct? | | | | | | |
| **Overall: PASS / FAIL** | | | | | | |

---

## 16 Production Acceptance Criteria

Before any AI code merges from `phase-3-ai-lab` to `main`, all 16 must pass on the target device:

| # | Criterion | Target |
|---|---|---|
| AC-1 | Model disk size | ≤ 1.5GB |
| AC-2 | Peak RAM (model + app) | ≤ 800MB |
| AC-3 | First token latency (SD 695) | ≤ 2,500ms |
| AC-4 | Generation speed (SD 695) | ≥ 8 tok/s |
| AC-5 | Thermal throttle | None in first 5 queries |
| AC-6 | Finance quality score | ≥ 4/5 average |
| AC-7 | Rupee format handling | 100% correct |
| AC-8 | Hallucination incidents | 0 in 20-question set |
| AC-9 | AI features hidden on low-end devices | Automated test passes |
| AC-10 | App startup unaffected by AI code presence | < 2s cold launch |
| AC-11 | No network calls from AI inference path | Network security config verified |
| AC-12 | Memory with AI screen closed | Same as without AI (< 100MB) |
| AC-13 | Memory with AI screen open (model loaded) | ≤ 800MB combined |
| AC-14 | Model unloads within 5min of AI screen close | Confirmed via memory profiler |
| AC-15 | Hindi/mixed-language prompts handled | No confusion or hallucination |
| AC-16 | All existing unit tests pass | Zero regressions |

---

## Recommended First Benchmark

**Start with: Qwen2.5 1.5B Q4_K_M on Samsung S24 Ultra via Termux + llama.cpp**

Rationale:
- Best balance of quality and size among all candidates
- ~986MB — well within disk constraint, likely within RAM constraint
- Qwen2.5 series has strong multilingual (including Hindi) performance
- If it fails on S24 Ultra, no mid-range candidate will pass either
- Sets the upper bound — if it passes, evaluate smaller models for wider device support

See `docs/TERMUX_AI_LAB_SETUP.md` for step-by-step execution.
