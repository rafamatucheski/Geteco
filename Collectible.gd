class_name Collectible
extends Area2D

## Achado de exploração espalhado pelo mapa (extremidades, território dos
## Cobras, docas). A cada 10 achados distintos o jogador ganha grana ou uma
## pista de carro secreto — ver Player.add_collectible().

@export var collectible_id: String = ""
@export var flavor_label: String = "ACHADO"

var _clock: float = 0.0
var _is_collected: bool = false
var visual_root: Node2D
var gem_poly: Polygon2D
var glow_circle: Polygon2D
var label: Label

var viewport: SubViewport
var model_3d: Node3D
var sprite_3d: Sprite2D
var screen_visible: bool = false
var _use_3d: bool = true
var _presentation_rendered := false

func _ready() -> void:
	if collectible_id.is_empty():
		push_warning("Collectible sem collectible_id definido em %s" % get_path())

	var player := get_tree().get_first_node_in_group("player")
	if player and player.get("collectibles_found") is Array and (player.collectibles_found as Array).has(collectible_id):
		queue_free()
		return

	# Objetos de exploração ficam sob fachadas e vegetação, como os demais props.
	z_index = 3
	collision_layer = 0
	collision_mask = 4 # Camada de personagens; o grupo player filtra os NPCs.

	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 15.0
	col.shape = circle
	add_child(col)

	visual_root = Node2D.new()
	add_child(visual_root)

	# 2D fallback / customization nodes (preserved for backwards compatibility with HarborCemetery etc.)
	glow_circle = Polygon2D.new()
	glow_circle.polygon = _create_circle_polygon(13.0, 14)
	glow_circle.color = Color(0.63, 0.52, 0.95, 0.25)
	glow_circle.visible = false
	visual_root.add_child(glow_circle)

	gem_poly = Polygon2D.new()
	gem_poly.color = Color("#a29bfe")
	gem_poly.polygon = PackedVector2Array([
		Vector2(0, -8), Vector2(6, -2), Vector2(4, 7), Vector2(-4, 7), Vector2(-6, -2)
	])
	gem_poly.visible = false
	visual_root.add_child(gem_poly)

	var facet := Polygon2D.new()
	facet.color = Color(1.0, 1.0, 1.0, 0.55)
	facet.polygon = PackedVector2Array([Vector2(0, -8), Vector2(3, -1), Vector2(0, 3), Vector2(-3, -1)])
	gem_poly.add_child(facet)

	# 3D Procedural collectible: Tangible metallic briefcase / lockbox with subtle glow
	_build_3d_viewport()

	label = Label.new()
	label.text = flavor_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-40, -26)
	label.size = Vector2(80, 14)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("#f5cd79"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.visible = false
	add_child(label)

	body_entered.connect(_on_body_entered)

func _build_3d_viewport() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	model_3d = Node3D.new()
	viewport.add_child(model_3d)

	# Briefcase body - dark gunmetal metallic
	_add_box(model_3d, Vector3.ZERO, Vector3(1.18, 0.34, 0.80), Color("#293038"), 0.45, 0.70)
	# Aluminum reinforced trim / edge rim
	_add_box(model_3d, Vector3(0, 0, 0), Vector3(1.20, 0.06, 0.82), Color("#7b8893"), 0.30, 0.85)
	# Twin brass latches
	_add_box(model_3d, Vector3(-0.35, 0.02, 0.41), Vector3(0.12, 0.12, 0.03), Color("#dab471"), 0.25, 0.90)
	_add_box(model_3d, Vector3(0.35, 0.02, 0.41), Vector3(0.12, 0.12, 0.03), Color("#dab471"), 0.25, 0.90)
	# Ergonomic handle & chrome brackets
	_add_box(model_3d, Vector3(0, 0.02, 0.48), Vector3(0.32, 0.06, 0.08), Color("#181b1e"), 0.80, 0.10)
	_add_box(model_3d, Vector3(-0.14, 0.02, 0.43), Vector3(0.04, 0.08, 0.06), Color("#8e9aa4"), 0.30, 0.80)
	_add_box(model_3d, Vector3(0.14, 0.02, 0.43), Vector3(0.04, 0.08, 0.06), Color("#8e9aa4"), 0.30, 0.80)
	# Corner reinforcing guards
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(model_3d, Vector3(sx * 0.56, 0, sz * 0.37), Vector3(0.10, 0.36, 0.10), Color("#414b54"), 0.40, 0.60)
	# Lacre discreto, sem emissão que denuncie o esconderijo.
	_add_box(model_3d, Vector3(0, 0.18, 0), Vector3(0.14, 0.02, 0.14), Color("#9b855b"), 0.80, 0.10)

	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	camera.position = Vector3(0, 2.5, 3.5)
	camera.look_at(Vector3.ZERO)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 1.3
	viewport.add_child(light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(40, 145, 0)
	fill_light.light_energy = 0.4
	viewport.add_child(fill_light)

	sprite_3d = Sprite2D.new()
	sprite_3d.texture = viewport.get_texture()
	sprite_3d.scale = Vector2.ONE * 0.28
	sprite_3d.position.y = -3
	model_3d.rotation.y = -0.35
	add_child(sprite_3d)

	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-32, -40, 64, 64)
	notifier.screen_entered.connect(func(): screen_visible = true)
	notifier.screen_exited.connect(func(): screen_visible = false)
	add_child(notifier)

func _add_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, rough: float = 0.6, metal: float = 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	return mesh

func _create_circle_polygon(radius: float, points: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(points):
		var ang = (float(i) / float(points)) * TAU
		arr.append(Vector2(cos(ang), sin(ang)) * radius)
	return arr

func _process(delta: float) -> void:
	if _is_collected:
		return
	_clock += delta * 2.2

	# If an external caller customized gem_poly (e.g. HarborCemetery memorial letter), honor 2D mode
	if gem_poly.color != Color("#a29bfe") or gem_poly.polygon.size() != 5:
		_use_3d = false

	if _use_3d and is_instance_valid(model_3d) and is_instance_valid(sprite_3d):
		if gem_poly.visible: gem_poly.visible = false
		if glow_circle.visible: glow_circle.visible = false
		sprite_3d.visible = true
		# Maleta apoiada no chão: pose fixa e uma única renderização.
		if screen_visible and not _presentation_rendered and is_instance_valid(viewport):
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_presentation_rendered = true
	else:
		if is_instance_valid(sprite_3d): sprite_3d.visible = false
		if is_instance_valid(viewport): viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if not gem_poly.visible: gem_poly.visible = true
		if not glow_circle.visible: glow_circle.visible = true
		if visual_root:
			visual_root.position.y = sin(_clock) * 3.0
			visual_root.rotation = sin(_clock * 0.6) * 0.18
		if glow_circle:
			glow_circle.scale = Vector2.ONE * (1.0 + sin(_clock * 1.8) * 0.15)

func _draw() -> void:
	if not _use_3d or _is_collected:
		return
	# Só sombra de contato; sem aro ou halo visível da rua.
	draw_circle(Vector2(0, 3), 9.0, Color(0.02, 0.04, 0.06, 0.28))

func _on_body_entered(body: Node2D) -> void:
	if _is_collected: return
	if not body.is_in_group("player"): return
	if not body.has_method("add_collectible"): return
	if not body.add_collectible(collectible_id, flavor_label): return
	_is_collected = true

	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = ProceduralAudio.get_powerup_stream()
	p.pitch_scale = 1.35
	p.volume_db = -4.0
	p.max_distance = 500.0
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	p.finished.connect(p.queue_free)

	if gem_poly: gem_poly.visible = false
	if glow_circle: glow_circle.visible = false
	if sprite_3d: sprite_3d.visible = false
	queue_redraw()
	label.visible = true

	var tw := create_tween().set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 22.0, 0.5)
	tw.tween_property(label, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(queue_free)
