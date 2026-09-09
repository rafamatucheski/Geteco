extends Node
## Local epilogue only. Never advances the legacy campaign or opens Map 2.
var world: Node
var ledger
var player: Node2D
var works: Node2D
var phase := "waiting"
var _was_eligible := false
var line_index := -1
var safe_elapsed := 0.0
var _snapshot: Dictionary
var _owns_pause := false
var _previous_pause := false
var _camera: Camera2D
var _previous_camera: Camera2D
var _shot_elapsed := 0.0
var _notification_elapsed := 0.0
var _notified := false
var _owns_player_lock := false
var _prior_dialogue := false
var _prior_disabled := false
var _panel: PanelContainer
var _label: Label
var _button: Button
var _audio: AudioStreamPlayer
var _fade: ColorRect
var _focus := Vector2.ZERO
const LINES := [
	["dante","Está feito. Os Cobras não mandam mais aqui.","It's done. The Cobras don't run this place anymore."],
	["maciota","Os Cobras recuaram. O Ironback está na garagem. É seu.","The Cobras backed off. The Ironback is in the garage. It's yours."],
	["dante","E os registros? Ainda falta uma peça nessa história.","And the records? There's still a piece missing."],
	["maciota","Guarda isso. A equipe liberou a ponte norte. O acesso à ilha ainda está fechado; por enquanto, use o retorno.","Keep them safe. The crew cleared the north bridge. Access to the island is still closed; use the turnaround for now."]
]

func configure(scene: Node, state) -> void:
	world = scene
	ledger = state
	player = world.get_node("Player")
	works = world.get_node_or_null("Gateway/Works")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_sync()

func _state() -> Dictionary:
	if not ledger.data.get("aftermath") is Dictionary:
		ledger.data.aftermath = {"call_complete":false,"works_complete":false}
	return ledger.data.aftermath

func _sync() -> void:
	var data := _state()
	if not is_same(_snapshot,data):
		cancel_presentation()
		_snapshot = data
		_notified = false
		phase = "done" if data.get("works_complete",false) else ("delay" if data.get("call_complete",false) else "waiting")
	if is_instance_valid(works):
		works.set_works_complete(_eligible() and bool(data.get("works_complete",false)))

func _eligible() -> bool:
	return ledger.data.get("defeated",false) and ledger.data.get("completed",{}).get("cobra_finale",false)

func _safe() -> bool:
	if get_tree().paused or not is_instance_valid(player) or not player.visible or player.get("is_dead") == true:
		return false
	if not _owns_player_lock and (player.get("is_in_dialogue") == true or player.get("is_control_disabled") == true):
		return false
	if not str(ledger.data.get("active_id","")).is_empty(): return false
	var wanted := get_node_or_null("/root/WantedManager")
	if wanted != null and int(wanted.get("current_stars")) > 0: return false
	var territory := world.get_node_or_null("CobraTerritory")
	if territory != null and territory.get("state") == "combat": return false
	for encounter in get_tree().get_nodes_in_group("cobra_campaign_encounter"):
		if encounter.get_living_count()>0: return false
	for room in get_tree().get_nodes_in_group("harbor_interior"):
		if world.is_ancestor_of(room) and room.has_method("get_camera_rect") and room.get_camera_rect().has_point(player.global_position): return false
	return true

func _process(delta: float) -> void:
	if ledger == null: return
	_sync()
	var eligible := _eligible()
	if not eligible:
		# Before the finale there is nothing to dismiss. Stop/reset only when
		# eligibility is actually revoked, not sixty times per second.
		if _was_eligible:
			cancel_presentation()
		_was_eligible = false
		return
	_was_eligible = true
	if not is_instance_valid(player) or player.get("is_dead") == true:
		cancel_presentation()
		return
	if phase == "waiting" and _safe():
		phase = "ringing"
		_notification_elapsed = 0.0
		if not _notified:
			_notified = true
			_audio.stream = ProceduralAudio.get_phone_ring_stream()
			_audio.play()
		_refresh_ui()
	elif phase in ["ringing","dialogue"]:
		if not _safe():
			cancel_presentation()
		elif phase == "ringing":
			_notification_elapsed += delta
			if _notification_elapsed >= 1.6: _audio.stop()
	elif phase == "delay" and _safe():
		safe_elapsed += maxf(0,delta)
		if safe_elapsed >= 7.0 and is_instance_valid(works): _begin_shot()
	elif phase == "shot":
		if not get_tree().paused:
			cancel_presentation()
			return
		_shot_elapsed += delta
		_camera.global_position = _focus + Vector2(0,lerpf(70,0,clampf(_shot_elapsed/4.0,0,1)))
		_camera.zoom = Vector2.ONE * lerpf(.60,.90,clampf(_shot_elapsed/4.0,0,1))
		_fade.color.a = maxf(1.0-clampf(_shot_elapsed/.45,0,1),clampf((_shot_elapsed-4.5)/.5,0,1))
		if _shot_elapsed >= 3.0:
			_state().works_complete = true
			works.set_works_complete(true)
		if _shot_elapsed >= 5.0:
			_finish_shot()

func advance_dialogue() -> void:
	if phase not in ["ringing","dialogue"] or not _safe(): return
	_lock_player()
	_audio.stop()
	line_index += 1
	if line_index >= LINES.size():
		_state().call_complete = true
		phase = "delay"
		safe_elapsed = 0.0
		_unlock_player()
	else:
		phase = "dialogue"
		_audio.stream = preload("res://ExpressiveVoice.gd").line(_line_text(),LINES[line_index][0])
		_audio.play()
	_refresh_ui()

func _begin_shot() -> void:
	_previous_pause = get_tree().paused
	if _previous_pause: return
	_previous_camera = get_viewport().get_camera_2d()
	_camera = Camera2D.new()
	_focus = works.get_focus_position()
	_camera.zoom = Vector2(.72,.72)
	_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(_camera)
	_camera.global_position = _focus + Vector2(0,70)
	_camera.make_current()
	_camera.reset_smoothing()
	_owns_pause = true
	get_tree().paused = true
	_shot_elapsed = 0.0
	phase = "shot"
	_fade.color.a = 1.0
	_refresh_ui()

func _finish_shot() -> void:
	if phase != "shot": return
	_state().works_complete = true
	works.set_works_complete(true)
	_release()
	phase = "done"
	_refresh_ui()

func _release() -> void:
	_unlock_player()
	if is_instance_valid(_camera):
		_camera.enabled = false
		_camera.queue_free()
	_camera = null
	if is_instance_valid(_previous_camera): _previous_camera.make_current()
	_previous_camera = null
	if _owns_pause and is_inside_tree(): get_tree().paused = _previous_pause
	_owns_pause = false
	if is_instance_valid(_audio): _audio.stop()
	if is_instance_valid(_fade): _fade.color.a = 0.0

func _lock_player() -> void:
	if _owns_player_lock or not is_instance_valid(player): return
	if player.get("is_in_dialogue") == true or player.get("is_control_disabled") == true: return
	_prior_dialogue = bool(player.get("is_in_dialogue"))
	_prior_disabled = bool(player.get("is_control_disabled"))
	_owns_player_lock = true
	player.set("is_in_dialogue",true)
	player.set("is_control_disabled",true)

func _unlock_player() -> void:
	if not _owns_player_lock: return
	if is_instance_valid(player):
		player.set("is_in_dialogue",_prior_dialogue)
		player.set("is_control_disabled",_prior_disabled)
	_owns_player_lock = false

func _pointer_entered() -> void:
	if phase in ["ringing","dialogue"]: _lock_player()

func _pointer_exited() -> void:
	if phase == "ringing": _unlock_player()

func cancel_presentation() -> void:
	_release()
	line_index = -1
	safe_elapsed = 0.0
	if ledger != null:
		phase = "done" if _state().get("works_complete",false) else ("delay" if _state().get("call_complete",false) else "waiting")
	_refresh_ui()

func _exit_tree() -> void: _release()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED: _refresh_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and phase == "shot" and event.physical_keycode in [KEY_F8,KEY_ESCAPE]:
		if event.physical_keycode == KEY_F8: _finish_shot()
		else: cancel_presentation()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8 and phase in ["ringing","dialogue"]:
		advance_dialogue()
		get_viewport().set_input_as_handled()

func _line_text() -> String:
	return LINES[line_index][2 if TranslationServer.get_locale().begins_with("en") else 1]

func _refresh_ui() -> void:
	if not is_instance_valid(_panel): return
	_panel.visible = phase in ["ringing","dialogue","shot"]
	_button.visible = true
	var en := TranslationServer.get_locale().begins_with("en")
	_button.text = ("Call Maciota [F8]" if en else "Ligar para Maciota [F8]") if phase == "ringing" else ("Continue [F8]" if en else "Continuar [F8]")
	_label.text = _line_text() if phase == "dialogue" else (("Let Maciota know the job is done." if en else "Avise ao Maciota que o serviço está feito.") if phase == "ringing" else ("North bridge — local works completed. Map 2 is still in development." if en else "Ponte norte — obra local concluída. Mapa 2 ainda em desenvolvimento."))

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 70
	add_child(canvas)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0,0,0,0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_fade)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 140
	_panel.offset_right = -140
	_panel.offset_top = -225
	_panel.offset_bottom = -28
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	panel_style.border_color = Color("#dab471")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_size = 12
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.mouse_entered.connect(_pointer_entered)
	_panel.mouse_exited.connect(_pointer_exited)
	canvas.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color("#ffffff"))
	_label.custom_minimum_size = Vector2(0, 75)
	box.add_child(_label)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(220, 36)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button.add_theme_font_size_override("font_size", 14)
	_button.mouse_entered.connect(_pointer_entered)
	_button.mouse_exited.connect(_pointer_exited)
	_button.button_down.connect(_pointer_entered)
	_button.pressed.connect(func():
		if phase == "shot": _finish_shot()
		else: advance_dialogue())
	box.add_child(_button)
	_audio = AudioStreamPlayer.new()
	_audio.bus = "SFX"
	_audio.volume_db = -18
	add_child(_audio)
	_panel.hide()

func get_status() -> Dictionary:
	return {"phase":phase,"line_index":line_index,"safe_elapsed":safe_elapsed,"owns_pause":_owns_pause,"call_complete":_state().get("call_complete",false),"works_complete":_state().get("works_complete",false)}
