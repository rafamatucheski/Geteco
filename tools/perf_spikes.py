"""Atribuição de picos (22/10): lista cada quadro acima do limite depois de jogável numa rodada do
ReleaseBenchmark rodada com logs (HARBOR_SESSION_LOG=1 HARBOR_SESSION_PROFILE=1, opcional HARBOR_STALL_LOG=1).

Uso: python -I tools/perf_spikes.py <rótulo do JSON> [--min 33] [--export <pasta do export>] [--detail]
     [--session <pasta do session-log>] [--stall <stalls-*.log>] [--all]
O rótulo é o nome do JSON em %APPDATA%/GetecoV2/benchmark-west sem ".json". A pasta do registro da sessão é
achada pela hora do JSON; o StallLog, pelo pid, em <export>/evidence/stall-logs. Para cada quadro: fases
(process, diferidas, desenho, física/entrada, sinal process_frame), spans >= 2 ms, operações da sessão que
cruzam o quadro, sistemas sys.* e, com o StallLog, pipelines novas e tempos de render. --detail lista os
totais por sistema >= 0,8 ms do quadro. O intervalo usado é o exato do registro (frame_spike), não o laço
da bancada (ver docs/perf-playthrough-20261021.md, 2ª rodada)."""
import argparse, glob, json, os, sys
from pathlib import Path

APPDATA = Path(os.environ["APPDATA"]) / "GetecoV2"


def load_bench(label):
    path = APPDATA / "benchmark-west" / (label + ".json")
    return json.load(open(path, encoding="utf-8")), path


def find_session(bench_path):
    mtime = bench_path.stat().st_mtime
    best = None
    for folder in (APPDATA / "session-logs").iterdir():
        if not folder.is_dir():
            continue
        parts = sorted(folder.glob("session-*.jsonl"))
        if not parts:
            continue
        end = max(p.stat().st_mtime for p in parts)
        if abs(end - mtime) < 40:
            if best is None or abs(end - mtime) < best[0]:
                best = (abs(end - mtime), folder)
    return best[1] if best else None


def records(folder):
    for part in sorted(folder.glob("session-*.jsonl")):
        with part.open(encoding="utf-8-sig") as stream:
            for line in stream:
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                yield r, r.get("data", r)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("label")
    ap.add_argument("--min", type=float, default=33.3)
    ap.add_argument("--session")
    ap.add_argument("--stall")
    ap.add_argument("--all", action="store_true", help="inclui quadros antes de jogável")
    ap.add_argument("--spans", type=int, default=6)
    ap.add_argument("--export")
    ap.add_argument("--detail", action="store_true")
    a = ap.parse_args()
    bench, bench_path = load_bench(a.label)
    folder = Path(a.session) if a.session else find_session(bench_path)
    pid = None
    start_usec = None
    spikes = []
    ops = []
    if folder:
        for env, d in records(folder):
            t = d.get("type")
            if t == "session_start":
                pid = d.get("pid")
            if t == "frame_spike":
                spikes.append(d)
            if t == "operation_timing":
                ops.append(d)
    playable_usec = int(bench.get("playable_ms", 0)) * 1000
    stall = {}
    stall_path = a.stall
    if not stall_path and pid and a.export:
        for cand in sorted(glob.glob(os.path.join(a.export, "evidence", "stall-logs", "*.log"))):
            try:
                head = json.loads(open(cand, encoding="utf-8").readline())
            except Exception:
                continue
            if head.get("pid") == pid:
                stall_path = cand
    end_usec = playable_usec + int(float(bench.get("duration_ms", 0)) * 1000) + 300000
    if stall_path:
        for line in open(stall_path, encoding="utf-8"):
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("type") == "slow":
                stall[int(r.get("process_frame", -1))] = r
    f = bench["frame_ms"]
    pr = bench.get("present_ms")
    if pr:
        print(f"  present: p50 {pr.get('p50')} p99 {pr.get('p99')} máx {pr.get('max')} >33 {bench.get('present_over_33ms')}")
    print(f"{a.label}: quadros {bench['frames']} média {f['mean']} p50 {f['p50']} p95 {f['p95']} p99 {f['p99']} máx {f['max']} >33 {bench['frames_over_33ms']} jogável {bench['playable_ms']/1000:.1f}s sessão {folder}")
    shown = 0
    for d in spikes:
        ms = float(d.get("frame_ms", 0))
        if ms < a.min:
            continue
        if not a.all and (int(d.get("end_usec", 0)) < playable_usec or int(d.get("end_usec", 0)) > end_usec):
            continue
        ph = d.get("phases", {})
        spans = sorted(d.get("slow_spans", []), key=lambda s: -float(s.get("ms", 0)))
        span_txt = ", ".join(f"{s['label']}={s['ms']:.1f}" for s in spans[: a.spans])
        markers = [f"{k[7:]}x{v.get('calls',0)}" for k, v in d.get("systems", {}).items() if k.startswith("marker.")]
        if markers:
            span_txt += " | marks: " + ", ".join(markers)
        sysbig = sorted([(k, v.get('total_ms', 0)) for k, v in d.get("systems", {}).items() if k.startswith("sys.") and v.get('total_ms', 0) >= 2.0], key=lambda kv: -kv[1])
        if sysbig:
            span_txt += " | sys: " + ", ".join(f"{k[4:]}={v:.1f}" for k, v in sysbig[:6])
        s0, s1 = int(d.get("start_usec", 0)), int(d.get("end_usec", 0))
        over = [o for o in ops if int(o.get("start_usec", 0)) < s1 and int(o.get("end_usec", 0)) > s0 and float(o.get("duration_ms", 0)) >= 1.0]
        if over:
            span_txt += " | ops: " + ", ".join(f"{o['operation']}={float(o['duration_ms']):.1f}" for o in sorted(over, key=lambda o: -float(o['duration_ms']))[:6])
        st = stall.get(int(d.get("process_frame", -2))) or stall.get(int(d.get("process_frame", -2)) + 1)
        pipe = ""
        if st:
            pd = {k: v for k, v in st.get("pipelines_delta", {}).items() if v}
            ren = st.get("render", {})
            pipe = f" pipes={pd} setup={ren.get('setup_ms')} vpcpu={ren.get('vp_cpu_ms')} objs={ren.get('objects')}"
        t = (int(d.get("end_usec", 0)) - playable_usec) / 1e6
        extra = ""
        if "late_to_deferred_tail_ms" in ph: extra += f" [diferidas {ph['late_to_deferred_tail_ms']:.1f} resto {ph['deferred_tail_to_render_pre_ms']:.1f}]"
        if "post_render_to_process_signal_ms" in ph: extra += f" [fís/entrada {ph['post_render_to_process_signal_ms']:.1f} sinal {ph['process_signal_to_callback_ms']:.1f}]"
        print(f"  t+{t:6.1f}s {ms:7.1f} ms{extra} | proc(e->l) {ph.get('early_to_late_ms',0):5.1f} l->rend {ph.get('late_to_render_pre_ms',0):5.1f} rend {ph.get('render_bracket_ms',0):5.1f} post->cb {ph.get('post_render_to_next_callback_ms',0):5.1f} (phys cb {ph.get('physics_callback_ms',0):4.1f} x{ph.get('physics_ticks')}) unobs {d.get('coverage',{}).get('unobserved_ms',0):5.1f}{pipe}\n      {span_txt}")
        if a.detail:
            for k, v in sorted(d.get("systems", {}).items(), key=lambda kv: -kv[1].get("total_ms", 0)):
                if v.get("total_ms", 0) >= 0.8: print(f"          {k}: {v.get('total_ms'):.2f} ms x{v.get('calls')} (máx {v.get('max_ms'):.2f})")
        shown += 1
    print(f"  ({shown} quadros >= {a.min} ms listados; frame_spike total {len(spikes)})")


main()
