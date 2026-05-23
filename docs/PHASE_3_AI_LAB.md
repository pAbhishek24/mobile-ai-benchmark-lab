# Phase 3 — Local AI Performance Lab

## Purpose

Phase 3 evaluates which local language model can run on a mid-range to high-end Android device, stay within acceptable latency and battery constraints, and deliver useful finance-specific intelligence — without any cloud call. This is an **isolated research branch** (`phase-3-ai-lab`). No AI code merges into `main` until a model passes all production acceptance criteria.

**Branch:** `phase-3-ai-lab`
**Merges into:** `main` only after passing production acceptance criteria (see `docs/PRODUCTION_RELEASE_CRITERIA.md`)
**Does not block:** Phase 2 stabilisation or beta releases

---

## Constraints

The app targets:
- **Min SDK:** API 26 (Android 8.0)
- **Primary test device:** Samsung S24 Ultra (12 GB RAM, Snapdragon 8 Gen 3)
- **Target device range:** any Android 11+ device with ≥ 4 GB RAM
- **APK size budget:** production APK should stay under 100 MB (models distributed separately or downloaded on first use)
- **RAM budget:** model + app combined must stay under 2.5 GB on a 4 GB device
- **Battery budget:** AI inference should not exceed 3% battery per session (10–15 queries)
- **Latency budget:** first token ≤ 3 seconds, full response ≤ 15 seconds on mid-range device

---

## Model candidates

| Model | Quantisation | Disk size | Est. RAM | Notes |
|---|---|---|---|---|
| **Qwen2.5 1.5B** | Q4_K_M | ~1.0 GB | ~1.2 GB | Strong instruction following, multilingual (Hindi support) |
| **Phi-3 Mini 3.8B** | Q4_K_M | ~2.3 GB | ~2.6 GB | Excellent reasoning for size, Microsoft, good on structured tasks |
| **Gemma 2B** | Q4_K_M | ~1.4 GB | ~1.6 GB | Google, fast inference, good for short prompts |
| **Gemma 3 1B** | Q4_K_M | ~0.7 GB | ~0.9 GB | Smallest viable option, very fast |
| **Llama 3.2 1B** | Q4_K_M | ~0.7 GB | ~0.9 GB | Meta, very fast, limited reasoning |
| **Llama 3.2 3B** | Q4_K_M | ~2.0 GB | ~2.3 GB | Better quality, still mobile-viable |

**Initial shortlist for benchmarking:** Qwen2.5 1.5B, Gemma 3 1B, Llama 3.2 3B — covers the size/quality tradeoff space.

---

## Benchmark metrics

Every candidate model is scored on all of the following:

### Performance metrics
| Metric | Measurement method | Acceptance threshold |
|---|---|---|
| **Model disk size** | `ls -lh model.gguf` | ≤ 2.5 GB |
| **RAM usage at inference** | Android Memory Profiler or `/proc/meminfo` | ≤ 2.5 GB total (app + model) |
| **First token latency** | Time from prompt sent → first token received (ms) | ≤ 3000 ms on S24 Ultra |
| **Tokens/sec (generation speed)** | Count tokens in response / generation time | ≥ 8 t/s on S24 Ultra |
| **Full response time** | Time from prompt → complete response (s) | ≤ 15 s for a 200-token response |
| **App UI responsiveness** | Janky frames during inference (Perfetto/systrace) | < 5% janky frames |
| **Battery drain per session** | Battery stats before/after 10 queries | ≤ 3% per session |
| **Thermal impact** | Device temperature after 10 queries | No thermal throttling within first 5 min |
| **Cold start time** | Time to load model from disk on first inference | ≤ 8 s |

### Quality metrics (finance-specific prompts)
| Task | Prompt type | Scoring |
|---|---|---|
| Budget summary | "I spent ₹14,200 this month on food. My budget is ₹12,000. What should I do?" | 1–5 relevance + actionability |
| Category suggestion | "SMS: Rs.450 debited for IRCTC. What category?" | Correct category Y/N |
| Debt advice | "I have a ₹5L personal loan at 14% and a ₹50K credit card at 36%. Which should I pay first?" | Financial correctness 1–5 |
| Savings tip | "My salary is ₹80,000. Expenses: ₹35,000. EMI: ₹15,000. How should I save?" | Relevance 1–5 |
| Anomaly flag | "I usually spend ₹2,000/month on fuel. This month I spent ₹8,500. Why might that be?" | Relevance 1–5 |

---

## Test plan — Phase A: Termux + llama.cpp

**Goal:** Establish raw model performance baselines on the target device before writing any Android integration code.

### Setup
```bash
# On the Android device via Termux
pkg install clang cmake git

# Clone and build llama.cpp
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_OPENMP=ON
cmake --build build --config Release -j4

# Download a candidate model (e.g. Gemma 3 1B Q4_K_M)
# Transfer from computer or download directly via wget
```

### Benchmark script
```bash
#!/bin/bash
MODEL="$1"
PROMPT="I spent Rs.450 on Swiggy today. My food budget this month is Rs.3000 and I have spent Rs.2100 so far. Am I on track?"

echo "=== Benchmark: $MODEL ==="
echo "Prompt tokens: $(echo $PROMPT | wc -w)"

time ./build/bin/llama-cli \
  -m "$MODEL" \
  -p "$PROMPT" \
  -n 200 \
  --temp 0.1 \
  --repeat-penalty 1.1 \
  -t 4 \
  2>&1 | tee benchmark_output.txt

grep "llama_print_timings" benchmark_output.txt
```

### Metrics to record per run
```
Model: ___________
Quantisation: ___________
Disk size (MB): ___________
RAM before (MB): ___________
RAM during (MB): ___________
RAM after (MB): ___________
Cold start (s): ___________
First token (ms): ___________
Tokens/sec: ___________
Full response (s): ___________
Device temperature before (°C): ___________
Device temperature after (°C): ___________
Thermal throttle observed: YES / NO
Response quality (1–5): ___________
```

---

## Test plan — Phase B: Local HTTP bridge

**Goal:** Allow the Android app to call the model running in Termux over localhost, without any JNI code. This lets us validate the full UI → model → response loop before committing to an embedded approach.

### Architecture
```
Android App (Kotlin)
    │
    │  HTTP POST localhost:8080/completion
    │  { "prompt": "...", "n_predict": 200 }
    ▼
llama.cpp server (Termux, background process)
    │
    ▼
Model response (JSON)
    { "content": "..." }
```

### llama.cpp server setup (Termux)
```bash
./build/bin/llama-server \
  -m gemma-3-1b-q4.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -t 4 \
  -n 200 \
  --temp 0.1 &
```

### Android integration (Phase B only — does not merge to main)
```kotlin
// LocalAiHttpClient.kt — branch only
suspend fun generate(prompt: String): String = withContext(Dispatchers.IO) {
    val url = URL("http://127.0.0.1:8080/completion")
    val connection = url.openConnection() as HttpURLConnection
    connection.requestMethod = "POST"
    connection.setRequestProperty("Content-Type", "application/json")
    connection.doOutput = true
    val body = """{"prompt":"$prompt","n_predict":200,"temperature":0.1}"""
    connection.outputStream.write(body.toByteArray())
    connection.inputStream.bufferedReader().readText()
}
```

### Validation criteria for Phase B pass
- [ ] App sends prompt and receives response without crash
- [ ] Latency within 20% of Termux-only benchmark
- [ ] UI remains responsive (main thread not blocked)
- [ ] No ANR during 200-token generation
- [ ] Response parsed and displayed in InsightsScreen

---

## Test plan — Phase C: Embedded JNI (future)

**Dependency:** Phase B pass + model selection decision

The embedded approach uses llama.cpp compiled as a `.so` library and called via JNI or a Kotlin/Native bridge. This eliminates the Termux dependency for production but requires:
- Pre-built `.so` for `arm64-v8a` (primary) and optionally `armeabi-v7a`
- NDK build pipeline in Gradle
- Model file bundled as a large asset or downloaded on first use
- A dedicated `ModelManager` that handles download, verification (SHA256), and loading

**This is Phase C work — not started in Phase 3 lab.**

---

## Model selection matrix

Score each candidate 1–5 on each dimension after benchmarking. Select the model with the highest weighted score.

| Dimension | Weight | Qwen2.5 1.5B | Phi-3 Mini | Gemma 3 1B | Llama 3.2 3B |
|---|---|---|---|---|---|
| Disk size (smaller = better) | 20% | — | — | — | — |
| RAM usage (lower = better) | 20% | — | — | — | — |
| First token latency | 15% | — | — | — | — |
| Tokens/sec | 15% | — | — | — | — |
| Finance answer quality | 20% | — | — | — | — |
| Thermal impact | 10% | — | — | — | — |
| **Weighted total** | 100% | — | — | — | — |

Fill in after Termux benchmarks. Selected model proceeds to Phase B.

---

## Production acceptance criteria

A model is production-ready for embedding when ALL of the following are true:

- [ ] Disk size ≤ 2.5 GB
- [ ] Peak RAM (app + model) ≤ 2.5 GB on a 4 GB device
- [ ] First token latency ≤ 3 s on Samsung S24 Ultra
- [ ] First token latency ≤ 6 s on a mid-range device (e.g. Redmi Note 12)
- [ ] Tokens/sec ≥ 8 on S24 Ultra
- [ ] No thermal throttle within first 5 minutes of continuous use
- [ ] Battery drain ≤ 3% for a 10-query session
- [ ] App UI shows no janky frames (< 5% janky) during inference
- [ ] Finance answer quality ≥ 4/5 on the benchmark prompt set
- [ ] Model runs fully offline — no internet call during inference
- [ ] User explicitly opts in before model is downloaded
- [ ] Model stored in app-private storage (not accessible to other apps)
- [ ] SHA256 integrity check on model file before first load
- [ ] AI feature can be disabled entirely from Settings with no performance impact on the rest of the app
