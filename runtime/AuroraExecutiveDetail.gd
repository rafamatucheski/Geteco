extends RefCounted
## Acabamento do Aurora Executive L (sedã executivo, `assets/fleet/aurora_executive.scn`).
## Roda em `FleetCatalog.create`, depois dos outros acabamentos, só para este modelo.
## Cada etapa é independente e cacheada por classe: criar 40 carros custa a mesma coisa que 1.
static var _hull_mesh: ArrayMesh
## Quantos triângulos do casco tiveram o enrolamento corrigido (para teste).
static var flipped_triangles := 0

static func decorate(model: Node3D) -> void:
	_smooth_hull(model)
	_tint_glass(model)
	_enlarge_lenses(model)
	_add_details(model)
	_merge_parts(model)

## Vidros: a cor de fábrica era um azul-acinzentado claro e chapado que, em sombra, lia como
## plástico. Mais escuro e mais liso, com reflexo do ambiente, como nos outros sedãs.
static func _tint_glass(model: Node3D) -> void:
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var material := part.material_override as StandardMaterial3D
		if material == null or material.resource_name != "glass": continue
		if not _glass.has(material):
			var copy := material.duplicate() as StandardMaterial3D
			copy.albedo_color = Color(0.12, 0.20, 0.24)
			copy.metallic = 0.12
			copy.roughness = 0.09
			_glass[material] = copy
		part.material_override = _glass[material]

## Faróis e lanternas eram tiras de 8 cm: lidas de cima, sumiam. Ficam com 13 cm de altura.
static func _enlarge_lenses(model: Node3D) -> void:
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box := part.mesh as BoxMesh
		var material := part.material_override as StandardMaterial3D
		if box == null or material == null or not material.emission_enabled or part.has_meta("wheel_center"): continue
		if absf(box.size.y - 0.08) > 0.001 or absf(box.size.z - 0.03) > 0.001: continue
		var grown := BoxMesh.new()
		grown.size = Vector3(box.size.x, 0.13, box.size.z)
		part.mesh = grown
		part.position.y += 0.025

static var _glass: Dictionary = {}

## O casco tinha os 252 triângulos dos dois flancos (portas e laterais) com o enrolamento
## invertido: o Godot os descarta como face traseira e, de lado, o carro mostrava o
## interior escuro no lugar da lataria. Aqui cada triângulo é orientado para fora do
## casco e recebe normal própria; só se suaviza curva de verdade (ângulo menor que
## `SMOOTH_ANGLE` entre faces vizinhas), senão o flanco herdava a normal do teto.
const SMOOTH_ANGLE := 62.0
## Elipsoide que aproxima o casco: aponta o "fora" de cada triângulo.
const HULL_CENTER := Vector3(0.0, 0.58, 0.0)
const HULL_RADII := Vector3(1.0, 0.34, 2.6)

static func _smooth_hull(model: Node3D) -> void:
	var hull: MeshInstance3D = null
	var triangles := 0
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not part.mesh is ArrayMesh or part.has_meta("wheel_center") or part.mesh.get_surface_count() != 1: continue
		var count: int = part.mesh.surface_get_array_len(0)
		if count > triangles:
			triangles = count
			hull = part
	if hull == null: return
	if _hull_mesh == null: _hull_mesh = _rebuilt(hull.mesh)
	hull.mesh = _hull_mesh

static func _rebuilt(source: Mesh) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	var order := PackedInt32Array()
	if indices != null and (indices as PackedInt32Array).size() > 0: order = (indices as PackedInt32Array).duplicate()
	else:
		order.resize(vertices.size())
		for i in order.size(): order[i] = i
	# Whole-number grouping/index; preserve integer truncation and precision.
	@warning_ignore("integer_division")
	var count: int = order.size() / 3
	var face_normal := PackedVector3Array()
	var face_weight := PackedFloat32Array()
	face_normal.resize(count)
	face_weight.resize(count)
	var slots := {}
	var flipped := 0
	for t in count:
		var a := vertices[order[t * 3]]
		var b := vertices[order[t * 3 + 1]]
		var c := vertices[order[t * 3 + 2]]
		var cross := (b - a).cross(c - a)
		face_weight[t] = cross.length()
		var geometric := cross / cross.length() if cross.length_squared() > 0.0000000001 else Vector3.UP
		var middle := (a + b + c) / 3.0 - HULL_CENTER
		var outward := Vector3(middle.x / (HULL_RADII.x * HULL_RADII.x), middle.y / (HULL_RADII.y * HULL_RADII.y), middle.z / (HULL_RADII.z * HULL_RADII.z))
		# Horário visto de fora (o que o Godot desenha) = normal geométrica para dentro.
		if geometric.dot(outward) > 0.0:
			# Enrolamento invertido: troca dois vértices e a normal geométrica passa a ser para dentro.
			var swap := order[t * 3 + 1]
			order[t * 3 + 1] = order[t * 3 + 2]
			order[t * 3 + 2] = swap
			flipped += 1
			face_normal[t] = geometric
		else:
			face_normal[t] = -geometric
		for k in 3:
			var key := Vector3i((vertices[order[t * 3 + k]] * 10000.0).round())
			if not slots.has(key): slots[key] = PackedInt32Array()
			(slots[key] as PackedInt32Array).append(t)
	flipped_triangles = flipped
	var limit := cos(deg_to_rad(SMOOTH_ANGLE))
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var has_uv: bool = arrays[Mesh.ARRAY_TEX_UV] != null
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if has_uv else PackedVector2Array()
	for t in count:
		for k in 3:
			var i := order[t * 3 + k]
			var key := Vector3i((vertices[i] * 10000.0).round())
			var sum := Vector3.ZERO
			for other in slots[key]:
				if face_normal[t].dot(face_normal[other]) >= limit: sum += face_normal[other] * face_weight[other]
			out_vertices.append(vertices[i])
			out_normals.append(sum.normalized() if sum.length_squared() > 0.0 else face_normal[t])
			if has_uv: out_uvs.append(uvs[i])
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = out_vertices
	result[Mesh.ARRAY_NORMAL] = out_normals
	if has_uv: result[Mesh.ARRAY_TEX_UV] = out_uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result)
	return mesh

# --- Detalhes de lataria ---------------------------------------------------------------

static var _detail_meshes: Dictionary = {}
static var _hull_triangles := PackedVector3Array()

## Linhas de porta nos dois flancos, caixa de farol e placa traseira. Tudo em duas malhas
## (uma escura, uma clara) compartilhadas por todos os carros deste modelo. As linhas
## acompanham a superfície real do casco: cada ponto é achado por raio contra os triângulos.
static func _add_details(model: Node3D) -> void:
	if _detail_meshes.is_empty():
		_hull_triangles = _collect_hull_triangles(model)
		var dark := SurfaceTool.new()
		dark.begin(Mesh.PRIMITIVE_TRIANGLES)
		var light := SurfaceTool.new()
		light.begin(Mesh.PRIMITIVE_TRIANGLES)
		_door_lines(dark)
		_lamp_bezels(dark)
		_plate(dark, light)
		var dark_material := StandardMaterial3D.new()
		dark_material.resource_name = "trim_dark"
		dark_material.albedo_color = Color(0.035, 0.045, 0.055)
		dark_material.roughness = 0.55
		dark_material.metallic = 0.1
		dark.set_material(dark_material)
		var light_material := StandardMaterial3D.new()
		light_material.resource_name = "plate"
		light_material.albedo_color = Color(0.86, 0.86, 0.80)
		light_material.roughness = 0.5
		light.set_material(light_material)
		_detail_meshes["dark"] = dark.commit()
		_detail_meshes["light"] = light.commit()
	for key in _detail_meshes:
		var node := MeshInstance3D.new()
		node.name = "Aurora_" + key
		node.mesh = _detail_meshes[key]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(node)

static func _collect_hull_triangles(model: Node3D) -> PackedVector3Array:
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == _hull_mesh: return (_hull_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	return PackedVector3Array()

## x do casco no ponto (y, z) do lado `side` (+1/-1): o primeiro triângulo que um raio
## horizontal vindo de fora encontra. NAN se não houver casco ali.
static func hull_x(side: float, y: float, z: float) -> float:
	var origin := Vector3(side * 3.0, y, z)
	var direction := Vector3(-side, 0.0, 0.0)
	var best := INF
	for t in range(0, _hull_triangles.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, direction, _hull_triangles[t], _hull_triangles[t + 1], _hull_triangles[t + 2])
		if hit != null: best = minf(best, (hit as Vector3).distance_to(origin))
	return side * (3.0 - best) if best < INF else NAN

## Fita fina (largura `width`) por uma polilinha no flanco; `lift` afasta da chapa o
## bastante para não brigar com ela no z-buffer.
static func _flank_ribbon(st: SurfaceTool, side: float, points: Array, width: float, lift: float) -> void:
	var previous_left := Vector3.INF
	var previous_right := Vector3.INF
	for p in points:
		var y: float = p.x
		var z: float = p.y
		# A chapa muda de x com a altura (o flanco tem tumblehome): cada borda da fita é
		# posta no casco no seu próprio (y, z), senão uma ponta flutua e a outra afunda.
		var along_z: bool = p.z > 0.5
		var y_a := y - (width * 0.5 if not along_z else 0.0)
		var z_a := z - (width * 0.5 if along_z else 0.0)
		var y_b := y + (width * 0.5 if not along_z else 0.0)
		var z_b := z + (width * 0.5 if along_z else 0.0)
		var x_a := hull_x(side, y_a, z_a)
		var x_b := hull_x(side, y_b, z_b)
		if is_nan(x_a) or is_nan(x_b): previous_left = Vector3.INF; continue
		var a := Vector3(x_a + side * lift, y_a, z_a)
		var b := Vector3(x_b + side * lift, y_b, z_b)
		if previous_left != Vector3.INF:
			var normal := Vector3(side, 0, 0)
			# Horário visto de fora (o que o Godot desenha).
			var quad := [previous_left, previous_right, b, a] if side > 0 else [previous_left, a, b, previous_right]
			for index in [0, 1, 2, 0, 2, 3]:
				st.set_normal(normal)
				st.add_vertex(quad[index])
		previous_left = a
		previous_right = b

static func _door_lines(st: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		# Emendas verticais da porta dianteira e traseira (z de VehicleDoorSpecs) e a soleira.
		for z in [-0.90, 0.25, 1.36]:
			var points := []
			for i in 8:
				points.append(Vector3(lerpf(0.45, 0.84, float(i) / 7.0), z, 0.0))
			_flank_ribbon(st, side, points, 0.014, 0.004)
		var sill := []
		for i in 12:
			sill.append(Vector3(0.455, lerpf(-0.90, 1.36, float(i) / 11.0), 1.0))
		_flank_ribbon(st, side, sill, 0.014, 0.004)

static func _lamp_bezels(st: SurfaceTool) -> void:
	# Moldura escura atrás de cada lente, mais larga que ela: separa o farol da chapa.
	for x in [-0.61, 0.61]:
		_box(st, Vector3(x, 0.665, -2.586), Vector3(0.58, 0.19, 0.02))
	for x in [-0.43, 0.43]:
		_box(st, Vector3(x, 0.685, 2.544), Vector3(0.58, 0.19, 0.02))

static func _plate(dark: SurfaceTool, light: SurfaceTool) -> void:
	_box(dark, Vector3(0, 0.50, 2.62), Vector3(0.56, 0.16, 0.014))
	_box(light, Vector3(0, 0.50, 2.628), Vector3(0.50, 0.11, 0.012))

static func _box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var source := ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.get_mesh_arrays())
	st.append_from(source, 0, Transform3D(Basis.IDENTITY, center))

# --- Menos peças, mesma imagem -----------------------------------------------------------

## As 4 rodas eram ~18 peças cada (pneu, aro, 12 raios, tampa...). Junta as que têm o
## mesmo material dentro de cada roda; peças de portas, vidro, luz e tinta ficam soltas
## (os outros sistemas as procuram por nome, meta ou material).
static func _merge_parts(model: Node3D) -> void:
	var groups := {}
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or not part.has_meta("wheel_center"): continue
		var material := part.material_override as StandardMaterial3D
		if material == null: continue
		var key := "%s|%s|%s|%s|%s" % [part.get_meta("wheel_center"), part.get_meta("wheel_spins", true), material.albedo_color.to_html(), material.metallic, material.roughness]
		if not groups.has(key): groups[key] = []
		groups[key].append(part)
	# Peças fixas da carroceria (frisos, grade, para-choques, escapamentos): por material.
	# Ficam de fora tudo o que outro sistema procura: meta (porta, roda), luz, vidro e tinta.
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.has_meta("wheel_center") or not part.get_meta_list().is_empty(): continue
		if part.name.begins_with("Aurora_"): continue
		var material := part.material_override as StandardMaterial3D
		if material == null or material.emission_enabled or material.resource_name in ["paint", "glass"]: continue
		var key := "fixo|%s|%s|%s|%s" % [material.albedo_color.to_html(), material.metallic, material.roughness, material.resource_name]
		if not groups.has(key): groups[key] = []
		groups[key].append(part)
	for key in groups:
		var parts: Array = groups[key]
		if parts.size() < 2: continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var expected := AABB()
		var first_box := true
		for part: MeshInstance3D in parts:
			var box: AABB = part.transform * part.mesh.get_aabb()
			expected = box if first_box else expected.merge(box)
			first_box = false
			var source: Mesh = part.mesh
			if not source is ArrayMesh:
				var converted := ArrayMesh.new()
				converted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(0))
				source = converted
			st.append_from(source, 0, part.transform)
		var merged := st.commit()
		var got := merged.get_aabb()
		if got.position.distance_to(expected.position) > 0.01 or got.size.distance_to(expected.size) > 0.01:
			push_warning("Aurora: fusão de '%s' mudaria a caixa (%s vs %s); peças mantidas" % [key, got, expected])
			print("AURORA_MERGE_SKIPPED ", key, " ", got, " vs ", expected)
			continue
		var first: MeshInstance3D = parts[0]
		first.mesh = merged
		first.transform = Transform3D.IDENTITY
		for index in range(1, parts.size()):
			(parts[index] as MeshInstance3D).get_parent().remove_child(parts[index])
			(parts[index] as MeshInstance3D).free()
