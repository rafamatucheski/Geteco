"""Analisa amostras do oeste sem somar spans inclusivos nem monitores de 1 s."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re
from statistics import median
from typing import Any


PHASE_FIELDS = (
    "physics_callback_ms", "process_callback_ms", "process_to_deferred_ms",
    "deferred_to_render_pre_ms", "render_bracket_ms", "post_draw_to_physics_ms",
    "pre_process_gap_ms", "telemetry_usec", "session_diagnostics_telemetry_usec",
    "session_profile_telemetry_usec",
)
STATIC_ROOT_PHASES = {
    "vehicle.physics": "physics", "actor.physics": "physics",
    "west.traffic_yield.physics": "physics", "west.street.physics": "physics",
    "west.parking.physics": "physics", "west.camera.process": "process",
    "west.world.process": "process", "west.region.process": "process",
    "west.audio.world_process": "process", "west.audio.nearby_process": "process",
    "west.audio.weather_process": "process", "west.telemetry.profile_process": "process",
    "reflection.process": "process",
    "gameplay.physics": "physics", "urban.physics": "physics", "terminal.physics": "physics",
    "vehicle_tires.redraw_marks": "process",
}
STATIC_PARENTS = {
    "street.pre.people": "vehicle.street_pre", "street.pre.props": "vehicle.street_pre",
    "street.pre.crush": "vehicle.street_pre", "street.pre.crush_audio": "vehicle.street_pre",
    "street.pre.people.cast": "street.pre.people", "street.pre.props.query": "street.pre.props",
    "street.pre.props.cast": "street.pre.props", "street.pre.props.hit": "street.pre.props",
    "street.post.contacts": "vehicle.street_post", "street.post.slide": "vehicle.street_post",
    "street.post.crush": "vehicle.street_post", "street.slide.move_and_collide": "street.post.slide",
    "street.slide.rotate": "street.post.slide", "street.crash.damage_self": "street.crash",
    "street.crash.damage_other": "street.crash", "street.crash.impulse": "street.crash",
    "street.glass.resources": "street.glass", "street.glass.attach": "street.glass",
    "street.scatter.geometry": "street.scatter", "street.scatter.commit": "street.scatter",
    "street.scatter.material": "street.scatter", "street.scatter.attach": "street.scatter",
    "west.street.watch_people": "west.street.physics",
    "west.traffic_yield.hazards": "west.traffic_yield.physics",
    "west.traffic_yield.agent_tick": "west.traffic_yield.physics",
    "west.audio.radio": "west.audio.world_process", "west.audio.ambience": "west.audio.world_process",
    "west.audio.nearby_select": "west.audio.nearby_process",
    "west.audio.road_contacts": "vehicle.effects",
    "west.vehicle.can_rotate": "vehicle.drive", "west.vehicle.junction_gate": "vehicle.drive",
    "west.vehicle.route_projection": "vehicle.drive", "west.vehicle.escape": "vehicle.drive",
    "reflection.batch": "reflection.process", "reflection.dynamic": "reflection.process",
    "reflection.registration": "reflection.process",
    "vehicle.effects.tires": "vehicle.effects", "vehicle.effects.powertrain": "vehicle.effects",
    "vehicle.effects.impact": "vehicle.effects", "vehicle_tires.contacts": "vehicle.effects.tires",
    "vehicle_tires.skid_audio": "vehicle.effects.tires", "vehicle_tires.skid_voice": "vehicle_tires.skid_audio",
    "vehicle_tires.surface_emit": "vehicle.effects.tires", "vehicle_tires.surface_end": "vehicle_tires.redraw_marks",
    "urban.refresh_presence": "urban.physics",
    "west.camera.terrain_offset": "west.camera.process", "west.camera.tunnel_chase": "west.camera.process",
    "west.camera.cutaway": "west.camera.process",
    "west.world.residency": "multiple_contexts", "west.world.logical_region": "west.world.process",
    "west.world.population_job": "west.world.process",
    "west.router.csharp.plan": "west.router.plan", "west.router.csharp.build_path": "multiple_contexts",
    "west.router.csharp.build": "multiple_contexts", "west.router.csharp.nearest_edge": "multiple_contexts",
    "west.router.csharp.search": "multiple_contexts", "west.router.plan": "caller_callback",
    "west.router.departure": "caller_callback", "west.router.spawn_candidates": "caller_callback",
}
SWITCH_NAMES = {
    "--population=0": "population0",
    "--no-traffic": "no_traffic",
    "--no-traffic-yield": "no_traffic_yield",
    "--no-roadside-parking": "no_roadside_parking",
    "--no-density": "no_density",
}


def stats(values: list[float]) -> dict[str, Any]:
    """Percentil por índice, como os runners Godot existentes; zeros permanecem."""
    ordered = sorted(values)
    if not ordered:
        return {"count": 0}
    result = {"count": len(ordered), "mean": sum(ordered) / len(ordered),
              "min": ordered[0], "max": ordered[-1], "zeros": ordered.count(0.0)}
    for name, fraction in (("p50", .5), ("p95", .95), ("p99", .99)):
        result[name] = ordered[min(len(ordered) - 1, int(len(ordered) * fraction))]
    return result


def number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) else None


def config_name(report: dict[str, Any]) -> str:
    settings = report.get("settings", {})
    explicit = report.get("config", settings.get("config", ""))
    if explicit:
        return str(explicit)
    args = settings.get("args", report.get("args", []))
    switches = [name for arg, name in SWITCH_NAMES.items() if arg in args]
    environment = settings.get("env", settings.get("environment", {}))
    profile = settings.get("HARBOR_SESSION_PROFILE", environment.get("HARBOR_SESSION_PROFILE"))
    if str(profile) == "0":
        switches.append("session_profile0")
    if settings.get("trace_enabled") is False and environment.get("HARBOR_WEST_CPU_SPANS") == "0":
        switches.append("instrumentation0")
    elif settings.get("trace_enabled") is False:
        switches.append("trace_off")
    elif environment.get("HARBOR_WEST_CPU_SPANS") == "0":
        switches.append("spans_off")
    for script in settings.get("disabled_scripts", []):
        switches.append("disabled:" + str(script))
    return "+".join(switches) or "baseline"


def span_milliseconds(row: Any) -> float:
    if isinstance(row, (int, float)):
        return float(row)
    for field, divisor in (("total_usec", 1000.0), ("total_ms", 1.0),
                           ("us", 1000.0), ("ms", 1.0)):
        value = number(row.get(field))
        if value is not None:
            return value / divisor
    return 0.0


def sample_spans(sample: dict[str, Any]) -> dict[str, Any]:
    return sample.get("spans", sample.get("systems", {}))


def definitions(report: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows = report.get("span_definitions", {})
    if isinstance(rows, list):
        return {str(row.get("label", row.get("name"))): row for row in rows}
    return {label: row if isinstance(row, dict) else {"note": row} for label, row in rows.items()}


def reviewed_definition(label: str, declaration: dict[str, Any], parent_map: dict[str, Any]) -> dict[str, Any]:
    result = dict(declaration)
    mapping = parent_map.get("labels", {}).get(label)
    if label == "vehicle_tires.redraw_marks":
        result.update(parent=None, phase="process", source_review="Timer.timeout_to_tick_mark_lifetime; default_idle_timer")
    elif label in ("gameplay.physics", "urban.physics", "terminal.physics"):
        result.update(parent=None, phase="physics", source_review="existing_top_level_physics_callback")
    elif label.startswith("vehicle.effects."):
        result.update(parent="vehicle.effects", phase="physics", source_review="VehicleEffects.physics_tick")
    elif mapping is not None:
        result.update(mapping)
        if mapping.get("kind") == "root":
            result["parent"] = None
        elif "parents" in mapping:
            result["parent"] = "multiple_contexts" if len(mapping["parents"]) > 1 else mapping["parents"][0]
        result["source_review"] = "span-parent-map.json"
    elif label in STATIC_ROOT_PHASES:
        result.update(parent=None, phase=STATIC_ROOT_PHASES[label], source_review="static_callback_boundary")
    elif label in STATIC_PARENTS:
        result.update(parent=STATIC_PARENTS[label], source_review="static_synchronous_call_boundary")
        if label.startswith(("street.pre.", "street.post.", "street.slide.", "vehicle_tires.")) or label in ("west.audio.road_contacts", "urban.refresh_presence"):
            result["phase"] = "process" if label == "vehicle_tires.surface_end" else "physics"
    elif label.startswith("vehicle.") and label not in ("vehicle.physics", "vehicle.doors.prepare"):
        result.update(parent="vehicle.physics", phase="physics", source_review="static_vehicle_tick")
    elif label.startswith("actor.") and label != "actor.physics":
        result.update(parent="actor.physics", phase="physics", source_review="static_actor_tick")
    elif label.startswith("west.vehicle."):
        result.update(parent="multiple_contexts", phase="physics",
                      source_review="vehicle.drive_or_external_driver; cannot_subtract_exclusive_cost")
    elif label.startswith("west.world.operation."):
        result.update(parent="multiple_contexts", source_review="production_trace_helper_with_startup_and_runtime_callers")
    return result


def console_errors(path: Path) -> tuple[Path, list[dict[str, Any]]]:
    console_path = path.with_suffix(".console.log")
    if not console_path.is_file():
        return console_path, []
    payload = console_path.read_bytes()
    encoding = "utf-16" if payload.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    lines = payload.decode(encoding, errors="replace").splitlines()
    pattern = re.compile(r"^\s*(SCRIPT ERROR:|ERROR:|FATAL ERROR:|Unhandled exception|UnhandledException)", re.IGNORECASE)
    errors = []
    for index, line in enumerate(lines):
        if not pattern.match(line):
            continue
        context = [line.strip()]
        for following in lines[index + 1:index + 18]:
            if pattern.match(following) or following.startswith("PROFILE_WEST"):
                break
            context.append(following.rstrip())
        errors.append({"category": "script" if "SCRIPT ERROR:" in line.upper() else "engine_or_managed",
                       "line": index + 1, "message": line.strip(), "context": context})
    return console_path, errors


def analyze_run(path: Path) -> dict[str, Any]:
    report = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(report.get("samples"), list):
        raise ValueError("Arquivo não contém samples por quadro; não é rodada deste profiler")
    samples = [row for row in report["samples"] if row.get("phase", "measurement") == "measurement"]
    if not samples:
        raise ValueError("Nenhum quadro de medição; aquecimento não conta")
    frame_values = [number(row.get("frame_ms", row.get("interval_ms"))) for row in samples]
    if any(value is None or value <= 0 for value in frame_values):
        raise ValueError("Quadro sem duração positiva finita")
    frame_values = [float(value) for value in frame_values]
    span_definitions = definitions(report)
    parent_map_path = path.parent / "span-parent-map.json"
    parent_map = json.loads(parent_map_path.read_text(encoding="utf-8-sig")) if parent_map_path.is_file() else {}
    labels = sorted(set(span_definitions) | {label for sample in samples for label in sample_spans(sample)})
    root_names = set(report.get("root_names", [])) | set(STATIC_ROOT_PHASES) | set(parent_map.get("root_names", []))
    span_ranking = []
    for label in labels:
        rows = [sample_spans(sample).get(label, {}) for sample in samples]
        span_values = [span_milliseconds(row) for row in rows]
        declaration = reviewed_definition(label, span_definitions.get(label, {}), parent_map)
        parent = declaration.get("parent", "unknown")
        kind = "root" if label in root_names else ("nested" if parent not in (None, "", "unknown") else "inclusive_unknown")
        span_row = {"label": label, "kind": kind, "parent": parent,
                             "phase": declaration.get("phase", "unknown"),
                             "inclusive": declaration.get("inclusive", True),
                             "source_review": declaration.get("source_review", "unreviewed"),
                             "possible_parents": declaration.get("parents", []),
                             "milliseconds_per_frame": stats(span_values),
                             "calls": sum(int(row.get("calls", 0)) for row in rows if isinstance(row, dict)),
                             "frames_with_calls": sum(bool(row.get("calls", 0)) for row in rows if isinstance(row, dict))}
        if declaration.get("phase") == "physics":
            eligible = [sample for sample in samples if sample.get("phase_valid", False) and int(sample.get("physics_steps", 0)) > 0]
            normalized = [span_milliseconds(sample_spans(sample).get(label, {})) / int(sample["physics_steps"]) for sample in eligible]
            total_steps = sum(int(sample["physics_steps"]) for sample in eligible)
            total_ms = sum(span_milliseconds(sample_spans(sample).get(label, {})) for sample in eligible)
            span_row["milliseconds_per_step_frame_average"] = stats(normalized)
            span_row["mean_per_step_weighted_ms"] = total_ms / total_steps if total_steps else None
            span_row["normalization_scope"] = "Média do span por passo dentro de cada quadro; quantis não são durações das chamadas individuais"
        span_ranking.append(span_row)
    span_ranking.sort(key=lambda row: row["milliseconds_per_frame"].get("mean", 0), reverse=True)
    phase_stats = {}
    valid_samples = [sample for sample in samples if sample.get("phase_valid", False)]
    for field in PHASE_FIELDS:
        values = [number(row.get(field)) for row in valid_samples]
        values = [value for value in values if value is not None and value >= 0]
        if field.endswith("_usec"):
            values = [value / 1000.0 for value in values]
        phase_stats[field.removesuffix("_usec") + ("_ms" if field.endswith("_usec") else "")] = stats(values)
    # Somente callbacks regulares revisados entram; o Timer de pneus pode cair fora dos probes.
    residuals = {}
    phase_roots = report.get("phase_roots", {})
    guaranteed = report.get("phase_roots_guaranteed_contained", False)
    residual_basis = "explicit_producer_guarantee"
    inferred = bool(parent_map) and report.get("settings", {}).get("trace_enabled") is True and not report.get("invalid", [])
    inferred = inferred and report.get("aggregate_dropped_calls", 0) == 0 and report.get("physics_probe_mismatches", 0) == 0
    if inferred and not guaranteed:
        phase_roots = {phase: [label for label, root_phase in STATIC_ROOT_PHASES.items()
                               if root_phase == phase and label != "vehicle_tires.redraw_marks"]
                       for phase in ("physics", "process")}
        guaranteed = True
        residual_basis = "source_review_regular_synchronous_callback_roots; aggregate_finish_time_assignment"
    if guaranteed:
        for phase, names in phase_roots.items():
            field = phase + "_callback_ms"
            eligible = all(name in root_names for name in names)
            residual_values, negative_frames = [], 0
            if eligible:
                for sample in valid_samples:
                    bracket = number(sample.get(field))
                    complete = sample.get("spans_complete", False) or (inferred and sample.get("span_dropped_calls", 0) == 0)
                    if bracket is None or not complete:
                        continue
                    covered = sum(span_milliseconds(sample_spans(sample).get(name, {})) for name in names)
                    remaining = bracket - covered
                    if remaining < -0.01:
                        negative_frames += 1
                    else:
                        residual_values.append(max(0.0, remaining))
            residuals[phase] = {"milliseconds_per_frame": stats(residual_values),
                                "invalid_negative_frames": negative_frames,
                                "root_names": names,
                                "basis": residual_basis,
                                "scope": "Complemento dos callbacks; inclui overhead da instrumentação e scripts sem span, sem atribuição causal"}
    gpu_values, cpu_values = [], []
    for sample in samples:
        timings = sample.get("viewport_timings", [])
        if timings:
            gpu_values.append(sum(float(row.get("gpu_ms", 0.0)) for row in timings))
            cpu_values.append(sum(float(row.get("cpu_ms", 0.0)) for row in timings))
    step_counts = [int(row.get("physics_steps", 0)) for row in samples]
    steps_histogram = {str(key): value for key, value in sorted(Counter(step_counts).items())}
    exact_tick_values = [float(tick["end_usec"] - tick["start_usec"]) / 1000.0 for sample in valid_samples
                         for tick in sample.get("physics_ticks", []) if tick["end_usec"] >= tick["start_usec"]]
    step_average_values = [float(sample["physics_callback_ms"]) / int(sample["physics_steps"]) for sample in valid_samples
                           if int(sample.get("physics_steps", 0)) > 0]
    steps_groups = {}
    for steps in sorted(set(step_counts)):
        selected = [row for row in samples if int(row.get("physics_steps", 0)) == steps]
        steps_groups[str(steps)] = {
            "frame_ms": stats([float(row.get("frame_ms", row.get("interval_ms"))) for row in selected]),
            "physics_callback_ms": stats([float(row["physics_callback_ms"]) for row in selected
                                           if row.get("phase_valid", False) and number(row.get("physics_callback_ms")) is not None]),
        }
        if steps > 0:
            steps_groups[str(steps)]["physics_callback_ms_per_step_frame_average"] = stats([
                float(row["physics_callback_ms"]) / steps for row in selected if row.get("phase_valid", False)])
            steps_groups[str(steps)]["span_ms_per_step_frame_average"] = {
                span["label"]: stats([span_milliseconds(sample_spans(row).get(span["label"], {})) / steps
                                      for row in selected if row.get("phase_valid", False)])
                for span in span_ranking if span["phase"] == "physics"}
    settings = report.get("settings", {})
    invalid = list(report.get("invalid", []))
    console_path, runtime_errors = console_errors(path)
    if runtime_errors:
        invalid.append("runtime_console_errors")
    counters = {}
    for field in ("people", "vehicles", "draw_calls", "primitives", "density_scale", "span_dropped_calls"):
        values = [number(sample.get(field)) for sample in samples]
        counters[field] = stats([value for value in values if value is not None])
    repetition = report.get("repetition", settings.get("repetition"))
    if repetition is None:
        match = re.search(r"(?:_|-)(\d+)$", path.stem)
        repetition = int(match.group(1)) if match else None
    frame_stats = stats(frame_values)
    frame_stats.update({"fps": len(frame_values) * 1000.0 / sum(frame_values),
                        "duration_seconds": sum(frame_values) / 1000.0,
                        "above_33_3_ms": sum(value > 33.3 for value in frame_values),
                        "above_66_7_ms": sum(value > 66.7 for value in frame_values)})
    inputs_path = path.with_suffix(".inputs.json")
    inputs = json.loads(inputs_path.read_text(encoding="utf-8-sig")) if inputs_path.is_file() else {}
    engine = report.get("engine", {})
    conditions = {"resolution": settings.get("resolution"), "vsync": settings.get("vsync"),
                  "max_fps": settings.get("max_fps"), "renderer": report.get("hardware", {}).get("renderer"),
                  "build": report.get("build"), "engine": engine.get("string") if isinstance(engine, dict) else engine,
                  "physics_ticks_per_second": settings.get("physics_ticks_per_second"),
                  "max_physics_steps_per_frame": settings.get("max_physics_steps_per_frame"),
                  "route": report.get("route", {}).get("points"), "speed_mps": report.get("route", {}).get("speed_mps")}
    state = {"focused_frames": sum(sample.get("focused") is True for sample in samples),
             "unfocused_frames": sum(sample.get("focused") is False for sample in samples),
             "focus_unknown_frames": sum("focused" not in sample for sample in samples),
             "paused_frames": sum(sample.get("paused") is True for sample in samples)}
    state["focused_percent"] = state["focused_frames"] * 100.0 / len(samples)
    state["unfocused_percent"] = state["unfocused_frames"] * 100.0 / len(samples)
    state["focused_duration_seconds"] = sum(float(sample.get("frame_ms", sample.get("interval_ms", 0))) for sample in samples if sample.get("focused") is True) / 1000.0
    state["unfocused_duration_seconds"] = sum(float(sample.get("frame_ms", sample.get("interval_ms", 0))) for sample in samples if sample.get("focused") is False) / 1000.0
    telemetry = report.get("session_telemetry", {})
    telemetry_mean = {key: float(telemetry[field]) / 1000.0 / len(samples)
                      for key, field in (("diagnostics_callback", "measured_usec"), ("system_profile_callback", "profile_measured_usec"))
                      if number(telemetry.get(field)) is not None}
    return {"source": str(path.resolve()), "label": report.get("label", path.stem),
            "config": config_name(report), "repetition": repetition, "settings": settings,
            "frame_ms": frame_stats, "phases_ms": phase_stats,
            "phase_valid_frames": len(valid_samples), "phase_invalid_frames": len(samples) - len(valid_samples),
            "span_ranking": span_ranking, "residuals_ms": residuals,
            "invalid": invalid, "runtime_usable": not invalid, "numerically_valid": not report.get("invalid", []),
            "comparable": not invalid and state["focused_frames"] == len(samples) and state["paused_frames"] == 0,
            "counters": counters,
            "runtime_errors": runtime_errors, "runtime_error_count": len(runtime_errors),
            "console_source": str(console_path.resolve()) if console_path.is_file() else None,
            "runtime_validation": "failed" if runtime_errors else ("passed" if console_path.is_file() else "unavailable"),
            "parent_map_source": str(parent_map_path.resolve()) if parent_map else None,
            "session_telemetry": report.get("session_telemetry", {}),
            "session_telemetry_mean_ms_per_frame": telemetry_mean,
            "source_digest": inputs.get("source_digest"),
            "source_snapshot": str(inputs_path.resolve()) if inputs else None,
            "conditions": conditions, "presentation_state": state,
            "viewport_gpu_ms_sum": stats(gpu_values), "viewport_cpu_ms_sum": stats(cpu_values),
            "physics_steps_histogram": steps_histogram, "by_physics_steps": steps_groups,
            "physics_tick_callback_ms": stats(exact_tick_values),
            "physics_callback_ms_per_step_frame_average": stats(step_average_values),
            "inventories": report.get("inventories", []), "diagnostics": report.get("diagnostics", {})}


def source_provenance(runs: list[dict[str, Any]]) -> dict[str, Any]:
    digests = {run.get("source_digest") for run in runs}
    matching = len(digests) == 1 and None not in digests
    changed_files = set()
    reference_files = None
    for run in runs:
        snapshot = run.get("source_snapshot")
        if snapshot is None:
            continue
        current_files = json.loads(Path(snapshot).read_text(encoding="utf-8-sig")).get("files", {})
        if reference_files is None:
            reference_files = current_files
        else:
            changed_files.update(name for name in set(reference_files) | set(current_files)
                                 if reference_files.get(name) != current_files.get(name))
    return {"matching": matching, "digests": sorted(digest for digest in digests if digest is not None),
            "missing_labels": [run.get("label", run["config"]) for run in runs if run.get("source_digest") is None],
            "changed_file_count": len(changed_files), "changed_files": sorted(changed_files)}


def comparisons(runs: list[dict[str, Any]], baseline: str) -> list[dict[str, Any]]:
    groups = defaultdict(list)
    for run in runs:
        if run.get("runtime_usable", run.get("comparable", True)):
            groups[run["config"]].append(run)
    base = groups.get(baseline, [])
    if not base:
        return []
    output = []
    for config, variants in sorted(groups.items()):
        if config == baseline:
            continue
        row = {"config": config, "baseline": baseline, "baseline_repetitions": len(base),
               "variant_repetitions": len(variants), "metrics": {}}
        provenance = source_provenance(base + variants)
        row["source_provenance"] = provenance
        keys = {key for run in base + variants for key in run.get("conditions", {})}
        different_conditions = {key: {run["label"]: run.get("conditions", {}).get(key) for run in base + variants}
                                for key in keys if len({json.dumps(run.get("conditions", {}).get(key), sort_keys=True) for run in base + variants}) > 1}
        states = {run["label"]: run["presentation_state"]["focused_percent"] for run in base + variants
                  if "presentation_state" in run}
        if states and any(value != 100.0 for value in states.values()):
            different_conditions["focused_percent"] = states
        row["different_conditions"] = different_conditions
        for metric in ("mean", "p50", "p95", "p99"):
            base_values = [run["frame_ms"][metric] for run in base]
            variant_values = [run["frame_ms"][metric] for run in variants]
            base_range = max(base_values) - min(base_values)
            variant_range = max(variant_values) - min(variant_values)
            improvement = median(base_values) - median(variant_values)
            # A soma das amplitudes é conservadora com apenas duas repetições.
            variation = base_range + variant_range
            disjoint = max(variant_values) < min(base_values) or min(variant_values) > max(base_values)
            replicated = len(base_values) >= 2 and len(variant_values) >= 2
            detected = replicated and disjoint and abs(improvement) > variation and provenance["matching"] and not different_conditions
            status = ("redução acima da variação" if improvement > 0 else "aumento acima da variação") if detected else (
                "repetição insuficiente" if not replicated else "efeito não separado da variação")
            if not provenance["matching"]:
                status = "fontes diferentes" if provenance["changed_file_count"] else "proveniência de fontes ausente ou diferente"
            elif different_conditions:
                status = "foco não equivalente" if "focused_percent" in different_conditions else "condições de execução diferentes"
            row["metrics"][metric] = {"baseline_median_ms": median(base_values),
                                       "variant_median_ms": median(variant_values),
                                       "improvement_ms": improvement, "baseline_range_ms": base_range,
                                       "variant_range_ms": variant_range, "conservative_variation_ms": variation,
                                       "separated_from_variation": detected, "status": status}
        output.append(row)
    return output


def format_ms(value: Any) -> str:
    return f"{value:.3f}" if isinstance(value, (int, float)) else "—"


def markdown(analysis: dict[str, Any]) -> str:
    lines = ["# Análise das rodadas do oeste", "",
             "Aquecimento excluído. Spans incluem todos os quadros de medição, inclusive zeros; valores em ms/quadro.",
             "Pais e filhos são inclusivos e não podem ser somados. GPU/CPU de viewport são amostras assíncronas.", "",
             "Comparações usam a mediana dos percentis das rodadas; a amplitude baseline + variante define a variação conservadora.",
             "Duas repetições estimam ruído, sem constituir teste estatístico de significância.", "",
             "| Rodada | Configuração | Quadros | Duração s | FPS | p50 ms | p95 ms | p99 ms | >33,3 | >66,7 | Erros runtime | Estado |", 
             "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|"]
    for run in analysis["runs"]:
        values = run["frame_ms"]
        lines.append(f"| {run['label']} | {run['config']} | {values['count']} | {values['duration_seconds']:.1f} | "
                     f"{values['fps']:.1f} | {values['p50']:.3f} | {values['p95']:.3f} | {values['p99']:.3f} | "
                     f"{values['above_33_3_ms']} | {values['above_66_7_ms']} | {run['runtime_error_count']} | "
                     f"{'inválida' if run['invalid'] else ('sem erros registrados' if run['runtime_validation'] == 'passed' else 'logs ausentes')} |")
    lines += ["", "| Rodada | Focado % | Sem foco % | Pausado quadros | Resolução | Renderer | VSync | Limite FPS |",
              "|---|---:|---:|---:|---|---|---:|---:|"]
    for run in analysis["runs"]:
        state, conditions = run["presentation_state"], run["conditions"]
        lines.append(f"| {run['label']} | {state['focused_percent']:.1f} | {state['unfocused_percent']:.1f} | "
                     f"{state['paused_frames']} | {conditions['resolution']} | {conditions['renderer']} | "
                     f"{conditions['vsync']} | {conditions['max_fps']} |")
    lines += ["", "Quadros sem foco são mantidos e identificados; eventual limitação do driver em segundo plano não foi eliminada por essa tabela."]
    lines += ["", "## Efeito de uma variável", "",
              "| Configuração | Repetições B/V | Redução p50 ms | Variação p50 ms | Critério p50 | Redução p95 ms | Variação p95 ms | Critério p95 |",
              "|---|---:|---:|---:|---|---:|---:|---|"]
    for comparison in analysis["comparisons"]:
        p50, p95 = comparison["metrics"]["p50"], comparison["metrics"]["p95"]
        lines.append(f"| {comparison['config']} | {comparison['baseline_repetitions']}/{comparison['variant_repetitions']} | "
                     f"{p50['improvement_ms']:.3f} | {p50['conservative_variation_ms']:.3f} | {p50['status']} | "
                     f"{p95['improvement_ms']:.3f} | {p95['conservative_variation_ms']:.3f} | {p95['status']} |")
    for comparison in analysis["comparisons"]:
        if not comparison["source_provenance"]["matching"]:
            lines += ["", f"Proveniência {comparison['config']}: `{json.dumps(comparison['source_provenance'], ensure_ascii=False)}`."]
        if comparison["different_conditions"]:
            lines += ["", f"Condições {comparison['config']}: `{json.dumps(comparison['different_conditions'], ensure_ascii=False)}`. "
                      "Rodadas sem erro permanecem nas tabelas; esse contraste não tem equivalência causal."]
    for run in analysis["runs"]:
        lines += ["", f"## {run['label']}", "", f"Fonte: `{run['source']}`", "",
                  f"Bracket válido em {run['phase_valid_frames']} quadros; inválido em {run['phase_invalid_frames']}. "
                  f"Passos físicos por quadro: `{json.dumps(run['physics_steps_histogram'])}`.", "",
                  "| Fase medida | n | Média ms | p50 ms | p95 ms |", "|---|---:|---:|---:|---:|"]
        for label, values in run["phases_ms"].items():
            lines.append(f"| {label} | {values['count']} | {format_ms(values.get('mean'))} | "
                         f"{format_ms(values.get('p50'))} | {format_ms(values.get('p95'))} |")
        if run["invalid"]:
            lines += ["", f"Rodada inválida, excluída dos comparativos: `{json.dumps(run['invalid'], ensure_ascii=False)}`.", ""]
        if run["runtime_errors"]:
            lines += ["", f"Erros durante execução em `{run['console_source']}`; timings preservados somente como diagnóstico:", ""]
            lines += [f"- Linha {row['line']}: {row['message']}" for row in run["runtime_errors"]]
        roots = [row for row in run["span_ranking"] if row["kind"] == "root"]
        lines += ["", "Raízes com fronteira de callback revisada na fonte (sem custo exclusivo):", "",
                  "| Sistema | Média ms | p50 ms | p95 ms |", "|---|---:|---:|---:|"]
        for row in roots:
            values = row["milliseconds_per_frame"]
            lines.append(f"| {row['label']} | {values['mean']:.3f} | {values['p50']:.3f} | {values['p95']:.3f} |")
        means = run["session_telemetry_mean_ms_per_frame"]
        if means:
            lines += ["", f"Contadores cumulativos da sessão: médias ms/quadro `{json.dumps(means)}`. "
                      "Sem p50/p95 por callback para esses contadores; system_profile_callback já pertence à raiz do profiler GDScript e não se soma a ela."]
        ticks = run["physics_tick_callback_ms"]
        lines += ["", f"Passos físicos efetivamente bracketados: {ticks['count']}; "
                  f"p50 {format_ms(ticks.get('p50'))} ms/passo e p95 {format_ms(ticks.get('p95'))} ms/passo.", "",
                  "Normalização por número de passos usa a média de cada quadro; seus quantis não representam chamadas individuais:", "",
                  "| Passos/quadro | Quadros | Frame p50 ms | Frame p95 ms | Física/passo p50 ms | Física/passo p95 ms |",
                  "|---:|---:|---:|---:|---:|---:|"]
        for count, group in run["by_physics_steps"].items():
            frames = group["frame_ms"]
            normalized = group.get("physics_callback_ms_per_step_frame_average", {})
            lines.append(f"| {count} | {frames['count']} | {frames['p50']:.3f} | {frames['p95']:.3f} | "
                         f"{format_ms(normalized.get('p50'))} | {format_ms(normalized.get('p95'))} |")
        lines += ["", "| Span físico | Média ponderada ms/passo | p50 média do quadro/passo ms | p95 média do quadro/passo ms |",
                  "|---|---:|---:|---:|"]
        for row in run["span_ranking"]:
            if "milliseconds_per_step_frame_average" not in row:
                continue
            normalized = row["milliseconds_per_step_frame_average"]
            lines.append(f"| {row['label']} | {format_ms(row['mean_per_step_weighted_ms'])} | "
                         f"{format_ms(normalized.get('p50'))} | {format_ms(normalized.get('p95'))} |")
        lines += ["", "Ranking por média por quadro; percentis sempre sobre todos os quadros:", "",
                  "| Span | Relação | Pai | Média ms | p50 ms | p95 ms | Quadros com chamadas |",
                  "|---|---|---|---:|---:|---:|---:|"]
        for row in run["span_ranking"]:
            values = row["milliseconds_per_frame"]
            lines.append(f"| {row['label']} | {row['kind']} | {row['parent']} | {values['mean']:.3f} | "
                         f"{values['p50']:.3f} | {values['p95']:.3f} | {row['frames_with_calls']} |")
        if not run["residuals_ms"]:
            lines += ["", "Residual não calculado: não há garantia de contenção temporal e ausência de sobreposição das raízes."]
        for phase, row in run["residuals_ms"].items():
            values = row["milliseconds_per_frame"]
            lines += ["", f"Residual {phase}: p50 {format_ms(values.get('p50'))} ms; "
                      f"p95 {format_ms(values.get('p95'))} ms ({values['count']} quadros, "
                      f"{row['invalid_negative_frames']} rejeitados por cobertura excedente). Complemento sem causa atribuída."]
    if analysis["rejected"]:
        lines += ["", "## Arquivos não utilizados", ""]
        lines += [f"- `{row['source']}`: {row['reason']}" for row in analysis["rejected"]]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("evidence/profile-west-cpu-20261013"))
    parser.add_argument("--baseline", default="baseline")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--markdown", type=Path)
    args = parser.parse_args()
    paths = [args.input] if args.input.is_file() else sorted(args.input.glob("*.json"))
    runs, rejected = [], []
    excluded = {path.resolve() for path in (args.output,) if path is not None}
    for path in paths:
        if path.resolve() in excluded:
            continue
        try:
            runs.append(analyze_run(path))
        except (ValueError, KeyError, TypeError) as error:
            rejected.append({"source": str(path.resolve()), "reason": str(error)})
    analysis = {"schema_version": 1, "runs": runs, "comparisons": comparisons(runs, args.baseline),
                "rejected": rejected,
                "limitations": ["Spans inclusivos; pais e filhos não se somam",
                                "Monitores TIME_PROCESS/TIME_PHYSICS_PROCESS não utilizados",
                                "Ausência de span é zero somente no coletor agregado opt-in ativo",
                                "Desligar um sistema altera interações e não mede seu custo exclusivo",
                                "Nenhuma causa atribuída ao residual"]}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(analysis, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text(markdown(analysis), encoding="utf-8")
    print(f"Rodadas analisadas: {len(runs)}; arquivos não utilizados: {len(rejected)}")
    if not runs:
        print("Nenhuma amostra deste profiler disponível; não há conclusão de desempenho.")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
