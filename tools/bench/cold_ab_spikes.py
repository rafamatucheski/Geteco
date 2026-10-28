# Separa os picos (> 500 ms) de uma rodada de tools/bench/cold_ab.sh pelo tipo de pipeline nova no quadro, lendo o
# StallLog do export: "draw" (compilada no desenho; até 27/10 era a carga da caçamba com a brasa da carcaça) e
# "surface" (superfície nova criada no quadro, muitas vezes com nós novos). Uso:
#   python -I tools/bench/cold_ab_spikes.py <pasta_do_export>
# Desde 28/10 cada pico leva também o que nasceu nos caches (registro slow_compile_cache do StallLog):
# "godot=N" são versões de shader novas (código de material compilado para SPIR-V naquele quadro) e
# "driver=N" arquivos do cache do driver gravados; "godot=0 driver=0" aponta para pipeline nativa já em memória.
import json, glob, os, sys
for f in sorted(glob.glob(os.path.join(sys.argv[1], "evidence", "stall-logs", "stalls-*.log")), key=os.path.getmtime):
    found = []
    caches = {}
    records = []
    for line in open(f, encoding="utf-8"):
        if not line.startswith("{"): continue
        try: r = json.loads(line)
        except Exception: continue
        if r.get("type") == "slow_compile_cache": caches[r.get("slow_t")] = r
        else: records.append(r)
    for r in records:
        if r.get("frame_ms", 0) <= 500: continue
        d = r.get("pipelines_delta", {})
        kind = "draw" if d.get("draw") else ("surface" if d.get("surface") else "outro")
        text = "%s %.0f ms t=%.0f carcaças=%s nós+%s" % (kind, r["frame_ms"], r["t"], r.get("wrecks"), r.get("nodes_delta"))
        cache = caches.get(r.get("t"))
        if cache is not None:
            shaders = cache.get("godot_shaders", [])
            text += " godot=%d driver=%d [%s]" % (len(shaders), len(cache.get("driver_files", [])),
                ",".join(sorted({s["shader"].replace("ShaderRD", "") for s in shaders})))
        found.append(text)
    print(os.path.basename(f), "|", "; ".join(found) if found else "sem pico")
