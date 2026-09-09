class_name HarborGarageInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

## Garage interior for Westgate Motor Co.
## One metric 3D workshop, with playable office, reward bay and diagnostic bench.

const JAGER_NPC := preload("res://JagerNPC.gd")
const CHALKBOARD := preload("res://CarChalkboard.gd")
const WORKSHOP_VIEW := preload("res://world/harbor/interiors/HarborWorkshopView.gd")
var showroom: Node2D

signal maciota_contact_completed()
signal mission_selected(mission_id: String)

var mission_board: CarChalkboard
var campaign_contact_enabled: bool = false
var _board_enabled_before_dialogue: bool = false

## Opt-in only: review scenes keep their existing conversations and layout.
func set_campaign_contact_enabled(enabled: bool) -> void:
	campaign_contact_enabled = enabled
	if not is_instance_valid(mission_board):
		mission_board = CHALKBOARD.new()
		mission_board.name = "MaciotaMissionBoard"
		mission_board.use_legacy_position = false
		mission_board.position = workshop_point(WORKSHOP_VIEW.BOARD_INTERACTION)
		mission_board.interaction_enabled = false
		mission_board.set_locked_message_key("BOARD_LOCKED_FINISH_MACIOTA")
		add_child(mission_board)
		# The actual board is a 3D prop; retain only its interaction prompts.
		for child in mission_board.get_children():
			if child is Polygon2D or (child is Label and child.name not in ["Prompt", "LockedPrompt"]):
				child.hide()
			elif child is Label:
				child.scale = Vector2.ONE * 0.5
				child.position = Vector2(-42, -32)
				child.size = Vector2(170, 42)
				child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mission_board.configure_missions([])
		mission_board.dialogue_opened.connect(func() -> void:
			jager_npc.set_process_unhandled_input(false)
			modal_opened.emit())
		mission_board.dialogue_closed.connect(func() -> void:
			jager_npc.set_process_unhandled_input(true)
			modal_closed.emit())
		mission_board.mission_selected.connect(func(id: String) -> void: mission_selected.emit(id))
		jager_npc.dialogue_opened.connect(func() -> void:
			_board_enabled_before_dialogue = mission_board.interaction_enabled
			mission_board.interaction_enabled = false
			modal_opened.emit())
		jager_npc.dialogue_closed.connect(func() -> void:
			mission_board.interaction_enabled = _board_enabled_before_dialogue
			modal_closed.emit())
	var settings := get_node_or_null("/root/SettingsManager")
	if settings != null and not settings.language_changed.is_connected(_on_garage_language_changed):
		settings.language_changed.connect(_on_garage_language_changed)
	if not enabled:
		var follow_up: Array[String] = [tr("MACIOTA_LINE_FOLLOWUP")]
		var follow_up_gestures: Array[String] = ["point"]
		var follow_up_keys: Array[String] = ["MACIOTA_LINE_FOLLOWUP"]
		jager_npc.configure_conversation(follow_up, follow_up_gestures, follow_up_keys)
		return
	var keys: Array[String] = [
		"MACIOTA_LINE_1",
		"MACIOTA_DANTE_REPLY",
		"MACIOTA_FAVOR",
		"MACIOTA_BROTHER",
		"MACIOTA_LINE_2",
		"MACIOTA_LINE_3",
		"MACIOTA_LINE_4"
	]
	var lines: Array[String] = []
	for key in keys:
		lines.append(tr(key))
	var gestures: Array[String] = ["welcome", "nod", "explain", "explain", "explain", "point", "nod"]
	var speakers: Array[String] = ["maciota", "dante", "maciota", "maciota", "maciota", "maciota", "maciota"]
	jager_npc.configure_conversation(lines, gestures, keys, speakers)
	if not jager_npc.conversation_completed.is_connected(_on_contact_completed):
		jager_npc.conversation_completed.connect(_on_contact_completed)

func _on_garage_language_changed(_locale: String) -> void:
	if is_instance_valid(jager_npc):
		set_campaign_contact_enabled(campaign_contact_enabled)

func _on_contact_completed() -> void:
	if not campaign_contact_enabled:
		return
	set_mission_board_unlocked(true)
	set_campaign_contact_enabled(false)
	maciota_contact_completed.emit()

func set_mission_board_unlocked(unlocked: bool) -> void:
	if is_instance_valid(mission_board):
		mission_board.interaction_enabled = unlocked
		if not unlocked:
			mission_board.close_chalkboard()

func configure_mission_board(missions: Array[Dictionary]) -> void:
	if is_instance_valid(mission_board):
		mission_board.configure_missions(missions)

var jager_npc: JagerNPC
var tito_pedestrian: Node2D
var diagnostic_area: Area2D
var diagnostic_badge: Label
var diagnostic_active: bool = false
var diagnostic_dialog: PanelContainer
var diagnostic_text: Label
var anim_clock: float = 0.0
var spark_particles: CPUParticles2D

func _init() -> void:
	interior_id = &"garage"
	display_name = "WESTGATE MOTOR CO. — GARAGEM"
	room_size = Vector2(330, 250)
	wall_color = Color("#12151a")
	floor_color = Color("#1e242b")
	accent_color = Color("#e8b44f")

# The art supplies every floor, wall and light. No second, oversized 2D room.
func _build_walls_and_floor() -> void:
	pass

func _build_lights() -> void:
	pass

func workshop_point(point: Vector3) -> Vector2:
	return showroom.position + showroom.project_point(point)

func get_vehicle_bay_position() -> Vector2:
	return to_global(workshop_point(Vector3.ZERO))

func restore_legacy_visitor(player: Node2D) -> void:
	if player.has_meta("westgate_layout_checked") or not player.visible:
		return
	var old_room := Rect2(global_position - Vector2(560, 320), Vector2(1120, 640))
	if not old_room.has_point(player.global_position):
		return
	player.set_meta("westgate_layout_checked", true)
	var ground: Vector2 = showroom.unproject_floor(player.global_position)
	if not Rect2(-4.1, -4.0, 10.5, 8.6).has_point(ground):
		player.global_position = spawn_point.global_position
		player.velocity = Vector2.ZERO

func is_vehicle_at_exit(world_point: Vector2) -> bool:
	var ground: Vector2 = showroom.unproject_floor(world_point)
	return absf(ground.x) < 1.8 and ground.y > 5.2 and ground.y < 12.0

func get_camera_rect() -> Rect2:
	var frame := Rect2(to_global(Vector2(9, -125)), room_size)
	# Tighten only the workshop framing: both camera entry and steady-state
	# fitting use this rectangle, preserving the same center at 20% more zoom.
	var framed_size := frame.size / 1.20
	return Rect2(frame.get_center() - framed_size * 0.5, framed_size)

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	if is_instance_valid(showroom):
		# Furniture is static; never render another full 3D pass every frame.
		showroom.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED

func _setup_interior_content() -> void:
	showroom = WORKSHOP_VIEW.new()
	showroom.name = "MonalizaShowroom"
	# Keep the historical bay origin so parked Monaliza saves remain aligned.
	showroom.position = Vector2(150, 20)
	add_child(showroom)
	showroom.build_workshop()
	jager_npc = JAGER_NPC.new()
	jager_npc.name = "JagerMaciota"
	jager_npc.position = workshop_point(showroom.model.get_interaction_points().maciota_seat)
	add_child(jager_npc)
	jager_npc.prompt_badge.scale = Vector2.ONE * 0.5
	jager_npc.prompt_badge.position = Vector2(-40, -30)
	jager_npc.greeting_label.scale = Vector2.ONE * 0.5
	jager_npc.greeting_label.position = Vector2(-50, -45)
	# Approach the desk inside the office, not through its glass partition.
	var contact: Vector2 = workshop_point(showroom.model.get_interaction_points().maciota_desk)
	jager_npc.interact_area.position = contact - jager_npc.position
	var contact_shape := jager_npc.interact_area.get_child(0) as CollisionShape2D
	contact_shape.shape = CircleShape2D.new()
	contact_shape.shape.radius = 15.0
	_create_spawn_and_exit(workshop_point(Vector3(1.35, 0, 3.55)), workshop_point(Vector3(0, 0, 5.4)), &"harbor/District/Garage/Entrance/exit", "SAIR DA GARAGEM")
	exit_door.get_node("Facade").hide()
	var sensor := exit_door.get_node("InteractionArea") as Area2D
	sensor.position = Vector2.ZERO
	var sensor_shape := sensor.get_node("CollisionShape2D") as CollisionShape2D
	sensor_shape.shape = RectangleShape2D.new()
	sensor_shape.shape.size = Vector2(70, 20)
	_build_diagnostic_station()

func _build_diagnostic_station() -> void:
	var lift_pos := workshop_point(showroom.model.get_interaction_points().workbench)
	diagnostic_area = Area2D.new()
	diagnostic_area.name = "DiagnosticArea"
	diagnostic_area.collision_layer = 0
	diagnostic_area.collision_mask = 4
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18, 12)
	shape.shape = rect
	diagnostic_area.add_child(shape)
	diagnostic_area.position = lift_pos
	add_child(diagnostic_area)
	diagnostic_area.body_entered.connect(_on_diagnostic_entered)
	diagnostic_area.body_exited.connect(_on_diagnostic_exited)
	diagnostic_badge = Label.new()
	diagnostic_badge.text = "[E] DIAGNÓSTICO"
	diagnostic_badge.position = lift_pos + Vector2(-40, -35)
	diagnostic_badge.add_theme_font_size_override("font_size", 9)
	diagnostic_badge.z_index = 10
	diagnostic_badge.hide()
	add_child(diagnostic_badge)
	_build_diagnostic_ui()

func _build_diagnostic_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 26
	add_child(canvas)

	diagnostic_dialog = PanelContainer.new()
	diagnostic_dialog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	diagnostic_dialog.offset_left = 140.0
	diagnostic_dialog.offset_right = -140.0
	diagnostic_dialog.offset_bottom = -28.0
	diagnostic_dialog.offset_top = -200.0
	diagnostic_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(diagnostic_dialog)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#f39c12")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	diagnostic_dialog.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	diagnostic_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "⚙ TERMINAL DE DIAGNÓSTICO WESTGATE"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#f39c12"))
	vbox.add_child(title)

	diagnostic_text = Label.new()
	diagnostic_text.text = "Estatísticas da bancada: Suspensão 100% • Pressão de óleo: Nominal • Vaga de trabalho ativa."
	diagnostic_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnostic_text.add_theme_font_size_override("font_size", 20)
	diagnostic_text.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(diagnostic_text)

	var hint := Label.new()
	var is_en := TranslationServer.get_locale().begins_with("en")
	hint.text = "[ E / ESC ] Close report" if is_en else "[ E / ESC ] Fechar relatório"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(hint)

	diagnostic_dialog.visible = false

func _on_diagnostic_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		diagnostic_active = true
		diagnostic_badge.visible = true

func _on_diagnostic_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		diagnostic_active = false
		diagnostic_badge.visible = false
		if diagnostic_dialog.visible:
			diagnostic_dialog.visible = false
			modal_closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not diagnostic_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if not diagnostic_dialog.visible:
				_run_diagnostic()
			else:
				diagnostic_dialog.visible = false
				modal_closed.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and diagnostic_dialog.visible:
			diagnostic_dialog.visible = false
			modal_closed.emit()
			get_viewport().set_input_as_handled()

func _run_diagnostic() -> void:
	diagnostic_dialog.visible = true
	modal_opened.emit()
	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_powerup_stream()
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

	var player := get_tree().get_first_node_in_group("player")
	var hp: int = player.health if player and "health" in player else 100
	diagnostic_text.text = "DIAGNÓSTICO WESTGATE: Elevador calibrado. Dante HP: %d/100. Pressão dos pneus: 32 PSI. Bancada operacional pronta para serviço." % hp
