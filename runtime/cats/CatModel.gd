extends Node3D
## Gato 3D nativo pequeno. O ator dono controla distância, tempo de vida e animação.
## A frente é -Z; os pés ficam em y=0. Sem física, timers, luzes nem viewport por gato.

const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const COATS := [
	[Color("d98138"), Color("814524"), Color("f0d3a4"), Color("b7d076")], # Ginger tabby.
	[Color("232630"), Color("15191e"), Color("232630"), Color("d6b85b")], # Black.
	[Color("e7e5df"), Color("c8c9c7"), Color("f3eee7"), Color("84bad3")], # White.
	[Color("899294"), Color("464f55"), Color("d4d7d1"), Color("a4c783")], # Grey tabby.
	[Color("eee3cf"), Color("25272a"), Color("bd6734"), Color("b4bb67")], # Calico.
	[Color("272c35"), Color("e5e4dc"), Color("f2ede0"), Color("87be89")], # Tuxedo.
	[Color("d6c29f"), Color("51453f"), Color("a49680"), Color("79bce0")], # Siamese.
	[Color("e5c78f"), Color("b1976f"), Color("f1dfbc"), Color("bb995b")], # Cream.
	[Color("765144"), Color("4d362e"), Color("ac8770"), Color("c7ac68")], # Chocolate.
	[Color("bec6c8"), Color("777f88"), Color("e4e9e6"), Color("70bba5")], # Silver.
]

static var _cache: Dictionary = {}
static var _material: StandardMaterial3D
static var _sphere: SphereMesh
static var _whisker: CylinderMesh

var coat_index := 0
var activity := "sit"
var _clock := 0.0
var _gait := 0.0
var _body: MeshInstance3D
var _head: MeshInstance3D
var _eyes: MeshInstance3D
var _legs: Array[MeshInstance3D] = []
var _tail: Array[MeshInstance3D] = []


func configure(index: int) -> void:
	coat_index = posmod(index, COATS.size())
	_clock = float(coat_index) * 1.73
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_legs.clear()
	_tail.clear()
	if not _cache.has(coat_index):
		_cache[coat_index] = _make_coat(coat_index)
	var meshes: Dictionary = _cache[coat_index]
	_body = _node("Body", meshes.body, self)
	_head = _node("Head", meshes.head, self)
	_eyes = _node("Eyes", meshes.eyes, _head)
	for n in range(4):
		_legs.append(_node("Paw%d" % n, meshes.front_leg if n < 2 else meshes.back_leg, self))
	var tail_parent: Node3D = self
	for n in range(3):
		var section := _node("Tail%d" % n, meshes["tail%d" % n], tail_parent)
		_tail.append(section)
		tail_parent = section
	set_meta("cat_coat", coat_index)
	set_meta("native_cat_model", true)
	_pose(1.0, 0.0)


func set_activity(value: String) -> void:
	activity = value if value in ["sit", "walk", "play", "sleep", "scratch"] else "sit"


func animate(delta: float, speed: float = 0.0) -> void:
	if not is_instance_valid(_body):
		return
	_clock += maxf(delta, 0.0)
	_gait += maxf(speed, 0.0) * delta * 12.0
	_pose(1.0 - exp(-maxf(delta, 0.0) * 11.0), speed)


func _pose(blend: float, speed: float) -> void:
	var walk := activity == "walk" and speed > 0.02
	var sleep := activity == "sleep"
	var play := activity == "play"
	var scratch := activity == "scratch"
	var sit := not walk and not sleep and not play and not scratch
	var breath := sin(_clock * 2.2) * 0.003
	var torso := Vector3(0.0, 0.245 + breath, 0.035)
	var torso_pitch := 0.0
	var head := Vector3(0.0, 0.355 + breath, -0.205)
	var head_pitch := 0.0
	if sit:
		torso = Vector3(0.0, 0.232 + breath, 0.10)
		torso_pitch = 0.62
		head = Vector3(0.0, 0.398 + breath, -0.116)
	elif sleep:
		torso = Vector3(0.0, 0.154 + breath, 0.015)
		head = Vector3(0.03, 0.158 + breath, -0.173)
		head_pitch = 0.37
	elif play:
		torso = Vector3(0.0, 0.218 + breath, 0.03)
		torso_pitch = -0.19
		head = Vector3(0.0, 0.28 + breath, -0.22)
		head_pitch = 0.22
	elif scratch:
		torso = Vector3(0.0, 0.285 + breath, 0.04)
		torso_pitch = 0.9
		head = Vector3(0.0, 0.49 + breath, -0.1)
	if walk:
		torso.y += absf(sin(_gait)) * 0.008
	_body.position = _body.position.lerp(torso, blend)
	_body.rotation.x = lerp_angle(_body.rotation.x, torso_pitch, blend)
	_head.position = _head.position.lerp(head, blend)
	_head.rotation.x = lerp_angle(_head.rotation.x, head_pitch, blend)
	_head.rotation.y = lerp_angle(_head.rotation.y, 0.42 if sleep else sin(_clock * 0.64) * 0.16, blend)
	# Olhos fechados para cochilos e uma piscada natural de vez em quando; a geometria dos olhos divide a cabeça.
	var blinking := fmod(_clock, 4.7) > 4.55
	_eyes.scale.y = lerpf(_eyes.scale.y, 0.07 if sleep or blinking else 1.0, blend)
	for n in range(4):
		var front := n < 2
		var side := -1.0 if n % 2 == 0 else 1.0
		var target := Vector3(side * 0.078, 0.223, -0.139 if front else 0.188)
		var pitch := 0.0
		var height := 1.0
		if walk:
			var phase := _gait + (PI if n == 0 or n == 3 else 0.0)
			pitch = sin(phase) * minf(speed * 0.58, 0.62)
			target.y += maxf(sin(phase), 0.0) * 0.016
		elif sit:
			target = Vector3(side * 0.068, 0.248 if front else 0.117, -0.108 if front else 0.23)
			height = 1.12 if front else 0.49
		elif sleep:
			target = Vector3(side * 0.07, 0.07, -0.10 if front else 0.13)
			height = 0.3
		elif play and front:
			target.y = 0.223
			if n == 0:
				pitch = 0.30 + maxf(0.0, sin(_clock * 5.2)) * 0.9
				target.y += maxf(0.0, sin(_clock * 5.2)) * 0.055
		elif scratch and front:
			target = Vector3(side * 0.071, 0.41, -0.125)
			pitch = 1.35 + sin(_clock * 8.0 + float(n) * PI) * 0.3
		_legs[n].position = _legs[n].position.lerp(target, blend)
		_legs[n].rotation.x = lerp_angle(_legs[n].rotation.x, pitch, blend)
		_legs[n].scale.y = lerpf(_legs[n].scale.y, height, blend)
	_tail[0].position = _tail[0].position.lerp(Vector3(0.0, 0.11 if sleep else 0.255, 0.246), blend)
	var tail_pitch := 0.9 if sit else (0.0 if sleep else -0.65)
	_tail[0].rotation = _tail[0].rotation.lerp(Vector3(tail_pitch, 1.13 if sleep else sin(_clock * 1.1) * 0.24, 0.0), blend)
	for n in range(1, 3):
		_tail[n].position = Vector3(0.0, 0.0, 0.123)
		_tail[n].rotation.x = lerp_angle(_tail[n].rotation.x, -0.42 if sit else (0.0 if sleep else 0.45), blend)
		_tail[n].rotation.y = lerp_angle(_tail[n].rotation.y, (0.75 if sleep else 0.28) + sin(_clock * 1.5 + n) * 0.16, blend)


static func _node(label: String, mesh: Mesh, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = _shared_material()
	parent.add_child(instance)
	return instance


static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.94
	return _material


static func _make_coat(index: int) -> Dictionary:
	var palette: Array = COATS[index]
	var fur: Color = palette[0]
	var marking: Color = palette[1]
	var cream: Color = palette[2]
	var body: Array = []
	_oval(body, Vector3.ZERO, Vector3(0.119, 0.13, 0.241), fur)
	_oval(body, Vector3(0.0, -0.01, 0.14), Vector3(0.126, 0.137, 0.115), fur)
	_oval(body, Vector3(0.0, 0.005, -0.137), Vector3(0.098, 0.12, 0.102), fur)
	if index in [0, 3, 9]:
		for n in range(4):
			var z := -0.12 + float(n) * 0.078
			_oval(body, Vector3(0.0, 0.122, z), Vector3(0.073, 0.014, 0.013), marking)
			for side in [-1.0, 1.0]:
				_oval(body, Vector3(side * 0.108, 0.028, z), Vector3(0.015, 0.075, 0.019), marking)
	if index == 4:
		_oval(body, Vector3(-0.054, 0.096, 0.10), Vector3(0.076, 0.059, 0.12), marking)
		_oval(body, Vector3(0.097, 0.019, -0.044), Vector3(0.032, 0.094, 0.114), cream)
	if index in [0, 2, 3, 5, 7, 9]:
		_oval(body, Vector3(0.0, -0.01, -0.206), Vector3(0.073, 0.079, 0.045), cream)
	var head: Array = []
	var face: Color = marking if index == 6 else fur
	_oval(head, Vector3.ZERO, Vector3(0.106, 0.093, 0.092), fur)
	_oval(head, Vector3(0.0, -0.014, -0.055), Vector3(0.09, 0.071, 0.067), face)
	for side in [-1.0, 1.0]:
		_ear(head, Vector3(side * 0.068, 0.053, 0.002), side, face)
		_oval(head, Vector3(side * 0.031, -0.027, -0.107), Vector3(0.04, 0.029, 0.03), cream if index != 6 else marking.lightened(0.10))
		for n in range(2):
			var start := Vector3(side * 0.052, -0.026 - float(n) * 0.013, -0.122)
			var end := Vector3(side * 0.151, -0.011 - float(n) * 0.027, -0.119)
			_line(head, start, end, 0.0014, Color("d5cec3"))
	if index == 4:
		_oval(head, Vector3(-0.051, 0.038, -0.051), Vector3(0.052, 0.057, 0.055), marking)
		_oval(head, Vector3(0.058, 0.052, -0.029), Vector3(0.045, 0.046, 0.059), cream)
	if index == 5:
		_oval(head, Vector3(0.0, -0.028, -0.097), Vector3(0.045, 0.034, 0.038), cream)
	if index in [0, 3, 9]:
		for side in [-1.0, 1.0]:
			_oval(head, Vector3(side * 0.038, 0.065, -0.046), Vector3(0.013, 0.034, 0.035), marking)
	_oval(head, Vector3(0.0, -0.021, -0.133), Vector3(0.015, 0.009, 0.009), Color("b9807f") if index != 6 else Color("332b2b"))
	_line(head, Vector3(0.0, -0.025, -0.132), Vector3(0.0, -0.045, -0.128), 0.0018, Color("483c3a"))
	var eyes: Array = []
	for side in [-1.0, 1.0]:
		_oval(eyes, Vector3(side * 0.052, 0.013, -0.096), Vector3(0.028, 0.017, 0.016), Color("292b29"))
		_oval(eyes, Vector3(side * 0.052, 0.014, -0.109), Vector3(0.022, 0.014, 0.006), palette[3])
		_oval(eyes, Vector3(side * 0.052, 0.014, -0.115), Vector3(0.005, 0.013, 0.003), Color("101516"))
		_oval(eyes, Vector3(side * 0.046, 0.02, -0.118), Vector3(0.004, 0.004, 0.002), Color("efeee8"))
	var legs: Array = []
	var paw_color: Color = cream if index in [0, 2, 3, 4, 5, 7, 9] else (marking if index == 6 else fur)
	_oval(legs, Vector3(0.0, -0.076, 0.0), Vector3(0.034, 0.109, 0.039), marking if index == 6 else fur)
	_oval(legs, Vector3(0.0, -0.19, -0.018), Vector3(0.041, 0.027, 0.059), paw_color)
	var result := {"body": _bake(body), "head": _bake(head), "eyes": _bake(eyes), "front_leg": _bake(legs), "back_leg": _bake(legs)}
	for n in range(3):
		var tail: Array = []
		var radius := 0.029 - float(n) * 0.005
		_oval(tail, Vector3(0.0, 0.0, 0.062), Vector3(radius, radius, 0.087), marking if index == 6 or (index == 4 and n > 0) else fur)
		if index in [0, 3, 9]:
			_oval(tail, Vector3(0.0, 0.0, 0.068), Vector3(radius + 0.001, radius + 0.001, 0.013), marking)
		result["tail%d" % n] = _bake(tail)
	return result


static func _oval(parts: Array, origin: Vector3, radii: Vector3, color: Color) -> void:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 12
		_sphere.rings = 6
	parts.append([_sphere, Transform3D(Basis.from_scale(radii), origin), color])


static func _line(parts: Array, start: Vector3, end: Vector3, radius: float, color: Color) -> void:
	if _whisker == null:
		_whisker = CylinderMesh.new()
		_whisker.top_radius = 1.0
		_whisker.bottom_radius = 1.0
		_whisker.height = 1.0
		_whisker.radial_segments = 4
	var direction := end - start
	var y := direction.normalized()
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.1:
		x = y.cross(Vector3.UP).normalized()
	var whisker_basis := Basis(x * radius, y * direction.length(), x.cross(y) * radius)
	parts.append([_whisker, Transform3D(whisker_basis, (start + end) * 0.5), color])


static func _ear(parts: Array, origin: Vector3, side: float, color: Color) -> void:
	var points := [Vector3(-0.051, 0, -0.035), Vector3(0.051, 0, -0.035), Vector3(side * 0.016, 0.126, 0.0), Vector3(0, -0.011, 0.047)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[0, 2, 1], [0, 3, 2], [1, 2, 3], [0, 1, 3]]:
		for vertex in face:
			surface.add_vertex(points[vertex])
	surface.generate_normals()
	parts.append([surface.commit(), Transform3D(Basis.IDENTITY, origin), color])
	var inner := SurfaceTool.new()
	inner.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(-0.032, 0.014, -0.0355), Vector3(side * 0.012, 0.094, -0.0105), Vector3(0.032, 0.014, -0.0355)]:
		inner.add_vertex(point)
	inner.generate_normals()
	parts.append([inner.commit(), Transform3D(Basis.IDENTITY, origin), Color("b9807f")])


static func _bake(parts: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var mesh: Mesh = part[0]
		var part_transform: Transform3D = part[1]
		var color: Color = part[2]
		var normal_basis := part_transform.basis.inverse().transposed()
		for surface_index in range(mesh.get_surface_count()):
			var arrays := MESH_ARRAYS.arrays_of(mesh, surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for n in range(count):
				var v := indices[n] if not indices.is_empty() else n
				surface.set_color(color)
				surface.set_normal((normal_basis * normals[v]).normalized())
				surface.add_vertex(part_transform * vertices[v])
	surface.index()
	return surface.commit()
