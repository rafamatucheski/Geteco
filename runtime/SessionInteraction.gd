extends RefCounted
## Interação da FullSession: qual ação está mais perto (nearest), a tecla que ela pede, o que fazer ao
## apertar (interact, _intro_interact, perform_urban_action) e o corpo do _input da sessão. Separado em
## 01/11 (Onda 2 de docs/plano-divisao-arquivos-grandes-20261101.md). O estado (modal, rebinding_action,
## _service_menu_open...) continua na sessão; cada função antiga virou delegação de uma linha.
## O _input continua declarado na sessão e só delega para cá: TestSession (test_session_cleanup_registry)
## e DialogueSession (test_maciota_voice) o sobrescrevem ou desligam numa subclasse, e o motor só chama
## _input de Node. Aqui ele é uma função comum com o mesmo nome.
## `g` fica como Node, e não como o script da FullSession, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem close_menu,
## show_message, save_game e _menu numa subclasse da sessão e o despacho tem de continuar igual.

const BLADE_FORGE_TALK := preload("res://gameplay/forge/BladeForgeTalk.gd")
const SEWER_NETWORK := preload("res://world/places/sewers/SewerNetwork.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func nearest() -> Dictionary:
	if g.upside_world != null and g.upside_world.busy(): return {}
	if g.rescue_pending or g.arrest_pending or g.world.gameplay.health <= 0: return {}
	var action: Dictionary = _nearest_activity_action()
	if not action.is_empty(): return action
	if g.building_entrance != null and g.building_entrance.falling: return {}
	if g.service_roofs != null:
		var roof_action: Dictionary = g.service_roofs.nearest_action()
		if not roof_action.is_empty() or g.service_roofs.is_active(): return roof_action
	action = _nearest_field_action()
	if not action.is_empty(): return action
	if g.passenger_transport != null and g.passenger_transport.riding: return g.passenger_transport.nearest_action()
	if g.jessica != null:
		var jessica_action: Dictionary = g.jessica.nearest_action()
		if not jessica_action.is_empty(): return jessica_action
	var arrival_action: Dictionary = g.arrival.nearest_action()
	if is_instance_valid(g.room) and g.room.has_method("nearest_action") and not g.room.has_method("start_game"):
		var rooftop_action: Dictionary = g.building_entrance.nearest_action() if g.building_entrance != null else {}
		if not rooftop_action.is_empty(): return rooftop_action
		var room_action: Dictionary = g.room.nearest_action()
		if not room_action.is_empty(): return room_action
	if not arrival_action.is_empty(): return arrival_action
	if not g.world.driving.occupied and not g.state.place_id.is_empty() and is_instance_valid(g.room):
		if (not g._uses_walkup_access(g.state.place_id) or g._keeps_interaction_access(g.state.place_id)) and g.world.player.position.distance_to(g.room.exit_position) < 1.45: return {"id":"exit","label":"Sair","silent":g.state.place_id in ["harbor_arcade","harbor_curitiba_cellar","harbor_haunted_house"] or preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").is_building(g.state.place_id)}
	var personal_action: Dictionary = g.personal_car.nearest_action()
	if not personal_action.is_empty(): return personal_action
	var residence_action: Dictionary = g.residence_services.nearest_action()
	if not residence_action.is_empty(): return residence_action
	if g.mountain_activities != null:
		var pack_action: Dictionary = g.mountain_activities.nearest_action()
		if not pack_action.is_empty(): return pack_action
	var mountain_action: Dictionary = g.mountain_progression.nearest_action()
	if not mountain_action.is_empty(): return mountain_action
	var garage_action: Dictionary = g.garage_rewards.nearest_action()
	if not garage_action.is_empty(): return garage_action
	if g.world.driving.occupied: return _nearest_driver_action()
	var point: Vector3 = g.world.player.position
	if not g.state.place_id.is_empty(): return _nearest_interior_action(point)
	return _nearest_outdoor_action(point)

## Atividades com ação própria que vêm antes de tudo (jogo de bar, fliperama, gatos, parque, pesca,
## mirante, ônibus): a primeira ação não vazia ganha, na ordem de antes.
func _nearest_activity_action() -> Dictionary:
	if is_instance_valid(g.room) and g.room.has_method("start_game") and g.room.has_method("nearest_action"):
		var bar_action: Dictionary = g.room.nearest_action(g)
		if not bar_action.is_empty(): return bar_action
	if g.arcade != null:
		var arcade_action: Dictionary = g.arcade.nearest_action()
		if not arcade_action.is_empty(): return arcade_action
	if g.cats != null:
		var cat_action: Dictionary = g.cats.nearest_action()
		if not cat_action.is_empty(): return cat_action
	if g.amusement_park != null:
		var park_action: Dictionary = g.amusement_park.nearest_action()
		if not park_action.is_empty(): return park_action
	if g.fishing != null:
		var fishing_action: Dictionary = g.fishing.nearest_action()
		if not fishing_action.is_empty(): return fishing_action
	if g.coastal_lookout != null:
		var lookout_action: Dictionary = g.coastal_lookout.nearest_action()
		if not lookout_action.is_empty(): return lookout_action
	if g.regional_coach != null:
		var coach_action: Dictionary = g.regional_coach.nearest_action()
		if not coach_action.is_empty(): return coach_action
	return {}

## Sistemas de campo (trem, carro-forte, serra, mineração, deserto, forjas, refúgios, skate, suprimentos,
## motocross, contêineres): mesma ordem e mesma regra da primeira ação não vazia.
func _nearest_field_action() -> Dictionary:
	if g.railway != null:
		var railway_action: Dictionary = g.railway.nearest_action()
		if not railway_action.is_empty(): return railway_action
	if g.armored_transport != null:
		var armored_action: Dictionary = g.armored_transport.nearest_action()
		if not armored_action.is_empty(): return armored_action
	if g.mountain_activities != null and g.mountain_activities.busy():
		var pack_active_action: Dictionary = g.mountain_activities.nearest_action()
		if not pack_active_action.is_empty(): return pack_active_action
	if g.mining != null:
		var mining_action: Dictionary = g.mining.nearest_action()
		if not mining_action.is_empty(): return mining_action
	if g.desert != null:
		var desert_action: Dictionary = g.desert.nearest_action()
		if not desert_action.is_empty(): return desert_action
	for site in g.get_tree().get_nodes_in_group("blade_forge_site"):
		var forge_action: Dictionary = site.nearest_action()
		if not forge_action.is_empty(): return forge_action
	for site in g.get_tree().get_nodes_in_group("mountain_refuge_site"):
		var refuge_action: Dictionary = site.nearest_action()
		if not refuge_action.is_empty(): return refuge_action
	if g.skate != null:
		var skate_action: Dictionary = g.skate.nearest_action()
		if not skate_action.is_empty(): return skate_action
	if g.field_inventory != null:
		var supply_action: Dictionary = g.field_inventory.nearest_action()
		if not supply_action.is_empty(): return supply_action
	if g.motocross != null:
		var mx_action: Dictionary = g.motocross.nearest_action()
		if not mx_action.is_empty(): return mx_action
	if g.port_container_loot != null:
		var cargo_action: Dictionary = g.port_container_loot.nearest_action()
		if not cargo_action.is_empty(): return cargo_action
	return {}

## Dirigindo: frete urbano, depois ação de veículo da missão ou da Helena, senão a das atividades.
func _nearest_driver_action() -> Dictionary:
	var driver_freight: Dictionary = g.urban_operations.freight.nearest_action() if g.urban_operations != null and is_instance_valid(g.urban_operations.freight) else {}
	if not driver_freight.is_empty(): return driver_freight
	var vehicle_action: Dictionary = g.mission_world.nearest_vehicle_action()
	if vehicle_action.is_empty() and g.helena_act1 != null: vehicle_action = g.helena_act1.nearest_vehicle_action()
	return vehicle_action if not vehicle_action.is_empty() else g.activities.nearest_action()

## Dentro de um lugar: saída, assalto, Helena, serviços, vinho, operações, rotina e o balcão da sala.
func _nearest_interior_action(point: Vector3) -> Dictionary:
	if (not g._uses_walkup_access(g.state.place_id) or g._keeps_interaction_access(g.state.place_id)) and point.distance_to(g.room.exit_position) < 1.45: return {"id":"exit","label":"Sair","silent":g.state.place_id in ["harbor_arcade","harbor_curitiba_cellar","harbor_haunted_house"] or preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").is_building(g.state.place_id)}
	var robbery_action: Dictionary = g.robberies.nearest_action()
	if not robbery_action.is_empty(): return robbery_action
	var act1_indoor: Dictionary = g.helena_act1.nearest_action() if g.helena_act1 != null else {}
	if not act1_indoor.is_empty(): return act1_indoor
	var original_action: Dictionary = g.services.nearest_action()
	if not original_action.is_empty() and not g.service_threatened(str(original_action.get("target", ""))): return original_action
	if g.wine != null:
		var wine_action: Dictionary = g.wine.nearest_action()
		if not wine_action.is_empty(): return wine_action
	var branch_urban_action: Dictionary = g.urban_operations.nearest_action() if g.urban_operations != null else {}
	if not branch_urban_action.is_empty(): return branch_urban_action
	var interior_routine_action: Dictionary = g.routine_director().nearest_action() if g.routine_director() != null else {}
	if not interior_routine_action.is_empty(): return interior_routine_action
	if g.state.place_id == "maciota":
		for id in ["maciota","mechanic","part"]:
			if id == "part" and g.state.intro.stage != "collect_part": continue
			if point.distance_to(g.room.interaction_points[id]) < 1.3: return {"id":id,"label":"Pegar peça" if id == "part" else "Conversar"}
	else:
		var service_point: Vector3 = g.room.interaction_points.service
		# Boa Praça: os dois caixas vendem; vale o mais perto (SupermarketPlace).
		if g.room.has_method("service_point_for"): service_point = g.room.service_point_for(point)
		var service: String = str(g.room.definition.get("service",""))
		# Police, hospital and fire station publish their terminal/NPC/healing
		# actions through Services.nearest_action(). A second generic counter
		# produced a visible "Atender" prompt with no consumer or result.
		var primary_available := service in ["weapons","clothing","supermarket"]
		if g.state.place_id == "harbor_bank": primary_available = g.state.campaign.target_id() == "helena"
		# A conveniência não tinha balcão de compras no V1: sua operação é o
		# caixa do assalto. Não exponha um "Atender" que não produz resultado.
		if primary_available and not g.service_threatened() and point.distance_to(service_point) < 1.5:
			return {"id":"service","label":"Comprar" if service == "supermarket" else "Falar com Vance" if g.state.place_id in ["harbor_ammunation", "mountain_gunshop"] else "Atender"}
	if g.building_social != null:
		var social_action: Dictionary = g.building_social.nearest_action()
		if not social_action.is_empty(): return social_action
	return {}

## Na rua: Helena, porta trancada, atividades, operações, rotina, entradas de lugares e missões.
func _nearest_outdoor_action(point: Vector3) -> Dictionary:
	# Antes das atividades: o Neco da cadeia da Helena fica no mesmo ponto do serviço de guincho.
	var act1_action: Dictionary = g.helena_act1.nearest_action() if g.helena_act1 != null else {}
	if not act1_action.is_empty(): return act1_action
	# Porta trancada antes das atividades: na soleira, a ação é arrombar.
	var lock_action: Dictionary = g.door_lockpick.nearest_action() if g.door_lockpick != null else {}
	if not lock_action.is_empty(): return lock_action
	var activity_action: Dictionary = g.activities.nearest_action()
	if not activity_action.is_empty(): return activity_action
	var urban_action: Dictionary = g.urban_operations.nearest_action() if g.urban_operations != null else {}
	if not urban_action.is_empty(): return urban_action
	var outdoor_routine_action: Dictionary = g.routine_director().nearest_action() if g.routine_director() != null else {}
	if not outdoor_routine_action.is_empty(): return outdoor_routine_action
	if g.state.region_id == "harbor" and not g._uses_walkup_access("maciota") and point.distance_to(g.world.maciota_place.entry_position) < 1.5: return {"id":"enter","place":"maciota","access":"maciota","label":"Entrar"}
	for entry in g.controller.region.entries:
		if (SEWER_NETWORK.is_manhole(entry.place_id) or entry.place_id == "remote_coal_mine") and point.distance_to(entry.position) < 1.5:
			return {"id":"enter","place":entry.place_id,"access":entry.id,"label":"","silent":true}
		if g._uses_walkup_access(entry.place_id) and not g._keeps_interaction_access(entry.place_id): continue
		if point.distance_to(entry.position) < 1.5:
			return {"id":"enter","place":entry.place_id,"access":entry.id,"label":"Entrar","silent":entry.place_id in ["harbor_arcade","harbor_curitiba_cellar","harbor_haunted_house"] or preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").is_building(entry.place_id)}
	var mission_action: Dictionary = g.mission_world.nearest_action()
	if not mission_action.is_empty(): return mission_action
	return g.passenger_transport.nearest_action()

func interaction_input_action(action: Dictionary) -> String:
	if action.get("id", "") == "enter" and SEWER_NETWORK.is_manhole(str(action.get("place", ""))): return "vehicle_interact"
	if action.get("id", "") == "exit" and SEWER_NETWORK.is_manhole(g.state.place_id): return "vehicle_interact"
	return "interact"

func interact() -> bool:
	if g.modal or not g.ready_for_play: return false
	if g.world.player.get_meta("player_air_busy",false): return false
	var action: Dictionary = g.nearest()
	if action.get("id", "") == "building_social": return g.building_social.open(action.target)
	if action.get("id","") == "building_stairs": return await action.provider.use_stairs()
	if action.get("id","") == "building_lockpick": return await action.provider.perform(action)
	if action.get("id","") == "door_lockpick": return action.provider.perform(action)
	if action.get("id","") == "desert_roadside" and is_instance_valid(action.get("provider")): return action.provider.perform(action)
	if action.get("id","") == "mountain_refuge" and is_instance_valid(action.get("provider")): return action.provider.perform(action)
	if action.get("id","") == "service_roof_stairs": return await g.service_roofs.use_stairs()
	if g.mining != null and action.get("id","") == "mining": return g.mining.perform(action)
	if g.desert != null and action.get("id","") in ["desert","desert_story","desert_drag"]: return g.desert.perform(action)
	if g.mountain_activities != null and g.mountain_activities.handles(action): return g.mountain_activities.perform(action)
	if action.get("id", "") == "blade_forge": return BLADE_FORGE_TALK.perform(g, action)
	if action.get("id", "") == "skate": return g.skate.perform(str(action.target))
	if action.get("id","") == "motocross": return g.motocross.perform(str(action.target))
	if str(action.get("id","")).begins_with("ski_"): return g.mountain_progression.perform(action.target)
	if str(action.get("id","")).begins_with("arrival_"): return g.arrival.perform(action.id)
	match str(action.get("id","")):
		"cat_adopt": return g.cats.perform(str(action.target))
		"fishing": return g.fishing.perform(str(action.target))
		"wine": return g.wine.perform(str(action.target))
		"bar_game": return g.room.start_game(str(action.target),g) if is_instance_valid(g.room) and g.room.has_method("start_game") else false
		"arcade": return g.arcade.perform(str(action.target))
		"coastal_binoculars": return g.coastal_lookout.perform(str(action.target))
		"amusement_park": return g.amusement_park.perform(str(action.target))
		"railway": return g.railway.perform(str(action.target))
		"regional_coach": return g.regional_coach.perform(str(action.target))
		"armored_transport": return g.armored_transport.perform(int(action.target))
		"field_inventory": return g.field_inventory.perform(str(action.target))
		"port_container": return g.port_container_loot.perform(str(action.target))
		"passenger_transport": return g.passenger_transport.perform(action.target)
		"residence_services": return g.residence_services.perform("residence_services")
		"personal_car": return g.personal_car.perform(action.target)
		"jessica": return g.jessica.perform(str(action.target))
		"helena_act1": return g.helena_act1 != null and g.helena_act1.perform(action)
		"garage_reward": return g.garage_rewards.perform(action.target)
		"robbery": return g.robberies.perform(action.target)
		"original_service":
			if g.service_threatened(str(action.target)): return false
			var performed: bool = g.services.perform(action.target)
			g._service_menu_open = performed and g.modal and str(action.target) not in ["hospital_triage", "police_terminal", "fire_alarm"]
			return performed
		"urban_v1": return g.perform_urban_action(str(action.target))
		"v1_routine":
			var routines = g.routine_director()
			return routines != null and routines.perform(str(action.target))
		"exit": return await g.leave_place()
		"enter":
			g.enter_place(action.place,true,str(action.access))
			return true
		"maciota":
			if g.state.intro.stage != "complete": return g._intro_interact("maciota")
			if g.mission_world.perform("maciota"): return true
			g.show_maciota_menu()
			return true
		"mechanic":
			if g.state.intro.stage != "complete": return g._intro_interact("mechanic")
			if g.maciota_workshop != null and g.maciota_workshop.open_menu(): return true
			g.show_services("garage")
			return true
		"part": return g._intro_interact("workbench")
		"service":
			if g.state.place_id == "harbor_bank" and g.mission_world.perform("helena"):
				g._service_menu_open = g.modal
				return true
			g.show_services(g.room.definition.service)
			return true
	if g.activities.perform(str(action.get("target",""))): return true
	return g.mission_world.perform(str(action.get("target","")))

func perform_urban_action(target: String) -> bool:
	if g.urban_operations == null: return false
	var quest = g.urban_operations.get("village_quest")
	if target == "truckers_village_tonico" and is_instance_valid(quest) and not quest.data.started:
		if not g.save_game(true): return false
	return g.urban_operations.perform(target)

func _intro_interact(id: String) -> bool:
	if id == "maciota" and g.state.intro.stage == "meet_maciota" and not g.save_game(true): return false
	g.state.intro.set_location("harbor_garage")
	var reply: Dictionary = g.state.intro.complete_meeting() if id == "maciota" and g.state.intro.stage == "meet_maciota" else g.state.intro.interact(id)
	if not reply.ok: return false
	if id == "maciota": g.arrival.notify_maciota_met()
	if reply.has("lines"):
		g.show_dialogue(preload("res://runtime/ArrivalDialogue.gd").lines(reply.lines),func():
			if g.state.campaign.active_id.is_empty() and not g.state.campaign.has_progress("primeiro_giro"): g.mission_world.begin("primeiro_giro"))
		preload("res://systems/campaign/HarborStory.gd").mark_maciota(g.state.world_state)
	else: g.show_dialogue([{ "speaker":reply.speaker,"message":reply.message }])
	g.world.maciota_place.set_part_available(g.state.intro.part_available)
	if reply.changed: g.save_game()
	return true

func _input(event: InputEvent) -> void:
	if g.world.player != null and g.world.player.get_meta("developer_free_flight",false): return
	GameInput.observe_event(event)
	if is_instance_valid(g.equipment_wheel) and g.equipment_wheel.active:
		g.equipment_wheel.handle_input(event)
		g.get_viewport().set_input_as_handled()
		return
	# A abertura é dona da entrada enquanto o mundo está pausado. Deixa cliques e Esc
	# disponíveis para o botão/diálogo de pular e o handler _unhandled_input.
	if g.arrival != null and g.arrival.phase == "opening" and is_instance_valid(g.arrival.presentation): return
	if g.upside_world != null and g.upside_world.busy():
		if g.upside_world.handle_input(event): g.get_viewport().set_input_as_handled()
		return
	if g.building_social != null and g.building_social.handle_input(event):
		g.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(g.room) and g.room.has_method("handle_game_input") and g.room.handle_game_input(event):
		g.get_viewport().set_input_as_handled()
		return
	if g.arcade != null and g.arcade.handle_input(event):
		g.get_viewport().set_input_as_handled()
		return
	if g.amusement_park != null and g.amusement_park.handle_input(event):
		g.get_viewport().set_input_as_handled()
		return
	if g.fishing != null and g.fishing.handle_input(event):
		g.get_viewport().set_input_as_handled()
		return
	if g.coastal_lookout != null and g.coastal_lookout.handle_input(event):
		g.get_viewport().set_input_as_handled()
		return
	if g.regional_coach != null and g.regional_coach.handle_input(event):
		g.get_viewport().set_input_as_handled()
		return
	if g.railway != null and g.railway.handle_input(event):
		g.get_viewport().set_input_as_handled()
		return
	if g.armored_transport != null and is_instance_valid(g.armored_transport.minigame) and g.armored_transport.minigame.active: return
	if g.port_container_loot != null and is_instance_valid(g.port_container_loot.minigame) and g.port_container_loot.minigame.active: return
	if g.urban_operations != null and is_instance_valid(g.urban_operations.village_leisure) and is_instance_valid(g.urban_operations.village_leisure.ui) and g.urban_operations.village_leisure.ui.active: return
	if g.transition_kind == "ski_lift" and g.mountain_progression != null and g.mountain_progression.lift.riding:
		if not g.get_tree().paused and event.is_action_pressed("interact"):
			g.mountain_progression.lift.skip()
		if not event.is_action_pressed("pause_game") and not (g.get_tree().paused and event.is_action_pressed("ui_cancel")):
			g.get_viewport().set_input_as_handled()
		return
	if g.controller.travel_busy or not g.transition_kind.is_empty() or g.vehicle_transition_busy:
		g.get_viewport().set_input_as_handled()
		return
	if not g.ready_for_play: return
	if g.arrival.riding and (event.is_action_pressed("pause_game") or event.is_action_pressed("exit_vehicle")):
		g.arrival.cancel_ride()
		g.get_viewport().set_input_as_handled()
		return
	if g._arrival_sequence_blocked():
		if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
			g.show_message("Aguarde a conclusão desta chegada.")
		g.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(g.robberies.lockpick) and g.robberies.lockpick.active: return
	if g.police_motor_pool != null and g.police_motor_pool.blocks_input(): return
	if not g.rebinding_action.is_empty():
		if event is InputEventKey and event.pressed and not event.echo:
			var controls = GameInput
			if event.keycode != KEY_ESCAPE:
				var error: String = controls.rebind(g.rebinding_action,event)
				if not error.is_empty(): g.show_message(error); g.get_viewport().set_input_as_handled(); return
				V2Settings.save_settings()
			g.rebinding_action = ""
			controls.remapping = false
			g.show_controls()
			g.get_viewport().set_input_as_handled()
		return
	if g.get_tree().paused: return
	if g.modal:
		if g.field_inventory != null and g.field_inventory.ui.visible and event.is_action_pressed("inventory") and not event.is_action("ui_left") and not event.is_action("ui_right") and not event.is_action("ui_up") and not event.is_action("ui_down"):
			g.close_menu()
			g.get_viewport().set_input_as_handled()
			return
		if g.storefronts != null and g.storefronts.is_open() and g.storefronts.handle_input(event):
			g.get_viewport().set_input_as_handled()
			return
		# Botões focados são donos de ui_accept. Consumi-lo aqui impedia o Enter e o
		# botão de confirmar do controle de chegarem a lojas, diários e resgate na morte.
		if g.dialogue_open and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
			g.advance_dialogue()
			g.get_viewport().set_input_as_handled()
		elif (event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel")) and not g.rescue_pending:
			# Esta conversa guiada é dona do callback de chegada. Dispensar só
			# a superfície largaria o encontro e deixaria Arrival.voice tocando.
			if g.dialogue_open and g.arrival != null and g.arrival.active and g.arrival.dialogue_in_progress():
				g.get_viewport().set_input_as_handled()
				return
			# O tuning é dono do rascunho pendente. O sinal de fechar solta este modal
			# só depois que o jogador aplica ou descarta essas mudanças temporárias.
			for tuning in g.get_tree().get_nodes_in_group("vehicle_tuning_panels"):
				var tuning_panel := tuning as CanvasLayer
				if tuning_panel != null and g.world.is_ancestor_of(tuning_panel) and tuning_panel.visible:
					tuning_panel.call("request_cancel")
					g.get_viewport().set_input_as_handled()
					return
			g.close_menu()
			g.get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact"):
			g.get_viewport().set_input_as_handled()
		return
	if g.get_tree().paused: return
	_play_input(event)

## Entrada de jogo fora de menus e transições: câmera, atividades montadas, pulo, interação, fúria,
## arsenal, recarga e os atalhos (diário, inventário, porta-malas, mapa, lanterna, F5/F9).
func _play_input(event: InputEvent) -> void:
	# Mounted activities consume gameplay events, but their camera stays usable.
	if (event is InputEventMouseMotion and g.world.camera.mouse_orbit_active()) or (not event is InputEventJoypadMotion and (event.is_action_pressed("camera_left") or event.is_action_pressed("camera_right") or event.is_action_pressed("camera_drag"))):
		g.world.camera._unhandled_input(event)
		if g.get_viewport().is_input_handled(): return
	if g.skate != null and g.skate.controls_locked():
		if not g.skate.recovering: g.skate.handle_input(event)
		if not event.is_action_pressed("pause_game"): g.get_viewport().set_input_as_handled()
		return
	if g.passenger_transport != null and g.passenger_transport.riding:
		if event.is_action_pressed("interact") or event.is_action_pressed("exit_vehicle") or event.is_action_pressed("vehicle_interact"):
			g.passenger_transport.request_exit()
		# Deixa a pausa disponível, mas consome entrada de jogo/menu/save rápido em trânsito.
		if not event.is_action_pressed("pause_game"): g.get_viewport().set_input_as_handled()
		return
	if g.motocross != null and g.motocross.mounted:
		# A camada de toque transforma dedos crus em ações de jogo. Consumir os
		# dedos aqui impedia os pedais e o botão de empinar de recebê-los.
		if event is InputEventScreenTouch or event is InputEventScreenDrag: return
		if event.is_action_pressed("interact") or event.is_action_pressed("exit_vehicle"):
			g.motocross.perform("quit" if g.motocross.active else "dismount")
		if not event.is_action_pressed("pause_game"): g.get_viewport().set_input_as_handled()
		return
	if g.world.driving.occupied and is_instance_valid(g.world.driving.car.equipment):
		if g.world.driving.car.equipment.handle_input(event,true):
			g.get_viewport().set_input_as_handled()
			return
	var wants_interact := false
	if is_instance_valid(g.equipment_wheel) and g.equipment_wheel.handle_input(event):
		g.get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("jump") and not event.is_echo() and not g.world.driving.occupied:
		if g.world.player.air_movement != null and g.world.player.air_movement.request_jump(): g.get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("vehicle_interact"):
		wants_interact = event.is_action_pressed(g.interaction_input_action(g.nearest()))
	# Trata antes que o foco de GUI consuma V/R3, depois das guardas de modal/veículo.
	if event.is_action_pressed("rage") and not event.is_echo() and not g.world.driving.occupied:
		if g.world.gameplay.request_rage(): g.get_viewport().set_input_as_handled()
		return
	if g.world.gameplay.handle_arsenal_input(event):
		g.get_viewport().set_input_as_handled()
		return
	var wants_reload: bool = event.is_action_pressed("reload") and not g.world.driving.occupied
	if wants_interact and (not wants_reload or not g.nearest().is_empty()):
		g.interact()
		g.get_viewport().set_input_as_handled()
	elif wants_reload:
		g.world.gameplay.reload_weapon()
		g.get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal"): g.show_journal()
	elif event.is_action_pressed("inventory"): g.show_inventory()
	elif event.is_action_pressed("trunk"):
		var personal_action: Dictionary = g.personal_car.nearest_action()
		if personal_action.get("target","") == "trunk":
			g.personal_car.perform(personal_action.target)
		elif event.is_action_pressed("unarmed") and not g.world.driving.occupied:
			g.state.equip_weapon("fists")
		g.get_viewport().set_input_as_handled()
	elif event.is_action_pressed("world_map"): g.show_map()
	elif event.is_action_pressed("unarmed"): g.state.equip_weapon("fists")
	elif event.is_action_pressed("weapon_next") and not g.world.driving.occupied: g.world.gameplay.cycle_weapon(1)
	elif event.is_action_pressed("weapon_flashlight") and not event.is_echo():
		g.toggle_weapon_flashlight()
		g.get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F5: g.save_game(true)
		elif event.physical_keycode == KEY_F9: g.load_game()
