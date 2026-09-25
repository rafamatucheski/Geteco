extends SceneTree
## Geometry oracle plus all source weapons; no Main, save, or FPS claims.
const FINISH_PATH := "res://assets/regions/source/scripts/player/WeaponFinish3D.gd"
const ARSENAL_PATH := "res://assets/regions/source/scripts/player/ArsenalWeapon3D.gd"
const IDS := ["knuckles", "knife", "bat", "axe", "pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "rpg", "flamethrower", "grenade", "hunting_rifle"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func _script(source: String) -> GDScript:
	var result := GDScript.new()
	result.source_code = source
	_check(result.reload() == OK, "script compiles")
	return result

func _run() -> void:
	var candidate_path := FINISH_PATH
	var legacy_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--candidate="): candidate_path = arg.trim_prefix("--candidate=")
		if arg.begins_with("--legacy="): legacy_path = arg.trim_prefix("--legacy=")
	var finish := _script(FileAccess.get_file_as_string(candidate_path))
	if not failures.is_empty():
		quit(1)
		return
	for inside in [false, true]: _synthetic(finish, inside)
	var first: ArrayMesh = finish._beveled_box(Vector3(.03, .04, .09))
	var second: ArrayMesh = finish._beveled_box(Vector3(.03, .04, .09))
	_check(first == second, "identical bevel geometry is reused")
	var different: ArrayMesh = finish._beveled_box(Vector3(.03, .04, .10))
	_check(first.get_aabb() != different.get_aabb(), "exact dimensions remain distinct")
	# Default oracle leaves finished source pieces unbatched; expected transforms
	# and triangle attributes are read independently before product batching.
	# An archived legacy pass can additionally prove before/after equivalence.
	var reference_source := FileAccess.get_file_as_string(candidate_path).replace("\t\tif moving: _batch_static(moving)", "\t\tif moving: pass").replace("\t_batch_static(root)", "\tpass")
	if not legacy_path.is_empty():
		reference_source = FileAccess.get_file_as_string(legacy_path)
		# Art edits in apply are independent of this optimization. Compare the
		# current authored shapes using old helpers, never an obsolete rail/guard.
		var current_source := FileAccess.get_file_as_string(candidate_path)
		var apply_start := current_source.find("static func apply(")
		var apply_end := current_source.find("static func _finish_meshes(")
		reference_source = reference_source.substr(0, reference_source.find("static func apply(")) + current_source.substr(apply_start, apply_end - apply_start) + reference_source.substr(reference_source.find("static func _finish_meshes("))
	var legacy := _script(reference_source)
	if failures.is_empty():
		var raw_source := FileAccess.get_file_as_string(ARSENAL_PATH).replace("\tpreload(\"" + FINISH_PATH + "\").apply(root, id, flash_pos)", "\t# Finishing is applied independently by this geometry test.")
		var arsenal := _script(raw_source)
		for id in IDS:
			var before := Node3D.new()
			var after := Node3D.new()
			var muzzle_before: Vector3 = arsenal.build(before, id)
			var muzzle_after: Vector3 = arsenal.build(after, id)
			legacy.apply(before, id, muzzle_before)
			finish.apply(after, id, muzzle_after)
			_check(muzzle_before.is_equal_approx(muzzle_after), id + " muzzle unchanged")
			_compare(_snapshot(before, false), _snapshot(after, false), id, false)
			var before_count := before.find_children("*", "MeshInstance3D", true, false).size()
			var after_count := after.find_children("*", "MeshInstance3D", true, false).size()
			_check(after_count == before_count if not legacy_path.is_empty() else after_count <= before_count, id + " draw meshes preserved or consolidated")
			for name in ["Pump", "LoadedRocket", "ReloadCylinder"]:
				_check(before.has_node(NodePath(name)) == after.has_node(NodePath(name)), id + " preserves " + name)
			before.free()
			after.free()
	for i in 280: finish._beveled_box(Vector3(.01 + i * .00013, .042, .019))
	_check(finish.get("_bevel_meshes").size() <= 256, "bevel cache has a hard bound")
	print("PHASE4_WEAPON_BATCH checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func _synthetic(finish: GDScript, inside: bool) -> void:
	var model := Node3D.new()
	model.transform = Transform3D(Basis.from_euler(Vector3(.15, .72, -.3)).scaled(Vector3(1.3, .7, 1.8)), Vector3(31, -6, 8))
	if inside: root.add_child(model)
	var pivot := Node3D.new()
	model.add_child(pivot)
	pivot.transform = Transform3D(Basis.from_euler(Vector3(.4, -.2, .6)).scaled(Vector3(.7, 1.3, 1.9)), Vector3(.4, -.8, 1.2))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.2, .5, .7)
	for indexed in [true, false]:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(.2, 0, 0), Vector3(0, .3, 0), Vector3(0, 0, .4)])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3(1, 2, 3).normalized(), Vector3(2, 1, 3).normalized(), Vector3(3, 2, 1).normalized()])
		if indexed:
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([2, 0, 1])
			arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(.1, .2), Vector2(.3, .4), Vector2(.5, .6)])
			arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var piece := MeshInstance3D.new()
		piece.mesh = mesh
		piece.material_override = material
		pivot.add_child(piece)
		piece.transform = Transform3D(Basis.from_euler(Vector3(.6, .1, .2)).scaled(Vector3(-.8, 1.7, 1.1)), Vector3(.1 if indexed else -.2, .3, .5))
	var moving: Array[Node3D] = []
	for name in ["Pump", "LoadedRocket", "ReloadCylinder"]:
		var part := Node3D.new()
		part.name = name
		model.add_child(part)
		var mesh := MeshInstance3D.new()
		mesh.mesh = SphereMesh.new()
		mesh.material_override = material
		part.add_child(mesh)
		moving.append(part)
	var expected := _snapshot(model, true)
	finish._batch_static(model)
	_compare(expected, _snapshot(model, true), "nested transform inside=%s" % inside, true)
	var batched := model.find_children("FinishedMaterial_*", "MeshInstance3D", true, false)
	_check(batched.size() == 1 and batched[0].mesh.surface_get_material(0) == material, "material resource identity preserved")
	for part in moving: _check(is_instance_valid(part) and part.get_child_count() == 1, "moving subtree untouched " + part.name)
	_check(model.find_children("FinishedMaterial_*", "MeshInstance3D", true, false).size() == 1, "one draw mesh for mixed indexed and nonindexed material")
	model.free()

func _snapshot(model: Node3D, skip_moving: bool) -> Dictionary:
	var groups := {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var transform := mesh.transform
		var parent := mesh.get_parent()
		var moving := false
		var moving_bucket := ""
		while parent != model:
			if parent.name in ["Pump", "LoadedRocket", "ReloadCylinder"]:
				moving = true
				moving_bucket += "/" + str(parent.name)
			transform = parent.transform * transform
			parent = parent.get_parent()
		if skip_moving and moving: continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.material_override if mesh.material_override else mesh.mesh.surface_get_material(surface)
			var key := str(material.albedo_color, "/", material.roughness, "/", material.metallic, moving_bucket)
			if not groups.has(key): groups[key] = []
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for corner in (indices.size() if not indices.is_empty() else vertices.size()):
				var index: int = indices[corner] if not indices.is_empty() else corner
				var uv: Vector2 = arrays[Mesh.ARRAY_TEX_UV][index] if arrays[Mesh.ARRAY_TEX_UV] != null else Vector2.ZERO
				var color: Color = arrays[Mesh.ARRAY_COLOR][index] if arrays[Mesh.ARRAY_COLOR] != null else Color.WHITE
				groups[key].append([transform * vertices[index], (transform.basis.inverse().transposed() * normals[index]).normalized(), uv, color])
	return groups

func _compare(expected: Dictionary, actual: Dictionary, label: String, attributes: bool) -> void:
	var topology := expected.size() == actual.size()
	var positions := true
	var normals := true
	var uv_colors := true
	for key in expected:
		if not actual.has(key) or expected[key].size() != actual[key].size():
			topology = false
			continue
		for i in expected[key].size():
			positions = positions and expected[key][i][0].distance_to(actual[key][i][0]) < .00002
			normals = normals and expected[key][i][1].distance_to(actual[key][i][1]) < .0003
			if attributes: uv_colors = uv_colors and expected[key][i][2].distance_to(actual[key][i][2]) < .00001 and expected[key][i][3].is_equal_approx(actual[key][i][3])
	_check(topology, label + " material groups and triangle order/count")
	_check(positions, label + " transformed vertices")
	_check(normals, label + " inverse-transpose unit normals")
	if attributes: _check(uv_colors, label + " UV/color attributes")
