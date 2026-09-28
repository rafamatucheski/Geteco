extends SceneTree
const ART = preload("res://gameplay/police_response/air_k9/PoliceHelicopterArt.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	ART.build(parent)
	var planes := [3.0, 4.8, 6.6]
	var crossings := [0, 0, 0]
	var invalid_indices := 0
	var surfaces := 0
	for part in parent.get_children():
		if not part is MeshInstance3D: continue
		for surface in part.mesh.get_surface_count():
			surfaces += 1
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty() or indices.size() % 3 != 0: invalid_indices += 1
			for value in indices:
				if value < 0 or value >= vertices.size(): invalid_indices += 1
			if not part.material_override.albedo_color.is_equal_approx(ART.NAVY): continue
			for triangle in range(0, indices.size(), 3):
				var a: Vector3 = vertices[indices[triangle]]
				var b: Vector3 = vertices[indices[triangle + 1]]
				var c: Vector3 = vertices[indices[triangle + 2]]
				for plane in planes.size():
					if minf(a.z, minf(b.z, c.z)) <= planes[plane] and maxf(a.z, maxf(b.z, c.z)) >= planes[plane]: crossings[plane] += 1
	var valid: bool = invalid_indices == 0 and crossings[0] >= 20 and crossings[1] >= 20 and crossings[2] >= 20
	print("AIRFRAME_MESH valid=", valid, " surfaces=", surfaces, " invalid_indices=", invalid_indices, " tail_plane_triangles=", crossings)
	parent.queue_free()
	await process_frame
	quit(0 if valid else 1)
