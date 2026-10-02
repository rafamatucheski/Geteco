extends Node3D
## Splits the prepared sport coupe body at the authored door seams. This runs
## only on the vehicle being entered; traffic keeps its shared prepared meshes.

var hinges: Dictionary = {}

func configure(vehicle: CharacterBody3D) -> bool:
	var shell: MeshInstance3D
	var glass: MeshInstance3D
	for child in vehicle.visual.get_children():
		if not child is MeshInstance3D: continue
		var part := child as MeshInstance3D
		if part.mesh == null: continue
		var key := str(part.get_meta("coupe_damage_material_key", ""))
		var arrays := part.mesh.surface_get_arrays(0)
		var triangles: int = (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
		if key == "paint" and triangles > 5000: shell = part
		elif key == "glass" and triangles == 68: glass = part
	if shell == null or glass == null: return false

	var source := shell.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	if indices.is_empty(): return false
	var fixed := PackedInt32Array()
	var leaves := {-1: PackedInt32Array(), 1: PackedInt32Array()}
	for i in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[i]]
		var b: Vector3 = vertices[indices[i + 1]]
		var c: Vector3 = vertices[indices[i + 2]]
		var center := (a + b + c) / 3.0
		var side := -1 if center.x < 0.0 else 1
		# Lower sidewall strips between the original A-pillar and rear shut line.
		var normal := (b - a).cross(c - a).normalized()
		var door_face := absf(center.x) > .76 and absf(normal.x) > .60 \
			and center.y >= .24 and center.y <= .92 and center.z >= -.70 and center.z <= .81
		if door_face:
			var leaf: PackedInt32Array = leaves[side]
			leaf.append_array(PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]]))
			leaves[side] = leaf
		else:
			fixed.append_array(PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]]))
	if leaves[-1].is_empty() or leaves[1].is_empty(): return false

	var static_arrays := source.duplicate(true)
	static_arrays[Mesh.ARRAY_INDEX] = fixed
	var static_shell := ArrayMesh.new()
	static_shell.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, static_arrays)
	var door_meshes := {}
	for side in [-1, 1]:
		door_meshes[side] = _compact_mesh(source, leaves[side], false)

	var glass_source := glass.mesh.surface_get_arrays(0)
	var glass_vertices: PackedVector3Array = glass_source[Mesh.ARRAY_VERTEX]
	var glass_normals: PackedVector3Array = glass_source[Mesh.ARRAY_NORMAL]
	var glass_tool := SurfaceTool.new()
	glass_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var removed := {-1: 0, 1: 0}
	for i in range(0, glass_vertices.size(), 3):
		var a: Vector3 = glass_vertices[i]
		var b: Vector3 = glass_vertices[i + 1]
		var c: Vector3 = glass_vertices[i + 2]
		var side := -1 if (a.x + b.x + c.x) < 0.0 else 1
		var side_window := minf(absf(a.x), minf(absf(b.x), absf(c.x))) >= .59 \
			and (absf(a.z + .73) < .015 or absf(b.z + .73) < .015 or absf(c.z + .73) < .015 \
			or absf(a.z - 1.17) < .015 or absf(b.z - 1.17) < .015 or absf(c.z - 1.17) < .015)
		if side_window:
			removed[side] += 1
			continue
		for j in 3:
			glass_tool.set_normal(glass_normals[i + j])
			glass_tool.add_vertex(glass_vertices[i + j])
	if removed[-1] != 2 or removed[1] != 2: return false
	for side in [-1, 1]:
		var s := float(side)
		# Keep the rear quarter pane fixed. The front glass belongs to the door.
		_add_quad(glass_tool, Vector3(s*.60, 1.25, .24), Vector3(s*.60, 1.25, .64),
			Vector3(s*.78, .82, 1.17), Vector3(s*.765, .815, .32))
	glass.mesh = glass_tool.commit()
	shell.mesh = static_shell

	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("30373d")
	trim.metallic = .15
	trim.roughness = .45
	var moving_glass := (glass.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	# The opened pane needs enough sky reflection to read against dark asphalt.
	moving_glass.albedo_color = Color("35566a")
	moving_glass.metallic = .3
	moving_glass.roughness = .18
	moving_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var interior := StandardMaterial3D.new()
	interior.albedo_color = Color("222c33")
	interior.roughness = .84
	for side in [-1, 1]:
		var s := float(side)
		var hinge := Node3D.new()
		hinge.name = "DriverDoorL" if side < 0 else "DriverDoorR"
		hinge.position = Vector3(s*.87, 0.0, -.72475)
		add_child(hinge)
		hinges[side] = hinge
		_add_leaf_mesh(hinge, door_meshes[side], shell.material_override)
		var reversed := PackedInt32Array()
		for i in range(0, leaves[side].size(), 3):
			reversed.append_array(PackedInt32Array([leaves[side][i + 2], leaves[side][i + 1], leaves[side][i]]))
		_add_leaf_mesh(hinge, _compact_mesh(source, reversed, true), interior)
		var pane_tool := SurfaceTool.new()
		pane_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_quad(pane_tool, Vector3(s*.75, .81, -.73), Vector3(s*.60, 1.25, -.30),
			Vector3(s*.60, 1.25, .24), Vector3(s*.765, .815, .32))
		_add_leaf_mesh(hinge, pane_tool.commit(), moving_glass)
		_add_bar(hinge, Vector3(s*.75, .81, -.73), Vector3(s*.60, 1.25, -.30), .027, shell.material_override)
		_add_bar(hinge, Vector3(s*.60, 1.25, -.30), Vector3(s*.60, 1.25, .24), .026, shell.material_override)
		_add_bar(hinge, Vector3(s*.60, 1.25, .24), Vector3(s*.765, .815, .32), .026, shell.material_override)
		_add_bar(hinge, Vector3(s*.765, .815, .32), Vector3(s*.75, .81, -.73), .014, trim)
		_add_bar(hinge, Vector3(s*.912, .76, .83), Vector3(s*.882, .34, .70), .014, shell.material_override)
		_add_bar(hinge, Vector3(s*.882, .34, .70), Vector3(s*.862, .34, -.57), .014, shell.material_override)
		var handle := MeshInstance3D.new()
		var handle_mesh := BoxMesh.new()
		handle_mesh.size = Vector3(.025, .025, .15)
		handle.mesh = handle_mesh
		handle.material_override = trim
		handle.position = Vector3(s*.92, .71, .52) - hinge.position
		hinge.add_child(handle)
	return true

func _compact_mesh(source: Array, selection: PackedInt32Array, inward: bool) -> ArrayMesh:
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = source[Mesh.ARRAY_TANGENT]
	var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var compact_vertices := PackedVector3Array()
	var compact_normals := PackedVector3Array()
	var compact_tangents := PackedFloat32Array()
	var compact_uvs := PackedVector2Array()
	var compact_indices := PackedInt32Array()
	var local_remap := {}
	for old_index in selection:
		if not local_remap.has(old_index):
			local_remap[old_index] = compact_vertices.size()
			compact_vertices.append(vertices[old_index])
			compact_normals.append(-normals[old_index] if inward else normals[old_index])
			compact_uvs.append(uvs[old_index])
			for component in 4: compact_tangents.append(tangents[old_index * 4 + component])
		compact_indices.append(local_remap[old_index])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = compact_vertices
	arrays[Mesh.ARRAY_NORMAL] = compact_normals
	arrays[Mesh.ARRAY_TANGENT] = compact_tangents
	arrays[Mesh.ARRAY_TEX_UV] = compact_uvs
	arrays[Mesh.ARRAY_INDEX] = compact_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		tool.set_normal(Vector3(signf(point.x), 0.0, 0.0))
		tool.add_vertex(point)

func _add_leaf_mesh(hinge: Node3D, mesh: Mesh, surface_material: Material) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = surface_material
	part.position = -hinge.position
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	hinge.add_child(part)

func _add_bar(hinge: Node3D, a: Vector3, b: Vector3, radius: float, surface_material: Material) -> void:
	var direction := b - a
	var bar := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = direction.length()
	cylinder.radial_segments = 6
	bar.mesh = cylinder
	bar.material_override = surface_material
	bar.position = (a + b) * .5 - hinge.position
	bar.quaternion = Quaternion(Vector3.UP, direction.normalized())
	hinge.add_child(bar)
