# Model Evaluation Record

Copy this file for each model tested. Filename: `MODEL_EVAL_<model-name>_<date>.md`

---

## Model Details

| Field | Value |
|---|---|
| Model name | |
| Quantization | |
| GGUF file size (MB) | |
| Source (HuggingFace URL) | |
| Test date | |
| Tested on device | |
| Android version | |
| Tester | |

---

## Resource Usage

| Metric | Value |
|---|---|
| Peak RAM — model + Termux (MB) | |
| RAM available before loading (MB) | |
| RAM available after loading (MB) | |
| Model load time (ms) | |
| Storage used (MB) | |

---

## Performance Metrics

| Metric | Run 1 | Run 2 | Run 3 | Median |
|---|---|---|---|---|
| First token latency (ms) | | | | |
| Tokens/sec (generation speed) | | | | |
| Time for 20-prompt benchmark (min) | | | | |

---

## Thermal & Battery

| Metric | Value |
|---|---|
| Device temp at benchmark start (°C) | |
| Device temp at benchmark end (°C) | |
| Max temp observed (°C) | |
| Thermal throttle detected? (Y/N) | |
| If yes — at which prompt number? | |
| Battery % at start | |
| Battery % at end | |
| Total battery drain (%) | |
| Estimated drain per query (%) | |

---

## App Responsiveness Impact

With model loaded (llama-server or llama-cli running), open PersonalFinanceAssistant and navigate through key screens.

| Screen | Impact observed |
|---|---|
| Dashboard | None / Minor jank / Significant / Unusable |
| Transaction list | None / Minor jank / Significant / Unusable |
| Review Queue | None / Minor jank / Significant / Unusable |
| Reports | None / Minor jank / Significant / Unusable |
| Settings | None / Minor jank / Significant / Unusable |

**Overall app impact:** None / Minor / Significant / Unusable

---

## Finance Domain Quality — 20 Prompt Scores

Score each answer 1–5:
- **5** — Correct, India-aware, practical, no hallucination
- **4** — Correct with minor omissions, no hallucination
- **3** — Partially correct, some useful content
- **2** — Mostly incorrect but no fabricated data
- **1** — Hallucinated transactions/amounts, or completely wrong

| Prompt ID | Category | Score (1–5) | Notes |
|---|---|---|---|
| P01 | expense_summary | | |
| P02 | expense_summary | | |
| P03 | emi_pressure | | |
| P04 | emi_pressure | | |
| P05 | credit_card_planning | | |
| P06 | credit_card_planning | | |
| P07 | sip_planning | | |
| P08 | sip_planning | | |
| P09 | lic_outflow | | |
| P10 | lic_outflow | | |
| P11 | budget_overspend | | |
| P12 | budget_overspend | | |
| P13 | safe_spend_remaining | | |
| P14 | safe_spend_remaining | | |
| P15 | debt_payoff | | |
| P16 | debt_payoff | | |
| P17 | category_spike | | |
| P18 | category_spike | | |
| P19 | cashflow_warning | | |
| P20 | cashflow_warning | | |
| **Average** | | | |

---

## Hard Criteria Checklist

All 8 must pass for the model to be considered a candidate.

| # | Criterion | Threshold | Result | Pass/Fail |
|---|---|---|---|---|
| HC-1 | Disk size (GGUF) | ≤ 1,500MB | | |
| HC-2 | Peak RAM (model + app) | ≤ 800MB | | |
| HC-3 | First token latency (SD 695) | ≤ 2,500ms | | |
| HC-4 | Generation speed (SD 695) | ≥ 8 tok/s | | |
| HC-5 | No thermal throttle in first 3 queries | Pass/Fail | | |
| HC-6 | Finance quality score average | ≥ 4.0/5.0 | | |
| HC-7 | Rupee format (₹ and Rs.) handled correctly | Pass/Fail | | |
| HC-8 | Zero hallucinated transactions or account numbers | Pass/Fail | | |

**HC pass count: ___ / 8**

---

## Hallucination Log

Record any instances where the model invented transaction data, account numbers, names, or amounts not present in the prompt.

| Prompt ID | What was hallucinated | Severity (Low/Med/High) |
|---|---|---|
| | | |

---

## Rupee Handling Check

| Test | Expected | Actual | Pass/Fail |
|---|---|---|---|
| ₹ symbol in response | ₹12,000 | | |
| Rs. format in response | Rs. 8,500 | | |
| Lakh notation | ₹1.5 lakhs | | |
| Crore notation | ₹10 crores | | |
| Comma formatting | ₹1,20,000 | | |

---

## Qualitative Notes

**Strengths of this model for Indian finance use case:**

*(free text)*

**Weaknesses or failure patterns observed:**

*(free text)*

**Hindi/mixed language handling** (if tested):

*(free text)*

---

## Decision

| Field | Value |
|---|---|
| **Overall decision** | ❌ Reject / ⚠️ Maybe (needs re-test on SD 695) / ✅ Candidate |
| **Rejection reason (if rejected)** | |
| **Recommended device tier (if candidate)** | Flagship only / Mid-range+ / All devices |
| **Recommended next step** | |

---

## Raw Benchmark File Reference

| File | Path |
|---|---|
| JSONL results | `ai-lab/results/benchmark_<model>_<timestamp>.jsonl` |
| Full log | `ai-lab/results/benchmark_<model>_<timestamp>.log` |
| Device snapshot before | `ai-lab/results/snapshot_before_<timestamp>.json` |
| Device snapshot after | `ai-lab/results/snapshot_after_<timestamp>.json` |
