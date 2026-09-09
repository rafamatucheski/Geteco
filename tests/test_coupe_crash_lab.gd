extends SceneTree

var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _init() -> void: call_deferred("run")
func run() -> void:
	var lab = load("res://prototypes/living_cast/CoupeCrashLab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await physics_frame
	var car = lab.car
	car.manual_input = false
	car.throttle = 1
	for frame in 360:
		await physics_frame
		if car.collision_count > 0: break
	car.throttle = 0
	car.braking = true
	check(car.collision_count > 0,"Driving did not hit physical barrier")
	check(car.position.z > -23,"Car passed through barrier")
	check(car.health < 100,"Physical crash did not affect health")
	check(car.model.max_deformation() > 0.001,"Physical crash did not deform mesh")
	check(car.model.max_deformation() <= 0.321,"Deformation exceeds bound")
	check(car.debris.size() == 1,"Strong impact did not detach piece")
	print("PHYSICAL_CRASH hit=%s position=%s deformation=%f broken_lamps=%s" % [car.last_hit,car.position,car.model.max_deformation(),car.model.broken_lamps])
	car.reset_vehicle()
	car.model.apply_impact(Vector3(-0.67,0.815,-1.8),Vector3.BACK,2)
	check(car.model.max_deformation() == 0,"Parking touch should not crumple the body")
	car.model.apply_impact(Vector3(-0.67,0.815,-1.8),Vector3.BACK,4)
	var light_dent: float = car.model.max_deformation()
	check(light_dent > 0 and car.model.broken_lamps == [false,false],"Light crash must dent without destroying lamps")
	car.reset_vehicle()
	car.model.apply_impact(Vector3(-0.67,0.815,-1.8),Vector3(0,0,1),12)
	check(car.model.max_deformation() > light_dent,"Strong crash should cause more damage")
	car.update_lights()
	check(car.model.broken_lamps == [true,false],"Left impact must not break right lamp")
	check(not car.headlights[0].visible and car.headlights[1].visible,"Broken headlight still projects light")
	var right_motion := 0.0
	for node in car.model.damaged_vertices:
		var pristine: PackedVector3Array = car.model.originals[node].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var points: PackedVector3Array = car.model.damaged_vertices[node]
		for i in points.size():
			if (node.transform * pristine[i]).x > 0.65:
				right_motion = maxf(right_motion,points[i].distance_to(pristine[i]))
	check(right_motion < 0.001,"Damage leaked into opposite side")
	for i in 8: car.model.apply_impact(Vector3(-0.67,0.815,-1.8),Vector3.BACK,18)
	check(car.model.max_deformation() <= 0.321,"Repeated impacts exceed deformation cap")
	car.light_mode = 2
	car.update_lights()
	check(car.headlights[1].spot_range == 32,"Main beam range incorrect")
	car.braking = true
	car.update_lights()
	check(car.brake_lights[0].light_energy == 2,"Brake light did not brighten")
	car.light_mode = 0
	car.update_lights()
	check(not car.headlights[1].visible,"Lights off failed")
	car.reset_vehicle()
	check(car.model.max_deformation() == 0 and car.health == 100,"Repair failed")
	check(car.model.broken_lamps == [false,false] and car.debris.is_empty(),"Repair left broken lamps/debris")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	lab._unhandled_key_input(key)
	check(car.light_mode == 1,"L key did not cycle lights")
	key.physical_keycode = KEY_N
	lab._unhandled_key_input(key)
	check(not lab.night,"N key did not switch day/night")
	print("COUPE_CRASH_RESULT failures=%d" % failures)
	lab.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
