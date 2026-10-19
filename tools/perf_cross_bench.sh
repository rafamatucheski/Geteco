#!/usr/bin/env bash
# Benchmark cruzado em release: todas as rotas do ReleaseBenchmark, N rodadas cada,
# sempre pela fila única de Godot (tools/run_godot_locked.sh) e sem sobreposição.
#
# Uso: tools/perf_cross_bench.sh <pasta_do_export> <rótulo> [rodadas=2] [rotas...]
#   tools/perf_cross_bench.sh artifacts/perf-baseline base 2
# Resultado: user://benchmark-west/<rótulo>_<rota>_<n>.json (AppData/Roaming/GetecoV2)
# e um resumo em evidence/perf-cross-20261015/<rótulo>.tsv.
# BENCH_EXTRA="--benchmark-road-events" acrescenta argumentos do ReleaseBenchmark às rodadas.
set -u
DIR="$1"; LABEL="$2"; RUNS="${3:-2}"; shift; shift; [ $# -gt 0 ] && shift
ROUTES="${*:-oeste porto sobrados serra ponte travessia deserto}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/evidence/perf-cross-20261015"
mkdir -p "$OUT"
start_for() {
	case "$1" in
		oeste) echo "harbor,64,82" ;; porto) echo "harbor,150,82" ;; sobrados) echo "harbor,295,100" ;;
		serra) echo "mountain,650,-290" ;; ponte) echo "harbor,440,-285" ;; travessia) echo "harbor,330,-285" ;;
		deserto) echo "desert,-1040,-1320" ;; rota66) echo "desert,347,-470" ;;
	esac
}
for run in $(seq 1 "$RUNS"); do
	for route in $ROUTES; do
		GODOT_BIN="$ROOT/$DIR/GetecoV2.exe" "$ROOT/tools/run_godot_locked.sh" -- --no-save --benchmark --no-dispatch \
			--benchmark-route="$route" --play-at="$(start_for "$route")" --label="${LABEL}_${route}_${run}" ${BENCH_EXTRA:-} 2>&1 | grep -E "BENCH_RELEASE" \
			| sed "s/^/$route $run /" | tee -a "$OUT/$LABEL.log"
	done
done
python -I - "$LABEL" "$OUT" <<'PY'
import json, os, sys, glob
label, out = sys.argv[1], sys.argv[2]
folder = os.path.join(os.environ["APPDATA"], "GetecoV2", "benchmark-west")
rows = ["rota\trodada\tquadros\tp50_ms\tp95_ms\tp99_ms\tmax_ms\t>33ms\t>100ms\t>250ms\tgpu_p50\tdraws_p50"]
for path in sorted(glob.glob(os.path.join(folder, label + "_*.json"))):
    r = json.load(open(path, encoding="utf-8"))
    name = os.path.basename(path)[len(label) + 1:-5]
    route, run = name.rsplit("_", 1)
    f = r["frame_ms"]
    over33 = r.get("frames_over_33ms", "")
    rows.append("\t".join(str(x) for x in [route, run, r["frames"], f["p50"], f["p95"], f["p99"], f["max"], over33,
        r["frames_over_100ms"], r["frames_over_250ms"], r["gpu_ms_main"]["p50"], r["draw_calls"]["p50"]]))
open(os.path.join(out, label + ".tsv"), "w", encoding="utf-8").write("\n".join(rows) + "\n")
print("\n".join(rows))
PY
