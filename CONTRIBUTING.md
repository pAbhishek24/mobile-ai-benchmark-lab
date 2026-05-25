# Contributing to Mobile AI Benchmark Lab

Thank you for contributing! This project is built on real device data — every result matters.

## What we welcome

- **New device results** — run the benchmark on your Android device and submit results
- **New model variants** — GGUF quantisations not yet in the registry
- **Prompt set improvements** — better, more representative finance prompts
- **Dashboard enhancements** — new visualisations, better UX
- **Bug fixes** — benchmark script issues, scoring bugs, data pipeline fixes
- **Documentation** — setup guides, methodology notes, device-specific tips

## How to submit benchmark results

1. Fork the repo
2. Run the benchmark: `bash ai-lab/scripts/run_llama_benchmark.sh --help`
3. Results are saved to `ai-lab/results/<device>/<model>/<timestamp>/`
4. Run the scoring script: `python3 ai-lab/analytics/compute_scores.py`
5. Open a PR with your results folder — title format: `[result] <device> <model> <quant>`

Include in your PR description:
- Device model and Android version
- RAM and storage available during run
- Ambient temperature / whether device was charging
- Any anomalies or throttling observed

## Adding a new model to the registry

Edit `ai-lab/models/model-registry.json` and add an entry:
```json
{
  "id": "your-model-q4km",
  "name": "ModelName",
  "family": "family",
  "params_b": 1.5,
  "quant": "Q4_K_M",
  "size_gb": 1.0,
  "source": "huggingface/repo"
}
```

## Code style

- Shell scripts: follow the existing style in `ai-lab/scripts/`
- Python: PEP 8, no external dependencies beyond stdlib
- Dashboard: vanilla JS only, no framework dependencies

## Code of Conduct

See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
