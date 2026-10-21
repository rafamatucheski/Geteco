#!/usr/bin/env bash
# A/B em release da perseguição de carro estilo GTA (gameplay/dispatch/PursuitRules.gd, 21/10):
# um export só, GETECO_GTA_CHASE=0 (antes) e =1 (depois) alternados, mesmo cenário. O carro anda a
# rota do porto com a própria física (--benchmark-drive) e é o alvo (--benchmark-chase), com três
# estrelas mantidas (--benchmark-chaos=3): a polícia persegue o carro. Carro protegido: sem PIT nem
# batida nele, então mede o custo de dirigir/planejar/guiar das viaturas, não o do carro rodando.
# Uso: tools/perf_gta_chase_ab.sh <rótulo> [rodadas=2] [pasta_do_export=artifacts/perf-release/gta-chase]
#      NO_EXPORT=1 reaproveita o export da pasta.
# Resumo: evidence/perf-gta-chase-20261021/<rótulo>.tsv (JSONs em %APPDATA%/GetecoV2/benchmark-west).
set -u
LABEL="$1"; RUNS="${2:-2}"; DIR="${3:-artifacts/perf-release/gta-chase}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/evidence/perf-gta-chase-20261021"
mkdir -p "$DIR" "$OUT"
. "$ROOT/tools/bench/bench_common.sh"
if [ "${NO_EXPORT:-0}" != "1" ]; then
	dotnet build Harbor.csproj -c Release -v q > "$DIR/build.log" 2>&1 || { echo "build falhou"; exit 1; }
	GODOT_RUN_TIMEOUT="${GODOT_RUN_TIMEOUT:-240}" tools/run_godot_locked.sh --headless --path . --export-release "Geteco V2 Windows" "$DIR/GetecoV2.exe" > "$DIR/export.log" 2>&1
	[ -f "$DIR/GetecoV2.exe" ] || { echo "export falhou"; exit 1; }
fi
for run in $(seq 1 "$RUNS"); do
	for mode in 0 1; do
		name="gta${mode}"
		save_root="$(bench_prepare_root "$ROOT/$DIR")" || { echo "bancada: não consegui preparar a pasta isolada"; exit 1; }
		# Limite por rodada: um jogo que não chega a jogável (erro de script de outra sessão no export,
		# por exemplo) seguraria a fila da máquina inteira para sempre.
		GODOT_RUN_TIMEOUT="${BENCH_RUN_TIMEOUT:-600}" GETECO_GTA_CHASE="$mode" GODOT_BIN="$ROOT/$DIR/GetecoV2.exe" "$ROOT/tools/run_godot_locked.sh" ${ENGINE_EXTRA:-} -- --no-save --benchmark \
			--isolated-save-root="$save_root" --play-at="harbor,150,82" --benchmark-route=porto \
			--benchmark-chaos=3 --benchmark-drive --benchmark-chase --label="${LABEL}_${name}_${run}" 2>&1 \
			| grep -E "BENCH_RELEASE" | sed "s/^/$name $run /" | tee -a "$OUT/$LABEL.log"
	done
done
python -I - "$LABEL" "$OUT" <<'PY'
import json, os, sys, glob
label, out = sys.argv[1], sys.argv[2]
folder = os.path.join(os.environ["APPDATA"], "GetecoV2", "benchmark-west")
rows = ["cenario\trodada\tquadros\tp50_ms\tp95_ms\tp99_ms\tmax_ms\t>16.7ms\t>33ms\t>100ms\tunidades_pico\tdrive_recoveries\tperseguicao"]
for path in sorted(glob.glob(os.path.join(folder, label + "_*.json"))):
    r = json.load(open(path, encoding="utf-8"))
    name = os.path.basename(path)[len(label) + 1:-5]
    scen, run = name.rsplit("_", 1)
    f = r["frame_ms"]
    chase = r.get("chase", {})
    rows.append("\t".join(str(x) for x in [scen, run, r["frames"], f["p50"], f["p95"], f["p99"], f["max"],
        r.get("frames_over_16_7ms", ""), r.get("frames_over_33ms", ""), r["frames_over_100ms"],
        r.get("chaos", {}).get("dispatch_units_peak", ""), r.get("drive", {}).get("recoveries", ""),
        json.dumps(chase.get("stats", {}), ensure_ascii=False)]))
open(os.path.join(out, label + ".tsv"), "w", encoding="utf-8").write("\n".join(rows) + "\n")
print("\n".join(rows))
PY
