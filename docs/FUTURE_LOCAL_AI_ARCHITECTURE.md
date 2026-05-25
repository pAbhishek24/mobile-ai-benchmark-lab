# Future Local AI Architecture — Personal Finance Assistant

Last updated: May 2026

**Status: Planning document. No AI code exists in the production app yet. This document defines the integration architecture once Phase 3 benchmarking is complete and a model candidate is selected.**

---

## Guiding Constraints

Before any architecture decision: the hard constraints that override everything else.

1. **No financial data leaves the device.** Ever. Not even anonymized.
2. **AI is optional.** The app functions identically without it.
3. **AI never runs in the background.** Load on demand, unload on timeout.
4. **Battery and thermal take priority over quality.** Suspend inference before throttle.
5. **Low-end devices are first-class.** AI absence is not a failure state.

---

## Integration Strategy: JNI + llama.cpp

### Why llama.cpp over alternatives

| Option | Pros | Cons | Decision |
|---|---|---|---|
| **llama.cpp JNI** | Best performance on CPU, active development, GGUF support, battle-tested on Android | Requires C++ JNI wrapper, build complexity | **Primary path** |
| ONNX Runtime | Widely used, good Kotlin API | Slower than llama.cpp for LLM inference, less GGUF model support | Secondary/fallback |
| TFLite | Small, well-integrated with Android | Limited to TFLite-converted models, not suitable for latest LLMs | Rejected |
| MediaPipe LLM | Google-backed, easy API | Limited model support, slower | Future evaluation |
| Ollama Android | Convenient | Still experimental, large overhead | Future evaluation |

### JNI wrapper design
```
app/
└── src/
    └── main/
        ├── cpp/
        │   ├── CMakeLists.txt
        │   ├── llama_bridge.cpp      ← JNI entry points
        │   └── llama.cpp/            ← llama.cpp as git submodule
        └── java/...ai/
            ├── LlamaJNI.kt           ← JNI declarations
            ├── LocalLLMEngine.kt     ← Kotlin API wrapping JNI
            └── AIRepository.kt       ← Coroutine-safe interface
```

The JNI layer is thin — it exposes three functions: `loadModel()`, `generateResponse()`, `unloadModel()`. All streaming, coroutine bridging, and error handling lives in Kotlin.

---

## Lazy Model Loading

### Principle
The model binary is never loaded at app startup. It is loaded only when:
1. The user opens the AI screen
2. The user submits a query
3. A model file is present on disk

If no model file exists, the AI screen shows a download prompt. If the device fails the runtime capability check, the AI screen is never shown.

### Load/unload lifecycle
```
User opens AI screen
    → check: model file exists?
        → No: show download prompt
        → Yes: show query input (model not loaded yet)

User submits query
    → check: model loaded?
        → No: load model (show loading indicator, ~2-3s)
        → Yes: skip load
    → run inference
    → stream response tokens to UI

User closes AI screen / 5 minutes idle
    → start unload timer
    → after timeout: unload model, release RAM
    → log: "model unloaded, RAM freed"
```

### Loading on background thread
```kotlin
// Pseudocode
class LocalLLMEngine(private val modelPath: String) {
    private val engineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    suspend fun loadIfNeeded() = withContext(Dispatchers.IO) {
        if (!isLoaded) {
            LlamaJNI.loadModel(modelPath)
            isLoaded = true
        }
    }
    
    fun unload() {
        engineScope.launch {
            LlamaJNI.unloadModel()
            isLoaded = false
        }
    }
}
```

Model loading never blocks the main thread. The UI shows a progress indicator that is cancellable.

---

## Optional AI Module Download

### Download flow
The model file (~700MB–1GB) is never bundled in the APK. It is downloaded on demand.

```
Eligibility check at app start (RAM, SDK, storage)
    → Eligible + 30 days used + 50 transactions:
        → Show one-time prompt: "Try AI Finance Assistant (requires Finance+ and 1GB download)"
        → User taps "Learn more" → Premium upsell screen
        → User subscribes → "Download model" button appears in AI Settings

Download:
    → WorkManager task: WIFI_REQUIRED, NOT_LOW_BATTERY, NOT_LOW_STORAGE
    → Downloads to getExternalFilesDir("models")/
    → SHA-256 checksum verified after download
    → On failure: retry with exponential backoff (max 3 attempts)
    → On success: AI screen becomes available
```

### Model storage location
```
/sdcard/Android/data/com.personalfinanceassistant/files/models/
└── qwen2.5-1.5b-q4_k_m.gguf   (or whichever model passed benchmarks)
```

This location is:
- Private to the app (not accessible by other apps without root)
- Deleted on app uninstall (no orphaned model files)
- Included in Android's app storage usage display
- Not backed up by default Android backup (intentional — user re-downloads if needed)

### Model update strategy
When a newer/better model passes benchmarks, the update flow:
1. New model file available in app update
2. Old model file is NOT deleted automatically (user controls storage)
3. Settings → AI → Storage shows current model size and "Remove model" button
4. User can opt into new model download

---

## Model Enable/Disable UX

### AI settings screen (future, Premium only)
```
AI Finance Assistant                     [Premium]

  Status:  ● Active (model loaded)
  Model:   Qwen2.5 1.5B (986MB)
  Storage: app/models/  ·  [Remove model]

  [Disable AI]   [Clear conversation history]

  ─────────────────────────────────────────────
  AI runs entirely on your device.
  Your financial data is never sent anywhere.
```

### Disable behavior
- Disabling AI hides the AI screen immediately
- Model file remains on disk (user can re-enable without re-downloading)
- "Remove model" deletes the file and disables AI until re-downloaded

---

## AI Timeout and Cancel Design

### Query timeout
If a query takes more than 60 seconds (extreme edge case on very slow devices), it is automatically cancelled with a message: "Query took too long. Try a shorter question."

### User-initiated cancel
Every active query shows a cancel button. Cancellation:
1. Stops the inference coroutine
2. Stops streaming tokens to the UI
3. Shows the partial response with "[Stopped]" indicator
4. Model remains loaded (no unload on cancel — user likely has a follow-up)

### Implementation
```kotlin
// Pseudocode
var currentJob: Job? = null

fun submitQuery(prompt: String) {
    currentJob?.cancel()
    currentJob = engineScope.launch {
        try {
            withTimeout(60_000L) {
                engine.generate(prompt).collect { token ->
                    _uiState.update { it.copy(response = it.response + token) }
                }
            }
        } catch (e: TimeoutCancellationException) {
            _uiState.update { it.copy(error = "Query timed out") }
        } catch (e: CancellationException) {
            _uiState.update { it.copy(response = it.response + " [Stopped]") }
        }
    }
}

fun cancelQuery() = currentJob?.cancel()
```

---

## Battery Protection Strategy

### Pre-inference checks
Before starting any inference:
```kotlin
fun canRunInference(context: Context): InferencePermission {
    val powerManager = context.getSystemService(PowerManager::class.java)
    val batteryManager = context.getSystemService(BatteryManager::class.java)
    
    val batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    val isCharging = batteryManager.isCharging
    
    return when {
        batteryLevel < 15 && !isCharging -> InferencePermission.BLOCKED_LOW_BATTERY
        powerManager.isPowerSaveMode -> InferencePermission.BLOCKED_POWER_SAVE
        else -> InferencePermission.ALLOWED
    }
}
```

When blocked: show message "AI queries paused — battery is low" with dismiss option (user can override).

### Inference on low-priority dispatcher
All inference runs on `Dispatchers.Default` with reduced thread priority. Never competes with main thread or IO thread pool.

```kotlin
val aiDispatcher = Executors.newFixedThreadPool(2) { runnable ->
    Thread(runnable, "llama-inference").also {
        it.priority = Thread.MIN_PRIORITY
    }
}.asCoroutineDispatcher()
```

---

## Thermal Throttling Strategy

### Monitoring
```kotlin
// Register thermal status listener (API 29+)
val powerManager = getSystemService(PowerManager::class.java)
powerManager.addThermalStatusListener(executor) { status ->
    when (status) {
        PowerManager.THERMAL_STATUS_SEVERE,
        PowerManager.THERMAL_STATUS_CRITICAL,
        PowerManager.THERMAL_STATUS_EMERGENCY -> suspendInference()
        PowerManager.THERMAL_STATUS_NONE,
        PowerManager.THERMAL_STATUS_LIGHT,
        PowerManager.THERMAL_STATUS_MODERATE -> resumeInference()
    }
}
```

### Behavior on thermal event
- `THERMAL_STATUS_MODERATE`: add 2-second delay between query submissions (soft throttle)
- `THERMAL_STATUS_SEVERE`: suspend inference, show "Device is warm — pausing AI for a moment"
- `THERMAL_STATUS_CRITICAL`: cancel current query immediately, unload model
- After thermal clears to `LIGHT` or below: resume normally

### Model-level throttling
If token generation rate drops >30% from the session baseline, assume thermal throttle even without a system event. Add a cooldown period before next query.

---

## Background Execution Restrictions

### Absolute restrictions
- Model is **never** loaded in the background
- Inference is **never** started in the background
- No `WorkManager` tasks that run AI inference
- No `AlarmManager` that triggers inference
- No push notification that preloads the model

### What background work IS allowed
- Model file download (WorkManager, wifi-required, not-low-battery)
- AI Lite heuristic computation (lightweight, < 5ms, triggered only from foreground)
- Model file integrity check on app update (fast checksum, no inference)

### Enforcement
The AI inference path has no background service component. The JNI engine is instantiated only inside `AIViewModel`, which is tied to `viewModelScope`. When the user leaves the AI screen and the ViewModel is cleared, the model unloads. There is no way for inference to run without an active ViewModel.

---

## Offline-Only Processing

### Network security config
```xml
<!-- res/xml/network_security_config.xml -->
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system"/>
        </trust-anchors>
    </base-config>
    <!-- AI inference path: no domain exceptions -->
</network-security-config>
```

The AI inference code path has zero outbound network calls. This is verified in CI by static analysis (no `HttpURLConnection`, `OkHttp`, or `Retrofit` imports in the `ai/` package) and confirmed via Android network security config.

### Runtime verification
In debug builds, a strict mode network policy is applied to the inference thread:
```kotlin
// Debug only
StrictMode.setThreadPolicy(
    StrictMode.ThreadPolicy.Builder()
        .detectNetwork()
        .penaltyDeath()
        .build()
)
```

Any accidental network call from the inference path crashes the debug build immediately.

---

## Optional Encrypted Local Model Storage

### Status: Future consideration (Phase 5+)

For users concerned about model file security (unlikely concern, but worth noting):

- Model files are GGUF weights — they contain no user data
- Encrypting the model file protects against an attacker extracting the model for redistribution, not against financial data exposure
- User financial data is in the Room database (already in app-private storage, not accessible without root)

### If implemented
- Use Android Keystore for key management
- AES-256-GCM encryption
- Key tied to device (not user account) — model must be re-downloaded if device is reset
- Encryption/decryption happens at model load time, not at inference time

This is a low-priority feature. The model file itself is public (downloadable from Hugging Face) — encrypting it provides minimal security value. Priority only if an enterprise/MDM use case requires it.

---

## Summary: Integration Phases

| Phase | What ships | Status |
|---|---|---|
| Phase 3 lab | Benchmarking only — no app code | In progress |
| Phase 3 acceptance | Model candidate selected — still no app code | Pending |
| Phase 4 v2.0.0 | JNI wrapper + LlamaJNI.kt + AIRepository.kt + AI screen | Planned |
| Phase 4 UI | AI Settings screen, model download flow, query UI | Planned |
| Phase 5 | Encrypted storage, multi-model support, custom fine-tune | Future |
