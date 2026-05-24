#!/usr/bin/env python3
"""
Aggregate AI Lab benchmark runs under ai-lab/results/ into a single JSON file
consumable by a static dashboard.

Design goals:
- No backend. Pure static artifacts.
- Robust to partial runs / missing files.
- Never assumes cwd; all paths resolved from repo root.
"""

from __future__ import annotations

import csv
import json
import statistics
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


REPO_ROOT = Path(__file__).resolve().parents[2]
RESULTS_ROOT = REPO_ROOT / "ai-lab" / "results"
DASHBOARD_DIR = REPO_ROOT / "dashboards"
DATA_DIR = DASHBOARD_DIR / "data"


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
                # Keep going; the dashboard should still render partial history.
                pass
    except FileNotFoundError:
        pass
    return rows


def _read_summary_csv(path: Path) -> Optional[Dict[str, Any]]:
    if not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8", newline="") as f:
            r = csv.reader(f)
            header = next(r, None)
            if not header:
                return None
            values = next(r, None)
            if not values:
                return None
            data = dict(zip(header, values))
            return data
    except Exception:
        return None


def _p50(values: List[float]) -> Optional[float]:
    if not values:
        return None
    values = sorted(values)
    return values[len(values) // 2]


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


def _derive_timestamp(run_dir: Path) -> str:
    # run dir name is YYYYMMDD_HHMMSS in current convention
    return run_dir.name


def find_runs() -> List[Path]:
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
                # Must contain at least one of these to be considered a run.
                if (run_dir / "benchmark.jsonl").exists() or (run_dir / "summary.csv").exists():
                    runs.append(run_dir)
    runs.sort(key=lambda p: (p.parent.parent.name, p.parent.name, p.name))
    return runs


def aggregate_run(run_dir: Path) -> Dict[str, Any]:
    device = run_dir.parent.parent.name
    model = run_dir.parent.name
    ts = _derive_timestamp(run_dir)

    summary = _read_summary_csv(run_dir / "summary.csv") or {}
    bench_rows = _read_jsonl(run_dir / "benchmark.jsonl")
    snap_before = _read_json(run_dir / "snapshot_before.json")
    snap_after = _read_json(run_dir / "snapshot_after.json")

    # Derive metrics from JSONL when possible.
    durations = []
    tokps = []
    statuses: Dict[str, int] = {"ok": 0, "timeout": 0, "error": 0}
    thermal_warn_count = 0
    output_present = 0

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
                if v is not None:
                    tokps.append(float(v))
        except Exception:
            pass

        if bool(r.get("thermal_warning")):
            thermal_warn_count += 1
        if (r.get("output") or "").strip():
            output_present += 1

    p50_dur = _p50(durations)
    p50_tok = _p50(tokps)
    avg_tok = (statistics.mean(tokps) if tokps else None)
    total_time_ms = int(sum(float(r.get("duration_ms", 0) or 0) for r in bench_rows)) if bench_rows else None

    max_before = _max_temp(snap_before)
    max_after = _max_temp(snap_after)

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
        "quality_score": None,  # placeholder for future human rubric scoring
        "summary": {
            **summary,
        },
        "derived": {
            "prompts": len(bench_rows) if bench_rows else _safe_int(summary.get("prompts")),
            "success": statuses["ok"],
            "timeout": statuses["timeout"],
            "error": statuses["error"],
            "total_time_ms": total_time_ms,
            "p50_duration_ms": p50_dur,
            "p50_tokens_per_sec": p50_tok,
            "avg_tokens_per_sec": avg_tok,
            "output_present": output_present,
            "thermal_warning_count": thermal_warn_count,
            "max_temp_before_c": max_before,
            "max_temp_after_c": max_after,
            "thermal_before_bucket": _thermal_bucket(max_before),
            "thermal_after_bucket": _thermal_bucket(max_after),
        },
        "snapshot_before": _min_snapshot(snap_before),
        "snapshot_after": _min_snapshot(snap_after),
    }


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


def main() -> None:
    runs = find_runs()
    aggregated = [aggregate_run(p) for p in runs]

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    out_path = DATA_DIR / "runs.json"
    out_path.write_text(json.dumps({"runs": aggregated}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {out_path} ({len(aggregated)} runs)")


if __name__ == "__main__":
    main()

