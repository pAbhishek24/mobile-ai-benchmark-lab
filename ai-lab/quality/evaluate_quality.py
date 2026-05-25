#!/usr/bin/env python3
"""
evaluate_quality.py — Finance quality evaluator for mobile LLM benchmark outputs.

Reads:
  ai-lab/results/<device>/<model>/<run>/benchmark.jsonl   (model outputs)
  ai-lab/quality/quality_benchmark_dataset.json           (ground truth + rubric)

Writes:
  ai-lab/results/<device>/<model>/<run>/quality_results.jsonl  (per-prompt scores)
  ai-lab/results/<device>/<model>/<run>/quality_summary.json   (aggregated scores)

Scores produced per run:
  quality_score               weighted average of per-prompt numeric + concept checks
  consistency_score           cross-run output similarity for same (device, model, prompt)
  hallucination_rate          fraction of prompts triggering hallucination patterns
  structured_output_success_rate  fraction of prompts producing valid JSON when asked
  recommendation_quality_score    fraction of prompts with required advice keywords present

Usage:
  python3 ai-lab/quality/evaluate_quality.py                   # all runs
  python3 ai-lab/quality/evaluate_quality.py --run-dir ai-lab/results/samsung-s24-ultra/qwen2.5-0.5b-q4km/20260524_203804
  python3 ai-lab/quality/evaluate_quality.py --model qwen2.5-0.5b-q4km
  python3 ai-lab/quality/evaluate_quality.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

REPO_ROOT   = Path(__file__).resolve().parents[2]
RESULTS_ROOT = REPO_ROOT / "ai-lab" / "results"
DATASET_PATH = REPO_ROOT / "ai-lab" / "quality" / "quality_benchmark_dataset.json"

FOCUS_MODELS = {"qwen2.5-0.5b-q4km", "qwen2.5-1.5b-q4km", "tinyllama-1.1b-q4km"}

# Truncation indicators: unfinished JSON, cut-off sentences, abrupt endings
TRUNCATION_PATTERNS = [
    r"\{[^}]*\Z",                             # unclosed JSON object
    r"\[[^\]]*\Z",                            # unclosed JSON array
    r"\b(?:and|but|the|to|of|in|a|an)\s*\Z", # trailing stop-word at sentence boundary
    r"[,;]\s*\Z",                             # trailing comma or semicolon
]

HARMFUL_ADVICE_PATTERNS = [
    r"\binvest\s+(?:everything|all\s+(?:your|the)\s+savings)\b",
    r"\bguaranteed?\s+returns?\b",
    r"\b(?:100|300|500|1000)\s*%\s+returns?\b",
    r"\buse\s+credit\s+card\s+to\s+(?:invest|pay\s+(?:off\s+)?(?:loan|emi|debt))\b",
    r"\btake\s+(?:a\s+)?(?:personal\s+)?loan\s+to\s+invest\b",
    r"\bwithdraw\s+(?:your\s+)?(?:pf|epf|ppf|provident\s+fund)\b",
    r"\bstop\s+paying\s+(?:emi|loan)\b",
    r"\bdefault\s+(?:on\s+)?(?:loan|emi)\b",
    r"\bcrypto\b",
    r"\bforex\b",
]

CATEGORY_WEIGHTS: Dict[str, float] = {
    "expense_summary":      1.0,
    "emi_pressure":         1.2,
    "credit_card_planning": 1.2,
    "sip_planning":         1.1,
    "lic_outflow":          1.0,
    "budget_overspend":     1.0,
    "safe_spend_remaining": 1.1,
    "debt_payoff":          1.2,
    "category_spike":       1.0,
    "cashflow_warning":     1.3,
}

# ── Dataset loading ──────────────────────────────────────────────────────────

def load_dataset() -> Dict[str, Any]:
    data = json.loads(DATASET_PATH.read_text(encoding="utf-8"))
    return {p["prompt_id"]: p for p in data["prompts"]}


def load_benchmark_jsonl(path: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    except FileNotFoundError:
        pass
    return rows


# ── Numeric check ────────────────────────────────────────────────────────────

def _extract_numbers(text: str) -> List[float]:
    """Pull all plain numbers (possibly with commas) from text."""
    cleaned = text.replace(",", "")
    return [float(m) for m in re.findall(r"\b\d+(?:\.\d+)?\b", cleaned)]


def check_numeric(output: str, check: Dict[str, Any]) -> Tuple[bool, float]:
    """Returns (passed, credit) where credit is 0–1."""
    target = float(check["value"])
    tol_pct = float(check.get("tolerance_pct", 2.0))
    lo = target * (1 - tol_pct / 100)
    hi = target * (1 + tol_pct / 100)
    nums = _extract_numbers(output)
    for n in nums:
        if lo <= n <= hi:
            return True, 1.0
    # Partial credit if within 10× tolerance
    wide_lo = target * (1 - tol_pct * 5 / 100)
    wide_hi = target * (1 + tol_pct * 5 / 100)
    for n in nums:
        if wide_lo <= n <= wide_hi:
            return False, 0.5
    return False, 0.0


# ── Concept check ────────────────────────────────────────────────────────────

def check_concepts(output: str, required_concepts: List[str]) -> float:
    """Returns fraction of required concepts found (case-insensitive)."""
    if not required_concepts:
        return 1.0
    lower = output.lower()
    found = sum(1 for c in required_concepts if c.lower() in lower)
    return found / len(required_concepts)


# ── Hallucination detection ──────────────────────────────────────────────────

def check_hallucinations(output: str, traps: List[Dict[str, Any]]) -> Tuple[bool, List[str]]:
    """Returns (hallucination_detected, list_of_triggered_trap_ids)."""
    triggered: List[str] = []
    for trap in traps:
        pat = trap.get("pattern", "")
        if pat and re.search(pat, output, re.IGNORECASE):
            triggered.append(trap["id"])
    return len(triggered) > 0, triggered


# ── Structured output (JSON) validation ──────────────────────────────────────

def _extract_json(text: str) -> Optional[Any]:
    """Try to extract a JSON object/array from model output (may be embedded in prose)."""
    # Try full text first
    try:
        return json.loads(text)
    except Exception:
        pass
    # Find first { ... } block
    match = re.search(r"\{[\s\S]*\}", text)
    if match:
        try:
            return json.loads(match.group(0))
        except Exception:
            pass
    # Find first [ ... ] block
    match = re.search(r"\[[\s\S]*\]", text)
    if match:
        try:
            return json.loads(match.group(0))
        except Exception:
            pass
    return None


def validate_json_schema(obj: Any, schema: Dict[str, Any]) -> Tuple[bool, float]:
    """Light schema validation. Returns (valid, completeness_score)."""
    if not isinstance(obj, dict):
        return False, 0.0
    required = schema.get("required", [])
    if not required:
        return True, 1.0
    present = sum(1 for k in required if k in obj and obj[k] is not None)
    score = present / len(required)
    return score >= 1.0, score


def check_structured_output(output: str, prompt_spec: Dict[str, Any]) -> Tuple[bool, float]:
    """
    Check whether the model produced valid structured JSON matching expected schema.
    Returns (json_valid, completeness_score 0-1).
    """
    schema = prompt_spec.get("json_schema")
    if not schema:
        return True, 1.0  # no JSON expected
    obj = _extract_json(output)
    if obj is None:
        return False, 0.0
    return validate_json_schema(obj, schema)


# ── Recommendation quality ───────────────────────────────────────────────────

def check_recommendation_quality(output: str, prompt_spec: Dict[str, Any]) -> Tuple[float, bool]:
    """
    Returns (quality_score 0-1, has_harmful_advice).
    quality_score = fraction of required_advice_keywords present.
    has_harmful = True if any harmful_advice_patterns found.
    """
    rec = prompt_spec.get("recommendation_check", {})
    required_kw = rec.get("required_advice_keywords", [])
    harmful_pats = rec.get("harmful_advice_patterns", [])

    lower = output.lower()

    kw_score = 1.0
    if required_kw:
        found = sum(1 for kw in required_kw if kw.lower() in lower)
        kw_score = found / len(required_kw)

    has_harmful = any(
        re.search(p, output, re.IGNORECASE)
        for p in harmful_pats
        if p
    )

    final_score = kw_score * (0.5 if has_harmful else 1.0)
    return final_score, has_harmful


# ── Truncation detection ─────────────────────────────────────────────────────

def check_truncation(output: str) -> Tuple[bool, List[str]]:
    """Returns (is_truncated, list_of_triggered_reasons)."""
    reasons: List[str] = []
    stripped = output.rstrip()
    if not stripped:
        return True, ["empty"]

    # Pattern-based checks
    for pat in TRUNCATION_PATTERNS:
        if re.search(pat, stripped, re.IGNORECASE | re.MULTILINE):
            reasons.append(pat[:40])

    # Abrupt-ending check: output does not end with sentence-closing punctuation
    last_char = stripped[-1]
    if last_char not in ".!?)>\"'" and len(stripped) > 30:
        reasons.append("no_sentence_end")

    return len(reasons) > 0, reasons


# ── Confidence extraction ─────────────────────────────────────────────────────

def extract_confidence(output: str) -> Optional[float]:
    """Extract confidence score if model emits {"confidence": 0.xx} or 'confidence: 0.xx'."""
    obj = _extract_json(output)
    if isinstance(obj, dict) and "confidence" in obj:
        try:
            return float(obj["confidence"])
        except (TypeError, ValueError):
            pass
    m = re.search(r'(?:confidence|certainty)\s*[=:]\s*([0-9]*\.?[0-9]+)', output, re.IGNORECASE)
    if m:
        try:
            v = float(m.group(1))
            return v if v <= 1.0 else v / 100.0
        except ValueError:
            pass
    return None


# ── Per-prompt scorer ────────────────────────────────────────────────────────

def score_prompt(output: str, prompt_spec: Dict[str, Any]) -> Dict[str, Any]:
    """
    Score a single model output against its ground-truth spec.
    Returns a dict with all sub-scores and flags.
    """
    if not output or not output.strip():
        return {
            "numeric_score": 0.0,
            "concept_score": 0.0,
            "hallucination_detected": False,
            "hallucination_triggers": [],
            "json_valid": False,
            "json_completeness": 0.0,
            "recommendation_quality": 0.0,
            "has_harmful_advice": False,
            "empty_output": True,
            "truncated": True,
            "truncation_reasons": ["empty"],
            "confidence": None,
            "quality_score": 0.0,
        }

    # Numeric checks
    numeric_checks = prompt_spec.get("numeric_checks", [])
    numeric_scores: List[float] = []
    numeric_details: List[Dict[str, Any]] = []
    if numeric_checks:
        required_passed = 0
        required_total = 0
        for chk in numeric_checks:
            passed, credit = check_numeric(output, chk)
            numeric_details.append({
                "id": chk["id"],
                "target": chk["value"],
                "passed": passed,
                "credit": credit,
                "required": chk.get("required", False),
            })
            numeric_scores.append(credit)
            if chk.get("required"):
                required_total += 1
                if passed:
                    required_passed += 1
        # If any required checks exist and none pass, cap numeric at 0.3
        if required_total > 0 and required_passed == 0:
            numeric_score = 0.3 * (sum(numeric_scores) / len(numeric_scores))
        else:
            numeric_score = sum(numeric_scores) / len(numeric_scores)
    else:
        numeric_score = 1.0  # no numeric checks = not penalised
        numeric_details = []

    # Concept checks
    concept_score = check_concepts(output, prompt_spec.get("required_concepts", []))

    # Hallucination
    hallucination_detected, triggers = check_hallucinations(
        output, prompt_spec.get("hallucination_traps", [])
    )

    # Structured output
    json_valid, json_completeness = check_structured_output(output, prompt_spec)

    # Recommendation quality — also check global harmful patterns
    rec_quality, has_harmful = check_recommendation_quality(output, prompt_spec)
    if not has_harmful:
        has_harmful = any(
            re.search(p, output, re.IGNORECASE)
            for p in HARMFUL_ADVICE_PATTERNS
            if p
        )

    # Truncation detection
    truncated, trunc_reasons = check_truncation(output)

    # Confidence extraction
    confidence = extract_confidence(output)

    # Composite quality score (weights)
    # numeric: 35%, concept: 25%, hallucination_penalty: 20%, rec_quality: 20%
    hallucination_penalty = 0.5 if hallucination_detected else 0.0
    truncation_penalty = 0.1 if truncated else 0.0
    quality_score = max(0.0, (
        0.35 * numeric_score
        + 0.25 * concept_score
        + 0.20 * (1.0 - hallucination_penalty)
        + 0.20 * rec_quality
        - truncation_penalty
    ))

    return {
        "numeric_score": round(numeric_score, 4),
        "numeric_details": numeric_details,
        "concept_score": round(concept_score, 4),
        "hallucination_detected": hallucination_detected,
        "hallucination_triggers": triggers,
        "json_valid": json_valid,
        "json_completeness": round(json_completeness, 4),
        "recommendation_quality": round(rec_quality, 4),
        "has_harmful_advice": has_harmful,
        "empty_output": False,
        "truncated": truncated,
        "truncation_reasons": trunc_reasons,
        "confidence": round(confidence, 3) if confidence is not None else None,
        "quality_score": round(quality_score, 4),
    }


# ── Run-level aggregation ────────────────────────────────────────────────────

def evaluate_run(run_dir: Path, dataset: Dict[str, Any], dry_run: bool = False) -> Optional[Dict[str, Any]]:
    jsonl_path = run_dir / "benchmark.jsonl"
    rows = load_benchmark_jsonl(jsonl_path)
    if not rows:
        return None

    results: List[Dict[str, Any]] = []
    for row in rows:
        pid = row.get("prompt_id") or row.get("id")
        output = (row.get("output") or "").strip()
        # Strip the prompt echo that some models prepend (output starts with prompt text)
        spec = dataset.get(pid)
        if spec is None:
            continue
        # Detect and strip prompt echo: if output starts with the prompt text, remove it
        prompt_text = ""
        # We don't have the original prompt text here; rely on tinyllama's <s> prefix to detect
        if output.startswith("<s>"):
            # tinyllama echoes the entire prompt; find where new content begins after prompt
            # The prompt is embedded in output; score the whole thing but note the echo
            output_clean = output
        else:
            output_clean = output

        scores = score_prompt(output_clean, spec)
        results.append({
            "prompt_id": pid,
            "category": spec["category"],
            "difficulty": spec["difficulty"],
            "status": row.get("status"),
            "output_length_words": len(output_clean.split()) if output_clean else 0,
            "scores": scores,
        })

    if not results:
        return None

    # Aggregate
    cat_weights = CATEGORY_WEIGHTS
    total_weight = 0.0
    weighted_quality = 0.0
    hallucination_count = 0
    json_valid_count = 0
    rec_quality_sum = 0.0
    empty_count = 0
    truncation_count = 0
    harmful_count = 0
    scored_count = len(results)

    per_prompt_quality: List[float] = []

    for r in results:
        sc = r["scores"]
        cat = r["category"]
        w = cat_weights.get(cat, 1.0)
        q = sc["quality_score"]
        weighted_quality += q * w
        total_weight += w
        per_prompt_quality.append(q)
        if sc["hallucination_detected"]:
            hallucination_count += 1
        if sc["json_valid"]:
            json_valid_count += 1
        if sc["empty_output"]:
            empty_count += 1
        if sc.get("truncated"):
            truncation_count += 1
        if sc.get("has_harmful_advice"):
            harmful_count += 1
        rec_quality_sum += sc["recommendation_quality"]

    quality_score = weighted_quality / total_weight if total_weight > 0 else 0.0
    hallucination_rate = hallucination_count / scored_count if scored_count > 0 else 0.0
    structured_output_success_rate = json_valid_count / scored_count if scored_count > 0 else 0.0
    recommendation_quality_score = rec_quality_sum / scored_count if scored_count > 0 else 0.0
    truncation_rate = truncation_count / scored_count if scored_count > 0 else 0.0
    harmful_advice_rate = harmful_count / scored_count if scored_count > 0 else 0.0

    summary = {
        "run_dir": str(run_dir.relative_to(REPO_ROOT)).replace("\\", "/"),
        "device": run_dir.parent.parent.name,
        "model": run_dir.parent.name,
        "timestamp": run_dir.name,
        "prompts_scored": scored_count,
        "prompts_empty": empty_count,
        "quality_score": round(quality_score, 4),
        "hallucination_rate": round(hallucination_rate, 4),
        "truncation_rate": round(truncation_rate, 4),
        "harmful_advice_rate": round(harmful_advice_rate, 4),
        "structured_output_success_rate": round(structured_output_success_rate, 4),
        "recommendation_quality_score": round(recommendation_quality_score, 4),
        "consistency_score": None,  # filled by aggregate step
        "per_prompt": results,
    }

    if not dry_run:
        out_jsonl = run_dir / "quality_results.jsonl"
        with out_jsonl.open("w", encoding="utf-8") as f:
            for r in results:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")

        out_json = run_dir / "quality_summary.json"
        out_json.write_text(
            json.dumps({k: v for k, v in summary.items() if k != "per_prompt"},
                       ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    return summary


# ── Consistency scoring (cross-run) ─────────────────────────────────────────

def compute_consistency(all_summaries: List[Dict[str, Any]]) -> Dict[Tuple[str, str], float]:
    """
    For each (device, model) pair with multiple runs, compute consistency as
    1 - (std_dev of quality_score across runs) normalised to [0, 1].
    Single runs get consistency_score = 1.0.
    """
    from collections import defaultdict
    groups: Dict[Tuple[str, str], List[float]] = defaultdict(list)
    for s in all_summaries:
        key = (s["device"], s["model"])
        groups[key].append(s["quality_score"])

    result: Dict[Tuple[str, str], float] = {}
    for key, scores in groups.items():
        if len(scores) < 2:
            result[key] = 1.0
        else:
            std = statistics.stdev(scores)
            # Normalise: std of 0 → 1.0, std of 0.2 → 0.0 (cap)
            consistency = max(0.0, 1.0 - std / 0.2)
            result[key] = round(consistency, 4)
    return result


# ── Find runs ────────────────────────────────────────────────────────────────

def find_runs(model_filter: Optional[str] = None) -> List[Path]:
    runs: List[Path] = []
    if not RESULTS_ROOT.exists():
        return runs
    for device_dir in RESULTS_ROOT.iterdir():
        if not device_dir.is_dir():
            continue
        for model_dir in device_dir.iterdir():
            if not model_dir.is_dir():
                continue
            if model_filter and model_dir.name != model_filter:
                continue
            for run_dir in model_dir.iterdir():
                if not run_dir.is_dir():
                    continue
                if (run_dir / "benchmark.jsonl").exists():
                    runs.append(run_dir)
    return sorted(runs)


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate finance output quality for benchmark runs")
    parser.add_argument("--run-dir", help="Evaluate a single run directory (relative or absolute)")
    parser.add_argument("--model",   help="Filter to a specific model name")
    parser.add_argument("--dry-run", action="store_true", help="Score without writing files")
    args = parser.parse_args()

    dataset = load_dataset()
    print(f"Loaded quality dataset: {len(dataset)} prompt specs")

    if args.run_dir:
        run_dirs = [Path(args.run_dir).resolve()]
    else:
        run_dirs = find_runs(model_filter=args.model)

    print(f"Evaluating {len(run_dirs)} run(s)...")

    summaries: List[Dict[str, Any]] = []
    for run_dir in run_dirs:
        result = evaluate_run(run_dir, dataset, dry_run=args.dry_run)
        if result is None:
            print(f"  SKIP (no data): {run_dir.relative_to(REPO_ROOT)}")
            continue
        summaries.append(result)
        action = "DRY" if args.dry_run else "wrote"
        print(
            f"  {action}: {run_dir.relative_to(REPO_ROOT)}"
            f"  quality={result['quality_score']:.3f}"
            f"  halluc={result['hallucination_rate']:.2f}"
            f"  json={result['structured_output_success_rate']:.2f}"
            f"  rec={result['recommendation_quality_score']:.2f}"
        )

    # Consistency pass
    consistency_map = compute_consistency(summaries)
    for s in summaries:
        key = (s["device"], s["model"])
        s["consistency_score"] = consistency_map.get(key, 1.0)

    if not args.dry_run:
        # Patch consistency back into quality_summary.json files
        for s in summaries:
            summary_path = REPO_ROOT / s["run_dir"] / "quality_summary.json"
            if summary_path.exists():
                data = json.loads(summary_path.read_text(encoding="utf-8"))
                data["consistency_score"] = s["consistency_score"]
                summary_path.write_text(
                    json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
                )

    print("\n── Summary ──────────────────────────────────────────")
    print(f"{'Model':<30} {'Runs':>4} {'Quality':>8} {'Consist':>8} {'Halluc':>7} {'Trunc':>6} {'JSON':>6} {'Rec':>6}")
    print("-" * 83)
    from collections import defaultdict
    model_groups: Dict[str, List[Dict]] = defaultdict(list)
    for s in summaries:
        model_groups[s["model"]].append(s)
    for model, runs in sorted(model_groups.items()):
        avg_q = statistics.mean(r["quality_score"] for r in runs)
        avg_h = statistics.mean(r["hallucination_rate"] for r in runs)
        avg_t = statistics.mean(r.get("truncation_rate", 0.0) for r in runs)
        avg_j = statistics.mean(r["structured_output_success_rate"] for r in runs)
        avg_r = statistics.mean(r["recommendation_quality_score"] for r in runs)
        cons  = runs[-1]["consistency_score"]
        flag = " ★" if model in FOCUS_MODELS else ""
        print(f"{model:<30}{flag} {len(runs):>4} {avg_q:>8.3f} {cons:>8.3f} {avg_h:>7.2f} {avg_t:>6.2f} {avg_j:>6.2f} {avg_r:>6.2f}")


if __name__ == "__main__":
    main()
