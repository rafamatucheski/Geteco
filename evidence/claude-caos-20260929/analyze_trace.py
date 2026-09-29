"""Resume os rastros do DispatchTrace de um report.json do guardiao (recovery) ou do
tests/dispatch/results/<label>.json da atribuicao.

Uso:  python analyze_trace.py <report.json> [--phase controlled-chaos]

Para cada fase, uma linha por segundo: unidades, ticks de fisica, custo medio por tick do
controlador (controller.tick), os 3 maiores trechos (soma/n) e o maximo de tick de fisica
do motor no segundo. Depois, os trechos individuais >= 2 ms (etapas que estouram o quadro).
Tudo em milissegundos. So le dados; nao mede nada.
"""
import json
import sys


def phases(report):
    if "cases" in report:
        for case in report["cases"]:
            yield case["id"], case.get("runtime_costs", [])
    else:
        yield report.get("label", "atribuicao"), report.get("dispatch_costs", [])


def main():
    path = sys.argv[1]
    only = sys.argv[sys.argv.index("--phase") + 1] if "--phase" in sys.argv else None
    report = json.load(open(path, encoding="utf-8"))
    for phase, costs in phases(report):
        if only and phase != only:
            continue
        summaries = [c for c in costs if c.get("label") == "dispatch.summary"]
        slow = [c for c in costs if c.get("label") != "dispatch.summary" and str(c.get("label", "")).split(":")[0].split(".")[0] != "traffic_spawn" and "duration_usec" in c]
        print("== %s: %d resumos, %d trechos lentos" % (phase, len(summaries), len(slow)))
        for s in summaries:
            ticks = max(1, s.get("physics_ticks", 1))
            spans = s.get("spans", {})
            ctl = spans.get("controller.tick", {})
            per_tick = ctl.get("sum_us", 0) / ticks / 1000.0
            top = sorted(((v["sum_us"] / 1000.0, k, v["n"], v["max_us"] / 1000.0) for k, v in spans.items() if k != "controller.tick"), reverse=True)[:3]
            census = s.get("census", {})
            print("  units=%-2d ticks=%-3d ctl/tick=%6.2f ms  fisica_max=%7.1f ms  pares=%-5s | %s" % (
                census.get("units", 0), ticks, per_tick, s.get("physics_process_max_ms", 0.0),
                s.get("phys3d", {}).get("collision_pairs", "?"),
                "; ".join("%s %.1f ms (n=%d, max %.1f)" % (k, total, n, peak) for total, k, n, peak in top)))
        for c in sorted(slow, key=lambda c: -c["duration_usec"])[:15]:
            extra = {k: v for k, v in c.items() if k not in ("label", "start_usec", "duration_usec")}
            print("  lento %8.1f ms  %s  %s" % (c["duration_usec"] / 1000.0, c["label"], extra if extra else ""))


if __name__ == "__main__":
    main()
