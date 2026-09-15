extends Node2D

## Real mesh, presented through the same 3D-to-2D approach as street props.
## A sliding lid does not change its viewing angle: render once, reuse while
## dragging instead of keeping another 3D viewport rendering every frame.
var viewport: SubViewport
var display: Sprite2D
var model: Node3D

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "CoverViewport"
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	model = Node3D.new()
	model.name = "CastIronCover"
	viewport.add_child(model)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("#42484a")
	iron.metallic = 0.65
	iron.roughness = 0.78
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color("#646967")
	edge.metallic = 0.55
	edge.roughness = 0.72
	var base := CylinderMesh.new()
	base.top_radius = 0.50
	base.bottom_radius = 0.49
	base.height = 0.055
	base.radial_segments = 48
	_add_mesh(base, Vector3.ZERO, iron)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.445
	ring.outer_radius = 0.482
	ring.rings = 48
	ring.ring_segments = 8
	_add_mesh(ring, Vector3(0, 0.032, 0), edge)
	# Raised cast grid, clipped to the round plate, and two recessed lifting slots.
	for index in range(-3, 4):
		var at := float(index) * 0.105
		var length := sqrt(0.40 * 0.40 - at * at) * 2.0
		var rib := BoxMesh.new()
		rib.size = Vector3(length, 0.014, 0.015)
		_add_mesh(rib, Vector3(0, 0.034, at), edge)
		var cross := BoxMesh.new()
		cross.size = Vector3(0.015, 0.014, length)
		_add_mesh(cross, Vector3(at, 0.034, 0), edge)
	var slot_material := StandardMaterial3D.new()
	slot_material.albedo_color = Color("#101518")
	slot_material.roughness = 1.0
	for side in [-1.0, 1.0]:
		var slot := BoxMesh.new()
		slot.size = Vector3(0.12, 0.006, 0.043)
		_add_mesh(slot, Vector3(0, 0.031, side * 0.365), slot_material)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	camera.position = Vector3(0, 3, 4.2)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#c6d3d9")
	environment.environment.ambient_light_energy = 0.65
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 1.2
	light.shadow_enabled = false
	viewport.add_child(light)
	display = Sprite2D.new()
	display.texture = viewport.get_texture()
	display.scale = Vector2.ONE * 0.85
	add_child(display)

func _add_mesh(mesh: Mesh, at: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	model.add_child(instance)
