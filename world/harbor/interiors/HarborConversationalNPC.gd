class_name HarborConversationalNPC
extends CharacterBody2D

signal dialogue_opened()
signal dialogue_closed()

@export var character_name: String = "Atendente"
@export var title_color: Color = Color("#f1c40f")
@export var shirt_color: Color = Color("#2980b9")
@export var pants_color: Color = Color("#1a5276")
@export var skin_color: Color = Color("#d2b48c")
@export var hat_color: Color = Color("#2c3e50")
@export var has_hat: bool = false
@export var is_female: bool = false
@export var resting_facing_y: float = 0.0

var dialogues: Array = [
	"Olá, como posso ajudar?",
	"O cais do Breakwater anda bastante movimentado hoje.",
	"Tenha um bom dia e tome cuidado nas docas."
]

var interact_area: Area2D
var prompt_badge: Label
var dialogue_ui: CanvasLayer
var dialogue_box: PanelContainer
var name_label: Label
var text_label: Label
var continue_hint: Label

var is_player_nearby: bool = false
var is_talking: bool = false
var dialogue_index: int = 0
var anim_clock: float = 0.0

var viewport_3d: SubViewport
var sprite_3d_display: Sprite2D
var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var torso_rest_height := 0.75
var head_rest_height := 1.14

func _ready() -> void:
	z_index = 8
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var body_shape := CollisionShape2D.new()
	body_shape.name = "BodyCollision"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5.0
	capsule.height = 16.0
	body_shape.shape = capsule
	add_child(body_shape)
	_build_3d_viewport()
	preload("res://characters/pedestrians/CitizenDetails.gd").finish_rig(self, "clerk")
	_setup_interaction()
	_build_dialogue_canvas()
	var settings := get_node_or_null("/root/SettingsManager")
	if settings != null and settings.has_signal("language_changed"):
		settings.language_changed.connect(func(_lang: String) -> void:
			if is_talking:
				_show_current_text()
		)

func _build_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(96, 96)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_3d.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport_3d)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.95, 0.95)
	env.ambient_light_energy = 1.2
	var viewport_world := viewport_3d.find_world_3d()
	if viewport_world != null:
		viewport_world.environment = env

	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.2
	cam.position = Vector3(0.0, 10.0, 0.01)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.current = true
	viewport_3d.add_child(cam)

	var light := DirectionalLight3D.new()
	light.position = Vector3(3.0, 10.0, 3.0)
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	light.light_color = Color(1.0, 0.98, 0.92)
	light.light_energy = 1.3
	viewport_3d.add_child(light)

	_build_model()
	preload("res://systems/ContactShadow.gd").add_person(viewport_3d)

	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.texture = viewport_3d.get_texture()
	sprite_3d_display.position = Vector2.ZERO
	add_child(sprite_3d_display)

## Production Dante's viewing angle, with ground contact calibrated to the room.
func configure_room_presentation(camera: Camera3D, display: Sprite2D) -> void:
	# Dante's longer legs and shallow tailored torso read naturally from above.
	torso_rest_height = 0.85
	head_rest_height = 1.21
	torso_node.position.y = torso_rest_height
	torso_node.scale.z = 0.65
	head_node.position.y = head_rest_height
	left_upper_arm.position = Vector3(-0.185, 1.05, 0)
	right_upper_arm.position = Vector3(0.185, 1.05, 0)
	for part in model_root.get_children():
		if part is Node3D and is_equal_approx(part.position.y, 0.50):
			part.position.y = 0.65
			for mesh in part.get_children():
				if mesh is MeshInstance3D and mesh.mesh is CylinderMesh:
					mesh.mesh.height = 0.59
					mesh.position.y = -0.295
				else:
					mesh.position.y -= 0.15
	# Replace the flat hair cap with a coherent hairstyle; keep uniform headwear.
	for part in head_node.get_children():
		if part is MeshInstance3D and part.mesh is SphereMesh and part.position.y > 0.05:
			part.hide()
	var hair_color := Color("88817c") if is_female else Color("302921")
	preload("res://characters/pedestrians/CitizenAppearance.gd").build_hair(head_node, 3 if is_female else 1, hair_color, has_hat)
	head_node.get_node("HairStyle").scale = Vector3.ONE * 0.82
	if is_female:
		var tail := head_node.get_node("HairStyle")
		# A compact tied bun for Dona Cida.
		for part in tail.get_children():
			if part.position.y < 0.04:
				part.hide()
		preload("res://characters/pedestrians/CitizenDetails.gd").piece(tail, Vector3(.15, .14, .14), Vector3(0, .06, .19), hair_color, true)
	resting_facing_y = PI
	model_root.rotation.y = resting_facing_y
	viewport_3d.find_world_3d().environment.ambient_light_energy = 0.65
	viewport_3d.size = Vector2i(256, 256)
	var portrait_camera := viewport_3d.get_camera_3d()
	portrait_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	portrait_camera.fov = 30.0
	portrait_camera.look_at_from_position(Vector3(0, 3.2, 1.4), Vector3(0, 0.65, 0))
	portrait_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	portrait_camera.force_update_transform()
	portrait_camera.reset_physics_interpolation()
	var height := camera.unproject_position(Vector3.UP * 1.8).distance_to(camera.unproject_position(Vector3.ZERO)) * display.scale.y
	var rig_height := portrait_camera.unproject_position(Vector3.UP * 1.4).distance_to(portrait_camera.unproject_position(Vector3.ZERO))
	var factor := height / maxf(rig_height, 1.0)
	sprite_3d_display.scale = Vector2.ONE * factor
	sprite_3d_display.position = -(portrait_camera.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * 0.5) * factor
	sprite_3d_display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func _make_mat(color: Color, roughness: float = 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	return m

func _build_model() -> void:
	model_root = Node3D.new()
	viewport_3d.add_child(model_root)

	var mat_shirt := _make_mat(shirt_color, 0.85)
	var mat_pants := _make_mat(pants_color, 0.5)
	var mat_skin := _make_mat(skin_color, 0.5)
	var mat_hat := _make_mat(hat_color, 0.3)

	# Torso
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.75, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := MeshInstance3D.new()
	var cap_t := CapsuleMesh.new()
	cap_t.radius = 0.16
	cap_t.height = 0.46
	torso_mesh.mesh = load("res://characters/pedestrians/CitizenAppearance.gd").tailored_body(is_female, false)
	torso_mesh.material_override = mat_shirt
	torso_node.add_child(torso_mesh)

	# Head
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.14, 0.0)
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.14
	sph_h.height = 0.28
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)
	head_node.scale=Vector3.ONE*.85
	var detail=preload("res://characters/pedestrians/CitizenDetails.gd")
	detail.piece(torso_node,Vector3(.11,.20,.115),Vector3(0,.285,.01),skin_color,true)
	detail.piece(torso_node,Vector3(.27,.13,.23),Vector3(0,-.25,0),pants_color)

	if has_hat:
		var cap := MeshInstance3D.new()
		var cyl_c := CylinderMesh.new()
		cyl_c.top_radius = 0.16
		cyl_c.bottom_radius = 0.17
		cyl_c.height = 0.08
		cap.mesh = cyl_c
		cap.material_override = mat_hat
		cap.position = Vector3(0.0, 0.12, 0.0)
		head_node.add_child(cap)

		var visor := MeshInstance3D.new()
		var box_v := BoxMesh.new()
		box_v.size = Vector3(0.14, 0.02, 0.10)
		visor.mesh = box_v
		visor.material_override = mat_hat
		visor.position = Vector3(0.0, 0.08, -0.15)
		head_node.add_child(visor)

	# Arms
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.21, 0.98, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.045, 0.20, mat_shirt, Vector3(0, -0.10, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.20, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.038, 0.18, mat_skin, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.21, 0.98, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.045, 0.20, mat_shirt, Vector3(0, -0.10, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.20, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.038, 0.18, mat_skin, Vector3(0, -0.09, 0)))

	# Legs
	for side in [-0.09, 0.09]:
		var leg := Node3D.new()
		leg.position = Vector3(side, 0.50, 0.0)
		model_root.add_child(leg)
		leg.add_child(_create_limb(0.050, 0.44, mat_pants, Vector3(0, -0.22, 0)))
		preload("res://characters/pedestrians/CitizenDetails.gd").piece(leg,Vector3(.11,.08,.20),Vector3(0,-.46,-.04),Color("34414a"),true)

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.9
	cyl.height = height
	m.mesh = cyl
	m.material_override = mat
	m.position = offset
	return m

@export var interact_radius: float = 75.0

func _setup_interaction() -> void:
	interact_area = Area2D.new()
	interact_area.collision_layer = 0
	interact_area.collision_mask = 4 # Player
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = interact_radius
	col.shape = circle
	interact_area.add_child(col)
	add_child(interact_area)

	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)

	prompt_badge = Label.new()
	prompt_badge.text = "E"
	prompt_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_badge.position = Vector2(-120, -50)
	prompt_badge.size = Vector2(240, 20)
	prompt_badge.add_theme_font_size_override("font_size", 11)
	prompt_badge.add_theme_color_override("font_color", title_color)
	prompt_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt_badge.add_theme_constant_override("shadow_offset_x", 1)
	prompt_badge.add_theme_constant_override("shadow_offset_y", 1)
	prompt_badge.visible = false
	add_child(prompt_badge)

func _build_dialogue_canvas() -> void:
	dialogue_ui = CanvasLayer.new()
	dialogue_ui.layer = 25
	add_child(dialogue_ui)

	dialogue_box = PanelContainer.new()
	dialogue_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_box.offset_left = 140.0
	dialogue_box.offset_right = -140.0
	dialogue_box.offset_bottom = -28.0
	dialogue_box.offset_top = -215.0
	dialogue_box.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue_ui.add_child(dialogue_box)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = title_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	dialogue_box.add_theme_stylebox_override("panel", style)

	dialogue_box.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if is_talking:
				_advance_dialogue()
				dialogue_box.accept_event()
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	dialogue_box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	name_label = Label.new()
	name_label.text = "● %s" % character_name.to_upper()
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", title_color)
	vbox.add_child(name_label)

	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 23)
	text_label.add_theme_color_override("font_color", Color("#ffffff"))
	text_label.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(text_label)

	continue_hint = Label.new()
	continue_hint.text = "[ ESPAÇO / E ] Continuar    [ ESC ] Fechar"
	continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_hint.add_theme_font_size_override("font_size", 13)
	continue_hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(continue_hint)

	dialogue_box.visible = false

func _exit_tree() -> void:
	if is_talking:
		_close_dialogue()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		is_player_nearby = true
		prompt_badge.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		is_player_nearby = false
		prompt_badge.visible = false
		if is_talking:
			_close_dialogue()

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_nearby:
		return

	if event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("interact"):
			if not is_talking:
				_open_dialogue()
			else:
				_advance_dialogue()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept") and is_talking:
			_advance_dialogue()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and is_talking:
			_close_dialogue()
			get_viewport().set_input_as_handled()

func _open_dialogue() -> void:
	if dialogues.is_empty():
		return
	dialogue_index = 0
	is_talking = true
	if prompt_badge != null:
		prompt_badge.visible = false
	if dialogue_box != null:
		dialogue_box.visible = true
	dialogue_opened.emit()
	_show_current_text()

func _advance_dialogue() -> void:
	if not is_talking:
		return
	if dialogue_index + 1 >= dialogues.size():
		_close_dialogue()
		return
	dialogue_index += 1
	_show_current_text()

func _show_current_text() -> void:
	if dialogues.is_empty():
		return
	if text_label != null:
		text_label.text = String(dialogues[dialogue_index])
	var is_en := TranslationServer.get_locale().begins_with("en")
	if continue_hint != null:
		continue_hint.text = "[ SPACE / E ] Continue    [ ESC ] Close" if is_en else "[ ESPAÇO / E ] Continuar    [ ESC ] Fechar"
		if dialogue_index == dialogues.size() - 1:
			continue_hint.text = "[ SPACE / E / ESC ] Close" if is_en else "[ ESPAÇO / E / ESC ] Fechar"

	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_dialogue_blip_stream()
	p.volume_db = -8.0
	p.pitch_scale = randf_range(0.90, 1.15)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

	_trigger_talking_gesture()

func _close_dialogue() -> void:
	is_talking = false
	if dialogue_box != null:
		dialogue_box.visible = false
	if is_player_nearby and prompt_badge != null:
		prompt_badge.visible = true
	dialogue_closed.emit()

func _trigger_talking_gesture() -> void:
	if model_root == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(head_node, "rotation:z", randf_range(-0.10, 0.10), 0.22)
	tw.tween_property(right_upper_arm, "rotation:x", randf_range(0.3, 0.6), 0.22)
	tw.tween_property(left_upper_arm, "rotation:x", randf_range(0.1, 0.4), 0.22)

func _physics_process(delta: float) -> void:
	anim_clock += delta
	if model_root and not is_talking:
		var sway := sin(anim_clock * 1.6) * 0.03
		torso_node.position.y = torso_rest_height + sway * 0.5
		head_node.position.y = head_rest_height + sway * 0.5
		right_upper_arm.rotation.x = sin(anim_clock * 1.1) * 0.05
		left_upper_arm.rotation.x = -sin(anim_clock * 1.1) * 0.05

		var player := get_tree().get_first_node_in_group("player")
		if player and is_player_nearby:
			var dir := global_position.direction_to(player.global_position)
			var angle_3d: float = -atan2(dir.y, dir.x) - PI * 0.5
			model_root.rotation.y = lerp_angle(model_root.rotation.y, angle_3d, 6.0 * delta)
		else:
			model_root.rotation.y = lerp_angle(model_root.rotation.y, resting_facing_y, 3.0 * delta)
