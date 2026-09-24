extends Node3D
var stage: Node3D
var palette: Dictionary = {}
func _ready() -> void:
	stage = self
	_build()

func _mat(color: String, metal := false) -> StandardMaterial3D:
	if not palette.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = 0.68 if metal else 0.93
		material.metallic = 0.45 if metal else 0.0
		palette[color] = material
	return palette[color]

func _point(p: Vector2, height: float) -> Vector3:
	return Vector3((p.x - 100) * 0.05, height, (p.y - 17) * 0.05)

func _mesh(mesh: Mesh, p: Vector2, height: float, color: String, metal := false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _mat(color, metal)
	instance.position = _point(p, height)
	stage.add_child(instance)
	return instance

func _box(rect: Rect2, height: float, elevation: float, color: String, metal := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(rect.size.x * 0.05, height, rect.size.y * 0.05)
	return _mesh(mesh, rect.get_center(), elevation + height * 0.5, color, metal)

func _pipe(a: Vector2, b: Vector2, height: float, radius: float, color: String) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b) * 0.05
	mesh.radial_segments = 12
	var instance := _mesh(mesh, (a + b) * 0.5, height, color, true)
	instance.quaternion = Quaternion(Vector3.UP, Vector3(b.x - a.x, 0, b.y - a.y).normalized())

func _build() -> void:
	_box(Rect2(-130, -118, 460, 270), 0.20, -0.28, "#252f30")
	var rng := RandomNumberGenerator.new()
	rng.seed = 708
	for y in range(-98, 132, 16):
		for x in range(-110, 312, 22):
			if x + 21 > 108 and x < 170: continue
			var tones := ["#566159", "#60665a", "#515d59", "#626958"]
			_box(Rect2(x, y, 21, 15), 0.09, -0.09, tones[rng.randi_range(0, 3)])
	# Recessed water and masonry sides; dry stone overhangs the channel.
	_box(Rect2(112, -100, 54, 234), 0.03, -0.20, "#123a3c", true)
	for x in [105, 166]: _box(Rect2(x, -100, 7, 234), 0.15, -0.04, "#747d68")
	# Two courses on the back wall; lower front/side caps preserve visibility.
	for y in [-118, 134]:
		var courses := 2 if y < 0 else 1
		for course in courses:
			for x in range(-130, 330, 23):
				_box(Rect2(x, y, 22, 18), 0.32, course * 0.33, "#626b59" if course == 0 else "#717663")
	for x in [-130, 312]:
		for y in range(-100, 133, 18): _box(Rect2(x, y, 18, 17), 0.34, 0, "#656e5e")
	for x in range(103, 175, 4): _box(Rect2(x, -23, 1.4, 46), 0.07, 0.02, "#5d6c68", true)
	for y in [-23, 21]: _box(Rect2(101, y, 76, 2), 0.10, 0.02, "#a3a087", true)
	_pipe(Vector2(-96, -80), Vector2(292, -80), 0.42, 0.17, "#61746b")
	_pipe(Vector2(290, -80), Vector2(290, -13), 0.42, 0.12, "#61746b")
	for x in [-83, 34, 203, 276]:
		_pipe(Vector2(x - 2, -80), Vector2(x + 2, -80), 0.42, 0.22, "#929783")
		_box(Rect2(x - 1, -98, 2, 19), 0.07, 0.2, "#353f3f", true)
	var valve := TorusMesh.new()
	valve.inner_radius = 0.29
	valve.outer_radius = 0.35
	valve.rings = 24
	valve.ring_segments = 8
	_mesh(valve, Vector2(44, -80), 0.80, "#a15c35", true)
	_pipe(Vector2(37, -80), Vector2(51, -80), 0.80, 0.03, "#b78052")
	_pipe(Vector2(44, -87), Vector2(44, -73), 0.80, 0.03, "#b78052")
	# Small ladder rather than the previous oversized circular landing graphic.
	_box(Rect2(-13, -36, 26, 39), 0.03, 0, "#182728")
	for x in [-6, 6]:
		var rail := CylinderMesh.new()
		rail.top_radius = 0.045
		rail.bottom_radius = 0.045
		rail.height = 2.0
		rail.radial_segments = 10
		_mesh(rail, Vector2(x, -5), 1.0, "#b0a276", true)
	for rung in range(7): _pipe(Vector2(-6, -5), Vector2(6, -5), 0.17 + rung * 0.29, 0.032, "#c6b37f")
	# Raised cabinet with door seams, vents, handle and an exposed cable run.
	_box(Rect2(-98, 38, 29, 28), 0.65, 0, "#455e55", true)
	_box(Rect2(-96, 39, 25, 23), 0.025, 0.65, "#748473", true)
	for y in range(43, 54, 3): _box(Rect2(-92, y, 17, 0.7), 0.004, 0.678, "#293c38")
	_box(Rect2(-75, 55, 1, 4), 0.03, 0.68, "#c2af6e", true)
	_pipe(Vector2(-84, -95), Vector2(-84, 37), 0.04, 0.026, "#222e2d")
	# Shelves with upright legs and individually modelled cans.
	for x in [213, 281]: _box(Rect2(x, -56, 2, 30), 0.7, 0, "#43554e", true)
	_box(Rect2(212, -56, 72, 29), 0.055, 0.32, "#706750")
	_box(Rect2(212, -56, 72, 29), 0.055, 0.75, "#857b5e")
	for x in [222, 239, 257, 274]:
		var can := CylinderMesh.new()
		can.top_radius = 0.10
		can.bottom_radius = 0.10
		can.height = 0.27
		can.radial_segments = 12
		_mesh(can, Vector2(x, -40), 0.93, "#788970", true)
	for p in [Vector2(222, 112), Vector2(260, 116)]:
		_box(Rect2(p - Vector2(12, 9), Vector2(24, 18)), 0.37, 0, "#756347")
		for x in [-10, 9]: _box(Rect2(p + Vector2(x, -9), Vector2(2, 18)), 0.035, 0.37, "#b19461")
		var cross := _box(Rect2(p - Vector2(10, 1), Vector2(20, 2)), 0.03, 0.37, "#a58a5e")
		cross.rotation.y = -0.5
	for p in [Vector2(77, 102), Vector2(291, 112)]:
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.22
		barrel.bottom_radius = 0.22
		barrel.height = 0.64
		barrel.radial_segments = 16
		_mesh(barrel, p, 0.32, "#4b655f", true)
		for height in [0.12, 0.52]:
			var band := TorusMesh.new()
			band.inner_radius = 0.215
			band.outer_radius = 0.24
			band.rings = 16
			band.ring_segments = 6
			_mesh(band, p, height, "#8a9788", true)
	# Only two local lights, rendered once with the architecture.
	# Damp mineral patches and debris break up the clean stone without labels.
	for i in range(28):
		var p := Vector2(rng.randf_range(-103, 300), -90 if i % 2 == 0 else 121)
		if p.x > 103 and p.x < 178: continue
		var patch := CylinderMesh.new()
		patch.top_radius = rng.randf_range(0.08, 0.24)
		patch.bottom_radius = patch.top_radius
		patch.height = 0.003
		patch.radial_segments = 9
		var stain := _mesh(patch, p, 0.006, "#3d4e3f")
		stain.scale.z = 0.35
	for p in [Vector2(-65, 85), Vector2(52, 104), Vector2(281, 19)]:
		var puddle := CylinderMesh.new()
		puddle.top_radius = 0.42
		puddle.bottom_radius = 0.42
		puddle.height = 0.004
		puddle.radial_segments = 16
		var wet := _mesh(puddle, p, 0.006, "#3e615b", true)
		wet.scale.z = 0.4
		wet.rotation.y = rng.randf_range(-1, 1)
	for p in [Vector2(-104, 106), Vector2(194, -87), Vector2(296, 82)]:
		for i in range(3):
			var debris := _box(Rect2(p + Vector2(i * 3, i % 2 * 3), Vector2(4, 2)), 0.055, 0, "#746b50")
			debris.rotation.y = i * 0.7
	for i in range(4):
		var coil := TorusMesh.new()
		coil.inner_radius = 0.13 + i * 0.042
		coil.outer_radius = coil.inner_radius + 0.027
		coil.rings = 24
		coil.ring_segments = 6
		_mesh(coil, Vector2(34, 91), 0.035, "#344e39")
	_pipe(Vector2(21, 74), Vector2(28, 77), 0.045, 0.023, "#9ba389")
	for p in [Vector2(-43, 117), Vector2(288, -5)]:
		_box(Rect2(p, Vector2(16, 8)), 0.02, 0.01, "#1e3231")
		for x in range(2, 15, 3): _box(Rect2(p + Vector2(x, 0), Vector2(1, 8)), 0.025, 0.02, "#60746a", true)
	for p in [Vector2(-51, -99), Vector2(224, -99)]:
		_box(Rect2(p - Vector2(4, 2), Vector2(8, 4)), 0.08, 0.77, "#c9aa66", true)
		var lamp := OmniLight3D.new()
		lamp.position = _point(p + Vector2(0, 12), 1.0)
		lamp.light_color = Color("#ffbd66")
		lamp.light_energy = 2.1
		lamp.omni_range = 4.8
		lamp.shadow_enabled = false
		stage.add_child(lamp)
	# Água corrente, gotas, luz com mau contato, ratos e o esconderijo da V1.
	add_child(preload("res://world/places/SewerAtmosphere3D.gd").new())
