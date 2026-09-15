extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	for id in ["sport_estate", "nordic_estate", "station_wagon"]:
		var spec := VehicleCatalog.get_vehicle_spec(id)
		var model = load(spec.model_class).new()
		world.add_child(model)
		assert(model.has_node("LongEstateRoof"), "Estate must use a long roof, not sedan geometry")
		var roof = model.get_node("LongEstateRoof")
		assert(roof.mesh.get_aabb().size.z > 2.35)
		var wheels := {}
		for mesh in model.get_children():
			if mesh.has_meta("wheel_center"): wheels[mesh.get_meta("wheel_center")] = true
		assert(wheels.size() == 4)
		model.apply_impact(Vector3(0,0.6,-2.3),Vector3(0,0,1),8.0)
		assert(model.impact_count > 0)
		model.repair()
		assert(model.impact_count == 0)
		var door := preload("res://prototypes/living_cast/VehicleDoor3D.gd").new()
		model.add_child(door)
		door.configure(model,-1)
		assert(door.extracted_triangles > 0, "New estate must support actual boarding doors")
		print("ESTATE PASS ",id," roof=",roof.mesh.get_aabb().size," door triangles=",door.extracted_triangles)
	world.queue_free()
	await process_frame
	var street := Node2D.new()
	root.add_child(street)
	current_scene = street
	var index := 0
	for id in ["sport_estate", "nordic_estate"]:
		assert(id in preload("res://world/harbor/HarborLife.gd").CAR_TYPES)
		assert(id in VehicleCatalog.DISTRICT_VEHICLES.city)
		var lane := ModernTrafficFactory.create_lane(street,id,PackedVector2Array([Vector2(0,index*200),Vector2(1500,index*200)]))
		var car := ModernTrafficFactory.spawn_moving_vehicle(lane,id,id,0.2,90,0)
		car.ensure_presentation()
		assert(car.body_model.get_script().resource_path == VehicleCatalog.get_vehicle_spec(id).model_class)
		assert(car.is_3d_vehicle and car.wheel_rig != null)
		assert(is_equal_approx(car.target_length,VehicleCatalog.get_vehicle_spec(id).target_length))
		print("ESTATE TRAFFIC PASS ",id)
		index += 1
	street.queue_free()
	await process_frame
	quit()
