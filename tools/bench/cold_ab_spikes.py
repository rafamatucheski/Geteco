# Separa os picos (> 500 ms) de uma rodada de tools/bench/cold_ab.sh pelo tipo de pipeline nova no quadro, lendo o
# StallLog do export: "draw" (compilada no desenho; até 27/10 era a carga da caçamba com a brasa da carcaça) e
# "surface" (superfície nova criada no quadro, muitas vezes com nós novos). Uso:
#   python -I tools/bench/cold_ab_spikes.py <pasta_do_export>
import json, glob, os, sys
for f in sorted(glob.glob(os.path.join(sys.argv[1], "evidence", "stall-logs", "stalls-*.log")), key=os.path.getmtime):
    found = []
    for line in open(f, encoding="utf-8"):
        if not line.startswith("{"): continue
        try: r = json.loads(line)
        except Exception: continue
        if r.get("frame_ms", 0) <= 500: continue
        d = r.get("pipelines_delta", {})
        kind = "draw" if d.get("draw") else ("surface" if d.get("surface") else "outro")
        found.append("%s %.0f ms t=%.0f carcaças=%s nós+%s" % (kind, r["frame_ms"], r["t"], r.get("wrecks"), r.get("nodes_delta")))
    print(os.path.basename(f), "|", "; ".join(found) if found else "sem pico")
