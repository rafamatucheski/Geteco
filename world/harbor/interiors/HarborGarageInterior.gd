class_name HarborGarageInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

## Garage interior for Westgate Motor Co.
## One metric 3D workshop, with playable office, reward bay and diagnostic bench.

const JAGER_NPC := preload("res://JagerNPC.gd")
const CHALKBOARD := preload("res://cars/CarChalkboard.gd")
const WORKSHOP_VIEW := preload("res://world/harbor/interiors/HarborWorkshopView.gd")
var showroom: Node2D
var actor_scale: Node
var camera_3d: Camera3D:
	get: return showroom.camera_3d if is_instance_valid(showroom) else null
var sprite_3d: Sprite2D:
	get: return showroom.sprite_3d if is_instance_valid(showroom) else null

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
		mission_board.interaction_radius = 26.0
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
				if child.name == "Prompt":
					child.position = Vector2(-14, -20)
					child.size = Vector2(56, 24)
					child.add_theme_font_size_override("font_size", 11)
					child.add_theme_color_override("font_outline_color", Color("#10171b"))
					child.add_theme_constant_override("outline_size", 3)
					child.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					var badge := StyleBoxFlat.new()
					badge.bg_color = Color("192329")
					badge.border_color = Color("e7c66a")
					badge.set_border_width_all(1)
					badge.set_corner_radius_all(4)
					child.add_theme_stylebox_override("normal", badge)
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
	var state := get_node_or_null("/root/CampaignState")
	if state != null and state.has_campaign_flag(&"harbor_story_arrival_v2"):
		keys[0] = "MACIOTA_V2_GARAGE_1"
		keys[1] = "MACIOTA_V2_GARAGE_2"
		# The exchange is already stated openly in the first line.
		keys[2] = "MACIOTA_BROTHER"
		keys[3] = "MACIOTA_LINE_2"
		keys.remove_at(4)
	var lines: Array[String] = []
	for key in keys:
		lines.append(tr(key))
	var gestures: Array[String] = ["welcome", "nod", "explain", "explain", "explain", "point", "nod"]
	var speakers: Array[String] = ["maciota", "dante", "maciota", "maciota", "maciota", "maciota", "maciota"]
	gestures.resize(keys.size())
	speakers.resize(keys.size())
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
var diagnostic_recover: Button
var diagnostic_repair: Button
var anim_clock: float = 0.0
var spark_particles: CPUParticles2D

func _init() -> void:
	add_to_group("weapon_free_zone")
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

## Pedestrians arrive beside the open gate. Driven vehicles need the full bay:
## using the pedestrian marker puts their body on the automatic exit strip and
## immediately sends them back outside.
func get_entry_position(actor: Node2D, fallback: Marker2D) -> Vector2:
	if actor.is_in_group("vehicle") and actor.get("is_driven_by_player") == true:
		return get_vehicle_bay_position()
	return fallback.global_position

func orient_actor_on_entry(actor: Node2D) -> void:
	if actor.is_in_group("vehicle") and actor.get("is_driven_by_player") == true:
		# The bay faces the south roller gate; reset saved/exterior headings so the
		# car never flashes sideways for its first interior frame.
		actor.global_rotation = PI / 2.0
		actor.reset_physics_interpolation()
		# Ensure the 3D body matches the corrected rotation immediately, even if
		# physics is paused during the dialogue handoff.
		var model: Node3D = actor.get("body_model")
		if is_instance_valid(model):
			model.rotation.y = -actor.global_rotation - PI / 2.0
		var visual: Sprite2D = actor.get("visual")
		if is_instance_valid(visual):
			visual.global_rotation = 0.0
		if actor.has_meta("interior_vehicle_presentation"):
			var presentation: Node = actor.get_meta("interior_vehicle_presentation")
			if is_instance_valid(presentation) and presentation.has_method("sync"):
				presentation.sync()

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
	return absf(ground.x) < 1.8 and ground.y > 4.3 and ground.y < 12.0

## A pista do portao fica ABAIXO do enquadramento: dirigindo para fora, o carro
## cruza a borda do retangulo da camera antes de alcancar o gatilho de saida. Se
## a garagem deixasse de conter o jogador ali, HarborGame._restore_room_presentation()
## limparia o estado de interior no meio da manobra e a saida nunca dispararia.
func contains_point(point: Vector2) -> bool:
	if super.contains_point(point):
		return true
	var ground: Vector2 = showroom.unproject_floor(point)
	return absf(ground.x) < 3.0 and ground.y > 0.0 and ground.y < 12.0

func get_camera_rect() -> Rect2:
	# Fit the rear wall's top and the visible gate threshold, including the office.
	var top_left := to_global(workshop_point(Vector3(-4.5, 3.8, -4.4)))
	var bottom_right := to_global(workshop_point(Vector3(6.8, 0, 4.95)))
	return Rect2(top_left, bottom_right - top_left)

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	if not active and is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale = null
	if is_instance_valid(showroom):
		# The existing room pass contains its actors; suspend it when empty.
		showroom.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED

func on_actor_entered(actor: Node2D) -> void:
	if not actor.is_in_group("player") or is_instance_valid(actor_scale):
		return
	actor_scale = preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	add_child(actor_scale)
	actor_scale.configure(actor, showroom.camera_3d, showroom.sprite_3d)

func _exit_tree() -> void:
	if is_instance_valid(actor_scale):
		actor_scale.restore()

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
	jager_npc.collision_layer = 4
	jager_npc.collision_mask = 1 | 2 | 4
	var body_shape := CollisionShape2D.new()
	body_shape.name = "BodyCollision"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5
	capsule.height = 16
	body_shape.shape = capsule
	jager_npc.add_child(body_shape)
	add_child(jager_npc)
	# Match the room's elevated camera and ground the detailed rig at his feet.
	jager_npc.viewport_3d.size = Vector2i(256, 256)
	jager_npc.viewport_3d.msaa_3d = Viewport.MSAA_2X
	var portrait_camera := jager_npc.viewport_3d.get_camera_3d()
	portrait_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	portrait_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	portrait_camera.size = 2.5
	portrait_camera.look_at_from_position(Vector3(0, 18.75, 15), Vector3(0, .75, 0))
	portrait_camera.reset_physics_interpolation()
	var height: float = showroom.project_point(Vector3.UP * 1.8).distance_to(showroom.project_point(Vector3.ZERO))
	var rig_height := portrait_camera.unproject_position(Vector3.UP * 1.5).distance_to(portrait_camera.unproject_position(Vector3.ZERO))
	jager_npc.sprite_3d_display.scale = Vector2.ONE * height / rig_height
	jager_npc.sprite_3d_display.position = -(portrait_camera.unproject_position(Vector3.ZERO) - Vector2(128, 128)) * jager_npc.sprite_3d_display.scale
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
	_create_spawn_and_exit(workshop_point(Vector3(1.35, 0, 3.35)), workshop_point(Vector3(0, 0, 4.3)), &"harbor/District/Garage/Entrance/exit", "SAIR DA GARAGEM")
	exit_door.get_node("Facade").hide()
	exit_door.get_node("Prompt").modulate.a = 0.0
	var sensor := exit_door.get_node("InteractionArea") as Area2D
	sensor.position = Vector2.ZERO
	var sensor_shape := sensor.get_node("CollisionShape2D") as CollisionShape2D
	sensor_shape.shape = RectangleShape2D.new()
	sensor_shape.shape.size = Vector2(70, 12)
	_build_diagnostic_station()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(exit_door) or not exit_door.enabled or exit_door._busy:
		return
	var actor := exit_door.get_nearest_actor()
	if not is_instance_valid(actor) or not actor.visible:
		return
	if actor.get("is_in_dialogue") or actor.get("is_control_disabled") or actor.get("is_dead") or actor.get("is_arrested"):
		return
	exit_door.request_interaction(actor)

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
	diagnostic_badge.text = "E"
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
	title.text = "⚙ WESTGATE DIAGNOSTIC TERMINAL" if TranslationServer.get_locale().begins_with("en") else "⚙ TERMINAL DE DIAGNÓSTICO WESTGATE"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#f39c12"))
	vbox.add_child(title)

	diagnostic_text = Label.new()
	diagnostic_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnostic_text.add_theme_font_size_override("font_size", 20)
	diagnostic_text.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(diagnostic_text)
	diagnostic_repair = Button.new()
	diagnostic_repair.name = "RepairMonaliza"
	diagnostic_repair.pressed.connect(_repair_from_diagnostic)
	vbox.add_child(diagnostic_repair)
	diagnostic_recover = Button.new()
	diagnostic_recover.name = "RecoverMonaliza"
	diagnostic_recover.pressed.connect(_recover_from_diagnostic)
	vbox.add_child(diagnostic_recover)

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
	if event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("interact"):
			if not diagnostic_dialog.visible:
				_run_diagnostic()
			else:
				diagnostic_dialog.visible = false
				modal_closed.emit()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and diagnostic_dialog.visible:
			diagnostic_dialog.visible = false
			modal_closed.emit()
			get_viewport().set_input_as_handled()

func _run_diagnostic() -> void:
	diagnostic_dialog.visible = true
	modal_opened.emit()
	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_powerup_stream()
	p.bus = &"SFX"
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

	_refresh_diagnostic()
	if diagnostic_repair.visible and not diagnostic_repair.disabled:
		diagnostic_repair.grab_focus()
	elif diagnostic_recover.visible and not diagnostic_recover.disabled:
		diagnostic_recover.grab_focus()

func _refresh_diagnostic() -> void:
	var manager := get_tree().get_first_node_in_group("personal_car_manager")
	var en := TranslationServer.get_locale().begins_with("en")
	diagnostic_recover.hide()
	diagnostic_repair.hide()
	if manager == null or not manager.car.unlocked:
		diagnostic_text.text = "Monaliza is not available yet." if en else "A Monaliza ainda não está disponível."
		return
	if manager.impounded:
		diagnostic_text.text = "Monaliza has been impounded." if en else "A Monaliza foi apreendida."
	elif manager.car.is_broken or manager.car.is_exploded:
		diagnostic_text.text = "Monaliza is out of service." if en else "A Monaliza está fora de operação."
	elif not manager.is_car_in_garage():
		diagnostic_text.text = "Monaliza is not in the garage." if en else "A Monaliza não está na garagem."
	else:
		diagnostic_text.text = ("Monaliza in the garage. Vehicle condition: %d/%d." if en else "Monaliza na garagem. Estado do veículo: %d/%d.") % [manager.car.health, manager.car.max_health]
	if manager.is_car_in_garage() and not manager.impounded:
		diagnostic_repair.show()
		diagnostic_repair.text = ("Repair car — $%d" if en else "Reparar carro — $%d") % manager.REPAIR_FEE
		diagnostic_repair.disabled = not manager.can_repair() or manager.player.money < manager.REPAIR_FEE
		if manager.can_repair() and manager.player.money < manager.REPAIR_FEE:
			diagnostic_text.text += " Insufficient funds." if en else " Saldo insuficiente."
	elif manager.can_recover(true):
		diagnostic_recover.show()
		diagnostic_recover.text = ("Recover Monaliza — $%d" if en else "Recuperar Monaliza — $%d") % manager.RECOVERY_FEE
		diagnostic_recover.disabled = manager.player.money < manager.RECOVERY_FEE
		if diagnostic_recover.disabled:
			diagnostic_text.text += " Insufficient funds." if en else " Saldo insuficiente."

func _repair_from_diagnostic() -> void:
	var manager := get_tree().get_first_node_in_group("personal_car_manager")
	if manager == null:
		return
	var repaired: bool = manager.repair()
	_refresh_diagnostic()
	if repaired:
		diagnostic_text.text = ("Car repaired. Vehicle condition: %d/%d." if TranslationServer.get_locale().begins_with("en") else "Carro reparado. Estado do veículo: %d/%d.") % [manager.car.health, manager.car.max_health]

func _recover_from_diagnostic() -> void:
	var manager := get_tree().get_first_node_in_group("personal_car_manager")
	if manager == null:
		return
	var recovered: bool = manager.recover(true)
	_refresh_diagnostic()
	if recovered:
		diagnostic_text.text = "Monaliza recovered. Ready in the service bay." if TranslationServer.get_locale().begins_with("en") else "Monaliza recuperada. Pronta no elevador."
