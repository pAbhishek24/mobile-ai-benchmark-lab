#!/usr/bin/env python3
"""
aggregate_quality.py — Merge quality scores into dashboards/data/quality-data.json
and annotate dashboard-data.json model_summaries with quality fields.

Reads:
  ai-lab/results/<device>/<model>/<run>/quality_summary.json  (written by evaluate_quality.py)
  dashboards/data/dashboard-data.json                         (existing performance data)

Writes:
  dashboards/data/quality-data.json   (standalone quality data for quality.html)
  dashboards/data/dashboard-data.json (annotates model_summaries.quality_scores)

Usage:
  python3 ai-lab/quality/aggregate_quality.py
  python3 ai-lab/quality/aggregate_quality.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import statistics
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

REPO_ROOT        = Path(__file__).resolve().parents[2]
RESULTS_ROOT     = REPO_ROOT / "ai-lab" / "results"
DASHBOARD_JSON   = REPO_ROOT / "dashboards" / "data" / "dashboard-data.json"
QUALITY_JSON     = REPO_ROOT / "dashboards" / "data" / "quality-data.json"


def load_quality_summaries() -> List[Dict[str, Any]]:
    summaries: List[Dict[str, Any]] = []
    if not RESULTS_ROOT.exists():
        return summaries
    for device_dir in RESULTS_ROOT.iterdir():
        if not device_dir.is_dir():
            continue
        for model_dir in device_dir.iterdir():
            if not model_dir.is_dir():
                continue
            for run_dir in model_dir.iterdir():
                if not run_dir.is_dir():
                    continue
                qs_path = run_dir / "quality_summary.json"
                if not qs_path.exists():
                    continue
                try:
                    data = json.loads(qs_path.read_text(encoding="utf-8"))
                    summaries.append(data)
                except Exception:
                    pass
    return sorted(summaries, key=lambda s: (s.get("device",""), s.get("model",""), s.get("timestamp","")))


def load_quality_results(run_dir_rel: str) -> List[Dict[str, Any]]:
    path = REPO_ROOT / run_dir_rel / "quality_results.jsonl"
    rows: List[Dict[str, Any]] = []
    if not path.exists():
        return rows
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line:
            try:
                rows.append(json.loads(line))
            except Exception:
                pass
    return rows


def build_model_quality(summaries: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Collapse all runs per (device, model) into a single quality entry,
    using the latest run as primary and averaging across runs for consistency.
    """
    groups: Dict[Tuple[str,str], List[Dict[str,Any]]] = defaultdict(list)
    for s in summaries:
        key = (s.get("device",""), s.get("model",""))
        groups[key].append(s)

    entries: List[Dict[str, Any]] = []
    for (device, model), runs in sorted(groups.items()):
        latest = max(runs, key=lambda r: r.get("timestamp", ""))

        def avg(field: str) -> Optional[float]:
            vals = [r[field] for r in runs if r.get(field) is not None]
            return round(statistics.mean(vals), 4) if vals else None

        per_prompt_all = []
        for run in runs:
            per_prompt_all.extend(load_quality_results(run.get("run_dir", "")))

        # Per-category quality breakdown
        cat_scores: Dict[str, List[float]] = defaultdict(list)
        for pr in per_prompt_all:
            cat = pr.get("category", "unknown")
            q = pr.get("scores", {}).get("quality_score")
            if q is not None:
                cat_scores[cat].append(q)
        category_quality = {
            cat: round(statistics.mean(vals), 4)
            for cat, vals in sorted(cat_scores.items())
            if vals
        }

        # Per-difficulty breakdown
        diff_scores: Dict[str, List[float]] = defaultdict(list)
        for pr in per_prompt_all:
            diff = pr.get("difficulty", "unknown")
            q = pr.get("scores", {}).get("quality_score")
            if q is not None:
                diff_scores[diff].append(q)
        difficulty_quality = {
            d: round(statistics.mean(vals), 4)
            for d, vals in sorted(diff_scores.items())
            if vals
        }

        # Worst prompts (lowest quality scores)
        prompt_avgs: Dict[str, List[float]] = defaultdict(list)
        for pr in per_prompt_all:
            pid = pr.get("prompt_id","?")
            q = pr.get("scores", {}).get("quality_score")
            if q is not None:
                prompt_avgs[pid].append(q)
        prompt_summary = sorted(
            [{"prompt_id": pid, "avg_quality": round(statistics.mean(vals), 4),
              "runs": len(vals)} for pid, vals in prompt_avgs.items()],
            key=lambda x: x["avg_quality"]
        )

        entries.append({
            "device": device,
            "model": model,
            "runs_evaluated": len(runs),
            "latest_timestamp": latest.get("timestamp"),
            "quality_score": avg("quality_score"),
            "consistency_score": avg("consistency_score"),
            "hallucination_rate": avg("hallucination_rate"),
            "structured_output_success_rate": avg("structured_output_success_rate"),
            "recommendation_quality_score": avg("recommendation_quality_score"),
            "prompts_scored": latest.get("prompts_scored", 0),
            "prompts_empty": latest.get("prompts_empty", 0),
            "category_quality": category_quality,
            "difficulty_quality": difficulty_quality,
            "prompt_quality_summary": prompt_summary,
        })

    return entries


def annotate_dashboard(model_quality: List[Dict[str, Any]], dry_run: bool = False) -> None:
    """Inject quality_scores block into each model_summary in dashboard-data.json."""
    if not DASHBOARD_JSON.exists():
        print(f"WARNING: {DASHBOARD_JSON} not found, skipping annotation")
        return

    data = json.loads(DASHBOARD_JSON.read_text(encoding="utf-8"))

    quality_lookup: Dict[Tuple[str,str], Dict[str,Any]] = {
        (e["device"], e["model"]): e for e in model_quality
    }

    for entry in data.get("model_summaries", []):
        key = (entry.get("device",""), entry.get("model",""))
        q = quality_lookup.get(key)
        if q:
            entry["quality_scores"] = {
                "quality_score": q["quality_score"],
                "consistency_score": q["consistency_score"],
                "hallucination_rate": q["hallucination_rate"],
                "structured_output_success_rate": q["structured_output_success_rate"],
                "recommendation_quality_score": q["recommendation_quality_score"],
                "category_quality": q["category_quality"],
                "difficulty_quality": q["difficulty_quality"],
            }
        else:
            entry.setdefault("quality_scores", None)

    if not dry_run:
        DASHBOARD_JSON.write_text(
            json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"Annotated {DASHBOARD_JSON}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Aggregate quality scores into dashboard JSON")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    summaries = load_quality_summaries()
    print(f"Loaded {len(summaries)} quality summary file(s)")

    if not summaries:
        print("No quality summaries found. Run evaluate_quality.py first.")
        # Still write an empty quality-data.json so dashboard doesn't 404
        payload: Dict[str, Any] = {
            "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "generated_by": "aggregate_quality.py",
            "model_quality": [],
            "run_summaries": [],
        }
        if not args.dry_run:
            QUALITY_JSON.parent.mkdir(parents=True, exist_ok=True)
            QUALITY_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"Wrote empty {QUALITY_JSON}")
        return

    model_quality = build_model_quality(summaries)

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generated_by": "aggregate_quality.py",
        "model_quality": model_quality,
        "run_summaries": [
            {k: v for k, v in s.items() if k != "per_prompt"}
            for s in summaries
        ],
    }

    if not args.dry_run:
        QUALITY_JSON.parent.mkdir(parents=True, exist_ok=True)
        QUALITY_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Wrote {QUALITY_JSON} ({len(model_quality)} model entries)")

    annotate_dashboard(model_quality, dry_run=args.dry_run)

    print("\n── Quality Leaderboard ───────────────────────────────────────────────")
    print(f"{'Model':<30} {'Quality':>8} {'Consist':>8} {'Halluc':>8} {'JSON':>6} {'Rec':>6}")
    print("-" * 70)
    for e in sorted(model_quality, key=lambda x: x["quality_score"] or 0, reverse=True):
        print(
            f"{e['model']:<30}"
            f" {(e['quality_score'] or 0):>8.3f}"
            f" {(e['consistency_score'] or 0):>8.3f}"
            f" {(e['hallucination_rate'] or 0):>8.3f}"
            f" {(e['structured_output_success_rate'] or 0):>6.3f}"
            f" {(e['recommendation_quality_score'] or 0):>6.3f}"
        )


if __name__ == "__main__":
    main()
