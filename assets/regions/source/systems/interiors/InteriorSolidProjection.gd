extends RefCounted
## Generate ground blockers from the rendered meshes, grouped by solid object.
## Thin legs do not make a table walkable. Each object reserves its full ground
## envelope; overhead beams and floor decoration must not be registered as solids.

static func mesh_bounds(model: Node3D) -> Dictionary:
	var bounds := {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var id: StringName = node.get_meta("interior_solid_id", &"")
		if id == &"" or node.mesh == null: continue
		var box: AABB = node.mesh.get_aabb()
		var transform: Transform3D = model.global_transform.affine_inverse() * node.global_transform
		for i in 8:
			var point: Vector3 = transform * box.get_endpoint(i)
			var floor_point := Vector2(point.x, point.z)
			if bounds.has(id):
				bounds[id] = bounds[id].expand(floor_point)
			else:
				bounds[id] = Rect2(floor_point, Vector2.ZERO)
	return bounds

static func build(model: Node3D, body: StaticBody2D, project_floor: Callable) -> void:
	var bounds := mesh_bounds(model)
	for id in bounds:
		var rect: Rect2 = bounds[id]
		assert(rect.has_area(), "Interior solid must have a non-empty footprint: " + String(id))
		var shape := CollisionPolygon2D.new()
		shape.name = id
		shape.set_meta("interior_solid_id", id)
		shape.set_meta("model_floor_rect", rect)
		shape.polygon = PackedVector2Array([
			project_floor.call(rect.position),
			project_floor.call(Vector2(rect.end.x, rect.position.y)),
			project_floor.call(rect.end),
			project_floor.call(Vector2(rect.position.x, rect.end.y)),
		])
		body.add_child(shape)
