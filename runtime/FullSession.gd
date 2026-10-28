extends Node
signal startup_finished
var incremental_startup := false
var startup_complete := false
var _startup_slice_usec := 0
const BLADE_FORGE_TALK := preload("res://gameplay/forge/BladeForgeTalk.gd")
const STALL_WORK_READY := preload("res://runtime/StallWorkTrace.gd")
const SESSION_OPS := preload("res://runtime/SessionOperations.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const SEWER_DESCENT := preload("res://gameplay/SewerHatchDescent.gd")
const SEWER_NETWORK := preload("res://world/places/sewers/SewerNetwork.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const V1_DEATH_AUDIO := preload("res://audio/V1DeathAudio.gd")
const DOOR_TRANSITION := preload("res://runtime/DoorTransition.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
const RECOVERY_PENALTY := preload("res://runtime/RecoveryPenalty.gd")
const STORY_PAY := preload("res://systems/campaign/StoryPay.gd")
const JOURNAL_ARCS := preload("res://runtime/JournalArcs.gd")
const WORKPLACE_REACTION := preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd")
const DIALOGUE_CARD := preload("res://ui/dialogue/DialogueCard.gd")
const DIALOGUE_CAPTION := preload("res://ui/dialogue/DialogueCaption.gd")
const VOICE := preload("res://audio/ExpressiveVoice.gd")
var world
var controller
var weather
var state
var room: Node3D
var room_npc: CharacterBody3D
var room_npcs: Array[CharacterBody3D] = []
var static_service_actor: Node3D
var anchor: Node3D
var objective: Label
var freight_active := false
var freight_target := Vector3.INF
var _restoring_saved_driver := false
var stats: Label
var thermal_status: Label
var prompt: Label
var notice: Label
var marker: Node2D
var arrow: Label
var panel: PanelContainer
var column: VBoxContainer
var modal := false
var _service_menu_open := false
var menu_closed := Callable()
var dialogue_open := false
var lines: Array = []
var dialogue_done := Callable()
var access_id := ""
var return_point := Vector3.ZERO
var saved_heading := 0.0
var saved_size := 28.0
var notice_time := 0.0
var _reward_failures: Dictionary = {}
var _reward_notice_id := ""
var tick := 0.0
var ready_for_play := false
var mission_world
var activities
var motocross
var skate
var services
var storefronts
var wine
var upside_world: Node
var arcade
var robberies
var arrival
var garage_rewards
var police_motor_pool
var personal_car
var jessica
## Ato 1, cadeia da Helena e do Neco (runtime/harbor_act1/HelenaAct1.gd).
var helena_act1
var desert
var maciota_workshop
var mining
var dialogue_voice: AudioStreamPlayer
var _dialogue_source: Dictionary = {}
var _speech_source: Dictionary = {}
var speech_voice: AudioStreamPlayer
var dialogue_card: DIALOGUE_CARD
var speech_caption: DIALOGUE_CAPTION
var speech_active := false
var residence_services
var cats
var mountain_progression
var mountain_activities
var cold
var passenger_transport
var railway
var railway_world
var regional_coach
var urban_operations
var port_container_loot
var armored_transport
var field_inventory
var equipment_wheel
var action_serial := 0
var rebinding_action := ""
var vehicle_transition_busy := false
var rescue_pending := false
var arrest_pending := false
var respawn_busy := false
var transition_generation := 0
var transition_kind := ""
var rescue_camera_heading := 0.0
var rescue_camera_size := 28.0
var death_presentation: CanvasLayer
var _recovery_time_scale := 1.0
var _recovery_slow_motion := false
var bank_death_loss := 0
var sewer_hatch: Node3D
var sewer_entry_origin := Vector3.ZERO
var prompt_input_action := "interact"
var weapon_shop_entrance: Node
var special_place_entrance: Node
var building_entrance: Node
var building_social: Node
var service_roofs: Node
var coastal_lookout: Node
var amusement_park: Node
var fishing: Node
var fishing_runtime: Node
var door_transition: CanvasLayer
var last_save_error := ""
## O HUD lê estes campos, não o texto dos Labels antigos (ContextualHUDManager). Antes ele lia
## objective.text/prompt.text e casava frases exatas ("J  Missões · M  Mapa", prefixo "E  ",
## "Atender telefone"): mudar ou traduzir uma frase quebrava o aviso em silêncio (revisão 18/10).
## hud_objective vazio = sem cartão de objetivo; hud_prompt é a legenda sem a tecla.
var hud_objective := ""
var hud_prompt := ""
var _save_block_shown := false
var _checkpoint_retry: Timer

## Umbra (parque), Fagulha e Curitiba Cellar: entra-se empurrando a porta
## (WeaponShopEntrance), mas a ação Entrar/Sair de antes continua valendo; a Umbra
## é em primeira pessoa e o indicador da saída é o que o jogador procura lá dentro.
func _keeps_interaction_access(id: String) -> bool:
	return id in ["harbor_haunted_house", "harbor_arcade", "harbor_curitiba_cellar"]

func _uses_walkup_access(id: String) -> bool:
	return (weapon_shop_entrance != null and weapon_shop_entrance.handles_place(id)) or (special_place_entrance != null and special_place_entrance.handles_place(id)) or (building_entrance != null and building_entrance.handles_place(id))

func _arrival_sequence_blocked() -> bool:
	return arrival != null and (arrival.controls_locked or arrival.phase == "opening")

func is_transition_blocked() -> bool:
	if regional_coach != null and regional_coach.busy(): return true
	if railway != null and railway.busy(): return true
	return not transition_kind.is_empty() or vehicle_transition_busy or rescue_pending or arrest_pending or respawn_busy or (jessica != null and jessica.riding) or (controller != null and controller.travel_busy) or _arrival_sequence_blocked()

func has_position_transition() -> bool:
	if regional_coach != null and (regional_coach.landing or regional_coach._boarding): return true
	if railway != null and railway.landing: return true
	# A guided passenger ride locks input but still needs real floor, traffic
	# and streaming. Only admission/recovery owns an independent focus point.
	return not transition_kind.is_empty() or vehicle_transition_busy or rescue_pending or arrest_pending or respawn_busy or (controller != null and controller.travel_busy) or (arrival != null and arrival.controls_locked and not arrival.riding) or (arrival != null and arrival.phase == "opening")

func blocks_driving_change() -> bool:
	if amusement_park != null and amusement_park.active: return true
	if fishing != null and fishing.controls_locked(): return true
	if coastal_lookout != null and coastal_lookout.active: return true
	if building_entrance != null and building_entrance.falling: return true
	if service_roofs != null and service_roofs.is_active(): return true
	if desert != null and desert.busy(): return true
	return is_transition_blocked() or not ready_for_play or (jessica != null and jessica.riding) or (motocross != null and motocross.mounted) or (skate != null and skate.controls_locked())

func allows_saved_driver_animation() -> bool:
	return _restoring_saved_driver and not ready_for_play and not modal and not is_transition_blocked()

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
	# O resgate também passa por "transition" (_begin_transition) entre rescue_1 e rescue_2.
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

## Roda uma etapa de CANCEL_STEPS. Devolve false só quando um passo abort_if_active recusou.
func _cancel_for(stage: StringName) -> bool:
	if is_instance_valid(equipment_wheel): equipment_wheel.cancel()
	if not CANCEL_STEPS.has(stage):
		push_error("Etapa de limpeza desconhecida: %s" % stage)
		return true
	for step: Array in CANCEL_STEPS[stage]:
		var system = _cancel_system(step[0])
		if system == null: continue
		var method: String = step[1]
		var rule: String = step[3] if step.size() > 3 else ""
		if rule == "if_method" and not system.has_method(method): continue
		if rule == "if_riding" and not system.riding: continue
		if rule == "if_jessica_bank" and not (is_instance_valid(jessica) and state.campaign.active_id == "jessica_bank"): continue
		system.callv(method, step[2] if step.size() > 2 else [])
		if rule == "abort_if_active" and system.active: return false
	return true

func _cancel_system(path: String) -> Object:
	if path.is_empty(): return self
	var system: Variant = self
	for part in path.split("."):
		system = system.get(part)
		if not is_instance_valid(system): return null
	return system

func _begin_transition(kind: String, _vehicle := false) -> int:
	if not transition_kind.is_empty() or (controller != null and controller.travel_busy): return -1
	if not _cancel_for(&"transition"): return -1
	transition_generation += 1
	transition_kind = kind
	# Legacy consumers already treat this public flag as the session transition
	# gate. Keep it asserted for every generation, not only vehicle transfers.
	vehicle_transition_busy = true
	return transition_generation

func _owns_transition(token: int) -> bool:
	return token > 0 and token == transition_generation and not transition_kind.is_empty()

func _finish_transition(token: int) -> void:
	if not _owns_transition(token): return
	transition_kind = ""
	vehicle_transition_busy = false

func _routine_director():
	return world.get_node_or_null("V1RoutineDirector") if world != null else null

func _refresh_routine_context() -> void:
	var routines = _routine_director()
	if routines != null: routines.refresh_context()
	if urban_operations != null: urban_operations.refresh_context()

func _sync_location_presentation() -> void:
	if is_instance_valid(weather): weather._update()
	prompt.text = ""
	world.gameplay._update_visual()
	var city_look := world.get_node_or_null("CityLook") as Node
	if city_look != null: city_look._refresh_silhouette()
	if world.hud.has_method("refresh_from_state"): world.hud.refresh_from_state()

func _vehicle_transition_snapshot(car: CharacterBody3D) -> Dictionary:
	return {
		"generation": transition_generation,
		"occupied": world.driving.occupied,
		"driving_car": world.driving.car,
		"car_locked": car.input_locked,
		"car_controlled": car.controlled,
		"car_external_input": car.external_input,
		"player_locked": world.player.input_locked,
		"player_visible": world.player.visible,
		"player_physics": world.player.is_physics_processing(),
		"player_layer": world.player.collision_layer,
		"player_mask": world.player.collision_mask,
		"camera_target": world.camera.target,
		"camera_offset": world.camera.offset,
		"camera_heading": world.camera.heading,
		"camera_target_size": world.camera.target_size,
		"camera_size": world.camera.size,
		"camera_locked": world.camera.locked,
	}

func _restore_vehicle_transition_snapshot(snapshot: Dictionary, car: CharacterBody3D) -> void:
	if int(snapshot.generation) != transition_generation: return
	# Death/arrest owns the actor now. Release only our provisional car lock;
	# restoring old occupancy, collision or camera would revive a stale state.
	if world.gameplay.health <= 0 or rescue_pending or arrest_pending:
		if is_instance_valid(car) and not car.controlled: car.input_locked = bool(snapshot.car_locked)
		return
	if is_instance_valid(car):
		car.input_locked = bool(snapshot.car_locked)
		car.controlled = bool(snapshot.car_controlled)
		car.external_input = bool(snapshot.car_external_input)
	world.driving.occupied = bool(snapshot.occupied)
	world.driving.car = snapshot.driving_car if is_instance_valid(snapshot.driving_car) else car
	world.player.input_locked = bool(snapshot.player_locked)
	world.player.visible = bool(snapshot.player_visible)
	world.player.set_physics_process(bool(snapshot.player_physics))
	world.player.collision_layer = int(snapshot.player_layer)
	world.player.collision_mask = int(snapshot.player_mask)
	if is_instance_valid(snapshot.camera_target): world.camera.target = snapshot.camera_target
	world.camera.offset = snapshot.camera_offset
	world.camera.heading = float(snapshot.camera_heading)
	world.camera.target_size = float(snapshot.camera_target_size)
	world.camera.size = float(snapshot.camera_size)
	world.camera.locked = bool(snapshot.camera_locked)
	world.camera.initialized = false

func _restore_transition_player_lock(previous: bool, token: int) -> void:
	if token != transition_generation or world.gameplay.health <= 0 or rescue_pending or arrest_pending: return
	world.player.input_locked = previous

func _discard_place_candidate(candidate: Node3D, owned: bool) -> void:
	if not is_instance_valid(candidate): return
	if building_entrance != null and candidate == building_entrance.staged: building_entrance.departed(candidate)
	if candidate == world.maciota_place: candidate.set_interior_active(false)
	elif owned: candidate.queue_free()

func _garage_transfer_valid(token: int, car: CharacterBody3D, place_id: String, entering: bool, expected_room: Node3D) -> bool:
	if not _owns_transition(token) or not is_instance_valid(car) or car.health <= 0 or world.gameplay.health <= 0: return false
	if not world.driving.occupied or world.driving.car != car or room != expected_room: return false
	if car.get("engine_disabled") == true: return false
	if entering and not preload("res://runtime/ShopSafety.gd").admission_allowed(place_id,world.gameplay.stars): return false
	if entering and place_id == "desert_digo" and not preload("res://systems/campaign/DigoProgress.gd").workshop_unlocked(state.world_state): return false
	return state.place_id.is_empty() if entering else state.place_id == place_id

func transfer_garage_vehicle(place_id: String, car: CharacterBody3D, entering: bool) -> bool:
	var access_speed := 2.2 if place_id == "desert_digo" else .5
	if is_transition_blocked() or not is_instance_valid(car) or car.health<=0 or absf(car.speed)>access_speed: return false
	if not world.driving.occupied or world.driving.car != car: return false
	if entering and (not state.place_id.is_empty() or is_instance_valid(room)): return false
	if not entering and state.place_id != place_id: return false
	if entering and not preload("res://runtime/ShopSafety.gd").admission_allowed(place_id,world.gameplay.stars): return false
	if entering and place_id == "desert_digo" and not preload("res://systems/campaign/DigoProgress.gd").workshop_unlocked(state.world_state): return false
	var definition: Dictionary = PLACES.get_definition(place_id)
	if place_id == "maciota":
		if state.region_id != "harbor": return false
	elif definition.is_empty() or definition.get("region","") != state.region_id or not definition.has("vehicle_spawn"):
		return false
	var token := _begin_transition("garage_vehicle",true)
	if token < 0: return false
	var snapshot := _vehicle_transition_snapshot(car)
	var expected_room: Node3D = room
	car.input_locked = true
	world.player.input_locked = true
	car.speed = 0
	car.horizontal_velocity = Vector3.ZERO
	if place_id == "desert_digo": await door_transition.fade_to(1.0,.18)
	if place_id == "desert_digo" and not _set_digo_vehicle_gate(true,token,car):
		_restore_vehicle_transition_snapshot(snapshot,car)
		_finish_transition(token)
		show_message("Aguarde o portão da oficina ficar disponível.")
		return false
	var destination: Vector3
	var yaw := 0.0
	var next_room: Node3D = null
	var owns_next_room := false
	if entering:
		if place_id == "maciota":
			next_room = world.maciota_place
			next_room.set_interior_active(true)
			destination = next_room.interior_origin+Vector3(0,.1,1)
		else:
			next_room = PLACES.create_place(place_id)
			if next_room == null:
				if place_id == "desert_digo": _set_digo_vehicle_gate(false)
				_restore_vehicle_transition_snapshot(snapshot,car)
				_finish_transition(token)
				return false
			owns_next_room = true
			next_room.position = Vector3(0,0,-2400)
			world.add_child(next_room)
			destination = next_room.to_global(definition.vehicle_spawn)+Vector3.UP*.08
			yaw = float(definition.get("vehicle_spawn_yaw",0.0))
	else:
		destination = world.maciota_place.exterior_vehicle_return+Vector3.UP*.1 if place_id == "maciota" else definition.vehicle_return+Vector3.UP*.08
		yaw = world.maciota_place.exterior_vehicle_yaw if place_id == "maciota" else float(definition.get("vehicle_return_yaw",0))
		controller.region.set_focus(destination)
	for i in 3:
		await get_tree().physics_frame
		if not _garage_transfer_valid(token,car,place_id,entering,expected_room):
			if place_id == "desert_digo": _set_digo_vehicle_gate(false)
			_discard_place_candidate(next_room,owns_next_room)
			controller.region.set_focus(car.global_position if is_instance_valid(car) else world.player.global_position)
			_restore_vehicle_transition_snapshot(snapshot,car)
			_finish_transition(token)
			return false
	if not controller.vehicle_position_clear(car,destination,yaw):
		if place_id == "desert_digo": _set_digo_vehicle_gate(false)
		_discard_place_candidate(next_room,owns_next_room)
		controller.region.set_focus(car.global_position)
		_restore_vehicle_transition_snapshot(snapshot,car)
		_finish_transition(token)
		show_message("Passagem do veículo ocupada. Aguarde espaço livre.")
		return false
	if entering:
		saved_heading = world.camera.heading
		saved_size = world.camera.target_size
		room = next_room
		return_point = room.exterior_return if place_id == "maciota" else definition.return_position
		state.set_location(state.region_id,place_id)
		state.checkpoint_id = place_id
		anchor.position = room.camera_target
		world.camera.target = anchor
		world.camera.offset = Vector3(0,18,15)
		world.camera.heading = 0
		world.camera.target_size = room.camera_size
		world.camera.size = room.camera_size
		world.camera.locked = true
	else:
		_clear_service_npcs()
		if room == world.maciota_place: room.set_interior_active(false)
		else: room.queue_free()
		room = null
		state.set_location(state.region_id)
		world.camera.target = car
		world.camera.offset = world.camera.EXTERIOR_OFFSET
		world.camera.heading = saved_heading
		world.camera.target_size = saved_size
		world.camera.locked = false
	car.set_meta("garage_place",place_id if entering else "")
	car.set_meta("region_id",state.region_id)
	car.place(destination,yaw)
	world.player.teleport(destination)
	# Actor.teleport releases the seated pose; this transfer keeps the same driver.
	if car.has_method("shows_seated_driver") and car.shows_seated_driver():
		preload("res://gameplay/VehicleInterior.gd").attach(car)
		preload("res://gameplay/VehicleInterior.gd").seat_driver(world.player,car,0.0)
	_sync_location_presentation()
	world.camera.initialized = false
	world.camera._process(1)
	if place_id == "desert_digo": _set_digo_vehicle_gate(false)
	car.input_locked = bool(snapshot.car_locked)
	world.player.input_locked = bool(snapshot.player_locked)
	_finish_transition(token)
	if entering and place_id != "maciota": _install_service_npc()
	arrival.on_location_changed()
	_refresh_routine_context()
	sync_dispatch_location()
	return true

func _set_digo_vehicle_gate(opened: bool, token := -1, car: CharacterBody3D = null) -> bool:
	var from_inside: bool = state.place_id == "desert_digo"
	var authorize := func() -> bool:
		if not is_instance_valid(car) or not _owns_transition(token) or transition_kind != "garage_vehicle" or not car.input_locked or not world.player.input_locked or not world.driving.occupied or world.driving.car != car or state.region_id != "desert" or car.health <= 0 or world.gameplay.health <= 0: return false
		if from_inside: return state.place_id == "desert_digo" and is_instance_valid(room)
		return state.place_id.is_empty() and preload("res://runtime/ShopSafety.gd").admission_allowed("desert_digo",world.gameplay.stars) and preload("res://systems/campaign/DigoProgress.gd").workshop_unlocked(state.world_state)
	var changed := false
	var groups: Array = ["digo_interior_vehicle_gate" if from_inside else "digo_vehicle_gate"] if opened else ["digo_vehicle_gate","digo_interior_vehicle_gate"]
	for group in groups:
		for gate in get_tree().get_nodes_in_group(group):
			if world.is_ancestor_of(gate) and gate.has_method("set_vehicle_access"):
				changed = bool(gate.set_vehicle_access(opened,authorize)) or changed
	return changed

func restore_garage_driver(car: CharacterBody3D) -> bool:
	if is_transition_blocked() or not is_instance_valid(car) or car.health<=0 or world.driving.occupied: return false
	var place: String = state.place_id
	if place not in ["","maciota","port_boss_garage","desert_digo"] or car.get_meta("garage_place","") != place: return false
	if car.get_meta("region_id",state.region_id) != state.region_id or car.get("engine_disabled") == true: return false
	if place == "maciota" and state.region_id != "harbor": return false
	var definition := PLACES.get_definition(place)
	if not place.is_empty() and place != "maciota" and (definition.is_empty() or definition.get("region","") != state.region_id): return false
	var token := _begin_transition("restore_garage_driver",true)
	if token < 0: return false
	var snapshot := _vehicle_transition_snapshot(car)
	var expected_room: Node3D = room
	car.input_locked = true
	for i in 3:
		await get_tree().physics_frame
		if not _owns_transition(token) or not is_instance_valid(car) or state.place_id != place or room != expected_room or world.driving.occupied or modal or world.gameplay.health <= 0:
			_restore_vehicle_transition_snapshot(snapshot,car)
			_finish_transition(token)
			return false
	if car.health<=0 or not car.is_visible_in_tree() or car.collision_layer == 0 or not controller.vehicle_position_clear(car,car.position,car.rotation.y):
		_restore_vehicle_transition_snapshot(snapshot,car)
		_finish_transition(token)
		return false
	var checkpoint: Vector3 = world.player.position
	var previous_car: CharacterBody3D = world.driving.car
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.7
	for side in [-1,1]:
		var point := car.to_global(Vector3(side*(car.half_width+.65),.05,.15))
		# Long cabins sit beyond the reach of the generic car-side anchor.
		if car.boarding_class() in ["truck", "bus"]:
			point = car.driver_door_anchor(side) + car.global_basis.x * float(side) * .11 + Vector3.UP * .01
		if not position_clear(point): continue
		# Restoring a seated save may relocate the actor to a door only through
		# a continuous clear walking corridor, never across a car or furniture.
		var paths: Array[PackedVector3Array] = [PackedVector3Array([point])]
		var routed: PackedVector3Array = world.gameplay.find_path(checkpoint,point)
		if not routed.is_empty():
			routed.append(point)
			paths.append(routed)
		var reachable := false
		for path in paths:
			var from := checkpoint
			var clear := true
			for destination in path:
				if not position_clear(destination): clear = false; break
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.collision_mask = 7
				query.exclude = [world.player.get_rid()]
				query.transform = Transform3D(Basis.IDENTITY,from+Vector3.UP*.9)
				query.motion = destination-from
				var sweep: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
				if sweep[0] < 1.0: clear = false; break
				var steps := maxi(1,ceili(from.distance_to(destination)/.5))
				for step in range(1,steps):
					if not position_clear(from.lerp(destination,float(step)/steps)): clear = false; break
				if not clear: break
				from = destination
			if clear: reachable = true; break
		if not reachable: continue
		world.player.teleport(point)
		var entry: Dictionary = world.driving._entry_option(true)
		# Driving.car still names the previous controlled vehicle until the entry
		# actually begins. Validate the physically selected candidate instead.
		if entry.get("car") == car and world.driving.interact(true):
			world.camera.target = car if place.is_empty() else anchor
			world.camera.locked = not place.is_empty()
			state.set_location(state.region_id,place)
			_sync_location_presentation()
			# Release only the session gate while the existing body/door presentation
			# owns input. Otherwise Driving sees our gate as an interruption and aborts
			# the entry on its first frame.
			_finish_transition(token)
			for frame in 180:
				if not world.driving.is_body_transition_active(): break
				await get_tree().physics_frame
				if not is_instance_valid(car) or car.health <= 0 or state.place_id != place or room != expected_room or world.gameplay.health <= 0:
					world.driving.cancel_transition("garage_restore_invalidated")
					_restore_vehicle_transition_snapshot(snapshot,car if is_instance_valid(car) else null)
					return false
			if world.driving.is_body_transition_active():
				world.driving.cancel_transition("garage_restore_timeout")
				_restore_vehicle_transition_snapshot(snapshot,car)
				return false
			if not world.driving.occupied or world.driving.car != car:
				_restore_vehicle_transition_snapshot(snapshot,car)
				return false
			car.input_locked = bool(snapshot.car_locked)
			return true
		world.player.teleport(checkpoint)
	world.player.teleport(checkpoint)
	world.driving.car = previous_car
	_restore_vehicle_transition_snapshot(snapshot,car)
	_finish_transition(token)
	return false

func _garage_restore_spawn(place: String, preferred: Vector3, candidate_room: Node3D = null) -> Vector3:
	if place not in ["maciota","port_boss_garage"] or garage_rewards == null: return preferred
	if candidate_room == null: candidate_room = room
	if not is_instance_valid(candidate_room): return Vector3.INF
	var records: Dictionary = garage_rewards.data.get("vehicles",{})
	if records.is_empty(): return preferred
	var origin: Vector3 = candidate_room.to_global(candidate_room.interior_origin) if place == "maciota" else candidate_room.global_position
	var reservations: Array[Dictionary] = []
	for record in records.values():
		if record.get("place_id","") != place or record.get("region_id","") != state.region_id: continue
		var specification: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(str(record.archetype))
		if specification.is_empty(): continue
		var size: Array = specification.bounds_size
		var point := origin+Vector3(record.position[0],record.position[1],record.position[2])
		reservations.append({"point":point,"inverse":Basis(Vector3.UP,float(record.yaw)).inverse(),"half":Vector2(maxf(.65,size[0])*.5+.4,float(size[2])*.5+.4),"height":clampf(size[1],1.1,3.6)})
	if reservations.is_empty(): return preferred
	var candidates: Array[Vector3] = [preferred,candidate_room.exit_position]
	for center: Vector3 in [candidate_room.exit_position,preferred]:
		for radius in [1.2,2.4,3.6]:
			for offset in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]: candidates.append(center+offset*radius)
	var bounds: Rect2
	if place == "maciota":
		bounds = Rect2(candidate_room.room_bounds.position.x,candidate_room.room_bounds.position.z,candidate_room.room_bounds.size.x,candidate_room.room_bounds.size.z)
	else:
		var size: Vector2 = candidate_room.definition.size
		bounds = Rect2(-size*.5,size)
	for candidate in candidates:
		var local := candidate-origin
		if not bounds.grow(-.34).has_point(Vector2(local.x,local.z)): continue
		if not position_clear(candidate+Vector3.UP*.04): continue
		var reserved := false
		for reservation in reservations:
			var relative: Vector3 = reservation.inverse*(candidate-reservation.point)
			if absf(relative.x) <= reservation.half.x and absf(relative.z) <= reservation.half.y and relative.y < reservation.height and relative.y+1.8 > 0:
				reserved = true
				break
		if not reserved: return candidate
	return Vector3.INF

## Spans por subsistema no _ready (auditoria de 16/10): o _ready inteiro levava ~13 s num
## quadro só no carregamento, sem nada medido dentro; o span diz qual filho custa.
func _timed_add(parent: Node, child: Node, label: String) -> void:
	var started := STALL_WORK_READY.begin()
	parent.add_child(child)
	STALL_WORK_READY.finish("session.ready." + label, started, {})

func _startup_frame() -> void:
	if not incremental_startup: return
	# Sob a cortina, fatias maiores (runtime/LoadingTurbo.gd; GETECO_LOADING_TURBO=0 volta a 4 ms).
	if Time.get_ticks_usec() - _startup_slice_usec < preload("res://runtime/LoadingTurbo.gd").budget(4000.0): return
	await get_tree().process_frame
	_startup_slice_usec = Time.get_ticks_usec()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Input and session updates cannot observe a half-constructed session.
	set_process(false)
	set_process_input(false)
	_startup_slice_usec = Time.get_ticks_usec()
	state = controller.state
	door_transition = DOOR_TRANSITION.new()
	await _startup_frame()
	_timed_add(self, door_transition, "door_transition")
	weapon_shop_entrance = preload("res://runtime/WeaponShopEntrance.gd").new()
	weapon_shop_entrance.session = self
	await _startup_frame()
	_timed_add(self, weapon_shop_entrance, "weapon_shop_entrance")
	special_place_entrance = preload("res://runtime/SpecialPlaceEntrance.gd").new()
	special_place_entrance.session = self
	await _startup_frame()
	_timed_add(self, special_place_entrance, "special_place_entrance")
	building_entrance = preload("res://runtime/HarborBuildingRuntime.gd").new()
	building_entrance.session = self
	await _startup_frame()
	_timed_add(self, building_entrance, "building_entrance")
	building_social = preload("res://runtime/BuildingSocialInteraction.gd").new()
	building_social.session = self
	await _startup_frame()
	_timed_add(self, building_social, "building_social")
	service_roofs = preload("res://runtime/HarborServiceRoofRuntime.gd").new()
	service_roofs.session = self
	await _startup_frame()
	_timed_add(self, service_roofs, "service_roofs")
	if not Engine.get_meta("coastal_lookout_baseline",false):
		coastal_lookout = preload("res://runtime/coastal_lookout/CoastalLookoutRuntime.gd").new()
		coastal_lookout.configure(world)
		await _startup_frame()
		_timed_add(self, coastal_lookout, "coastal_lookout")
	if not Engine.get_meta("amusement_park_baseline",false):
		var diagnostic_amusement_park := SESSION_OPS.begin(self, "amusement_park", "create_and_configure")
		amusement_park = preload("res://runtime/amusement_park/AmusementParkRuntime.gd").new()
		amusement_park.configure(self)
		SESSION_OPS.finish(diagnostic_amusement_park)
		await _startup_frame()
		_timed_add(self, amusement_park, "amusement_park")
	anchor = Node3D.new()
	await _startup_frame()
	_timed_add(world, anchor, "anchor")
	objective = _label(Vector2(530,24),20)
	objective.custom_minimum_size.x = 700
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats = _label(Vector2(26,64),18)
	thermal_status = _label(Vector2(26,120),18)
	thermal_status.add_theme_color_override("font_outline_color",Color(0.02,0.04,0.06))
	thermal_status.add_theme_constant_override("outline_size",4)
	thermal_status.hide()
	prompt = _label(Vector2(26,590),20)
	notice = _label(Vector2(26,550),18)
	# Message source only; ContextualHUDManager owns the visible notification.
	notice.hide()
	marker = preload("res://ui/DoorAccessMarker.gd").new()
	await _startup_frame()
	_timed_add(world.hud, marker, "marker")
	arrow = _label(Vector2.ZERO,30)
	arrow.text = "▲"
	arrow.modulate = Color("f39a38")
	arrow.pivot_offset = Vector2(12,20)
	# World-anchored HUD must follow the final camera every rendered frame,
	# not the 10 Hz text refresh (which made the orange marker jump).
	marker.update_position = _update_world_indicator
	panel = PanelContainer.new()
	panel.position = Vector2(330,110)
	panel.custom_minimum_size = Vector2(620,440)
	await _startup_frame()
	_timed_add(world.hud, panel, "panel")
	var margin := MarginContainer.new()
	for side in ["top","left","right","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580,400)
	margin.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",10)
	scroll.add_child(column)
	panel.hide()
	world.gameplay.message.connect(show_message)
	world.gameplay.player_died.connect(_on_death)
	world.gameplay.player_arrested.connect(_on_arrest)
	world.gameplay.police_warning_issued.connect(_police_voice_warning)
	mission_world = preload("res://runtime/MissionWorld.gd").new()
	mission_world.session = self
	await _startup_frame()
	_timed_add(world, mission_world, "mission_world")
	var diagnostic_activities := SESSION_OPS.begin(self, "activities", "create_and_configure")
	activities = preload("res://activities/Activities.gd").new()
	await _startup_frame()
	_timed_add(world, activities, "activities")
	activities.configure(self)
	SESSION_OPS.finish(diagnostic_activities)
	var diagnostic_motocross := SESSION_OPS.begin(self, "motocross", "create_and_configure")
	motocross = preload("res://activities/motocross/Motocross.gd").new()
	await _startup_frame()
	_timed_add(world, motocross, "motocross")
	motocross.configure(self)
	SESSION_OPS.finish(diagnostic_motocross)
	var diagnostic_skate := SESSION_OPS.begin(self, "skate", "create_and_configure")
	skate = preload("res://activities/skate/Skate.gd").new()
	await _startup_frame()
	_timed_add(world, skate, "skate")
	skate.configure(self)
	SESSION_OPS.finish(diagnostic_skate)
	var diagnostic_residence_services := SESSION_OPS.begin(self, "residence_services", "create_and_configure")
	residence_services = preload("res://runtime/ResidenceServices.gd").new()
	await _startup_frame()
	_timed_add(world, residence_services, "residence_services")
	residence_services.configure(self)
	SESSION_OPS.finish(diagnostic_residence_services)
	if not Engine.get_meta("cats_baseline",false):
		var diagnostic_cats := SESSION_OPS.begin(self, "cats", "create_and_configure")
		cats = preload("res://runtime/cats/CatRuntime.gd").new()
		await _startup_frame()
		_timed_add(world, cats, "cats")
		cats.configure(self)
		SESSION_OPS.finish(diagnostic_cats)
	var diagnostic_mountain_progression := SESSION_OPS.begin(self, "mountain_progression", "create_and_configure")
	mountain_progression = preload("res://activities/MountainProgression.gd").new()
	await _startup_frame()
	_timed_add(world, mountain_progression, "mountain_progression")
	mountain_progression.configure(self)
	SESSION_OPS.finish(diagnostic_mountain_progression)
	world.player.ski_controller = mountain_progression
	var diagnostic_mountain_activities := SESSION_OPS.begin(self, "mountain_activities", "create_and_configure")
	mountain_activities = preload("res://runtime/MountainActivities.gd").new()
	await _startup_frame()
	_timed_add(world, mountain_activities, "mountain_activities")
	mountain_activities.configure(self)
	SESSION_OPS.finish(diagnostic_mountain_activities)
	var diagnostic_services := SESSION_OPS.begin(self, "services", "create_and_configure")
	services = preload("res://runtime/Services.gd").new()
	await _startup_frame()
	_timed_add(world, services, "services")
	services.configure(self)
	SESSION_OPS.finish(diagnostic_services)
	if state.world_state.has("services") and not services.restore_snapshot(state.world_state.services): controller.block_saving("serviços não restauraram")
	var diagnostic_storefronts := SESSION_OPS.begin(self, "storefronts", "create_and_configure")
	storefronts = preload("res://runtime/HarborStorefronts.gd").new()
	await _startup_frame()
	_timed_add(world.hud, storefronts, "storefronts")
	storefronts.configure(self)
	SESSION_OPS.finish(diagnostic_storefronts)
	if not Engine.get_meta("curitiba_cellar_baseline",false):
		var diagnostic_wine := SESSION_OPS.begin(self, "wine", "create_and_configure")
		wine = preload("res://gameplay/wine/WineRuntime.gd").new()
		await _startup_frame()
		_timed_add(world, wine, "wine")
		wine.configure(self)
		SESSION_OPS.finish(diagnostic_wine)
	if not Engine.get_meta("upside_world_baseline",false):
		var diagnostic_upside_world := SESSION_OPS.begin(self, "upside_world", "create_and_configure")
		upside_world = preload("res://runtime/upside_world/UpsideWorldRuntime.gd").new()
		upside_world.configure(self)
		SESSION_OPS.finish(diagnostic_upside_world)
		await _startup_frame()
		_timed_add(self, upside_world, "upside_world")
	if not Engine.get_meta("arcade_baseline",false):
		var diagnostic_arcade := SESSION_OPS.begin(self, "arcade", "create_and_configure")
		arcade = preload("res://activities/arcade/ArcadeRuntime.gd").new()
		await _startup_frame()
		_timed_add(world, arcade, "arcade")
		arcade.configure(self)
		SESSION_OPS.finish(diagnostic_arcade)
	var diagnostic_robberies := SESSION_OPS.begin(self, "robberies", "create_and_configure")
	robberies = preload("res://runtime/Robberies.gd").new()
	if state.world_state.has("robberies") and not robberies.restore_snapshot(state.world_state.robberies): controller.block_saving("assaltos não restauraram")
	await _startup_frame()
	_timed_add(world, robberies, "robberies")
	robberies.configure(self)
	SESSION_OPS.finish(diagnostic_robberies)
	var diagnostic_arrival := SESSION_OPS.begin(self, "arrival", "create_and_configure")
	arrival = preload("res://runtime/Arrival.gd").new()
	arrival.configure(self)
	SESSION_OPS.finish(diagnostic_arrival)
	if state.world_state.has("arrival") and not arrival.restore_state(state.world_state.arrival): controller.block_saving("chegada não restaurou")
	await _startup_frame()
	_timed_add(world, arrival, "arrival")
	arrival.changed.connect(save_game)
	var diagnostic_garage_rewards := SESSION_OPS.begin(self, "garage_rewards", "create_and_configure")
	garage_rewards = preload("res://runtime/GarageRewards.gd").new()
	if state.world_state.has("garage_rewards") and not garage_rewards.restore_snapshot(state.world_state.garage_rewards): controller.block_saving("prêmios da garagem não restauraram")
	await _startup_frame()
	_timed_add(world, garage_rewards, "garage_rewards")
	garage_rewards.configure(self)
	SESSION_OPS.finish(diagnostic_garage_rewards)
	var diagnostic_police_motor_pool := SESSION_OPS.begin(self, "police_motor_pool", "create_and_configure")
	police_motor_pool = preload("res://runtime/PoliceMotorPool.gd").new()
	await _startup_frame()
	_timed_add(world, police_motor_pool, "police_motor_pool")
	police_motor_pool.configure(self)
	SESSION_OPS.finish(diagnostic_police_motor_pool)
	var diagnostic_personal_car := SESSION_OPS.begin(self, "personal_car", "create_and_configure")
	personal_car = preload("res://runtime/PersonalCar.gd").new()
	await _startup_frame()
	_timed_add(world, personal_car, "personal_car")
	personal_car.configure(self)
	SESSION_OPS.finish(diagnostic_personal_car)
	var diagnostic_jessica := SESSION_OPS.begin(self, "jessica", "create_and_configure")
	jessica = preload("res://runtime/JessicaRuntime.gd").new()
	await _startup_frame()
	_timed_add(world, jessica, "jessica")
	jessica.configure(self)
	SESSION_OPS.finish(diagnostic_jessica)
	var diagnostic_helena_act1 := SESSION_OPS.begin(self, "helena_act1", "create_and_configure")
	helena_act1 = preload("res://runtime/harbor_act1/HelenaAct1.gd").new()
	_timed_add(world, helena_act1, "helena_act1")
	helena_act1.configure(self)
	SESSION_OPS.finish(diagnostic_helena_act1)
	var diagnostic_desert := SESSION_OPS.begin(self, "desert", "create_and_configure")
	desert = preload("res://runtime/desert/DesertRuntime.gd").new()
	await _startup_frame()
	_timed_add(world, desert, "desert")
	desert.configure(self)
	SESSION_OPS.finish(diagnostic_desert)
	var diagnostic_maciota_workshop := SESSION_OPS.begin(self, "maciota_workshop", "create_and_configure")
	maciota_workshop = preload("res://runtime/MaciotaWorkshop.gd").new()
	await _startup_frame()
	_timed_add(world, maciota_workshop, "maciota_workshop")
	maciota_workshop.configure(self)
	SESSION_OPS.finish(diagnostic_maciota_workshop)
	var diagnostic_mining := SESSION_OPS.begin(self, "mining", "create_and_configure")
	mining = preload("res://runtime/MiningRuntime.gd").new()
	await _startup_frame()
	_timed_add(world, mining, "mining")
	mining.configure(self)
	SESSION_OPS.finish(diagnostic_mining)
	dialogue_voice = AudioStreamPlayer.new()
	dialogue_voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	dialogue_voice.bus = &"Dialogue" if AudioServer.get_bus_index("Dialogue") >= 0 else &"Master"
	await _startup_frame()
	_timed_add(self, dialogue_voice, "dialogue_voice")
	speech_voice = AudioStreamPlayer.new()
	speech_voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	speech_voice.bus = dialogue_voice.bus
	await _startup_frame()
	_timed_add(self, speech_voice, "speech_voice")
	var voice_settings := get_node_or_null("/root/V2Settings")
	if voice_settings != null:
		voice_settings.voice_language_changed.connect(func(_value): _refresh_voice_presentation(true))
		voice_settings.text_language_changed.connect(func(_value): _refresh_voice_presentation(false))
	var diagnostic_passenger_transport := SESSION_OPS.begin(self, "passenger_transport", "create_and_configure")
	passenger_transport = preload("res://runtime/PassengerTransport.gd").new()
	passenger_transport.configure(self)
	SESSION_OPS.finish(diagnostic_passenger_transport)
	await _startup_frame()
	_timed_add(world, passenger_transport, "passenger_transport")
	var diagnostic_urban_operations := SESSION_OPS.begin(self, "urban_operations", "create_and_configure")
	urban_operations = preload("res://gameplay/urban_v1/UrbanOperations.gd").new()
	urban_operations.configure(self)
	SESSION_OPS.finish(diagnostic_urban_operations)
	await _startup_frame()
	_timed_add(world, urban_operations, "urban_operations")
	if state.world_state.has("urban_operations") and not urban_operations.restore_snapshot(state.world_state.urban_operations): controller.block_saving("porto e cemitério não restauraram")
	var diagnostic_port_container_loot := SESSION_OPS.begin(self, "port_container_loot", "create_and_configure")
	port_container_loot = preload("res://gameplay/urban_v1/PortContainerLoot.gd").new()
	port_container_loot.configure(self)
	SESSION_OPS.finish(diagnostic_port_container_loot)
	await _startup_frame()
	_timed_add(world, port_container_loot, "port_container_loot")
	var diagnostic_armored_transport := SESSION_OPS.begin(self, "armored_transport", "create_and_configure")
	armored_transport = preload("res://gameplay/armored/ArmoredTransport.gd").new()
	armored_transport.configure(self)
	SESSION_OPS.finish(diagnostic_armored_transport)
	await _startup_frame()
	_timed_add(world, armored_transport, "armored_transport")
	var diagnostic_field_inventory := SESSION_OPS.begin(self, "field_inventory", "create_and_configure")
	field_inventory = preload("res://systems/inventory/FieldInventoryRuntime.gd").new()
	await _startup_frame()
	_timed_add(world, field_inventory, "field_inventory")
	field_inventory.configure(self)
	SESSION_OPS.finish(diagnostic_field_inventory)
	equipment_wheel = preload("res://runtime/EquipmentWheel.gd").new()
	world.add_child(equipment_wheel)
	equipment_wheel.configure(self)
	if not Engine.get_meta("fishing_baseline",false):
		var diagnostic_fishing := SESSION_OPS.begin(self, "fishing", "create_and_configure")
		fishing = preload("res://activities/fishing/Fishing.gd").new()
		await _startup_frame()
		_timed_add(world, fishing, "fishing")
		fishing.configure(self)
		SESSION_OPS.finish(diagnostic_fishing)
		fishing_runtime = preload("res://runtime/FishingRuntime.gd").new()
		fishing_runtime.session = self
		await _startup_frame()
		_timed_add(self, fishing_runtime, "fishing_runtime")
	if not world.get_meta("skip_cold",false):
		var diagnostic_cold := SESSION_OPS.begin(self, "cold", "create_and_configure")
		cold = preload("res://runtime/ColdSurvival.gd").new()
		cold.configure(self)
		SESSION_OPS.finish(diagnostic_cold)
		if state.world_state.has("cold") and not cold.restore(state.world_state.cold): controller.block_saving("frio da serra não restaurou")
		await _startup_frame()
		_timed_add(world, cold, "cold")
	if "--railway-baseline" not in OS.get_cmdline_user_args():
		railway_world = preload("res://world/railway/RailwayWorld.gd").new()
		railway_world.configure(controller)
		await _startup_frame()
		_timed_add(world, railway_world, "railway_world")
		var diagnostic_railway := SESSION_OPS.begin(self, "railway", "create_and_configure")
		railway = preload("res://runtime/railway/RailwayTransit.gd").new()
		railway.name = "RailwayTransit"
		railway.configure(self)
		SESSION_OPS.finish(diagnostic_railway)
		await _startup_frame()
		_timed_add(world, railway, "railway")
		var railway_ui := preload("res://ui/railway/RailwayUI.gd").new()
		await _startup_frame()
		_timed_add(world, railway_ui, "railway_ui")
		railway_ui.configure(railway)
	var diagnostic_regional_coach := SESSION_OPS.begin(self, "regional_coach", "create_and_configure")
	regional_coach = preload("res://runtime/regional/RegionalCoachTransit.gd").new()
	regional_coach.name = "RegionalCoachTransit"
	regional_coach.configure(self)
	SESSION_OPS.finish(diagnostic_regional_coach)
	await _startup_frame()
	_timed_add(world, regional_coach, "regional_coach")
	var coach_ui := preload("res://ui/railway/RailwayUI.gd").new()
	await _startup_frame()
	_timed_add(world, coach_ui, "coach_ui")
	coach_ui.name = "RegionalCoachUI"
	coach_ui.configure(regional_coach)
	startup_complete = true
	set_process(true)
	set_process_input(true)
	startup_finished.emit()

func _label(point: Vector2,size_value: int) -> Label:
	var result := Label.new()
	result.position = point
	result.add_theme_font_size_override("font_size",size_value)
	result.add_theme_color_override("font_shadow_color",Color.BLACK)
	result.add_theme_constant_override("shadow_offset_y",2)
	world.hud.add_child(result)
	return result

func show_message(text: String) -> void:
	if not is_instance_valid(notice): return
	var spoken := preload("res://audio/AuthoredSpeech.gd").notice(text)
	if not spoken.is_empty():
		show_speech(spoken.speaker, spoken.message, 5.0, true, spoken.persona, spoken.voice_text, str(spoken.get("character_id", "")), str(spoken.get("section", "")))
		return
	clear_speech()
	_reward_notice_id = ""
	notice.text = text
	notice_time = 5.0

func _police_voice_warning() -> void:
	var actor: Node3D = world.gameplay.last_warning_actor.get_ref() if world.gameplay.last_warning_actor != null else null
	var binding := preload("res://audio/VoiceActorBinding.gd").resolve(actor, "polícia", "spoken_notice:runtime/FullSession.gd")
	var source := "POLÍCIA: Pare e fique imóvel para se render!".trim_prefix("POLÍCIA: ")
	if binding.is_empty():
		show_speech("POLÍCIA", tr(source), 5.0, false)
		return
	var shown := preload("res://audio/ActorDialogueVoice.gd").speak(actor, source, binding)
	show_speech("POLÍCIA", str(shown.message), maxf(5.0, float(shown.duration) + .6), false,
		str(binding.persona), source, str(binding.character_id), str(binding.get("section", "")))

func show_speech(speaker: String, message: String, duration := 5.0, play_voice := true, persona := "", voice_text := "", character_id := "", section := "") -> void:
	if not is_instance_valid(notice): return
	clear_speech()
	if not is_instance_valid(speech_caption):
		speech_caption = DIALOGUE_CAPTION.new()
		world.hud.add_child(speech_caption)
	_reward_notice_id = ""
	var actor := persona if not persona.is_empty() else speaker.to_lower().split(" · ")[0]
	var shown: Dictionary = {}
	if play_voice or not voice_text.is_empty():
		_speech_source = {"speaker":speaker, "message":message, "persona":actor, "source":voice_text if not voice_text.is_empty() else message,
			"character_id":character_id, "section":section, "play_voice":play_voice}
		shown = VOICE.presentation(str(_speech_source.source), actor, "", "", character_id, section)
		message = str(shown.message)
	notice.text = speaker + ": " + message
	notice_time = duration
	speech_active = true
	speech_caption.set_line(speaker, message)
	speech_caption.visible = not get_tree().paused and not (is_instance_valid(equipment_wheel) and equipment_wheel.active)
	if play_voice and is_instance_valid(speech_voice):
		speech_voice.stream = shown.get("stream") as AudioStream
		speech_voice.volume_db = VOICE.playback_volume(speech_voice.stream, -8.0 if actor in ["maciota", "caller"] else 0.0)
		if speech_voice.stream != null:
			notice_time = maxf(notice_time, speech_voice.stream.get_length()+.6)
			speech_voice.play()

func clear_speech() -> void:
	if is_instance_valid(speech_voice): speech_voice.stop()
	if is_instance_valid(speech_caption): speech_caption.hide()
	if speech_active: notice_time = 0.0
	speech_active = false
	_speech_source.clear()

func _refresh_voice_presentation(restart_audio: bool) -> void:
	if dialogue_open and not _dialogue_source.is_empty():
		_present_current_dialogue(restart_audio)
	if speech_active and not _speech_source.is_empty():
		var source := _speech_source
		var shown := VOICE.presentation(str(source.source), str(source.persona), "", "", str(source.character_id), str(source.section))
		notice.text = str(source.speaker) + ": " + str(shown.message)
		speech_caption.set_line(str(source.speaker), str(shown.message))
		if restart_audio: notice_time = maxf(notice_time, float(shown.duration) + .6)
		if restart_audio and source.play_voice and speech_voice.playing:
			speech_voice.stop()
			speech_voice.stream = shown.stream
			speech_voice.volume_db = VOICE.playback_volume(speech_voice.stream, -8.0 if source.persona in ["maciota", "caller"] else 0.0)
			if speech_voice.stream != null:
				notice_time = maxf(notice_time, speech_voice.stream.get_length() + .6)
				speech_voice.play()

func position_clear(point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.7
	query.shape = shape
	query.collision_mask = 7
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.9)
	query.exclude = [world.player.get_rid()]
	if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	var ground := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.5,1)
	return not world.get_world_3d().direct_space_state.intersect_ray(ground).is_empty()

func restore_location() -> void:
	var restore_blocked := false
	var place: String = state.place_id
	state.place_id = ""
	var definition := PLACES.get_definition(place)
	var previous_roof: Dictionary = state.world_state.get("harbor_service_roof",{})
	if not previous_roof.is_empty() and preload("res://world/editing/WorldServiceBuildings.gd").is_deleted(str(previous_roof.get("id",""))):
		definition = PLACES.get_definition(str(previous_roof.id))
	var removed_place: bool = bool(definition.get("editor_deleted",false))
	if removed_place: state.world_state.erase("harbor_service_roof")
	var place_matches_region: bool = place == "maciota" and state.region_id == "harbor"
	if not definition.is_empty(): place_matches_region = definition.get("region","") == state.region_id and not removed_place
	if place_matches_region:
		if not await enter_place(place,false): restore_blocked = true
	else:
		# Só o local se perde: Dante volta pelo ponto de retorno e o resto do save continua
		# gravável (antes isto desligava o salvamento pelo resto da sessão).
		if not place.is_empty():
			show_message("Local salvo incompatível com a região; retomada pelo ponto de retorno.")
		var point: Vector3 = world.maciota_place.exterior_return if state.region_id == "harbor" else controller.region.spawn_position
		for entry in controller.region.entries:
			if entry.id == state.checkpoint_id: point = entry.return_position
		if removed_place and definition.get("region","") == state.region_id: point = definition.return_position
		var fallback: Vector3 = point
		var pedestrian: Dictionary = state.world_state.get("pedestrian",{})
		if not removed_place and pedestrian.get("region","") == state.region_id:
			var coordinates: Array = pedestrian.position
			point = Vector3(coordinates[0],coordinates[1],coordinates[2])-Vector3.UP*.08
			if state.region_id == "harbor":
				point = preload("res://world/railway/RailwayNetwork.gd").restore_harbor_pedestrian(point+Vector3.UP*.08)-Vector3.UP*.08
		var saved_roof: Dictionary = state.world_state.get("harbor_service_roof",{})
		if not removed_place and not saved_roof.is_empty() and str(saved_roof.get("place","")) == "":
			var roof_return: Array = saved_roof["return"]
			point = Vector3(roof_return[0],roof_return[1],roof_return[2])-Vector3.UP*.08
		var seated: Dictionary = _saved_garage_driver()
		if not seated.is_empty():
			var size: Array = preload("res://runtime/FleetCatalog.gd").spec(seated.archetype).bounds_size
			var parked := Vector3(seated.position[0],seated.position[1],seated.position[2])
			point = parked+Basis(Vector3.UP,float(seated.yaw))*Vector3(maxf(.65,float(size[0]))*.5+.65,0,.15)
		if state.region_id=="desert": point=preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").restore_point(point,state.world_state)
		controller.region.set_focus(point)
		if cold != null: cold.prepare_collision_at(point)
		for i in 3: await get_tree().physics_frame
		if position_clear(point+Vector3.UP*.08): world.player.teleport(point+Vector3.UP*.08)
		else:
			controller.region.set_focus(fallback)
			if cold != null: cold.prepare_collision_at(fallback)
			for i in 3: await get_tree().physics_frame
			if position_clear(fallback+Vector3.UP*.08):
				world.player.teleport(fallback+Vector3.UP*.08)
				show_message("Local salvo ocupado. Retomada pelo ponto de retorno.")
			else: restore_blocked = true
	if not state.combat_state.is_empty(): world.gameplay.restore_state(state.combat_state)
	if state.world_state.has("mission_world"):
		if not mission_world.restore_snapshot(state.world_state.mission_world):
			controller.block_saving("guincho não restaurou")
			show_message("Não foi possível restaurar o guincho; save preservado.")
	elif state.campaign.active_id == "cobra_contact":
		mission_world.begin_tow_job({"story":true,"kind":"local"})
	await _restore_outdoor_driver()
	if desert != null and desert.get("workshop_drive") != null:
		if not await desert.workshop_drive.restore_saved_driver():
			controller.block_saving("carro da oficina do Digo não restaurou")
			show_message("Não foi possível restaurar o carro da oficina; save preservado.")
	if service_roofs != null and not await service_roofs.restore_saved(): restore_blocked = true
	ready_for_play = true
	if personal_car != null: personal_car.refresh()
	if activities != null: activities.refresh_achievements()
	garage_rewards.on_location_changed()
	apply_outfit()
	_refresh_routine_context()
	# O menu acabou de recuperar este slot (SessionLaunch._publish_recovery): diga o que voltou ao padrão.
	var launch := get_node_or_null("/root/V2Launch")
	var load_notices: Array[String] = []
	var recovery_text: Variant = launch.get("recovery_notice") if launch != null else null
	if recovery_text is String and not recovery_text.is_empty():
		load_notices.append(recovery_text)
		launch.recovery_notice = ""
	# Save de antes do bônus de missão (EconomyBalance.STORY_BONUS): paga uma vez o que faltou.
	var back_pay: int = STORY_PAY.settle(state.campaign.snapshot(), state.economy)
	if back_pay > 0:
		load_notices.append(String(TranslationServer.translate("Bônus das missões já concluídas: + R$ %d")) % back_pay)
		world.gameplay.changed.emit()
	if not load_notices.is_empty(): show_message(" · ".join(load_notices))
	if world.gameplay.health <= 0 or restore_blocked: _on_death()

func _saved_garage_driver() -> Dictionary:
	if garage_rewards == null or not state.place_id.is_empty(): return {}
	for record in garage_rewards.data.get("vehicles",{}).values():
		if record.get("was_driven",false) and record.region_id == state.region_id and record.place_id.is_empty(): return record
	return {}

func _restore_outdoor_driver() -> void:
	# A seated save resumes at the saved car, not at a remote pedestrian checkpoint.
	if not state.place_id.is_empty() or world.gameplay.health <= 0: return
	var saved: Dictionary = controller.starting_vehicle()
	if saved.is_empty() or not saved.get("was_driven",false) or saved.region != state.region_id: return
	var car: CharacterBody3D = world.driving.car
	var destination := Vector3(saved.position[0],saved.position[1],saved.position[2])
	var checkpoint: Vector3 = world.player.position
	controller.region.set_focus(destination)
	if cold != null: cold.prepare_collision_at(destination)
	for i in 3: await get_tree().physics_frame
	if not controller.vehicle_position_clear(car,destination,float(saved.yaw)):
		if _restore_saved_driver_on_foot(saved): return
		controller.region.set_focus(checkpoint)
		return
	car.place(destination,float(saved.yaw))
	car.remove_meta("awaiting_ground")
	car.set_physics_process(true)
	for side in [-1,1]:
		var door := car.to_global(Vector3(side*(car.half_width+.65),.05,.15))
		if car.boarding_class() in ["truck", "bus"]:
			door = car.driver_door_anchor(side) + car.global_basis.x * float(side) * .11 + Vector3.UP * .01
		if not position_clear(door): continue
		world.player.teleport(door)
		# The saved driver is admitted before ready_for_play. Keep normal input
		# gated, but allow its already-owned body animation to finish under the curtain.
		_restoring_saved_driver = true
		var restored := await restore_garage_driver(car)
		_restoring_saved_driver = false
		if restored: return
	if _restore_saved_driver_on_foot(saved): return
	world.player.teleport(checkpoint)
	controller.region.set_focus(checkpoint)

func _restore_saved_driver_on_foot(saved: Dictionary) -> bool:
	# A blocked hull/door must not send a seated save to a distant checkpoint.
	# Probe the actual capsule and floor around the saved pose, including legacy
	# saves without a pedestrian record. Keep normal boarding admission intact.
	var size: Array = preload("res://runtime/FleetCatalog.gd").spec(saved.archetype).bounds_size
	var half_width := maxf(.65,float(size[0]))*.5
	var half_length := maxf(1.0,float(size[2]))*.5
	var origin := Vector3(saved.position[0],saved.position[1],saved.position[2])
	var basis := Basis(Vector3.UP,float(saved.yaw))
	for side in [-1,1]:
		for longitudinal in [0.0,half_length+.6,-half_length-.6]:
			var point: Vector3 = origin+basis*Vector3(side*(half_width+.85),.08,longitudinal)
			if not position_clear(point): continue
			world.player.teleport(point)
			controller.region.set_focus(point)
			world.camera.initialized = false
			show_message("Veículo salvo bloqueado. Retomada a pé nas proximidades.")
			return true
	return false

func enter_place(id: String, autosave := true, requested_access_id := "") -> bool:
	if is_transition_blocked() or world.driving.occupied or not state.place_id.is_empty() or is_instance_valid(room) or world.player.input_locked: return false
	if world.player.get_meta("player_air_busy",false): return false
	if not preload("res://runtime/ShopSafety.gd").admission_allowed(id, world.gameplay.stars):
		show_message("Perca a polícia antes de entrar.")
		return false
	var definition := PLACES.get_definition(id)
	if definition.get("editor_deleted",false): return false
	if id == "maciota":
		if state.region_id != "harbor": return false
	elif definition.is_empty() or (definition.get("region","") != state.region_id and not definition.get("any_region",false)):
		show_message("Este acesso não pertence à região atual.")
		return false
	if autosave and garage_rewards != null and not garage_rewards.can_enter(id):
		show_message("A garagem abre entre 1h e 5h.")
		return false
	if id == "harbor_bank" and not robberies.can_enter_bank():
		show_message("O banco está fechado para investigação.")
		return false
	if id == "cobra_leader_house" and not state.campaign.has_progress("cobra_finale") and not (state.campaign.active_id == "cobra_finale" and state.campaign.step>=6):
		show_message("Takeshi ainda não liberou o acesso à casa.")
		return false
	if activities != null and not activities.can_enter_home(id):
		show_message("Esta casa ainda não é sua.")
		return false
	var token := _begin_transition("enter_place")
	if token < 0: return false
	var origin_region: String = state.region_id
	var origin_room: Node3D = room
	var was_player_locked: bool = world.player.input_locked
	var local_access_id: String = requested_access_id
	world.player.input_locked = true
	var destination: Vector3
	var candidate_room: Node3D
	var owns_candidate := false
	var candidate_return := Vector3.ZERO
	if SEWER_NETWORK.is_manhole(id):
		sewer_hatch = _find_sewer_hatch(id)
		sewer_entry_origin = world.player.global_position
	if id == "maciota":
		candidate_room = world.maciota_place
		candidate_return = candidate_room.exterior_return
		destination = candidate_room.interior_spawn
		candidate_room.set_interior_active(true)
	else:
		var embedded_building: bool = building_entrance != null and building_entrance.handles_place(id)
		candidate_room = await building_entrance.prepare_room(id,autosave) if embedded_building else PLACES.create_place(id)
		if candidate_room == null:
			if SEWER_NETWORK.is_manhole(id) and sewer_entry_origin.is_finite():
				world.player.teleport(sewer_entry_origin)
				_close_sewer_hatch_for_transition(token)
				sewer_entry_origin = Vector3.ZERO
			_restore_transition_player_lock(was_player_locked,token)
			_finish_transition(token)
			return false
		owns_candidate = true
		if not embedded_building:
			if candidate_room.has_method("prepare_session"): candidate_room.prepare_session(self,autosave)
			candidate_room.position = Vector3(0,0,-2400)
			world.add_child(candidate_room)
		candidate_return = candidate_room.definition.return_position
		for entry in controller.region.entries:
			if entry.id == local_access_id: candidate_return = entry.return_position
		destination = candidate_room.spawn_position
		if embedded_building and building_entrance.walking_admission:
			destination = world.player.global_position-Vector3.UP*.04
	load("res://world/editing/WorldInteriorEdits.gd").apply_saved(candidate_room,id)
	controller.region.set_focus(candidate_return)
	for i in 2:
		await get_tree().physics_frame
		if not _owns_transition(token) or state.region_id != origin_region or not state.place_id.is_empty() or room != origin_room or world.driving.occupied or world.gameplay.health <= 0 or not is_instance_valid(candidate_room) or not preload("res://runtime/ShopSafety.gd").admission_allowed(id, world.gameplay.stars):
			_discard_place_candidate(candidate_room,owns_candidate)
			controller.region.set_focus(world.player.global_position)
			if SEWER_NETWORK.is_manhole(id) and sewer_entry_origin.is_finite():
				world.player.teleport(sewer_entry_origin)
				_close_sewer_hatch_for_transition(token)
				sewer_entry_origin = Vector3.ZERO
			_restore_transition_player_lock(was_player_locked,token)
			_finish_transition(token)
			return false
	destination = _garage_restore_spawn(id,destination,candidate_room)
	if not destination.is_finite() or not position_clear(destination+Vector3.UP*.04):
		_discard_place_candidate(candidate_room,owns_candidate)
		controller.region.set_focus(world.player.global_position)
		if SEWER_NETWORK.is_manhole(id) and sewer_entry_origin.is_finite():
			world.player.teleport(sewer_entry_origin)
			_close_sewer_hatch_for_transition(token)
		_restore_transition_player_lock(was_player_locked,token)
		_finish_transition(token)
		show_message("Entrada bloqueada.")
		return false
	# Bueiro: Dante anda até a borda, a tampa desliza e ele desce a escada antes do véu cobrir a troca.
	# Loading a saved interior admits Dante directly; it is not a street approach.
	if ready_for_play and SEWER_NETWORK.is_manhole(id) and is_instance_valid(sewer_hatch):
		var descent: Node = SEWER_DESCENT.new()
		descent.setup(world.player, sewer_hatch, func() -> bool: return _owns_transition(token) and world.gameplay.health > 0)
		if descent.can_run():
			add_child(descent)
			var descended: bool = await descent.descend()
			descent.queue_free()
			if not descended:
				_discard_place_candidate(candidate_room,owns_candidate)
				controller.region.set_focus(world.player.global_position)
				if sewer_entry_origin.is_finite():
					world.player.teleport(sewer_entry_origin)
					_close_sewer_hatch_for_transition(token)
					sewer_entry_origin = Vector3.ZERO
				_restore_transition_player_lock(was_player_locked,token)
				_finish_transition(token)
				return false
		else:
			descent.free()
	# Lojas com acesso a pé têm a própria câmera; nas demais portas a sala já foi
	# admitida e o véu cobre só a troca, entre a aproximação e a revelação.
	var animated := autosave and not _uses_walkup_access(id)
	if animated:
		var door_focus: Vector3 = world.player.global_position + Vector3.UP * 1.2
		world.camera.focus_on_transition(door_focus, maxf(8.0, world.camera.size * 0.78), world.camera.STORE_FOCUS_OFFSET, 0.42)
		await get_tree().create_timer(0.12).timeout
		await door_transition.fade_to(1.0, 0.30)
		if not _owns_transition(token) or state.region_id != origin_region or not state.place_id.is_empty() or room != origin_room or world.driving.occupied or world.gameplay.health <= 0 or not is_instance_valid(candidate_room) or not preload("res://runtime/ShopSafety.gd").admission_allowed(id, world.gameplay.stars):
			_discard_place_candidate(candidate_room,owns_candidate)
			controller.region.set_focus(world.player.global_position)
			world.camera.clear_store_focus()
			world.camera._process(0.0)
			if SEWER_NETWORK.is_manhole(id) and sewer_entry_origin.is_finite():
				world.player.teleport(sewer_entry_origin)
				_close_sewer_hatch_for_transition(token)
				sewer_entry_origin = Vector3.ZERO
			await door_transition.fade_to(0.0, 0.22)
			_restore_transition_player_lock(was_player_locked,token)
			_finish_transition(token)
			return false
	saved_heading = world.camera.heading
	saved_size = world.camera.target_size
	room = candidate_room
	return_point = candidate_return
	access_id = local_access_id
	state.set_location(state.region_id,id)
	if id == "cobra_leader_house" and state.campaign.active_id == "cobra_finale" and state.campaign.step == 6:
		mission_world._event("leader_house_entered","cobra_leader_house")
	state.checkpoint_id = local_access_id if not local_access_id.is_empty() else id
	world.player.teleport(destination+Vector3.UP*.04)
	_sync_location_presentation()
	anchor.position = room.camera_target
	world.camera.clear_store_focus()
	world.camera.target = anchor
	world.camera.offset = Vector3(0,18,15)
	world.camera.heading = 0
	world.camera.target_size = room.camera_size
	world.camera.size = room.camera_size
	world.camera.locked = true
	world.camera.initialized = false
	world.camera._process(1)
	if SEWER_NETWORK.is_manhole(id) and is_instance_valid(sewer_hatch):
		_close_sewer_hatch_for_transition(token)
		sewer_hatch = null
		sewer_entry_origin = Vector3.ZERO
	# Recibos antes de a tela clarear: depois do fade, a arma e o dinheiro já coletados apareciam na sala
	# por 0,34 s e só então sumiam (reentrada no esconderijo do Vértice, test_vertice_hideout).
	if id != "maciota": _update_reward()
	if animated: await door_transition.fade_to(0.0, 0.34)
	_restore_transition_player_lock(was_player_locked,token)
	if id != "maciota":
		_install_service_npc()
		_update_reward()
	if room.has_method("on_session_entered"): room.on_session_entered(self)
	if building_entrance != null and building_entrance.handles_place(id): building_entrance.entered()
	_finish_transition(token)
	arrival.on_location_changed()
	garage_rewards.on_location_changed()
	_refresh_routine_context()
	sync_dispatch_location()
	if autosave: save_game()
	if upside_world != null: upside_world.arm_entry(id, not autosave)
	return true

func complete_upside_return(provider: Node, illusion_token: int) -> bool:
	# The illusion owns its curtain and transition; this adapter owns real-world
	# admission and reuses the ordinary room/NPC/camera departure transaction.
	if provider != upside_world or not provider.owns(illusion_token) or state.place_id != "harbor_haunted_house": return false
	var original_return := return_point
	var trace := {"result":"searching","attempts":[]}
	provider.set_meta("return_trace",trace)
	for candidate: Vector3 in provider.return_candidates():
		if not candidate.is_finite() or candidate.distance_to(original_return) < 35.0: continue
		return_point = candidate - Vector3.UP * .08
		controller.region.set_focus(candidate)
		controller.region.prepare_collision_at(candidate)
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not provider.owns(illusion_token) or world.gameplay.health <= 0 or rescue_pending or arrest_pending: return false
		var attempt := {"point":str(candidate),"clear":_upside_landing_clear(candidate)}
		trace.attempts.append(attempt)
		if not attempt.clear: continue
		if provider._released:
			if not provider.prepare_departure_retry(illusion_token): return false
		elif not provider.release_for_return(illusion_token):
			trace.result = "room_blocked"
			return_point = original_return
			controller.region.set_focus(original_return)
			return false
		var departed: bool = await leave_place()
		attempt["departed"] = departed
		attempt["place_after"] = state.place_id
		attempt["generation"] = transition_generation
		if departed:
			if not provider.finish_return(illusion_token):
				trace.result = "completion_interrupted"
				return false
			trace.result = "returned"
			close_menu()
			save_game()
			return true
		# A pedestrian or newly streamed solid may occupy the chosen pavement
		# during the normal door fade. Keep our curtain and try another candidate;
		# aborting here used to strand the living visitor drunk inside Umbra.
		if not provider.owns(illusion_token) or state.place_id != "harbor_haunted_house" or world.gameplay.health <= 0 or rescue_pending or arrest_pending or not transition_kind.is_empty(): return false
		world.player.input_locked = true
	trace.result = "all_candidates_blocked"
	return_point = original_return
	controller.region.set_focus(original_return)
	# A refused departure already returned our transition token. Release only
	# our own remaining input lock before the runtime cancels on the safe room.
	if provider._released and provider.owns(illusion_token) and transition_kind.is_empty(): close_menu()
	return false

func _upside_landing_clear(point: Vector3) -> bool:
	# Authored public pavements only, full capsule, a flat supporting surface,
	# and a margin against nearby or approaching live vehicles.
	if not position_clear(point): return false
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .25, point - Vector3.UP * .45, 1)
	var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	if ground.is_empty() or ground.normal.y < .85 or absf(ground.position.y - point.y) > .25: return false
	for vehicle in controller.vehicles:
		if not is_instance_valid(vehicle): continue
		var offset: Vector3 = vehicle.global_position - point
		offset.y = 0.0
		var future: Vector3 = vehicle.global_position + vehicle.velocity * .75 - point
		future.y = 0.0
		if offset.length_squared() < 12.25 or future.length_squared() < 12.25: return false
	return true

func leave_place() -> bool:
	if is_transition_blocked() or state.place_id.is_empty() or not is_instance_valid(room): return false
	if service_roofs != null and service_roofs.is_active(): service_roofs.clear(true)
	var token := _begin_transition("leave_place")
	if token < 0: return false
	var leaving_room: Node3D = room
	var was_player_locked: bool = world.player.input_locked
	var was_sewer_exit: bool = SEWER_NETWORK.is_manhole(state.place_id)
	if SEWER_NETWORK.is_manhole(state.place_id):
		sewer_hatch = _find_sewer_hatch(state.place_id)
		if is_instance_valid(sewer_hatch):
			world.player.input_locked = true
	var continuous_departure: bool = building_entrance != null and building_entrance.handles_place(state.place_id) and building_entrance.walking_departure
	# Rebuild exterior support before admitting an actor from a remote room.
	if not continuous_departure:
		world.player.input_locked = true
		controller.region.prepare_collision_at(return_point)
		controller.region.set_focus(return_point)
		for i in 3: await get_tree().physics_frame
		if not _owns_transition(token) or room != leaving_room or world.gameplay.health <= 0:
			_restore_transition_player_lock(was_player_locked,token)
			_finish_transition(token)
			return false
	var leaving_return: Vector3 = world.player.global_position-Vector3.UP*.08 if continuous_departure else _clear_return_point(state.place_id, return_point)
	if continuous_departure and not position_clear(world.player.global_position): leaving_return = Vector3.INF
	world.player.input_locked = true
	if not leaving_return.is_finite():
		if is_instance_valid(sewer_hatch):
			sewer_hatch.set_open_amount(0.0)
			sewer_hatch = null
		world.player.input_locked = was_player_locked
		_finish_transition(token)
		show_message("Passagem ocupada. Aguarde.")
		return false
	var animated := not _uses_walkup_access(state.place_id)
	if animated:
		var exit_focus: Vector3 = leaving_room.exit_position + Vector3.UP * 0.8
		world.camera.focus_on_transition(exit_focus, maxf(6.0, world.camera.size * 0.82), world.camera.offset, 0.38)
		await get_tree().create_timer(0.10).timeout
		await door_transition.fade_to(1.0, 0.28)
		leaving_return = _clear_return_point(state.place_id, return_point)
		if not _owns_transition(token) or world.gameplay.health <= 0 or room != leaving_room or not leaving_return.is_finite():
			world.camera.clear_store_focus()
			world.camera._process(0.0)
			await door_transition.fade_to(0.0, 0.22)
			if is_instance_valid(sewer_hatch):
				sewer_hatch.set_open_amount(0.0)
				sewer_hatch = null
			_restore_transition_player_lock(was_player_locked,token)
			_finish_transition(token)
			if not leaving_return.is_finite(): show_message("Passagem ocupada. Aguarde.")
			return false
	controller.region.set_focus(leaving_return)
	if state.place_id=="harbor_bank": robberies.bank_departed()
	if state.place_id=="remote_coal_mine" and mining != null and is_instance_valid(mining.raid): mining.raid.departed()
	if building_entrance != null: building_entrance.departed(leaving_room)
	if leaving_room == world.maciota_place: leaving_room.set_interior_active(false)
	else: leaving_room.queue_free()
	_clear_service_npcs()
	room = null
	state.set_location(state.region_id)
	world.player.teleport(leaving_return+Vector3.UP*.08)
	_sync_location_presentation()
	# Saída do bueiro: Dante reaparece no fundo do poço com a tampa aberta e sobe a escada depois do véu abrir.
	var ascent: Node
	if was_sewer_exit and is_instance_valid(sewer_hatch):
		ascent = SEWER_DESCENT.new()
		ascent.setup(world.player, sewer_hatch, func() -> bool: return _owns_transition(token) and world.gameplay.health > 0)
		if ascent.can_run():
			add_child(ascent)
			ascent.prepare_exit()
		else:
			ascent.free()
			ascent = null
	if state.place_id.is_empty() and is_instance_valid(sewer_hatch) and ascent == null:
		_close_sewer_hatch_after_exit(sewer_hatch)
		sewer_hatch = null
	world.camera.target = world.player
	world.camera.offset = world.camera.EXTERIOR_OFFSET
	world.camera.heading = saved_heading
	world.camera.target_size = saved_size
	world.camera.locked = false
	world.camera.initialized = false
	world.camera._process(1)
	if animated:
		world.camera.reveal_exterior(world.player.global_position, maxf(8.0, saved_size * 0.78), saved_size, 0.42)
		await door_transition.fade_to(0.0, 0.42)
		world.camera.clear_store_focus()
	if ascent != null:
		await ascent.ascend(leaving_return)
		ascent.queue_free()
		if is_instance_valid(sewer_hatch):
			_close_sewer_hatch_after_exit(sewer_hatch)
			sewer_hatch = null
		world.player.teleport(leaving_return+Vector3.UP*.08)
	world.player.input_locked = was_player_locked
	_finish_transition(token)
	close_menu()
	arrival.on_location_changed()
	garage_rewards.on_location_changed()
	_refresh_routine_context()
	sync_dispatch_location()
	save_game()
	return true

func _find_sewer_hatch(place_id := "harbor_sewer") -> Node3D:
	if controller == null or controller.region == null: return null
	var target := Vector2(1182.0, 2114.0) / 16.0
	if place_id != "harbor_sewer":
		var exterior: Vector3 = PLACES.get_definition(place_id).get("exterior_position", Vector3.ZERO)
		target = Vector2(exterior.x, exterior.z)
	var best: Node3D
	var best_distance := 2.0
	for chunk in controller.region.get_children():
		for node in chunk.find_children(place_id, "Node3D", true, false):
			var distance := Vector2(node.global_position.x, node.global_position.z).distance_to(target)
			if distance < best_distance:
				best_distance = distance
				best = node
	return best

func _close_sewer_hatch_for_transition(token: int) -> void:
	if not is_instance_valid(sewer_hatch) or not sewer_hatch.has_method("set_open_amount"): return
	if _owns_transition(token): sewer_hatch.set_open_amount(0.0)

func _close_sewer_hatch_after_exit(hatch: Node3D) -> void:
	if is_instance_valid(hatch): hatch.set_open_amount(0.0)


func _clear_return_point(place_id: String, desired: Vector3) -> Vector3:
	if upside_world != null and upside_world.busy() and upside_world._released and place_id == "harbor_haunted_house":
		# The return belongs to a different facade. Revalidate its exact authored
		# pavement, including live vehicles, instead of offsetting from Umbra.
		return desired if _upside_landing_clear(desired + Vector3.UP * .08) else Vector3.INF
	# Keep the authored V1 return first. A streamed pedestrian or a facade edge
	# must not trap the player inside forever, so test a few small points farther
	# along the same exterior approach before refusing the transition.
	if position_clear(desired + Vector3.UP * .08): return desired
	var outward := Vector3.FORWARD
	var definition: Dictionary = {}
	if place_id == "maciota":
		outward = desired - world.maciota_place.entry_position
	else:
		definition = PLACES.get_definition(place_id)
		if weapon_shop_entrance != null and weapon_shop_entrance.handles_place(access_id):
			definition = weapon_shop_entrance._definition_for(access_id)
		if not definition.is_empty(): outward = desired - definition.exterior_position
	outward.y = 0
	if outward.length_squared() < .01: outward = Vector3.FORWARD
	outward = outward.normalized()
	var side := Vector3(-outward.z, 0, outward.x)
	for offset in [outward * .75, outward * 1.5, side * .8 + outward * .75, -side * .8 + outward * .75]:
		var candidate: Vector3 = desired + offset
		if position_clear(candidate + Vector3.UP * .08): return candidate
	for offset: Vector3 in definition.get("return_clearance_offsets",[]):
		var candidate: Vector3 = desired + offset
		if position_clear(candidate + Vector3.UP * .08): return candidate
	return Vector3.INF

func sync_dispatch_location() -> void:
	if is_instance_valid(world.dispatch):
		world.dispatch.player_position_override = return_point if not state.place_id.is_empty() else Vector3.INF

func _install_service_npc() -> void:
	if preload("res://runtime/ShopSafety.gd").peaceful(state.place_id): room.set_meta("invulnerable", true)
	# Vance is authored into the room's 3D art, rather than the NPC catalog.
	static_service_actor = room.find_child("VanceMilitaryGunsmith", true, false) as Node3D
	if is_instance_valid(static_service_actor): _install_workplace_reaction(static_service_actor, static_service_actor)
	var residents: Array = room.definition.get("npcs",[])
	if not residents.is_empty():
		for definition in residents:
			var point: Vector3 = room.to_global(definition.local_position)+Vector3.UP*.04
			if not position_clear(point):
				push_error("Interior NPC position blocked: "+str(definition.id))
				continue
			if state.place_id in preload("res://world/places/sewers/SewerNetwork.gd").ids():
				var resident: CharacterBody3D = preload("res://world/places/sewers/SewerHostility.gd").install(self, definition, point)
				room_npcs.append(resident)
				continue
			var actor = preload("res://scripts/Actor.gd").new()
			actor.controlled_automatically = true
			actor.position = point
			actor.set_meta("interior_npc_id",definition.id)
			# Story and service residents must survive every combat damage path.
			if state.place_id == "harbor_police" or preload("res://runtime/ShopSafety.gd").peaceful(state.place_id): actor.set_meta("invulnerable",true)
			world.add_child(actor)
			var original: Node = actor.visual.get_child(0)
			actor.visual.remove_child(original)
			original.queue_free()
			var branch_model: Node3D = preload("res://world/places/OriginalResidents.gd").create_model(definition)
			actor.visual.add_child(branch_model)
			room_npcs.append(actor)
			_install_workplace_reaction(actor, branch_model)
		room_npc = room_npcs[0] if not room_npcs.is_empty() else null
		return
	if str(room.definition.get("npc_model","")).is_empty(): return
	var model_resource = load(room.definition.npc_model)
	if model_resource == null: return
	room_npc = preload("res://scripts/Actor.gd").new()
	room_npc.controlled_automatically = true
	if preload("res://runtime/ShopSafety.gd").peaceful(state.place_id): room_npc.set_meta("invulnerable",true)
	room_npc.position = room.to_global(room.definition.get("npc_point",Vector3(0,0,-2)))
	world.add_child(room_npc)
	var old_model: Node = room_npc.visual.get_child(0)
	room_npc.visual.remove_child(old_model)
	old_model.queue_free()
	var model: Node3D = model_resource.instantiate() if model_resource is PackedScene else model_resource.new()
	room_npc.visual.add_child(model)
	room_npc.visual.rotation.y = PI
	room_npcs.append(room_npc)
	_install_workplace_reaction(room_npc, model)

func _install_workplace_reaction(actor: Node3D, model: Node3D) -> void:
	var reaction: Node = WORKPLACE_REACTION.install(actor, model, world.gameplay)
	if reaction != null and not reaction.threat_started.is_connected(_on_workplace_threat_started):
		reaction.threat_started.connect(_on_workplace_threat_started)

func _service_threatened(npc_id := "") -> bool:
	if npc_id.is_empty() and is_instance_valid(static_service_actor) and static_service_actor.get_meta("workplace_threatened", false): return true
	for actor in room_npcs:
		if not is_instance_valid(actor) or not actor.is_visible_in_tree(): continue
		if not npc_id.is_empty() and str(actor.get_meta("interior_npc_id", "")) != npc_id: continue
		if actor.get_meta("workplace_threatened", false): return true
	# Robberies replace the generic bank/fuel resident with their physical actors.
	if npc_id.is_empty() and robberies != null:
		for actor in robberies._actors:
			if is_instance_valid(actor) and not actor.guard and actor.get_meta("workplace_threatened", false): return true
	return false

func _on_workplace_threat_started(actor: Node3D) -> void:
	var local_staff: bool = actor == static_service_actor or room_npcs.has(actor) or (robberies != null and robberies._actors.has(actor))
	if not local_staff: return
	if _service_menu_open or (storefronts != null and storefronts.is_open()):
		lines.clear()
		dialogue_done = Callable()
		close_menu()
	prompt.text = ""

func _clear_service_npcs() -> void:
	static_service_actor = null
	for actor in room_npcs:
		if is_instance_valid(actor): actor.queue_free()
	room_npcs.clear()
	room_npc = null

func nearest() -> Dictionary:
	if upside_world != null and upside_world.busy(): return {}
	if rescue_pending or arrest_pending or world.gameplay.health <= 0: return {}
	if is_instance_valid(room) and room.has_method("start_game") and room.has_method("nearest_action"):
		var bar_action: Dictionary = room.nearest_action(self)
		if not bar_action.is_empty(): return bar_action
	if arcade != null:
		var arcade_action: Dictionary = arcade.nearest_action()
		if not arcade_action.is_empty(): return arcade_action
	if cats != null:
		var cat_action: Dictionary = cats.nearest_action()
		if not cat_action.is_empty(): return cat_action
	if amusement_park != null:
		var park_action: Dictionary = amusement_park.nearest_action()
		if not park_action.is_empty(): return park_action
	if fishing != null:
		var fishing_action: Dictionary = fishing.nearest_action()
		if not fishing_action.is_empty(): return fishing_action
	if coastal_lookout != null:
		var lookout_action: Dictionary = coastal_lookout.nearest_action()
		if not lookout_action.is_empty(): return lookout_action
	if regional_coach != null:
		var coach_action: Dictionary = regional_coach.nearest_action()
		if not coach_action.is_empty(): return coach_action
	if building_entrance != null and building_entrance.falling: return {}
	if service_roofs != null:
		var roof_action: Dictionary = service_roofs.nearest_action()
		if not roof_action.is_empty() or service_roofs.is_active(): return roof_action
	if railway != null:
		var railway_action: Dictionary = railway.nearest_action()
		if not railway_action.is_empty(): return railway_action
	if armored_transport != null:
		var armored_action: Dictionary = armored_transport.nearest_action()
		if not armored_action.is_empty(): return armored_action
	if mountain_activities != null and mountain_activities.busy():
		var pack_active_action: Dictionary = mountain_activities.nearest_action()
		if not pack_active_action.is_empty(): return pack_active_action
	if mining != null:
		var mining_action: Dictionary = mining.nearest_action()
		if not mining_action.is_empty(): return mining_action
	if desert != null:
		var desert_action: Dictionary = desert.nearest_action()
		if not desert_action.is_empty(): return desert_action
	for site in get_tree().get_nodes_in_group("blade_forge_site"):
		var forge_action: Dictionary = site.nearest_action()
		if not forge_action.is_empty(): return forge_action
	for site in get_tree().get_nodes_in_group("mountain_refuge_site"):
		var refuge_action: Dictionary = site.nearest_action()
		if not refuge_action.is_empty(): return refuge_action
	if skate != null:
		var skate_action: Dictionary = skate.nearest_action()
		if not skate_action.is_empty(): return skate_action
	if field_inventory != null:
		var supply_action: Dictionary = field_inventory.nearest_action()
		if not supply_action.is_empty(): return supply_action
	if motocross != null:
		var mx_action: Dictionary = motocross.nearest_action()
		if not mx_action.is_empty(): return mx_action
	if port_container_loot != null:
		var cargo_action: Dictionary = port_container_loot.nearest_action()
		if not cargo_action.is_empty(): return cargo_action
	if passenger_transport != null and passenger_transport.riding: return passenger_transport.nearest_action()
	if jessica != null:
		var jessica_action: Dictionary = jessica.nearest_action()
		if not jessica_action.is_empty(): return jessica_action
	var arrival_action: Dictionary = arrival.nearest_action()
	if is_instance_valid(room) and room.has_method("nearest_action") and not room.has_method("start_game"):
		var rooftop_action: Dictionary = building_entrance.nearest_action() if building_entrance != null else {}
		if not rooftop_action.is_empty(): return rooftop_action
		var room_action: Dictionary = room.nearest_action()
		if not room_action.is_empty(): return room_action
	if not arrival_action.is_empty(): return arrival_action
	if not world.driving.occupied and not state.place_id.is_empty() and is_instance_valid(room):
		if (not _uses_walkup_access(state.place_id) or _keeps_interaction_access(state.place_id)) and world.player.position.distance_to(room.exit_position) < 1.45: return {"id":"exit","label":"Sair","silent":state.place_id in ["harbor_arcade","harbor_curitiba_cellar","harbor_haunted_house"] or preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").is_building(state.place_id)}
	var personal_action: Dictionary = personal_car.nearest_action()
	if not personal_action.is_empty(): return personal_action
	var residence_action: Dictionary = residence_services.nearest_action()
	if not residence_action.is_empty(): return residence_action
	if mountain_activities != null:
		var pack_action: Dictionary = mountain_activities.nearest_action()
		if not pack_action.is_empty(): return pack_action
	var mountain_action: Dictionary = mountain_progression.nearest_action()
	if not mountain_action.is_empty(): return mountain_action
	var garage_action: Dictionary = garage_rewards.nearest_action()
	if not garage_action.is_empty(): return garage_action
	if world.driving.occupied:
		var driver_freight: Dictionary = urban_operations.freight.nearest_action() if urban_operations != null and is_instance_valid(urban_operations.freight) else {}
		if not driver_freight.is_empty(): return driver_freight
		var vehicle_action: Dictionary = mission_world.nearest_vehicle_action()
		if vehicle_action.is_empty() and helena_act1 != null: vehicle_action = helena_act1.nearest_vehicle_action()
		return vehicle_action if not vehicle_action.is_empty() else activities.nearest_action()
	var point: Vector3 = world.player.position
	if not state.place_id.is_empty():
		if (not _uses_walkup_access(state.place_id) or _keeps_interaction_access(state.place_id)) and point.distance_to(room.exit_position) < 1.45: return {"id":"exit","label":"Sair","silent":state.place_id in ["harbor_arcade","harbor_curitiba_cellar","harbor_haunted_house"] or preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").is_building(state.place_id)}
		var robbery_action: Dictionary = robberies.nearest_action()
		if not robbery_action.is_empty(): return robbery_action
		var act1_indoor: Dictionary = helena_act1.nearest_action() if helena_act1 != null else {}
		if not act1_indoor.is_empty(): return act1_indoor
		var original_action: Dictionary = services.nearest_action()
		if not original_action.is_empty() and not _service_threatened(str(original_action.get("target", ""))): return original_action
		if wine != null:
			var wine_action: Dictionary = wine.nearest_action()
			if not wine_action.is_empty(): return wine_action
		var branch_urban_action: Dictionary = urban_operations.nearest_action() if urban_operations != null else {}
		if not branch_urban_action.is_empty(): return branch_urban_action
		var interior_routine_action: Dictionary = _routine_director().nearest_action() if _routine_director() != null else {}
		if not interior_routine_action.is_empty(): return interior_routine_action
		if state.place_id == "maciota":
			for id in ["maciota","mechanic","part"]:
				if id == "part" and state.intro.stage != "collect_part": continue
				if point.distance_to(room.interaction_points[id]) < 1.3: return {"id":id,"label":"Pegar peça" if id == "part" else "Conversar"}
		else:
			var service_point: Vector3 = room.interaction_points.service
			var service: String = str(room.definition.get("service",""))
			# Police, hospital and fire station publish their terminal/NPC/healing
			# actions through Services.nearest_action(). A second generic counter
			# produced a visible "Atender" prompt with no consumer or result.
			var primary_available := service in ["weapons","clothing","supermarket"]
			if state.place_id == "harbor_bank": primary_available = state.campaign.target_id() == "helena"
			# A conveniência não tinha balcão de compras no V1: sua operação é o
			# caixa do assalto. Não exponha um "Atender" que não produz resultado.
			if primary_available and not _service_threatened() and point.distance_to(service_point) < 1.5:
				return {"id":"service","label":"Comprar" if service == "supermarket" else "Falar com Vance" if state.place_id in ["harbor_ammunation", "mountain_gunshop"] else "Atender"}
		if building_social != null:
			var social_action: Dictionary = building_social.nearest_action()
			if not social_action.is_empty(): return social_action
		return {}
	# Antes das atividades: o Neco da cadeia da Helena fica no mesmo ponto do serviço de guincho.
	var act1_action: Dictionary = helena_act1.nearest_action() if helena_act1 != null else {}
	if not act1_action.is_empty(): return act1_action
	var activity_action: Dictionary = activities.nearest_action()
	if not activity_action.is_empty(): return activity_action
	var urban_action: Dictionary = urban_operations.nearest_action() if urban_operations != null else {}
	if not urban_action.is_empty(): return urban_action
	var outdoor_routine_action: Dictionary = _routine_director().nearest_action() if _routine_director() != null else {}
	if not outdoor_routine_action.is_empty(): return outdoor_routine_action
	if state.region_id == "harbor" and not _uses_walkup_access("maciota") and point.distance_to(world.maciota_place.entry_position) < 1.5: return {"id":"enter","place":"maciota","access":"maciota","label":"Entrar"}
	for entry in controller.region.entries:
		if (SEWER_NETWORK.is_manhole(entry.place_id) or entry.place_id == "remote_coal_mine") and point.distance_to(entry.position) < 1.5:
			return {"id":"enter","place":entry.place_id,"access":entry.id,"label":"","silent":true}
		if _uses_walkup_access(entry.place_id) and not _keeps_interaction_access(entry.place_id): continue
		if point.distance_to(entry.position) < 1.5:
			return {"id":"enter","place":entry.place_id,"access":entry.id,"label":"Entrar","silent":entry.place_id in ["harbor_arcade","harbor_curitiba_cellar","harbor_haunted_house"] or preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").is_building(entry.place_id)}
	var mission_action: Dictionary = mission_world.nearest_action()
	if not mission_action.is_empty(): return mission_action
	return passenger_transport.nearest_action()

func interaction_input_action(action: Dictionary) -> String:
	if action.get("id", "") == "enter" and SEWER_NETWORK.is_manhole(str(action.get("place", ""))): return "vehicle_interact"
	if action.get("id", "") == "exit" and SEWER_NETWORK.is_manhole(state.place_id): return "vehicle_interact"
	return "interact"

func interact() -> bool:
	if modal or not ready_for_play: return false
	if world.player.get_meta("player_air_busy",false): return false
	var action := nearest()
	if action.get("id", "") == "building_social": return building_social.open(action.target)
	if action.get("id","") == "building_stairs": return await action.provider.use_stairs()
	if action.get("id","") == "building_lockpick": return await action.provider.perform(action)
	if action.get("id","") == "desert_roadside" and is_instance_valid(action.get("provider")): return action.provider.perform(action)
	if action.get("id","") == "mountain_refuge" and is_instance_valid(action.get("provider")): return action.provider.perform(action)
	if action.get("id","") == "service_roof_stairs": return await service_roofs.use_stairs()
	if mining != null and action.get("id","") == "mining": return mining.perform(action)
	if desert != null and action.get("id","") in ["desert","desert_story","desert_drag"]: return desert.perform(action)
	if mountain_activities != null and mountain_activities.handles(action): return mountain_activities.perform(action)
	if action.get("id", "") == "blade_forge": return BLADE_FORGE_TALK.perform(self, action)
	if action.get("id", "") == "skate": return skate.perform(str(action.target))
	if action.get("id","") == "motocross": return motocross.perform(str(action.target))
	if str(action.get("id","")).begins_with("ski_"): return mountain_progression.perform(action.target)
	if str(action.get("id","")).begins_with("arrival_"): return arrival.perform(action.id)
	match str(action.get("id","")):
		"cat_adopt": return cats.perform(str(action.target))
		"fishing": return fishing.perform(str(action.target))
		"wine": return wine.perform(str(action.target))
		"bar_game": return room.start_game(str(action.target),self) if is_instance_valid(room) and room.has_method("start_game") else false
		"arcade": return arcade.perform(str(action.target))
		"coastal_binoculars": return coastal_lookout.perform(str(action.target))
		"amusement_park": return amusement_park.perform(str(action.target))
		"railway": return railway.perform(str(action.target))
		"regional_coach": return regional_coach.perform(str(action.target))
		"armored_transport": return armored_transport.perform(int(action.target))
		"field_inventory": return field_inventory.perform(str(action.target))
		"port_container": return port_container_loot.perform(str(action.target))
		"passenger_transport": return passenger_transport.perform(action.target)
		"residence_services": return residence_services.perform("residence_services")
		"personal_car": return personal_car.perform(action.target)
		"jessica": return jessica.perform(str(action.target))
		"helena_act1": return helena_act1 != null and helena_act1.perform(action)
		"garage_reward": return garage_rewards.perform(action.target)
		"robbery": return robberies.perform(action.target)
		"original_service":
			if _service_threatened(str(action.target)): return false
			var performed: bool = services.perform(action.target)
			_service_menu_open = performed and modal and str(action.target) not in ["hospital_triage", "police_terminal", "fire_alarm"]
			return performed
		"urban_v1": return _perform_urban_action(str(action.target))
		"v1_routine":
			var routines = _routine_director()
			return routines != null and routines.perform(str(action.target))
		"exit": return await leave_place()
		"enter":
			enter_place(action.place,true,str(action.access))
			return true
		"maciota":
			if state.intro.stage != "complete": return _intro_interact("maciota")
			if mission_world.perform("maciota"): return true
			show_maciota_menu()
			return true
		"mechanic":
			if state.intro.stage != "complete": return _intro_interact("mechanic")
			if maciota_workshop != null and maciota_workshop.open_menu(): return true
			show_services("garage")
			return true
		"part": return _intro_interact("workbench")
		"service":
			if state.place_id == "harbor_bank" and mission_world.perform("helena"):
				_service_menu_open = modal
				return true
			show_services(room.definition.service)
			return true
	if activities.perform(str(action.get("target",""))): return true
	return mission_world.perform(str(action.get("target","")))

func _perform_urban_action(target: String) -> bool:
	if urban_operations == null: return false
	var quest = urban_operations.get("village_quest")
	if target == "truckers_village_tonico" and is_instance_valid(quest) and not quest.data.started:
		if not save_game(true): return false
	return urban_operations.perform(target)

func _intro_interact(id: String) -> bool:
	if id == "maciota" and state.intro.stage == "meet_maciota" and not save_game(true): return false
	state.intro.set_location("harbor_garage")
	var reply: Dictionary = state.intro.complete_meeting() if id == "maciota" and state.intro.stage == "meet_maciota" else state.intro.interact(id)
	if not reply.ok: return false
	if id == "maciota": arrival.notify_maciota_met()
	if reply.has("lines"):
		show_dialogue(preload("res://runtime/ArrivalDialogue.gd").lines(reply.lines),func():
			if state.campaign.active_id.is_empty() and not state.campaign.has_progress("primeiro_giro"): mission_world.begin("primeiro_giro"))
		preload("res://systems/campaign/HarborStory.gd").mark_maciota(state.world_state)
	else: show_dialogue([{ "speaker":reply.speaker,"message":reply.message }])
	world.maciota_place.set_part_available(state.intro.part_available)
	if reply.changed: save_game()
	return true

func _input(event: InputEvent) -> void:
	if world.player != null and world.player.get_meta("developer_free_flight",false): return
	get_node("/root/GameInput").observe_event(event)
	if is_instance_valid(equipment_wheel) and equipment_wheel.active:
		equipment_wheel.handle_input(event)
		get_viewport().set_input_as_handled()
		return
	# The opening owns input while the world is paused. Leave clicks and Esc
	# available to its skip button/dialog and _unhandled_input handler.
	if arrival != null and arrival.phase == "opening" and is_instance_valid(arrival.presentation): return
	if upside_world != null and upside_world.busy():
		if upside_world.handle_input(event): get_viewport().set_input_as_handled()
		return
	if building_social != null and building_social.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(room) and room.has_method("handle_game_input") and room.handle_game_input(event):
		get_viewport().set_input_as_handled()
		return
	if arcade != null and arcade.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if amusement_park != null and amusement_park.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if fishing != null and fishing.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if coastal_lookout != null and coastal_lookout.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if regional_coach != null and regional_coach.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if railway != null and railway.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if armored_transport != null and is_instance_valid(armored_transport.minigame) and armored_transport.minigame.active: return
	if port_container_loot != null and is_instance_valid(port_container_loot.minigame) and port_container_loot.minigame.active: return
	if urban_operations != null and is_instance_valid(urban_operations.village_leisure) and is_instance_valid(urban_operations.village_leisure.ui) and urban_operations.village_leisure.ui.active: return
	if transition_kind == "ski_lift" and mountain_progression != null and mountain_progression.lift.riding:
		if not get_tree().paused and event.is_action_pressed("interact"):
			mountain_progression.lift.skip()
		if not event.is_action_pressed("pause_game") and not (get_tree().paused and event.is_action_pressed("ui_cancel")):
			get_viewport().set_input_as_handled()
		return
	if controller.travel_busy or not transition_kind.is_empty() or vehicle_transition_busy:
		get_viewport().set_input_as_handled()
		return
	if not ready_for_play: return
	if arrival.riding and (event.is_action_pressed("pause_game") or event.is_action_pressed("exit_vehicle")):
		arrival.cancel_ride()
		get_viewport().set_input_as_handled()
		return
	if _arrival_sequence_blocked():
		if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
			show_message("Aguarde a conclusão desta chegada.")
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(robberies.lockpick) and robberies.lockpick.active: return
	if police_motor_pool != null and police_motor_pool.blocks_input(): return
	if not rebinding_action.is_empty():
		if event is InputEventKey and event.pressed and not event.echo:
			var controls = get_node("/root/GameInput")
			if event.keycode != KEY_ESCAPE:
				var error: String = controls.rebind(rebinding_action,event)
				if not error.is_empty(): show_message(error); get_viewport().set_input_as_handled(); return
				get_node("/root/V2Settings").save_settings()
			rebinding_action = ""
			controls.remapping = false
			show_controls()
			get_viewport().set_input_as_handled()
		return
	if get_tree().paused: return
	if modal:
		if field_inventory != null and field_inventory.ui.visible and event.is_action_pressed("inventory") and not event.is_action("ui_left") and not event.is_action("ui_right") and not event.is_action("ui_up") and not event.is_action("ui_down"):
			close_menu()
			get_viewport().set_input_as_handled()
			return
		if storefronts != null and storefronts.is_open() and storefronts.handle_input(event):
			get_viewport().set_input_as_handled()
			return
		# Focused Buttons own ui_accept. Consuming it here prevented Enter and the
		# controller accept button from reaching shops, journals and death rescue.
		if dialogue_open and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
			_advance_dialogue()
			get_viewport().set_input_as_handled()
		elif (event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel")) and not rescue_pending:
			# This guided conversation owns the arrival callback. Dismissing only
			# its surface would strand the encounter and leave Arrival.voice playing.
			if dialogue_open and arrival != null and arrival.active and arrival.dialogue_in_progress():
				get_viewport().set_input_as_handled()
				return
			# Tuning owns its pending draft. Its close signal releases this modal
			# only after the player applies or discards those temporary changes.
			for tuning in get_tree().get_nodes_in_group("vehicle_tuning_panels"):
				var tuning_panel := tuning as CanvasLayer
				if tuning_panel != null and world.is_ancestor_of(tuning_panel) and tuning_panel.visible:
					tuning_panel.call("request_cancel")
					get_viewport().set_input_as_handled()
					return
			close_menu()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
		return
	if get_tree().paused: return
	# Mounted activities consume gameplay events, but their camera stays usable.
	if (event is InputEventMouseMotion and world.camera.mouse_orbit_active()) or (not event is InputEventJoypadMotion and (event.is_action_pressed("camera_left") or event.is_action_pressed("camera_right") or event.is_action_pressed("camera_drag"))):
		world.camera._unhandled_input(event)
		if get_viewport().is_input_handled(): return
	if skate != null and skate.controls_locked():
		if not skate.recovering: skate.handle_input(event)
		if not event.is_action_pressed("pause_game"): get_viewport().set_input_as_handled()
		return
	if passenger_transport != null and passenger_transport.riding:
		if event.is_action_pressed("interact") or event.is_action_pressed("exit_vehicle") or event.is_action_pressed("vehicle_interact"):
			passenger_transport.request_exit()
		# Leave pause available, but consume gameplay/menu/quick-save input in transit.
		if not event.is_action_pressed("pause_game"): get_viewport().set_input_as_handled()
		return
	if motocross != null and motocross.mounted:
		# The touch overlay turns raw fingers into game actions. Consuming the
		# fingers here prevented its pedals and wheelie button from receiving them.
		if event is InputEventScreenTouch or event is InputEventScreenDrag: return
		if event.is_action_pressed("interact") or event.is_action_pressed("exit_vehicle"):
			motocross.perform("quit" if motocross.active else "dismount")
		if not event.is_action_pressed("pause_game"): get_viewport().set_input_as_handled()
		return
	if world.driving.occupied and is_instance_valid(world.driving.car.equipment):
		if world.driving.car.equipment.handle_input(event,true):
			get_viewport().set_input_as_handled()
			return
	var wants_interact := false
	if is_instance_valid(equipment_wheel) and equipment_wheel.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("jump") and not event.is_echo() and not world.driving.occupied:
		if world.player.air_movement != null and world.player.air_movement.request_jump(): get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("vehicle_interact"):
		wants_interact = event.is_action_pressed(interaction_input_action(nearest()))
	# Handle before GUI focus consumes V/R3, after modal/vehicle guards.
	if event.is_action_pressed("rage") and not event.is_echo() and not world.driving.occupied:
		if world.gameplay.request_rage(): get_viewport().set_input_as_handled()
		return
	if world.gameplay.handle_arsenal_input(event):
		get_viewport().set_input_as_handled()
		return
	var wants_reload: bool = event.is_action_pressed("reload") and not world.driving.occupied
	if wants_interact and (not wants_reload or not nearest().is_empty()):
		interact()
		get_viewport().set_input_as_handled()
	elif wants_reload:
		world.gameplay.reload_weapon()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal"): show_journal()
	elif event.is_action_pressed("inventory"): show_inventory()
	elif event.is_action_pressed("trunk"):
		var personal_action: Dictionary = personal_car.nearest_action()
		if personal_action.get("target","") == "trunk":
			personal_car.perform(personal_action.target)
		elif event.is_action_pressed("unarmed") and not world.driving.occupied:
			state.equip_weapon("fists")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("world_map"): show_map()
	elif event.is_action_pressed("unarmed"): state.equip_weapon("fists")
	elif event.is_action_pressed("weapon_next") and not world.driving.occupied: world.gameplay.cycle_weapon(1)
	elif event.is_action_pressed("weapon_flashlight") and not event.is_echo():
		_toggle_weapon_flashlight()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F5: save_game(true)
		elif event.physical_keycode == KEY_F9: load_game()

## One command synchronizes the belt and the usable weapon attachment.
func _toggle_weapon_flashlight() -> void:
	if world.driving.occupied: return
	if world.gameplay.toggle_personal_lights(): return
	var id: String = world.gameplay.equipped()
	if not state.can_attack() or id in ["", "fists"]: return
	if not preload("res://gameplay/WeaponCustomization.gd").installed(world.gameplay.customization, id):
		show_message("Instale uma lanterna nesta arma na Ammu-Nation.")

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _process(delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_process_traced(delta)
	_SYS_SPAN.finish_slow("sys.session.process", span, 3000)

func _process_traced(delta: float) -> void:
	if world.player != null and world.player.get_meta("developer_free_flight",false): return
	if not get_tree().paused: notice_time = maxf(0.0,notice_time-delta)
	if speech_active:
		if notice_time <= 0.0: clear_speech()
		elif is_instance_valid(speech_caption): speech_caption.visible = not get_tree().paused and not (is_instance_valid(equipment_wheel) and equipment_wheel.active)
	if not ready_for_play or get_tree().paused: return
	# Aviso fixo enquanto o salvamento estiver desligado (antes o autosave só parava).
	if controller.save_invalid != _save_block_shown:
		_save_block_shown = controller.save_invalid
		_save_indicator().set_blocked(controller.save_block_text() if _save_block_shown else "")
	service_roofs.update(delta)
	if not service_roofs.is_active():
		weapon_shop_entrance.update(delta)
		special_place_entrance.update(delta)
		building_entrance.update(delta)
	if is_instance_valid(world.driving.car) and is_instance_valid(world.driving.car.equipment): world.driving.car.equipment.set_input_enabled(not modal)
	if not modal and not world.driving.occupied and not get_tree().paused and (building_social == null or not building_social.blocks_gameplay_input()):
		var aim: Vector3 = world.gameplay.aim_from_screen(world.camera.aim_screen_position())
		var controls = get_node("/root/GameInput")
		if controls.using_gamepad or controls.get_meta("touch_controls_active", false) or not controls.touch_aim.is_zero_approx():
			aim = controls.aim_target_3d(world.player,world.camera,delta)
			# Robbery intimidation and every non-shot aim consumer read the same
			# authoritative world point as firearm presentation. Previously only the
			# local fire target followed a controller/touch stick, so the fuel clerk
			# could be aimed at visually but never surrender without a mouse cursor.
			world.gameplay.aim_point = aim
		var data: Dictionary = WEAPONS.WEAPONS.get(state.equipped_weapon,{})
		if Input.is_action_pressed("fire") and (data.get("automatic",false) or Input.is_action_just_pressed("fire")): world.gameplay.fire_at(aim)
	var fall_limit: float = mining.fall_limit(world.player.position) if mining != null else -12.0
	if world.player.position.y < fall_limit and not modal: _on_death()
	tick += delta
	if tick < .1: return
	tick = 0
	_refresh_reward_feedback()
	if not modal and not world.driving.occupied:
		if service_roofs.is_active(): pass
		elif not state.place_id.is_empty() and state.place_id != "maciota": _collect_reward(room)
		elif state.place_id.is_empty():
			for source in get_tree().get_nodes_in_group("native_world_rewards"): _collect_reward(source)
	var ammo: Dictionary = state.get_ammo(state.equipped_weapon)
	if cold != null:
		var thermal: Dictionary = cold.status()
		# The contextual HUD owns cold status once it is active.  The legacy label
		# otherwise reappears between its sync ticks and overlaps the new panel.
		thermal_status.visible = thermal.visible and not modal and not is_instance_valid(world.hud)
		thermal_status.text = String(TranslationServer.translate("Calor corporal %d%% · %s"))%[roundi(thermal.temperature),thermal.text]
	stats.text = String(TranslationServer.translate("R$ %d   Vida %d   Colete %d\n%s   %s   %s")) % [state.economy.balance,roundi(world.gameplay.health),roundi(world.gameplay.armor),str(WEAPONS.WEAPONS.get(state.equipped_weapon,{}).get("label",state.equipped_weapon)),"—" if int(ammo.magazine)<0 else "%d / %d"%[ammo.magazine,ammo.reserve],"★".repeat(world.gameplay.stars)]
	_set_objective(mission_world.objective() if state.campaign.active_id != "" else (state.intro.objective() if state.intro.stage != "complete" else "J  Missões · M  Mapa"), state.campaign.active_id == "" and state.intro.stage == "complete")
	if helena_act1 != null and state.campaign.active_id == "" and state.intro.stage == "complete":
		var act1_objective: String = helena_act1.objective()
		if not act1_objective.is_empty(): _set_objective(act1_objective)
	if arrival.active: _set_objective(arrival.objective_text)
	var freight: Dictionary = urban_operations.freight_status() if urban_operations != null else {}
	freight_active = bool(freight.get("active", false)) and state.region_id == "harbor" and state.campaign.active_id.is_empty() and state.intro.stage == "complete" and not arrival.active
	freight_target = freight.get("target", Vector3.INF) if freight_active else Vector3.INF
	if freight_active: _set_objective(str(freight.get("objective", "")))
	if urban_operations != null and is_instance_valid(urban_operations.village_quest) and state.campaign.active_id.is_empty() and state.intro.stage == "complete" and not arrival.active and not freight_active:
		var village_objective: String = urban_operations.village_quest.objective()
		if not village_objective.is_empty(): _set_objective(village_objective)
	if jessica != null and state.campaign.active_id == "jessica_bank": _set_objective(jessica.objective())
	var vertice_night: Node = _vertice_night()
	if vertice_night != null and state.campaign.active_id.is_empty() and state.region_id == "harbor" and not arrival.active:
		var night_objective: String = vertice_night.objective()
		if not night_objective.is_empty(): _set_objective(night_objective)
	if desert != null and state.region_id == "desert": _set_objective(desert.objective())
	if desert != null and state.region_id == "desert" and is_instance_valid(desert.frontier) and is_instance_valid(desert.frontier.roadside):
		var roadside_objective: String = desert.frontier.roadside.objective()
		if not roadside_objective.is_empty(): _set_objective(roadside_objective)
	if mountain_activities != null:
		var pack_objective: String = mountain_activities.objective()
		if not pack_objective.is_empty(): _set_objective(pack_objective)
	var action := nearest()
	if fishing != null and fishing.active: _set_objective(fishing.objective())
	prompt_input_action = interaction_input_action(action)
	var silent_exit: bool = action.get("id","") == "exit" and state.place_id in ["vertice_undercroft","remote_coal_mine"]
	var prompt_hidden: bool = modal or action.is_empty() or action.get("silent",false) or silent_exit
	prompt.text = "" if prompt_hidden else "E  "+str(action.label)
	# Legenda curta para o HUD, quando a ação tem uma ("Atender" no lugar de "Atender telefone").
	hud_prompt = "" if prompt_hidden else str(action.get("hud_label", action.label)).strip_edges()
	if not modal and (prompt_input_action == "vehicle_interact" or action.get("id","") in ["port_container","railway","regional_coach","fishing","building_social"]):
		var caption: String = str(action.get("label", "")).strip_edges()
		if prompt_input_action == "vehicle_interact" and caption.is_empty(): caption = "Descer" if action.get("id", "") == "enter" else "Subir"
		prompt.text = get_node("/root/GameInput").hint(prompt_input_action)+"  "+caption
		hud_prompt = caption

func _set_objective(text: String, hint := false) -> void:
	objective.text = text
	hud_objective = "" if hint else text.strip_edges()

func navigation_destination() -> Dictionary:
	return preload("res://runtime/NavigationDestination.gd").resolve(self)

func _update_world_indicator() -> void:
	if upside_world != null and upside_world.busy():
		if is_instance_valid(marker): marker.hide()
		if is_instance_valid(arrow): arrow.hide()
		return
	if not ready_for_play or not is_instance_valid(marker) or not is_instance_valid(arrow): return
	if fishing != null and fishing.controls_locked():
		marker.hide()
		arrow.hide()
		return
	if service_roofs != null and service_roofs.is_active():
		marker.hide()
		arrow.hide()
		return
	if desert != null and is_instance_valid(desert.drag) and desert.drag.active:
		marker.hide()
		arrow.hide()
		return
	var destination := navigation_destination()
	var target: Vector3 = destination.point if not destination.is_empty() else Vector3.INF
	if destination.is_empty() and arcade != null and state.region_id == "harbor" and state.place_id.is_empty():
		var arcade_entry := preload("res://world/places/arcade/ArcadePlace.gd").EXTERIOR + Vector3(0,0,6.3)
		if world.player.global_position.distance_squared_to(arcade_entry) < 144.0: target = arcade_entry
	if destination.is_empty() and wine != null and state.region_id == "harbor" and state.place_id.is_empty():
		var cellar_entry := preload("res://world/places/curitiba_cellar/CuritibaCellarPlace.gd").EXTERIOR + Vector3(0,0,6.7)
		if world.player.global_position.distance_squared_to(cellar_entry) < 144.0: target = cellar_entry
	if destination.is_empty() and mining != null and state.region_id == "desert" and state.place_id.is_empty() and world.player.global_position.distance_to(preload("res://world/mining/MiningLayout.gd").SECRET_ENTRY)<14.0:
		target = preload("res://world/mining/MiningLayout.gd").SECRET_ENTRY
	if not state.place_id.is_empty() and is_instance_valid(room):
		target = room.exit_position
		if state.place_id == "maciota":
			var phase: String = state.intro.stage
			if phase in ["meet_maciota","return_maciota"] or state.campaign.target_id()=="maciota": target = room.interaction_points.maciota
			elif phase == "talk_mechanic": target = room.interaction_points.mechanic
			elif phase == "collect_part": target = room.interaction_points.part
		elif state.place_id == "harbor_bank" and state.campaign.target_id()=="helena": target = robberies.helena_position()
		if helena_act1 != null:
			var act1_inside: Vector3 = helena_act1.indoor_target()
			if act1_inside.is_finite(): target = act1_inside
	if mountain_activities != null and not mountain_activities.objective().is_empty():
		var pack_target: Vector3 = mountain_activities.target_position()
		if pack_target.is_finite(): target = pack_target
	if fishing != null and fishing.active: target = fishing.target_position()
	var maciota_exterior_marker: bool = state.place_id.is_empty() and target.is_equal_approx(world.maciota_place.entry_position)
	var automatic_shop_exit: bool = _uses_walkup_access(state.place_id) and not _keeps_interaction_access(state.place_id) and is_instance_valid(room) and target.is_equal_approx(room.exit_position)
	var indicator_camera: Camera3D = amusement_park.view if amusement_park != null and amusement_park.house_view and is_instance_valid(amusement_park.view) else world.camera
	marker.visible = target.is_finite() and not maciota_exterior_marker and not automatic_shop_exit and not indicator_camera.is_position_behind(target)
	if marker.visible: marker.position = indicator_camera.unproject_position(target+Vector3.UP*.06)
	var screen: Vector2 = indicator_camera.unproject_position(target) if target.is_finite() else Vector2(640,360)
	arrow.visible = state.place_id.is_empty() and not Rect2(40,90,1200,520).has_point(screen)
	arrow.position = Vector2(clampf(screen.x,40,1220),clampf(screen.y,90,610))
	arrow.rotation = (screen-Vector2(640,360)).angle()+PI/2

func _menu(title: String) -> void:
	if is_instance_valid(room) and room.has_method("dismiss_game") and room.get("game_active") == true:
		room.dismiss_game()
		if menu_closed == Callable(room,"dismiss_game"): menu_closed = Callable()
	if is_instance_valid(equipment_wheel): equipment_wheel.cancel()
	if building_social != null and building_social.active: building_social.close()
	if arcade != null and arcade.active: arcade.close()
	clear_speech()
	if is_instance_valid(dialogue_card): dialogue_card.hide()
	if is_instance_valid(dialogue_voice): dialogue_voice.stop()
	if panel.has_meta("modal_preferred_size"): panel.remove_meta("modal_preferred_size")
	if panel.has_meta("modal_dock_right"): panel.remove_meta("modal_dock_right")
	var previous_map: Node = world.hud.get_node_or_null("MapUI")
	if is_instance_valid(previous_map):
		previous_map.queue_free()
		menu_closed = Callable()
	if field_inventory != null and field_inventory.ui.visible:
		field_inventory.dismiss()
		menu_closed = Callable()
	_service_menu_open = false
	if storefronts != null and storefronts.is_open(): storefronts.dismiss()
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	modal = true
	dialogue_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.player.input_locked = true
	if world.driving.occupied: world.driving.car.input_locked = true
	panel.show()
	panel.custom_minimum_size = Vector2(620,440)
	# Compact conversation screens release this legacy minimum only for themselves.
	column.get_parent().custom_minimum_size = Vector2(580,400)
	column.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.get_parent().focus_mode = Control.FOCUS_NONE
	column.get_parent().follow_focus = false
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size",26)
	column.add_child(label)
func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	var previous: Button = null
	for child in column.get_children():
		if child is Button: previous = child
	column.add_child(button)
	if previous != null:
		previous.focus_neighbor_bottom = previous.get_path_to(button)
		previous.focus_next = previous.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_previous = button.get_path_to(previous)
	else:
		_focus_menu_button.call_deferred(weakref(button))
func _focus_menu_button(reference: WeakRef) -> void:
	var button := reference.get_ref() as Control
	if not is_instance_valid(button) or button.is_queued_for_deletion(): return
	if modal and button.is_inside_tree() and button.get_parent() == column and button.is_visible_in_tree():
		button.grab_focus()
func close_menu() -> void:
	if dialogue_voice != null: dialogue_voice.stop()
	_dialogue_source.clear()
	if is_instance_valid(dialogue_card): dialogue_card.hide()
	clear_speech()
	_service_menu_open = false
	if storefronts != null and storefronts.is_open(): storefronts.dismiss()
	if menu_closed.is_valid(): menu_closed.call()
	menu_closed = Callable()
	modal = false
	dialogue_open = false
	panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	world.player.input_locked = world.gameplay.health <= 0 or is_transition_blocked() or (desert != null and desert.busy()) or (passenger_transport != null and passenger_transport.riding) or (motocross != null and motocross.mounted) or (skate != null and skate.controls_locked())
	if fishing != null and fishing.controls_locked(): world.player.input_locked = true
	if amusement_park != null and amusement_park.active: world.player.input_locked = true
	if is_instance_valid(world.driving.car): world.driving.car.input_locked = is_transition_blocked() or (desert != null and desert.controls_locked())
func show_dialogue(dialogue_lines: Array, on_done := Callable()) -> void:
	lines = dialogue_lines.duplicate(true)
	dialogue_done = on_done
	_advance_dialogue()

func interrupt_dialogue() -> void:
	# Recovery discards unfinished words without completing their mission callback.
	lines.clear()
	dialogue_done = Callable()
	dialogue_open = false
	_dialogue_source.clear()
	if is_instance_valid(dialogue_voice): dialogue_voice.stop()
	if is_instance_valid(dialogue_card): dialogue_card.hide()
	clear_speech()
	if arrival != null: arrival.cancel_dialogue()
func _advance_dialogue() -> void:
	if dialogue_voice != null: dialogue_voice.stop()
	if lines.is_empty():
		close_menu()
		if dialogue_done.is_valid(): dialogue_done.call()
		return
	var line: Dictionary = lines.pop_front()
	var continuing_service := _service_menu_open
	_menu(str(line.get("speaker","")))
	_service_menu_open = continuing_service
	dialogue_open = true
	_dialogue_source = line.duplicate(true)
	_present_current_dialogue(true)

func _present_current_dialogue(restart_audio: bool) -> void:
	var line := _dialogue_source.duplicate(true)
	var speaker := str(line.get("voice_persona", str(line.get("speaker", "")).to_lower().split(" · ")[0]))
	var shown := VOICE.presentation(str(line.get("voice_text", line.get("message", ""))), speaker, "", "", str(line.get("character_id", "")), str(line.get("voice_section", "")))
	line["message"] = str(shown.message)
	if dialogue_voice != null and not (arrival != null and arrival.active):
		if restart_audio:
			dialogue_voice.stop()
			dialogue_voice.stream = shown.stream
			dialogue_voice.volume_db = VOICE.playback_volume(dialogue_voice.stream, -8.0 if speaker in ["maciota", "caller"] else 0.0)
			if dialogue_voice.stream != null: dialogue_voice.play()
	_present_dialogue_line(line)

func _present_dialogue_line(line: Dictionary) -> void:
	panel.hide()
	if not is_instance_valid(dialogue_card):
		dialogue_card = DIALOGUE_CARD.new()
		world.hud.add_child(dialogue_card)
		dialogue_card.advance_requested.connect(_advance_dialogue)
	dialogue_card.configure(str(line.get("speaker","")), str(line.get("message","")), get_node_or_null("/root/GameInput"))
	dialogue_card.focus_advance.call_deferred()

func cancel_mission() -> bool:
	if state.campaign.active_id.is_empty(): return false
	if not mission_world.cancel_attempt():
		show_message("Libere uma área para descarregar o guincho antes de cancelar.")
		save_game()
		return false
	close_menu()
	save_game()
	return true

func show_maciota_menu() -> void:
	_menu("Maciota")
	_compact_menu_size(Vector2(360, 310))
	_button("Ver missões", show_journal)
	_button("Informações", show_journal_information)
	_button("Encerrar conversa", close_menu)
	_menu_information("Guia do HUD em Configurações → Ajuda.", 13)
	_fit_compact_menu(column.get_child(0), Vector2(360, 310))

func _compact_menu_size(extent: Vector2) -> void:
	panel.set_meta("modal_preferred_size", extent)
	column.get_parent().custom_minimum_size = Vector2.ZERO
	column.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.get_parent().follow_focus = true
	panel.custom_minimum_size = extent
	panel.size = extent

func _fit_compact_menu(identity: Node, maximum: Vector2) -> void:
	# Wait for wrapping at the new width. Bound the result, keeping the existing
	# scroller for long records; short menus should not reserve empty space.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(identity) or identity.get_parent() != column or not panel.visible: return
	# Shared panel/margin chrome is 84 px; allow 16 px for focus and final wrap.
	var extent := Vector2(maximum.x, minf(maximum.y, column.get_combined_minimum_size().y + 100.0))
	panel.set_meta("modal_preferred_size", extent)
	panel.custom_minimum_size = extent
	panel.size = extent
	panel.position = ((panel.get_viewport_rect().size - panel.size) * .5).round()

## Read-only text must never look or behave like a mission action.
func _menu_information(text: String, font_size := 16, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", preload("res://ui/GameStyle.gd").TEXT if font_size >= 16 else preload("res://ui/GameStyle.gd").MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		label.focus_mode = Control.FOCUS_ALL
		var reading_focus := StyleBoxFlat.new()
		reading_focus.bg_color = Color.TRANSPARENT
		reading_focus.border_color = preload("res://ui/GameStyle.gd").ACCENT
		reading_focus.border_width_left = 2
		label.add_theme_stylebox_override("focus", reading_focus)
	(parent if parent != null else column).add_child(label)
	return label

func show_journal_information() -> void:
	_menu("Informações")
	_compact_menu_size(Vector2(480, 360))
	column.get_parent().follow_focus = true
	var records := VBoxContainer.new()
	records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records.add_theme_constant_override("separation", 14)
	column.add_child(records)
	var village: Dictionary = {}
	if urban_operations != null and is_instance_valid(urban_operations.village_quest): village = urban_operations.village_quest.data
	var entries: Array = JOURNAL_ARCS.lines(state.world_state, state.campaign.snapshot(), village)
	for line in entries: _menu_information(str(line), 16, records)
	if entries.is_empty(): _menu_information("Nenhuma informação registrada ainda.", 16, records)
	var secret_file: Variant = urban_operations.get("secret_file") if urban_operations != null else null
	if is_instance_valid(secret_file) and secret_file.available():
		_button("Arquivo de Vicente", secret_file.open_from_journal)
	_button("Ver missões", show_journal)
	_button("Fechar", close_menu)
	# Read the first record before navigating the actions below the records.
	var scroll: ScrollContainer = column.get_parent()
	if records.get_child_count() > 0: records.get_child(0).grab_focus.call_deferred()
	scroll.set_deferred("scroll_vertical", 0)
	_fit_compact_menu(column.get_child(0), Vector2(480, 360))

func show_journal() -> void:
	if mountain_activities != null and mountain_activities.busy():
		mountain_activities.show_journal()
		return
	_menu("Missões")
	_compact_menu_size(Vector2(480, 360))
	if mountain_activities != null: _button("Atividades da montanha", mountain_activities.show_journal)
	if state.campaign.active_id != "":
		_menu_information("OBJETIVO ATUAL", 13)
		_menu_information(mission_world.objective())
		_button("Cancelar missão",cancel_mission)
	else:
		for id in state.campaign.available_missions():
			_button(str(MISSIONS.MISSIONS[id].title),func():
				if state.intro.stage != "complete": show_message("Converse primeiro com Maciota."); close_menu(); return
				if not mission_world.begin(id):
					close_menu()
					return
				if not dialogue_open: close_menu())
	# Cadeia da Helena: escolher a linha põe objetivo e marcador nela. As histórias de JournalArcs e o
	# arquivo de Vicente ficam em "Informações" (show_journal_information).
	if helena_act1 != null and state.campaign.active_id == "":
		for entry in helena_act1.journal_entries():
			var act1_id: String = entry.id
			_button(entry.text, func():
				helena_act1.focus(act1_id)
				close_menu())
	_button("Informações", show_journal_information)
	_button("Voltar",close_menu)
	_fit_compact_menu(column.get_child(0), Vector2(480, 360))
func show_inventory() -> void:
	if field_inventory != null:
		field_inventory.open()
		return
	_menu(String(TranslationServer.translate("Inventário · R$ %d"))%state.economy.balance)
	for id in WEAPONS.ORDER:
		if state.owns_weapon(id):
			var stored: bool = not state.economy.can_carry_weapon(id)
			_button(str(WEAPONS.WEAPONS[id].label)+(" · No porta-malas" if stored else ""),func():
				if not state.economy.can_carry_weapon(id):
					close_menu()
					show_message("Selecione esta arma no porta-malas da Monaliza.")
					return
				close_menu()
				state.equip_weapon(id))
	if state.economy.inventory.get("first_aid",0)>0:
		_button("Usar primeiros socorros",func():
			if world.gameplay.heal(40): state.economy.consume_item("first_aid")
			close_menu(); save_game())
	_button("Configurações",show_settings)
	_button("Voltar",close_menu)
func show_services(service: String) -> void:
	if _service_threatened(): return
	_show_services_available(service)
	_service_menu_open = modal
	if modal and panel.visible: preload("res://ui/ShopPresentation.gd").apply(panel)

func _show_services_available(service: String) -> void:
	if service == "supermarket":
		preload("res://runtime/SupermarketShop.gd").open(self)
		return
	if service == "ski_rental":
		mountain_progression.show_services()
		return
	if services.perform(service): return
	if service in ["weapons","ammunation","gunshop"]:
		if state.place_id == "harbor_ammunation" and storefronts.open_weapons(): return
		_show_shop("weapon")
		return
	if service == "clothing":
		if state.place_id == "harbor_clothing" and storefronts.open_clothing(): return
		_show_shop("outfit")
		return
	# Vehicle repair belongs to its physical service. Maciota is handled above
	# by Services.perform(); Northgate admits the occupied car in its exterior
	# bay. This fallback must never charge or clear wanted state remotely.
	if service == "garage":
		show_message("Use a bancada da garagem para cuidar da Monaliza.")
		return
	if service == "auto_service":
		show_message("Leve o veículo até a baia externa da Northgate.")
		return
func _show_shop(category: String) -> void:
	_menu("R$ %d"%state.economy.balance)
	for item in state.economy.storefront(category):
		if category == "weapon" and item.id == "katana" and not item.unlocked: continue
		var label := str(item.get("name",item.get("label",item.id)))
		_button(label+(" · Equipar" if item.owned else " · R$ %d"%item.price),func():
			if not item.owned:
				var result: Dictionary = state.economy.purchase(category,item.id,_transaction())
				if not result.ok: show_message("Compra indisponível: "+str(result.reason)); close_menu(); return
			if category == "weapon": state.equip_weapon(item.id)
			else: preload("res://runtime/OutfitDisguise.gd").equip(self, item.id, true)
			close_menu(); save_game())
	if category == "weapon":
		_button("Personalizar arma equipada",_show_customization)
		_button("Munição para arma equipada",func():
			var purchased: bool = state.economy.buy_ammo(state.equipped_weapon,30,_transaction())
			show_message("Munição comprada." if purchased else "Compra indisponível.")
			close_menu(); save_game())
		if world.gameplay.armor >= 100:
			_button("Proteção completa",func():
				show_message("O colete já está completo.")
				close_menu())
		else:
			_button("Colete · R$ 500",func():
				var result: Dictionary = state.economy.purchase_body_armor(world.gameplay.armor,100,_transaction())
				if result.ok:
					world.gameplay.armor = int(result.armor)
					show_message("Colete equipado.")
				else:
					show_message("Proteção completa." if result.reason == "protection_full" else "Compra indisponível.")
				close_menu()
				if result.ok: save_game())
	_button("Voltar",close_menu)
	preload("res://ui/ShopPresentation.gd").apply(panel)
func _show_customization() -> void:
	var catalog = preload("res://gameplay/WeaponCustomization.gd")
	var id: String = state.equipped_weapon
	if id == "katana":
		_show_saber_customization()
		return
	_menu("Personalizar · "+str(WEAPONS.WEAPONS[id].label))
	for part in catalog.PARTS:
		if not catalog.supports(id,part): continue
		var data: Dictionary = catalog.PARTS[part]
		var owned: bool = catalog.owns(world.gameplay.customization,id,part)
		var selected: bool = catalog.selected(world.gameplay.customization,id,data.slot) == part
		var suffix := " · Remover" if selected else (" · Instalar" if owned else " · R$ %d"%data.price)
		_button(str(data.label)+suffix,func():
			var ok: bool = world.gameplay.install_attachment(id,part,false) if selected else world.gameplay.buy_attachment(id,part)
			if not ok: show_message("Personalização indisponível.")
			save_game()
			_show_customization())
	_button("Voltar",func(): _show_shop("weapon"))
	preload("res://ui/ShopPresentation.gd").apply(panel)
func _show_saber_customization() -> void:
	_menu("Katana")
	panel.hide()
	var custom_panel := preload("res://runtime/TakeshiSaberPanel.gd").new()
	custom_panel.configure(self)
	world.hud.add_child(custom_panel)
	custom_panel.closed.connect(func(): _show_shop("weapon"))
	menu_closed = func():
		if is_instance_valid(custom_panel): custom_panel.queue_free()
func _transaction() -> String:
	action_serial += 1
	return "%d_%d_%d"%[Time.get_unix_time_from_system(),Time.get_ticks_usec(),action_serial]
func apply_outfit() -> void:
	# Palette integration is applied by the original Dante outfit shader adapter.
	var outfit: String = state.economy.outfit
	if mountain_progression != null and mountain_progression.data.rental: outfit = mountain_progression.suit_outfit()
	if world.player.has_method("set_outfit"): world.player.set_outfit(outfit)
	preload("res://activities/amusement_park/AmusementParkCosmetics.gd").apply(world.player,state.world_state)
	preload("res://assets/outfits/DanteAccessories.gd").apply(world.player,preload("res://systems/wardrobe/AccessoryState.gd").equipped(state.world_state))

func advance_residence_time(target: float) -> bool:
	if target not in [.36,.84] or not can_rest_at_residence(): return false
	return advance_residence_minutes(maxi(1,roundi(fposmod(target-float(weather.time_of_day),1.0)*1440.0)))

func can_rest_at_residence() -> bool:
	if controller.save_invalid or weather == null: return false
	if state.region_id != "harbor" or not activities.residence.can_enter(state.place_id) or state.place_id.is_empty(): return false
	if not is_instance_valid(room) or world.driving.occupied or world.gameplay.health <= 0 or world.gameplay.stars > 0: return false
	if not room.interaction_points.has("time") or world.player.position.distance_to(room.interaction_points.time) >= .95: return false
	if not state.campaign.active_id.is_empty() or not activities.can_rest() or arrival.active: return false
	return not is_transition_blocked()

func advance_residence_minutes(minutes: int) -> bool:
	if minutes < 1 or minutes > 1440 or not can_rest_at_residence(): return false
	var elapsed := float(minutes)/1440.0*600.0
	activities.advance_time(elapsed)
	var target := fposmod(float(weather.time_of_day)+float(minutes)/1440.0,1.0)
	var days_advanced := floori(float(weather.time_of_day)+float(minutes)/1440.0)
	if days_advanced>0: state.world_state.moon_day = weather.moon_day() + days_advanced
	weather.time_of_day = target
	state.world_state.time = target
	weather._update()
	return true
func show_settings() -> void:
	close_menu()
	world.pause_panel.pause_game()
	world.pause_panel.open_settings()
func show_controls() -> void:
	show_settings()
	world.pause_panel.settings._select_tab(2)
func show_map() -> void:
	_menu("Mapa")
	var map = preload("res://ui/v2/WorldMap.gd").new()
	map.controller = controller
	world.hud.add_child(map)
	panel.hide()
	menu_closed = map.queue_free
func _update_reward() -> void:
	if room == null or room == world.maciota_place: return
	for point in room.reward_points:
		var data: Dictionary = point.get("reward",{})
		if not data.is_empty(): room.set_reward_available(not state.world_state.rewards.has(data.id),data.id)
func _collect_reward(source: Node3D) -> void:
	if not is_instance_valid(source) or not source.is_visible_in_tree() or world.gameplay.health <= 0: return
	for reward in source.reward_points:
		var data: Dictionary = reward.get("reward",{})
		if data.is_empty(): continue
		if state.world_state.rewards.has(data.id):
			source.set_reward_available(false,data.id)
			continue
		var point: Vector3 = reward.get("position",Vector3.ZERO)
		if world.player.global_position.distance_to(point) > .8: continue
		if _reward_failures.has(data.id): continue
		var result: Dictionary = state.economy.grant_world_reward(data)
		if not result.ok:
			var reason := str(result.get("reason","grant_failed"))
			var item_name := str(WEAPONS.WEAPONS.get(str(data.get("item", "")), {}).get("label", "Item")) if data.get("kind", "") == "weapon" else "Recompensa"
			var explanation: String = {"already_owned":"Você já possui esta arma.", "wallet_full":"Carteira cheia.", "inventory_full":"Inventário cheio.", "ammo_full":"Munição no limite.", "invalid_reward":"Não foi possível coletar este item: dados inválidos.", "transaction_conflict":"Coleta bloqueada por conflito no registro da recompensa."}.get(reason, "Não foi possível concluir a coleta.")
			show_message("%s: %s" % [item_name, explanation])
			_reward_notice_id = str(data.id)
			_reward_failures[data.id] = {"source":weakref(source), "position":point, "region":state.region_id, "place":state.place_id}
			continue
		if not state.world_state.rewards.has(data.id): state.world_state.rewards.append(data.id)
		if result.get("changed",true):
			REWARD_AUDIO.play(self,REWARD_AUDIO.kind_for_reward(str(data.get("kind",""))))
		source.set_reward_available(false,data.id,true)
		# Coleta sem aviso na tela (como os drops de combate); só a falha avisa.
		save_game()
func _refresh_reward_feedback() -> void:
	# Uma falha por aproximação; não renove o aviso a cada tick nem após sair.
	for id in _reward_failures.keys():
		var failure: Dictionary = _reward_failures[id]
		var source = failure.source.get_ref()
		if is_instance_valid(source) and source.is_visible_in_tree() and failure.region == state.region_id and failure.place == state.place_id and not world.driving.occupied and world.player.global_position.distance_to(failure.position) <= .8: continue
		_reward_failures.erase(id)
		if _reward_notice_id == id:
			_reward_notice_id = ""
			notice_time = 0.0
			notice.text = ""
			notice.hide()
## M06-C "Turno da noite" (VerticeNightShift), filho da Vértice em PortLogistics.
func _vertice_night() -> Node:
	if urban_operations == null or not is_instance_valid(urban_operations.cargo_handling): return null
	var depot: Variant = urban_operations.cargo_handling.get("depot")
	if not is_instance_valid(depot): return null
	var shift: Variant = depot.get("night_shift")
	return shift if is_instance_valid(shift) else null

func save_block_reason() -> String:
	if world.player.get_meta("player_air_busy", false): return "Aguarde terminar o salto ou a queda para salvar."
	if world.get_meta("developer_mode_active",false): return "Desligue o modo desenvolvedor para salvar."
	if upside_world != null and upside_world.busy(): return "Aguarde a visão passar."
	if arcade != null and arcade.active: return "Saia do fliperama para salvar."
	if amusement_park != null and amusement_park.active: return "Termine o passeio para salvar."
	if fishing != null:
		var fishing_reason: String = fishing.save_block_reason()
		if not fishing_reason.is_empty(): return fishing_reason
	if coastal_lookout != null and coastal_lookout.active: return "Saia do binóculo para salvar."
	if building_entrance != null and building_entrance.falling: return "Aguarde chegar ao chão."
	if service_roofs != null and service_roofs.falling: return "Aguarde chegar ao chão."
	if regional_coach != null:
		var coach_reason: String = regional_coach.save_block_reason()
		if not coach_reason.is_empty(): return coach_reason
	if railway != null:
		var railway_reason: String = railway.save_block_reason()
		if not railway_reason.is_empty(): return railway_reason
	if armored_transport != null:
		var armored_reason: String = armored_transport.save_block_reason()
		if not armored_reason.is_empty(): return armored_reason
	if mountain_activities != null:
		var pack_reason: String = mountain_activities.save_block_reason()
		if not pack_reason.is_empty(): return pack_reason
	if mining != null:
		var mining_reason: String = mining.save_block_reason()
		if not mining_reason.is_empty(): return mining_reason
	if desert != null:
		var desert_reason: String = desert.save_block_reason()
		if not desert_reason.is_empty(): return desert_reason
	if jessica != null and jessica.riding: return "Aguarde Jessica estacionar para salvar."
	var vertice_night: Node = _vertice_night()
	if vertice_night != null:
		var night_reason: String = vertice_night.save_block_reason()
		if not night_reason.is_empty(): return night_reason
	if skate != null and skate.controls_locked(): return "Desça do skate e se recupere para salvar."
	if controller.save_invalid: return controller.save_block_text()
	if is_instance_valid(room) and room.has_method("start_game") and room.get("game_active") == true: return "Encerre a partida para salvar."
	if motocross != null and motocross.mounted: return "Termine a corrida ou desça da moto para salvar."
	if world.gameplay.health <= 0: return "Salvar indisponível enquanto o jogador estiver morto."
	if world.gameplay.stars > 0: return "Perca todas as estrelas da polícia para salvar."
	if not state.campaign.active_id.is_empty() or state.intro.stage not in ["meet_maciota", "complete"]:
		return "Conclua ou encerre a missão para salvar um checkpoint."
	if activities != null and not activities.can_rest(): return "Encerre a corrida ou o contrato de guincho para salvar."
	if mountain_progression != null and not mountain_progression.race.mode.is_empty(): return "Encerre a prova de esqui para salvar."
	if urban_operations != null:
		var quest = urban_operations.get("village_quest")
		if is_instance_valid(quest) and quest.data.started and not quest.data.completed:
			return "Conclua a missão de Tonico para salvar um checkpoint."
	if urban_operations != null and urban_operations.freight != null and urban_operations.freight.active_bay >= 0:
		return "Encerre a entrega de carga para salvar."
	if is_transition_blocked(): return "Conclua a chegada, o resgate ou a transição para salvar."
	if passenger_transport != null and passenger_transport.riding: return "Aguarde o desembarque para salvar."
	return ""

func _queue_checkpoint() -> void:
	if controller.no_save or controller.save_invalid: return
	if _checkpoint_retry == null:
		_checkpoint_retry = Timer.new()
		_checkpoint_retry.process_mode = Node.PROCESS_MODE_PAUSABLE
		_checkpoint_retry.wait_time = 1.0
		_checkpoint_retry.one_shot = true
		add_child(_checkpoint_retry)
		_checkpoint_retry.timeout.connect(func(): save_game())
	# Only one pending request; capture fresh state once saving becomes safe.
	if _checkpoint_retry.is_stopped(): _checkpoint_retry.start()

func _save_indicator() -> Control:
	var indicator := get_node_or_null("SaveFeedback/Indicator")
	if indicator == null:
		var feedback := CanvasLayer.new()
		feedback.name = "SaveFeedback"
		feedback.layer = 125
		add_child(feedback)
		indicator = preload("res://ui/SaveIndicator.gd").new()
		indicator.name = "Indicator"
		feedback.add_child(indicator)
	return indicator

## Autosave tem ~170 chamadores e cada gravação faz ~25 snapshots e quatro validações completas:
## o span dá nome ao pico no log de quadros lentos (antes aparecia sem dono).
func save_game(manual := false) -> bool:
	var began := STALL_WORK_READY.begin()
	var saved := _save_game(manual)
	STALL_WORK_READY.finish_slow("session.save_game", began, 4000, self)
	return saved

func _save_game(manual: bool) -> bool:
	var blocked := save_block_reason()
	if not blocked.is_empty():
		if manual: _save_indicator().reject(blocked)
		else: _queue_checkpoint()
		return false
	state.world_state.erase("pedestrian")
	# Menus hold input too; a supported, free on-foot position remains saveable.
	if state.place_id.is_empty() and not world.driving.occupied and position_clear(world.player.position):
		var point: Vector3 = world.player.position
		state.world_state.pedestrian = {"region":state.region_id,"position":[point.x,point.y,point.z]}
	if personal_car != null: personal_car.refresh()
	if activities != null: activities.refresh_achievements()
	if desert != null: desert.write_snapshot()
	if mining != null: mining.write_snapshot()
	controller.capture_player_vehicle()
	if desert!=null and is_instance_valid(desert.drag) and is_instance_valid(desert.drag.loaner_controller): desert.drag.loaner_controller.prepare_save()
	if cold != null: state.world_state.cold = cold.snapshot()
	if wine != null: state.world_state.wine_cellar = wine.snapshot()
	if garage_rewards != null: state.world_state.garage_rewards = garage_rewards.snapshot()
	if arrival != null: state.world_state.arrival = arrival.snapshot()
	if robberies != null: state.world_state.robberies = robberies.snapshot()
	if services != null: state.world_state.services = services.snapshot()
	if activities != null: state.world_state.activities = activities.snapshot()
	if motocross != null: state.world_state.motocross = motocross.snapshot()
	if skate != null: state.world_state.skate = skate.snapshot()
	if mountain_progression != null: state.world_state.mountain_progression = mountain_progression.snapshot()
	if mountain_activities != null: mountain_activities.write_snapshot()
	if mission_world != null: state.world_state.mission_world = mission_world.snapshot()
	if jessica != null: state.world_state.jessica_vehicle = jessica.vehicle_snapshot()
	if urban_operations != null:
		var urban_snapshot: Dictionary = urban_operations.snapshot()
		# Estado urbano no meio de uma troca: recusa só esta gravação; o próximo pedido de
		# salvar tenta de novo. Antes um único instante assim desligava o salvamento pelo
		# resto da sessão, em silêncio. Sem fila de 1 s: cada tentativa refaz todos os snapshots.
		if not preload("res://gameplay/urban_v1/UrbanOperations.gd").validate_snapshot(urban_snapshot):
			last_save_error = "Estado urbano incompleto; salvamento adiado."
			push_warning(last_save_error)
			if manual: _save_indicator().reject(last_save_error)
			return false
		state.world_state.urban_operations = urban_snapshot
	if controller.no_save: return true
	state.combat_state = world.gameplay.snapshot()
	var result: Error = controller.store.save(state)
	if _checkpoint_retry != null: _checkpoint_retry.stop()
	if result != OK:
		last_save_error = String(TranslationServer.translate("Não foi possível salvar (%d).")) % result
		_save_indicator().reject(last_save_error)
		return false
	last_save_error = ""
	_save_indicator().acknowledge()
	return true
func load_game() -> void:
	if upside_world != null and upside_world.busy() and upside_world._released:
		show_message("Aguarde a conclusão da transição para carregar.")
		return
	# Ilusão, pesca, mirante e parque terminam antes das recusas abaixo, como sempre foi.
	_cancel_for(&"load_1")
	if desert != null and desert.busy(): show_message("Encerre a prova para carregar."); return
	if jessica != null and jessica.riding:
		show_message("Aguarde Jessica estacionar para carregar."); return
	if is_transition_blocked():
		show_message("Aguarde a conclusão da transição para carregar."); return
	if passenger_transport != null and passenger_transport.riding:
		show_message("Aguarde o desembarque para carregar."); return
	if world.driving.occupied: show_message("Saia do veículo para carregar."); return
	_cancel_for(&"load_2")
	var result := get_tree().reload_current_scene()
	if result != OK: show_message(String(TranslationServer.translate("Não foi possível carregar o jogo (%d).")) % result)
func return_to_main_menu() -> void:
	if upside_world != null and upside_world.busy() and upside_world._released:
		show_message("Aguarde a conclusão da transição.")
		return
	# Deserto e mineração já são cancelados quando o menu recusa abaixo, como sempre foi.
	_cancel_for(&"menu_1")
	if is_transition_blocked() or (passenger_transport != null and passenger_transport.riding):
		show_message("Aguarde a conclusão da chegada, do resgate ou da transição.")
		return
	_cancel_for(&"menu_2")
	var launch = get_node_or_null("/root/V2Launch")
	if launch != null: launch.direct_start_consumed = true
	var was_paused := get_tree().paused
	get_tree().paused = false
	var result := get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
	if result != OK:
		get_tree().paused = was_paused
		show_message("Não foi possível abrir o menu principal.")

func _show_v1_death_presentation() -> void:
	if is_instance_valid(death_presentation): death_presentation.queue_free()
	death_presentation = CanvasLayer.new()
	death_presentation.name = "WastedPresentation"
	death_presentation.layer = 120
	var audio := AudioStreamPlayer.new()
	audio.name = "WastedAudio"
	audio.stream = V1_DEATH_AUDIO.stream()
	audio.volume_db = 0.0
	death_presentation.add_child(audio)
	var tint := ColorRect.new()
	tint.name = "DeathTint"
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.48,0.035,0.055,0.0)
	tint.mouse_filter = Control.MOUSE_FILTER_STOP
	death_presentation.add_child(tint)
	var label := Label.new()
	label.name = "WastedLabel"
	label.text = "SE FODEU"
	if bank_death_loss>0: label.text+=String(TranslationServer.translate("\n− R$ %d · Saque perdido"))%bank_death_loss
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size",42)
	label.add_theme_color_override("font_color",Color(1.0,0.94,0.87))
	label.add_theme_color_override("font_outline_color",Color(0.08,0.01,0.015))
	label.add_theme_constant_override("outline_size",5)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",3)
	label.add_theme_constant_override("shadow_offset_y",3)
	label.modulate.a = 0.0
	death_presentation.add_child(label)
	get_tree().root.add_child(death_presentation)
	audio.play()
	label.pivot_offset = get_viewport().get_visible_rect().size*.5
	label.scale = Vector2(1.35,1.35)
	var intro := create_tween().set_ignore_time_scale(true).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	intro.tween_property(tint,"color:a",.66,.35)
	intro.tween_property(label,"modulate:a",1.0,.35)
	intro.tween_property(label,"scale",Vector2.ONE,.35)
	await _hold_recovery_presentation(death_presentation)

func _show_v1_arrest_presentation() -> void:
	if is_instance_valid(death_presentation): death_presentation.queue_free()
	death_presentation = CanvasLayer.new()
	death_presentation.name = "ArrestPresentation"
	death_presentation.layer = 120
	var tint := ColorRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.1,0.2,0.8,0.45)
	tint.mouse_filter = Control.MOUSE_FILTER_STOP
	death_presentation.add_child(tint)
	var label := Label.new()
	label.name = "ArrestLabel"
	label.text = "PRESO"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size",46)
	label.add_theme_color_override("font_color",Color(0.2,0.6,1.0))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",3)
	label.add_theme_constant_override("shadow_offset_y",3)
	death_presentation.add_child(label)
	get_tree().root.add_child(death_presentation)
	label.modulate.a = 0.0
	var intro := create_tween().set_ignore_time_scale(true)
	intro.tween_property(label, "modulate:a", 1.0, 0.35)
	await _hold_recovery_presentation(death_presentation)

func _hold_recovery_presentation(presentation: CanvasLayer) -> void:
	if not _recovery_slow_motion:
		_recovery_time_scale = Engine.time_scale
		_recovery_slow_motion = true
	Engine.time_scale = _recovery_time_scale * 0.2
	# Wall-clock timing keeps the message readable despite the slowed world.
	await get_tree().create_timer(2.4, false, false, true).timeout
	if not is_instance_valid(presentation) or presentation != death_presentation: return
	var blackout := ColorRect.new()
	blackout.name = "RecoveryBlackout"
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout.color = Color(0, 0, 0, 0)
	blackout.mouse_filter = Control.MOUSE_FILTER_STOP
	presentation.add_child(blackout)
	var fade := create_tween().set_ignore_time_scale(true)
	fade.tween_property(blackout, "color:a", 1.0, 0.8)
	await fade.finished
	if presentation != death_presentation: return
	_restore_recovery_time_scale()

func _restore_recovery_time_scale() -> void:
	if not _recovery_slow_motion: return
	Engine.time_scale = _recovery_time_scale
	_recovery_slow_motion = false

func _finish_recovery_presentation() -> void:
	_restore_recovery_time_scale()
	var presentation := death_presentation
	if not is_instance_valid(presentation): return
	# Remove the message behind the opaque cover, then reveal the settled camera.
	for child in presentation.get_children():
		if child is Control and child.name != "RecoveryBlackout": child.hide()
	await get_tree().create_timer(0.3, false, false, true).timeout
	if not is_instance_valid(presentation) or presentation != death_presentation: return
	var fade := create_tween().set_ignore_time_scale(true)
	fade.tween_property(presentation.get_node("RecoveryBlackout"), "color:a", 0.0, 1.0)
	await fade.finished
	if is_instance_valid(presentation) and presentation == death_presentation:
		death_presentation = null
		presentation.queue_free()

func _exit_tree() -> void:
	_restore_recovery_time_scale()
	if is_instance_valid(death_presentation): death_presentation.queue_free()


func _on_arrest() -> void:
	if arrest_pending or rescue_pending: return
	_cancel_for(&"arrest_1")
	arrest_pending = true
	# Gameplay's arrest signal already owns this lock; illusion cleanup must
	# not release it while the custody presentation is running.
	world.player.input_locked = true
	_cancel_for(&"arrest_2")
	prompt.text = ""
	_cancel_for(&"arrest_3")
	# Service/mission teardown may restore an earlier input snapshot.
	# Custody takes final ownership before yielding to the presentation.
	world.player.input_locked = true
	await _show_v1_arrest_presentation()
	if not arrest_pending or not is_inside_tree(): return
	await _respawn()

func _on_death() -> void:
	_cancel_for(&"death_1")
	if rescue_pending: return
	_cancel_for(&"death_2")
	# Fora do registro: a resposta é o saque perdido, mostrado no "SE FODEU".
	bank_death_loss = robberies.player_died() if robberies != null else 0
	# The old arrest coroutine must not select custody or consume this rescue.
	arrest_pending = false
	# Um resgate que não é desta morte pode estar em curso: o _respawn da própria prisão (delegacia
	# escolhida, cortina abrindo; a rendição não para as balas de civis hostis) ou o da chegada.
	# Ele terminava depois desta morte, limpava rescue_pending, cobrava a multa e deixava o corpo
	# morto e travado na delegacia; esta morte via rescue_pending falso e pulava o próprio resgate.
	# Soltar a transição dele o faz parar no próximo _owns_transition, sem mexer nas bandeiras nem
	# cobrar nada, e deixa o _respawn desta morte começar (morte prevalece, como na apresentação).
	if respawn_busy:
		respawn_busy = false
		if transition_kind == "rescue": _finish_transition(transition_generation)
	# Falling out of the world and an invalid restored position reach this path
	# directly, without damage_player. Establish the same dead state before any
	# boarding cleanup or death presentation reads it.
	world.gameplay.health = 0
	_cancel_for(&"death_3")
	world.player.input_locked = true
	world.player.on_player_death()
	# Damage may have posed death before Driving restored the on-foot capsule.
	# Reassert the dead body's collision after cancelling that presentation.
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.set_physics_process(false)
	world.gameplay.changed.emit()
	var from_interior: bool = not state.place_id.is_empty() or is_instance_valid(room)
	rescue_camera_heading = saved_heading if from_interior else world.camera.heading
	rescue_camera_size = saved_size if from_interior else world.camera.target_size
	rescue_pending = true
	prompt.text = ""
	world.hud.refresh_from_state()
	_cancel_for(&"death_4")
	await _show_v1_death_presentation()
	if not rescue_pending or not is_inside_tree(): return
	await _respawn()

func _respawn() -> void:
	_cancel_for(&"rescue_1")
	if respawn_busy: return
	var token := _begin_transition("rescue")
	if token < 0:
		show_message("Aguarde a transição atual e tente novamente.")
		return
	respawn_busy = true
	var arrested := arrest_pending
	var fallback: Vector3 = controller.region.spawn_position+Vector3.UP*.1
	var destination := fallback
	# Morte acorda na porta do Bay Medical, prisão sai pela delegacia (RecoveryPenalty).
	var recovery_place: Dictionary = PLACES.get_definition(RECOVERY_PENALTY.place_for(state.region_id, arrested))
	if not recovery_place.is_empty(): destination = recovery_place.return_position+Vector3.UP*.1
	controller.region.set_focus(destination)
	# Na serra o ponto de resgate é o spawn_position, no tabuleiro da ponte: o piso é da conexão.
	controller.prepare_connection_at(destination)
	if cold != null: cold.prepare_collision_at(destination)
	for i in 3:
		await get_tree().physics_frame
		if not _owns_transition(token): return
	if not position_clear(destination) and destination != fallback:
		# Porta ocupada (ambulância, viatura estacionada): usa o ponto de resgate da região.
		destination = fallback
		controller.region.set_focus(destination)
		controller.prepare_connection_at(destination)
		if cold != null: cold.prepare_collision_at(destination)
		for i in 3:
			await get_tree().physics_frame
			if not _owns_transition(token): return
	if not position_clear(destination):
		respawn_busy = false
		_finish_transition(token)
		_restore_recovery_time_scale()
		if is_instance_valid(death_presentation): death_presentation.queue_free()
		death_presentation = null
		_menu("Local de custódia ocupado. Aguarde e tente novamente." if arrest_pending else "Local de resgate ocupado. Aguarde e tente novamente.")
		_button("Tentar novamente",_respawn)
		return
	if world.driving.occupied:
		world.driving.occupied = false
		if is_instance_valid(world.driving.car):
			world.driving.car.controlled = false
			world.driving.car.external_input = false
			world.driving.car.throttle_input = 0
	_cancel_for(&"rescue_2")
	if is_instance_valid(room):
		if room == world.maciota_place: room.set_interior_active(false)
		else: room.queue_free()
	_clear_service_npcs()
	room = null
	state.set_location(state.region_id)
	world.gameplay.respawn()
	world.player.respawn_player()
	_cancel_for(&"rescue_3")
	sync_dispatch_location()
	if cold != null: cold.recover_after_rescue()
	if wine != null: wine.recover()
	world.player.teleport(destination)
	_sync_location_presentation()
	world.player.collision_layer = 2
	world.player.collision_mask = 7
	world.player.show()
	world.player.set_physics_process(true)
	world.camera.target = world.player
	world.camera.offset = world.camera.EXTERIOR_OFFSET
	world.camera.heading = rescue_camera_heading
	world.camera.target_size = rescue_camera_size
	world.camera.size = rescue_camera_size
	world.camera.locked = false
	world.camera.initialized = false
	world.camera._process(1)
	_refresh_routine_context()
	world.player.input_locked = true
	await _finish_recovery_presentation()
	if not _owns_transition(token): return
	rescue_pending = false
	arrest_pending = false
	respawn_busy = false
	_finish_transition(token)
	close_menu()
	# Só depois do resgate concluído: "Tentar novamente" não pode cobrar duas vezes.
	var notices: Array[String] = []
	if bank_death_loss>0:
		notices.append(String(TranslationServer.translate("Assalto fracassado: − R$ %d"))%bank_death_loss)
		bank_death_loss=0
	var penalty_text := RECOVERY_PENALTY.message(RECOVERY_PENALTY.apply(state.economy, arrested), arrested)
	if not penalty_text.is_empty(): notices.append(penalty_text)
	if not notices.is_empty():
		show_message(" · ".join(notices))
		world.gameplay.changed.emit()
	save_game()
