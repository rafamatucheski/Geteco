#!/usr/bin/env bash
# Fila única de Godot: só um jogo/teste/export roda por vez nesta máquina.
#
# Por que existe: várias sessões e agentes rodando Godot ao mesmo tempo travavam o
# PC e contaminavam medições (CPU, GPU e cache de shader compartilhados). O laço
# antigo `tasklist | grep Godot...exe` não funcionava: o tasklist trunca o nome do
# processo e o grep nunca casava.
#
# Uso:
#   tools/run_godot_locked.sh <args do Godot...>          # editor binário (--script, --import, --export-release)
#   GODOT_BIN=artifacts/perf-release/GetecoV2.exe tools/run_godot_locked.sh -- --no-save --benchmark ...
# Variáveis: GODOT_BIN (padrão: Godot 4.7.2 mono console), GODOT_LOCK_LOG (registro da fila).
#
# ORDEM DE CHEGADA: cada processo deixa uma senha `<epoch_ns>-<pid>` em
# `$GODOT_LOCK_DIR/geteco-godot-queue.d/` e só tenta o cadeado quando a sua é a mais antiga
# ainda viva (senha de processo morto é descartada). Antes todos sondavam o cadeado a cada
# 10 s e levava quem acertasse o instante: houve espera de 30+ min por sorte.
#   GODOT_LOCK_DIR     onde ficam cadeado, fila e registro (padrão: $TEMP). Um diretório
#                      próprio dá cadeado/fila isolados (para testar este script sem esperar
#                      atrás dos outros); nesse caso NÃO espera Godot de fora, salvo
#                      GODOT_WAIT_OTHERS=1.
#   GODOT_WAIT_OTHERS  1 = esperar Godot rodando fora da fila (padrão 1 só no diretório padrão).
#
# Limites de EXECUÇÃO (a espera na fila nunca conta; antes um teste com erro de script ficava
# aberto para sempre, segurava o cadeado e travava todos que esperavam atrás dele):
#   GODOT_RUN_TIMEOUT  segundos de execução. Padrão 900 em `--script` (testes); sem limite nas
#                      demais execuções (jogo/benchmark/--import/export), salvo se definido.
#   GODOT_ERROR_GRACE  segundos sem saída nenhuma depois de um "SCRIPT ERROR" para encerrar
#                      (padrão 90). Em teste SceneTree um erro de script não sai sozinho.
# Códigos: 124 = estourou GODOT_RUN_TIMEOUT; 125 = erro de script e Godot parado (encerrado);
# o encerramento mata a ÁRVORE de processos (o `_console.exe` é só o lançador do filho).
# Se este script receber INT/TERM (ex.: `timeout` externo), também mata a árvore do Godot.
set -u
DEFAULT_DIR="${TEMP:-/tmp}"
LOCK_DIR="${GODOT_LOCK_DIR:-$DEFAULT_DIR}"
if [ "$LOCK_DIR" = "$DEFAULT_DIR" ]; then wait_others="${GODOT_WAIT_OTHERS:-1}"; else wait_others="${GODOT_WAIT_OTHERS:-0}"; fi
mkdir -p "$LOCK_DIR"
LOCK="$LOCK_DIR/geteco-godot.lock"
QUEUE="$LOCK_DIR/geteco-godot-queue.d"
BIN="${GODOT_BIN:-D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe}"
LOG="${GODOT_LOCK_LOG:-$LOCK_DIR/geteco-godot-queue.log}"
POLL=3

my_winpid=$(cat "/proc/$$/winpid" 2>/dev/null || echo "")
ticket=""
godot=""
follower=""
out=""

other_godot_running() {
	# Conta Godot/jogo exportado vivos, ignorando o lançador _console (só embrulha o filho).
	local n
	n=$(powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='Godot_v4.7.2-stable_mono_win64.exe' or Name='GetecoV2.exe'\" | Measure-Object).Count" 2>/dev/null | tr -d '\r ')
	[ "${n:-0}" -gt 0 ]
}

# Vivo = o pid MSYS responde; se não, confere o pid Windows gravado (bash de outra
# instalação MSYS não aparece no `kill -0` desta).
pid_alive() {
	local pid="$1" winpid="${2:-}"
	[ -n "$pid" ] || return 1
	kill -0 "$pid" 2>/dev/null && return 0
	[ -n "$winpid" ] || return 1
	tasklist //FI "PID eq $winpid" //NH 2>/dev/null | tr -d '\r' | grep -qw "$winpid"
}

# Primeira senha viva da fila (descarta as de processo morto).
queue_head() {
	local name pid
	for name in $(ls -1 "$QUEUE" 2>/dev/null | sort); do
		pid="${name##*-}"
		if pid_alive "$pid" "$(cat "$QUEUE/$name" 2>/dev/null)"; then
			echo "$name"; return 0
		fi
		rm -f "$QUEUE/$name"
	done
	echo ""
}

acquire() {
	mkdir -p "$QUEUE"
	ticket="$(date +%s%N)-$$"
	echo "$my_winpid" > "$QUEUE/$ticket"
	while true; do
		if [ "$(queue_head)" = "$ticket" ]; then
			if mkdir "$LOCK" 2>/dev/null; then
				echo "$$ $my_winpid" > "$LOCK/pid"
				rm -f "$QUEUE/$ticket"; ticket=""
				# Outro Godot fora da fila (sessão que não usa este script): espera ele acabar.
				if [ "$wait_others" = "1" ]; then
					while other_godot_running; do sleep 10; done
				fi
				return 0
			fi
			# Trava órfã: o dono morreu sem liberar.
			local holder holder_pid holder_win
			holder=$(cat "$LOCK/pid" 2>/dev/null || echo "")
			holder_pid="${holder%% *}"
			holder_win=""; [ "$holder" != "$holder_pid" ] && holder_win="${holder#* }"
			if [ -n "$holder_pid" ] && ! pid_alive "$holder_pid" "$holder_win"; then
				echo "$(date '+%H:%M:%S') trava órfã de pid=$holder_pid removida por pid=$$" >> "$LOG"
				rm -rf "$LOCK"
				continue
			fi
		fi
		sleep "$POLL"
	done
}

kill_tree() {
	[ -n "$godot" ] || return 0
	kill -0 "$godot" 2>/dev/null || return 0
	local winpid
	winpid=$(cat "/proc/$godot/winpid" 2>/dev/null || echo "$godot")
	taskkill //F //T //PID "$winpid" > /dev/null 2>&1 || kill -9 "$godot" 2>/dev/null
}

cleanup() {
	kill_tree
	[ -n "$follower" ] && kill "$follower" 2>/dev/null
	[ -n "$out" ] && rm -f "$out"
	[ -n "$ticket" ] && rm -f "$QUEUE/$ticket"
	# Só solta o cadeado se for nosso.
	local holder
	holder=$(cat "$LOCK/pid" 2>/dev/null || echo "")
	[ "${holder%% *}" = "$$" ] && rm -rf "$LOCK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

acquire
echo "$(date '+%H:%M:%S') start pid=$$ $*" >> "$LOG"

run_limit="${GODOT_RUN_TIMEOUT:-}"
if [ -z "$run_limit" ]; then
	case " $* " in *" --script "*) run_limit=900 ;; *) run_limit=0 ;; esac
fi
error_grace="${GODOT_ERROR_GRACE:-90}"

out="$(mktemp 2>/dev/null || echo "${TEMP:-/tmp}/godot-locked-$$.out")"
: > "$out"
"$BIN" "$@" > "$out" 2>&1 &
godot=$!
tail -n +1 -f "$out" --pid="$godot" 2>/dev/null &
follower=$!

status=""
started=$(date +%s)
while kill -0 "$godot" 2>/dev/null; do
	sleep 2
	now=$(date +%s)
	if [ "$run_limit" -gt 0 ] && [ $((now - started)) -ge "$run_limit" ]; then
		echo "run_godot_locked: estourou GODOT_RUN_TIMEOUT=${run_limit}s, encerrando a árvore de processos" >&2
		kill_tree; status=124; break
	fi
	if grep -q "^SCRIPT ERROR" "$out" 2>/dev/null; then
		modified=$(stat -c %Y "$out" 2>/dev/null || echo "$now")
		if [ $((now - modified)) -ge "$error_grace" ]; then
			echo "run_godot_locked: SCRIPT ERROR e nenhuma saída há ${error_grace}s (teste não sai sozinho), encerrando a árvore de processos" >&2
			kill_tree; status=125; break
		fi
	fi
done
if [ -z "$status" ]; then wait "$godot"; status=$?; fi
sleep 1
kill "$follower" 2>/dev/null; follower=""
echo "$(date '+%H:%M:%S') end   pid=$$ exit=$status" >> "$LOG"
exit $status
