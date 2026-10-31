extends RefCounted
## Gravar, recarregar e voltar ao menu principal da FullSession: motivo de recusa, checkpoint adiado,
## indicador e os snapshots de cada sistema. Separado em 31/10 para o FullSession.gd caber na leitura;
## o estado (last_save_error, _checkpoint_retry) continua na sessão e cada função antiga virou delegação.
## `g` fica como Node, e não como o script da FullSession, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem save_game numa
## subclasse da sessão e o despacho tem de continuar igual.

const STALL_WORK_READY := preload("res://runtime/StallWorkTrace.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func save_block_reason() -> String:
	if g.world.player.get_meta("player_air_busy", false): return "Aguarde terminar o salto ou a queda para salvar."
	if g.world.get_meta("developer_mode_active",false): return "Desligue o modo desenvolvedor para salvar."
	if g.upside_world != null and g.upside_world.busy(): return "Aguarde a visão passar."
	if g.arcade != null and g.arcade.active: return "Saia do fliperama para salvar."
	if g.amusement_park != null and g.amusement_park.active: return "Termine o passeio para salvar."
	if g.fishing != null:
		var fishing_reason: String = g.fishing.save_block_reason()
		if not fishing_reason.is_empty(): return fishing_reason
	if g.coastal_lookout != null and g.coastal_lookout.active: return "Saia do binóculo para salvar."
	if g.building_entrance != null and g.building_entrance.falling: return "Aguarde chegar ao chão."
	if g.service_roofs != null and g.service_roofs.falling: return "Aguarde chegar ao chão."
	if g.regional_coach != null:
		var coach_reason: String = g.regional_coach.save_block_reason()
		if not coach_reason.is_empty(): return coach_reason
	if g.railway != null:
		var railway_reason: String = g.railway.save_block_reason()
		if not railway_reason.is_empty(): return railway_reason
	if g.armored_transport != null:
		var armored_reason: String = g.armored_transport.save_block_reason()
		if not armored_reason.is_empty(): return armored_reason
	if g.mountain_activities != null:
		var pack_reason: String = g.mountain_activities.save_block_reason()
		if not pack_reason.is_empty(): return pack_reason
	if g.mining != null:
		var mining_reason: String = g.mining.save_block_reason()
		if not mining_reason.is_empty(): return mining_reason
	if g.desert != null:
		var desert_reason: String = g.desert.save_block_reason()
		if not desert_reason.is_empty(): return desert_reason
	if g.jessica != null and g.jessica.riding: return "Aguarde Jessica estacionar para salvar."
	var vertice_night: Node = g._vertice_night()
	if vertice_night != null:
		var night_reason: String = vertice_night.save_block_reason()
		if not night_reason.is_empty(): return night_reason
	if g.skate != null and g.skate.controls_locked(): return "Desça do skate e se recupere para salvar."
	if g.controller.save_invalid: return g.controller.save_block_text()
	if is_instance_valid(g.room) and g.room.has_method("start_game") and g.room.get("game_active") == true: return "Encerre a partida para salvar."
	if g.motocross != null and g.motocross.mounted: return "Termine a corrida ou desça da moto para salvar."
	if g.world.gameplay.health <= 0: return "Salvar indisponível enquanto o jogador estiver morto."
	if g.world.gameplay.stars > 0: return "Perca todas as estrelas da polícia para salvar."
	if not g.state.campaign.active_id.is_empty() or g.state.intro.stage not in ["meet_maciota", "complete"]:
		return "Conclua ou encerre a missão para salvar um checkpoint."
	if g.activities != null and not g.activities.can_rest(): return "Encerre a corrida ou o contrato de guincho para salvar."
	if g.mountain_progression != null and not g.mountain_progression.race.mode.is_empty(): return "Encerre a prova de esqui para salvar."
	if g.urban_operations != null:
		var quest = g.urban_operations.get("village_quest")
		if is_instance_valid(quest) and quest.data.started and not quest.data.completed:
			return "Conclua a missão de Tonico para salvar um checkpoint."
	if g.urban_operations != null and g.urban_operations.freight != null and g.urban_operations.freight.active_bay >= 0:
		return "Encerre a entrega de carga para salvar."
	if g.is_transition_blocked(): return "Conclua a chegada, o resgate ou a transição para salvar."
	if g.passenger_transport != null and g.passenger_transport.riding: return "Aguarde o desembarque para salvar."
	return ""

func _queue_checkpoint() -> void:
	if g.controller.no_save or g.controller.save_invalid: return
	if g._checkpoint_retry == null:
		g._checkpoint_retry = Timer.new()
		g._checkpoint_retry.process_mode = Node.PROCESS_MODE_PAUSABLE
		g._checkpoint_retry.wait_time = 1.0
		g._checkpoint_retry.one_shot = true
		g.add_child(g._checkpoint_retry)
		g._checkpoint_retry.timeout.connect(func(): g.save_game())
	# Only one pending request; capture fresh state once saving becomes safe.
	if g._checkpoint_retry.is_stopped(): g._checkpoint_retry.start()

func _save_indicator() -> Control:
	var indicator: Node = g.get_node_or_null("SaveFeedback/Indicator")
	if indicator == null:
		var feedback := CanvasLayer.new()
		feedback.name = "SaveFeedback"
		feedback.layer = 125
		g.add_child(feedback)
		indicator = preload("res://ui/SaveIndicator.gd").new()
		indicator.name = "Indicator"
		feedback.add_child(indicator)
	return indicator

## Autosave tem ~170 chamadores e cada gravação faz ~25 snapshots e quatro validações completas:
## o span dá nome ao pico no log de quadros lentos (antes aparecia sem dono).
func save_game(manual := false) -> bool:
	var began := STALL_WORK_READY.begin()
	var saved: bool = g._save_game(manual)
	STALL_WORK_READY.finish_slow("session.save_game", began, 4000, g)
	return saved

func _save_game(manual: bool) -> bool:
	var blocked: String = g.save_block_reason()
	if not blocked.is_empty():
		if manual: g._save_indicator().reject(blocked)
		else: g._queue_checkpoint()
		return false
	g.state.world_state.erase("pedestrian")
	# Menus hold input too; a supported, free on-foot position remains saveable.
	if g.state.place_id.is_empty() and not g.world.driving.occupied and g.position_clear(g.world.player.position):
		var point: Vector3 = g.world.player.position
		g.state.world_state.pedestrian = {"region":g.state.region_id,"position":[point.x,point.y,point.z]}
	if g.personal_car != null: g.personal_car.refresh()
	if g.activities != null: g.activities.refresh_achievements()
	if g.desert != null: g.desert.write_snapshot()
	if g.mining != null: g.mining.write_snapshot()
	g.controller.capture_player_vehicle()
	if g.desert!=null and is_instance_valid(g.desert.drag) and is_instance_valid(g.desert.drag.loaner_controller): g.desert.drag.loaner_controller.prepare_save()
	if g.cold != null: g.state.world_state.cold = g.cold.snapshot()
	if g.wine != null: g.state.world_state.wine_cellar = g.wine.snapshot()
	if g.garage_rewards != null: g.state.world_state.garage_rewards = g.garage_rewards.snapshot()
	if g.arrival != null: g.state.world_state.arrival = g.arrival.snapshot()
	if g.robberies != null: g.state.world_state.robberies = g.robberies.snapshot()
	if g.services != null: g.state.world_state.services = g.services.snapshot()
	if g.activities != null: g.state.world_state.activities = g.activities.snapshot()
	if g.motocross != null: g.state.world_state.motocross = g.motocross.snapshot()
	if g.skate != null: g.state.world_state.skate = g.skate.snapshot()
	if g.mountain_progression != null: g.state.world_state.mountain_progression = g.mountain_progression.snapshot()
	if g.mountain_activities != null: g.mountain_activities.write_snapshot()
	if g.mission_world != null: g.state.world_state.mission_world = g.mission_world.snapshot()
	if g.jessica != null: g.state.world_state.jessica_vehicle = g.jessica.vehicle_snapshot()
	if g.urban_operations != null:
		var urban_snapshot: Dictionary = g.urban_operations.snapshot()
		# Estado urbano no meio de uma troca: recusa só esta gravação; o próximo pedido de
		# salvar tenta de novo. Antes um único instante assim desligava o salvamento pelo
		# resto da sessão, em silêncio. Sem fila de 1 s: cada tentativa refaz todos os snapshots.
		if not preload("res://gameplay/urban_v1/UrbanOperations.gd").validate_snapshot(urban_snapshot):
			g.last_save_error = "Estado urbano incompleto; salvamento adiado."
			push_warning(g.last_save_error)
			if manual: g._save_indicator().reject(g.last_save_error)
			return false
		g.state.world_state.urban_operations = urban_snapshot
	if g.controller.no_save: return true
	g.state.combat_state = g.world.gameplay.snapshot()
	var result: Error = g.controller.store.save(g.state)
	if g._checkpoint_retry != null: g._checkpoint_retry.stop()
	if result != OK:
		g.last_save_error = String(TranslationServer.translate("Não foi possível salvar (%d).")) % result
		g._save_indicator().reject(g.last_save_error)
		return false
	g.last_save_error = ""
	g._save_indicator().acknowledge()
	return true

func load_game() -> void:
	if g.upside_world != null and g.upside_world.busy() and g.upside_world._released:
		g.show_message("Aguarde a conclusão da transição para carregar.")
		return
	# Ilusão, pesca, mirante e parque terminam antes das recusas abaixo, como sempre foi.
	g._cancel_for(&"load_1")
	if g.desert != null and g.desert.busy(): g.show_message("Encerre a prova para carregar."); return
	if g.jessica != null and g.jessica.riding:
		g.show_message("Aguarde Jessica estacionar para carregar."); return
	if g.is_transition_blocked():
		g.show_message("Aguarde a conclusão da transição para carregar."); return
	if g.passenger_transport != null and g.passenger_transport.riding:
		g.show_message("Aguarde o desembarque para carregar."); return
	if g.world.driving.occupied: g.show_message("Saia do veículo para carregar."); return
	g._cancel_for(&"load_2")
	var result: Error = g.get_tree().reload_current_scene()
	if result != OK: g.show_message(String(TranslationServer.translate("Não foi possível carregar o jogo (%d).")) % result)

func return_to_main_menu() -> void:
	if g.upside_world != null and g.upside_world.busy() and g.upside_world._released:
		g.show_message("Aguarde a conclusão da transição.")
		return
	# Deserto e mineração já são cancelados quando o menu recusa abaixo, como sempre foi.
	g._cancel_for(&"menu_1")
	if g.is_transition_blocked() or (g.passenger_transport != null and g.passenger_transport.riding):
		g.show_message("Aguarde a conclusão da chegada, do resgate ou da transição.")
		return
	g._cancel_for(&"menu_2")
	var launch = g.get_node_or_null("/root/V2Launch")
	if launch != null: launch.direct_start_consumed = true
	var was_paused: bool = g.get_tree().paused
	g.get_tree().paused = false
	var result: Error = g.get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
	if result != OK:
		g.get_tree().paused = was_paused
		g.show_message("Não foi possível abrir o menu principal.")
