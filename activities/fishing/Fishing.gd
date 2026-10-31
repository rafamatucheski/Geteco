extends Node
const RULES := preload("res://activities/fishing/FishingRules.gd")
const STATE := preload("res://activities/fishing/FishingState.gd")
const ROD := preload("res://activities/fishing/FishingRod.gd")
const HUD := preload("res://activities/fishing/FishingHUD.gd")
const CAMERA := preload("res://activities/fishing/FishingCamera.gd")
const CATCH_ITEMS := preload("res://activities/fishing/FishingCatchItems.gd")
signal completed(result: Dictionary)
var session
var site: Node3D
var active := false
var phase := ""
var tier := -1
var serial := 0
var best := 0
var caught := 0
var remaining := 0.0
var last_result: Dictionary = {}
var rivals: Array[Dictionary] = []
var current_fish: Dictionary = {}
var fight = RULES.Fight.new()
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _phase_time := 0.0
var _next_fish_run := 0.0
var _fish_run_ends := 0.0
var _fish_recovery_ends := 0.0
var _fight_hint := ""
var _charge := 0.0
var _held := false
var _water := Vector3.ZERO
var _cast_water := Vector3.ZERO
var _origin := Vector3.ZERO
var _old_weapon := "fists"
var _old_lock := false
var _old_facing := NAN
var _rod: Node3D
var _canvas: CanvasLayer
var _hud: Control
var _message := ""
var _camera = CAMERA.new()
var _catch_record := false
var _keep_available := true
var _choice_message := ""
var _exit_after_choice := false

func configure(owner_session) -> void:
	session = owner_session
	name = "Fishing"
	process_physics_priority = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	set_physics_process(false)
	if not STATE.validate_world(session.state.world_state, session.state.economy.snapshot()):
		session.controller.save_invalid = true
		session.show_message("Dados de pesca inválidos; save preservado.")
		return
	var saved := snapshot()
	if not saved.last.is_empty() and saved.last.status == "active":
		STATE.finish(session.state.world_state, int(saved.serial), false)
	STATE.claim(session.state.world_state, session.state.economy)

func snapshot() -> Dictionary:
	return STATE.data(session.state.world_state)

static func validate_snapshot(value: Dictionary) -> bool:
	return STATE.valid(value)

func controls_locked() -> bool:
	return active and phase != "walking"

func save_block_reason() -> String:
	return "Encerre a pescaria para salvar." if active else ""

func objective() -> String:
	if not active: return ""
	if phase == "walking": return "Pesca · Vá até um dos pontos livres na margem"
	return "Pesca · Capture o peixe mais pesado" if tier >= 0 else "Pesca livre · Lance, fisgue e recolha"

func target_position() -> Vector3:
	if not is_instance_valid(site): return Vector3.INF
	if controls_locked(): return _water
	var spots: Array = site.fishing_spots()
	return spots[0].position if active and not spots.is_empty() else site.entry_position()

func _outside() -> bool:
	return session != null and session.ready_for_play and session.state.region_id == "harbor" and session.state.place_id.is_empty() and is_instance_valid(site) and not site.is_queued_for_deletion()

func _nearest_spot() -> Dictionary:
	if not _outside(): return {}
	var player_position: Vector3 = session.world.player.global_position
	var nearest: Dictionary = {}
	var distance := 2.15
	for spot in site.fishing_spots():
		var candidate: float = player_position.distance_to(spot.position)
		if candidate < distance:
			distance = candidate
			nearest = spot
	return nearest

func nearest_action() -> Dictionary:
	if not _outside() or session.controller.save_invalid or session.modal or session.world.driving.occupied or session.world.gameplay.health <= 0: return {}
	if controls_locked(): return {}
	var spot := _nearest_spot()
	if not spot.is_empty(): return {"id":"fishing", "target":"fish" if active else "menu", "label":"Começar a pescar" if active else "Pescar · entrada R$ 10", "position":spot.position}
	var entry: Vector3 = site.entry_position()
	if session.world.player.global_position.distance_to(entry) <= 3.2:
		return {"id":"fishing", "target":"cancel" if active else "menu", "label":"Encerrar pescaria" if active else "Pesca e campeonatos", "position":entry}
	return {}

func perform(target: String) -> bool:
	if target != str(nearest_action().get("target", "")): return false
	match target:
		"menu": return open_menu()
		"fish": return take_spot()
		"cancel": cancel_attempt(); return true
	return false

func start_block_reason() -> String:
	if not _outside() or session.controller.save_invalid: return "A pescaria está indisponível."
	if active: return "A pescaria já começou."
	if session.modal or get_tree().paused or session.is_transition_blocked(): return "Encerre a atividade atual."
	if session.world.driving.occupied or session.world.player.input_locked: return "Aproxime-se a pé."
	if session.world.gameplay.health <= 0 or session.world.player.dead or session.rescue_pending or session.arrest_pending: return "Aguarde a recuperação."
	if session.world.gameplay.stars > 0: return "Despiste a polícia antes de pescar."
	if not session.state.campaign.active_id.is_empty() or not session.activities.can_rest(): return "Conclua a atividade atual antes de pescar."
	return ""

func open_menu() -> bool:
	var reason := start_block_reason()
	if not reason.is_empty(): session.show_message(reason); return false
	if nearest_action().get("target", "") != "menu": return false
	session._menu("Pesque-pague · Lago Sereno")
	var label := Label.new()
	label.text = "Entrada: R$ 10 por pescaria · Vara e isca incluídas\nCampeonatos: vence o maior peixe individual; empate não premia.\nA inscrição é cobrada ao começar e não é devolvida ao sair."
	label.add_theme_font_size_override("font_size", 15)
	session.column.add_child(label)
	session._button("Pesca livre · R$ 10", _choose.bind(-1))
	for index in RULES.TIERS.size():
		var spec: Dictionary = RULES.TIERS[index]
		session._button(String(TranslationServer.translate("%s · %d s · prêmio R$ %d")) % [spec.name, spec.seconds, spec.prize], _choose.bind(index))
	var saved := snapshot()
	var record := Label.new()
	record.text = String(TranslationServer.translate("Recorde: %s · %d peixes · %d/%d espécies")) % [RULES.kg(int(saved.best)), saved.catches, saved.species.size(), RULES.SPECIES.size()]
	session.column.add_child(record)
	if session.world.player.global_position.distance_to(site.entry_position()) <= 3.2:
		session._button("Vender peixes", CATCH_ITEMS.open_stock.bind(session))
	session._button("Voltar", session.close_menu)
	return true

func _choose(selected: int) -> void:
	session.close_menu()
	start(selected)

func start(selected: int) -> bool:
	if selected < -1 or selected >= RULES.TIERS.size(): return false
	var reason := start_block_reason()
	if not reason.is_empty(): session.show_message(reason); return false
	if nearest_action().get("target", "") != "menu": return false
	if selected >= 0 and not _rivals_available():
		session.show_message("O campeonato precisa dos cinco pescadores na lagoa.")
		return false
	var next_serial := STATE.begin(session.state.world_state, session.state.economy, selected)
	if next_serial == 0:
		session.show_message("É preciso R$ 10 para entrar na pescaria.")
		return false
	serial = next_serial
	tier = selected
	active = true
	phase = "walking"
	best = 0
	caught = 0
	_clock = 0
	remaining = float(RULES.TIERS[tier].seconds) if tier >= 0 else 0.0
	last_result = {}
	rivals.clear()
	current_fish = {}
	_exit_after_choice = false
	_choice_message = ""
	_message = "Vá a um ponto livre na margem."
	for rival_name in RULES.RIVALS:
		rivals.append({"name":rival_name, "grams":0, "next":_rng.randf_range(11, 21), "catches":0})
	_canvas = CanvasLayer.new()
	_canvas.layer = 23
	add_child(_canvas)
	_hud = HUD.new()
	_canvas.add_child(_hud)
	_hud.catch_choice.connect(choose_catch)
	set_physics_process(true)
	if not _nearest_spot().is_empty(): take_spot()
	_update_hud()
	return true

func take_spot() -> bool:
	if not active or phase != "walking" or not _outside() or session.modal or session.is_transition_blocked() or session.world.driving.occupied: return false
	var spot := _nearest_spot()
	if spot.is_empty() or session.world.player.input_locked or not session.world.player.is_on_floor(): return false
	var player = session.world.player
	_origin = player.global_position
	_water = spot.water
	_cast_water = _water
	_old_lock = bool(player.input_locked)
	_old_facing = player.combat_facing
	_old_weapon = session.state.equipped_weapon
	session.state.equip_weapon("fists")
	player.input_locked = true
	player.velocity = Vector3.ZERO
	var direction: Vector3 = _water - _origin
	player.visual.rotation.y = atan2(-direction.x, -direction.z)
	player.combat_facing = player.visual.rotation.y
	player.clear_combat_weapon_pose()
	session.world.gameplay.aiming = false
	_rod = ROD.new()
	session.world.add_child(_rod)
	_camera.begin(session.world)
	phase = "ready"
	_phase_time = 0
	_held = false
	_charge = 0
	_message = "Segure e solte para arremessar."
	_update_hud()
	return true

func handle_input(event: InputEvent) -> bool:
	if not controls_locked() or session.modal or get_tree().paused: return false
	if event.is_action_pressed("pause_game") or event.is_action("camera_left") or event.is_action("camera_right"): return false
	if event is InputEventScreenTouch or event is InputEventScreenDrag: return false
	# Enter also maps to exit_vehicle, and Space maps to jump. During a decision,
	# the focused choice owns both keys before the shared gameplay handlers.
	if phase == "caught" and event.is_action("ui_accept"):
		if event.is_action_pressed("ui_accept") and not event.is_echo(): _hud.activate_focused_choice()
		return true
	if event.is_action_pressed("exit_vehicle") or event.is_action_pressed("ui_cancel"):
		if not event.is_action_pressed("pause_game"):
			if phase == "caught":
				_exit_after_choice = true
				choose_catch("release")
			elif phase in ["storing", "releasing"]: _exit_after_choice = true
			else: cancel_attempt()
		return true
	if phase == "caught":
		# Native buttons must receive mouse/touch and focus navigation.
		if event is InputEventMouse or event.is_action("ui_accept") or event.is_action("ui_left") or event.is_action("ui_right") or event.is_action("ui_up") or event.is_action("ui_down") or event.is_action("ui_focus_next") or event.is_action("ui_focus_prev"): return false
		if event.is_action_pressed("interact") and not event.is_echo(): choose_catch("keep")
		elif event.is_action_pressed("reload") and not event.is_echo(): choose_catch("release")
		return true
	if phase in ["storing", "releasing"]: return true
	if event.is_action_released("interact"):
		_held = false
		if phase == "charging": _cast()
	elif event.is_action_pressed("interact") and not event.is_echo():
		_held = true
		if phase == "ready":
			phase = "charging"
			_phase_time = 0.0
			_charge = .08
		elif phase == "bite":
			phase = "hooking"
			_begin_fish_fight(float(RULES.definition(str(current_fish.id)).strength))
			_phase_time = 0.0
			_message = "Fisgou!"
		elif phase in ["missed", "line_broke"]:
			phase = "ready"
			_phase_time = 0.0
	_update_hud()
	return true

func _cast() -> void:
	if phase != "charging": return
	current_fish = RULES.roll(_rng, _charge)
	_cast_water = _origin.lerp(_water, lerpf(.58, 1.0, _charge))
	_cast_water.y = _water.y
	_catch_record = false
	_choice_message = ""
	phase = "casting"
	_phase_time = 0.0
	_message = "Observe a boia."

func _physics_process(delta: float) -> void:
	if not active: return
	if not _outside() or session.world.driving.occupied or session.is_transition_blocked(): cancel_attempt("transition"); return
	if session.world.gameplay.health <= 0 or session.world.player.dead or session.rescue_pending or session.arrest_pending: cancel_attempt("recovery"); return
	if session.world.gameplay.stars > 0: cancel_attempt("police"); return
	if is_instance_valid(_hud): _hud.visible = not session.modal and not get_tree().paused
	if session.modal or get_tree().paused:
		_held = false
		return
	if controls_locked() and session.world.player.global_position.distance_to(_origin) > 1.0: cancel_attempt("moved"); return
	if phase == "walking":
		_clock -= delta
		if _clock <= 0: _clock = .2; _update_hud()
		return
	# The real character retains its collision, gravity, damage and recovery.
	session.world.player.input_locked = true
	if session.state.equipped_weapon != "fists": session.state.equip_weapon("fists")
	_phase_time += delta
	if tier >= 0:
		if not _rivals_available(): cancel_attempt("rivals"); return
		var competition_delta := minf(delta, remaining)
		remaining = maxf(0, remaining - delta)
		if competition_delta > 0.0: _update_rivals(competition_delta)
		# Finish an already-earned landing before closing the camera; no new fight
		# or rival catch can advance once the competition clock reaches zero.
		if remaining <= 0 and phase not in ["landing", "caught", "storing", "releasing"]: _finish_tournament(); return
	match phase:
		"charging":
			_charge = clampf(_phase_time / 1.1, .08, 1)
			if _phase_time >= 1.1: _cast()
		"casting":
			if _phase_time >= .72:
				phase = "waiting"
				_phase_time = -_rng.randf_range(2.3, 5.5)
		"waiting":
			if _phase_time >= 0:
				phase = "bite"
				_phase_time = 0
				_message = "Pressione para fisgar!"
		"bite":
			if _phase_time > 1.65: _lose("missed", "A fisgada veio tarde.")
		"hooking":
			if _phase_time >= .45:
				phase = "reeling"
				_phase_time = 0.0
				_message = "Recolha nas folgas; alivie quando o peixe arrancar."
		"reeling":
			var result: String = _update_fish_fight(delta)
			if result == "caught": _land()
			elif result == "line_broke": _lose("line_broke", "Tensão alta: alivie a linha na próxima.")
			elif result == "escaped": _lose("missed", "A linha ficou frouxa e o peixe escapou.")
		"landing":
			if _phase_time >= 1.9: _complete_landing()
		"storing", "releasing":
			if _phase_time >= (ROD.STORE_DURATION if phase == "storing" else ROD.RELEASE_DURATION):
				_finish_catch_choice()
				if not active: return
		"missed", "line_broke":
			if _phase_time > 3.5:
				phase = "ready"
				_message = "Segure e solte para arremessar."
	if is_instance_valid(_rod):
		_rod.water_surface = site
		_rod.present(session.world.player, _cast_water, phase, fight.tension if phase in ["reeling", "hooking"] else 0.0, fight.progress if phase == "reeling" else 0.0, _charge, current_fish, delta, _fight_hint, _held, _phase_time if phase != "waiting" else -1.0)
		_camera.present(session.world.player, _cast_water, _rod._fish, phase, clampf(_phase_time / 1.9, 0.0, 1.0), delta)
	_clock -= delta
	if _clock <= 0: _clock = .1; _update_hud()

func _begin_fish_fight(strength: float) -> void:
	fight.begin(strength)
	var weight_factor := clampf(float(current_fish.get("grams", 0)) / 11500.0, 0.0, 1.0)
	_next_fish_run = 2.6 + fight.strength * .55 + weight_factor * .35
	_fish_run_ends = 0.0
	_fish_recovery_ends = 0.0
	_fight_hint = "steady"

func _update_fish_fight(delta: float) -> String:
	var elapsed: float = fight.elapsed
	var strength: float = fight.strength
	if elapsed >= _next_fish_run:
		_fish_run_ends = elapsed + .78 + strength * .44
		_fish_recovery_ends = _fish_run_ends + 1.15 - strength * .38
		var weight_factor := clampf(float(current_fish.get("grams", 0)) / 11500.0, 0.0, 1.0)
		_next_fish_run = _fish_recovery_ends + 3.8 - strength * .55 + weight_factor * .4
		_fight_hint = "run"
		_message = "Arrancada! Solte para aliviar a linha."
	elif _fight_hint == "run" and elapsed >= _fish_run_ends:
		_fight_hint = "recovery"
		_message = "Ele cansou! Recolha agora."
	elif _fight_hint == "recovery" and elapsed >= _fish_recovery_ends:
		_fight_hint = "steady"
		_message = "Puxe nas folgas da tensão."

	var in_run := elapsed < _fish_run_ends
	var in_recovery := elapsed >= _fish_run_ends and elapsed < _fish_recovery_ends
	var result := fight.update(delta, _held)
	if not result.is_empty(): return result
	var applied_delta := minf(delta, .25)
	if in_run and _held:
		# Forçar a vara durante a arrancada eleva a tensão além do esforço normal.
		fight.tension = clampf(fight.tension + applied_delta * lerpf(.18, .46, strength), 0.0, 1.0)
		if fight.tension >= 1.0:
			fight.outcome = "line_broke"
			return "line_broke"
	elif in_recovery and _held:
		# O intervalo de cansaço recompensa recolher no ritmo certo.
		fight.tension = maxf(0.0, fight.tension - applied_delta * (.22 + strength * .12))
		fight.progress = clampf(fight.progress + applied_delta * (.045 + (1.0 - strength) * .025), 0.0, 1.0)
		if fight.progress >= 1.0:
			fight.outcome = "caught"
			return "caught"
	return ""

func _update_rivals(delta: float) -> void:
	var skill: float = RULES.TIERS[tier].skill
	for index in rivals.size():
		var rival: Dictionary = rivals[index]
		rival.next -= delta
		if rival.next > 0: continue
		rival.next = _rng.randf_range(17, 28) - skill * 5
		if _rng.randf() > .65 + skill * .26: continue
		var fish := RULES.roll(_rng, skill)
		rival.grams = maxi(int(rival.grams), int(fish.grams))
		rival.catches += 1
		if is_instance_valid(site) and site.has_method("show_rival_catch"): site.show_rival_catch(index, fish)

func _rivals_available() -> bool:
	if not is_instance_valid(site): return false
	if not site.has_method("is_angler_available"): return true
	for index in RULES.RIVALS.size():
		if not site.is_angler_available(index): return false
	return true

func _land() -> void:
	# A catch is awarded only after the same fish has cleared the bank and reached Dante.
	phase = "landing"
	_phase_time = 0.0
	_held = false
	_message = "Erguendo o peixe..."
	_update_hud()

func _complete_landing() -> void:
	if phase != "landing": return
	_catch_record = int(current_fish.grams) > int(snapshot().best)
	if not STATE.record_catch(session.state.world_state, serial, current_fish): cancel_attempt("invalid_catch"); return
	best = maxi(best, int(current_fish.grams))
	caught += 1
	phase = "caught"
	_phase_time = 0
	_held = false
	_message = "%s · %s" % [RULES.definition(str(current_fish.id)).name, RULES.kg(int(current_fish.grams))]
	_keep_available = CATCH_ITEMS.can_store(session, current_fish)
	_choice_message = "" if _keep_available else "Bagagem cheia · solte o peixe para continuar."
	_update_hud()

func choose_catch(action: String) -> bool:
	if not active or phase != "caught" or action not in ["keep", "release"]: return false
	if session.modal or get_tree().paused or not _outside() or session.is_transition_blocked(): return false
	if session.world.gameplay.health <= 0 or session.world.player.dead: return false
	if action == "keep":
		if not CATCH_ITEMS.store(session, current_fish):
			_keep_available = CATCH_ITEMS.can_store(session, current_fish)
			_choice_message = "Não foi possível guardar. Solte o peixe para continuar."
			_update_hud()
			return false
		phase = "storing"
	else: phase = "releasing"
	# The phase guards repeated callbacks, including taps in the same frame.
	_phase_time = 0.0
	_held = false
	_choice_message = ""
	_update_hud()
	# Active fishing queues this checkpoint until record and inventory can save together.
	session.save_game()
	return true

func _finish_catch_choice() -> void:
	if tier >= 0 and remaining <= 0.0:
		_finish_tournament()
		return
	if _exit_after_choice:
		cancel_attempt()
		return
	phase = "ready"
	_phase_time = 0.0
	current_fish = {}
	_message = "Segure e solte para arremessar."

func _lose(new_phase: String, reason: String) -> void:
	phase = new_phase
	_phase_time = 0
	_held = false
	_message = reason
	_update_hud()

func _finish_tournament() -> void:
	if not active or tier < 0: return
	if not STATE.finish(session.state.world_state, serial, true, rivals): cancel_attempt("invalid_result"); return
	var won := RULES.winner(best, rivals)
	var paid := STATE.claim(session.state.world_state, session.state.economy)
	last_result = {"finished":true, "won":won, "paid":paid, "best":best, "ranking":RULES.ranking(best, rivals), "tier":tier}
	_release()
	var message := "Campeonato encerrado · Maior peixe: " + RULES.kg(best)
	if won: message = String(TranslationServer.translate("Você venceu! %s · Prêmio R$ %d%s")) % [RULES.kg(best), RULES.TIERS[tier].prize, " aguardando espaço na carteira" if paid == 0 else ""]
	else:
		var leader: Dictionary = last_result.ranking[0]
		message += " · %s: %s" % [leader.name, RULES.kg(int(leader.grams))]
	session.show_message(message)
	session.save_game()
	completed.emit(last_result)

func cancel_attempt(reason := "cancelled") -> void:
	if not active: return
	STATE.finish(session.state.world_state, serial, false)
	last_result = {"finished":false, "reason":reason, "best":best, "catches":caught}
	_release()
	if is_instance_valid(session) and reason == "cancelled":
		session.show_message(String(TranslationServer.translate("Pescaria encerrada · %d peixes · Maior: %s")) % [caught, RULES.kg(best)])
		session.save_game()
	elif is_instance_valid(session) and reason == "rivals":
		session.show_message("Campeonato interrompido: faltam participantes na lagoa.")

func _release() -> void:
	var was_locked := controls_locked()
	active = false
	phase = ""
	_held = false
	_exit_after_choice = false
	set_physics_process(false)
	if is_instance_valid(_rod): _rod.queue_free()
	if is_instance_valid(_canvas): _canvas.queue_free()
	_rod = null
	_canvas = null
	_hud = null
	_camera.release()
	if not was_locked or not is_instance_valid(session) or not is_instance_valid(session.world.player): return
	var player = session.world.player
	player.clear_combat_weapon_pose()
	player.combat_facing = _old_facing
	var keep_locked: bool = session.modal or session.is_transition_blocked() or session.world.gameplay.health <= 0
	player.input_locked = _old_lock or keep_locked
	if session.state.weapons_allowed() and session.state.owns_weapon(_old_weapon): session.state.equip_weapon(_old_weapon)

func _update_hud() -> void:
	if not is_instance_valid(_hud): return
	var controls = GameInput
	var touch := bool(controls.get_meta("touch_controls_active", false)) or OS.has_feature("android") or "--touch-controls" in OS.get_cmdline_user_args()
	var use_key: String = "Pescar" if touch else controls.hint("interact")
	var exit_key: String = "Sair" if touch else controls.hint("exit_vehicle") + " sair"
	var pause_key: String = "Pausa" if touch else controls.hint("pause_game") + " pausa"
	var hint := use_key + " segure e solte: arremessar"
	if phase == "walking": hint = use_key + " num ponto livre: começar a pescar"
	elif phase == "charging": hint = "Solte " + use_key + " para arremessar"
	elif phase == "waiting": hint = use_key + " quando afundar: fisgar"
	elif phase == "bite": hint = use_key + " agora: fisgar"
	elif phase == "hooking": hint = "Fisgou!"
	elif phase == "reeling": hint = use_key + " recolher · solte para aliviar"
	elif phase == "landing": hint = "Erguendo o peixe"
	elif phase == "caught": hint = "Guardar ou soltar"
	elif phase == "storing": hint = "Guardando o peixe…"
	elif phase == "releasing": hint = "Soltando o peixe…"
	var saved: Dictionary = session.state.world_state[STATE.KEY]
	var camera := get_viewport().get_camera_3d()
	var rod_screen := Vector2.ZERO
	if is_instance_valid(camera) and controls_locked(): rod_screen = camera.unproject_position(session.world.player.global_position + Vector3.UP * 1.45)
	var definition := RULES.definition(str(current_fish.get("id", "")))
	_hud.update_state({"title":RULES.TIERS[tier].name if tier >= 0 else "Pesca livre", "clock":"Vá até a margem · R$ 10 pagos" if phase == "walking" else (String(TranslationServer.translate("%d s · prêmio R$ %d")) % [ceili(remaining), RULES.TIERS[tier].prize] if tier >= 0 else "Sem limite de tempo"), "phase":phase, "detail":_message, "fight_hint":_fight_hint, "charge":_charge, "tension":fight.tension, "progress":fight.progress, "best":best, "catches":caught, "species":saved.species.size(), "tournament":tier >= 0, "ranking":RULES.ranking(best, rivals), "hint":hint, "cancel":("Volte ao balcão para encerrar" if phase == "walking" else exit_key) + " · " + pause_key, "rod_screen":rod_screen, "remaining":remaining, "prize":int(RULES.TIERS[tier].prize) if tier >= 0 else 0, "touch":touch, "action_key":use_key, "release_key":controls.hint("reload"), "keep_enabled":_keep_available, "choice_message":_choice_message, "catch_name":str(definition.get("name", "")), "catch_grams":int(current_fish.get("grams", 0)), "catch_record":_catch_record, "landing":clampf(_phase_time / 1.9, 0.0, 1.0)})

func _exit_tree() -> void:
	if active and is_instance_valid(session): STATE.finish(session.state.world_state, serial, false)
	_release()
