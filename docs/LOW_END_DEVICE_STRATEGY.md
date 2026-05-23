# Low-End Device Strategy — Personal Finance Assistant

Last updated: May 2026

---

## Philosophy

**A user on a ₹8,000 phone deserves the same financial tracking capability as a user on a ₹1,20,000 flagship.**

The Indian middle class — our core audience — uses a wide range of hardware. The majority of smartphone users in India are on devices with 3–4GB RAM, Snapdragon 4xx/6xx SoCs, and 32–64GB storage. These are not edge cases. They are the primary market.

Every core feature — SMS ingestion, categorisation, rules engine, dashboard, reports, backup — must work perfectly on the lowest supported device tier. AI features are an enhancement for users with capable hardware, not a gate that penalises users on affordable devices.

**The low-end device is the design constraint, not the exception.**

---

## Device Tier Definitions

### Tier 1 — Entry-Level (2–3GB RAM)
*Target devices: Redmi 9A, Realme C35, Samsung Galaxy A03, Tecno Pop 6*

| Property | Spec |
|---|---|
| RAM | 2–3GB |
| SoC | Snapdragon 439/460, MediaTek Helio G35/G37 |
| Storage | 32–64GB (often <10GB free after OS) |
| Android | 10–12 (Go Edition on some) |
| CPU cores | 4–8, ~1.8GHz max |
| Thermal | Limited cooling, throttles within 5 minutes of sustained load |

**AI capability: None.** This tier cannot run any local LLM — not even the smallest candidate. AI features are completely hidden, not disabled. The user sees no empty state, no locked icon, no upgrade prompt.

### Tier 2 — Mid-Range Budget (3–4GB RAM)
*Target devices: Redmi Note 11, Realme 9i, Samsung Galaxy A23, Moto G62*

| Property | Spec |
|---|---|
| RAM | 3–4GB |
| SoC | Snapdragon 680, MediaTek Helio G88/G96 |
| Storage | 64–128GB |
| Android | 11–13 |
| CPU cores | 8, ~2.4GHz max |
| Thermal | Moderate — throttles under sustained load |

**AI capability: AI Lite only.** Heuristic-based rule suggestions and spend summaries (no LLM). Local LLM is hidden. AI Lite features are free and run with zero additional RAM.

### Tier 3 — Mid-Range (4–6GB RAM)
*Target devices: Redmi Note 12 Pro, Realme GT Neo, Samsung Galaxy A54, Moto G84*

| Property | Spec |
|---|---|
| RAM | 4–6GB |
| SoC | Snapdragon 695/778G, MediaTek Dimensity 1080 |
| Storage | 128–256GB |
| Android | 12–14 |
| CPU cores | 8, ~2.8GHz max |
| Thermal | Good — can sustain load for 10+ minutes |

**AI capability: AI Lite + Local LLM (gated).** Local LLM is optionally enabled but requires explicit user opt-in and runtime validation. If the device fails the runtime RAM/performance check, Local LLM stays hidden. No degraded experience.

### Tier 4 — Flagship (6–8GB RAM)
*Target devices: OnePlus Nord 3, Samsung Galaxy S23 FE, Pixel 7a*

| Property | Spec |
|---|---|
| RAM | 6–8GB |
| SoC | Snapdragon 782G/8 Gen 1, Dimensity 9000 |
| Storage | 128–256GB |
| Android | 13–14 |
| CPU cores | 8, ~3.0GHz |
| Thermal | Good with brief peaks |

**AI capability: AI Lite + Local LLM (enabled).** Local LLM available after user opt-in. Model download prompted once after 30 days + 50 transactions (never during onboarding).

### Tier 5 — Premium Flagship (8GB+ RAM)
*Target devices: Samsung Galaxy S24 Ultra, OnePlus 12, Pixel 8 Pro, Nothing Phone 2a*

| Property | Spec |
|---|---|
| RAM | 8–16GB |
| SoC | Snapdragon 8 Gen 2/3, Dimensity 9200+ |
| Storage | 256GB+ |
| Android | 13–15 |
| CPU cores | 8, ~3.3GHz+ |
| Thermal | Excellent |

**AI capability: Full.** All AI features available. Best model candidate assigned. Model download prominently offered (but never forced) after establishing usage.

---

## AI Capability Summary

| Tier | RAM | Local LLM | AI Lite | Tracking | Reports |
|---|---|---|---|---|---|
| 1 — Entry | 2–3GB | Hidden | Hidden | Full | Full |
| 2 — Budget mid | 3–4GB | Hidden | Free | Full | Full |
| 3 — Mid-range | 4–6GB | Runtime-gated | Free | Full | Full |
| 4 — Flagship | 6–8GB | Premium opt-in | Free | Full | Full |
| 5 — Premium | 8GB+ | Premium opt-in | Free | Full | Full |

---

## AI Lite Mode (Tiers 2–5)

AI Lite delivers value without a model file. It runs on all devices from API 26 upward and requires no additional RAM.

### Features
- **Merchant rule suggestion**: "You've manually categorised BLINKIT as Grocery 8 times. Create a rule?"
- **Spend pattern summary**: "Food spend is 40% above your 3-month average this month"
- **Confidence score improvement**: Pattern-derived scoring updates from user correction signals
- **Duplicate detection tuning**: Learns user-confirmed duplicates to improve future detection

### Implementation
Pure Kotlin heuristics over local Room data. No model file, no inference library, no JNI. Ships in the same APK as the rest of the app.

### Resource constraints
| Metric | Budget |
|---|---|
| Additional RAM | 0MB |
| Additional APK size | < 50KB |
| Additional startup time | 0ms |
| Processing time per suggestion | < 5ms |
| Background processing | Never |

---

## No-LLM Fallback Architecture

The app is architected in layers. Each layer is independently functional:

```
Layer 3: Local LLM (Tier 3–5 only, opt-in, downloaded separately)
   ↓ absent = silently unavailable
Layer 2: AI Lite (Tier 2–5, free, built-in heuristics)
   ↓ absent = no visible change
Layer 1: Rules engine + category resolver (all tiers, always on)
   ↓ always present
Layer 0: Raw SMS/notification ingestion + manual entry (all tiers, core)
```

No layer depends on a layer above it. Removing the LLM layer leaves the app 100% functional. Removing AI Lite leaves the app fully functional with rule-based categorisation. The app is designed bottom-up — the AI layers are additions, not requirements.

### Feature gating implementation
```kotlin
// Pseudocode — runtime capability check
fun isLocalLLMEligible(context: Context): Boolean {
    val activityManager = context.getSystemService(ActivityManager::class.java)
    val memInfo = ActivityManager.MemoryInfo()
    activityManager.getMemoryInfo(memInfo)
    
    val totalRamGb = memInfo.totalMem / (1024f * 1024f * 1024f)
    val sdkVersion = Build.VERSION.SDK_INT
    
    return totalRamGb >= 6.0f && sdkVersion >= Build.VERSION_CODES.S
}
```

Check is performed once at app start and cached in DataStore. Result never blocks UI — features are silently hidden if check fails. The user never sees a loading state or an error.

---

## RAM Targets

### App RAM envelope (without LLM)
| State | Target | Hard Limit |
|---|---|---|
| Background / idle | < 50MB | 80MB |
| Dashboard active | < 80MB | 100MB |
| Transaction list (500 items) | < 90MB | 110MB |
| AI Lite suggestion running | < 85MB | 105MB |

### App RAM with Local LLM
| State | Target | Hard Limit |
|---|---|---|
| App active, AI screen open, model loaded | < 750MB | 800MB |
| Model loading | < 800MB peak | 900MB |
| After AI screen closed (model unloading) | < 100MB within 5min | — |
| After model fully unloaded | Same as without AI | — |

### Per-tier RAM allocation
| Tier | Device RAM | App ceiling | LLM budget | Remaining for OS/other apps |
|---|---|---|---|---|
| 1 | 2GB | 80MB | 0MB | 1.92GB |
| 2 | 3GB | 90MB | 0MB | 2.91GB |
| 3 | 4GB | 100MB | 700MB (opt-in) | 3.2GB / 3.9GB |
| 4 | 6GB | 100MB | 750MB | 5.15GB |
| 5 | 8GB+ | 100MB | 800MB | 7.1GB+ |

---

## Storage Targets

### App storage (all tiers)
| Component | Target |
|---|---|
| APK size | < 20MB |
| Cold install DB footprint | < 5MB |
| DB per 1,000 transactions | < 2MB |
| App total (1 year of data) | < 30MB |

### LLM model files (Tier 3–5 only)
| Model | Size | Minimum free storage before download |
|---|---|---|
| Qwen2.5 1.5B Q4_K_M | ~1.0GB | 2GB (1GB model + 1GB safety buffer) |
| TinyLlama 1.1B Q4_K_M | ~670MB | 1.5GB |
| Qwen2.5 0.5B Q4_K_M | ~400MB | 1GB |

If device has less than 2GB free, model download is blocked with a clear message. Model files are stored in the app's external files directory (`getExternalFilesDir()`), visible in Settings → Apps → Personal Finance Assistant → Storage.

---

## Battery Targets

### All tiers (no LLM)
| Operation | Target |
|---|---|
| Background drain per hour | < 0.1% |
| Foreground active session per hour | < 0.5% |
| SMS ingestion (per message) | Negligible (< 0.01%) |
| No wake locks held during idle | Required |
| No persistent foreground service | Required |

### Tiers 3–5 (with LLM)
| Operation | Target |
|---|---|
| Battery drain per AI query | < 0.5% |
| Battery drain per hour with AI screen open (no queries) | < 0.2% (model loaded but idle) |
| Battery drain per hour of AI background activity | 0% (AI never runs in background) |

---

## Graceful Degradation Philosophy

### What "graceful" means
When a device cannot run a feature, the user experiences the absence of that feature — not a failure. There are no:
- Error messages ("Your device doesn't support AI")
- Locked icons with upgrade prompts
- Empty states where AI features would be
- Performance degradation from feature checks that fail

### Degradation decision tree
```
Device RAM < 4GB?
  └── Yes → Show no AI UI at all. Full tracking works normally.

Device RAM 4–6GB and runtime check passes?
  └── Show Local LLM option in Settings (premium, opt-in)
  └── If user opts in, attempt model download
  └── If performance test fails post-download → hide LLM, keep model file for retry

Device RAM ≥ 6GB?
  └── Show full AI UI after 30 days + 50 transactions
  └── Never prompt during onboarding
```

### Feature gating is silently checked, never loudly declared
A Tier 1 user never sees anything that tells them they are on a low-end device. They see a fully functional finance app. The AI features simply don't exist for them — like a feature that hasn't been built yet.

---

## Future: Low-End AI Candidate (Qwen2.5 0.5B)

The 0.5B model at Q4_K_M is ~400MB on disk and potentially runnable on 3GB RAM devices. This is an experimental candidate — it may not meet finance quality thresholds — but it is worth benchmarking.

If it passes quality and performance criteria, it could enable a "AI Lite Plus" tier for budget mid-range devices that is still fully on-device, free, and private.

This evaluation is deferred to Phase 3 benchmarking. See `docs/AI_BENCHMARK_PROTOCOL.md` for the test protocol.
