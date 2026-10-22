extends "res://tools/fleet_fixups/build_breakaway_prototype.gd"
## Offline partition: the closed authored exterior is conserved, with a real
## deck lid pivot and an opaque recessed bay. No per-frame mesh processing.
const TRUNK_OUTPUT := "res://assets/fleet/interactive"
const TRUNK_PIVOT := Vector3(0, .81, 1.425)
const TRUNK_ZONE := AABB(Vector3(-.76, .70, 1.425), Vector3(1.52, .85, .78))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TRUNK_OUTPUT))
	steel = StandardMaterial3D.new()
	steel.resource_name = "trunk_liner"
	steel.vertex_color_use_as_albedo = true
	steel.albedo_color = Color.WHITE
	steel.roughness = .88
	var reports := {}
	for variant: String in ["redesigned", "breakaway"]:
		var source := "res://assets/fleet/" + variant + "/monaliza.scn"
		var model: Node3D = load(source).instantiate()
		var report := partition_trunk(model)
		if report.is_empty(): model.free(); continue
		model.set_meta("interactive_trunk_version", 1)
		model.set_meta("interactive_trunk_source_sha256", FileAccess.get_sha256(source))
		own(model, model)
		var packed := PackedScene.new()
		var result := packed.pack(model)
		if result == OK:
			result = ResourceSaver.save(packed, TRUNK_OUTPUT.path_join("monaliza_" + variant + ".scn"), ResourceSaver.FLAG_BUNDLE_RESOURCES)
		if result != OK: fail("trunk save " + variant + " " + str(result))
		report.source = source
		reports[variant] = report
		print("MONALIZA_TRUNK ", variant, " ", JSON.stringify(report))
		model.free()
	FileAccess.open(TRUNK_OUTPUT.path_join("monaliza-trunk.json"), FileAccess.WRITE).store_string(JSON.stringify(reports, "\t"))
	quit(0 if failures.is_empty() else 1)

func partition_trunk(model: Node3D) -> Dictionary:
	var bucket := {}
	var source_area := 0.0
	var kept_area := 0.0
	var lid_area := 0.0
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null or node.name != "Body": continue
		var xf := relative(model, node)
		var inverse := xf.affine_inverse()
		var rebuilt := ArrayMesh.new()
		var roles: Array = []
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else points.size()
			var role := ROLES.key(node, surface)
			var material := node.get_active_material(surface)
			var keep: Array = []
			for first in range(0, count, 3):
				var polygon: Array = []
				for offset in 3:
					polygon.append(vertex(arrays, indices[first + offset] if not indices.is_empty() else first + offset, xf))
				source_area += polygon_area(polygon)
				var normal := ((polygon[1][0] as Vector3) - (polygon[0][0] as Vector3)).cross((polygon[2][0] as Vector3) - (polygon[0][0] as Vector3)).normalized()
				var base_role := role.get_slice("#", 0)
				var eligible := base_role == "paint" and absf(normal.y) > .5
				var zone := TRUNK_ZONE
				# The rear spoiler and its vertical supports belong to the lid.
				# Keep the rear-window frame ahead of them fixed to the cabin.
				if base_role in ["detail", "trim", "chrome"]:
					eligible = true
					zone = AABB(Vector3(-1.02, .72, 1.75), Vector3(2.04, .83, .37))
				var split: Array = clip_box(polygon, zone) if eligible else [[], [polygon]]
				if not split[0].is_empty():
					lid_area += polygon_area(split[0])
					add_bucket(bucket, material, role, split[0])
				for fragment: Array in split[1]:
					kept_area += polygon_area(fragment)
					append_fan(keep, fragment)
			if keep.is_empty(): continue
			for item: Array in keep:
				item[0] = inverse * (item[0] as Vector3)
				item[1] = (xf.basis.transposed() * (item[1] as Vector3)).normalized()
			rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, to_arrays(keep))
			rebuilt.surface_set_material(rebuilt.get_surface_count() - 1, material)
			roles.append(role)
		for surface in node.get_surface_override_material_count(): node.set_surface_override_material(surface, null)
		node.mesh = rebuilt
		node.material_override = null
		set_roles(node, roles)
	var error := absf(source_area - kept_area - lid_area)
	if lid_area < .25 or error > .001:
		fail("trunk partition area=" + str(lid_area) + " conservation=" + str(error))
		return {}
	var hinge := Node3D.new()
	hinge.name = "MonalizaTrunkHinge"
	hinge.position = TRUNK_PIVOT
	model.add_child(hinge)
	var lid := MeshInstance3D.new()
	lid.name = "MonalizaTrunkLid"
	lid.mesh = build_panel(bucket, "trunk")
	lid.position = -TRUNK_PIVOT
	var lid_roles: Array = []
	for entry: Dictionary in bucket.values(): lid_roles.append(entry.role)
	lid_roles.append("trunk_liner")
	set_roles(lid, lid_roles)
	hinge.add_child(lid)
	var bay_vertices: Array = []
	add_box(bay_vertices, Vector3(0, .61, 1.80), Vector3(1.48, .04, .74), Color("202725"))
	add_box(bay_vertices, Vector3(-.74, .67, 1.80), Vector3(.035, .12, .74), Color("29312f"))
	add_box(bay_vertices, Vector3(.74, .67, 1.80), Vector3(.035, .12, .74), Color("29312f"))
	add_box(bay_vertices, Vector3(0, .67, 1.43), Vector3(1.48, .12, .035), Color("29312f"))
	add_box(bay_vertices, Vector3(0, .67, 2.17), Vector3(1.48, .12, .035), Color("29312f"))
	attach_hardware(model, "MonalizaTrunkBay", bay_vertices)
	return {"lid_area": lid_area, "closed_exterior_area_error": error, "hinge": str(TRUNK_PIVOT)}
