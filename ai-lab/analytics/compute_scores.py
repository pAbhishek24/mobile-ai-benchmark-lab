#!/usr/bin/env python3
"""
Compute weighted benchmark scores for all models in a given device context.

Reads:  dashboards/data/dashboard-data.json  (produced by generate_dashboard_data.py)
Writes: dashboards/data/scores.json  (ranked scores per model per device)
        Also annotates models with their weighted_score in dashboard-data.json.
Prints: ranked table to stdout.

Scoring weights (all 0–1 normalised within the same device):
  speed              25%   avg tok/s (higher = better)
  thermal_efficiency 25%   lower temp rise is better (0 rise = 1.0, >=15°C rise = 0.0)
  stability          20%   success / total prompts
  output_success     20%   output_present / total prompts
  memory_efficiency  10%   smaller model file = better (inverted, normalised)

Models with zero successes receive speed=0, stability=0, output_success=0 automatically,
making them non-candidates regardless of other metrics.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = REPO_ROOT / "dashboards" / "data"
DASHBOARD_JSON = DATA_DIR / "dashboard-data.json"
SCORES_JSON = DATA_DIR / "scores.json"

WEIGHTS = {
    "speed": 0.25,
    "thermal_efficiency": 0.25,
    "stability": 0.20,
    "output_success": 0.20,
    "memory_efficiency": 0.10,
}

# Thermal cap: delta >= THERMAL_CAP_C maps to score 0.0
THERMAL_CAP_C = 15.0


# ---------------------------------------------------------------------------
# Raw metric extraction
# ---------------------------------------------------------------------------

def _extract_raw(model_entry: Dict[str, Any]) -> Dict[str, Optional[float]]:
    """Pull the raw numbers we need from a model_summary entry."""
    d = model_entry.get("derived", {})
    total = d.get("prompts") or 0
    success = d.get("success") or 0
    output_present = d.get("output_present") or 0
    avg_tok = d.get("avg_tokens_per_sec")  # may be None
    size_mb = model_entry.get("size_mb")   # may be None

    temp_before = d.get("max_temp_before_c")
    temp_after = d.get("max_temp_after_c")
    temp_delta: Optional[float] = None
    if temp_before is not None and temp_after is not None:
        temp_delta = temp_after - temp_before

    stability = (success / total) if total > 0 else 0.0
    output_rate = (output_present / total) if total > 0 else 0.0

    return {
        "avg_tok_s": float(avg_tok) if (avg_tok is not None and success > 0) else 0.0,
        "temp_delta_c": temp_delta,
        "stability": stability,
        "output_rate": output_rate,
        "size_mb": float(size_mb) if size_mb is not None else None,
        "success": success,
        "total": total,
    }


# ---------------------------------------------------------------------------
# Normalisation helpers
# ---------------------------------------------------------------------------

def _normalise_minmax(value: float, lo: float, hi: float) -> float:
    """Linear normalise value to [0, 1].  Returns 0.5 if lo == hi."""
    if hi == lo:
        return 0.5
    return max(0.0, min(1.0, (value - lo) / (hi - lo)))


def _thermal_score(delta: Optional[float]) -> float:
    """Convert a temperature rise (°C) to a 0–1 score (lower rise = higher score)."""
    if delta is None:
        # No thermal data — treat as neutral (middle score) so a missing snapshot
        # doesn't completely tank an otherwise good model.
        return 0.5
    if delta <= 0.0:
        return 1.0
    if delta >= THERMAL_CAP_C:
        return 0.0
    return 1.0 - (delta / THERMAL_CAP_C)


# ---------------------------------------------------------------------------
# Per-device scoring
# ---------------------------------------------------------------------------

def score_device_models(
    models: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """
    Given a flat list of model_summary dicts (all from the same device),
    compute and return scored entries sorted by weighted_score descending.

    Each returned dict is the original model_summary extended with a
    'scoring' sub-dict containing raw metrics, component scores, and the
    final weighted_score.
    """
    raws = [_extract_raw(m) for m in models]

    # --- speed: normalise avg_tok_s across all models in this device context ---
    tok_vals = [r["avg_tok_s"] for r in raws]
    tok_lo, tok_hi = min(tok_vals), max(tok_vals)

    # --- memory efficiency: normalise size_mb (inverted — smaller = better) ---
    size_vals = [r["size_mb"] for r in raws if r["size_mb"] is not None]
    size_lo = min(size_vals) if size_vals else None
    size_hi = max(size_vals) if size_vals else None

    results = []
    for model, raw in zip(models, raws):
        # Speed score
        speed_score = _normalise_minmax(raw["avg_tok_s"], tok_lo, tok_hi)

        # Thermal efficiency
        thermal_score = _thermal_score(raw["temp_delta_c"])

        # Stability
        stability_score = raw["stability"]

        # Output success
        output_score = raw["output_rate"]

        # Memory efficiency (inverted: smaller model = higher score)
        if size_lo is not None and size_hi is not None and raw["size_mb"] is not None:
            # Invert: use (hi - val) / (hi - lo) so smallest = 1.0
            mem_score = _normalise_minmax(size_hi - raw["size_mb"], 0.0, size_hi - size_lo)
        else:
            mem_score = 0.5  # neutral when size unknown

        # Weighted total
        weighted = (
            WEIGHTS["speed"] * speed_score
            + WEIGHTS["thermal_efficiency"] * thermal_score
            + WEIGHTS["stability"] * stability_score
            + WEIGHTS["output_success"] * output_score
            + WEIGHTS["memory_efficiency"] * mem_score
        )

        import copy
        scored = copy.deepcopy(model)
        scored["scoring"] = {
            "raw": {
                "avg_tok_s": raw["avg_tok_s"],
                "temp_delta_c": raw["temp_delta_c"],
                "stability": raw["stability"],
                "output_rate": raw["output_rate"],
                "size_mb": raw["size_mb"],
            },
            "components": {
                "speed": round(speed_score, 4),
                "thermal_efficiency": round(thermal_score, 4),
                "stability": round(stability_score, 4),
                "output_success": round(output_score, 4),
                "memory_efficiency": round(mem_score, 4),
            },
            "weights": WEIGHTS,
            "weighted_score": round(weighted, 4),
        }
        results.append(scored)

    results.sort(key=lambda x: x["scoring"]["weighted_score"], reverse=True)
    for rank, entry in enumerate(results, start=1):
        entry["scoring"]["rank"] = rank

    return results


# ---------------------------------------------------------------------------
# Pretty-print ranked table
# ---------------------------------------------------------------------------

def _print_table(device: str, scored_models: List[Dict[str, Any]]) -> None:
    header = f"\n{'='*72}\nDevice: {device}\n{'='*72}"
    print(header)
    col_fmt = "{:<28} {:>6} {:>7} {:>8} {:>9} {:>10} {:>7} {:>5}"
    print(col_fmt.format(
        "Model", "Score", "tok/s", "Thermal", "Stability", "Output", "MemEff", "Rank"
    ))
    print("-" * 72)
    for entry in scored_models:
        s = entry["scoring"]
        c = s["components"]
        r = s["raw"]
        model_name = entry.get("model", "?")
        tok_s_str = f"{r['avg_tok_s']:.1f}" if r["avg_tok_s"] else "  n/a"
        print(col_fmt.format(
            model_name[:28],
            f"{s['weighted_score']:.3f}",
            tok_s_str,
            f"{c['thermal_efficiency']:.3f}",
            f"{c['stability']:.3f}",
            f"{c['output_success']:.3f}",
            f"{c['memory_efficiency']:.3f}",
            s["rank"],
        ))
    print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def compute_scores(
    dashboard_json_path: Path = DASHBOARD_JSON,
    scores_json_path: Path = SCORES_JSON,
    update_dashboard: bool = True,
) -> Dict[str, Any]:
    """
    Load dashboard-data.json, compute scores, write scores.json, and optionally
    annotate dashboard-data.json with scoring results.

    Returns the full scores dict (keyed by device).
    """
    if not dashboard_json_path.exists():
        print(
            f"ERROR: {dashboard_json_path} not found.\n"
            "Run generate_dashboard_data.py first.",
            file=sys.stderr,
        )
        sys.exit(1)

    data = json.loads(dashboard_json_path.read_text(encoding="utf-8"))

    # Support both 'model_summaries' (new format) and legacy 'runs' arrays
    model_summaries: List[Dict[str, Any]] = data.get("model_summaries") or []
    if not model_summaries:
        # Fall back to runs format — group by device and take latest run per model
        runs = data.get("runs") or []
        by_device_model: Dict[Tuple[str, str], Dict[str, Any]] = {}
        for run in runs:
            key = (run.get("device", "unknown"), run.get("model", "unknown"))
            if key not in by_device_model:
                by_device_model[key] = run
            else:
                # Keep latest timestamp
                if str(run.get("timestamp", "")) > str(by_device_model[key].get("timestamp", "")):
                    by_device_model[key] = run
        model_summaries = list(by_device_model.values())

    if not model_summaries:
        print("WARNING: No model data found in dashboard-data.json.", file=sys.stderr)

    # Group by device
    by_device: Dict[str, List[Dict[str, Any]]] = {}
    for entry in model_summaries:
        device = entry.get("device", "unknown")
        by_device.setdefault(device, []).append(entry)

    scores_by_device: Dict[str, Any] = {}

    for device, models in sorted(by_device.items()):
        scored = score_device_models(models)
        scores_by_device[device] = scored
        _print_table(device, scored)

    # Write scores.json
    scores_json_path.parent.mkdir(parents=True, exist_ok=True)
    scores_output = {
        "generated_by": "compute_scores.py",
        "weights": WEIGHTS,
        "thermal_cap_c": THERMAL_CAP_C,
        "scores_by_device": scores_by_device,
    }
    scores_json_path.write_text(
        json.dumps(scores_output, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Wrote {scores_json_path}")

    # Optionally annotate dashboard-data.json with scores
    if update_dashboard:
        # Build lookup: (device, model) -> scoring
        lookup: Dict[Tuple[str, str], Dict[str, Any]] = {}
        for device, scored_list in scores_by_device.items():
            for entry in scored_list:
                lookup[(device, entry.get("model", ""))] = entry.get("scoring", {})

        # Annotate model_summaries in-place
        for entry in data.get("model_summaries", []):
            key = (entry.get("device", ""), entry.get("model", ""))
            if key in lookup:
                entry["scoring"] = lookup[key]

        # Also annotate runs if present
        for run in data.get("runs", []):
            key = (run.get("device", ""), run.get("model", ""))
            if key in lookup:
                run["scoring"] = lookup[key]

        dashboard_json_path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"Updated {dashboard_json_path} with scoring annotations")

    return scores_by_device


def main() -> None:
    compute_scores()


if __name__ == "__main__":
    main()
