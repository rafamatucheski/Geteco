# Resumo de tools/bench/cold_ab.sh: uma linha por rodada (p50, máximo, quadros > 150 ms) e, por lado, em quantas
# sessões houve quadro > 700 ms (o quadro de ~1 s do cache frio). Uso: python -I tools/bench/cold_ab_summary.py <prefixo>
import json, os, glob, sys, re
prefix = sys.argv[1] if len(sys.argv) > 1 else "q09"
folder = os.path.join(os.environ["APPDATA"], "GetecoV2", "benchmark-west")
rows = []
pattern = re.compile("^" + re.escape(prefix) + r"([A-Z])(\d+)_oeste_1\.json$")
found = []
for path in glob.glob(os.path.join(folder, prefix + "*_oeste_1.json")):
    m = pattern.match(os.path.basename(path))
    if m: found.append((int(m.group(2)), m.group(1), path))
for run, side, path in sorted(found):
    r = json.load(open(path, encoding="utf-8"))
    samples = r.get("frame_samples_ms", [])
    long = sorted([round(x) for x in samples if x > 150], reverse=True)
    rows.append((run, side, r["frame_ms"]["p50"], r["frame_ms"]["p95"], r["frame_ms"]["max"], r["frames_over_250ms"], long[:5], round(r.get("playable_ms", 0) / 1000.0, 1)))
print("rodada\tlado\tp50\tp95\tmáx\t>250ms\tquadros>150ms\tjogável_s")
for row in rows: print("\t".join(str(x) for x in row))
for side in sorted(set(row[1] for row in rows)):
    sel = [row for row in rows if row[1] == side]
    hits = sum(1 for row in sel if row[4] > 700)
    print("lado %s: %d rodadas, quadro > 700 ms em %d" % (side, len(sel), hits))
