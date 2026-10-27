#!/usr/bin/env bash
# Suíte central (o "esqueleto" do jogo), sempre pela fila única de Godot.
#
# Por que existe: há mais de 1.500 scripts em tests/, mas ninguém roda o conjunto inteiro;
# as últimas execuções gravadas tinham de 1 a 16 testes, então "verde" não dizia nada sobre
# o jogo todo (revisão cruzada de 18/10/2026). Esta lista curta cobre o que, quebrado,
# estraga qualquer sessão: save e recuperação, carteira e recibos, campanha, crime, regiões,
# ponte, direção, admissão do frio e o deserto. Cada teste passa por
# tools/run_godot_locked.sh, então dá para rodar com outras sessões abertas: espera a vez.
#
# Uso:
#   tools/run_core_suite.sh            # rápida: contratos sem carregar o mundo (~1–3 min)
#   tools/run_core_suite.sh full       # rápida + testes com o mundo de verdade (bem mais lenta)
#   tools/run_core_suite.sh full --no-build   # pula o dotnet build (C# já compilado)
#
# Resultado: tabela em evidence/test-suite/core/<data>/RESUMO.md (fora do Git) e um log por
# teste ao lado. Sai com 0 só se todos passaram. Um teste passa quando sai com código 0 e o
# log não tem erro de script/engine (regra de tests/Runner.Common.ps1, menos vazamento no
# encerramento e o erro esperado declarado na linha do teste).
#
# Adicionar um teste: uma linha em FAST (sem mundo, headless) ou WORLD ("modo|script|args|erro
# esperado"). O último campo, opcional, é uma regex de ERROR que o próprio teste provoca de
# propósito (ex.: falha de disco simulada) e que não conta como falha.
# Modo "rendered" abre janela (capturas de tela); "headless" usa o driver dummy, que serve
# para lógica e NUNCA para medir desempenho.
set -u
cd "$(dirname "$0")/.."

FAST=(
	"headless|tests/test_core_contracts.gd|"
	"headless|tests/test_prologue_save_contract.gd|"
	"headless|tests/test_session_cleanup_registry.gd|"
	"headless|tests/test_orphan_save_slots.gd|"
	"headless|tests/test_full_save.gd|"
	"headless|tests/test_save_store_byte_preflight.gd|"
	"headless|tests/test_consumed_world_reward_save.gd|"
	"headless|tests/test_campaign_economy.gd|"
	"headless|tests/test_garage_rewards.gd|"
	"headless|tests/test_police_crime_contract.gd|"
	"headless|tests/test_private_security_crime.gd|"
	"headless|tests/test_gpu_release_scene_swap.gd|"
)
# As quatro primeiras são a verificação mínima do CLAUDE.md depois de mudança estrutural.
WORLD=(
	"headless|tests/test_regions.gd|"
	"headless|tests/test_bridge_approach_terrain.gd|"
	"headless|tests/test_native_driving.gd|--no-save"
	"headless|tests/cold/test_admission.gd|"
	# Forma do mundo orgânico (etapa 0): estrada, lugar ou prédio novo tem que caber dentro das ilhas.
	"headless|tests/test_world_shape.gd|--no-save"
	"headless|tests/test_world_sea.gd|"
	"headless|tests/test_desert_island.gd|"
	"headless|tests/test_mountain_island.gd|"
	"headless|tests/test_save_indicator.gd|--no-save --skip-arrival|Could not create directory: .*/missing-parent-"
	"headless|tests/test_recovery_penalty_session.gd|--no-save --skip-arrival"
	"rendered|tests/test_desert_wilds.gd|--no-save --no-traffic"
	"rendered|tests/test_desert_roadside_session.gd|--no-save --no-traffic"
	"rendered|tests/test_dialogue_flow.gd|--no-save --skip-arrival"
	"rendered|tests/test_video_vehicle_lifecycle.gd|--no-save --skip-arrival"
)

tier="${1:-fast}"
build=1
for argument in "$@"; do [ "$argument" = "--no-build" ] && build=0; done
case "$tier" in
	fast) entries=("${FAST[@]}") ;;
	full) entries=("${FAST[@]}" "${WORLD[@]}") ;;
	--no-build) tier=fast; entries=("${FAST[@]}") ;;
	*) echo "uso: tools/run_core_suite.sh [fast|full] [--no-build]" >&2; exit 2 ;;
esac

stamp="$(date '+%Y%m%d-%H%M%S')"
out="evidence/test-suite/core/$stamp"
mkdir -p "$out"
summary="$out/RESUMO.md"

if [ "$build" = 1 ]; then
	echo "core-suite: dotnet build Harbor.csproj"
	if ! dotnet build Harbor.csproj -nologo -v q > "$out/dotnet-build.log" 2>&1; then
		echo "core-suite: dotnet build falhou; veja $out/dotnet-build.log" >&2
		exit 3
	fi
fi

{
	echo "# Suíte central ($tier) — $stamp"
	echo
	echo "- HEAD: \`$(git rev-parse --short HEAD 2>/dev/null)\`; arquivos modificados no checkout: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
	echo "- Cada teste rodou uma vez pela fila (tools/run_godot_locked.sh). Verde aqui prova estes casos, não o jogo inteiro."
	echo
	echo "| Teste | Modo | Resultado | Segundos | Última linha |"
	echo "|---|---|---|---|---|"
} > "$summary"

passed=0
failed=0
tmp_root="$(cygpath -u "${TEMP:-/tmp}" 2>/dev/null || echo /tmp)"
for entry in "${entries[@]}"; do
	IFS='|' read -r mode script extra expected <<< "$entry"
	name="$(basename "$script" .gd)"
	log="$out/$name.log"
	args=(--path . --script "res://$script")
	[ "$mode" = "headless" ] && args=(--headless "${args[@]}")
	# Pasta própria por teste: preferências (idioma do texto!) nunca vêm do settings.cfg do jogador.
	isolated="$(mktemp -d "$tmp_root/geteco-core-XXXXXX")"
	isolated_arg="$(cygpath -m "$isolated" 2>/dev/null || echo "$isolated")"
	# shellcheck disable=SC2206
	args+=(-- $extra "--isolated-save-root=$isolated_arg")
	limit=180
	[ "$tier" = "full" ] && case " ${WORLD[*]} " in *"|$script|"*) limit=600 ;; esac
	started=$(date +%s)
	echo "core-suite: $name ($mode)…"
	GODOT_RUN_TIMEOUT=$limit tools/run_godot_locked.sh "${args[@]}" > "$log" 2>&1
	code=$?
	case "$isolated" in "$tmp_root"/geteco-core-*) rm -rf -- "$isolated" ;; esac
	seconds=$(( $(date +%s) - started ))
	problems=""
	[ "$code" != 0 ] && problems="código $code"
	# Vazamento no encerramento ("... at exit") é limpeza do teste, não erro de jogo: fica no log.
	if grep -E '^\s*ERROR:|SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Invalid (call|access|assignment)' "$log" | grep -v 'at exit' | grep -qvE "${expected:-^$}"; then
		problems="${problems:+$problems; }erro no log"
	fi
	last="$(grep -E 'PASS|FAIL|checks=|failures=' "$log" | tail -1 | tr '|' '/' | cut -c1-140)"
	if [ -z "$problems" ]; then
		result="PASSOU"; passed=$((passed + 1))
	else
		result="FALHOU ($problems)"; failed=$((failed + 1))
	fi
	echo "core-suite:   $result em ${seconds}s"
	echo "| \`$script\` | $mode | $result | $seconds | ${last:-—} |" >> "$summary"
done

{
	echo
	echo "**$passed passaram, $failed falharam.** Logs ao lado deste arquivo."
} >> "$summary"
echo "core-suite: $passed passaram, $failed falharam — $summary"
[ "$failed" = 0 ]
