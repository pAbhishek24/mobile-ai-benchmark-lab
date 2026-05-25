#!/usr/bin/env python3
"""
generate_dashboard_data.py — canonical pipeline for producing dashboard-data.json.

What it does (in order):
  1. Aggregates all benchmark runs under ai-lab/results/ (via aggregate_results logic)
  2. Builds per-model summaries (latest run per device+model, with merged metrics)
  3. Computes weighted scores (via compute_scores logic)
  4. Writes dashboards/data/dashboard-data.json — the single source of truth for the dashboard

Output format of dashboard-data.json:
  {
    "generated_at": "...",
    "generated_by": "generate_dashboard_data.py",
    "benchmark_context": { ... },
    "runs": [ ... ],          // all individual runs (from aggregate_results)
    "model_summaries": [ ... ],// one entry per (device, model) — best/latest run merged
    "scores_by_device": { ... } // weighted scores keyed by device
  }

Usage:
  python3 ai-lab/analytics/generate_dashboard_data.py        # from repo root
  python3 ai-lab/analytics/generate_dashboard_data.py --dry-run
"""

from __future__ import annotations

import argparse
import copy
import json
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
RESULTS_ROOT = REPO_ROOT / "ai-lab" / "results"
DATA_DIR = REPO_ROOT / "dashboards" / "data"
DASHBOARD_JSON = DATA_DIR / "dashboard-data.json"

# ---------------------------------------------------------------------------
# Benchmark context (static metadata — describes run conditions)
# ---------------------------------------------------------------------------

BENCHMARK_CONTEXT: Dict[str, Any] = {
    "background_apps_estimate": True,
    "charging": False,
    "screen_on": True,
    "power_mode": "optimized",
    "benchmark_mode": "real_world",
    "notes": (
        "Results collected on a Samsung Galaxy S24 Ultra (SM-S928B) running Samsung One UI. "
        "No clean-room isolation: background Samsung and Google services were active, "
        "no reboot before each run, One UI thermal management engaged. "
        "Numbers represent realistic consumer-device performance — conservative vs clean-room."
    ),
}

# ---------------------------------------------------------------------------
# Inline aggregate_results logic (mirrors aggregate_results.py without importing)
# ---------------------------------------------------------------------------

def _read_json(path: Path) -> Optional[Dict[str, Any]]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _read_jsonl(path: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                pass
    except FileNotFoundError:
        pass
    return rows


def _read_summary_csv(path: Path) -> Optional[Dict[str, Any]]:
    if not path.exists():
        return None
    try:
        import csv
        with path.open("r", encoding="utf-8", newline="") as f:
            r = csv.reader(f)
            header = next(r, None)
            if not header:
                return None
            values = next(r, None)
            if not values:
                return None
            return dict(zip(header, values))
    except Exception:
        return None


def _p50(values: List[float]) -> Optional[float]:
    if not values:
        return None
    s = sorted(values)
    return s[len(s) // 2]


def _p95(values: List[float]) -> Optional[float]:
    if not values:
        return None
    s = sorted(values)
    return s[min(int(len(s) * 0.95), len(s) - 1)]


def _max_temp(snapshot: Optional[Dict[str, Any]]) -> Optional[float]:
    if not snapshot:
        return None
    zones = snapshot.get("thermal", {}).get("zones", [])
    if not isinstance(zones, list) or not zones:
        return None
    temps: List[float] = []
    for z in zones:
        try:
            temps.append(float(z.get("temp_c")))
        except Exception:
            pass
    return max(temps) if temps else None


def _thermal_bucket(max_c: Optional[float]) -> str:
    if max_c is None:
        return "unknown"
    if max_c > 60.0:
        return "red"
    if max_c > 55.0:
        return "yellow"
    return "green"


def _safe_int(v: Any) -> Optional[int]:
    try:
        if v is None or v == "":
            return None
        return int(float(v))
    except Exception:
        return None


def _min_snapshot(s: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if not s:
        return None
    return {
        "timestamp": s.get("timestamp"),
        "device": s.get("device", {}),
        "cpu": s.get("cpu", {}),
        "memory": s.get("memory", {}),
        "battery": s.get("battery", {}),
        "thermal": {
            "android_status": s.get("thermal", {}).get("android_status"),
            "zones": s.get("thermal", {}).get("zones", []),
        },
    }


def _aggregate_run(run_dir: Path) -> Dict[str, Any]:
    device = run_dir.parent.parent.name
    model = run_dir.parent.name
    ts = run_dir.name

    summary = _read_summary_csv(run_dir / "summary.csv") or {}
    bench_rows = _read_jsonl(run_dir / "benchmark.jsonl")
    snap_before = _read_json(run_dir / "snapshot_before.json")
    snap_after = _read_json(run_dir / "snapshot_after.json")

    durations: List[float] = []
    tokps: List[float] = []
    statuses: Dict[str, int] = {"ok": 0, "timeout": 0, "error": 0}
    thermal_warn_count = 0
    output_present = 0
    output_word_counts: List[int] = []
    prompt_results: List[Dict[str, Any]] = []

    for r in bench_rows:
        status = r.get("status")
        if status in statuses:
            statuses[status] += 1
        else:
            statuses["error"] += 1

        try:
            if status == "ok":
                durations.append(float(r.get("duration_ms", 0)))
                v = r.get("tokens_per_sec")
                if v is not None and float(v) > 0:
                    tokps.append(float(v))
        except Exception:
            pass

        out = (r.get("output") or "").strip()
        if out:
            output_present += 1
            output_word_counts.append(len(out.split()))
        if bool(r.get("thermal_warning")):
            thermal_warn_count += 1

        tok_val = r.get("tokens_per_sec")
        prompt_results.append({
            "prompt_id": r.get("prompt_id"),
            "status": r.get("status"),
            "duration_ms": r.get("duration_ms"),
            "tokens_per_sec": float(tok_val) if tok_val is not None and float(tok_val) > 0 else None,
            "out_words": len(out.split()) if out else 0,
            "thermal_warning": bool(r.get("thermal_warning")),
        })

    p50_dur = _p50(durations)
    p95_dur = _p95(durations)
    p50_tok = _p50(tokps)
    avg_tok = statistics.mean(tokps) if tokps else None
    avg_output_words = round(statistics.mean(output_word_counts), 1) if output_word_counts else None
    total_time_ms = (
        int(sum(float(r.get("duration_ms", 0) or 0) for r in bench_rows))
        if bench_rows
        else None
    )

    max_before = _max_temp(snap_before)
    max_after = _max_temp(snap_after)

    ram_before = snap_before.get("memory", {}).get("used_mb") if snap_before else None
    ram_after = snap_after.get("memory", {}).get("used_mb") if snap_after else None
    ram_delta_mb = int(ram_after - ram_before) if (ram_before is not None and ram_after is not None) else None

    return {
        "device": device,
        "model": model,
        "timestamp": ts,
        "run_dir": str(run_dir.relative_to(REPO_ROOT)).replace("\\", "/"),
        "files": {
            "benchmark_jsonl": (run_dir / "benchmark.jsonl").exists(),
            "summary_csv": (run_dir / "summary.csv").exists(),
            "summary_md": (run_dir / "summary.md").exists(),
            "snapshot_before": (run_dir / "snapshot_before.json").exists(),
            "snapshot_after": (run_dir / "snapshot_after.json").exists(),
        },
        "quality_score": None,
        "summary": {**summary},
        "derived": {
            "prompts": len(bench_rows) if bench_rows else _safe_int(summary.get("prompts")),
            "success": statuses["ok"],
            "timeout": statuses["timeout"],
            "error": statuses["error"],
            "total_time_ms": total_time_ms,
            "p50_duration_ms": p50_dur,
            "p95_duration_ms": p95_dur,
            "p50_tokens_per_sec": p50_tok,
            "avg_tokens_per_sec": avg_tok,
            "avg_output_words": avg_output_words,
            "output_present": output_present,
            "thermal_warning_count": thermal_warn_count,
            "max_temp_before_c": max_before,
            "max_temp_after_c": max_after,
            "thermal_before_bucket": _thermal_bucket(max_before),
            "thermal_after_bucket": _thermal_bucket(max_after),
            "ram_delta_mb": ram_delta_mb,
            "prompt_results": prompt_results,
        },
        "snapshot_before": _min_snapshot(snap_before),
        "snapshot_after": _min_snapshot(snap_after),
    }


def find_and_aggregate_runs() -> List[Dict[str, Any]]:
    if not RESULTS_ROOT.exists():
        return []
    runs: List[Path] = []
    for device_dir in RESULTS_ROOT.iterdir():
        if not device_dir.is_dir():
            continue
        for model_dir in device_dir.iterdir():
            if not model_dir.is_dir():
                continue
            for run_dir in model_dir.iterdir():
                if not run_dir.is_dir():
                    continue
                if (run_dir / "benchmark.jsonl").exists() or (run_dir / "summary.csv").exists():
                    runs.append(run_dir)
    runs.sort(key=lambda p: (p.parent.parent.name, p.parent.name, p.name))
    return [_aggregate_run(r) for r in runs]


# ---------------------------------------------------------------------------
# Model registry enrichment
# ---------------------------------------------------------------------------

def _load_model_registry() -> Dict[str, Any]:
    reg_path = REPO_ROOT / "ai-lab" / "models" / "model-registry.json"
    try:
        data = json.loads(reg_path.read_text(encoding="utf-8"))
        return {m["id"]: m for m in data.get("models", [])}
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# Build per-model summaries (latest run per device+model)
# ---------------------------------------------------------------------------

def build_model_summaries(runs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Collapse all runs for each (device, model) pair into a single summary entry,
    taking the latest timestamp's derived metrics as authoritative and enriching
    with model registry metadata.
    """
    registry = _load_model_registry()

    # Index latest run per (device, model)
    latest: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for run in runs:
        key = (run["device"], run["model"])
        if key not in latest or str(run["timestamp"]) > str(latest[key]["timestamp"]):
            latest[key] = run

    summaries: List[Dict[str, Any]] = []
    for (device, model), run in sorted(latest.items()):
        entry = copy.deepcopy(run)
        # Enrich with registry info
        reg_info = registry.get(model, {})
        entry["size_mb"] = reg_info.get("sizeEstimateMb") or reg_info.get("size_mb")
        entry["display_name"] = reg_info.get("displayName", model)
        entry["provider"] = reg_info.get("provider")
        entry["target_device_tier"] = reg_info.get("targetDeviceTier")
        entry["registry_notes"] = reg_info.get("notes")
        summaries.append(entry)

    return summaries


# ---------------------------------------------------------------------------
# Inline scoring logic (mirrors compute_scores.py — no import to keep standalone)
# ---------------------------------------------------------------------------

_WEIGHTS = {
    "speed": 0.25,
    "thermal_efficiency": 0.25,
    "stability": 0.20,
    "output_success": 0.20,
    "memory_efficiency": 0.10,
}
_THERMAL_CAP_C = 15.0


def _thermal_score(delta: Optional[float]) -> float:
    if delta is None:
        return 0.5
    if delta <= 0.0:
        return 1.0
    if delta >= _THERMAL_CAP_C:
        return 0.0
    return 1.0 - (delta / _THERMAL_CAP_C)


def _normalise(value: float, lo: float, hi: float) -> float:
    if hi == lo:
        return 0.5
    return max(0.0, min(1.0, (value - lo) / (hi - lo)))


def _score_device_group(models: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    def _raw(m: Dict[str, Any]) -> Dict[str, Any]:
        d = m.get("derived", {})
        total = d.get("prompts") or 0
        success = d.get("success") or 0
        output_present = d.get("output_present") or 0
        avg_tok = d.get("avg_tokens_per_sec")
        size_mb = m.get("size_mb")
        tb = d.get("max_temp_before_c")
        ta = d.get("max_temp_after_c")
        temp_delta = (ta - tb) if (tb is not None and ta is not None) else None
        return {
            "avg_tok_s": float(avg_tok) if (avg_tok is not None and success > 0) else 0.0,
            "temp_delta_c": temp_delta,
            "stability": (success / total) if total > 0 else 0.0,
            "output_rate": (output_present / total) if total > 0 else 0.0,
            "size_mb": float(size_mb) if size_mb is not None else None,
        }

    raws = [_raw(m) for m in models]
    tok_vals = [r["avg_tok_s"] for r in raws]
    tok_lo, tok_hi = min(tok_vals), max(tok_vals)

    size_vals = [r["size_mb"] for r in raws if r["size_mb"] is not None]
    size_lo = min(size_vals) if size_vals else None
    size_hi = max(size_vals) if size_vals else None

    results = []
    for model, raw in zip(models, raws):
        speed_score = _normalise(raw["avg_tok_s"], tok_lo, tok_hi)
        thermal_score = _thermal_score(raw["temp_delta_c"])
        stability_score = raw["stability"]
        output_score = raw["output_rate"]

        if size_lo is not None and size_hi is not None and raw["size_mb"] is not None:
            mem_score = _normalise(size_hi - raw["size_mb"], 0.0, size_hi - size_lo)
        else:
            mem_score = 0.5

        weighted = (
            _WEIGHTS["speed"] * speed_score
            + _WEIGHTS["thermal_efficiency"] * thermal_score
            + _WEIGHTS["stability"] * stability_score
            + _WEIGHTS["output_success"] * output_score
            + _WEIGHTS["memory_efficiency"] * mem_score
        )

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
            "weights": _WEIGHTS,
            "weighted_score": round(weighted, 4),
        }
        results.append(scored)

    results.sort(key=lambda x: x["scoring"]["weighted_score"], reverse=True)
    for rank, entry in enumerate(results, start=1):
        entry["scoring"]["rank"] = rank

    return results


def compute_scores_for_summaries(
    model_summaries: List[Dict[str, Any]],
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    Score all model summaries grouped by device.
    Returns (annotated_summaries, scores_by_device).
    """
    by_device: Dict[str, List[Dict[str, Any]]] = {}
    for entry in model_summaries:
        device = entry.get("device", "unknown")
        by_device.setdefault(device, []).append(entry)

    annotated: List[Dict[str, Any]] = []
    scores_by_device: Dict[str, Any] = {}

    for device, models in sorted(by_device.items()):
        scored = _score_device_group(models)
        scores_by_device[device] = scored
        annotated.extend(scored)

    return annotated, scores_by_device


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def _run_quality_pipeline(dry_run: bool) -> None:
    """Run evaluate_quality then aggregate_quality as a subprocess-free inline call."""
    import importlib.util, sys as _sys

    def _load(rel: str):
        p = REPO_ROOT / rel
        spec = importlib.util.spec_from_file_location(p.stem, p)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    try:
        eq = _load("ai-lab/quality/evaluate_quality.py")
        dataset = eq.load_dataset()
        run_dirs = eq.find_runs()
        summaries = []
        for rd in run_dirs:
            s = eq.evaluate_run(rd, dataset, dry_run=dry_run)
            if s:
                summaries.append(s)
        cmap = eq.compute_consistency(summaries)
        for s in summaries:
            s["consistency_score"] = cmap.get((s["device"], s["model"]), 1.0)
        if not dry_run:
            for s in summaries:
                sp = REPO_ROOT / s["run_dir"] / "quality_summary.json"
                if sp.exists():
                    d = json.loads(sp.read_text(encoding="utf-8"))
                    d["consistency_score"] = s["consistency_score"]
                    sp.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"  Quality evaluated: {len(summaries)} run(s)")
    except Exception as e:
        print(f"  WARNING: quality evaluation failed: {e}")

    try:
        aq = _load("ai-lab/quality/aggregate_quality.py")
        aq.main.__globals__["__name__"] = "__not_main__"
        qsums = aq.load_quality_summaries()
        mq = aq.build_model_quality(qsums)
        payload_q = {
            "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "generated_by": "aggregate_quality.py",
            "model_quality": mq,
            "run_summaries": [{k: v for k, v in s.items() if k != "per_prompt"} for s in qsums],
        }
        if not dry_run:
            QUALITY_JSON = REPO_ROOT / "dashboards" / "data" / "quality-data.json"
            QUALITY_JSON.parent.mkdir(parents=True, exist_ok=True)
            QUALITY_JSON.write_text(json.dumps(payload_q, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"  Wrote quality-data.json ({len(mq)} model entries)")
            aq.annotate_dashboard(mq, dry_run=False)
    except Exception as e:
        print(f"  WARNING: quality aggregation failed: {e}")


def generate(dry_run: bool = False) -> Dict[str, Any]:
    print("Step 1: Aggregating benchmark runs...")
    runs = find_and_aggregate_runs()
    print(f"  Found {len(runs)} run(s) across all devices and models")

    print("Step 2: Building per-model summaries...")
    model_summaries = build_model_summaries(runs)
    print(f"  Built {len(model_summaries)} model summary/summaries")

    print("Step 3: Computing weighted scores...")
    annotated_summaries, scores_by_device = compute_scores_for_summaries(model_summaries)

    for device, scored_list in scores_by_device.items():
        print(f"\n  [{device}]")
        for entry in scored_list:
            s = entry["scoring"]
            print(
                f"    rank {s['rank']:>2}  {entry['model']:<30}  "
                f"score={s['weighted_score']:.3f}  "
                f"tok/s={s['raw']['avg_tok_s']:.1f}"
            )

    now_iso = datetime.now(timezone.utc).isoformat(timespec="seconds")

    payload: Dict[str, Any] = {
        "generated_at": now_iso,
        "generated_by": "generate_dashboard_data.py",
        "benchmark_context": BENCHMARK_CONTEXT,
        "runs": runs,
        "model_summaries": annotated_summaries,
        "scores_by_device": scores_by_device,
    }

    if dry_run:
        print("\n[dry-run] Would write to:", DASHBOARD_JSON)
        preview = json.dumps(payload, ensure_ascii=False, indent=2)
        lines = preview.splitlines()
        print("\n".join(lines[:40]))
        if len(lines) > 40:
            print(f"  ... ({len(lines) - 40} more lines)")
    else:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        DASHBOARD_JSON.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"\nWrote {DASHBOARD_JSON}")
        print(f"  {len(runs)} runs, {len(annotated_summaries)} model summaries")

    print("\nStep 4: Running quality evaluation pipeline...")
    _run_quality_pipeline(dry_run=dry_run)

    # Reload dashboard-data.json to pick up quality annotations
    if not dry_run and DASHBOARD_JSON.exists():
        payload = json.loads(DASHBOARD_JSON.read_text(encoding="utf-8"))

    return payload


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate dashboards/data/dashboard-data.json from ai-lab/results/"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be written without writing any files",
    )
    args = parser.parse_args()
    generate(dry_run=args.dry_run)


if __name__ == "__main__":
    main()
