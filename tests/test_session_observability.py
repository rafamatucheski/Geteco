"""Run production observability integration, or verify an already completed fixture folder."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--godot")
parser.add_argument("--folder", type=Path)
parser.add_argument("--rendered", action="store_true")
args = parser.parse_args()
folder = args.folder
if folder is None:
    assert args.godot, "Supply --godot or --folder"
    engine_args = [] if args.rendered else ["--headless"]
    run = subprocess.run([args.godot, *engine_args, "--path", str(root), "--script",
                          "res://tests/test_session_observability.gd", "--", "--no-save"],
                         capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=150)
    assert run.returncode == 0, run.stdout + run.stderr
    marker = "OBSERVABILITY_PATH "
    folder = Path(next(line.split(marker, 1)[1] for line in run.stdout.splitlines() if marker in line))
rows = [json.loads(line) for part in sorted(folder.glob("session-*.jsonl"))
        for line in part.read_text(encoding="utf-8-sig").splitlines()]
data = [row.get("data", row) for row in rows]
assert data[0]["schema"] == 5
assert not [r for r in data if r["type"] in ("telemetry_error", "logger_capture_error")]
game_errors = [r for r in data if r["type"] == "error"]
for error in game_errors:
    # Warnings remain explicit; script errors (including Cobra seat fitting) fail integration.
    assert error["error_type"] == 1, error
    assert "context" in error and "active_operations" in error
print("GAME_ERRORS (not logger certification):", [(e["file"],e["line"],e["code"]) for e in game_errors])
begins = [r for r in data if r["type"] == "operation_begin"]
child = next(r for r in begins if r["operation"] == "child")
parent = next(r for r in begins if r["operation"] == "parent")
assert child["parent_id"] == parent["id"]
assert child["engine_usec"] >= parent["engine_usec"] > 0
assert any(r["system"] == "resource" and r["operation"] == "load" and r["details"]["path"] != "res://Main.tscn" for r in begins)
assert any(r["system"] == "scene" and r["details"].get("script", "").endswith("FullSession.gd") for r in begins)
contexts = [r["context"] for r in data if r["type"] == "context_update"]
assert any(c.get("region") == "harbor" and c.get("world_ready") and c.get("streaming") for c in contexts)
assert any(c["inventory"]["classes"].get("MeshInstance3D", 0) > 0 for c in contexts)
assert any(c["inventory"]["removed_total"] > 0 for c in contexts)
states = [r for r in data if r["type"] == "runtime_state_changed"]
assert any(r["paused"] for r in states)
assert {60, 144} <= {r["max_fps"] for r in states}
for metric in [r for r in data if r["type"] == "metrics"]:
    assert len(metric["frame_ms"]) == len(metric["frame_context_ids"]) == len(metric["frame_state_ids"])
for incident in [r for r in data if r["type"] == "frame_spike"]:
    coverage = incident["coverage"]
    assert abs(coverage["retained_slow_spans_union_ms"] + coverage["unobserved_ms"] - incident["frame_ms"]) < 1e-5
assert data[-1]["type"] == "session_end"
assert data[-1]["writer"]["queue_high_water"] > 0
summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
assert summary["normal_end_seen"] and not summary["writer_failure"] and summary["records_dropped"] == 0
assert summary["events"]["session_end"] == 1
spec = importlib.util.spec_from_file_location("reader", root / "tools/read_session_log.py")
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
exact = reader.summarize(folder)
assert sum(s["metrics"]["frames"] for s in summary["scenarios"]) == sum(s["metrics"]["frames"] for s in exact["scenarios"])
assert not exact["unfinished_operations"]
if args.rendered:
    phases = [f["phases"] for r in data if r["type"] == "frame_history" for f in r["frames"] if "phases" in f]
    assert any(p["valid"] and p["render_frame"] > 0 for p in phases), "Real render brackets were not observed"
print("PASS production startup, resource/ready correlation, bounded inventory, per-frame states, incident coverage and automatic summary", folder)
