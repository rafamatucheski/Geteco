extends SceneTree
var world
var failures: Array[String] = []
var checks := 0
var exit_observation: Dictionary = {}
var removed_before_callback_id := 0
var removed_callback_deadline := 0

func observe_exit(place: String, car) -> void:
	var presentation = world.driving.transition
	if not is_instance_valid(presentation): return
	var phase: String = str(presentation.phase)
	if exit_observation.get("phase", "") == phase: return
	exit_observation["phase"] = phase
	var now := Time.get_ticks_msec()
	var inside_swing: bool = presentation._inside_swing(presentation._landing, .30)
	var observation := {"event":"exit_phase", "place":place, "msec":now, "car_id":car.get_instance_id(), "presentation_id":presentation.get_instance_id(), "phase":phase, "inside_swing":inside_swing}
	if phase == "close_outside" and inside_swing:
		# Production schedules a 1.6 s callback in this exact branch. This is
		# an observation deadline, not a delay or an alteration of that timer.
		exit_observation["expected_callback_msec"] = now+1600
		exit_observation["side"] = int(presentation.side)
		observation["expected_callback_msec"] = now+1600
	print("GARAGE_EXIT_OBSERVATION ", JSON.stringify(observation))
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func settle(frames := 5) -> void:
	for i in frames: await physics_frame
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var startup_deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec() < startup_deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"Main starts")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	var original_car = world.driving.car
	check(world.production.no_save,"Never touch user save")
	for place in ["maciota","port_boss_garage"]:
		var center := Vector3(0,.08,1.2) if place == "maciota" else Vector3(0,.08,6)
		var saved := {"version":1,"port_status":"parked","alarm_remaining":-1.0,"police_called":false,"vehicles":{"garage_guest_1":{"archetype":"sport_coupe","region_id":"harbor","place_id":place,"position":[center.x,center.y,center.z],"yaw":0.0,"health":80.0,"paint":"ffffffff","was_driven":true}}}
		check(session.garage_rewards.restore_snapshot(saved),place+" saved car accepted")
		check(await session.enter_place(place,false),place+" safe entry before car materializes")
		await settle(12)
		var car = session.garage_rewards.cars.get("garage_guest_1")
		check(is_instance_valid(car),place+" saved car materializes")
		if not is_instance_valid(car): continue
		check(world.driving.occupied and world.driving.car == car,place+" driver restored through admitted door")
		check(world.camera.locked and world.camera.target == session.anchor,place+" interior camera preserved")
		check(not session.state.can_attack() and session.state.equipped_weapon == "fists",place+" attacks remain disabled")
		check(world.production.vehicle_position_clear(car,car.position,car.rotation.y),place+" full hull collision admission")
		session.garage_rewards.on_location_changed()
		await settle()
		var count := 0
		for vehicle in world.production.vehicles:
			if is_instance_valid(vehicle) and vehicle.vehicle_id == "garage_guest_1": count += 1
		check(count == 1,place+" repeated sync does not duplicate car")
		check(session.garage_rewards.snapshot().vehicles.garage_guest_1.was_driven,place+" seated save retains driver")
		exit_observation = {}
		print("GARAGE_EXIT_OBSERVATION ", JSON.stringify({"event":"before_leave", "place":place, "msec":Time.get_ticks_msec(), "car_id":car.get_instance_id()}))
		if world.driving.occupied: check(world.driving.leave(),place+" physical disembark")
		# leave() admits an asynchronous body transition; do not destroy its car.
		var exit_deadline := Time.get_ticks_msec()+6000
		while world.driving.is_body_transition_active() and Time.get_ticks_msec() < exit_deadline:
			observe_exit(place, car)
			await physics_frame
		var on_foot: bool = not world.driving.is_body_transition_active() and not world.driving.occupied
		check(on_foot,place+" physical disembark completes before destroying car")
		if not on_foot:
			world.queue_free()
			await process_frame
			print("GARAGE_DRIVER_RESTORE ",checks," checks failures=",failures)
			quit(1)
			return
		var callback_deadline: int = int(exit_observation.get("expected_callback_msec",0))
		check(callback_deadline > 0,place+" exercises deferred close branch")
		if place == "port_boss_garage" and callback_deadline > 0:
			var side: int = int(exit_observation.side)
			var doors = car.door_presentation
			var previous_motion: Tween = doors.motions.get(side)
			var previous_motion_id: int = previous_motion.get_instance_id() if is_instance_valid(previous_motion) else 0
			# Keep this vehicle alive for the authored 1.6 s callback and .32 s
			# closing tween; the Maciota case below still frees before its timer.
			while Time.get_ticks_msec() < callback_deadline+500:
				await physics_frame
			var close_motion: Tween = doors.motions.get(side)
			var hinge: Node3D = doors.hinges.get(side)
			check(is_instance_valid(car) and is_instance_valid(close_motion) and close_motion.get_instance_id() != previous_motion_id,place+" deferred callback runs on surviving vehicle")
			check(is_instance_valid(hinge) and absf(hinge.rotation.y) < .001,place+" surviving door finishes closed")
			print("GARAGE_EXIT_OBSERVATION ", JSON.stringify({"event":"surviving_callback_complete", "place":place, "msec":Time.get_ticks_msec(), "car_id":car.get_instance_id(), "expected_callback_msec":callback_deadline, "hinge_angle":hinge.rotation.y if is_instance_valid(hinge) else null}))
		car.health = 0
		check(not await session.restore_garage_driver(car),place+" destroyed car cannot board")
		check(session.leave_place(),place+" physical exit")
		world.driving.car = original_car
		for vehicle in session.garage_rewards.cars.values():
			if is_instance_valid(vehicle):
				if place == "maciota" and vehicle == car:
					check(callback_deadline > Time.get_ticks_msec(),"Maciota car is removed before deferred callback, without masking lifetime race")
					removed_before_callback_id = vehicle.get_instance_id()
					removed_callback_deadline = callback_deadline
				print("GARAGE_EXIT_OBSERVATION ", JSON.stringify({"event":"queue_free_car", "place":place, "msec":Time.get_ticks_msec(), "car_id":vehicle.get_instance_id(), "expected_callback_msec":exit_observation.get("expected_callback_msec",0)}))
				vehicle.queue_free()
		session.garage_rewards.cars.clear()
		await settle()
	check(removed_before_callback_id != 0 and not is_instance_valid(instance_from_id(removed_before_callback_id)) and Time.get_ticks_msec() >= removed_callback_deadline,"removed Maciota vehicle stays gone after its callback deadline")
	world.queue_free()
	await settle(10)
	print("GARAGE_DRIVER_RESTORE ",checks," checks failures=",failures)
	quit(0 if failures.is_empty() else 1)
