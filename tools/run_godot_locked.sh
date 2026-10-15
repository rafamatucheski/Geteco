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
set -u
LOCK="${TEMP:-/tmp}/geteco-godot.lock"
BIN="${GODOT_BIN:-D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe}"
LOG="${GODOT_LOCK_LOG:-${TEMP:-/tmp}/geteco-godot-queue.log}"

other_godot_running() {
	# Conta Godot/jogo exportado vivos, ignorando o lançador _console (só embrulha o filho).
	local n
	n=$(powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='Godot_v4.7.2-stable_mono_win64.exe' or Name='GetecoV2.exe'\" | Measure-Object).Count" 2>/dev/null | tr -d '\r ')
	[ "${n:-0}" -gt 0 ]
}

acquire() {
	while true; do
		if mkdir "$LOCK" 2>/dev/null; then
			echo $$ > "$LOCK/pid"
			# Outro Godot fora da fila (sessão que não usa este script): espera ele acabar.
			while other_godot_running; do sleep 10; done
			return 0
		fi
		# Trava órfã: o dono morreu sem liberar.
		local holder
		holder=$(cat "$LOCK/pid" 2>/dev/null || echo "")
		if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
			rm -rf "$LOCK"
			continue
		fi
		sleep 10
	done
}

release() { rm -rf "$LOCK"; }

acquire
trap release EXIT INT TERM
echo "$(date '+%H:%M:%S') start pid=$$ $*" >> "$LOG"
"$BIN" "$@"
status=$?
echo "$(date '+%H:%M:%S') end   pid=$$ exit=$status" >> "$LOG"
exit $status
