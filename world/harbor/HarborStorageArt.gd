extends "res://world/mountain_pass/MountainStaticModelView.gd"
## Preserve the authored arrangement while giving each load its own physics.
func _ready() -> void:
	z_as_relative = false
	z_index = 4
	build_view(preload("res://world/harbor/InteractiveStorageComposition.gd"), 10.5, 22.0, Vector3(0, 0.5, 0))
	var supports: Array[Dictionary] = []
	for prop in model.get_children():
		if not prop is Node3D or not prop.has_method("get_obstacle_bounds"): continue
		var bounds := AABB()
		var first := true
		for box: AABB in prop.get_obstacle_bounds():
			bounds = box if first else bounds.merge(box)
			first = false
		var origin: Vector3 = prop.position
		if origin.y > 0.05:
			for support in supports:
				if Vector2(origin.x, origin.z).distance_to(support.floor) < 0.65:
					prop.reparent(support.root, false)
					prop.position = origin - support.origin
					break
			if prop.get_parent() != model: continue
		var body := preload("res://world/shared/PhysicalCargo.gd").new()
		var cargo_material := "metal"
		if prop is PortPalletStack3D or prop is PortWoodenPallet3D or prop is PortLongCrate3D or prop is PortCargoCrate3D: cargo_material = "wood"
		elif prop is PortPlasticTote3D: cargo_material = "plastic"
		body.cargo_material = cargo_material
		body.mass_kg = 65.0 if cargo_material == "wood" else 24.0
		body.resistance = 65.0 if cargo_material == "wood" else 110.0
		if prop is PortDrumClusterPallet3D: body.mass_kg = 145.0
		if prop is PortHazardSign3D: body.mass_kg = 6.0
		if prop is PortPlatformCart3D:
			body.mass_kg = 35.0
			body.friction = 28.0
		body.health = body.resistance
		body.position = project_floor(Vector2(origin.x, origin.z))
		var transformed: AABB = model._transform_aabb(prop.transform, bounds)
		var rect := Rect2(Vector2(transformed.position.x, transformed.position.z), Vector2(transformed.size.x, transformed.size.z))
		var shape := CollisionPolygon2D.new()
		shape.polygon = PackedVector2Array([project_floor(rect.position) - body.position, project_floor(Vector2(rect.end.x, rect.position.y)) - body.position, project_floor(rect.end) - body.position, project_floor(Vector2(rect.position.x, rect.end.y)) - body.position])
		body.extent = Vector2(rect.size.x * 22.0, rect.size.y * 17.0)
		body.add_child(shape)
		add_child(body)
		var art := preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
		body.add_child(art)
		art.build_view(prop.get_script(), 4.8, 22.0, Vector3(0, 0.5, 0))
		art.model.queue_free()
		var holder := Node3D.new()
		art.viewport_3d.add_child(holder)
		prop.reparent(holder, false)
		prop.position = Vector3(0, origin.y, 0)
		art.model = holder
		# Keep the calibrated world scale with a smaller render target per object.
		art.viewport_3d.size = Vector2i(288, 240)
		art.sprite_3d.scale *= 960.0 / 288.0
		body.view = art
		supports.append({"root": holder, "floor": Vector2(origin.x, origin.z), "origin": origin})
	sprite_3d.hide()
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for support in supports:
		preload("res://prototypes/harbor_art_pack/PortMeshOptimizer.gd").optimize_hierarchy(support.root)
