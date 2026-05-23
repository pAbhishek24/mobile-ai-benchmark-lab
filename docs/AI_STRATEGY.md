# AI Strategy — Personal Finance Assistant

Last updated: May 2026

---

## AI Philosophy

**AI is an enhancement layer, not a dependency.**

The app must be fully functional, accurate, and useful with zero AI. Every transaction is tracked, every category is resolved, every report is generated — all without a model. AI layers on top of a working product to improve accuracy and add insight. It never gates core features.

This is both a product principle and an architectural constraint. The ingestion pipeline, category resolver, and analytics engine are all pure Kotlin — they have no model dependency and run on any device.

**No financial data ever leaves the device for AI inference.** This is non-negotiable. Cloud AI APIs (OpenAI, Gemini, Claude API, etc.) will never receive user transaction data, SMS content, or any identifiable financial information.

---

## AI Modes

### Mode 0 — No AI (default, all devices)
The app as it exists today. Rule-based category resolver, regex SMS parser, heuristic confidence scoring. Works fully offline on a 2GB RAM device from 2018.

### Mode 1 — AI Lite (Phase 3, v1.x.x)
Lightweight on-device intelligence using classic ML and pattern heuristics. No LLM, no large model file.

Features:
- Merchant rule suggestion: "You've manually categorized BLINKIT as Grocery 8 times — create a rule?"
- Spend pattern summaries: "Food spend is 40% above your 3-month average"
- Parser confidence improvement from user correction signals
- Duplicate detection improvement

Device requirement: Any device running the app (API 26+). No extra RAM or storage needed.
Model size: Zero — these are heuristic algorithms, not loaded models.

### Mode 2 — Local LLM (Phase 4, v2.0.0, premium)
A quantized GGUF model running on-device via llama.cpp JNI or ONNX Runtime.

Features:
- "Ask your finances" — natural language queries over local transaction data
- Contextual budget advice ("You're on track to overspend ₹4,000 on Food this month")
- Debt payoff planning (avalanche / snowball calculator with explanation)
- Monthly review in plain language

Hard constraints:
- Model file ≤ 1.5GB on disk
- Peak RAM usage ≤ 800MB (model + app combined)
- First token latency ≤ 2,500ms on target device
- Generation speed ≥ 8 tokens/sec on target device
- No thermal throttle in first 3 queries
- Finance answer quality ≥ 4/5 on standard benchmark set

### Mode 3 — Future Premium AI (Phase 5+)
Optional cloud-assisted AI for users who opt in. Even in this mode, raw transaction data is never sent to any server. Only aggregated, anonymized summaries (e.g. "monthly_food_spend: ₹8,200") may be used for cloud inference, and only with explicit user consent per query.

---

## Device-Tier Strategy

### Low-end (2–3GB RAM, pre-2020 SoC, e.g. Snapdragon 4xx)
- Mode: 0 only (No AI)
- AI features: Hidden — no visible toggle, no empty state
- No model download prompt
- Full tracking, reporting, rules engine — everything works

### Mid-range (4–6GB RAM, 2020–2022 SoC, e.g. Snapdragon 6xx/7xx)
- Mode: 0 + Mode 1 (AI Lite)
- Mode 2 attempted but gated: if device doesn't meet RAM/performance threshold at runtime, Mode 2 stays hidden
- Model download: optional, shown as "Try AI (beta)" — never pushed during onboarding

### Flagship (8GB+ RAM, 2022+ SoC, e.g. Snapdragon 8 Gen 1+, Dimensity 9xxx)
- Mode: 0 + 1 + 2
- Mode 2 shown as "AI Finance Assistant" in premium settings
- Model download prompted once after stable usage established (≥30 days, ≥50 transactions)

Detection strategy: Runtime check using `ActivityManager.getMemoryInfo()` + `Build.VERSION.SDK_INT`. Thresholds checked at app startup and cached in DataStore. Never block UI — hide features silently.

---

## Model Candidate Roadmap

Evaluated against the benchmark protocol in `docs/PHASE_3_AI_LAB.md`.

| Model | Size (Q4_K_M) | Target device | Status |
|---|---|---|---|
| TinyLlama 1.1B | ~700MB | Low-end | Benchmarking |
| Qwen2.5 1.5B | ~986MB | Mid-range | Benchmarking |
| Phi-3 Mini 3.8B | ~2.2GB | Flagship | Planned |
| Gemma-2 2B | ~1.5GB | Mid-range/Flagship | Planned |
| Qwen2.5 3B | ~1.9GB | Flagship | Planned |
| FinanceLLM (custom fine-tune) | TBD | TBD | Future |

Selection criteria (all must pass):
1. Disk size ≤ 1.5GB
2. Peak RAM ≤ 800MB
3. First token latency ≤ 2,500ms
4. Generation speed ≥ 8 tokens/sec
5. Finance answer quality ≥ 4/5
6. No thermal throttle in first 3 queries
7. Correct rupee amount handling
8. No hallucination of account numbers or transactions

---

## Battery & Thermal Constraints

### Hard rules
- Model is never loaded at app startup
- Model is never loaded in the background
- Model is loaded only when the user explicitly opens the AI screen and sends a query
- Model is unloaded from memory after 5 minutes of AI screen inactivity
- AI inference is cancellable — user can abort a running query
- AI inference runs on a low-priority coroutine dispatcher, never on the main thread
- If device temperature exceeds Android thermal threshold (`PowerManager.THERMAL_STATUS_SEVERE`), inference is suspended

### Targets
| Metric | Target |
|---|---|
| Battery drain per AI query | < 0.5% |
| Battery drain per hour of background AI | 0% (AI never runs in background) |
| Thermal throttle threshold | None in first 5 queries on target device |
| Model load time | < 3s on target device |
| Model unload | Within 5 minutes of last query |

---

## AI Feature Gating Philosophy

Features are gated at three levels:

1. **Device capability gate** — checked at runtime, silently hides AI UI if device doesn't qualify
2. **User consent gate** — model download requires explicit user tap, shown only after 30+ days and 50+ transactions
3. **Premium gate** — Local LLM is a premium feature; AI Lite is free

**No degraded experience for non-AI users.** A user who never enables AI gets the same tracking, reporting, and rules engine as an AI user. The only difference is the absence of the AI screen.

---

## Production Acceptance Criteria

Before any AI code merges from `phase-3-ai-lab` to `main`:

- [ ] All 16 criteria in `docs/PHASE_3_AI_LAB.md` pass on target device
- [ ] AI features fully hidden on devices not meeting thresholds (automated test)
- [ ] App startup time unaffected by AI code presence (< 2s, measured without model loaded)
- [ ] All existing unit tests still pass — AI code adds zero regressions
- [ ] Model file not bundled in APK (downloaded separately, .gitignored)
- [ ] No network calls from AI inference path — verified by network security config
- [ ] Memory usage with AI screen open ≤ 800MB combined (model + app)
- [ ] Memory usage with AI screen closed = same as without AI code (< 100MB)
- [ ] Thermal test: 10 consecutive queries on Snapdragon 695, no throttle
- [ ] Finance domain test: 20 standard Indian finance questions answered accurately
- [ ] Hindi/mixed language prompt test: no confusion or hallucination
- [ ] Rupee amount test: ₹ and Rs. formats handled correctly in all outputs
