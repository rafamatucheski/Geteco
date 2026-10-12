"""Enrich a completed fleet benchmark without recalculating paired percentiles.

Usage: python tools/fleet_fixups/summarize_fleet_performance.py BENCHMARK_DIRECTORY
Only comparison-detail.json is written; source measurements remain unchanged.
"""

import argparse
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path
from statistics import fmean


LOAD_FIELDS = ("traffic", "pedestrians", "vehicles", "vehicle_centres_in_frustum")
FOCUS_FIELDS = (
    "expected_focus_mode", "focused_frames", "minimized_frames", "window_no_focus",
    "low_processor_usage_mode", "discarded_focus_frames",
    "discarded_focus_intervals", "discarded_focus_segments", "focus_reselections", "sample_complete",
    "sampling_wall_seconds", "focus_sampling_deadline_seconds",
)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def distribution(values):
    if not values:
        return {"samples": 0, "min": None, "mean": None, "max": None, "counts": {}}
    return {
        "samples": len(values), "min": min(values), "mean": fmean(values),
        "max": max(values),
        "counts": {str(value): count for value, count in sorted(Counter(values).items())},
    }


def summarize_windows(windows):
    loads = [sample for window in windows for sample in window.get("load_samples", [])]
    draws = [value for window in windows for value in window.get("draw_calls_per_frame", [])]
    primitives = [value for window in windows for value in window.get("primitives_per_frame", [])]
    return {
        "scenarios": [window["scenario"] for window in windows],
        "frames": sum(len(window.get("frames_ms", [])) for window in windows),
        "draw_calls_samples": len(draws),
        "draw_calls_mean": fmean(draws) if draws else None,
        "primitives_samples": len(primitives),
        "primitives_mean": fmean(primitives) if primitives else None,
        "load_distribution": {
            field: distribution([sample[field] for sample in loads if field in sample])
            for field in LOAD_FIELDS
        },
        "all_invariants": bool(windows) and all(
            window.get("paired_invariants", {}).get("valid") is True for window in windows
        ),
        "all_samples_complete": bool(windows) and all(
            window.get("sample_complete") is True for window in windows
        ),
        "focused_frames": sum(window.get("focused_frames", 0) for window in windows),
        "minimized_frames": sum(window.get("minimized_frames", 0) for window in windows),
        "discarded_focus_frames": sum(window.get("discarded_focus_frames", 0) for window in windows),
        "focus_conditions": sorted({str(window.get("expected_focus_mode")) for window in windows}),
        "focus_and_discards": {
            window["scenario"]: {field: window.get(field) for field in FOCUS_FIELDS}
            for window in windows
        },
    }


def build_comparison(directory):
    source = read_json(directory / "paired-summary.json")
    result = {
        "source": "paired-summary.json",
        "measurement_valid": source.get("measurement_valid"),
        "order": source.get("order"),
        "confirm_case": source.get("confirm_case"),
        "completed_samples": source.get("completed_samples"),
        "focus_condition": source.get("focus_condition"),
        "initial_focus_reselected": source.get("initial_focus_reselected"),
        "focus_selection_policy": source.get("focus_selection_policy"),
        "cases": deepcopy(source["cases"]),
        "notes": [
            "Cases and their paired percentiles are copied unchanged from paired-summary.json; percentiles are not averaged.",
            "Draw-call and primitive means use concatenated per-frame samples, not unweighted window means.",
            "Load distributions concatenate periodic load_samples; their means are sample-weighted, not frame-weighted, and frustum counts do not measure occlusion.",
            "Viewport CPU and GPU timings are separate overlapping workloads and are never added here.",
            "Normal-setting windows are separate observations, not a before/after comparison or approval.",
        ],
    }
    all_windows = []
    for case in result["cases"].values():
        case["detail"] = {}
        for variant, references in case["windows"].items():
            windows = []
            for reference in references:
                scenario = reference["scenario"]
                if Path(scenario).name != scenario:
                    raise ValueError(f"Invalid scenario filename: {scenario!r}")
                window = read_json(directory / f"{scenario}.json")
                if window.get("scenario") != scenario or window.get("variant") != variant:
                    raise ValueError(f"Scenario/variant mismatch in {scenario}.json")
                windows.append(window)
            case["detail"][variant] = summarize_windows(windows)
            all_windows.extend(windows)
    result["diagnostic"] = summarize_windows(all_windows)
    result["all_invariants"] = result["diagnostic"]["all_invariants"]
    result["invariants_by_window"] = {
        window["scenario"]: window.get("paired_invariants", {}) for window in all_windows
    }
    result["normal"] = {}
    for period in ("day", "night"):
        path = directory / f"normal-{period}.json"
        if path.exists():
            window = read_json(path)
            result["normal"][period] = {
                field: window.get(field) for field in (
                    "scenario", "variant", "summary", "render_timing", "max_fps",
                    "vsync", "renderer", "resolution", "msaa", "paired_invariants",
                )
            }
            result["normal"][period]["detail"] = summarize_windows([window])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Directory containing paired-summary.json and its raw windows")
    directory = parser.parse_args().directory.resolve()
    result = build_comparison(directory)
    output = directory / "comparison-detail.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
