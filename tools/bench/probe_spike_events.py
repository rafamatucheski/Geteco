"""Junta cada quadro grande da sonda de pipelines aos eventos que vieram antes dele.

Uso: python tools/bench/probe_spike_events.py "<pasta>/evidence/pipeline-probe/*.jsonl" [limiar_ms] [janela_s]

A sonda (runtime/PipelineProbe.gd, GETECO_PIPELINE_PROBE=sig ou lite) grava registros `compile` por desenho
com pipelines novas e, desde 27/10, registros `event` (carcaça, carcaça sumindo, destroço sumindo, carro
novo, pintura molhada). Para cada quadro jogável acima do limiar (padrão 300 ms) lista os eventos da janela
anterior (padrão 3 s) e, no fim, conta por tipo de evento quantos quadros grandes ele precedeu, contra
quantas vezes aconteceu sem quadro grande depois: é isso que separa causa de coincidência.
"""
import collections
import glob
import json
import os
import sys


def main():
    pattern = sys.argv[1] if len(sys.argv) > 1 else "artifacts/*/evidence/pipeline-probe/*.jsonl"
    threshold = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
    window = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0
    before_spike = collections.Counter()
    total = collections.Counter()
    spikes = 0
    for path in sorted(glob.glob(pattern)):
        rows = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
        events = [r for r in rows if r.get("type") == "event"]
        for event in events:
            total[event["kind"]] += 1
        big = [r for r in rows if r.get("type") == "compile" and r.get("playing")
               and (r.get("draw_interval_ms") or 0) >= threshold]
        if not big and not events:
            continue
        print("==", os.path.normpath(path), "eventos=%d quadros>=%.0fms=%d" % (len(events), threshold, len(big)))
        for spike in big:
            spikes += 1
            near = [e for e in events if 0 <= spike["t"] - e["t"] <= window]
            print("  t=%.1f %.0f ms %s" % (spike["t"], spike["draw_interval_ms"], spike.get("delta")))
            for event in near:
                print("     -%.2fs %s %s %s" % (spike["t"] - event["t"], event["kind"], event.get("archetype", ""),
                                             event.get("node", "")[-70:]))
            for kind in {e["kind"] for e in near}:
                before_spike[kind] += 1
    print("\nquadros grandes: %d" % spikes)
    print("%-20s %8s %8s" % ("evento", "antes", "total"))
    for kind in sorted(total, key=lambda k: -before_spike[k]):
        print("%-20s %8d %8d" % (kind, before_spike[kind], total[kind]))


if __name__ == "__main__":
    main()
