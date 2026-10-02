extends RefCounted
## Lofted rescue/patrol airframe. Static pieces are batched by material; moving
## doors/rotors retain their own transforms. All cockpit glass is opaque.
const ART = preload("res://gameplay/police_response/air_k9/AirK9Models.gd")
const NAVY := Color("182c3c")
const WHITE := Color("cbd4cf")
const STEEL := Color("677579")
const BLACK := Color("161f25")
const GLASS := Color("294d60")
const SECTION := [
	Vector4(-3.1, -0.12, 0.07, 0.12), Vector4(-2.82, -0.03, 0.55, 0.62),
	Vector4(-2.2, 0.06, 1.02, 0.99), Vector4(-1.3, 0.0, 1.24, 1.13),
	Vector4(-0.95, -0.02, 1.26, 1.12), Vector4(1.4, -0.02, 1.18, 1.02),
	Vector4(2.15, 0.12, 0.73, 0.66), Vector4(2.8, 0.25, 0.32, 0.32),
]

## Matriz montada uma única vez. Gerar a fuselagem (SurfaceTool + _bake_static)
## custava ~95 ms no quadro de cada chegada de helicóptero (medido em
## tests/measure/measure_event_hitches.gd); duplicate() reaproveita malhas e materiais.
static var _template: Node3D

# Retencao global ate o root sair; worlds/transicoes conservam os templates.
static func _watch_template_shutdown() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.root.tree_exiting.is_connected(_release_template):
		tree.root.tree_exiting.connect(_release_template, CONNECT_ONE_SHOT)

static func _release_template() -> void:
	if is_instance_valid(_template) and _template.get_parent() == null: _template.free()
	_template = null

## Monta a matriz na carga do jogo, não no quadro da primeira chegada.
static func warm() -> void:
	if _template == null:
		_template = Node3D.new()
		_build_uncached(_template)
		_watch_template_shutdown()

static func build(parent: Node3D) -> Dictionary:
	warm()
	var copy := _template.duplicate() as Node3D
	for child in copy.get_children():
		child.reparent(parent, false)
	copy.free()
	var doors: Array[Node3D] = []
	for child in parent.get_children():
		if str(child.name).begins_with("SlidingCabinDoor"): doors.append(child)
	return {"rotor": parent.get_node("MainRotor"), "tail_rotor": parent.get_node("TailRotor"), "doors": doors}

static func _build_uncached(parent: Node3D) -> Dictionary:
	_loft_body(parent)
	# Faceted windscreen follows the actual nose cross sections; narrow metal
	# mullions separate pilot/copilot windows instead of a floating glass sphere.
	for side in [-1.0, 1.0]:
		_glass_band(parent, side, 1, 3, 0.10, 1.42)
		_glass_band(parent, side, 3, 4, 0.06, 0.95)
		_polyline(parent, "WindscreenFrame", [
			_ring(SECTION[1], 0.1, side, 0.025), _ring(SECTION[2], 0.1, side, 0.025), _ring(SECTION[3], 0.1, side, 0.025)], 0.035, WHITE)
		_polyline(parent, "WindscreenTop", [
			_ring(SECTION[1], 1.42, side, 0.028), _ring(SECTION[2], 1.42, side, 0.028), _ring(SECTION[3], 1.42, side, 0.028)], 0.025, WHITE)
		_tube(parent, "CockpitPillar", _ring(SECTION[3], 0.02, side, 0.025), _ring(SECTION[3], 1.47, side, 0.025), 0.043, WHITE)
		# A real opening, dark cabin floor, bench and rear bulkhead remain visible.
		var x: float = side * 1.27
		_polyline(parent, "DoorFrame", [Vector3(x, -0.71, -0.94), Vector3(x, 0.73, -0.94), Vector3(x, 0.73, 1.37), Vector3(x, -0.71, 1.37)], 0.055, WHITE)
		_tube(parent, "DoorRail", Vector3(x, 0.85, -0.95), Vector3(x, 0.84, 2.64), 0.03, STEEL)
		_tube(parent, "DoorStep", Vector3(side * 1.55, -0.92, -0.6), Vector3(side * 1.55, -0.92, 1.28), 0.065, BLACK)
		for z in [-0.8, 1.05]:
			_tube(parent, "RappelOutrigger", Vector3(side * 0.8, 0.68, z), Vector3(side * 1.7, 0.68, z), 0.067, STEEL)
			_tube(parent, "RappelBrace", Vector3(side * 1.18, 0.13, z), Vector3(side * 1.67, 0.65, z), 0.043, STEEL)
			_polyline(parent, "RopeAnchorEye", [Vector3(side * 1.7, 0.7, z - 0.06), Vector3(side * 1.7, 0.58, z - 0.06), Vector3(side * 1.7, 0.58, z + 0.06), Vector3(side * 1.7, 0.7, z + 0.06)], 0.024, Color("adb8b1"))
		# Tubular skids curve upwards at the front. Cross struts are swept tubes.
		_polyline(parent, "LandingSkid", [Vector3(side * 1.48, -1.28, -2.55), Vector3(side * 1.53, -1.57, -2.1), Vector3(side * 1.53, -1.6, 1.93), Vector3(side * 1.50, -1.5, 2.15)], 0.085, STEEL)
		for z in [-1.18, 1.2]:
			_polyline(parent, "LandingStrut", [Vector3(side * 0.72, -0.74, z), Vector3(side * 1.03, -1.15, z), Vector3(side * 1.53, -1.54, z)], 0.072, STEEL)
		# Swept engine pod and intake/exhaust are separate from the fuselage shell.
		ART.ellipsoid(parent, "TurbineFairing", Vector3(side * 0.46, 1.05, 0.83), Vector3(0.72, 0.78, 2.55), NAVY)
		ART.ellipsoid(parent, "EngineIntake", Vector3(side * 0.46, 1.09, -0.36), Vector3(0.49, 0.41, 0.15), BLACK)
		_tube(parent, "Exhaust", Vector3(side * 0.49, 1.08, 1.79), Vector3(side * 0.53, 1.11, 2.22), 0.16, STEEL)
		ART.ellipsoid(parent, "ExhaustMouth", Vector3(side * 0.53, 1.11, 2.225), Vector3(0.25, 0.25, 0.035), BLACK)
		# Small fixed navigation lenses, no extra light sources or transparency.
		ART.ellipsoid(parent, "NavigationLens", Vector3(side * 1.32, 0.32, 1.32), Vector3(0.12, 0.11, 0.15), Color("b83735") if side < 0 else Color("468368"))
	ART.box(parent, "CabinFloor", Vector3(0, -0.8, 0.18), Vector3(2.4, 0.10, 2.43), BLACK)
	ART.box(parent, "RearBulkhead", Vector3(0, 0.0, 1.48), Vector3(1.8, 1.65, 0.09), BLACK)
	ART.box(parent, "CabinBench", Vector3(0, -0.47, 0.7), Vector3(0.6, 0.16, 1.13), NAVY)
	for side in [-1.0, 1.0]:
		ART.ellipsoid(parent, "PilotSeat", Vector3(side * 0.47, -0.1, -1.32), Vector3(0.5, 0.91, 0.35), BLACK)
		ART.ellipsoid(parent, "PilotHelmet", Vector3(side * 0.45, 0.45, -1.65), Vector3(0.29, 0.3, 0.29), NAVY)
	_tail(parent)
	_tube(parent, "MainMast", Vector3(0, 1.0, 0.1), Vector3(0, 2.1, 0.1), 0.095, STEEL)
	_tube(parent, "Swashplate", Vector3(0, 1.64, 0.1), Vector3(0, 1.74, 0.1), 0.31, STEEL)
	for side in [-1.0, 1.0]:
		_tube(parent, "PitchLink", Vector3(side * 0.23, 1.7, 0.1), Vector3(side * 0.28, 2.0, 0.1), 0.025, BLACK)
	var rotor := Node3D.new()
	rotor.name = "MainRotor"
	rotor.position = Vector3(0, 2.12, 0.1)
	parent.add_child(rotor)
	_tube(rotor, "RotorHub", Vector3(0, -0.08, 0), Vector3(0, 0.12, 0), 0.24, STEEL)
	for index in 4:
		var blade := _blade(rotor, 5.15, 0.29, 0.07)
		blade.rotation.y = index * PI * 0.5
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var grip := _tube(rotor, "BladeGrip", Vector3(0.12, 0, 0), Vector3(0.75, 0, 0), 0.08, STEEL)
		grip.rotation.y = index * PI * 0.5
	var tail_rotor := Node3D.new()
	tail_rotor.name = "TailRotor"
	tail_rotor.position = Vector3(-0.29, 1.58, 7.05)
	parent.add_child(tail_rotor)
	_tube(tail_rotor, "TailHub", Vector3(-0.12, 0, 0), Vector3(0.12, 0, 0), 0.12, STEEL)
	for index in 4:
		var blade := _blade(tail_rotor, 0.98, 0.13, 0.025)
		blade.rotation = Vector3(index * PI * 0.5, 0, PI * 0.5)
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var doors: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var door := Node3D.new()
		door.name = "SlidingCabinDoor"
		door.position = Vector3(side * 1.32, 0, 0.23)
		parent.add_child(door)
		var shell := _prism(door, "DoorSkin", [Vector3(0, -0.73, -1.16), Vector3(0, 0.58, -1.16), Vector3(0, 0.73, -1.0), Vector3(0, 0.73, 1.0), Vector3(0, 0.56, 1.15), Vector3(0, -0.73, 1.15)], Vector3(side * 0.065, 0, 0), NAVY)
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		ART.box(door, "DoorWindow", Vector3(side * 0.07, 0.32, -0.2), Vector3(0.025, 0.52, 1.6), GLASS)
		ART.box(door, "IdentificationStripe", Vector3(side * 0.08, -0.28, 0), Vector3(0.018, 0.18, 2.15), WHITE)
		_tube(door, "DoorHandle", Vector3(side * 0.14, -0.03, -0.67), Vector3(side * 0.14, -0.03, -0.35), 0.032, STEEL)
		_bake_static(door)
		doors.append(door)
	_bake_static(parent)
	return {"rotor": rotor, "tail_rotor": tail_rotor, "doors": doors}

static func _ring(section: Vector4, angle: float, side: float = 1.0, inflate: float = 0.0) -> Vector3:
	return Vector3(cos(angle) * (section.z + inflate) * side, section.y + sin(angle) * (section.w + inflate), section.x)

static func _loft_body(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section in SECTION.size() - 1:
		for ring in 20:
			var a := float(ring) * TAU / 20.0
			var b := float(ring + 1) * TAU / 20.0
			var mid := (a + b) * 0.5
			if section == 4 and absf(cos(mid)) > 0.69: continue
			var color := WHITE if sin(mid) > 0.04 else NAVY
			if sin(mid) > -0.12 and sin(mid) < 0.06: color = Color("79979a")
			# Outside faces must wind clockwise for Godot. Advance along the
			# fuselage before advancing around its section, not the reverse.
			_quad(st, _ring(SECTION[section], a), _ring(SECTION[section + 1], a), _ring(SECTION[section + 1], b), _ring(SECTION[section], b), color)
	st.generate_normals()
	var mat := ART.material(WHITE).duplicate() as StandardMaterial3D
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	var body := ART.part(parent, "SculptedFuselage", st.commit(), Vector3.ZERO, WHITE)
	body.material_override = mat

static func _glass_band(parent: Node3D, side: float, start: int, finish: int, low: float, high: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(start, finish):
		for patch in 4:
			var a := lerpf(low, high, float(patch) / 4.0)
			var b := lerpf(low, high, float(patch + 1) / 4.0)
			_quad(st, _ring(SECTION[index], a, side, 0.018), _ring(SECTION[index], b, side, 0.018), _ring(SECTION[index + 1], b, side, 0.018), _ring(SECTION[index + 1], a, side, 0.018), Color.WHITE)
	st.generate_normals()
	var part := ART.part(parent, "FacetedCockpitGlazing", st.commit(), Vector3.ZERO, GLASS)
	var mat := ART.material(GLASS).duplicate() as StandardMaterial3D
	mat.roughness = 0.18
	mat.metallic = 0.28
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	part.material_override = mat

static func _tail(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections := [Vector4(2.32, 0.27, 0.44, 0.40), Vector4(4.1, 0.7, 0.28, 0.28), Vector4(6.93, 1.27, 0.12, 0.18)]
	for index in sections.size() - 1:
		for ring in 10:
			var a := float(ring) * TAU / 10.0
			var b := float(ring + 1) * TAU / 10.0
			_quad(st, _ring(sections[index], a), _ring(sections[index + 1], a), _ring(sections[index + 1], b), _ring(sections[index], b), Color.WHITE)
	st.generate_normals()
	ART.part(parent, "TaperedTailBoom", st.commit(), Vector3.ZERO, NAVY)
	_prism(parent, "SweptVerticalTail", [Vector3(-0.065, 0.96, 6.55), Vector3(-0.065, 3.1, 6.66), Vector3(-0.065, 3.37, 7.27), Vector3(-0.065, 1.35, 7.25), Vector3(-0.065, 0.8, 7.42)], Vector3(0.13, 0, 0), WHITE)
	_prism(parent, "HorizontalStabilizer", [Vector3(-1.6, 0.82, 5.63), Vector3(-1.6, 0.82, 6.07), Vector3(0, 0.82, 6.55), Vector3(1.6, 0.82, 6.07), Vector3(1.6, 0.82, 5.63), Vector3(0, 0.82, 5.87)], Vector3(0, 0.07, 0), WHITE)
	_tube(parent, "RadioAntenna", Vector3(0, 1.38, 2.27), Vector3(0, 2.12, 2.49), 0.017, BLACK)

static func _blade(parent: Node3D, length: float, width: float, thickness: float) -> MeshInstance3D:
	return _prism(parent, "AirfoilBlade", [Vector3(0.35, 0, -width * 0.4), Vector3(length * 0.85, 0.03, -width * 0.55), Vector3(length, 0.035, -width * 0.18), Vector3(length, 0.035, width * 0.42), Vector3(0.75, 0, width * 0.5)], Vector3(0, thickness, 0), BLACK)

static func _prism(parent: Node3D, label: String, polygon: Array, depth: Vector3, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, polygon.size() - 1):
		_tri(st, polygon[0], polygon[index + 1], polygon[index], Color.WHITE)
		_tri(st, polygon[0] + depth, polygon[index] + depth, polygon[index + 1] + depth, Color.WHITE)
	for index in polygon.size():
		var next := (index + 1) % polygon.size()
		_quad(st, polygon[index], polygon[next], polygon[next] + depth, polygon[index] + depth, Color.WHITE)
	st.generate_normals()
	var node := ART.part(parent, label, st.commit(), Vector3.ZERO, color)
	var mat := ART.material(color).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	return node

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for point in [a, b, c]: st.set_color(color); st.add_vertex(point)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)

static func _tube(parent: Node3D, label: String, a: Vector3, b: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 8
	var node := ART.part(parent, label, mesh, (a + b) * 0.5, color)
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return node

static func _polyline(parent: Node3D, label: String, points: Array, radius: float, color: Color) -> void:
	for index in points.size() - 1: _tube(parent, label, points[index], points[index + 1], radius, color)

static func _bake_static(parent: Node3D) -> void:
	var batches: Dictionary = {}
	var pieces: Array[MeshInstance3D] = []
	for child in parent.get_children():
		if not child is MeshInstance3D or child.mesh == null: continue
		var mat: Material = child.material_override
		if mat == null: continue
		if not batches.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[mat] = st
		for surface in child.mesh.get_surface_count():
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices == null or indices.is_empty():
				# append_from does not synthesize indices for a non-indexed source.
				# Mixing its loose vertices with an indexed primitive leaves those
				# triangles unreferenced in the merged surface (the entire tail boom).
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var sequential := PackedInt32Array()
				sequential.resize(vertices.size())
				for vertex in vertices.size(): sequential[vertex] = vertex
				arrays[Mesh.ARRAY_INDEX] = sequential
				var indexed := ArrayMesh.new()
				indexed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				batches[mat].append_from(indexed, 0, child.transform)
			else:
				batches[mat].append_from(child.mesh, surface, child.transform)
		pieces.append(child)
	for mat in batches:
		var mesh: ArrayMesh = batches[mat].commit()
		var node := MeshInstance3D.new()
		node.name = "AirframeFinish"
		node.mesh = mesh
		node.material_override = mat
		parent.add_child(node)
	for child in pieces:
		parent.remove_child(child)
		child.free()
