extends SceneTree
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var total_first := 0
	var total_cached := 0
	for script in [preload("res://prototypes/living_cast/models/UnionSedanModel.gd"),preload("res://prototypes/living_cast/models/RouteCityModel.gd"),preload("res://prototypes/living_cast/models/SummitSUVModel.gd")]:
		var time := Time.get_ticks_usec()
		var first: Node3D = script.new()
		root.add_child(first)
		total_first += Time.get_ticks_usec()-time
		time = Time.get_ticks_usec()
		var second: Node3D = script.new()
		root.add_child(second)
		total_cached += Time.get_ticks_usec()-time
		assert(first.get_child_count() == second.get_child_count())
		assert(first.originals.size() == second.originals.size())
		assert(first.lamp_sources.size() == second.lamp_sources.size())
		assert(first.paint != second.paint)
		var color: Color = second.paint.albedo_color
		first.paint.albedo_color = Color.MAGENTA
		assert(second.paint.albedo_color == color)
		for i in first.get_child_count():
			var a := first.get_child(i)
			var b := second.get_child(i)
			assert(a.transform == b.transform)
			if a is MeshInstance3D:
				assert(a.mesh == b.mesh)
				assert(a.material_override != b.material_override)
				assert(a.get_meta("wheel_center",Vector3.INF) == b.get_meta("wheel_center",Vector3.INF))
		preload("res://prototypes/living_cast/VehicleWheelRig.gd").new().mount(first)
		preload("res://prototypes/living_cast/VehicleWheelRig.gd").new().mount(second)
		preload("res://cars/VehicleMeshBatcher.gd").batch_model(first)
		preload("res://cars/VehicleMeshBatcher.gd").batch_model(second)
		assert(preload("res://cars/VehicleMeshBatcher.gd").cache_hits > 0)
		assert(first.originals.size() == second.originals.size())
		first.apply_impact(Vector3(0.8,0.8,-1.5),Vector3.LEFT,15.0)
		assert(second.damaged_vertices.is_empty())
		first.free()
		second.free()
	var hit_count := CACHE.hits
	for i in 2:
		var pumper := preload("res://prototypes/living_cast/models/RescuePumperModel.gd").new()
		root.add_child(pumper)
		assert(is_instance_valid(pumper.water_muzzle) and pumper.is_ancestor_of(pumper.water_muzzle))
		pumper.free()
	assert(CACHE.hits == hit_count)
	# Reuse geometry across different paints, but invalidate when its source changes.
	var box := BoxMesh.new()
	var batch_a := _batch_boxes(box)
	var original: Mesh = batch_a.get_child(0).mesh
	var batch_b := _batch_boxes(box)
	assert(batch_b.get_child(0).mesh == original)
	assert(batch_b.get_child(0).material_override != batch_a.get_child(0).material_override)
	box.size = Vector3(3,2,1)
	await process_frame
	var batch_c := _batch_boxes(box)
	assert(batch_c.get_child(0).mesh != original)
	assert(batch_c.get_child(0).mesh.get_aabb().size.x > original.get_aabb().size.x)
	for batch in [batch_a,batch_b,batch_c]: batch.free()
	await CACHE.prepare_common_models(self)
	assert(not CACHE._models.has("res://prototypes/living_cast/models/ArcticJeepModel.gd"))
	await CACHE.prepare_region(self, &"mountain")
	assert(CACHE._models.has("res://prototypes/living_cast/models/ArcticJeepModel.gd"))
	print("VEHICLE_GEOMETRY_CACHE_RESULT hits=%d first_us=%d cached_us=%d" % [CACHE.hits,total_first,total_cached])
	quit(0)

func _batch_boxes(mesh: Mesh) -> Node3D:
	var model := Node3D.new()
	var material := StandardMaterial3D.new()
	for i in 2:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.material_override = material
		part.position.x = i*2.0
		model.add_child(part)
	preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
	return model
