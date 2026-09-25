extends SceneTree
## CPU/resource attribution and material isolation, not a rendered FPS test.
const ART_PATH := "res://assets/regions/source/guns/ammunation/AmmunationArt.gd"
const FINISH := preload("res://gameplay/WeaponAttachmentVisuals.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func _script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	_check(script.reload() == OK, "kit script compiles")
	return script

func _run() -> void:
	var candidate_path := ART_PATH
	var legacy_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--candidate="): candidate_path = arg.trim_prefix("--candidate=")
		if arg.begins_with("--legacy="): legacy_path = arg.trim_prefix("--legacy=")
	var source := FileAccess.get_file_as_string(candidate_path).replace("\r\n", "\n")
	var candidate := _script(source)
	# Independent uncached primitive construction is available without an archive.
	var reference := source
	var start := reference.find("static func box(")
	var end := reference.find("static func text(")
	reference = reference.substr(0, start) + "static func box(root: Node3D, size: Vector3, pos: Vector3, color: Color, _unique_material := false) -> MeshInstance3D:\n\treturn P.piece(root, size, pos, color)\n\n" + reference.substr(end)
	reference = reference.replace("\tif _bevel_meshes.has(size): return _bevel_meshes[size]\n", "").replace("\tif _bevel_meshes.size() < GEOMETRY_CACHE_LIMIT: _bevel_meshes[size] = mesh\n", "")
	if not legacy_path.is_empty(): reference = FileAccess.get_file_as_string(legacy_path)
	var legacy := _script(reference)
	if not failures.is_empty():
		quit(1)
		return
	# Warm only the shared Arsenal/WeaponFinish dependency before A/B kit timings.
	var warmup := Node3D.new()
	legacy.room(warmup, false)
	warmup.free()
	for mountain in [false, true]:
		var before := Node3D.new()
		var after := Node3D.new()
		var began := Time.get_ticks_usec()
		legacy.room(before, mountain)
		var before_ms := (Time.get_ticks_usec() - began) / 1000.0
		began = Time.get_ticks_usec()
		candidate.room(after, mountain)
		var after_ms := (Time.get_ticks_usec() - began) / 1000.0
		_check(_signature(before) == _signature(after), "room geometry/transforms/materials match mountain=%s" % mountain)
		_check(_inventory(after).materials < _inventory(before).materials, "room unique materials reduced mountain=%s" % mountain)
		_check(_inventory(after).mesh_resources < _inventory(before).mesh_resources, "room mesh resources reduced mountain=%s" % mountain)
		print("ART_CACHE_CPU ", JSON.stringify({"mountain": mountain, "reference_ms": before_ms, "candidate_ms": after_ms, "reference_inventory": _inventory(before), "candidate_inventory": _inventory(after), "condition": "headless CPU causal, shared Arsenal warmed; no FPS approval"}))
		var vance := after.find_child("VanceMilitaryGunsmith", true, false)
		_check(vance != null and vance.get_meta("workplace_shield_pivots", []).size() == 2, "Vance reaction pivots preserved")
		var glass := _glass(after)
		_check(glass.size() == 2 and glass[0].material_override == glass[1].material_override, "counter glass and top share their unique material")
		var opaque := candidate.box(after, Vector3(.1, .2, .3), Vector3.ZERO, Color("a5d2ca")) as MeshInstance3D
		_check(opaque.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(opaque.material_override.albedo_color.a, 1.0), "glass mutation cannot contaminate opaque same-color material")
		var second_room := Node3D.new()
		candidate.room(second_room, mountain)
		var second_glass := _glass(second_room)
		_check(second_glass.size() == 2 and second_glass[0].material_override != glass[0].material_override, "glass material independent across rooms")
		glass[0].material_override.albedo_color = Color.RED
		_check(not second_glass[0].material_override.albedo_color.is_equal_approx(Color.RED), "mutating first room glass leaves second room unchanged")
		before.free()
		after.free()
		second_room.free()
	for id in ["pistol", "grenade", "armor"]:
		var preview := Node3D.new()
		var other := Node3D.new()
		candidate.item(preview, id)
		candidate.item(other, id)
		var unchanged := _signature(other)
		FINISH._finish(preview, "gold")
		_check(_signature(other) == unchanged, id + " finish cannot contaminate another instance")
		preview.free()
		preview = Node3D.new()
		candidate.item(preview, id)
		_check(_signature(preview) == unchanged, id + " finish cannot contaminate later preview")
		FINISH._recolor(preview, {"recolor": {"222b2d": Color.PURPLE, "626b46": Color.PURPLE}})
		_check(_signature(other) == unchanged, id + " recolor cannot contaminate another instance")
		preview.free()
		other.free()
	var holder := Node3D.new()
	var repeated_a: MeshInstance3D = candidate.box(holder, Vector3(.11, .22, .33), Vector3.ZERO, Color("243d33"))
	var repeated_b: MeshInstance3D = candidate.box(holder, Vector3(.11, .22, .33), Vector3.ONE, Color("243d33"))
	_check(repeated_a.mesh == repeated_b.mesh and repeated_a.material_override == repeated_b.material_override, "identical immutable box/material resources reused")
	for index in 300:
		candidate.box(holder, Vector3(.015 + index * .00015, .024, .09), Vector3.ZERO, Color.from_hsv(index / 301.0, .73, .89))
		candidate.bevel_box(Vector3(.027 + index * .00013, .03, .07))
	_check(candidate.get("_box_meshes").size() <= 256 and candidate.get("_bevel_meshes").size() <= 256 and candidate.get("_box_materials").size() <= 64, "all three caches bounded")
	holder.free()
	print("PHASE4_ART_CACHE checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func _glass(model: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override is StandardMaterial3D and mesh.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA: result.append(mesh)
	return result

func _signature(model: Node3D) -> Array:
	var result := []
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var transform := mesh.transform
		var parent := mesh.get_parent()
		while parent != model:
			transform = parent.transform * transform
			parent = parent.get_parent()
		var surfaces := []
		for surface in mesh.mesh.get_surface_count():
			var material: Material = mesh.material_override if mesh.material_override else mesh.mesh.surface_get_material(surface)
			var attributes := []
			if material is StandardMaterial3D:
				attributes = [material.albedo_color, material.roughness, material.metallic, material.transparency, material.cull_mode, material.shading_mode, material.emission_enabled]
			surfaces.append([hash(mesh.mesh.surface_get_arrays(surface)), attributes])
		result.append([transform, surfaces])
	return result

func _inventory(model: Node3D) -> Dictionary:
	var meshes := {}
	var materials := {}
	var count := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		count += 1
		meshes[mesh.mesh.get_instance_id()] = true
		if mesh.material_override: materials[mesh.material_override.get_instance_id()] = true
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if material: materials[material.get_instance_id()] = true
	return {"meshes": count, "mesh_resources": meshes.size(), "materials": materials.size()}
