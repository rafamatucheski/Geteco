#!/usr/bin/env bash
# Base fixa da bancada de desempenho, usada por tools/perf_cross_bench.sh e perf_cross_phase2.sh.
#
# Por que existe (auditoria 19/10, §1): o benchmark lia o user://settings.cfg do jogador, que mudou
# no meio das rodadas, e o motor não recebia argumentos (BENCH_EXTRA entra depois do `--`, onde
# `--rendering-driver` é ignorado em silêncio). Aqui ficam as duas coisas que precisam ser iguais
# em toda rodada: a pasta isolada com as opções gráficas fixas e os argumentos do motor.
#
# Variáveis:
#   BENCH_SETTINGS  settings.cfg copiado para a pasta isolada antes de cada rodada
#                   (padrão: tools/bench/settings.cfg, preset "Média", janela 1280x720).
#   BENCH_SAVE_ROOT pasta isolada (padrão: <pasta do export>/bench-save-root). Passa ao jogo como
#                   --isolated-save-root=<pasta>; só o Settings.gd lê esse argumento no jogo.
#   ENGINE_EXTRA    argumentos do MOTOR, antes do `--` (ex.: "--rendering-driver d3d12",
#                   "--rendering-method mobile", "--verbose").
#   BENCH_EXTRA     argumentos do ReleaseBenchmark, depois do `--` (como antes).
#   GETECO_TRACK_CALL_STACKS=1  põe tools/bench/override-callstacks.cfg como override.cfg ao lado do
#                   exe (pilha de GDScript nos erros do release). Não existe forma em runtime: o Godot
#                   lê essa opção uma vez, antes dos scripts. Sem a variável, uma cópia nossa que tenha
#                   ficado na pasta é afastada (renomeada), para não contaminar a rodada seguinte.
#                   O JSON grava graphics.always_track_call_stacks e graphics.override_cfg_present.
BENCH_REPO_ROOT="${BENCH_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# bench_prepare_root <pasta_do_export_absoluta>
# Copia o settings.cfg da bancada para a pasta isolada e imprime o caminho no formato do Windows
# (o jogo é um .exe nativo: caminho MSYS /d/... não serve para ele).
bench_prepare_root() {
	local export_dir="$1"
	local root="${BENCH_SAVE_ROOT:-$export_dir/bench-save-root}"
	local source="${BENCH_SETTINGS:-$BENCH_REPO_ROOT/tools/bench/settings.cfg}"
	mkdir -p "$root" || return 1
	# Cópia nova a cada rodada: o jogo pode gravar preferências lá (menu, migração), e isso não
	# pode vazar para a rodada seguinte.
	cp -f "$source" "$root/settings.cfg" || return 1
	bench_apply_callstacks "$export_dir" || return 1
	if command -v cygpath > /dev/null 2>&1; then cygpath -m "$root"; else echo "$root"; fi
}

# bench_apply_callstacks <pasta_do_export_absoluta>
# Mensagens vão para stderr: o stdout de bench_prepare_root é o caminho da pasta isolada.
bench_apply_callstacks() {
	local export_dir="$1"
	local ours="$BENCH_REPO_ROOT/tools/bench/override-callstacks.cfg"
	local target="$export_dir/override.cfg"
	if [ "${GETECO_TRACK_CALL_STACKS:-0}" = "1" ]; then
		if [ -f "$target" ] && ! cmp -s "$ours" "$target"; then
			echo "bancada: $target existe e não é o de pilha de chamadas; não sobrescrevo" >&2
			return 1
		fi
		cp -f "$ours" "$target" || return 1
		echo "bancada: always_track_call_stacks ligado via $target" >&2
	elif [ -f "$target" ]; then
		if cmp -s "$ours" "$target"; then
			mv -f "$target" "$target.callstacks-off" || return 1
			echo "bancada: override.cfg de pilha afastado (GETECO_TRACK_CALL_STACKS não está em 1)" >&2
		else
			echo "bancada: AVISO, $target de outra origem vale nesta rodada" >&2
		fi
	fi
	return 0
}
