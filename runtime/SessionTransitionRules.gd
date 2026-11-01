extends RefCounted
## Regras de transição da FullSession: quando a sessão está em transição, quando a posição do jogador
## está em troca, quando trocar de carro é proibido e quando o motorista salvo pode animar; mais a tabela
## CANCEL_STEPS (quem para em cada evento). Separado em 01/11 (Onda 2 de
## docs/plano-divisao-arquivos-grandes-20261101.md). As bandeiras (transition_kind, rescue_pending,
## vehicle_transition_busy...) continuam na sessão; cada função antiga virou delegação de uma linha, e a
## sessão reexporta CANCEL_STEPS como constante própria (tests/test_session_cleanup_registry.gd a lê pelo
## mapa de constantes do script da sessão).
## `g` fica como Node, e não como o script da FullSession, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`, como nos outros auxiliares da sessão.

## Quem para em cada evento da sessão, em que ordem e com que argumento. Antes cada evento
## (morte, prisão, resgate, carregar, menu, transição, viagem) tinha a própria lista escrita à
## mão, um pouco diferente das outras, e sistema esquecido numa delas seguia rodando através
## daquele evento. As listas viraram este registro na ordem exata de antes; inventário e
## diferenças entre eventos em docs/session-cleanup-registry.md, contrato em
## tests/test_session_cleanup_registry.gd.
## Etapa numerada = o evento é cortado onde a função intercala estado ou um guarda (ex.: a
## ilusão é cancelada antes do guarda do resgate; health = 0 antes de desmontar embarques).
## Passo: [sistema, método, argumentos, regra]. Sistema é a propriedade da sessão ("world.x"
## desce um nível, "" é a própria sessão); nulo ou liberado é pulado. Regras: if_method (só se
## o método existir), if_riding (só com alguém embarcado), if_jessica_bank (Jessica montada e
## o assalto dela ativo), abort_if_active (o sistema seguiu ativo: a etapa para e devolve false).
const CANCEL_STEPS := {
	&"death_1": [["upside_world", "cancel", ["death", false]]],
	&"death_2": [
		["fishing", "cancel_attempt", ["Pesca interrompida."]],
		["coastal_lookout", "leave"],
		["amusement_park", "leave"],
		["regional_coach", "cancel_for_transition"],
		["railway", "cancel_for_transition"],
	],
	&"death_3": [
		["desert", "cancel_attempt"],
		["mining", "cancel_attempt"],
		["jessica", "cancel_for_transition"],
		["services", "cancel_auto_service", ["player_death"], "if_method"],
		["world.driving", "cancel_transition", ["player_death"], "if_method"],
	],
	&"death_4": [
		["passenger_transport", "_brake", [], "if_riding"],
		["", "interrupt_dialogue"],
		["garage_rewards", "cancel_press_delivery"],
		["activities", "cancel_attempt"],
		["mountain_progression", "cancel_attempt"],
		["mountain_activities", "cancel_attempt"],
		["mission_world", "cancel_attempt", ["player_death"]],
	],
	&"arrest_1": [["upside_world", "cancel", ["arrest"]]],
	&"arrest_2": [
		["amusement_park", "leave"],
		["regional_coach", "cancel_for_transition"],
		["railway", "cancel_for_transition"],
		["", "interrupt_dialogue"],
		["desert", "cancel_attempt"],
		["mining", "cancel_attempt"],
	],
	&"arrest_3": [
		["services", "cancel_auto_service", ["player_arrest"], "if_method"],
		["world.driving", "cancel_transition", ["player_arrest"], "if_method"],
		["passenger_transport", "_brake", [], "if_riding"],
		["jessica", "cancel_for_transition"],
		["garage_rewards", "cancel_press_delivery"],
		["activities", "cancel_attempt"],
		["mountain_progression", "cancel_attempt"],
		["mountain_activities", "cancel_attempt"],
		["mission_world", "cancel_attempt", ["player_arrest"]],
	],
	# O resgate também passa por "transition" (begin_transition) entre rescue_1 e rescue_2.
	&"rescue_1": [["upside_world", "cancel", ["rescue", false]]],
	&"rescue_2": [
		["passenger_transport", "cancel_for_transition"],
		["building_entrance", "reset"],
		["service_roofs", "clear", [true]],
	],
	&"rescue_3": [
		["world.traffic_yield", "release_all", ["rescue"]],
		["world.dispatch", "dismiss_all", ["rescue"]],
	],
	&"load_1": [
		["upside_world", "cancel", ["load"]],
		["fishing", "cancel_attempt", ["Pesca encerrada."]],
		["coastal_lookout", "leave"],
		["amusement_park", "leave"],
	],
	&"load_2": [
		["garage_rewards", "cancel_press_delivery"],
		["world.traffic_yield", "release_all", ["load"]],
		["world.dispatch", "dismiss_all", ["load"]],
	],
	&"menu_1": [
		["upside_world", "cancel", ["main_menu"]],
		["amusement_park", "leave"],
		["desert", "cancel_attempt"],
		["mining", "cancel_attempt"],
	],
	&"menu_2": [
		["garage_rewards", "cancel_press_delivery"],
		["world.traffic_yield", "release_all", ["main_menu"]],
		["world.dispatch", "dismiss_all", ["main_menu"]],
	],
	&"transition": [
		["arcade", "close"],
		["fishing", "cancel_attempt", ["Pesca encerrada."]],
		["coastal_lookout", "leave"],
		["amusement_park", "leave", [], "abort_if_active"],
		["mountain_activities", "cancel_attempt"],
	],
	# Chamada por ProductionWorld._travel_checked, depois de conferir o solo do destino.
	&"travel": [
		["armored_transport", "suspend_for_travel"],
		["passenger_transport", "cancel_for_transition"],
		["activities", "cancel_attempt"],
		["mountain_progression", "cancel_attempt"],
		["mountain_activities", "cancel_attempt"],
		["garage_rewards", "cancel_press_delivery"],
		["mission_world", "cancel_attempt", ["world_transition"], "if_jessica_bank"],
		["jessica", "cancel_for_transition"],
		["world.traffic_yield", "release_all", ["travel"]],
		["world.dispatch", "dismiss_all", ["travel"]],
	],
}

var g: Node

func _init(host: Node) -> void:
	g = host

## Umbra (parque), Fagulha e Curitiba Cellar: entra-se empurrando a porta
## (WeaponShopEntrance), mas a ação Entrar/Sair de antes continua valendo; a Umbra
## é em primeira pessoa e o indicador da saída é o que o jogador procura lá dentro.
func _keeps_interaction_access(id: String) -> bool:
	return id in ["harbor_haunted_house", "harbor_arcade", "harbor_curitiba_cellar"]

func _uses_walkup_access(id: String) -> bool:
	return (g.weapon_shop_entrance != null and g.weapon_shop_entrance.handles_place(id)) or (g.special_place_entrance != null and g.special_place_entrance.handles_place(id)) or (g.building_entrance != null and g.building_entrance.handles_place(id))

func _arrival_sequence_blocked() -> bool:
	return g.arrival != null and (g.arrival.controls_locked or g.arrival.phase == "opening")

func is_transition_blocked() -> bool:
	if g.regional_coach != null and g.regional_coach.busy(): return true
	if g.railway != null and g.railway.busy(): return true
	return not g.transition_kind.is_empty() or g.vehicle_transition_busy or g.rescue_pending or g.arrest_pending or g.respawn_busy or (g.jessica != null and g.jessica.riding) or (g.controller != null and g.controller.travel_busy) or g._arrival_sequence_blocked()

func has_position_transition() -> bool:
	if g.regional_coach != null and (g.regional_coach.landing or g.regional_coach._boarding): return true
	if g.railway != null and g.railway.landing: return true
	# Uma carona guiada de passageiro trava a entrada mas ainda precisa de chão, trânsito
	# e streaming reais. Só a admissão/recuperação tem um ponto de foco independente.
	return not g.transition_kind.is_empty() or g.vehicle_transition_busy or g.rescue_pending or g.arrest_pending or g.respawn_busy or (g.controller != null and g.controller.travel_busy) or (g.arrival != null and g.arrival.controls_locked and not g.arrival.riding) or (g.arrival != null and g.arrival.phase == "opening")

func blocks_driving_change() -> bool:
	if g.amusement_park != null and g.amusement_park.active: return true
	if g.fishing != null and g.fishing.controls_locked(): return true
	if g.coastal_lookout != null and g.coastal_lookout.active: return true
	if g.building_entrance != null and g.building_entrance.falling: return true
	if g.service_roofs != null and g.service_roofs.is_active(): return true
	if g.desert != null and g.desert.busy(): return true
	return g.is_transition_blocked() or not g.ready_for_play or (g.jessica != null and g.jessica.riding) or (g.motocross != null and g.motocross.mounted) or (g.skate != null and g.skate.controls_locked())

func allows_saved_driver_animation() -> bool:
	return g._restoring_saved_driver and not g.ready_for_play and not g.modal and not g.is_transition_blocked()
