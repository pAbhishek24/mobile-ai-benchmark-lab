# Methodology v2 — Release Notes

## Why v2 Was Introduced

The original benchmark runs (v1) were collected without explicit environment metadata or benchmark mode tagging. This made it impossible to:

1. **Compare apples to apples** — a run collected with 30+ background apps and thermal throttling engaged cannot be fairly compared to a run on a cold, freshly rebooted device.
2. **Isolate model performance** — without knowing the device state, latency deltas between models could be caused by OS interference rather than model architecture differences.
3. **Build a rerun schedule** — without a declared methodology, it was unclear which runs needed to be repeated under controlled conditions.

v2 introduces explicit tagging of every run so the dashboard can filter and compare runs by methodology.

## v2 Schema Fields

Every v2 benchmark run includes the following fields in `benchmark.jsonl`, `summary.csv`, `summary.md`, and both snapshot files:

| Field | Type | Description |
|---|---|---|
| `methodology_version` | string | Always `"v2"` for new runs |
| `benchmark_mode` | string | `real_world` or `controlled` |
| `post_reboot` | bool | Was the device freshly rebooted before this run? |
| `airplane_mode` | bool | Was airplane mode enabled? |
| `background_apps_estimate` | bool | Were background apps running? |
| `run_notes` | string | Free-text notes for the run |

Snapshots (`snapshot_before.json`, `snapshot_after.json`) include an `"environment"` key with all the above fields.

## How Legacy Runs Are Handled

Runs without `methodology_version` in their JSONL data are treated as:

- `methodology_version = "v1"`
- `benchmark_mode = "unknown"`
- Environment metadata fields are `null`

**Old data is never deleted or modified.** The aggregation scripts read whatever fields are present and backfill defaults for missing ones. v1 runs remain fully visible in dashboards but are excluded from controlled/v2-only comparison views.

## real_world vs controlled: How They Differ

### real_world (default)
- `--benchmark-mode real_world`
- Background Samsung and Google services active
- No forced device reboot before run
- Screen on, One UI thermal management engaged
- Represents what a real consumer would experience
- **Use for**: end-user experience benchmarks, thermal stress testing, realistic performance baselines

### controlled
- `--benchmark-mode controlled --post-reboot true --airplane-mode true --background-apps false`
- Airplane mode on (no network activity, no push notifications)
- Fresh reboot before run (clears RAM, resets thermal baseline)
- Minimize all background apps possible
- Screen brightness at minimum (reduce heat generation)
- **Use for**: isolating model performance, architecture comparisons, reproducible results

## What Data Should Be Rerun

The following models need v2 reruns to establish controlled baselines:

| Model | real_world v2 | controlled v2 | Priority |
|---|---|---|---|
| qwen2.5-0.5b-q4km | needed | needed | HIGH |
| qwen2.5-1.5b-q4km | needed | needed | HIGH |
| tinyllama-1.1b-q4km | needed | needed | HIGH |
| qwen2.5-3b-q4km | needed | needed | MEDIUM |
| phi3-mini-q4km | needed | needed | MEDIUM |
| llama3.2-1b-q4km | needed | needed | MEDIUM |
| llama3.2-3b-q4km | needed | needed | LOW |

Existing v1 runs provide a real_world baseline but lack the explicit `post_reboot=false` and `airplane_mode=false` tags required for v2 comparison. Run at minimum the top 3 models in both modes to establish the comparison dataset.

## Run Commands (on mobile device)

### real_world run (v2):
```bash
cd ~/mobile-ai-benchmark-lab
./ai-lab/scripts/run_model_evaluation.sh \
  --model qwen2.5-0.5b-q4km \
  --device-label samsung-s24-ultra \
  --profile quality \
  --benchmark-mode real_world \
  --background-apps true \
  --post-reboot false \
  --airplane-mode false \
  --notes "v2 real_world baseline"
```

### controlled run (v2):
```bash
# Step 1: Reboot device
# Step 2: Enable airplane mode
# Step 3: Wait 5 minutes for thermal cooldown
# Step 4:
cd ~/mobile-ai-benchmark-lab
./ai-lab/scripts/run_model_evaluation.sh \
  --model qwen2.5-0.5b-q4km \
  --device-label samsung-s24-ultra \
  --profile quality \
  --benchmark-mode controlled \
  --background-apps false \
  --post-reboot true \
  --airplane-mode true \
  --notes "v2 controlled baseline"
```

## Controlled Mode Checklist

Before running a controlled benchmark:
- [ ] Reboot device (do not open any apps after reboot)
- [ ] Enable Airplane Mode
- [ ] Wait ≥ 5 minutes for thermal baseline (check temp < 35°C)
- [ ] Reduce screen brightness to minimum
- [ ] Do not touch the device during the run
- [ ] Plug charger only if needed (note: affects thermal + power mode)
- [ ] Use `--post-reboot true --airplane-mode true --background-apps false`

## real_world Mode Checklist

For consistent real_world runs:
- [ ] Use device normally for ≥ 30 minutes before run (warm start)
- [ ] Do NOT force-close background apps
- [ ] Keep screen on at normal brightness
- [ ] WiFi connected (realistic consumer state)
- [ ] Use `--post-reboot false --airplane-mode false --background-apps true`
- [ ] Note: results will vary by 5–15% across runs due to OS state
