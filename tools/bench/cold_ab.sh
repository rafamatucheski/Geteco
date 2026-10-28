#!/usr/bin/env bash
# A/B com cache FRIO em sessões alternadas (27/10): cada rodada afasta os caches de shader/pipeline
# (tools/bench/cold_cache_run.sh), roda a rota com o estresse e o despacho no export release e grava o JSON
# da bancada como <prefixo><lado><n>_<rota>_1.json. O lado "A" roda sem nada a mais; o lado "B" recebe as
# variáveis de ambiente passadas em LADO_B. StallLog ligado nos dois lados.
#
# Uso: tools/bench/cold_ab.sh <pasta_do_export> <prefixo> <ordem> [rota=oeste]
#   LADO_B="GETECO_CARGO_WRECK_PREWARM=0" tools/bench/cold_ab.sh artifacts/perf-x q09c ABBAABBA
# COLD_PART_A / COLD_PART_B (all|shader|pipeline, padrão all) escolhem o que esfria em cada lado; ver
# tools/bench/cold_cache_run.sh. Atribuição do quadro de ~1 s (28/10):
#   COLD_PART_A=shader COLD_PART_B=pipeline tools/bench/cold_ab.sh artifacts/perf-x q10 ABBAABBAABBA
# A ordem alternada (ABBAABBA) cancela deriva de máquina ao longo da noite. Resumo:
#   python -I tools/bench/cold_ab_summary.py <prefixo>
# O quadro de ~1 s sai em ~70 % das sessões frias: 4 de cada lado só separa diferença grande.
# Não rode com outro Godot aberto; o PC precisa estar sozinho (a medição compete por CPU/GPU).
set -u
EXPORT="$1"; PREFIX="$2"; ORDER="$3"; ROUTE="${4:-oeste}"
cd "$(dirname "$0")/../.."
n=0
for side in $(echo "$ORDER" | grep -o .); do
	n=$((n+1))
	label="${PREFIX}${side}${n}"
	extra=""
	part="${COLD_PART_A:-all}"
	[ "$side" = "B" ] && extra="${LADO_B:-}" && part="${COLD_PART_B:-all}"
	echo "=== rodada $n lado $side ($label) $(date +%H:%M:%S) frio=${part} ${extra}"
	COLD_PART="$part" tools/bench/cold_cache_run.sh "$label" env $extra HARBOR_STALL_LOG=1 BENCH_DISPATCH=1 \
		BENCH_SETTINGS=tools/bench/settings-jogador-3440.cfg \
		BENCH_EXTRA="--benchmark-stress --benchmark-cold --benchmark-weapon-cycle=5 --skip-arrival" \
		tools/perf_cross_bench.sh "$EXPORT" "$label" 1 "$ROUTE"
done
echo "=== fim $(date +%H:%M:%S)"
