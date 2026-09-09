extends SceneTree

func _init() -> void: call_deferred("run")

func run() -> void:
	var car = load("res://prototypes/living_cast/RearEngineCoupe.gd").new()
	root.add_child(car)
	var failures := 0
	var vertices := 0
	var bounds := AABB()
	for node in car.get_children():
		if not node is MeshInstance3D: continue
		if not node.transform.is_finite(): failures += 1
		bounds = bounds.merge(node.transform * node.mesh.get_aabb())
		for index in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(index)
			vertices += arrays[Mesh.ARRAY_VERTEX].size()
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				if not vertex.is_finite(): failures += 1
	if bounds.size.x < 1.9 or bounds.size.x > 2.2: failures += 1
	if bounds.size.z < 4.4 or bounds.size.z > 4.8: failures += 1
	if bounds.size.y < 1.2 or bounds.size.y > 1.5: failures += 1
	print("COUPE_GEOMETRY_RESULT failures=%d meshes=%d vertices=%d dimensions=%s" % [failures,car.get_child_count(),vertices,bounds.size])
	car.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
