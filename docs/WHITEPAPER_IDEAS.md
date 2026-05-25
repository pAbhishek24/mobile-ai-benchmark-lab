# Whitepaper Ideas — Mobile AI Benchmark Lab

Ideas for future research papers, blog posts, or technical notes based on this benchmark work.

---

## 1. Thermal-Aware Mobile LLM Inference

**Working title:** *"When Your Phone Gets Hot: Thermal Throttling and Its Impact on On-Device LLM Performance"*

**Core insight:** Sustained LLM inference causes CPU/GPU thermal throttling on all tested Android devices within 3–8 minutes. The performance cliff is non-linear — tokens/s can drop 40–60% after throttling onset.

**Key findings to document:**
- Throttling onset time by device class (flagship vs mid-range)
- Token throughput before/after throttling (delta curves)
- Recovery time after model unload
- Thermal-safe mode: burst inference with cooldown gaps
- Comparison: charging vs not charging during inference

**Methodology note:** Benchmark captures `snapshot_before.json` and `snapshot_after.json` with device temp, CPU freq, and throttling state.

---

## 2. Quantisation vs Accuracy on Finance Tasks

**Working title:** *"Q4 vs Q8: Does Quantisation Hurt Domain-Specific Accuracy on Resource-Constrained Devices?"*

**Core insight:** Q4_K_M offers the best size/accuracy tradeoff for finance-domain prompts. Q8 adds 2x memory overhead for marginal accuracy gains. INT4 is unusable for structured reasoning.

**Key findings:**
- Accuracy scores by quant level across all models
- Task-specific accuracy: arithmetic vs categorisation vs explanation
- RAM savings vs accuracy loss tradeoff curves
- Recommended quant for each device RAM tier

---

## 3. Sub-2B Models for Financial Intelligence

**Working title:** *"Small Models, Real Problems: Evaluating Sub-2B LLMs for Personal Finance on Android"*

**Core insight:** Models under 2B parameters can handle expense categorisation and simple budget reasoning reliably, but fail on multi-step calculations and nuanced anomaly detection.

**Key findings:**
- Task categories where 0.5B–1.5B models are sufficient
- Failure modes: hallucinated numbers, wrong currencies, unit errors
- Qwen2.5-1.5B as current best-in-class for finance tasks under 2B
- Implications for offline financial apps

---

## 4. Offline Financial Intelligence Architecture

**Working title:** *"Finance Without the Cloud: Architecture for Privacy-First AI on Android"*

**Core insight:** A local LLM integrated into a personal finance app can provide meaningful intelligence (categorisation correction, anomaly flags, budget suggestions) without ever sending financial data to a server.

**Architecture components:**
- SMS/notification ingestion pipeline (no LLM dependency)
- Rule-based category resolver as primary path
- LLM as fallback and enhancement layer only
- Context window management for transaction history
- Token budget constraints per inference call

**Privacy guarantees:**
- All data stays on-device
- LLM inference is sandboxed — no network access during inference
- Model weights stored in app-private storage

---

## 5. Termux as a Mobile AI Development Platform

**Working title:** *"Termux + llama.cpp: The Surprisingly Good Android AI Dev Environment"*

**Core insight:** Termux provides a fully functional Linux environment on unrooted Android. Combined with llama.cpp, it enables reproducible LLM benchmarking without custom ROMs or ADB.

**Practical guide sections:**
- Installing llama.cpp in Termux (build from source)
- Model download and storage management
- Running batched inference from shell scripts
- Capturing device telemetry (thermal, battery, RAM)
- Automating benchmarks via cron or ADB
- Limitations vs a rooted device

---

## 6. Benchmark Methodology for On-Device LLMs

**Working title:** *"Beyond Perplexity: A Practical Benchmark Framework for Production Mobile LLM Deployment"*

**Core insight:** Standard NLP benchmarks (MMLU, HumanEval) don't reflect real-world mobile deployment constraints. A production benchmark must measure latency, thermal, memory, and domain accuracy together.

**Methodology contributions:**
- Composite scoring formula (accuracy 40% / speed 30% / thermal 20% / memory 10%)
- Thermal-adjusted throughput metric (TAT/s)
- Domain-specific prompt set design principles
- Controlled vs real-world benchmark modes
- Statistical validity: minimum run count, variance thresholds
- Device snapshot protocol (before/after JSON)

---

## Publication targets

- arXiv (cs.LG or cs.AI) for methodology papers
- Medium/Substack for practitioner-focused posts
- GitHub Pages for living benchmark results (this repo)
- ACL/EMNLP workshop on efficient NLP for practitioner track
