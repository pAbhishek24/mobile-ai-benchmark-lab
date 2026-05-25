# AI Lab Benchmark Summary

| Field | Value |
|---|---|
| Device | `samsung-s24-ultra` |
| Model | `qwen2.5-0.5b-q4km` (468 MB) |
| llama.cpp | `/data/data/com.termux/files/home/llama.cpp/build/bin/llama-cli` |
| Profile | quality |
| Benchmark Mode | real_world |
| Max tokens | 512 |
| Threads | 4 |
| Prompt timeout | 180s |
| Output capture | 20/20 prompts have non-empty output |
| Max temp (snapshot before) | 60.1 °C |
| Max temp (snapshot after) | 49.9 °C |

## Results

| Metric | Value |
|---|---|
| Total prompts | 20 |
| ✅ Success | 19 |
| ⏱ Timeout | 1 |
| ❌ Error | 0 |
| 🌡 Thermal warnings | 14 |
| p50 duration | 51501 ms |
| p50 tokens/sec | 35.77 |

## Per-Prompt

| Prompt | Status | Duration (ms) | Tok/s | Timed out |
|---|---|---:|---:|:---:|
| P01 | ✅ ok | 181353 | 8.86 | no |
| P02 | ✅ ok | 12792 | 48.44 | no |
| P03 | ✅ ok | 62037 | 37.8 | no |
| P04 | ✅ ok | 17905 | 34.02 | no |
| P05 | ✅ ok | 109306 | 47.96 | no |
| P06 | ✅ ok | 169704 | 15.44 | no |
| P07 | ✅ ok | 349127 | 8.4 | no |
| P08 | ✅ ok | 55359 | 10.14 | no |
| P09 | ✅ ok | 51501 | 12.98 | no |
| P10 | ✅ ok | 202119 | 35.77 | no |
| P11 | ✅ ok | 14880 | 47.24 | no |
| P12 | ✅ ok | 49099 | 42.33 | no |
| P13 | ✅ ok | 13912 | 46.82 | no |
| P14 | ✅ ok | 168126 | 19.52 | no |
| P15 | ✅ ok | 31977 | 17.49 | no |
| P16 | ✅ ok | 13191 | 47.88 | no |
| P17 | ✅ ok | 25340 | 41.57 | no |
| P18 | ⏱ timeout | 242952 |  | yes |
| P19 | ✅ ok | 52259 | 35.25 | no |
| P20 | ✅ ok | 14721 | 43.51 | no |
