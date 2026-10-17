extends Node3D
## Passenger coach and articulated diesel unit; real windows into the shared world.
## Geometry is instanced by material, not one draw call per seat/frame.
const PASSENGER_FOOT := Vector3(0.0, 0.84, 2.7)
const WINDOW_EYE := Vector3(0.06, 2.37, -1.50)
const ENGINE_LEAD := 9.15
var locomotive: Node3D
var solids: Array[Dictionary] = []
var _batches: Dictionary = {}
var _materials: Dictionary = {}
var _wheels: Array[MeshInstance3D] = []
var _wheel_angle := 0.0
var _doors: Array[Node3D] = []

func _ready() -> void:
	name = "PassengerTrain"
	set_meta("railway_train", true)
	_materials = {
		"paint": _material(Color("244c49"), .42, .25),
		"cream": _material(Color("d6d0bb"), .58, .15),
		"orange": _material(Color("b98753"), .5, .35),
		"metal": _material(Color("485356"), .4, .65),
		"roof": _material(Color("687575"), .62, .3),
		"rubber": _material(Color("20262a"), .92, .0, false, ""),
		"wood": _material(Color("6f5140"), .83, .0, false, "wood"),
		"seat": _material(Color("526e71"), .94, .0, false, "fabric"),
		"lamp": _material(Color("ecdcb0"), .6, .0, true),
		"glass": _material(Color("29434e"), .18, .4, false, ""),
	}
	_build_coach()
	locomotive = Node3D.new()
	locomotive.name = "DieselUnit"
	add_child(locomotive)
	locomotive.position.z = -ENGINE_LEAD
	_build_locomotive()
	_flush_batches()

func _build_coach() -> void:
	_box(self, "rubber", Vector3(2.58, .34, 9.65), Vector3(0, .51, 0))
	_box(self, "wood", Vector3(2.68, .14, 10), Vector3(0, .76, 0), true, "coach_floor")
	_arched_roof(self, "CoachRoof", 2.86, 10.2, Vector3(0, 2.78, 0), .36)
	for side in [-1.0, 1.0]:
		# Sill and window header stay solid; the open middle is a genuine view out.
		for z in [-2.98, 2.98]:
			_box(self, "paint", Vector3(.12, .78, 4.04), Vector3(side * 1.36, 1.19, z), true, "wall_sill")
		_box(self, "cream", Vector3(.12, .30, 10), Vector3(side * 1.36, 2.64, 0), true, "window_header")
		for z in [-2.98, 2.98]: _box(self, "orange", Vector3(.14, .11, 4.04), Vector3(side * 1.37, 1.49, z))
		for panel in [-1.0, 1.0]:
			var door := Node3D.new()
			door.name = "SlidingDoor"
			add_child(door)
			door.position = Vector3(side * 1.37, .84, panel * .46)
			door.set_meta("closed_z", panel * .46)
			door.set_meta("slide_direction", panel)
			_box(door, "paint", Vector3(.14, 1.69, .91), Vector3(0, .84, 0), true, "sliding_door")
			_box(door, "orange", Vector3(.16, .11, .91), Vector3(0, .65, 0))
			_box(door, "glass", Vector3(.155, .60, .62), Vector3(0, 1.12, 0))
			_box(door, "metal", Vector3(.19, .19, .045), Vector3(0, .74, -panel * .3))
			_doors.append(door)
		_box(self, "metal", Vector3(.38, .12, 1.90), Vector3(side * 1.51, .66, 0))
		for z in [-4.9, -2.95, -.98, .98, 2.95, 4.9]:
			_box(self, "cream", Vector3(.15, 1.02, .105), Vector3(side * 1.36, 2.05, z), true, "window_post")
		# Recessed seals and divided glazing read as windows, rather than an open tram.
		for z in [-3.92, -1.96, 1.96, 3.92]:
			_box(self, "rubber", Vector3(.025, .055, 1.80), Vector3(side * 1.375, 1.64, z))
			_box(self, "rubber", Vector3(.025, .055, 1.80), Vector3(side * 1.375, 2.45, z))
			_box(self, "metal", Vector3(.035, .055, 1.80), Vector3(side * 1.39, 2.22, z))
			_box(self, "glass", Vector3(.02, .19, 1.78), Vector3(side * 1.35, 2.34, z))
		for z in [-2.98, 2.98]:
			_box(self, "cream", Vector3(.035, .07, 4.04), Vector3(side * 1.43, .91, z))
		_box(self, "metal", Vector3(.10, .09, 10.12), Vector3(side * 1.42, 2.78, 0))
		# Two facing bays, clear centre aisle and unobstructed boarding vestibules.
		for z in [-3.7, -1.8, 1.8, 3.7]:
			var seat_x: float = side * .89
			_box(self, "metal", Vector3(.64, .35, .60), Vector3(seat_x, 1.01, z))
			_box(self, "seat", Vector3(.73, .16, .68), Vector3(seat_x, 1.22, z), true, "seat_base")
			var back_z: float = z + (.31 if z < 0 else -.31)
			_box(self, "seat", Vector3(.74, .69, .13), Vector3(seat_x, 1.61, back_z), true, "seat_back")
			_box(self, "wood", Vector3(.055, .075, .58), Vector3(side * .50, 1.41, z))
		_box(self, "metal", Vector3(.20, .055, 7.6), Vector3(side * 1.08, 2.62, 0))
	for z in [-3.2, 3.2]: _bogie(self, z)
	_box(self, "metal", Vector3(1.4, .28, 2.7), Vector3(0, .43, 0))
	for z in [-5.0, 5.0]:
		_box(self, "paint", Vector3(2.73, .77, .12), Vector3(0, 1.18, z), true, "end_sill")
		_box(self, "cream", Vector3(2.73, .30, .12), Vector3(0, 2.64, z), true, "end_header")
		for x in [-1.31, -.45, .45, 1.31]:
			_box(self, "cream", Vector3(.095, 1.05, .12), Vector3(x, 2.07, z), true, "end_post")
		_box(self, "metal", Vector3(.75, .10, .55), Vector3(0, .53, z + signf(z) * .24))
		_box(self, "cream", Vector3(2.74, .06, .14), Vector3(0, 1.57, z))
		for x in [-1.1, 1.1]:
			_box(self, "orange", Vector3(.15, .18, .045), Vector3(x, 1.34, z + signf(z) * .08))
	# Luminaires are emissive materials, no extra shadow maps or per-pixel light.
	for z in [-3.5, 0.0, 3.5]:
		_box(self, "metal", Vector3(.52, .06, .72), Vector3(0, 2.74, z))
		_box(self, "lamp", Vector3(.39, .045, .60), Vector3(0, 2.70, z))
	_box(self, "metal", Vector3(.26, .25, 1.7), Vector3(0, .51, -5.65))

func _build_locomotive() -> void:
	_box(locomotive, "rubber", Vector3(2.63, .43, 7.5), Vector3(0, .53, 0))
	_box(locomotive, "paint", Vector3(2.62, 1.36, 6.95), Vector3(0, 1.38, 0))
	_box(locomotive, "orange", Vector3(2.69, .17, 7.0), Vector3(0, 1.10, 0))
	_arched_roof(locomotive, "CabRoof", 2.73, 3.35, Vector3(0, 2.72, -1.73), .35)
	_box(locomotive, "cream", Vector3(2.66, .36, 3.0), Vector3(0, 2.03, -1.75))
	_box(locomotive, "glass", Vector3(2.42, .49, .065), Vector3(0, 2.41, -3.24))
	_box(locomotive, "cream", Vector3(.07, .58, .09), Vector3(0, 2.42, -3.30))
	for side in [-1.0, 1.0]:
		_box(locomotive, "glass", Vector3(.065, .48, 2.62), Vector3(side * 1.33, 2.41, -1.72))
		for z in [-3.15, -.3]:
			_box(locomotive, "cream", Vector3(.075, .57, .095), Vector3(side * 1.36, 2.42, z))
		_box(locomotive, "metal", Vector3(.1, .66, 2.9), Vector3(side * 1.35, 1.58, 1.56))
		for z in [0.3, .65, 1, 1.35, 1.7, 2.05, 2.4, 2.75]:
			_box(locomotive, "rubber", Vector3(.11, .055, .16), Vector3(side * 1.41, 1.73, z))
		_box(locomotive, "cream", Vector3(.035, .065, 7.0), Vector3(side * 1.36, 1.24, 0))
		_box(locomotive, "metal", Vector3(.14, .10, 7.3), Vector3(side * 1.35, .79, 0))
		# Cab doors and inset handles; no extra animated roof attachment.
		_box(locomotive, "cream", Vector3(.035, 1.31, .065), Vector3(side * 1.34, 1.47, -.43))
		_box(locomotive, "metal", Vector3(.065, .07, .26), Vector3(side * 1.38, 1.61, -.69))
		_box(locomotive, "lamp", Vector3(.27, .19, .08), Vector3(side * .83, 1.73, -3.52))
	for z in [-2.35, 2.45]: _bogie(locomotive, z)
	_arched_roof(locomotive, "EngineCover", 2.6, 3.65, Vector3(0, 2.02, 1.52), .18)
	# Flush exhaust grille replaces the isolated block above the engine cover.
	for z in [.55, .76, .97, 1.18, 1.39, 1.60, 1.81, 2.02, 2.23, 2.44]:
		_box(locomotive, "rubber", Vector3(1.35, .025, .065), Vector3(0, 2.205, z))
	_box(locomotive, "paint", Vector3(2.42, .31, .34), Vector3(0, 1.34, -3.51))
	_box(locomotive, "orange", Vector3(2.44, .075, .035), Vector3(0, 1.44, -3.70))
	_box(locomotive, "metal", Vector3(2.45, .24, .29), Vector3(0, .75, -3.78))
	_box(locomotive, "metal", Vector3(.28, .24, .55), Vector3(0, .54, 3.92))
	_solid(locomotive, Vector3(2.7, 2.2, 7.6), Vector3(0, 1.54, 0), "engine_hull")

func _material(color: Color, roughness: float, metallic: float, glow := false, surface := "metal") -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	if not glow and not surface.is_empty():
		preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(result, surface, 1.5, .22)
		# World-anchored mapping slides across a moving roof. Keep it on the vehicle.
		result.uv1_world_triplanar = false
		result.albedo_color = Color(minf(color.r * result.albedo_color.r, 1.0), minf(color.g * result.albedo_color.g, 1.0), minf(color.b * result.albedo_color.b, 1.0), color.a)
		result.roughness = roughness
	if glow:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = .65
	return result

func _bogie(parent: Node3D, z: float) -> void:
	_box(parent, "rubber", Vector3(1.95, .23, 1.95), Vector3(0, .49, z))
	for axle_z in [z - .62, z + .62]:
		_box(parent, "metal", Vector3(1.70, .12, .12), Vector3(0, .48, axle_z))
		for side in [-1.0, 1.0]:
			_wheel(parent, Vector3(side * .72, .48, axle_z))
			_box(parent, "metal", Vector3(.18, .20, .27), Vector3(side * 1.02, .48, axle_z))
	for side in [-1.0, 1.0]:
		_box(parent, "metal", Vector3(.11, .12, 1.84), Vector3(side * 1.07, .63, z))

func _arched_roof(parent: Node3D, node_name: String, width: float, length: float, center: Vector3, rise: float) -> void:
	# One low-poly extrusion per roof, with closed ends and no moving props.
	var profile := PackedVector2Array()
	for index in range(9):
		var angle := PI - float(index) * PI / 8.0
		profile.append(Vector2(cos(angle) * width * .5, sin(angle) * rise))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in profile.size():
		var next := (index + 1) % profile.size()
		var a := Vector3(profile[index].x, profile[index].y, -length * .5)
		var b := Vector3(profile[next].x, profile[next].y, -length * .5)
		var c := Vector3(profile[next].x, profile[next].y, length * .5)
		var d := Vector3(profile[index].x, profile[index].y, length * .5)
		_roof_triangle(surface, a, b, c)
		_roof_triangle(surface, a, c, d)
		_roof_triangle(surface, Vector3(0, rise * .4, -length * .5), b, a)
		_roof_triangle(surface, Vector3(0, rise * .4, length * .5), d, c)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = surface.commit()
	instance.material_override = _materials.roof
	instance.position = center
	parent.add_child(instance)
	var hull := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for point in profile:
		for z in [-length * .5, length * .5]:
			points.append(Vector3(point.x, point.y - rise * .5, z))
	hull.points = points
	_solid(parent, Vector3(width, rise, length), center + Vector3.UP * rise * .5, node_name.to_snake_case(), hull)

func _roof_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.set_normal((c - a).cross(b - a).normalized())
	for point in [a, b, c]:
		surface.set_uv(Vector2(point.x, point.z))
		surface.add_vertex(point)

func _box(parent: Node3D, material: String, size: Vector3, center: Vector3, solid := false, solid_id := "") -> void:
	var key := str(parent.get_instance_id()) + ":" + material
	if not _batches.has(key): _batches[key] = {"parent": parent, "material": material, "transforms": []}
	_batches[key].transforms.append(Transform3D(Basis.from_scale(size), center))
	if solid: _solid(parent, size, center, solid_id)

func _solid(parent: Node3D, size: Vector3, center: Vector3, id: String, shape_override: Shape3D = null) -> void:
	var body := parent.get_node_or_null("Solids") as AnimatableBody3D
	if body == null:
		body = AnimatableBody3D.new()
		body.name = "Solids"
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = false
		parent.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = shape_override if shape_override != null else box
	shape.position = center
	shape.set_meta("interior_solid_id", id)
	body.add_child(shape)
	solids.append({"id": id, "body": body, "shape": shape, "size": size, "position": center})

func _wheel(parent: Node3D, point: Vector3) -> void:
	var wheel := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = .33
	mesh.bottom_radius = .33
	mesh.height = .17
	mesh.radial_segments = 12
	mesh.material = _materials.metal
	wheel.mesh = mesh
	wheel.position = point
	wheel.rotation.z = PI * .5
	parent.add_child(wheel)
	_wheels.append(wheel)

func _flush_batches() -> void:
	for batch in _batches.values():
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = _materials[batch.material]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = batch.transforms.size()
		for index in batch.transforms.size(): multimesh.set_instance_transform(index, batch.transforms[index])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.name = "Batch_" + str(batch.material)
		batch.parent.add_child(instance)
	_batches.clear()

func set_engine_transform(world_transform: Transform3D) -> void:
	if is_instance_valid(locomotive): locomotive.global_transform = world_transform

func advance_wheels(distance: float) -> void:
	_wheel_angle = fmod(_wheel_angle + distance / .33, TAU)
	for wheel in _wheels: wheel.rotation = Vector3(_wheel_angle, 0, PI * .5)

func set_doors_open(open: bool) -> void:
	for door in _doors:
		door.position.z = float(door.get_meta("closed_z")) + (float(door.get_meta("slide_direction")) * .87 if open else 0.0)
