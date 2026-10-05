"""Analyze bounded rendered stall captures without assigning wall time to GPU/solver.

Usage: python tests/measure/analyze_intermittent_stalls.py capture.json
       --output analysis.json --markdown analysis.md

All frames determine percentiles; the retained circular intervals only explain
individual peaks. Work spans are inclusive and are never added to their parents.
"""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from pathlib import Path
from typing import Any


def number(value: Any, default: float | None = None) -> float | None:
    try:
        result = float(value)
        return result if math.isfinite(result) else default
    except (TypeError, ValueError):
        return default


def usec(row: dict[str, Any], key: str) -> int | None:
    value = number(row.get(key))
    return int(value) if value is not None else None


def duration_ms(row: dict[str, Any]) -> float | None:
    start, end = usec(row, "start_usec"), usec(row, "end_usec")
    if start is not None and end is not None:
        return (end - start) / 1000.0
    return number(row.get("ms", row.get("frame_ms")))


def metrics(values: list[float]) -> dict[str, Any]:
    if not values:
        return {"frames": 0, "seconds": 0.0, "status": "not_measured"}
    ordered = sorted(values)
    total_ms = sum(values)
    seconds = total_ms / 1000.0
    # Same lower empirical quantile as measure_performance_plan.gd.
    result: dict[str, Any] = {
        "frames": len(values),
        "seconds": seconds,
        "fps": len(values) / seconds if seconds > 0 else None,
        "mean_ms": total_ms / len(values),
        "p50_ms": ordered[int((len(ordered) - 1) * .50)],
        "p95_ms": ordered[int((len(ordered) - 1) * .95)],
        "p99_ms": ordered[int((len(ordered) - 1) * .99)],
        "max_ms": ordered[-1],
    }
    for label, threshold in (("33_3", 33.3), ("66_7", 66.7)):
        count = sum(value > threshold for value in values)
        result[f"over_{label}_ms"] = count
        result[f"over_{label}_per_second"] = count / seconds if seconds > 0 else None
        result[f"over_{label}_percent"] = 100.0 * count / len(values)
    return result


def frame_id(row: dict[str, Any]) -> Any:
    return row.get("frame", row.get("process_frame"))


def clipped_span(row: dict[str, Any], start: int, end: int) -> tuple[int, int] | None:
    a, b = usec(row, "start_usec"), usec(row, "end_usec")
    if a is None or b is None or b < a:
        return None
    a, b = max(a, start), min(b, end)
    return (a, b) if b > a else None


def covered_usec(spans: list[tuple[int, int]]) -> int:
    total, current_start, current_end = 0, None, None
    for start, end in sorted(spans):
        if current_end is None or start > current_end:
            if current_end is not None:
                total += current_end - current_start
            current_start, current_end = start, end
        else:
            current_end = max(current_end, end)
    if current_end is not None:
        total += current_end - current_start
    return total


def counter_delta(begin: Any, end: Any) -> dict[str, Any]:
    if not isinstance(begin, list) or not isinstance(end, list) or len(begin) < 7 or len(end) < 7:
        return {"available": False}
    if begin[5] != 1 or end[5] != 1 or begin[1] != end[1]:
        return {"available": False, "reason": "invalid_counter_or_thread_change"}
    numeric_begin = [number(value) for value in begin[2:5]]
    numeric_end = [number(value) for value in end[2:5]]
    if None in numeric_begin or None in numeric_end:
        return {"available": False, "reason": "counter_not_numeric"}
    kernel, user, cycles = [last - first for first, last in zip(numeric_begin, numeric_end)]
    if min(kernel, user, cycles) < 0:
        return {"available": False, "reason": "non_monotonic_counter"}
    return {
        "available": True,
        "thread_id": begin[1],
        "kernel_ms": kernel / 1000.0,
        "user_ms": user / 1000.0,
        "accounted_cpu_ms": (kernel + user) / 1000.0,
        "cycles": cycles,
        "processor_begin": begin[6],
        "processor_end": end[6],
        "ready_wait_split": "not_captured_by_thread_counters",
        "scope": "Coarse Windows thread accounting; cycles are not elapsed CPU time.",
    }


def interval_detail(row: dict[str, Any]) -> dict[str, Any]:
    start, end = usec(row, "start_usec"), usec(row, "end_usec")
    if start is None or end is None or end < start:
        return {"error": "invalid_interval_clock"}
    ticks = row.get("physics_ticks", [])
    ticks = [tick for tick in ticks if isinstance(tick, dict)] if isinstance(ticks, list) else []
    tick_spans = [span for tick in ticks if (span := clipped_span(tick, start, end))]
    tick_durations = [(b - a) / 1000.0 for a, b in tick_spans]
    warnings = []
    if len(tick_spans) != len(ticks):
        warnings.append("Some callback tick clocks are invalid or outside this interval.")
    steps = number(row.get("physics_steps"), len(tick_spans))
    if len(tick_spans) != int(steps):
        warnings.append("Retained callback tick count differs from physical step count.")
    tick_union = covered_usec(tick_spans)
    if tick_union != sum(b - a for a, b in tick_spans):
        warnings.append("Callback tick spans overlap; the union is used for uncovered wall time.")
    draw_pre, draw_post = usec(row, "draw_pre_usec"), usec(row, "draw_post_usec")
    draw_valid = (row.get("draw_pair_valid", True) and draw_pre is not None and draw_post is not None
                  and start <= draw_pre <= draw_post <= end)
    draw_span = (draw_pre, draw_post) if draw_valid else None
    covered = tick_spans + ([draw_span] if draw_span else [])
    process_end = usec(row, "process_callbacks_end_usec")
    tick_end = max((span[1] for span in tick_spans), default=start)
    process_tail = ((process_end - tick_end) / 1000.0
                    if process_end is not None and tick_end <= process_end <= end else None)
    between_ticks = [(b[0] - a[1]) / 1000.0 for a, b in zip(sorted(tick_spans), sorted(tick_spans)[1:])
                     if b[0] >= a[1]]
    work = row.get("work", [])
    if not isinstance(work, list):
        work = []
    work = [item for item in work if isinstance(item, dict)]
    selected_work = []
    for item in work:
        span_ms = duration_ms(item)
        if span_ms is None:
            selected_work.append(item)
            continue
        selected_work.append({**item, "ms": span_ms, "inclusive": True})
    selected_work.sort(key=lambda item: number(item.get("ms"), -1), reverse=True)
    return {
        "physics_callback_wall_ms": sum(tick_durations),
        "physics_tick_wall_ms": tick_durations,
        "physics_callback_cpu": [counter_delta(tick.get("thread_start"), tick.get("thread_end")) for tick in ticks],
        "between_physics_callbacks_wall_ms": sum(between_ticks),
        "draw_wall_ms": (draw_post - draw_pre) / 1000.0 if draw_valid else None,
        "draw_pair_valid": bool(draw_valid),
        "draw_thread_cpu": counter_delta(row.get("thread_draw_pre"), row.get("thread_draw_post")),
        "after_last_physics_to_process_end_wall_ms": process_tail,
        "outside_physics_callbacks_and_draw_wall_ms": (end - start - covered_usec(covered)) / 1000.0,
        "frame_thread_cpu": counter_delta(row.get("thread_start"), row.get("thread_end")),
        "observer_wall_usec": row.get("observer_wall_usec"),
        "observer_calls": row.get("observer_calls"),
        "capture_usec": row.get("capture_usec"),
        "context": row.get("context", {}),
        "pipelines": row.get("pipelines"),
        "work_inclusive_not_summed": selected_work,
        "events": row.get("events", row.get("entity_events", [])),
        "warnings": warnings,
        "scope": "Callbacks include nested script/native calls. Draw is wall time, not exclusive GPU. Gaps may contain solver, synchronization, dispatch or scheduling; there is no exclusive attribution.",
    }


def analyze(data: dict[str, Any], threshold_ms: float) -> dict[str, Any]:
    frames = data.get("frames", [])
    if not isinstance(frames, list):
        raise ValueError("frames must be an array")
    intervals = data.get("intervals", [])
    if not isinstance(intervals, list):
        raise ValueError("intervals must be an array")
    valid_frames, invalid_rows = [], []
    for index, row in enumerate(frames):
        if not isinstance(row, dict):
            invalid_rows.append({"index": index, "reason": "frame_not_object"})
            continue
        value = duration_ms(row)
        if value is None or value <= 0:
            invalid_rows.append({"index": index, "reason": "invalid_frame_duration"})
            continue
        valid_frames.append({**row, "ms": value})
    by_bounds = {(usec(row, "start_usec"), usec(row, "end_usec")): row
                 for row in intervals if isinstance(row, dict)}
    by_frame = {frame_id(row): row for row in intervals if isinstance(row, dict) and frame_id(row) is not None}
    phases = sorted({str(row.get("phase", "unspecified")) for row in valid_frames})
    timeline = []
    for row in valid_frames:
        if row["ms"] < threshold_ms:
            continue
        detail = by_bounds.get((usec(row, "start_usec"), usec(row, "end_usec")))
        if detail is None:
            detail = by_frame.get(frame_id(row))
        timeline.append({
            "frame": frame_id(row), "phase": row.get("phase", "unspecified"),
            "start_usec": row.get("start_usec"), "end_usec": row.get("end_usec"),
            "ms": row["ms"], "physics_steps": row.get("physics_steps"),
            "focused": row.get("focused"), "detail_retained": detail is not None,
            "detail": interval_detail(detail) if detail is not None else {},
        })
    counter_keys = ("observer_wall_usec", "capture_usec")
    observer: dict[str, Any] = {"reported": data.get("observer", {}), "scope": "Costs included in measured frames; no correction/subtraction. Retained intervals alone cannot quantify whole-run overhead or engine dispatch cost."}
    for key in counter_keys:
        values = [number(row.get(key)) for row in intervals if isinstance(row, dict)]
        values = [value for value in values if value is not None and value >= 0]
        observer[f"retained_{key}"] = {
            "samples": len(values), "sum_usec": sum(values),
            "max_usec": max(values) if values else None,
        }
    counts = Counter(row.get("physics_steps", "unknown") for row in valid_frames)
    return {
        "label": data.get("label", ""), "input_schema": data.get("format_version"),
        "configuration": data.get("configuration", data.get("config", {})),
        "clock": data.get("clock", {}), "capture_validity": data.get("validity", data.get("invalid", None)),
        "analysis_validity": {"invalid_frame_rows": invalid_rows, "missing_peak_details": sum(not row["detail_retained"] for row in timeline)},
        "summary": metrics([row["ms"] for row in valid_frames]),
        "summary_all": metrics([row["ms"] for row in valid_frames]),
        "gameplay_summary": metrics([row["ms"] for row in valid_frames if row.get("phase") not in ("loading", "tail")]),
        "loading_summary": metrics([row["ms"] for row in valid_frames if row.get("phase") == "loading"]),
        "tail_summary": metrics([row["ms"] for row in valid_frames if row.get("phase") == "tail"]),
        "phases": {phase: metrics([row["ms"] for row in valid_frames if str(row.get("phase", "unspecified")) == phase]) for phase in phases},
        "unfocused_frames": sum(row.get("focused") is False for row in valid_frames),
        "unknown_focus_frames": sum(not isinstance(row.get("focused"), bool) for row in valid_frames),
        "physics_step_histogram": {str(key): value for key, value in counts.items()},
        "timeline_threshold_ms": threshold_ms, "timeline": timeline,
        "observer": observer, "events": data.get("events", []),
        "limitations": [
            "No ready/running/waiting attribution without a native scheduling trace.",
            "No GPU or solver exclusive attribution from callback/draw wall-time boundaries.",
            "Work spans are inclusive; parent/child durations are retained separately and never added.",
            "A missing signature in a finite run is inconclusive about elimination.",
            "All valid frame rows, including initial passage/warmup, remain in the total and separate phase summaries.",
        ],
    }


def markdown(result: dict[str, Any]) -> str:
    def fmt(value: Any) -> str:
        return f"{value:.3f}" if isinstance(value, (float, int)) else "n/d"

    lines = [f"# Análise: {result['label']}", "", "Percentis usam todos os frames válidos; o detalhe circular explica os picos preservados.", "",
             "| Fase | Frames | s | FPS | p50/p95/p99 ms | Máx. ms | >33,3 / >66,7 | Frequência /s |",
             "|---|---:|---:|---:|---|---:|---|---|"]
    summaries = [("total", result["summary"])]
    if result.get("loading_summary", {}).get("frames", 0):
        summaries.append(("gameplay (sem loading/tail)", result["gameplay_summary"]))
    for phase, stats in [*summaries, *result["phases"].items()]:
        if stats["frames"] == 0:
            lines.append(f"| {phase} | 0 | 0 | n/d | n/d | n/d | n/d | n/d |")
            continue
        lines.append(f"| {phase} | {stats['frames']} | {fmt(stats['seconds'])} | {fmt(stats['fps'])} | "
                     f"{fmt(stats['p50_ms'])}/{fmt(stats['p95_ms'])}/{fmt(stats['p99_ms'])} | {fmt(stats['max_ms'])} | "
                     f"{stats['over_33_3_ms']}/{stats['over_66_7_ms']} | {fmt(stats['over_33_3_per_second'])}/{fmt(stats['over_66_7_per_second'])} |")
    lines += ["", "| Frame | Fase | Início monotônico µs | Frame ms | Passos | Callbacks físicos ms | pre→post draw ms | Fora desses spans ms |",
              "|---:|---|---:|---:|---:|---:|---:|---:|"]
    for row in result["timeline"]:
        detail = row["detail"]
        lines.append(f"| {row['frame']} | {row['phase']} | {row['start_usec']} | {fmt(row['ms'])} | {row['physics_steps']} | "
                     f"{fmt(detail.get('physics_callback_wall_ms'))} | {fmt(detail.get('draw_wall_ms'))} | "
                     f"{fmt(detail.get('outside_physics_callbacks_and_draw_wall_ms'))} |")
    lines += ["", "Tempos acima são de parede. Gaps não identificam exclusivamente solver, e pre/post draw não mede exclusivamente GPU. Spans de trabalho são inclusivos e não são somados.", "",
              "Detalhe por pico, custos dos observadores, eventos e validade estão no JSON de análise.", ""]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--threshold-ms", type=float, default=25.0)
    args = parser.parse_args()
    if not math.isfinite(args.threshold_ms) or args.threshold_ms <= 0:
        parser.error("--threshold-ms must be finite and positive")
    for output in (args.output, args.markdown):
        if output and output.resolve() == args.capture.resolve():
            parser.error("analysis output must not overwrite the capture")
    if args.output and args.markdown and args.output.resolve() == args.markdown.resolve():
        parser.error("JSON and Markdown outputs must use different paths")
    data = json.loads(args.capture.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        parser.error("capture must contain a JSON object")
    result = analyze(data, args.threshold_ms)
    if args.output:
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(markdown(result), encoding="utf-8")
    print(json.dumps({key: result[key] for key in ("label", "summary", "gameplay_summary", "loading_summary", "phases", "analysis_validity", "unfocused_frames")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
