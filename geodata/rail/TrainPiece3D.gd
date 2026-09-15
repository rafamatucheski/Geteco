extends Node2D
## Modelo real em vista ortográfica; a câmera permanece alinhada à câmera do mundo.
## Só renderizamos outra vez quando muda a orientação de uma peça visível.
var wagon_index := -1
var viewport: SubViewport
var model: Node3D
var display: Sprite2D
var _last_heading := INF
var _materials: Dictionary = {}

func _ready() -> void:
	# Cached renders must contain the requested pose, never a transient physics
	# interpolation angle that would then remain frozen on a straight track.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport = SubViewport.new()
	viewport.name = "TrainModelViewport"
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var projection := Node3D.new()
	# Compensa o encurtamento do chão pela câmera, preservando engates nas curvas.
	projection.scale.z = 1.25
	stage.add_child(projection)
	model = Node3D.new()
	projection.add_child(model)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c5d4df")
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -32, 0)
	light.light_color = Color("ffe6c3")
	light.light_energy = 1.25
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.8
	camera.position = Vector3(0, 16, 12)
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	display = Sprite2D.new()
	display.name = "Train3DDisplay"
	display.texture = viewport.get_texture()
	display.scale = Vector2.ONE * 0.5
	add_child(display)
	_build()
	queue_redraw()

func update_heading(heading: float) -> void:
	# O pai segue o trilho em 2D; a imagem não gira como uma placa plana.
	global_rotation = 0.0
	if modulate.a <= 0.001: return
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		var half_view := get_viewport_rect().size * 0.5 / camera.zoom
		if not Rect2(camera.get_screen_center_position() - half_view, half_view * 2.0).grow(160.0).has_point(global_position): return
	if absf(angle_difference(_last_heading, heading)) < 0.006:
		return
	_last_heading = heading
	model.rotation.y = -heading
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()

func set_reveal(reveal: ShaderMaterial) -> void:
	display.material = reveal
	material = reveal

func _draw() -> void:
	if not is_finite(_last_heading): return
	draw_set_transform(Vector2(3, 5), _last_heading)
	var length := 76.0 if wagon_index < 0 else 52.0
	draw_style_box(_shadow_style(), Rect2(-length * 0.5, -12, length, 26))

func _shadow_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.02, 0.025, 0.28)
	style.set_corner_radius_all(8)
	return style

func _mat(hex: String) -> StandardMaterial3D:
	if not _materials.has(hex):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(hex)
		mat.roughness = 0.72
		_materials[hex] = mat
	return _materials[hex]

func _box(at: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, at, color)

func _mesh(mesh: Mesh, at: Vector3, color: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = _mat(color)
	model.add_child(part)
	return part

func _cylinder(at: Vector3, radius: float, height: float, color: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	return _mesh(mesh, at, color)

func _build() -> void:
	var engine := wagon_index < 0
	var length := 7.6 if engine else 5.2
	_box(Vector3(0, 0.55, 0), Vector3(length, 0.32, 2.28), "30383b")
	for x in [-length * 0.31, length * 0.31]:
		_box(Vector3(x, 0.32, 0), Vector3(1.05, 0.35, 1.65), "24282a")
		for axle in [-0.35, 0.35]:
			for side in [-1.0, 1.0]:
				var wheel := _cylinder(Vector3(x + axle, 0.30, side * 1.02), 0.30, 0.20, "171c20")
				wheel.rotation.x = PI * 0.5
	for end in [-1.0, 1.0]:
		_box(Vector3(end * (length * 0.5 + 0.22), 0.5, 0), Vector3(0.5, 0.16, 0.24), "5a6162")
	if engine:
		_build_engine()
		return
	var colors := ["426f86", "aaaba0", "637b50", "8e453a", "b38442", "587b7b"]
	var color: String = colors[wagon_index % colors.size()]
	match wagon_index % 4:
		0: _container(color)
		1: _tank(color)
		2: _hopper(color)
		3: _timber(color)

func _build_engine() -> void:
	_box(Vector3(-0.9, 1.35, 0), Vector3(4.4, 1.35, 1.75), "b44e2d")
	_box(Vector3(-0.9, 2.04, 0), Vector3(4.5, 0.14, 1.85), "d36b3c")
	_box(Vector3(1.85, 1.65, 0), Vector3(1.65, 2.0, 2.1), "dfb34b")
	_box(Vector3(1.85, 2.7, 0), Vector3(1.9, 0.17, 2.34), "e7ce81")
	_box(Vector3(3.1, 1.1, 0), Vector3(0.95, 0.8, 1.75), "b34e2f")
	_box(Vector3(2.69, 2.16, 0), Vector3(0.035, 0.60, 1.60), "244653")
	for side in [-1.0, 1.0]:
		_box(Vector3(1.83, 2.18, side * 1.058), Vector3(1.05, 0.62, 0.035), "315f71")
		_box(Vector3(-0.4, 0.85, side * 1.15), Vector3(6.4, 0.13, 0.18), "e4be51")
		_box(Vector3(-0.9, 1.85, side * 1.20), Vector3(4.8, 0.055, 0.055), "d1bf8b")
		for x in [-3.1, -1.9, -0.7, 0.6]:
			_box(Vector3(x, 1.35, side * 1.20), Vector3(0.05, 1.0, 0.05), "bdac7f")
		for x in [-2.9, -2.6, -2.3, -2.0, -1.7]:
			_box(Vector3(x, 1.42, side * 0.886), Vector3(0.10, 0.85, 0.025), "523a30")
		_box(Vector3(3.60, 1.32, side * 0.58), Vector3(0.08, 0.20, 0.25), "fff1b4")
		_box(Vector3(3.7, 0.55, side * 0.68), Vector3(0.10, 0.25, 0.30), "d8b65b")
	for x in [-2.25, -0.85]:
		_cylinder(Vector3(x, 2.16, 0), 0.52, 0.12, "30383c")
		for offset in [-0.25, 0.0, 0.25]:
			_box(Vector3(x + offset, 2.23, 0), Vector3(0.045, 0.025, 0.8), "7d8583")
	_cylinder(Vector3(0.45, 2.27, 0), 0.15, 0.48, "33393b")
	_box(Vector3(1.8, 2.9, 0.4), Vector3(0.4, 0.13, 0.14), "777568")

func _container(color: String) -> void:
	_box(Vector3(0, 1.58, 0), Vector3(4.75, 1.78, 2.05), color)
	for x in range(15):
		var pos := -2.2 + float(x) * 0.31
		_box(Vector3(pos, 2.50, 0), Vector3(0.065, 0.07, 2.06), color)
		for side in [-1.0, 1.0]:
			_box(Vector3(pos, 1.58, side * 1.05), Vector3(0.065, 1.78, 0.06), color)
	for side in [-1.0, 1.0]:
		_box(Vector3(2.40, 1.58, side * 0.45), Vector3(0.04, 1.60, 0.04), "c4bfa9")

func _tank(color: String) -> void:
	var tank := _cylinder(Vector3(0, 1.6, 0), 0.94, 4.4, color)
	tank.rotation.z = PI * 0.5
	for x in [-2.2, 2.2]:
		var cap := SphereMesh.new()
		cap.radius = 0.94
		cap.height = 1.88
		var end := _mesh(cap, Vector3(x, 1.6, 0), color)
		end.scale.x = 0.22
	_cylinder(Vector3(0, 2.57, 0), 0.27, 0.22, "555d5b")
	_box(Vector3(0, 2.68, 0.5), Vector3(1.65, 0.09, 0.6), "505859")
	for y in range(5):
		_box(Vector3(0, 0.8 + y * 0.36, 1.03), Vector3(0.65, 0.045, 0.07), "505859")
	for x in [-0.34, 0.34]:
		_box(Vector3(x, 1.62, 1.03), Vector3(0.045, 1.85, 0.07), "505859")

func _hopper(color: String) -> void:
	_box(Vector3(0, 0.9, 0), Vector3(4.6, 0.4, 1.8), color)
	for side in [-1.0, 1.0]:
		_box(Vector3(0, 1.65, side * 0.99), Vector3(4.8, 1.5, 0.16), color)
		for x in [-2.2, -1.1, 0.0, 1.1, 2.2]:
			_box(Vector3(x, 1.65, side * 1.10), Vector3(0.10, 1.5, 0.12), color)
	for x in [-2.32, 2.32]:
		_box(Vector3(x, 1.65, 0), Vector3(0.16, 1.5, 2.0), color)
	for i in range(18):
		var coal := SphereMesh.new()
		coal.radius = 0.35
		coal.height = 0.46
		_mesh(coal, Vector3(-1.9 + (i % 6) * 0.74, 1.99 + (i % 2) * 0.09, -0.56 + (i / 6) * 0.53), "343b3c")

func _timber(color: String) -> void:
	_box(Vector3(0, 0.8, 0), Vector3(4.9, 0.2, 2.12), color)
	for i in range(5):
		var log_piece := _cylinder(Vector3(0, 1.15 + (i / 3) * 0.51, -0.62 + (i % 3) * 0.62), 0.31, 4.4, "806047")
		log_piece.rotation.z = PI * 0.5
	for x in [-1.7, 1.7]:
		for side in [-1.0, 1.0]:
			_box(Vector3(x, 1.25, side * 1.0), Vector3(0.1, 1.1, 0.1), "a69777")
