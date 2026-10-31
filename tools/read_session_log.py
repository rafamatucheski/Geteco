"""Lê todas as partes rotacionadas de uma sessão. Estatísticas exatas de quadro e detalhes limitados de eventos."""
import argparse
from array import array
import collections
import json
import math
import sys
from pathlib import Path


def read_records(path):
    folder = path if path.is_dir() else path.parent
    for part in sorted(folder.glob("session-*.jsonl")):
        with part.open(encoding="utf-8-sig") as stream:
            for number, line in enumerate(stream, 1):
                try:
                    record = json.loads(line)
                    if not isinstance(record, dict):
                        raise ValueError("record must be an object")
                except (json.JSONDecodeError, ValueError):
                    yield {}, {"type": "invalid_record", "part": part.name, "line": number}
                    continue
                yield record, record.get("data", record)


def statistics(frames):
    ordered = sorted(frames)
    total = math.fsum(frames)
    n = len(frames)
    quantile = lambda p: ordered[max(0, math.ceil(n*p)-1)] if n else 0
    return {"frames": n, "duration_ms": total, "fps": n*1000/total if total else 0,
            "p50_ms": quantile(.5), "p95_ms": quantile(.95), "p99_ms": quantile(.99),
            "max_ms": max(frames, default=0), "over_33_3_ms": sum(v > 33.3 for v in frames),
            "over_66_7_ms": sum(v > 66.7 for v in frames)}


def summarize(path, top=10):
    counts = collections.Counter()
    samples = collections.defaultdict(lambda: array("d"))
    contexts, states, active = {}, {}, {}
    incidents, stages, errors = [], [], []
    sources = collections.Counter()
    first = last = None
    start = {}
    ended = False
    dropped = 0
    peak_ram = peak_vram = peak_queue = 0
    timing_missing = 0
    def retain(items, record, key):
        items.append(record)
        items.sort(key=lambda item: item.get(key, 0), reverse=True)
        del items[max(0, top):]
    def cache(target, key, value):
        target[key] = value
        if len(target) > 64:
            del target[min(target)]
    def add_frames(data, tail=False):
        nonlocal timing_missing
        fallback = data.get("context", {})
        values = data.get("remaining_frame_ms" if tail else "frame_ms", [])
        ids = data.get("remaining_context_ids" if tail else "frame_context_ids", [])
        state_ids = data.get("remaining_state_ids" if tail else "frame_state_ids", [])
        for i, value in enumerate(values):
            world = contexts.get(ids[i], {}) if i < len(ids) else fallback.get("world", {}) or {}
            state = states.get(state_ids[i], fallback) if i < len(state_ids) else fallback
            if i < len(state_ids) and state_ids[i] not in states:
                timing_missing += 1
            scenario = json.dumps({"scene": state.get("scene", "unknown"), "region": world.get("region", "unknown"),
                "place": world.get("place", "unknown"), "ready": world.get("world_ready", "unknown"),
                "focused": state.get("focused", "unknown"), "paused": state.get("paused", "unknown"),
                "resolution": state.get("resolution", "unknown"), "max_fps": state.get("max_fps", "unknown")}, sort_keys=True)
            samples[scenario].append(value)
    for envelope, data in read_records(path):
        kind = data.get("type", "unknown")
        counts[kind] += 1
        first = first or envelope.get("utc", data.get("utc"))
        last = envelope.get("utc", data.get("utc", last))
        if kind == "session_start": start = data
        elif kind == "context_update": cache(contexts, data["id"], data["context"])
        elif kind == "runtime_state_changed": cache(states, data["id"], data)
        elif kind == "operation_begin": active[data["id"]] = data
        elif kind == "operation_end":
            active.pop(data["id"], None)
            retain(stages, data, "duration_ms")
        elif kind == "frame_spike":
            retain(incidents, {**data, "utc": envelope.get("utc"), "elapsed_ms": envelope.get("elapsed_ms")}, "frame_ms")
        elif kind == "metrics":
            add_frames(data)
            c = data.get("context", {})
            peak_ram = max(peak_ram, c.get("working_set_bytes", 0))
            peak_vram = max(peak_vram, c.get("video_memory_bytes", 0))
            peak_queue = max(peak_queue, c.get("writer_queue", 0), c.get("writer", {}).get("queue_high_water", 0))
        elif kind == "session_end":
            ended = True
            add_frames(data, True)
        if kind == "records_dropped": dropped = max(dropped, data.get("total", data.get("count", 0)))
        if kind in ("error", "stderr", "telemetry_error", "logger_capture_error", "managed_unhandled_exception", "managed_unobserved_task_exception", "invalid_record"):
            key = kind + ":" + data.get("source_key", data.get("file", "unknown"))
            sources[key] += 1
            if len(errors) < 50: errors.append(data)
    return {"schema": start.get("schema"), "first_utc": first, "last_utc": last,
            "session": start, "normal_end_seen": ended, "events": dict(counts),
            "scenarios": [{"scenario": json.loads(key), "metrics": statistics(values)} for key, values in samples.items()],
            "largest_incidents": incidents, "slowest_completed_stages": stages,
            "errors_by_source": dict(sources), "error_examples": errors, "unfinished_operations": list(active.values()),
            "records_dropped": dropped, "frames_missing_runtime_state": timing_missing,
            "peak_ram_bytes": peak_ram, "peak_vram_bytes": peak_vram, "queue_high_water": peak_queue,
            "interpretation": "correlation_not_proven_cause; older_schemas_use_window_context; missing_end_may_be_active_crash_or_write_failure"}


def main():
    if hasattr(sys.stdout, "reconfigure"): sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--json", action="store_true", help="Emit machine-readable exact summary")
    parser.add_argument("--summary-only", action="store_true", help="Omit detailed incident bodies")
    parser.add_argument("--output", type=Path, help="Write JSON summary to this file")
    args = parser.parse_args()
    folder = args.path if args.path.is_dir() else args.path.parent
    if not args.path.exists() or not any(folder.glob("session-*.jsonl")):
        parser.error("Informe uma pasta de sessão ou parte JSONL existente.")
    result = summarize(args.path, max(0, args.top))
    if args.output:
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return
    print(f"Sessão: {result['first_utc']} até {result['last_utc']} (UTC)")
    print("Encerramento normal:", result['normal_end_seen'], "| Eventos:", result['events'])
    for scenario in result["scenarios"]:
        s = scenario["metrics"]
        print("Cenário:", json.dumps(scenario['scenario'], ensure_ascii=False))
        print(f"  {s['frames']} frames / {s['duration_ms']/1000:.2f}s; FPS={s['fps']:.2f}; "
              f"p50/p95/p99={s['p50_ms']:.2f}/{s['p95_ms']:.2f}/{s['p99_ms']:.2f}ms; "
              f"máximo={s['max_ms']:.2f}ms; >33,3={s['over_33_3_ms']} >66,7={s['over_66_7_ms']}")
    print("Maiores incidentes (correlação, sem presumir causa):")
    for incident in ([] if args.summary_only else result["largest_incidents"]):
        context = incident.get("context", {})
        print(f"  {incident.get('utc')} +{(incident.get('elapsed_ms') or 0)/1000:.3f}s: {incident['frame_ms']:.3f}ms; "
              f"região={context.get('region')} lugar={context.get('place')} foco={incident.get('focused')} pausa={incident.get('paused')}")
        if "coverage" in incident: print("    cobertura:", json.dumps(incident['coverage'], ensure_ascii=False))
        if "phases" in incident: print("    fases:", json.dumps(incident['phases'], ensure_ascii=False))
        for span in sorted(incident.get("slow_spans", []), key=lambda s: s['ms'], reverse=True)[:5]:
            print("    trecho:", json.dumps(span, ensure_ascii=False))
    print("Etapas mais demoradas (incluem esperas e filhos; não somar):")
    for stage in result["slowest_completed_stages"]:
        print(f"  {stage['system']}/{stage['operation']}: {stage['duration_ms']:.2f}ms; status={stage.get('status')}; origem={stage.get('source')}; detalhes={stage.get('details')}")
    print("Erros por origem:", result['errors_by_source'])
    print("Operações sem fechamento:", json.dumps(result['unfinished_operations'], ensure_ascii=False))
    print(f"RAM pico={result['peak_ram_bytes']/1024**2:.1f}MiB; VRAM reportada pico={result['peak_vram_bytes']/1024**2:.1f}MiB; "
          f"fila máxima={result['queue_high_water']}; registros perdidos={result['records_dropped']}")
    print("Tempos GPU são assíncronos. Intervalos sem cobertura não identificam o culpado.")


if __name__ == "__main__": main()
