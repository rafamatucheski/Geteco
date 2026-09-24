extends Node3D
## A modular Brazilian intercity terminal, authored in calibrated ground pixels.
const COACH := preload("res://world/harbor/terminal/HarborCoachModel3D.gd")
const PPM := 18.0
const OVERHEAD_LAYER := 64
const FLOOR_Y := 0.76822128
const COACH_CENTERS := [-141.0, -41.0, 59.0, 159.0]
var solids: Array[Dictionary] = []
var parked_coaches: Array[Node3D] = []
var materials: Dictionary = {}
var _mesh_layer := 1
var guard_arm: Node3D
var _guard_authorizing := false
var _guard_wave := 0.0

func set_guard_authorization(active: bool) -> void:
	_guard_authorizing = active
	set_process(true)

func _process(delta: float) -> void:
	if not is_instance_valid(guard_arm): return
	_guard_wave += delta
	var angle := -1.65 + sin(_guard_wave * 5.0) * 0.18 if _guard_authorizing else -0.15
	guard_arm.rotation.z = move_toward(guard_arm.rotation.z, angle, delta * 3.0)
	if not _guard_authorizing and is_equal_approx(guard_arm.rotation.z, angle): set_process(false)

func _ready() -> void:
	for pair in [["asphalt", "3d484e"], ["concrete", "8f9588"], ["curb", "aaad98"], ["wall", "a3a28d"], ["roof", "344e54"], ["metal", "587174"], ["trim", "203c44"], ["glass", "234c58"], ["white", "d4c9a9"], ["yellow", "d2a547"], ["wood", "916349"], ["green", "4c7865"]]:
		materials[pair[0]] = _mat(Color(pair[1]))
	for kind in ["asphalt","concrete"]:
		var pavement: StandardMaterial3D = materials[kind]
		pavement.albedo_texture=preload("res://world/harbor/UrbanGround.gd").texture(kind)
		pavement.uv1_triplanar=true
		pavement.uv1_world_triplanar=true
		pavement.uv1_scale=Vector3.ONE*.08
		pavement.roughness=.96
	materials["light"] = _mat(Color("ffdda0"), true)
	_build_ground()
	_build_circuit_markings()
	_build_headhouse()
	_build_platforms()
	_build_guardhouse()
	_build_floodlights()
	# Arquitetura e ônibus estacionados compartilham superfícies por material.
	# O ônibus em circulação e os passageiros são acrescentados depois.
	for coach in parked_coaches:
		preload("res://cars/VehicleMeshBatcher.gd").batch_model(coach)
	preload("res://cars/VehicleMeshBatcher.gd").batch_model(self)

static func floor_from_local(point: Vector2) -> Vector3:
	return Vector3(point.x / PPM, 0, point.y / (PPM * FLOOR_Y))

func _build_ground() -> void:
	_slab(Rect2(-199, -239, 598, 338), -0.045, 0.08, "asphalt")
	# Raised passenger concourse is continuous behind every covered bay.
	_slab(Rect2(-190, -185, 400, 36), 0.06, 0.12, "concrete")
	# Level crossing through the manoeuvring apron; no raised sidewalk under buses.
	_slab(Rect2(-195, -3, 405, 23), 0.006, 0.012, "asphalt")
	for x in range(-189, 209, 13):
		_slab(Rect2(x, 0, 6, 16), 0.015, 0.01, "white")
	_slab(Rect2(-192, -151, 404, 3), 0.14, 0.10, "curb")
	for x in [-187.0, -91.0, 9.0, 109.0, 209.0]:
		_slab(Rect2(x, -149, 2, 120), 0.015, 0.025, "yellow")
	for x in COACH_CENTERS:
		_slab(Rect2(x - 37, -31, 74, 2), 0.014, 0.025, "yellow")
		var marking := _label("ÔNIBUS", Vector3(x / PPM, 0.025, -22 / (PPM * FLOOR_Y)), 42, "yellow")
		marking.rotation.x = -PI / 2.0
	# Zebra crossings join the open foreground promenade to the sidewalks.
	for i in 8:
		_slab(Rect2(-29 + i * 9, 27, 5, 36), 0.012, 0.025, "white")
	# Outer perimeter allows the south promenade and both bus gates to remain open.
	_slab(Rect2(-199, -239, 599, 3), 0.1, 0.2, "curb")
	_slab(Rect2(-199, -239, 3, 248), 0.1, 0.2, "curb")
	_slab(Rect2(396, -239, 3, 335), 0.1, 0.2, "curb")

func _build_headhouse() -> void:
	_slab(Rect2(-190, -232, 400, 49), 1.47, 2.94, "wall")
	_add_rect_solid(Rect2(-190, -232, 400, 49), "TerminalHeadHouse")
	_slab(Rect2(-194, -236, 408, 57), 3.09, 0.25, "curb")
	# Roof ribs, clerestory and roof equipment establish scale from above.
	for i in 17:
		_slab(Rect2(-190 + i * 25, -232, 1.6, 49), 3.24, 0.10, "wall")
	for x in [-149.0, -102.0, 131.0, 173.0]:
		_box_at(Vector2(x, -209), 3.51, Vector3(1.30, 0.50, 1.33), "metal")
		for offset in [-0.40, -0.15, 0.10, 0.35]:
			_box_at(Vector2(x, -209), 3.78, Vector3(1.05, 0.025, 0.055), "trim").position.z += offset
	for x in [-147.0, -85.0, 84.0, 146.0]:
		_box_at(Vector2(x, -182), 1.67, Vector3(2.70, 1.27, 0.10), "trim")
		_box_at(Vector2(x, -180.9), 1.69, Vector3(2.43, 1.05, 0.07), "glass")
		_box_at(Vector2(x, -179), 1.09, Vector3(2.80, 0.13, 0.35), "curb")
		_box_at(Vector2(x, -179.8), 1.65, Vector3(0.05, 1.07, 0.07), "metal")
	# Open-looking glazed central passenger entrance.
	_box_at(Vector2(10, -182), 1.46, Vector3(3.0, 2.60, 0.12), "trim")
	for x in [-3.0, 23.0]:
		_box_at(Vector2(x, -180), 1.45, Vector3(1.28, 2.32, 0.08), "glass")
		_box_at(Vector2(x, -178), 1.36, Vector3(0.045, 0.37, 0.09), "curb")
	_sign("BILHETERIA", Vector2(-115, -179), 2.64, Vector2(5.85, 0.47), 46)
	_sign("EMBARQUE", Vector2(10, -179), 2.73, Vector2(3.4, 0.48), 43)
	_sign("LANCHONETE", Vector2(117, -179), 2.64, Vector2(6.0, 0.47), 45)

func _build_circuit_markings() -> void:
	# The apron connects the platforms with separate street arrival/departure lanes.
	_slab(Rect2(-199, 70, 598, 100), -0.045, 0.08, "asphalt")
	for y in [124.0, 145.0]:
		for x in [250.0, 360.0]:
			_paint_line(Vector2(x - 21, y), Vector2(x + 21, y), 1.2, "white")
	for x in COACH_CENTERS:
		_paint_line(Vector2(x, -23), Vector2(x, 2), 1.5, "white")

func _paint_line(start: Vector2, end: Vector2, width: float, material: String) -> void:
	var from := floor_from_local(start)
	var to := floor_from_local(end)
	var delta := to - from
	var line := _box_at((start + end) * 0.5, 0.027, Vector3(width / PPM, 0.018, delta.length()), material)
	line.rotation.y = atan2(delta.x, delta.z)

func _build_platforms() -> void:
	# Four independent folded metal canopy modules, carried by slim steel columns.
	for i in 4:
		var x: float = COACH_CENTERS[i]
		for edge in [-45.0, 45.0]:
			for y in [-171.0, -98.0]:
				_box_at(Vector2(x + edge, y), 1.55, Vector3(0.18, 3.1, 0.18), "metal")
				_box_at(Vector2(x + edge, y), 0.23, Vector3(0.35, 0.46, 0.34), "curb")
				_add_rect_solid(Rect2(x + edge - 3, y - 3, 6, 6), "CanopyColumn")
		for side in [-1.0, 1.0]:
			var roof := _box_at(Vector2(x + side * 23, -136), 3.20, Vector3(2.74, 0.14, 5.77), "roof")
			roof.rotation.z = side * 0.075
			for rib in 5:
				var beam := _box_at(Vector2(x + side * 23, -169 + rib * 17), 3.26, Vector3(2.72, 0.055, 0.06), "metal")
				beam.rotation.z = side * 0.075
		_box_at(Vector2(x, -136), 3.32, Vector3(0.10, 0.13, 5.86), "curb")
		_box_at(Vector2(x, -97), 3.11, Vector3(5.42, 0.34, 0.10), "trim")
		_box_at(Vector2(x, -171), 3.06, Vector3(5.44, 0.15, 0.12), "metal")
		_box_at(Vector2(x, -108), 3.02, Vector3(2.7, 0.05, 0.12), "light")
		_sign("%02d" % (i + 1), Vector2(x + 32, -95), 2.85, Vector2(1.02, 0.72), 79)
		# Metal waiting benches and travelers' rolling cases under the canopy.
		_bench(Vector2(x + 29, -162))
		_box_at(Vector2(x + 40, -157), 0.36, Vector3(0.38, 0.68, 0.31), "wood" if i % 2 == 0 else "green")
		_box_at(Vector2(x + 40, -157), 0.83, Vector3(0.22, 0.29, 0.035), "trim")
	# Arrival gantry clears coach roofs, below the elevated rail's screen
	# silhouette. Its outer posts leave every coach bay free.
	_mesh_layer = 1
	for x in [-190.0, 209.0]:
		_box_at(Vector2(x, -55), 1.68, Vector3(0.15, 3.36, 0.15), "metal")
		_add_rect_solid(Rect2(x - 3, -58, 6, 6), "ArrivalGantryPost")
	# Standalone front amenities remain visible below the roof edge.
	_sign("INFORMAÇÕES", Vector2(-179, -73), 2.04, Vector2(1.15, 0.42), 24)
	_box_at(Vector2(-179, -73), 0.88, Vector3(1.10, 1.76, 0.66), "green")
	_box_at(Vector2(-179, -68), 1.18, Vector3(0.73, 0.66, 0.08), "glass")
	_add_rect_solid(Rect2(-190, -79, 22, 12), "InformationKiosk")

func _build_floodlights() -> void:
	# Keep the lamp bases outside the swept envelopes of the two outer coach
	# bays. The former positions sat exactly where platforms 1 and 4 turn.
	for x in [-260.0, 430.0]:
		var point := Vector2(x, 38)
		_box_at(point, 0.18, Vector3(0.65, 0.36, 0.65), "curb")
		_add_rect_solid(Rect2(point - Vector2(6, 6), Vector2(12, 12)), "FloodlightBase")
		_mesh_layer = OVERHEAD_LAYER
		_box_at(point, 3.5, Vector3(0.16, 7.0, 0.16), "metal")
		_box_at(point, 6.9, Vector3(2.8, 0.16, 0.24), "metal")
		for side in [-1.0, 1.0]:
			var head := point + Vector2(side * 19, 0)
			_box_at(head, 6.8, Vector3(1.15, 0.70, 0.35), "trim")
			_box_at(head + Vector2(0, 3), 6.75, Vector3(0.96, 0.51, 0.06), "light")
		_mesh_layer = 1

func _build_guardhouse() -> void:
	# Control booth separates the two street driveways, clear of the swept hulls.
	_mesh_layer = preload("res://world/harbor/terminal/HarborTerminalAccess.gd").FOREGROUND_LAYER
	_slab(Rect2(282, 83, 45, 32), 0.09, 0.18, "concrete")
	_slab(Rect2(289, 87, 31, 24), 1.00, 2.00, "wall")
	_add_rect_solid(Rect2(289, 87, 31, 24), "GuardHouse")
	_slab(Rect2(286, 84, 37, 30), 2.15, 0.19, "roof")
	_box_at(Vector2(305, 112), 1.48, Vector3(1.45, 0.78, 0.07), "glass")
	# The attendant is visible at the service window and acknowledges each request.
	_box_at(Vector2(305, 113.2), 1.37, Vector3(.40, .47, .20), "trim")
	var face := MeshInstance3D.new()
	var head := SphereMesh.new()
	head.radius = .145
	head.height = .29
	face.mesh = head
	face.material_override = _mat(Color("bb8b66"))
	face.position = floor_from_local(Vector2(305, 113.5)) + Vector3.UP * 1.72
	face.layers = _mesh_layer
	add_child(face)
	_box_at(Vector2(305, 113.5), 1.85, Vector3(.33, .07, .29), "trim")
	guard_arm = Node3D.new()
	guard_arm.name = "GuardAcknowledgment"
	guard_arm.position = floor_from_local(Vector2(310, 114)) + Vector3.UP * 1.53
	add_child(guard_arm)
	var sleeve := MeshInstance3D.new()
	var sleeve_mesh := BoxMesh.new()
	sleeve_mesh.size = Vector3(.13, .40, .15)
	sleeve.mesh = sleeve_mesh
	sleeve.material_override = materials.trim
	sleeve.position.y = -.2
	sleeve.layers = _mesh_layer
	guard_arm.add_child(sleeve)
	var hand := MeshInstance3D.new()
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = .07
	hand_mesh.height = .14
	hand.mesh = hand_mesh
	hand.material_override = face.material_override
	hand.position.y = -.42
	hand.layers = _mesh_layer
	guard_arm.add_child(hand)
	for x in [249.0, 360.0]:
		_sign("SAÍDA" if x < 300 else "ENTRADA", Vector2(x, 125), 3.4, Vector2(2.65, 0.54), 42)
		for side in [-38.0, 38.0]:
			_box_at(Vector2(x + side, 125), 1.7, Vector3(0.1, 3.4, 0.1), "metal")
	_mesh_layer = 1

func _bench(point: Vector2) -> void:
	_box_at(point, 0.53, Vector3(1.9, 0.12, 0.48), "wood")
	_box_at(point + Vector2(0, -3), 0.86, Vector3(1.9, 0.51, 0.09), "wood")
	for x in [-0.73, 0.73]:
		var leg := _box_at(point, 0.24, Vector3(0.09, 0.46, 0.43), "metal")
		leg.position.x += x
	_add_rect_solid(Rect2(point - Vector2(18, 5), Vector2(36, 10)), "WaitingBench")

func _add_rect_solid(rect: Rect2, label: String) -> void:
	var points := PackedVector3Array([floor_from_local(rect.position), floor_from_local(Vector2(rect.end.x, rect.position.y)), floor_from_local(rect.end), floor_from_local(Vector2(rect.position.x, rect.end.y))])
	solids.append({"name": label, "polygon": points})

func _slab(rect: Rect2, height: float, thickness: float, material: String) -> MeshInstance3D:
	return _box_at(rect.get_center(), height, Vector3(rect.size.x / PPM, thickness, rect.size.y / (PPM * FLOOR_Y)), material)

func _box_at(point: Vector2, height: float, size: Vector3, material: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = materials[material]
	instance.layers = _mesh_layer
	instance.position = floor_from_local(point) + Vector3.UP * height
	add_child(instance)
	return instance

func _mat(color: Color, glow := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.75
	result.emission_enabled = glow
	result.emission = color
	result.emission_energy_multiplier = 0.45
	return result

func _label(value: String, pos: Vector3, font_size: int, material: String) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.layers = _mesh_layer
	label.font_size = font_size
	label.pixel_size = 0.006
	label.modulate = materials[material].albedo_color
	label.outline_size = 0
	label.position = pos
	add_child(label)
	return label

func _sign(value: String, point: Vector2, height: float, size: Vector2, font_size: int) -> void:
	_box_at(point, height, Vector3(size.x, size.y, 0.10), "trim")
	var label := _label(value, floor_from_local(point) + Vector3(0, height, 0.07), font_size, "white")
	var text_width := ThemeDB.fallback_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	label.pixel_size = minf(size.x * 0.9 / maxf(text_width, 1.0), size.y * 0.78 / (font_size * 0.72))
