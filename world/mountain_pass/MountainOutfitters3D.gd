extends Node2D

var camera: Camera3D
var sprite: Sprite2D
var viewport_3d: SubViewport
var door_leaf: MeshInstance3D
var door_handle: MeshInstance3D
var _open_amount := 0.0

func project_floor(point: Vector2) -> Vector2:
	return (camera.unproject_position(Vector3(point.x,0,point.y))-camera.unproject_position(Vector3.ZERO))*sprite.scale

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport_3d = viewport
	viewport.size = Vector2i(768, 640)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var wood := _material(Color("68462f"))
	var trim := _material(Color("b3956f"))
	var roof := _material(Color("303f49"))
	var snow := _material(Color("d5e5ed"))
	var dark := _material(Color("202b32"))
	var warm := _material(Color("ffd18a"), true)
	var red := _material(Color("aa4e3f"))
	_mesh(world, Vector3(0, 0.12, 0), Vector3(6.5, 0.24, 4.0), trim)
	_mesh(world, Vector3(0, 1.4, -0.45), Vector3(6, 2.6, 2.7), wood)
	for i in 13:
		_mesh(world, Vector3(0, 0.3 + i * 0.2, 0.925), Vector3(6.04, 0.045, 0.06), trim)
	for side in [-1.0, 1.0]:
		_mesh(world, Vector3(side * 1.85, 1.5, 0.98), Vector3(1.5, 1.3, 0.09), trim)
		_mesh(world, Vector3(side * 1.85, 1.5, 1.035), Vector3(1.28, 1.09, 0.04), warm)
		_mesh(world, Vector3(side * 1.85, 1.5, 1.07), Vector3(0.06, 1.15, 0.04), dark)
		_mesh(world, Vector3(side * 1.85, 1.5, 1.07), Vector3(1.3, 0.06, 0.04), dark)
		_mesh(world, Vector3(side * 2.9, 1.25, 1.8), Vector3(0.16, 2.4, 0.16), trim)
	door_leaf = _mesh(world, Vector3(0, 1.13, 0.99), Vector3(1.05, 2.1, 0.1), dark)
	door_handle = _mesh(world, Vector3(0.35, 1.1, 1.07), Vector3(0.08, 0.12, 0.08), warm)
	var canopy := _mesh(world, Vector3(0, 2.55, 1.25), Vector3(6.5, 0.12, 1.7), red)
	canopy.rotation.x = 0.12
	for i in 11:
		_mesh(world, Vector3(-3 + i * 0.6, 2.45, 2.05), Vector3(0.27, 0.22, 0.08), trim)
	for side in [-1.0, 1.0]:
		var panel := _mesh(world, Vector3(side * 1.55, 3.0, -0.45), Vector3(3.5, 0.15, 3.2), roof)
		panel.rotation.z = side * -0.24
		var cap := _mesh(world, Vector3(side * 1.55, 3.11, -0.45), Vector3(3.5, 0.1, 3.22), snow)
		cap.rotation.z = side * -0.24
	_mesh(world, Vector3(2, 3.25, -1.3), Vector3(0.55, 1.3, 0.5), dark)
	_mesh(world, Vector3(2, 3.95, -1.3), Vector3(0.7, 0.12, 0.65), snow)
	# Garments on a porch rack: three distinct padded coats and sleeves.
	for i in 3:
		var coat := _material([Color("b34f36"), Color("cfaa54"), Color("427987")][i])
		var x := -2.2 + i * 0.55
		_mesh(world, Vector3(x, 0.85, 1.55), Vector3(0.37, 0.65, 0.22), coat)
		for side in [-1.0, 1.0]:
			_mesh(world, Vector3(x + side * 0.23, 0.9, 1.55), Vector3(0.14, 0.48, 0.2), coat)
	_mesh(world, Vector3(-1.65, 1.4, 1.55), Vector3(1.85, 0.06, 0.06), dark)
	var sign := Label3D.new()
	sign.text = "ÚLTIMO ABRIGO"
	sign.font_size = 68
	sign.pixel_size = .004
	sign.modulate = Color("f1dab2")
	sign.position = Vector3(0, 2.44, 1.09)
	world.add_child(sign)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0, 8, 5)
	camera.look_at(Vector3(0, 1.3, 0))
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.reset_physics_interpolation()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	viewport.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b2c5d4")
	environment.environment.ambient_light_energy = 0.65
	viewport.add_child(environment)
	sprite = Sprite2D.new()
	sprite.texture = viewport.get_texture()
	var pixels_per_metre := camera.unproject_position(Vector3.RIGHT).distance_to(camera.unproject_position(Vector3.ZERO))
	sprite.scale = Vector2.ONE * 18.0 / pixels_per_metre
	sprite.position = (Vector2(viewport.size)*0.5-camera.unproject_position(Vector3.ZERO))*sprite.scale
	add_child(sprite)
	# Render the static shop only when approached, instead of compiling and drawing
	# an offscreen viewport during the streaming batch.
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-180,-180,360,320)
	notifier.screen_entered.connect(func(): viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
	add_child(notifier)

func set_open_amount(value: float) -> void:
	_open_amount = clampf(value, 0.0, 1.0)
	if not is_instance_valid(door_leaf): return
	door_leaf.position.x = -1.15 * _open_amount
	door_handle.position.x = .35 - 1.15 * _open_amount
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	material.emission_enabled = glow
	material.emission = color
	material.emission_energy_multiplier = 0.45
	return material

func _mesh(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	instance.position = pos
	parent.add_child(instance)
	return instance
