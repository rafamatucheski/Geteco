extends Node3D
## Static, batched bridge. Progression and animated workers belong to the owner.
const Layout := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const Ground := preload("res://world/editing/WorldGroundFactory.gd")
const THICKNESS := 0.75
var completed := false
var _built := false
var _common: Node3D
var _works: Node3D
var _finished: Node3D
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _surfaces: Dictionary = {}
var _faces := PackedVector3Array()
var _body: StaticBody3D
var _part_root: Node3D

func build(initial_completed: bool = false) -> Node3D:
	if _built:
		set_completed(initial_completed)
		return self
	name = "NorthGatewayScenery"
	_common = _new_part("PermanentBridge")
	_build_decks(false)
	_build_supports()
	_flush_part()
	_finished = _new_part("CompletedSpan")
	_build_decks(true)
	_flush_part()
	_works = _new_part("ConstructionSite")
	_build_works()
	_flush_part()
	_built = true
	set_completed(initial_completed)
	return self

func set_completed(value: bool) -> void:
	completed = value
	if not _built: return
	# Build both immutable states once. A save restore can safely select either.
	_set_enabled(_finished, value)
	_set_enabled(_works, not value)

func _set_enabled(root: Node3D, enabled: bool) -> void:
	root.visible = enabled
	for body in root.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 1 if enabled else 0
	root.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED

func _new_part(part_name: String) -> Node3D:
	var result := Node3D.new()
	result.name = part_name
	add_child(result)
	_part_root = result
	_batches = {}
	_surfaces = {}
	_faces = PackedVector3Array()
	_body = StaticBody3D.new()
	_body.name = part_name + "Solid"
	_body.collision_layer = 1
	_body.collision_mask = 0
	result.add_child(_body)
	return result

func _build_decks(gap_only: bool) -> void:
	var points := Layout.centerline()
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		if Layout.in_gap((a + b) * 0.5) != gap_only: continue
		var sa := _side(points, i)
		var sb := _side(points, i + 1)
		var wa := Layout.deck_half_width(a)
		var wb := Layout.deck_half_width(b)
		var ra := _road_half_width(a)
		var rb := _road_half_width(b)
		var al := a + sa * wa
		var ar := a - sa * wa
		var bl := b + sb * wb
		var br := b - sb * wb
		var normal := sa.cross(b - a).normalized()
		if normal.y < 0.0: normal = -normal
		_quad("asphalt", a + sa * ra, a - sa * ra, b - sb * rb, b + sb * rb, normal, true)
		_quad("concrete", al, a + sa * ra, b + sb * rb, bl, normal, true)
		_quad("concrete", a - sa * ra, ar, br, b - sb * rb, normal, true)
		var down := Vector3.DOWN * THICKNESS
		_quad("concrete", al, bl, bl + down, al + down, sa, true)
		_quad("concrete", br, ar, ar + down, br + down, -sa, true)
		_quad("concrete", ar + down, al + down, bl + down, br + down, Vector3.DOWN, true)
		if i == 0 or is_equal_approx(a.z, Layout.GAP_NORTH):
			_quad("concrete", ar, al, al + down, ar + down, (a - b).normalized(), true)
		if i == points.size() - 2 or is_equal_approx(b.z, Layout.GAP_SOUTH):
			_quad("concrete", bl, br, br + down, bl + down, (b - a).normalized(), true)
		# Entry rails start behind the sidewalk junction, not inside the highway.
		if i >= 2:
			_guard(al - sa * 0.22, bl - sb * 0.22)
			_guard(ar + sa * 0.22, br + sb * 0.22)
		_paint(a, b, sa, sb, ra, rb, i)
	if not gap_only:
		# Future region is not built. The finished bridge has a permanent guarded
		# turnaround instead of a fall or an invented transition to an empty map.
		var last := points[-1]
		# The connected desert owns the northern shore. Keep the road opening clear.
		_guard(last + Vector3.LEFT * 12.78, last + Vector3.LEFT * 5.4)
		_guard(last + Vector3.RIGHT * 5.4, last + Vector3.RIGHT * 12.78)

func _side(points: PackedVector3Array, index: int) -> Vector3:
	var direction := points[mini(index + 1, points.size() - 1)] - points[maxi(0, index - 1)]
	return Vector3(-direction.z, 0.0, direction.x).normalized()

func _road_half_width(point: Vector3) -> float:
	if point.z > -343.0: return Layout.ROAD_HALF_WIDTH
	return lerpf(Layout.ROAD_HALF_WIDTH, 11.8, clampf((-343.0 - point.z) / 9.0, 0.0, 1.0))

func _guard(a: Vector3, b: Vector3) -> void:
	_beam("concrete", a + Vector3.UP * 0.30, b + Vector3.UP * 0.30, 0.34, 0.60, true)
	_beam("steel", a + Vector3.UP * 1.03, b + Vector3.UP * 1.03, 0.13, 0.18)
	_beam("steel", a + Vector3.UP * 0.74, b + Vector3.UP * 0.74, 0.08, 0.10)
	# A continuous solid envelope matches the closely spaced safety rail.
	_beam("", a + Vector3.UP * 0.87, b + Vector3.UP * 0.87, 0.22, 0.54, true)
	_box("steel", a + Vector3.UP * 0.83, Vector3(0.12, 0.59, 0.12))

func _paint(a: Vector3, b: Vector3, sa: Vector3, sb: Vector3, ra: float, rb: float, index: int) -> void:
	var lift := Vector3.UP * 0.018
	for sign_value in [-1.0, 1.0]:
		var pa: Vector3 = a + sa * (ra - 0.14) * sign_value + lift
		var pb: Vector3 = b + sb * (rb - 0.14) * sign_value + lift
		_beam("white", pa, pb, 0.10, 0.006)
	if a.z < -343.0 or index % 3 == 0: return
	for offset in [-0.12, 0.12]:
		_beam("yellow", a + sa * offset + lift, b + sb * offset + lift, 0.09, 0.006)

func _build_supports() -> void:
	# Real abutment and piled bents meet the underside; no floating thin plane.
	_box("concrete", Vector3(356.0, -0.40, -255.7), Vector3(2.0, 0.8, 9.5), Basis(Vector3.UP, -0.30), true)
	var points := Layout.centerline()
	for i in [12, 18, 24]:
		var p := points[i]
		_pier(p, _side(points, i), Layout.deck_half_width(p))
	for z in [-292.0, -307.0, -325.0, -343.0, -360.0, -370.5]:
		var p := Vector3(Layout.TERMINAL.x, Layout.DECK_HEIGHT, z)
		_pier(p, Vector3.RIGHT, Layout.deck_half_width(p))
	# Longitudinal girders continue through the unfinished opening below road
	# level. They are visual construction steel, not a traversable road surface.
	for x in [-3.8, 3.8]:
		_box("dark_steel", Vector3(342.5 + x, 1.02, -323.0), Vector3(0.32, 1.05, 100.8))

func _pier(p: Vector3, side: Vector3, half_width: float) -> void:
	var top := p.y - THICKNESS
	for offset in [-minf(half_width - 1.1, 5.0), minf(half_width - 1.1, 5.0)]:
		var center: Vector3 = p + side * offset
		center.y = (top - 4.0) * 0.5
		_box("concrete", center, Vector3(1.15, top + 4.0, 1.45), Basis.IDENTITY, true)
	_beam("concrete", p - side * (half_width - 0.5) + Vector3.DOWN * 1.0,
		p + side * (half_width - 0.5) + Vector3.DOWN * 1.0, 1.25, 0.5, true)

func _build_works() -> void:
	var gate := Layout.WORK_POSITION
	# A wide, visibly solid barrier spans road AND shoulders. Workers remain
	# visible through a closely barred upper fence, with no walking bypass.
	_box("concrete", gate + Vector3.UP * 0.34, Vector3(Layout.GATE_WIDTH, 0.68, 0.65), Basis.IDENTITY, true)
	_box("", gate + Vector3.UP * Layout.GATE_HEIGHT * 0.5,
		Vector3(Layout.GATE_WIDTH, Layout.GATE_HEIGHT, 0.32), Basis.IDENTITY, true)
	for x in range(43):
		_box("steel", gate + Vector3(-8.4 + float(x) * 0.4, 1.46, 0), Vector3(0.045, 1.57, 0.045))
	for y in [0.85, 1.75, 2.22]:
		_box("steel", gate + Vector3.UP * y, Vector3(17.0, 0.065, 0.07))
	for x in range(17):
		_box("orange" if x % 2 == 0 else "white", gate + Vector3(-8.0 + x, 0.46, 0.347), Vector3(0.97, 0.27, 0.022))
	# Separate caps protect the unfinished gap even if a player reaches it from
	# an unusual direction; completion removes all these work barriers together.
	for z in [Layout.GAP_SOUTH + 0.45, Layout.GAP_NORTH - 0.45]:
		var center := Vector3(342.5, Layout.DECK_HEIGHT, z)
		_box("orange", center + Vector3.UP * 0.55, Vector3(9.8, 1.1, 0.55), Basis.IDENTITY, true)
		for x in range(10):
			_box("white", center + Vector3(-4.5 + x, 0.57, 0.288), Vector3(0.38, 0.58, 0.024))
	# Exposed deck bars, anchored at the actual two unfinished faces.
	for z in [Layout.GAP_SOUTH - 0.45, Layout.GAP_NORTH + 0.45]:
		for x in range(13):
			_box("rust", Vector3(338.9 + x * 0.6, 2.16, z), Vector3(0.028, 0.028, 1.35))
	# Compact fixed crane and material stack on the workshop shoulders. No
	# physics simulation, lights, particles, or per-frame construction scripts.
	_box("orange", Vector3(336.3, 2.85, -295.1), Vector3(1.9, 0.9, 2.0), Basis.IDENTITY, true)
	_box("yellow", Vector3(336.3, 6.35, -295.1), Vector3(0.42, 6.5, 0.42), Basis.IDENTITY, true)
	_box("yellow", Vector3(336.3, 9.4, -297.8), Vector3(0.40, 0.44, 9.1))
	_beam("dark_steel", Vector3(336.3, 9.3, -302.1), Vector3(336.3, 4.9, -302.1), 0.035, 0.035)
	_box("dark_steel", Vector3(336.3, 4.85, -302.1), Vector3(0.24, 0.30, 0.08))
	for row in range(3):
		_box("concrete", Vector3(349.0, 2.57 + row * 0.28, -295.0), Vector3(1.6, 0.24, 2.2), Basis.IDENTITY, true)

func _beam(id: String, a: Vector3, b: Vector3, width: float, height: float, solid: bool = false) -> void:
	var direction := b - a
	if direction.length_squared() < 0.000001: return
	var planar := Vector2(direction.x, direction.z).length()
	var orientation := Basis(Vector3.UP, atan2(direction.x, direction.z)) * Basis(Vector3.RIGHT, -atan2(direction.y, planar))
	_box(id, (a + b) * 0.5, Vector3(width, height, direction.length() + 0.018), orientation, solid)

func _box(id: String, center: Vector3, size: Vector3, orientation: Basis = Basis.IDENTITY, solid: bool = false) -> void:
	if not id.is_empty():
		if not _batches.has(id): _batches[id] = []
		_batches[id].append(Transform3D(orientation.scaled_local(size), center))
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = Transform3D(orientation, center)
		_body.add_child(collider)

func _quad(id: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, solid: bool) -> void:
	if not _surfaces.has(id):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[id] = surface
	_triangle(_surfaces[id], a, b, c, normal, solid)
	_triangle(_surfaces[id], a, c, d, normal, solid)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, solid: bool) -> void:
	var vertices := [a, c, b] if (b - a).cross(c - a).dot(normal) > 0.0 else [a, b, c]
	for vertex: Vector3 in vertices:
		surface.set_normal(normal)
		surface.set_uv(Vector2(vertex.x, vertex.z) * 0.35)
		surface.add_vertex(vertex)
		if solid: _faces.append(vertex)

func _flush_part() -> void:
	for id in _surfaces:
		var mesh := MeshInstance3D.new()
		mesh.name = id + "Deck"
		mesh.mesh = _surfaces[id].commit()
		mesh.material_override = _material(id)
		_part_root.add_child(mesh)
	if not _faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_faces)
		var collider := CollisionShape3D.new()
		collider.name = "DeckFaces"
		collider.shape = shape
		_body.add_child(collider)
	var box := BoxMesh.new()
	for id in _batches:
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.mesh = box
		mesh.instance_count = _batches[id].size()
		for i in mesh.instance_count: mesh.set_instance_transform(i, _batches[id][i])
		var instance := MultiMeshInstance3D.new()
		instance.name = id + "Parts"
		instance.multimesh = mesh
		if Engine.get_meta("geteco_live_preview_build",false): instance.set_meta("preview_instance_transforms",_batches[id])
		instance.material_override = _material(id)
		_part_root.add_child(instance)
	_surfaces.clear()
	_batches.clear()
	_faces.clear()

func _material(id: String) -> StandardMaterial3D:
	if _materials.has(id): return _materials[id]
	var result: StandardMaterial3D
	if id in ["asphalt", "concrete"]:
		result = Ground.material(id).duplicate() as StandardMaterial3D
		result.uv1_triplanar = true
		result.uv1_world_triplanar = true
		result.uv1_scale = Vector3.ONE * 0.35
	else:
		result = StandardMaterial3D.new()
		var colors := {"steel": "879094", "dark_steel": "344047", "white": "e2dfcf",
			"yellow": "d5a63e", "orange": "df7633", "rust": "785b49"}
		result.albedo_color = Color(colors.get(id, "848b8c"))
		result.roughness = 0.88
		if id in ["steel", "dark_steel", "rust"]: result.metallic = 0.35
	_materials[id] = result
	return result
