"""Agrega os braços A/B (todos os quadros; mesmo quantil inferior)."""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from analyze_first_draw_ab import analyze, metrics, PHASES
base = Path(__file__).parent.parent / "intermittent-stalls-20261004"
groups = {"A_sem_preparo": ["first-draw-a1", "first-draw-a2", "first-draw-a3", "first-draw-a4"],
          "B_pintura_apenas": ["first-draw-b1", "first-draw-b2"],
          "B_completo": ["first-draw-b3", "first-draw-b4"]}
out = {}
for name, labels in groups.items():
    frames = []
    draws = []
    rows = [analyze(base / l) for l in labels]
    for l in labels:
        d = json.loads((base / l / f"{l}.json").read_text(encoding="utf-8-sig"))
        frames += d["frames"]
    out[name] = {"labels": labels,
                 "phases": {p: metrics([f["ms"] for f in frames if f["phase"] == p]) for p in PHASES + ["gameplay"]} ,
                 "draws_ge25": sum(len(r["draws_ge25_after_ready"]) for r in rows),
                 "draws_ge40": sum(sum(x["draw_ms"] >= 40 for x in r["draws_ge25_after_ready"]) for r in rows),
                 "scene_keys_after_ready": {r["label"]: [(k["key"], k["ready_s"]) for k in r["scene_keys_after_ready"] if k["ready_s"] < 123.5] for r in rows},
                 "unfocused_route_frames": {r["label"]: [r["unfocused_route_frames"], r["route_frames"]] for r in rows},
                 "loading_until_ready_s": {r["label"]: r["loading_until_ready_s"] for r in rows},
                 "prewarm": {r["label"]: r["prewarm_summary"] for r in rows}}
    out[name]["phases"]["gameplay"] = metrics([f["ms"] for f in frames if f["phase"] in PHASES[1:5]])
Path(__file__).with_name("ab-pooled.json").write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf-8")
for name, g in out.items():
    print(name, "draws>=25", g["draws_ge25"], ">=40", g["draws_ge40"])
    for p in ["first_pass", "return", "event", "recovery", "gameplay", "loading"]:
        m = g["phases"][p]; print("  ", p, m["p50_ms"], m["p95_ms"], m["p99_ms"], m["max_ms"], m["over_33_3"], m["over_66_7"], m["frames"], m["seconds"])
