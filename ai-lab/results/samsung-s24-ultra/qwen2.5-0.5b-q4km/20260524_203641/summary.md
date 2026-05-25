# AI Lab Benchmark Summary

| Field | Value |
|---|---|
| Device | `samsung-s24-ultra` |
| Model | `qwen2.5-0.5b-q4km` (468 MB) |
| llama.cpp | `/data/data/com.termux/files/home/llama.cpp/build/bin/llama-cli` |
| Max tokens | 48 |
| Threads | 4 |
| Prompt timeout | 90s |
| Output capture | 2/2 prompts have non-empty output |
| Max temp (snapshot before) | 50.6 °C |
| Max temp (snapshot after) | 43.2 °C |

## Results

| Metric | Value |
|---|---|
| Total prompts | 2 |
| ✅ Success | 2 |
| ⏱ Timeout | 0 |
| ❌ Error | 0 |
| 🌡 Thermal warnings | 0 |
| p50 duration | 3086 ms |
| p50 tokens/sec | 50.81 |

## Per-Prompt

| Prompt | Status | Duration (ms) | Tok/s | Timed out |
|---|---|---:|---:|:---:|
| P01 | ✅ ok | 3086 | 50.81 | no |
| P02 | ✅ ok | 3020 | 42.89 | no |
