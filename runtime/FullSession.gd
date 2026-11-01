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
## Blocos extraídos em 31/10 para o arquivo caber na leitura (ver o cabeçalho de cada um). O estado segue
## aqui; as funções antigas ficam como delegações de uma linha para não mudar quem chama por nome.
const SESSION_MENUS := preload("res://runtime/SessionMenus.gd")
var _menus: SESSION_MENUS = SESSION_MENUS.new(self)
const SESSION_SAVING := preload("res://runtime/SessionSaving.gd")
var _saving: SESSION_SAVING = SESSION_SAVING.new(self)
const SESSION_RECOVERY := preload("res://runtime/SessionRecovery.gd")
var _recovery: SESSION_RECOVERY = SESSION_RECOVERY.new(self)
const SESSION_REWARDS := preload("res://runtime/SessionRewards.gd")
var _rewards: SESSION_REWARDS = SESSION_REWARDS.new(self)
const SESSION_TRANSITION_RULES := preload("res://runtime/SessionTransitionRules.gd")
var _transition_rules: SESSION_TRANSITION_RULES = SESSION_TRANSITION_RULES.new(self)
const SESSION_GARAGE := preload("res://runtime/SessionGarage.gd")
var _garage: SESSION_GARAGE = SESSION_GARAGE.new(self)
const SESSION_INTERACTION := preload("res://runtime/SessionInteraction.gd")
var _interaction: SESSION_INTERACTION = SESSION_INTERACTION.new(self)
const SESSION_PLACES := preload("res://runtime/SessionPlaces.gd")
var _places: SESSION_PLACES = SESSION_PLACES.new(self)
const SESSION_STARTUP := preload("res://runtime/SessionStartup.gd")
var _startup: SESSION_STARTUP = SESSION_STARTUP.new(self)
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
## Portas trancadas das casas (lockpick); ver runtime/DoorLockpick.gd.
var door_lockpick: Node
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

## Fachada de leitura do jogador (item 1 de docs/analise-arquitetura-codigo-20261101.md): o resto
## do jogo lê posição, vida e carro por aqui em vez de session.world.player/gameplay/driving.
## Sem guarda de nulo de propósito: a cadeia antiga também quebrava com world/player nulo, e
## a guarda custaria a cada chamada (várias são por quadro). Só leitura; escrita continua
## pela cadeia. Os dublês de sessão dos testes repetem estes cinco métodos.
func player_position() -> Vector3: return world.player.global_position
func player_local_position() -> Vector3: return world.player.position
func player_health() -> float: return world.gameplay.health
func player_in_vehicle() -> bool: return world.driving.occupied
## Sem tipo de retorno: o carro pode já ter sido liberado e os chamadores conferem com
## is_instance_valid; retorno tipado acusaria "instância liberada" antes disso.
func player_vehicle(): return world.driving.car

func _keeps_interaction_access(id: String) -> bool: return _transition_rules._keeps_interaction_access(id)
func _uses_walkup_access(id: String) -> bool: return _transition_rules._uses_walkup_access(id)
func _arrival_sequence_blocked() -> bool: return _transition_rules._arrival_sequence_blocked()
func is_transition_blocked() -> bool: return _transition_rules.is_transition_blocked()
func has_position_transition() -> bool: return _transition_rules.has_position_transition()
func blocks_driving_change() -> bool: return _transition_rules.blocks_driving_change()
func allows_saved_driver_animation() -> bool: return _transition_rules.allows_saved_driver_animation()

## Quem para em cada evento da sessão: a tabela (com a explicação) mora em runtime/SessionTransitionRules.gd.
## Fica reexportada aqui com o mesmo nome: test_session_cleanup_registry lê o mapa de constantes deste script.
const CANCEL_STEPS := SESSION_TRANSITION_RULES.CANCEL_STEPS

## Roda uma etapa de CANCEL_STEPS. Devolve false só quando um passo abort_if_active recusou.
func cancel_for(stage: StringName) -> bool:
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

func begin_transition(kind: String, _vehicle := false) -> int:
	if not transition_kind.is_empty() or (controller != null and controller.travel_busy): return -1
	if not cancel_for(&"transition"): return -1
	transition_generation += 1
	transition_kind = kind
	# Consumidores antigos já tratam esta flag pública como a trava de transição
	# da sessão. Mantém ela ligada em toda geração, não só nas transferências de veículo.
	vehicle_transition_busy = true
	return transition_generation
func _begin_transition(kind: String, _vehicle := false) -> int: return begin_transition(kind, _vehicle)

func owns_transition(token: int) -> bool:
	return token > 0 and token == transition_generation and not transition_kind.is_empty()
func _owns_transition(token: int) -> bool: return owns_transition(token)

func finish_transition(token: int) -> void:
	if not owns_transition(token): return
	transition_kind = ""
	vehicle_transition_busy = false
func _finish_transition(token: int) -> void: finish_transition(token)

func routine_director():
	return world.get_node_or_null("V1RoutineDirector") if world != null else null

func refresh_routine_context() -> void:
	var routines = routine_director()
	if routines != null: routines.refresh_context()
	if urban_operations != null: urban_operations.refresh_context()

func sync_location_presentation() -> void:
	if is_instance_valid(weather): weather._update()
	prompt.text = ""
	world.gameplay.update_visual()
	var city_look := world.get_node_or_null("CityLook") as Node
	if city_look != null: city_look._refresh_silhouette()
	if world.hud.has_method("refresh_from_state"): world.hud.refresh_from_state()

func _vehicle_transition_snapshot(car: CharacterBody3D) -> Dictionary: return _garage._vehicle_transition_snapshot(car)
func _restore_vehicle_transition_snapshot(snapshot: Dictionary, car: CharacterBody3D) -> void: _garage._restore_vehicle_transition_snapshot(snapshot, car)
func restore_transition_player_lock(previous: bool, token: int) -> void: _garage.restore_transition_player_lock(previous, token)
func _discard_place_candidate(candidate: Node3D, owned: bool) -> void: _garage._discard_place_candidate(candidate, owned)
func _garage_transfer_valid(token: int, car: CharacterBody3D, place_id: String, entering: bool, expected_room: Node3D) -> bool: return _garage._garage_transfer_valid(token, car, place_id, entering, expected_room)
func transfer_garage_vehicle(place_id: String, car: CharacterBody3D, entering: bool) -> bool: return await _garage.transfer_garage_vehicle(place_id, car, entering)
func _set_digo_vehicle_gate(opened: bool, token := -1, car: CharacterBody3D = null) -> bool: return _garage._set_digo_vehicle_gate(opened, token, car)
func restore_garage_driver(car: CharacterBody3D) -> bool: return await _garage.restore_garage_driver(car)
func _garage_restore_spawn(place: String, preferred: Vector3, candidate_room: Node3D = null) -> Vector3: return _garage._garage_restore_spawn(place, preferred, candidate_room)

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

## O corpo do carregamento mora em runtime/SessionStartup.gd (etapas na ordem de antes); o _ready fica
## aqui porque TestSession e DialogueSession o sobrescrevem numa subclasse.
func _ready() -> void: await _startup.run()

## A ligação com V2Settings fica na sessão: um lambda criado no SessionStartup (RefCounted) seguraria o
## auxiliar vivo pela conexão do autoload depois da sessão liberada, e trocar o idioma chamaria a sessão
## morta. Aqui o lambda é da sessão e a conexão cai junto com ela, como antes.
func _connect_voice_settings() -> void:
	var voice_settings := get_node_or_null("/root/V2Settings")
	if voice_settings != null:
		voice_settings.voice_language_changed.connect(func(_value): _refresh_voice_presentation(true))
		voice_settings.text_language_changed.connect(func(_value): _refresh_voice_presentation(false))

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

func restore_location() -> void: await _places.restore_location()
func _saved_garage_driver() -> Dictionary: return _places._saved_garage_driver()
func _restore_outdoor_driver() -> void: await _places._restore_outdoor_driver()
func _restore_saved_driver_on_foot(saved: Dictionary) -> bool: return _places._restore_saved_driver_on_foot(saved)
func enter_place(id: String, autosave := true, requested_access_id := "") -> bool: return await _places.enter_place(id, autosave, requested_access_id)
func complete_upside_return(provider: Node, illusion_token: int) -> bool: return await _places.complete_upside_return(provider, illusion_token)
func _upside_landing_clear(point: Vector3) -> bool: return _places._upside_landing_clear(point)
func leave_place() -> bool: return await _places.leave_place()
func find_sewer_hatch(place_id := "harbor_sewer") -> Node3D: return _places.find_sewer_hatch(place_id)
func _close_sewer_hatch_for_transition(token: int) -> void: _places._close_sewer_hatch_for_transition(token)
func _close_sewer_hatch_after_exit(hatch: Node3D) -> void: _places._close_sewer_hatch_after_exit(hatch)
func _clear_return_point(place_id: String, desired: Vector3) -> Vector3: return _places._clear_return_point(place_id, desired)
func sync_dispatch_location() -> void: _places.sync_dispatch_location()

func _install_service_npc() -> void:
	if preload("res://runtime/ShopSafety.gd").peaceful(state.place_id): room.set_meta("invulnerable", true)
	# O Vance está escrito na arte 3D da sala, e não no catálogo de NPCs.
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

func service_threatened(npc_id := "") -> bool:
	if npc_id.is_empty() and is_instance_valid(static_service_actor) and static_service_actor.get_meta("workplace_threatened", false): return true
	for actor in room_npcs:
		if not is_instance_valid(actor) or not actor.is_visible_in_tree(): continue
		if not npc_id.is_empty() and str(actor.get_meta("interior_npc_id", "")) != npc_id: continue
		if actor.get_meta("workplace_threatened", false): return true
	# Assaltos substituem o morador genérico de banco/posto pelos atores físicos deles.
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

func nearest() -> Dictionary: return _interaction.nearest()
func interaction_input_action(action: Dictionary) -> String: return _interaction.interaction_input_action(action)
func interact() -> bool: return await _interaction.interact()
func perform_urban_action(target: String) -> bool: return _interaction.perform_urban_action(target)
func _intro_interact(id: String) -> bool: return _interaction._intro_interact(id)
func _input(event: InputEvent) -> void: _interaction._input(event)

## Um comando sincroniza o cinto e o acessório de arma utilizável.
func toggle_weapon_flashlight() -> void:
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

## A carteira é trocada ao carregar um save; religa o som de dinheiro quando isso acontece.
## Comparar a referência custa nada e evita depender de cada ponto que paga o jogador.
var _money_wired_economy
func _wire_money_audio() -> void:
	if state.economy == _money_wired_economy: return
	_money_wired_economy = state.economy
	if not state.economy.money_gained.is_connected(_on_money_gained):
		state.economy.money_gained.connect(_on_money_gained)

## Sempre que entra dinheiro mostra "+R$" no centro (MoneyReceivedNotice) e toca o "cash" do
## RewardAudio uma vez por aviso: créditos somados no mesmo aviso não repetem o som. Débitos,
## carregar save e restore_snapshot não emitem money_gained, então não aparecem aqui.
func _on_money_gained(amount: int) -> void:
	if is_instance_valid(world) and is_instance_valid(world.hud) and world.hud.has_method("present_money"):
		if world.hud.present_money(amount, String(TranslationServer.translate(state.economy.gain_label)) if not state.economy.gain_label.is_empty() else ""): REWARD_AUDIO.play(self, "cash")
		return
	REWARD_AUDIO.play(self, "cash")

func _process_traced(delta: float) -> void:
	_wire_money_audio()
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
			# A intimidação no assalto e todo consumidor de mira sem tiro leem o mesmo
			# ponto oficial do mundo que a apresentação da arma de fogo. Antes só o
			# alvo de tiro local seguia um analógico de controle/toque, então o frentista
			# podia ser mirado visualmente mas nunca se render sem cursor de mouse.
			world.gameplay.aim_point = aim
		var data: Dictionary = WEAPONS.WEAPONS.get(state.equipped_weapon,{})
		if Input.is_action_pressed("fire") and (data.get("automatic",false) or Input.is_action_just_pressed("fire")): world.gameplay.fire_at(aim)
	var fall_limit: float = mining.fall_limit(world.player.position) if mining != null else -12.0
	if world.player.position.y < fall_limit and not modal: on_death()
	tick += delta
	if tick < .1: return
	tick = 0
	_refresh_reward_feedback()
	if not modal and not world.driving.occupied:
		if service_roofs.is_active(): pass
		elif not state.place_id.is_empty() and state.place_id != "maciota": collect_reward(room)
		elif state.place_id.is_empty():
			for source in get_tree().get_nodes_in_group("native_world_rewards"): collect_reward(source)
	var ammo: Dictionary = state.get_ammo(state.equipped_weapon)
	if cold != null:
		var thermal: Dictionary = cold.status()
		# O HUD contextual é dono do status de frio quando está ativo. O rótulo antigo
		# senão reaparece entre os ticks de sincronia e se sobrepõe ao painel novo.
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

func update_world_indicator() -> void:
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

func _menu(title: String) -> void: _menus._menu(title)
func menu(title: String) -> void: _menu(title)
func button(text: String, action: Callable) -> void: _menus._button(text, action)
func _button(text: String, action: Callable) -> void: button(text, action)
func _focus_menu_button(reference: WeakRef) -> void: _menus._focus_menu_button(reference)
func close_menu() -> void: _menus.close_menu()
func show_dialogue(dialogue_lines: Array, on_done := Callable()) -> void: _menus.show_dialogue(dialogue_lines, on_done)

func interrupt_dialogue() -> void: _menus.interrupt_dialogue()
func advance_dialogue() -> void: _menus._advance_dialogue()
func _advance_dialogue() -> void: advance_dialogue()

func _present_current_dialogue(restart_audio: bool) -> void: _menus._present_current_dialogue(restart_audio)

func _present_dialogue_line(line: Dictionary) -> void: _menus._present_dialogue_line(line)

func cancel_mission() -> bool: return _menus.cancel_mission()

func show_maciota_menu() -> void: _menus.show_maciota_menu()

func _compact_menu_size(extent: Vector2) -> void: _menus._compact_menu_size(extent)

func _fit_compact_menu(identity: Node, maximum: Vector2) -> void: await _menus._fit_compact_menu(identity, maximum)

func _menu_information(text: String, font_size := 16, parent: Node = null) -> Label: return _menus._menu_information(text, font_size, parent)

func show_journal_information() -> void: _menus.show_journal_information()

func show_journal() -> void: _menus.show_journal()
func show_inventory() -> void: _menus.show_inventory()
func show_services(service: String) -> void: _menus.show_services(service)

func _show_services_available(service: String) -> void: _menus._show_services_available(service)
func _show_shop(category: String) -> void: _menus._show_shop(category)
func _show_customization() -> void: _menus._show_customization()
func _show_saber_customization() -> void: _menus._show_saber_customization()
func transaction() -> String: return _menus._transaction()
func _transaction() -> String: return transaction()
func apply_outfit() -> void:
	# A integração de paleta é aplicada pelo adaptador original de shader da roupa do Dante.
	var outfit: String = state.economy.outfit
	if mountain_progression != null and mountain_progression.data.rental: outfit = mountain_progression.suit_outfit()
	if world.player.has_method("set_outfit"): world.player.set_outfit(outfit)
	preload("res://activities/amusement_park/AmusementParkCosmetics.gd").apply(world.player,state.world_state)
	preload("res://assets/outfits/DanteAccessories.gd").apply(world.player,preload("res://systems/wardrobe/AccessoryState.gd").equipped(state.world_state))

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
func show_settings() -> void: _menus.show_settings()
func show_controls() -> void: _menus.show_controls()
func show_map() -> void: _menus.show_map()
func _update_reward() -> void: _rewards._update_reward()
func collect_reward(source: Node3D) -> void: _rewards._collect_reward(source)
func _collect_reward(source: Node3D) -> void: collect_reward(source)
func _refresh_reward_feedback() -> void: _rewards._refresh_reward_feedback()
## M06-C "Turno da noite" (VerticeNightShift), filho da Vértice em PortLogistics.
func _vertice_night() -> Node:
	if urban_operations == null or not is_instance_valid(urban_operations.cargo_handling): return null
	var depot: Variant = urban_operations.cargo_handling.get("depot")
	if not is_instance_valid(depot): return null
	var shift: Variant = depot.get("night_shift")
	return shift if is_instance_valid(shift) else null

func save_block_reason() -> String: return _saving.save_block_reason()

func _queue_checkpoint() -> void: _saving._queue_checkpoint()

func _save_indicator() -> Control: return _saving._save_indicator()

func save_game(manual := false) -> bool: return _saving.save_game(manual)

func _save_game(manual: bool) -> bool: return _saving._save_game(manual)
func load_game() -> void: _saving.load_game()
func return_to_main_menu() -> void: _saving.return_to_main_menu()

func _show_v1_death_presentation() -> void: await _recovery._show_v1_death_presentation()

func _show_v1_arrest_presentation() -> void: await _recovery._show_v1_arrest_presentation()

func _hold_recovery_presentation(presentation: CanvasLayer) -> void: await _recovery._hold_recovery_presentation(presentation)

func _restore_recovery_time_scale() -> void: _recovery._restore_recovery_time_scale()

func _finish_recovery_presentation() -> void: await _recovery._finish_recovery_presentation()

func _exit_tree() -> void:
	_restore_recovery_time_scale()
	if is_instance_valid(death_presentation): death_presentation.queue_free()


func on_arrest() -> void: await _recovery._on_arrest()
func _on_arrest() -> void: await on_arrest()

func on_death() -> void: await _recovery._on_death()
func _on_death() -> void: await on_death()

func _respawn() -> void: await _recovery._respawn()
func respawn() -> void: await _respawn()
