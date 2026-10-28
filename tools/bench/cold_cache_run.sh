#!/usr/bin/env bash
# Rodada com cache de pipeline/shader FRIO (22/10), para medir a primeira sessão de uma instalação nova
# ou depois de atualizar o driver. Afasta (não apaga) %APPDATA%/GetecoV2/vulkan e shader_cache, roda o
# comando com o cache de disco do driver NVIDIA numa pasta vazia (__GL_SHADER_DISK_CACHE_PATH; o driver
# respeita a variável: o cache dele aparece lá) e devolve os caches quentes no fim. Saves e settings.cfg
# não são tocados. O cache frio criado pela rodada fica em %APPDATA%/GetecoV2/cache-cold-<rótulo>/.
#
# Uso: tools/bench/cold_cache_run.sh <rótulo> <comando...>
#   tools/bench/cold_cache_run.sh frio_oeste env BENCH_DISPATCH=1 BENCH_SETTINGS=tools/bench/settings-jogador-3440.cfg \
#     BENCH_EXTRA="--benchmark-stress --benchmark-cold --benchmark-weapon-cycle=5 --skip-arrival" \
#     tools/perf_cross_bench.sh artifacts/<export> frio 1 oeste
#
# COLD_PART escolhe o que esfria (28/10, para atribuir o quadro de ~1 s do frio):
#   all (padrão) tudo; shader só o shader_cache do Godot (código GLSL -> SPIR-V), pipeline e driver ficam
#   quentes; pipeline só o cache de pipeline do Godot (vulkan/) e o do driver, shader_cache fica quente.
#   Se o pico some com "pipeline" quente, é compilação nativa; se some com "shader" quente, é código novo.
# Não rode com outro Godot aberto (a fila de tools/run_godot_locked.sh espera, mas os caches são do usuário).
set -u
LABEL="$1"; shift
U="$APPDATA/GetecoV2"
WARM="$U/cache-warm-hold"
COLD="$U/cache-cold-$LABEL"
DRIVER="$COLD/driver"
mkdir -p "$WARM" "$COLD" "$DRIVER" || exit 1
# Só afasta o que ainda não está afastado: uma rodada interrompida não pode perder o cache quente.
case "${COLD_PART:-all}" in
	all) PARTS="vulkan shader_cache" ;;
	shader) PARTS="shader_cache" ;;
	pipeline) PARTS="vulkan" ;;
	*) echo "COLD_PART inválido: $COLD_PART (all|shader|pipeline)" >&2; exit 1 ;;
esac
for d in $PARTS; do
	if [ -d "$U/$d" ] && [ ! -d "$WARM/$d" ]; then mv "$U/$d" "$WARM/$d" || exit 1; fi
	if [ -d "$U/$d" ]; then mv "$U/$d" "$COLD/$d-pre" || exit 1; fi
done
restore() {
	for d in $PARTS; do
		if [ -d "$U/$d" ]; then mv "$U/$d" "$COLD/$d" || return 1; fi
		if [ -d "$WARM/$d" ]; then mv "$WARM/$d" "$U/$d" || return 1; fi
	done
}
trap restore EXIT
if [ "${COLD_PART:-all}" = "shader" ]; then
	"$@"
else
	__GL_SHADER_DISK_CACHE_PATH="$(cygpath -w "$DRIVER" 2>/dev/null || echo "$DRIVER")" "$@"
fi
