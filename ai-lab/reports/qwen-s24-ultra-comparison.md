# Qwen Benchmarks: Samsung S24 Ultra (Termux + llama.cpp)

Branch: `phase-3-ai-lab`  
Device label: `samsung-s24-ultra` (SM-S928B)

This report compares the **latest pushed** benchmark result folders under:
- `ai-lab/results/samsung-s24-ultra/qwen2.5-1.5b-q4km/`
- `ai-lab/results/samsung-s24-ultra/qwen2.5-0.5b-q4km/`

## Result Folders Used (Latest)

- Qwen2.5 1.5B Q4_K_M: `ai-lab/results/samsung-s24-ultra/qwen2.5-1.5b-q4km/20260524_105125/`
- Qwen2.5 0.5B Q4_K_M: `ai-lab/results/samsung-s24-ultra/qwen2.5-0.5b-q4km/20260524_105517/`

## Executive Summary

Both runs currently show **0/20 prompts succeeded** (100% failure) and **blank outputs**, so:
- tokens/sec cannot be computed
- quality scoring cannot be performed
- these results are **not production-evaluable yet**

However, we can still compare:
- model sizes
- time-to-failure behavior (total benchmark duration)
- baseline thermals/memory snapshots before/after the attempted run

## Key Metrics

| Metric | Qwen2.5 1.5B (q4km) | Qwen2.5 0.5B (q4km) |
|---|---:|---:|
| Model size (MB) | 1065 | 468 |
| Prompts attempted | 20 | 20 |
| Success / Fail | 0 / 20 | 0 / 20 |
| Total benchmark time (sum of per-prompt duration_ms) | 984 ms | 764 ms |
| Avg tokens/sec | n/a (no successful runs) | n/a (no successful runs) |
| Fastest prompt | P05 (41 ms) | P01 (36 ms) |
| Slowest prompt | P12 (62 ms) | P10 (41 ms) |

### Failure Analysis (Most Important)

Both `summary.csv` files report the llama.cpp binary as:

`/data/data/com.termux/files/home/llama.cpp/build/bin/llava-cli`

These are **text-only GGUF models**, so selecting `llava-cli` is likely the reason every run fails immediately and produces no output.

Action item:
- Rerun using `llama-cli` (or `main`) for text models.

## Snapshots (Before vs After)

Battery metrics were `unknown` in snapshots (likely Termux API not installed or permission not granted).

### Thermal (max of captured zones)

| Model | Max temp before (°C) | Max temp after (°C) | Delta |
|---|---:|---:|---:|
| Qwen2.5 1.5B | 48.7 | 47.5 | -1.2 |
| Qwen2.5 0.5B | 56.1 | 54.6 | -1.5 |

Interpretation:
- Because the benchmark appears to fail immediately, thermal changes here are not meaningful for sustained inference performance.
- The 0.5B run started from a hotter baseline.

### Memory (available_mb)

| Model | Available before (MB) | Available after (MB) | Delta |
|---|---:|---:|---:|
| Qwen2.5 1.5B | 2827 | 2798 | -29 |
| Qwen2.5 0.5B | 2708 | 2743 | +35 |

Again, given immediate failures, this is not representative of real inference memory pressure.

## Recommendation

### Best quality candidate (once runner is fixed)
- **Qwen2.5 1.5B (q4km)** is the best quality candidate of the two, assuming it runs successfully under `llama-cli`.

### Best speed candidate (once runner is fixed)
- **Qwen2.5 0.5B (q4km)** should be the fastest on-device, and is the better low-end candidate.

### Low-end candidate
- **Qwen2.5 0.5B (q4km)**.

### Production-safety status
- **Not production-safe yet**: these runs are invalid for evaluation because success rate is 0% and outputs are empty.

## Recommended Next Model / Next Run

Next run (highest priority) is **Qwen2.5 1.5B** again, but forcing `llama-cli`:
- confirm the runner chooses `llama-cli` for text models
- ensure non-empty outputs
- get tokens/sec and latency distributions

After that, add a third comparison model:
- `llama3.2-1b-q4km` as an alternative small instruct model baseline

