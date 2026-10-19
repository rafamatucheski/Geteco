#!/usr/bin/env bash
# Fase 2 da verificação cruzada (15/10): um export release e todos os cenários, 2
# rodadas cada, pela fila única de Godot. Rotas normais via perf_cross_bench.sh; os
# cenários especiais (caos, noite, chuva, dirigindo, diagnóstico desligado) aqui.
# Uso: tools/perf_cross_phase2.sh <rótulo> [pasta_do_export=artifacts/perf-phase2]
# Todas as rodadas usam as opções fixas de tools/bench/settings.cfg; ENGINE_EXTRA vale para as
# rodadas (não para o export). Ver tools/bench/bench_common.sh.
set -u
LABEL="$1"; DIR="${2:-artifacts/perf-phase2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p "$DIR"
dotnet build Harbor.csproj -c Release -v q > "$DIR/build.log" 2>&1 || { echo "build falhou"; exit 1; }
tools/run_godot_locked.sh --headless --path . --export-release "Geteco V2 Windows" "$DIR/GetecoV2.exe" > "$DIR/export.log" 2>&1 || { echo "export falhou"; exit 1; }
tools/perf_cross_bench.sh "$DIR" "$LABEL" 2
OUT="$ROOT/evidence/perf-cross-20261015"
# Mesma base fixa das rotas (opções gráficas da bancada e ENGINE_EXTRA): ver tools/bench/bench_common.sh.
. "$ROOT/tools/bench/bench_common.sh"
special() {  # rótulo início env args...
	local name="$1" start="$2" envs="$3"; shift 3
	for run in 1 2; do
		local save_root
		save_root="$(bench_prepare_root "$ROOT/$DIR")" || { echo "bancada: não consegui preparar a pasta isolada"; exit 1; }
		env $envs GODOT_BIN="$ROOT/$DIR/GetecoV2.exe" "$ROOT/tools/run_godot_locked.sh" ${ENGINE_EXTRA:-} -- --no-save --benchmark \
			--isolated-save-root="$save_root" \
			--play-at="$start" --label="${LABEL}_${name}_${run}" "$@" 2>&1 | grep -E "BENCH_RELEASE" | sed "s/^/$name $run /" | tee -a "$OUT/$LABEL.log"
	done
}
special caos3porto "harbor,150,82" "X=1" --benchmark-route=porto --benchmark-chaos=3
special noiteoeste "harbor,64,82" "X=1" --no-dispatch --benchmark-route=oeste --benchmark-hour=22
special chuvaoeste "harbor,64,82" "X=1" --no-dispatch --benchmark-route=oeste --benchmark-rain=2
special dirigindooeste "harbor,64,82" "X=1" --no-dispatch --benchmark-route=oeste --benchmark-drive
special semdiagsobrados "harbor,295,100" "HARBOR_SESSION_PROFILE=0" --no-dispatch --benchmark-route=sobrados
special semdiagserra "mountain,650,-290" "HARBOR_SESSION_PROFILE=0" --no-dispatch --benchmark-route=serra
# Resumo de todos os JSON do rótulo (rotas e especiais).
python -I - "$LABEL" "$OUT" <<'PY'
import json, os, sys, glob
label, out = sys.argv[1], sys.argv[2]
folder = os.path.join(os.environ["APPDATA"], "GetecoV2", "benchmark-west")
rows = ["cenario\trodada\tquadros\tp50_ms\tp95_ms\tp99_ms\tmax_ms\t>6.9ms\t>16.7ms\t>33ms\t>100ms\t>250ms\tgpu_p50\tdraws_p50\tjogavel_ms\textra\trenderizador\tdriver\tpreset\tviewport"]
for path in sorted(glob.glob(os.path.join(folder, label + "_*.json"))):
    r = json.load(open(path, encoding="utf-8"))
    name = os.path.basename(path)[len(label) + 1:-5]
    scen, run = name.rsplit("_", 1)
    f = r["frame_ms"]
    extra = {k: r[k] for k in ("chaos", "drive") if k in r}
    rows.append("\t".join(str(x) for x in [scen, run, r["frames"], f["p50"], f["p95"], f["p99"], f["max"],
        r.get("frames_over_6_9ms", ""), r.get("frames_over_16_7ms", ""), r.get("frames_over_33ms", ""),
        r["frames_over_100ms"], r["frames_over_250ms"], r["gpu_ms_main"]["p50"], r["draw_calls"]["p50"],
        r.get("playable_ms", ""), json.dumps(extra) if extra else "",
        r.get("graphics", {}).get("rendering_method", ""), r.get("graphics", {}).get("rendering_driver", ""),
        r.get("graphics", {}).get("preset", ""), r.get("viewport_pixels", "")]))
open(os.path.join(out, label + "_all.tsv"), "w", encoding="utf-8").write("\n".join(rows) + "\n")
print("\n".join(rows))
PY
