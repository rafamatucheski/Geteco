class_name MountainEvidence
extends Node2D

var evidence_id := ""
var evidence_title := "EVIDÊNCIA"
var evidence_text := ""
var model_kind := "journal"
var prompt: Label
var viewport_3d: SubViewport
var model_root: Node3D
var _modal: CanvasLayer
var _reader: Node
var _near := false

func configure(id: String, title: String, text: String, kind: String) -> void:
	evidence_id = id
	evidence_title = title
	evidence_text = text
	model_kind = kind

func _ready() -> void:
	add_to_group("mountain_expedition_evidence")
	z_index = 18
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.get("collectibles_found") is Array and evidence_id in player.collectibles_found:
		set_process(false)
		queue_free()
		return
	_build_3d_view()
	prompt = Label.new()
	prompt.position = Vector2(-110, -55)
	prompt.size = Vector2(220, 44)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_font_size_override("font_size", 13)
	prompt.add_theme_color_override("font_color", Color("f1d59c"))
	prompt.add_theme_color_override("font_outline_color", Color("0b1115"))
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.hide()
	add_child(prompt)

func _process(_delta: float) -> void:
	if is_queued_for_deletion() or not is_instance_valid(prompt):
		return
	if is_instance_valid(_modal):
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_cancel"):
			_close_reading()
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	_near = is_instance_valid(player) and player.is_visible_in_tree() and global_position.distance_to(player.global_position) < 52.0
	prompt.visible = _near
	if not _near:
		return
	prompt.text = "[%s] EXAMINAR %s" % [get_node("/root/GameInput").hint("interact"), evidence_title]
	if Input.is_action_just_pressed("interact"):
		_open_reading(player)

func _open_reading(player: Node) -> void:
	_reader = player
	if player.has_method("add_collectible"):
		player.add_collectible(evidence_id, evidence_title)
	if player.has_method("set_dialogue_active"):
		player.set_dialogue_active(true)
	_modal = CanvasLayer.new()
	_modal.name = "MountainEvidenceReading"
	_modal.layer = 130
	get_tree().root.add_child(_modal)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.035, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -310
	panel.offset_right = 310
	panel.offset_top = -155
	panel.offset_bottom = 155
	var style := StyleBoxFlat.new()
	style.bg_color = Color("10191f")
	style.border_color = Color("8b7654")
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	shade.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var title := Label.new()
	title.text = evidence_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("efd49b"))
	box.add_child(title)
	var body := Label.new()
	body.text = evidence_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", Color("d7dee0"))
	box.add_child(body)
	var hint := Label.new()
	hint.text = "[%s] fechar" % get_node("/root/GameInput").hint("interact")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("8ea0a8"))
	box.add_child(hint)

func _close_reading() -> void:
	if is_instance_valid(_reader) and _reader.has_method("set_dialogue_active"):
		_reader.set_dialogue_active(false)
	_reader = null
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(_reader) and _reader.has_method("set_dialogue_active"):
		_reader.set_dialogue_active(false)
	if is_instance_valid(_modal):
		_modal.queue_free()

func _build_3d_view() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "EvidenceViewport3D"
	viewport_3d.size = Vector2i(160, 160)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport_3d)
	model_root = Node3D.new()
	viewport_3d.add_child(model_root)
	_build_model()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	camera.position = Vector3(0, 2.9, 3.5)
	viewport_3d.add_child(camera)
	camera.look_at(Vector3(0, 0.45, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.5
	viewport_3d.add_child(light)
	var sprite := Sprite2D.new()
	sprite.name = "EvidenceModel"
	sprite.texture = viewport_3d.get_texture()
	sprite.scale = Vector2.ONE * 0.30
	sprite.position.y = -4
	add_child(sprite)

func _build_model() -> void:
	var leather := _mat(Color("594735"), 0.92)
	var paper := _mat(Color("d0bd91"), 0.88)
	var metal := _mat(Color("66747b"), 0.35, 0.62)
	var dark := _mat(Color("1b2226"), 0.80)
	if model_kind == "pack":
		_box(Vector3(0, 0.52, 0), Vector3(1.0, 1.05, 0.54), leather)
		_box(Vector3(0, 0.65, 0.30), Vector3(0.72, 0.40, 0.08), _mat(Color("3f5746"), 0.94))
		for side in [-1.0, 1.0]:
			_cylinder(Vector3(side * 0.66, 0.65, 0), 0.025, 1.75, metal, Vector3(0.12, 0, side * 0.20))
	elif model_kind == "camera":
		_box(Vector3(0, 0.38, 0), Vector3(1.05, 0.67, 0.48), dark)
		_cylinder(Vector3(0, 0.39, 0.32), 0.25, 0.30, metal, Vector3(PI * 0.5, 0, 0))
		_box(Vector3(0.28, 0.78, -0.02), Vector3(0.26, 0.10, 0.20), dark)
	else:
		_box(Vector3(0, 0.12, 0), Vector3(1.15, 0.18, 0.86), leather, Vector3(0, -0.18, 0))
		_box(Vector3(0, 0.23, -0.02), Vector3(0.92, 0.035, 0.68), paper, Vector3(0, -0.18, 0))
		for x in [-0.28, -0.10, 0.08, 0.26]:
			_box(Vector3(x, 0.255, 0), Vector3(0.018, 0.018, 0.52), _mat(Color("544637"), 0.95), Vector3(0, -0.18, 0))

func _mat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _box(point: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = point
	node.rotation = rotation
	model_root.add_child(node)
	return node

func _cylinder(point: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = material
	node.position = point
	node.rotation = rotation
	model_root.add_child(node)
	return node
