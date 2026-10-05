"""A/B dos draws de primeira passagem (variantes de pintura sob a cortina).

Uso: python analyze_first_draw_ab.py <pasta_captura> [...] --out ab.json
Percentis: mesmo quantil empírico inferior de analyze_intermittent_stalls.py.
Draw = wall pre_draw->post_draw dos intervalos retidos (todo frame >=25 ms é
retido); não é GPU exclusiva. Chaves ShaderRD gravadas depois de READY vêm do
mtime dos arquivos no APPDATA isolado da captura.
"""
from __future__ import annotations
import argparse, json, os
from pathlib import Path

PHASES = ["loading", "first_pass", "return", "event", "recovery", "tail"]


def metrics(values):
    if not values:
        return {"frames": 0}
    o = sorted(values)
    s = sum(values) / 1000.0
    q = lambda p: o[int((len(o) - 1) * p)]
    return {"frames": len(values), "seconds": round(s, 3), "p50_ms": round(q(.5), 3), "p95_ms": round(q(.95), 3),
            "p99_ms": round(q(.99), 3), "max_ms": round(o[-1], 3),
            "over_33_3": sum(v > 33.3 for v in values), "over_66_7": sum(v > 66.7 for v in values)}


def analyze(folder: Path):
    label = folder.name
    d = json.loads((folder / f"{label}.json").read_text(encoding="utf-8-sig"))
    start = next(e for e in d["events"] if e["kind"] == "start")
    ready_usec = d["clock"]["start_usec"]
    ready_unix = float(start["details"]["unix_seconds"])
    phases = {p: metrics([f["ms"] for f in d["frames"] if f["phase"] == p]) for p in PHASES}
    phases["gameplay"] = metrics([f["ms"] for f in d["frames"] if f["phase"] in PHASES[1:5]])
    draws = []
    for i in d["intervals"]:
        if not i.get("draw_pair_valid") or i["phase"] == "loading":
            continue
        ms = (i["draw_post_usec"] - i["draw_pre_usec"]) / 1000.0
        if ms >= 25.0:
            draws.append({"frame": i["frame"], "phase": i["phase"], "ready_s": round((i["start_usec"] - ready_usec) / 1e6, 3),
                          "frame_ms": i["ms"], "draw_ms": round(ms, 3)})
    keys = []
    # Prefixo de caminho longo do Windows: as chaves passam de 260 caracteres.
    cache = Path("\\\\?\\" + str(folder.resolve())) / "user" / "GetecoV2" / "shader_cache" / "SceneForwardMobileShaderRD"
    if cache.exists():
        for f in cache.rglob("*.cache"):
            t = os.path.getmtime(f) - ready_unix
            if t > 0:
                keys.append({"key": f.name[:8], "ready_s": round(t, 3)})
    keys.sort(key=lambda k: k["ready_s"])
    total_cache = len(list(cache.rglob("*.cache"))) if cache.exists() else 0
    loading_s = (ready_usec - d["clock"]["startup_start_usec"]) / 1e6
    out = Path(folder / "stdout.log").read_text(encoding="utf-8", errors="replace")
    summary = [l for l in out.splitlines() if l.startswith("Variantes de")]
    route = [f for f in d["frames"] if f["phase"] in PHASES[1:5]]
    unfocused = sum(not f["focused"] for f in route)
    return {"label": label, "validity": d["validity"], "unfocused_route_frames": unfocused, "route_frames": len(route), "loading_until_ready_s": round(loading_s, 3), "phases": phases,
            "draws_ge25_after_ready": draws, "scene_keys_after_ready": keys, "scene_keys_total": total_cache,
            "prewarm_summary": summary,
            "population_end": next(e for e in d["events"] if e["kind"] == "end")["details"].get("people"),
            "vehicles_end": next(e for e in d["events"] if e["kind"] == "end")["details"].get("vehicles")}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("folders", nargs="+")
    ap.add_argument("--out")
    a = ap.parse_args()
    rows = [analyze(Path(f)) for f in a.folders]
    text = json.dumps(rows, indent=1, ensure_ascii=False)
    if a.out:
        Path(a.out).write_text(text, encoding="utf-8")
    for r in rows:
        print(r["label"], r["validity"], "unfocused", r["unfocused_route_frames"], "/", r["route_frames"], "loading", r["loading_until_ready_s"], r["prewarm_summary"])
        for p in ["first_pass", "return", "event", "recovery", "gameplay", "loading"]:
            print("  ", p, r["phases"][p])
        print("   draws>=25:", [(x["frame"], x["phase"], x["ready_s"], x["draw_ms"]) for x in r["draws_ge25_after_ready"]])
        print("   keys after READY:", [(k["key"], k["ready_s"]) for k in r["scene_keys_after_ready"] if k["ready_s"] < 124])
