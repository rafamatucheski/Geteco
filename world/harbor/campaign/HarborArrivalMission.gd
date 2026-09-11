extends Node2D

## Scene adapter: Harbor onboarding has its own persistent flags. It does not
## complete the older campaign's theft/arrest; only the actual opening prologue
## advances its matching legacy beat.
signal objective_changed(text: String, target: Vector2)
signal arrival_finished
signal delivery_finished

const CONTRACT_ID := "primeiro_giro"
const REWARD := 150
const OPENING := preload("res://cutscenes/opening/OpeningCutscene.tscn")
## Speaker + translation key per line (extracted text only — the call's
## sequence, timing and voice synthesis mechanics are unchanged).
const PHONE_LINES := [
	["DANTE", "PHONE_LINE_1"],
	["MACIOTA", "PHONE_LINE_2"],
	["DANTE", "PHONE_LINE_3"],
	["MACIOTA", "PHONE_LINE_4"],
]

var phase := "idle"
var dialogue_index := 0
var objective := ""
var target := Vector2.ZERO
var navigation_target := Vector2.ZERO
var world: Node2D
var player: Node2D
var garage: Node2D
var entrance: Node2D
var campaign: Node
var _ui: CanvasLayer
var _dialog: PanelContainer
var _speaker: Label
var _text: Label
var _next: Button
var _objective_label: Label
var _obj_card: PanelContainer
var _obj_tag: Label
var _opening: Control
var _opening_layer: CanvasLayer
var _owns_pause := false
var _previous_paused := false
var _paused_weather: Node
var _weather_process_mode := Node.PROCESS_MODE_ALWAYS
var _pickup_prop: Node2D
var _owns_lock := false
var _previous_disabled := false
var _previous_dialogue := false
var _refresh_clock := 0.0
var _phone_wait := 0.0
var _phone_answered := false
var _phone_audio: AudioStreamPlayer


func configure(scene: Node2D) -> void:
	world = scene
	player = world.get_node("Player")
	campaign = get_node("/root/CampaignState")
	entrance = world.get_node("District/Garage/Entrance")
	garage = world.get_node("Interiors").get("garage_interior")
	garage.connect("maciota_contact_completed", notify_maciota_conversation_completed)
	garage.connect("mission_selected", accept_mission)
	if garage.has_signal("modal_opened"):
		garage.modal_opened.connect(func() -> void: _refresh_objective())
		garage.modal_closed.connect(func() -> void: _refresh_objective())
	var interiors: Node = world.get_node_or_null("Interiors")
	if is_instance_valid(interiors):
		for prop in ["clinic_interior", "police_interior", "workshop_interior", "fire_station_interior"]:
			var it: Node = interiors.get(prop) as Node
			if is_instance_valid(it) and it.has_signal("modal_opened"):
				it.modal_opened.connect(func() -> void: _refresh_objective())
				it.modal_closed.connect(func() -> void: _refresh_objective())
	_build_ui()
	_build_pickup_prop()
	_phone_audio = AudioStreamPlayer.new()
	_phone_audio.bus = "SFX"
	_phone_audio.volume_db = -18.0
	add_child(_phone_audio)
	for entry in PHONE_LINES:
		preload("res://ExpressiveVoice.gd").line(tr(entry[1]), "dante" if entry[0] == "DANTE" else "maciota")
	for voice in ["voice_dante", "voice_maciota"]:
		preload("res://world/harbor/HarborAudioBank.gd").sound(voice)
	var settings := get_node_or_null("/root/SettingsManager")
	if settings and not settings.language_changed.is_connected(_on_language_changed):
		settings.language_changed.connect(_on_language_changed)


## Live language switch: re-resolves board/contract, objective and (if a call
## is currently on screen) the phone dialog text through tr() again. Never
## restarts _phone_audio — only the displayed text changes, so an in-progress
## line's timing/sequence is untouched.
func _on_language_changed(_locale: String) -> void:
	if is_instance_valid(_obj_tag):
		_obj_tag.text = "🎯 CURRENT OBJECTIVE" if TranslationServer.get_locale().begins_with("en") else "🎯 OBJETIVO ATUAL"
	_refresh_board()
	_refresh_objective()
	if phase == "phone":
		if not _phone_answered:
			_speaker.text = tr("PHONE_INCOMING")
			_text.text = tr("PHONE_RINGING")
			_next.text = tr("PHONE_ANSWER")
		else:
			_speaker.text = tr("PHONE_CALL_PREFIX") + " " + PHONE_LINES[dialogue_index][0]
			_text.text = tr(PHONE_LINES[dialogue_index][1])
			_next.text = tr("PHONE_HANG_UP") if dialogue_index == PHONE_LINES.size() - 1 else tr("PHONE_CONTINUE")


func start_or_resume() -> void:
	campaign.call("set_campaign_flag", &"harbor_campaign_active", true)
	garage.call("set_campaign_contact_enabled", not _flag("harbor_maciota_met"))
	garage.call("set_mission_board_unlocked", _flag("harbor_maciota_met"))
	_refresh_board()
	var loading := get_node_or_null("/root/GameLoading")
	if loading != null and loading.active:
		await loading.finished
	if _flag("harbor_delivery_complete"):
		_set_phase("complete", tr("OBJ_COMPLETE_RESUME"), Vector2.ZERO)
	elif _flag("harbor_delivery_picked_up"):
		_set_phase("delivery_return", tr("OBJ_DELIVERY_RETURN"), entrance.global_position)
	elif _flag("harbor_delivery_started"):
		_set_phase("delivery_pickup", tr("OBJ_DELIVERY_PICKUP"), _pickup_position())
	elif _flag("harbor_maciota_met"):
		_set_phase("board", tr("OBJ_BOARD"), entrance.global_position)
	elif _flag("harbor_arrival_call_complete"):
		_set_phase("meet_maciota", tr("OBJ_MEET_MACIOTA"), entrance.global_position)
	elif _flag("harbor_arrival_seen"):
		_begin_phone()
	else:
		_begin_arrival()


func _begin_arrival() -> void:
	phase = "arrival"
	_lock_player()
	_dialog.hide()
	_opening_layer = CanvasLayer.new()
	_opening_layer.name = "OpeningPresentation"
	_opening_layer.layer = 100
	_opening_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_opening_layer)
	_opening = OPENING.instantiate()
	_opening.show_preview_hud = false
	_opening.show_studio_intro = true
	_opening.finished.connect(_on_opening_finished)
	_opening.skipped.connect(_on_opening_finished)
	_opening_layer.add_child(_opening)
	_previous_paused = get_tree().paused
	_paused_weather = world.weather
	_weather_process_mode = _paused_weather.process_mode
	# The CGI has its own rain/foley. Suspend the always-running world weather
	# and its child audio during presentation, without changing weather state.
	_paused_weather.process_mode = Node.PROCESS_MODE_PAUSABLE
	_owns_pause = true
	get_tree().paused = true


func skip_cinematic() -> void:
	if phase != "arrival" or not is_instance_valid(_opening):
		return
	_opening.skip()


func _on_opening_finished(destination: StringName) -> void:
	if phase != "arrival" or destination != &"bus_terminal_arrival":
		return
	# Both actual completion and skip arrive here only after the fade. Keep the
	# player locked through the following phone call; never fabricate completion.
	if is_instance_valid(_opening_layer):
		_opening.queue_free()
		var reveal := ColorRect.new()
		reveal.color = Color.BLACK
		reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_opening_layer.add_child(reveal)
		reveal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade.tween_property(reveal, "color:a", 0.0, 0.65)
		fade.tween_callback(_opening_layer.queue_free)
	_opening = null
	_restore_opening_pause()
	# A madrugada da CGI continua no desembarque; só a primeira chegada passa aqui.
	world.weather.time_of_day = 0.18
	world.weather.set_weather(2)
	world.weather.weather_timer = 90.0
	var camera := player.get_node_or_null("Camera") as Camera2D
	if camera != null:
		camera.make_current()
	campaign.call("set_campaign_flag", &"harbor_arrival_seen", true)
	# This presentation really contains the original prologue. Do not advance
	# any later legacy beat or rewrite already-progressed saves.
	if campaign.get("current_stage") == &"prologue_call":
		campaign.call("complete_current_beat")
	# The real actor exits the stopped coach before answering the arrival call.
	phase = "disembark"
	var terminal := world.get_node("ArrivalStop")
	terminal.player_disembarked.connect(_wait_for_phone, CONNECT_ONE_SHOT)
	terminal.begin_player_disembark(player)

func _wait_for_phone() -> void:
	phase = "arrival_wait"
	_phone_wait = 0.0
	_unlock_player()


func _begin_phone() -> void:
	phase = "phone"
	_phone_answered = false
	dialogue_index = 0
	_lock_player()
	_dialog.show()
	_speaker.text = tr("PHONE_INCOMING")
	_text.text = tr("PHONE_RINGING")
	_next.text = tr("PHONE_ANSWER")
	_phone_audio.stream = ProceduralAudio.get_phone_ring_stream()
	_phone_audio.play()

func answer_phone() -> void:
	if phase != "phone" or _phone_answered:
		return
	_phone_answered = true
	_phone_audio.stop()
	_show_phone_line()


func advance_dialogue() -> void:
	if phase == "arrival":
		if is_instance_valid(_opening):
			_opening.request_skip()
		return
	if phase != "phone":
		return
	if not _phone_answered:
		answer_phone()
		return
	dialogue_index += 1
	if dialogue_index < PHONE_LINES.size():
		_show_phone_line()
		return
	_dialog.hide()
	_phone_audio.stop()
	_unlock_player()
	campaign.call("set_campaign_flag", &"harbor_arrival_call_complete", true)
	_set_phase("meet_maciota", tr("OBJ_MEET_MACIOTA"), entrance.global_position)
	arrival_finished.emit()


func _show_phone_line() -> void:
	_phone_audio.stop()
	var line_text := tr(PHONE_LINES[dialogue_index][1])
	_phone_audio.stream = preload("res://ExpressiveVoice.gd").line(line_text, "dante" if PHONE_LINES[dialogue_index][0] == "DANTE" else "maciota")
	_phone_audio.play()
	_speaker.text = tr("PHONE_CALL_PREFIX") + " " + PHONE_LINES[dialogue_index][0]
	_text.text = line_text
	_next.text = tr("PHONE_HANG_UP") if dialogue_index == PHONE_LINES.size() - 1 else tr("PHONE_CONTINUE")


func notify_maciota_conversation_completed() -> void:
	if phase != "meet_maciota" or not _flag("harbor_arrival_call_complete"):
		return
	campaign.call("set_campaign_flag", &"harbor_maciota_met", true)
	garage.call("set_mission_board_unlocked", true)
	_refresh_board()
	_set_phase("board", tr("OBJ_BOARD"), entrance.global_position)


func accept_mission(id: String) -> bool:
	if id != CONTRACT_ID or phase != "board" or not _flag("harbor_maciota_met"):
		return false
	var board := garage.get("mission_board") as Node2D
	if board == null or not player.visible or player.get("is_dead") == true or player.global_position.distance_to(board.global_position) > 80.0:
		return false
	campaign.call("set_campaign_flag", &"harbor_delivery_started", true)
	_play_mission_feedback(ProceduralAudio.get_mission_start_stream())
	_refresh_board()
	_set_phase("delivery_pickup", tr("OBJ_DELIVERY_PICKUP"), _pickup_position())
	return true


func interact_with_objective() -> bool:
	if player.get("is_dead") == true or player.get("is_control_disabled") == true or not player.visible:
		return false
	if phase == "delivery_pickup" and player.global_position.distance_to(_pickup_position()) <= 65.0:
		campaign.call("set_campaign_flag", &"harbor_delivery_picked_up", true)
		_play_mission_feedback(ProceduralAudio.get_powerup_stream())
		_set_phase("delivery_return", tr("OBJ_DELIVERY_RETURN"), entrance.global_position)
		return true
	if phase == "delivery_return":
		var maciota := garage.get("jager_npc") as Node2D
		if maciota == null or player.global_position.distance_to(maciota.global_position) > 82.0:
			return false
		if _flag("harbor_delivery_complete"):
			return false
		# Flag before payment makes repeated interaction idempotent.
		campaign.call("set_campaign_flag", &"harbor_delivery_complete", true)
		_play_mission_feedback(ProceduralAudio.get_mission_passed_stream())
		player.set("money", int(player.get("money")) + REWARD)
		if player.has_method("_refresh_weapon_ui"):
			player.call("_refresh_weapon_ui")
		_refresh_board()
		_set_phase("complete", tr("OBJ_COMPLETE_REWARD"), Vector2.ZERO)
		delivery_finished.emit()
		return true
	return false


func _play_mission_feedback(stream: AudioStream) -> void:
	var sound := AudioStreamPlayer.new()
	sound.process_mode = Node.PROCESS_MODE_ALWAYS
	sound.bus = &"SFX"
	sound.stream = stream
	sound.volume_db = -10.0
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func _refresh_board() -> void:
	# Estado fixo e autorado (nenhum contrato gerado): a mesma missão transita
	# entre disponível -> em andamento (bloqueada, com motivo) -> concluída
	# (riscada), sem nunca ser removida ou substituída por conteúdo inventado.
	var completed := _flag("harbor_delivery_complete")
	var started := _flag("harbor_delivery_started")
	var missions: Array[Dictionary] = [{
		"id": CONTRACT_ID,
		"title": tr("MISSION_PRIMEIRO_GIRO_TITLE"),
		"description": tr("MISSION_PRIMEIRO_GIRO_DESC"),
		"enabled": not started,
		"completed": completed,
		"requirement": tr("MISSION_STATUS_IN_PROGRESS") if (started and not completed) else ""
	}]
	garage.call("configure_mission_board", missions)


func _set_phase(value: String, description: String, destination: Vector2) -> void:
	phase = value
	objective = description
	target = destination
	_pickup_prop.visible = phase == "delivery_pickup"
	objective_changed.emit(objective, target)
	_refresh_objective()


func get_campaign_status() -> Dictionary:
	return {"phase": phase, "dialogue_index": dialogue_index, "controls_locked": _owns_lock, "objective": objective, "target": target}


func _flag(id: String) -> bool:
	return bool(campaign.call("has_campaign_flag", StringName(id)))


func _pickup_position() -> Vector2:
	return (world.get_node("FirstDeliveryPickup") as Node2D).global_position


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not event.is_echo() and phase in ["arrival", "phone"]:
		advance_dialogue()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and phase in ["delivery_pickup", "delivery_return"]:
		if interact_with_objective():
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if phase == "arrival_wait" and player.get("is_dead") != true:
		_phone_wait += delta
		if _phone_wait >= 7.0:
			_begin_phone()
	if phase == "phone" and not _phone_answered and not _phone_audio.playing:
		_phone_audio.play()
	_refresh_clock += delta
	if _refresh_clock >= 0.2 and is_instance_valid(player):
		_refresh_clock = 0.0
		_refresh_objective()


func set_objective_card_visible(is_visible: bool) -> void:
	if is_instance_valid(_obj_card):
		_obj_card.visible = is_visible

func _is_any_interior_modal_open() -> bool:
	var interiors: Node = world.get_node_or_null("Interiors") if is_instance_valid(world) else null
	if not is_instance_valid(interiors):
		return false
	for prop in ["clinic_interior", "police_interior", "garage_interior", "fire_station_interior", "workshop_interior", "morgue_interior", "ammunation_interior"]:
		var interior: Node = interiors.get(prop) as Node
		if is_instance_valid(interior):
			for dialog_name in ["triage_dialog", "terminal_dialog", "diagnostic_dialog", "alarm_dialog", "bench_dialog", "registry_dialog", "counter_dialog"]:
				var d: Control = interior.get(dialog_name) as Control
				if is_instance_valid(d) and d.visible:
					return true
	return false

func _refresh_objective() -> void:
	if is_instance_valid(player) and (player.has_meta("robbery_room") or player.has_meta("bank_heist_active")):
		if _obj_card: _obj_card.hide()
		return
	if _objective_label == null:
		return
	var destination := target
	# Interior coordinates are isolated; never show a misleading 20 km route.
	if player.global_position.distance_to(garage.global_position) < 900.0:
		if phase in ["meet_maciota", "delivery_return"]:
			destination = (garage.get("jager_npc") as Node2D).global_position
		elif phase == "board":
			destination = (garage.get("mission_board") as Node2D).global_position
		elif phase == "delivery_pickup":
			destination = (garage.get("exit_door") as Node2D).global_position
	navigation_target = destination if phase not in ["idle","phone","arrival","disembark","arrival_wait"] else Vector2.ZERO
	var suffix := ""
	if destination != Vector2.ZERO and phase not in ["phone", "arrival", "delivery_pickup"]:
		var map_position: Vector2=player.get_meta("police_exterior_position",player.global_position)
		var distance := map_position.distance_to(destination)
		var direction := destination - map_position
		var compass: Array[String] = ["L", "SE", "S", "SO", "O", "NO", "N", "NE"]
		suffix = "  ·  %s / %.0f m" % [compass[posmod(int(round(direction.angle() / (PI / 4.0))), 8)], distance / 16.6]
	_objective_label.text = objective + suffix
	if _obj_card != null:
		if _flag("harbor_delivery_complete"):
			_obj_card.visible = false
			return
		var board: Node = (garage.get("mission_board") if is_instance_valid(garage) else null) as Node
		var board_open: bool = bool(board.get("is_ui_open")) if is_instance_valid(board) else false
		var maciota: Node = (garage.get("jager_npc") if is_instance_valid(garage) else null) as Node
		var maciota_talking: bool = bool(maciota.get("is_talking")) if is_instance_valid(maciota) else false
		var dialog_open: bool = _dialog.visible if is_instance_valid(_dialog) else false
		var modal_open: bool = dialog_open or _owns_lock or board_open or maciota_talking or _is_any_interior_modal_open()
		_obj_card.visible = not modal_open


func _lock_player() -> void:
	if _owns_lock:
		return
	_previous_disabled = bool(player.get("is_control_disabled"))
	_previous_dialogue = bool(player.get("is_in_dialogue"))
	_owns_lock = true
	player.call("set_dialogue_active", true)


func _unlock_player() -> void:
	if not _owns_lock or not is_instance_valid(player):
		return
	player.set("is_control_disabled", _previous_disabled)
	player.set("is_in_dialogue", _previous_dialogue)
	_owns_lock = false


func _exit_tree() -> void:
	_restore_opening_pause()
	_unlock_player()


func _restore_opening_pause() -> void:
	if _owns_pause:
		get_tree().paused = _previous_paused
		if is_instance_valid(_paused_weather):
			_paused_weather.process_mode = _weather_process_mode
		_paused_weather = null
		_owns_pause = false


func _build_pickup_prop() -> void:
	var waterfront := world.get_node("Waterfront") as Node2D
	world.get_node("FirstDeliveryPickup").global_position = waterfront.get_node("ShipWaypoints/CargoInspection").global_position
	_pickup_prop = preload("res://world/harbor/campaign/DeliveryParcel3D.gd").new()
	_pickup_prop.name = "FirstDeliveryParcel"
	_pickup_prop.position = world.to_local(_pickup_position())
	_pickup_prop.z_index = 12
	world.add_child(_pickup_prop)
	_pickup_prop.hide()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)

	# Card compacto estruturado de objetivo HUD
	var obj_card := PanelContainer.new()
	_obj_card = obj_card
	obj_card.position = Vector2(24, 150)
	obj_card.custom_minimum_size = Vector2(400, 0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.06, 0.08, 0.12, 1.0)
	card_style.border_color = Color("#dab471")
	card_style.border_width_left = 3
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_right = 6
	card_style.content_margin_left = 14
	card_style.content_margin_right = 14
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	obj_card.add_theme_stylebox_override("panel", card_style)
	_ui.add_child(obj_card)

	var obj_vbox := VBoxContainer.new()
	obj_vbox.add_theme_constant_override("separation", 2)
	obj_card.add_child(obj_vbox)

	var obj_tag := Label.new()
	_obj_tag = obj_tag
	obj_tag.text = "🎯 CURRENT OBJECTIVE" if TranslationServer.get_locale().begins_with("en") else "🎯 OBJETIVO ATUAL"
	obj_tag.add_theme_font_size_override("font_size", 12)
	obj_tag.add_theme_color_override("font_color", Color("#e6bd76"))
	obj_vbox.add_child(obj_tag)

	_objective_label = Label.new()
	_objective_label.custom_minimum_size = Vector2(370, 0)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.add_theme_font_size_override("font_size", 16)
	_objective_label.add_theme_color_override("font_color", Color.WHITE)
	_objective_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_objective_label.add_theme_constant_override("shadow_offset_x", 1)
	_objective_label.add_theme_constant_override("shadow_offset_y", 1)
	obj_vbox.add_child(_objective_label)

	# Diálogo narrativo em painel centralizado na faixa inferior com margem segura
	_dialog = PanelContainer.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dialog.offset_left = 140
	_dialog.offset_right = -140
	_dialog.offset_top = -225
	_dialog.offset_bottom = -28
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	style.border_color = Color("#dab471")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	_dialog.add_theme_stylebox_override("panel", style)
	_ui.add_child(_dialog)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_dialog.add_child(column)

	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 16)
	_speaker.add_theme_color_override("font_color", Color("#e6bd76"))
	column.add_child(_speaker)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 23)
	_text.add_theme_color_override("font_color", Color("#ffffff"))
	_text.custom_minimum_size = Vector2(0, 75)
	column.add_child(_text)

	_next = Button.new()
	_next.custom_minimum_size = Vector2(220, 36)
	_next.size_flags_horizontal = Control.SIZE_SHRINK_END
	_next.add_theme_font_size_override("font_size", 14)
	_next.pressed.connect(advance_dialogue)
	column.add_child(_next)
	_dialog.hide()
