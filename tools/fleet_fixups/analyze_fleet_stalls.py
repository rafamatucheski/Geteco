"""Análise offline de janelas concluídas da frota; nunca inicia o Godot nem muda entradas."""

import argparse
from bisect import bisect_left
from itertools import accumulate
import json
from math import sqrt
from pathlib import Path
from statistics import fmean


METRICS = (
    "viewport_cpu_ms", "viewport_gpu_ms", "frame_setup_cpu_ms",
    "cpu_process_ms", "physics_ms", "draw_calls_per_frame", "primitives_per_frame",
)


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def pearson(left, right):
    if not left or len(left) != len(right):
        return None
    mx, my = fmean(left), fmean(right)
    xx = sum((x - mx) ** 2 for x in left)
    yy = sum((y - my) ** 2 for y in right)
    if not xx or not yy:
        return None
    return round(sum((x - mx) * (y - my) for x, y in zip(left, right)) / sqrt(xx * yy), 6)


def held_samples(values, frames):
    runs = []
    count, duration = 1, frames[0]
    for index in range(1, len(values)):
        if values[index] == values[index - 1]:
            count += 1
            duration += frames[index]
        else:
            runs.append((count, duration))
            count, duration = 1, frames[index]
    runs.append((count, duration))
    return {
        "changes": len(runs) - 1,
        "distinct_values": len(set(values)),
        "same_as_previous_fraction": (len(values) - len(runs)) / max(1, len(values) - 1),
        "longest_constant_run_frames": max(count for count, _ in runs),
        "longest_constant_run_ms": max(duration for _, duration in runs),
    }


def analyze(path):
    window = read(path)
    frames = window["frames_ms"]
    ends = list(accumulate(ms / 1000 for ms in frames))
    spikes = [i for i, ms in enumerate(frames) if ms > 33.3]
    spike_set = set(spikes)
    groups = []
    for index in spikes:
        if not groups or ends[index] - ends[groups[-1][-1]] > 0.25:
            groups.append([])
        groups[-1].append(index)

    # load_snapshot roda depois de carimbar o quadro atual; o custo dele pode
    # cair no intervalo seguinte. Localiza esse intervalo sem alterar dados.
    after_probe = set()
    for sample in window.get("load_samples", []):
        index = bisect_left(ends, sample["seconds"] - 1e-7)
        if index + 1 < len(frames) and abs(ends[index] - sample["seconds"]) < 1e-5:
            after_probe.add(index + 1)

    def subset_summary(indices):
        return {
            "frames": len(indices),
            "frame_mean_ms": fmean(frames[i] for i in indices) if indices else None,
            "frame_max_ms": max((frames[i] for i in indices), default=None),
            "over_33_3_ms": sum(frames[i] > 33.3 for i in indices),
        }

    correlations = {}
    for name in METRICS:
        values = window.get(name, [])
        if len(values) != len(frames):
            raise ValueError(f"Array length mismatch: {path}: {name}")
        lags = {}
        for lag in (-2, -1, 0, 1, 2):
            left = frames[max(0, -lag):min(len(frames), len(frames) - lag)]
            right = values[max(0, lag):min(len(values), len(values) + lag)]
            lags[str(lag)] = pearson(left, right)
        correlations[name] = {
            "pearson_by_lag_frames": lags,
            "all_frame_mean": fmean(values),
            "spike_frame_mean": fmean(values[i] for i in spikes) if spikes else None,
            "other_frame_mean": fmean(v for i, v in enumerate(values) if i not in spike_set),
        }

    return {
        "source": path.as_posix(), "scenario": window["scenario"],
        "variant": window["variant"], "night": window["night"],
        "summary_unchanged": window["summary"],
        "focus_valid": window["focused_frames"] == len(frames) and window["minimized_frames"] == 0,
        "sample_complete": window["sample_complete"],
        "invariants_valid": window["paired_invariants"]["valid"],
        "no_focus_discards": window["discarded_focus_frames"] == 0,
        "sum_intervals_matches_summary": abs(sum(frames) / 1000 - window["summary"]["seconds"]) < 1e-6,
        "clusters_gap_threshold_ms": 250,
        "clusters": [{
            "first_index_zero_based": group[0], "last_index_zero_based": group[-1],
            "first_end_seconds": ends[group[0]], "last_end_seconds": ends[group[-1]],
            "count_over_33_3_ms": len(group),
            "max_ms": max(frames[i] for i in group),
            "max_at_seconds": ends[max(group, key=lambda i: frames[i])],
            "load_samples_near_cluster": [sample for sample in window.get("load_samples", [])
                if ends[group[0]] - 1 <= sample["seconds"] <= ends[group[-1]] + 1],
        } for group in groups],
        "correlations": correlations,
        "cached_monitor_runs": {name: held_samples(window[name], frames)
            for name in ("cpu_process_ms", "physics_ms")},
        "following_load_probe": subset_summary(sorted(after_probe)),
        "other_intervals": subset_summary([i for i in range(len(frames)) if i not in after_probe]),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    windows = []
    for directory in args.directories:
        source = read(directory / "paired-summary.json")
        scenarios = {reference["scenario"] for case in source["cases"].values()
            for references in case["windows"].values() for reference in references}
        scenarios.update(f"normal-{period}" for period in ("day", "night")
            if (directory / f"normal-{period}.json").exists())
        windows.extend(analyze(directory / f"{scenario}.json") for scenario in sorted(scenarios))
    output = {
        "method": "Read-only offline analysis of all completed raw windows; inputs and their summary percentiles unchanged.",
        "limits": [
            "Correlations are associations, not causal attribution; delayed render samples may describe a different frame.",
            "Lag k pairs wall_frame[i] with metric[i+k]; positive lag means the monitor reports later.",
            "CPU process/physics monitor samples repeat for many frames; they are not independent per-frame measurements.",
            "Spike clustering is descriptive, uses a predeclared 250 ms gap, and never removes a frame from an aggregate.",
            "Raw windows lack absolute monotonic/UTC start and process-frame IDs; global periodicity cannot be established precisely from these files alone.",
            "Frames following load snapshots are observational subsets, not a probe-disabled experiment.",
        ],
        "window_count": len(windows), "total_frames": sum(w["summary_unchanged"]["frames"] for w in windows),
        "total_over_33_3_ms": sum(w["summary_unchanged"]["over_33_3_ms"] for w in windows),
        "windows": windows,
        "harness_review": {
            "sample_loop": "tests/measure/measure_sport_coupe_redesign.gd:218-266",
            "all_file_writes_hashes_and_screenshots_after_loop": "tests/measure/measure_sport_coupe_redesign.gd:267-300",
            "load_probe": "tests/measure/measure_sport_coupe_redesign.gd:394-404; O(vehicle_count), about once per second",
            "normal_telemetry_also_active": "runtime/SessionDiagnostics.cs; runtime/SessionSystemProfile.gd",
            "observed": "No readback, hashing or file write occurs inside the benchmark sample loop. Telemetry and array append overhead exists but was not timed separately. Post-window write/readback is followed by next-window warmup.",
            "cannot_exclude": "Concurrent external CPU/GPU workload, clocks/power/thermal changes, driver waits, garbage collection, uninstrumented engine work or profiler overhead.",
        },
        "minimal_instrumentation_proposal": [
            "Write a sample-start marker with scenario, variant, PID, Time.get_ticks_usec, UTC and Engine.get_process_frames after warmup; use the same markers in SessionDiagnostics.",
            "Record each accepted frame's end_usec and process_frame alongside existing arrays. Record physics-frame deltas and focus changes; retain all frames and original wall intervals.",
            "Measure sampler body duration and load_snapshot duration with ticks into preallocated numeric buffers, recording that this work is charged to the following frame interval. Serialize only after collection.",
            "Reuse existing SessionDiagnostics system spans instead of duplicating scans. Add GC collection-count and cumulative-pause deltas only if the existing telemetry cannot identify a pause.",
            "Collect timestamped total CPU versus game-process CPU and GPU utilization/clocks/power/temperature externally at low cadence, with one collector process and its own overhead recorded. No overlay, readback or forced synchronization.",
            "Fix the finite A/B window count and acceptance conditions before running. Keep visual quality/AI/physics enabled; do not discard intervals based on FPS or resource utilization.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"output":str(args.output),"windows":output["window_count"],"frames":output["total_frames"],"over_33_3_ms":output["total_over_33_3_ms"]}))


if __name__ == "__main__":
    main()
