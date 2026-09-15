extends SceneTree

func _initialize() -> void: run.call_deferred()
func run() -> void:
	var failures := 0
	for id in ["bike_sport","bike_cruiser","bike_urban"]:
		var spec := VehicleCatalog.get_vehicle_spec(id)
		var model: Node3D = load(spec.model_class).new()
		root.add_child(model)
		var tires: Array[MeshInstance3D] = []
		var panels: Array[MeshInstance3D] = []
		for part in model.get_children():
			if not part is MeshInstance3D: continue
			if part.mesh is TorusMesh and part.material_override == model.materials.rubber: tires.append(part)
			if part.material_override == model.paint and not part.has_meta("wheel_center"): panels.append(part)
		var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
		rig.mount(model)
		for angle in [-.58,0.0,.58]:
			rig.update(1.0,0.0,0.0,angle)
			var penetrations := 0
			for panel in panels:
				var arrays := panel.mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var count := indices.size() if not indices.is_empty() else vertices.size()
				for tri in range(0,count,3):
					var a := panel.to_global(vertices[indices[tri] if not indices.is_empty() else tri])
					var b := panel.to_global(vertices[indices[tri+1] if not indices.is_empty() else tri+1])
					var c := panel.to_global(vertices[indices[tri+2] if not indices.is_empty() else tri+2])
					for u in 7:
						for v in range(7-u):
							var sample := a+(b-a)*(u/6.0)+(c-a)*(v/6.0)
							for tire in tires:
								var point := tire.to_local(sample)
								var torus := tire.mesh as TorusMesh
								var major := (torus.outer_radius+torus.inner_radius)*.5
								var minor := (torus.outer_radius-torus.inner_radius)*.5
								if Vector2(Vector2(point.x,point.z).length()-major,point.y).length() < minor-.003:
									penetrations += 1
			print("MOTO_CLEARANCE ",id," steer=",angle," paint/tire intersections=",penetrations)
			if penetrations: failures += 1
		preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
		model.update_riding_pose(1.0,0.0,0.0,true)
		assert(model._leg_parts[0].boot.position.y < .12,"Stopped rider reaches the ground")
		for angle in [-.58,.58]:
			rig.update(1.0,5.0,0.0,angle)
			model.update_riding_pose(1.0,5.0,angle,true)
			for arm in model._arm_parts:
				var resting_grip := Vector3(arm.side*.31,model._handle_y+.015,model._handle_z+.065)
				var axis: Vector3 = model.get_meta("steering_axis_position")
				var grip: Vector3 = axis+Basis(Vector3.UP,angle)*(resting_grip-axis)
				assert(arm.hand.position.distance_to(grip)<.002,"Hand tracks actual handlebar")
		model.free()
	print("MOTORCYCLE_GEOMETRY failures=",failures)
	quit(1 if failures else 0)
