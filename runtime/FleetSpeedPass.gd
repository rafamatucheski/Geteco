extends RefCounted
## Passe rápido para toda a frota (modelo por modelo pode ganhar acabamento próprio depois):
## 1) corrige o enrolamento invertido do casco quando o flanco está sendo descartado pelo
##    Godot (carro "sem laterais" de lado); 2) junta peças de roda e peças fixas por material.
## Não mexe em peças com meta (roda/porta), luz, vidro ou tinta. Cada fusão confere a caixa.
const SMOOTH_ANGLE := 62.0
static var _hulls: Dictionary = {}

static func decorate(id: String, model: Node3D) -> void:
	if id.begins_with("bike_") or id == "army_tank" or "--no-fleet-pass" in OS.get_cmdline_user_args(): return
	_fix_hull(id, model)
	_door_lines(id, model)
	merge_parts(model, id)

static func _fix_hull(id: String, model: Node3D) -> void:
	if _hulls.has(id):
		var cached: Variant = _hulls[id]
		if cached == null: return
		var target := _find_hull(model)
		if target != null: target.mesh = cached
		return
	var hull := _find_hull(model)
	if hull == null:
		_hulls[id] = null
		return
	var box: AABB = hull.mesh.get_aabb()
	var center := box.get_center()
	var radii := box.size * 0.5
	if radii.x < 0.2 or radii.y < 0.05 or radii.z < 0.5:
		_hulls[id] = null
		return
	var arrays := hull.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	var order := PackedInt32Array()
	if idx != null and (idx as PackedInt32Array).size() > 0: order = idx
	else:
		order.resize(v.size())
		for i in order.size(): order[i] = i
	var flank := 0
	var culled := 0
	for t in order.size() / 3:
		var a := v[order[t * 3]]
		var b := v[order[t * 3 + 1]]
		var c := v[order[t * 3 + 2]]
		var g := (b - a).cross(c - a)
		if g.length_squared() < 1e-10: continue
		g = g.normalized()
		var m := (a + b + c) / 3.0 - center
		if absf(m.x) < radii.x * 0.7 or absf(g.x) < 0.6: continue
		flank += 1
		if g.x * m.x > 0.0: culled += 1
	if flank < 20 or float(culled) / float(flank) < 0.25:
		_hulls[id] = null
		return
	var fixed := _rebuilt(hull.mesh, center, radii)
	_hulls[id] = fixed
	hull.mesh = fixed

static func _find_hull(model: Node3D) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_n := 0
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not part.mesh is ArrayMesh or part.has_meta("wheel_center") or part.mesh.get_surface_count() != 1: continue
		var m := part.material_override as StandardMaterial3D
		if m == null or m.resource_name != "paint": continue
		var n: int = part.mesh.surface_get_array_len(0)
		if n > best_n:
			best_n = n
			best = part
	return best

static func _rebuilt(source: Mesh, center: Vector3, radii: Vector3) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	var order := PackedInt32Array()
	if indices != null and (indices as PackedInt32Array).size() > 0: order = (indices as PackedInt32Array).duplicate()
	else:
		order.resize(vertices.size())
		for i in order.size(): order[i] = i
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
		var middle := (a + b + c) / 3.0 - center
		var outward := Vector3(middle.x / (radii.x * radii.x), middle.y / (radii.y * radii.y), middle.z / (radii.z * radii.z))
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

# --- Menos peças, mesma imagem -----------------------------------------------------------

## As 4 rodas eram ~18 peças cada (pneu, aro, 12 raios, tampa...). Junta as que têm o
## mesmo material dentro de cada roda; peças de portas, vidro, luz e tinta ficam soltas
## (os outros sistemas as procuram por nome, meta ou material).
static var _plans: Dictionary = {}

static func merge_parts(model: Node3D, id := "") -> void:
	# Custo por carro nascido: a 1ª vez monta as malhas fundidas; as seguintes só as aplicam.
	if id != "" and _plans.has(id):
		var parts := model.find_children("*", "MeshInstance3D", true, false)
		for step: Dictionary in _plans[id]:
			var first: MeshInstance3D = parts[step.first]
			first.mesh = step.mesh
			first.transform = Transform3D.IDENTITY
			for index in step.others:
				var other: MeshInstance3D = parts[index]
				other.get_parent().remove_child(other)
				other.free()
		return
	var plan: Array = []
	var all_parts := model.find_children("*", "MeshInstance3D", true, false)
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
		var material := part.material_override as StandardMaterial3D
		if material == null: continue
		# Luz: lado esquerdo e direito ficam separados (o equipamento decide o lado pela posição).
		var side := ""
		if material.emission_enabled: side = "L" if part.transform.origin.x + part.mesh.get_aabb().get_center().x < 0.0 else "R"
		var key := "fixo|%s|%s|%s|%s|%s|%s" % [material.albedo_color.to_html(), material.metallic, material.roughness, material.resource_name, side, material.get_instance_id()]
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
		var others: Array = []
		for index in range(1, parts.size()): others.append(all_parts.find(parts[index]))
		plan.append({"first": all_parts.find(first), "others": others, "mesh": merged})
		first.mesh = merged
		first.transform = Transform3D.IDENTITY
		for index in range(1, parts.size()):
			(parts[index] as MeshInstance3D).get_parent().remove_child(parts[index])
			(parts[index] as MeshInstance3D).free()
	if id != "": _plans[id] = plan

# --- Linhas de porta (só onde há medida em VehicleDoorSpecs) ---------------------------

static var _doors: Dictionary = {}

static func _door_lines(id: String, model: Node3D) -> void:
	var specs := preload("res://data/catalogs/VehicleDoorSpecs.gd")
	if not specs.has_row(id): return
	if not _doors.has(id):
		_doors[id] = null
		var hull := _find_hull(model)
		if hull == null: return
		var row: Dictionary = specs.row(id)
		if not (row.has("zf") and row.has("zr") and row.has("sill") and row.has("belt")): return
		var v: PackedVector3Array = hull.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var idx: Variant = hull.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		var tris := PackedVector3Array()
		if idx != null and (idx as PackedInt32Array).size() > 0:
			for i in idx: tris.append(hull.transform * v[i])
		else:
			for p in v: tris.append(hull.transform * p)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var zf: float = row.zf
		var zr: float = row.zr
		var span := zr - zf
		var lines: Array = [zf, zr, zr + span * 0.95] if span > 0.4 else [zf, zr]
		for side in [-1.0, 1.0]:
			for z in lines:
				_ribbon(st, tris, side, float(row.sill) + 0.02, float(row.belt) - 0.02, z, true)
			_ribbon(st, tris, side, float(row.sill) + 0.03, float(row.sill) + 0.03, zf, false, lines[lines.size() - 1] - zf)
		var material := StandardMaterial3D.new()
		material.resource_name = "trim_dark"
		material.albedo_color = Color(0.035, 0.045, 0.055)
		material.roughness = 0.55
		st.set_material(material)
		var mesh := st.commit()
		if mesh.get_surface_count() > 0: _doors[id] = mesh
	if _doors[id] == null: return
	var node := MeshInstance3D.new()
	node.name = "DoorLines"
	node.mesh = _doors[id]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(node)

static func _hull_x(tris: PackedVector3Array, side: float, y: float, z: float) -> float:
	var origin := Vector3(side * 4.0, y, z)
	var best := INF
	for t in range(0, tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, Vector3(-side, 0, 0), tris[t], tris[t + 1], tris[t + 2])
		if hit != null: best = minf(best, (hit as Vector3).distance_to(origin))
	return side * (4.0 - best) if best < INF else NAN

static func _ribbon(st: SurfaceTool, tris: PackedVector3Array, side: float, y0: float, y1: float, z: float, vertical: bool, length := 0.0) -> void:
	var steps := 7
	var last_a := Vector3.INF
	var last_b := Vector3.INF
	for i in steps + 1:
		var f := float(i) / float(steps)
		var y := lerpf(y0, y1, f) if vertical else y0
		var zz := z if vertical else z + length * f
		var dy := 0.0 if vertical else 0.007
		var dz := 0.007 if vertical else 0.0
		var xa := _hull_x(tris, side, y - dy, zz - dz)
		var xb := _hull_x(tris, side, y + dy, zz + dz)
		if is_nan(xa) or is_nan(xb):
			last_a = Vector3.INF
			continue
		var a := Vector3(xa + side * 0.004, y - dy, zz - dz)
		var b := Vector3(xb + side * 0.004, y + dy, zz + dz)
		if last_a != Vector3.INF:
			var quad := [last_a, last_b, b, a] if side > 0 else [last_a, a, b, last_b]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(side, 0, 0))
				st.add_vertex(quad[k])
		last_a = a
		last_b = b
