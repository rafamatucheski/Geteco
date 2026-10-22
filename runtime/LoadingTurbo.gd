extends RefCounted
## Orçamento grande enquanto a cortina de carregamento cobre a tela (21/10/2026).
##
## Por que existe: o carregamento fatiava o trabalho com os MESMOS orçamentos do jogo (streaming de
## prédios 1–2 ms por quadro, preparação retida 2 ms, partida da sessão 4 ms). Sob a cortina cada quadro
## ainda desenha o mundo e a tela de carregamento (~5–15 ms a 3440x1440), então a maior parte do tempo de
## "Preparando texturas e prédios" (4,9 s no release) e do streaming inicial era quadro, não trabalho.
## Com a cortina cobrindo (StartupCurtain sem estar saindo), esses orçamentos são multiplicados por FACTOR:
## quadros de ~15–25 ms sob a cortina são aceitáveis (docs/HOW-TO-DEVELOP.md §3.1); no instante em que a
## cortina começa a sair (lift), tudo volta ao orçamento do jogo. Nada sai da cortina por causa disto.
## GETECO_LOADING_TURBO=0 desliga (A/B no mesmo export).
const FACTOR := 6.0
## Cortinas que cobrem a tela agora (id da instância → true). Prévia do menu (stage_only) não entra.
static var _covers := {}
static var _enabled := OS.get_environment("GETECO_LOADING_TURBO") != "0"

static func cover(curtain: Object) -> void:
	if _enabled and curtain != null: _covers[curtain.get_instance_id()] = true

static func uncover(curtain: Object) -> void:
	if curtain != null: _covers.erase(curtain.get_instance_id())

static func active() -> bool:
	return not _covers.is_empty()

static func budget(base_usec: float) -> float:
	return base_usec * FACTOR if not _covers.is_empty() else base_usec
