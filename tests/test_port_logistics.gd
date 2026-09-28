extends SceneTree
var world
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(480,true,false,true).timeout.connect(func(): push_error("LOGISTICS TIMEOUT"); quit(3))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(2); return
	var cargo = world.session.urban_operations.cargo_handling
	world.session.weather.time_of_day = .4
	world.session.weather.set_process(false)
	world.player.controlled_automatically = true
	world.player.set_physics_process(false)
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.session.urban_operations.security.authorized_visit = true
	world.player.teleport(Vector3(298,.1,219))
	world.production.region.set_focus(world.player.position)
	for i in 600:
		await physics_frame
		if is_instance_valid(cargo.work_trucks[0].truck): break
	check(is_instance_valid(cargo.work_trucks[0].truck),"Truck spawns physically in port")
	if not is_instance_valid(cargo.work_trucks[0].truck): quit(1); return
	for index in 3:
		var plan = cargo.HAUL.journey(world.production.traffic_routes,cargo.work_trucks[index].stop,index,false)
		check(plan != null,"Directed outbound route exists %d"%index)
		if plan != null: print("HAUL_PLAN ",index," length=",plan.get_baked_length()," end=",plan.get_point_position(plan.point_count-1))
		check(cargo.HAUL.journey(world.production.traffic_routes,cargo.HAUL.dock(index),index,true) != null,"Directed return route exists %d"%index)
	var state: Dictionary = cargo.work_trucks[0]
	var first_id: int = state.truck.get_instance_id()
	if "--cooldown-only" in OS.get_cmdline_user_args():
		# Clear the spawn bay by driving to the crane before leaving a wreck.
		for i in 3600:
			await physics_frame
			if state.phase in ["loading", "securing"]: break
		check(state.phase in ["loading", "securing"],"Truck clears its spawn bay before destruction")
		await validate_cooldown(cargo,state,first_id)
		return
	var saw_loaded := false
	var saw_unload := false
	var saw_return := false
	Engine.time_scale = 4
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 64
	Engine.max_fps = 0
	var stalled_since := Time.get_ticks_msec()
	var last_progress: Vector3 = state.truck.global_position
	for i in 90000:
		await physics_frame
		var truck = state.truck
		if not is_instance_valid(truck): break
		if i%30==0:
			world.player.teleport(truck.global_position+Vector3(0,.1,9))
			world.production.region.set_focus(world.player.position)
			for entry in cargo.work_trucks:
				if is_instance_valid(entry.truck) and entry.truck.global_position.y < -.25 and not entry.has("fall_reported"):
					entry.fall_reported = true
					print("GROUND_FAILURE ",entry.bay," p=",entry.truck.global_position," velocity=",entry.truck.velocity," collision=",entry.truck.collision_mask," shape=",entry.truck.shape.position," disabled=",entry.truck.shape.disabled," ready=",entry.ground_ready," processing=",entry.truck.is_physics_processing())
		saw_loaded = saw_loaded or state.loaded
		saw_unload = saw_unload or state.phase == "delivering"
		saw_return = saw_return or state.phase == "returning"
		if i%1800==0: print("HAUL_PROGRESS ",i," ",state.phase," p=",truck.global_position," speed=",truck.speed," blocked=",truck.blocker," health=",truck.health," deliveries=",state.deliveries)
		if truck.global_position.distance_to(last_progress) > 1 or state.phase not in ["departed","returning"]:
			stalled_since = Time.get_ticks_msec()
			last_progress = truck.global_position
		# Traffic lights use real wall time, even when physics is accelerated.
		# Allow a complete signal cycle before diagnosing a blocked convoy.
		if Time.get_ticks_msec()-stalled_since > 60000:
			for item in cargo.work_trucks:
				var other = item.truck
				if not is_instance_valid(other): continue
				print("FLEET_DIAG ",item.bay," ",item.phase," p=",other.global_position," speed=",other.speed," blocked=",other.blocker," route_d=",other.route_distance," yaw=",other.rotation.y)
				if is_instance_valid(other.blocker) and other.blocker is Node: print("FLEET_BLOCKER ",other.blocker.get_path())
				if is_instance_valid(other.blocker) and other.blocker is CharacterBody3D: print("FLEET_BLOCKER_STATE id=",other.blocker.get("vehicle_id")," p=",other.blocker.global_position," traffic=",other.blocker.get("traffic")," ambient=",other.blocker.get_meta("ambient_traffic",false))
				for hit_index in other.get_slide_collision_count():
					var contact = other.get_slide_collision(hit_index)
					print("FLEET_CONTACT ",contact.get_collider().get_path()," p=",contact.get_position()," normal=",contact.get_normal())
				if other.route != null:
					print("FLEET_PATH ",other.route.sample_baked(other.route_distance)," -> ",other.route.sample_baked(other.route_distance+5)," -> ",other.route.sample_baked(other.route_distance+15))
			print("HAUL_STALL path=",truck.blocker.get_path() if is_instance_valid(truck.blocker) and truck.blocker is Node else "none")
			if is_instance_valid(truck.blocker) and truck.blocker is CharacterBody3D:
				print("BLOCKER ",truck.blocker.get("vehicle_id")," ",truck.blocker.get("archetype")," p=",truck.blocker.global_position," traffic=",truck.blocker.get("traffic")," health=",truck.blocker.get("health"))
			break
		if state.deliveries >= 1 and state.loaded and state.phase == "securing": break
	check(saw_loaded,"Crane transfers a container to the physical truck")
	check(saw_unload,"Truck physically reaches the remote dock")
	check(saw_return,"Unloaded truck starts the return route")
	check(state.deliveries >= 1 and state.loaded and state.phase == "securing","Same truck returns and loads another container")
	check(is_instance_valid(state.truck) and state.truck.get_instance_id()==first_id,"Round trip conserves the same truck")
	await validate_cooldown(cargo,state,first_id)

func validate_cooldown(cargo,state: Dictionary,first_id: int) -> void:
	Engine.time_scale = 1
	cargo.set_physics_process(false)
	var truck = state.truck
	truck.receive_damage(truck.max_health*10)
	var due: float = state.respawn_at
	check(state.phase == "destroyed" and due >= cargo.game_seconds()+599.9,"Destruction schedules replacement after 24 game hours")
	var saved: Dictionary = cargo.snapshot()
	check(cargo.validate_snapshot(saved),"Replacement state serializes")
	var bad: Dictionary = saved.duplicate(true)
	bad.trucks[0].respawn_at = NAN
	check(not cargo.validate_snapshot(bad),"Invalid replacement deadline rejected")
	check(cargo.restore_snapshot(JSON.parse_string(JSON.stringify(saved))),"Replacement deadline survives save round trip")
	world.session.weather.time_of_day = fposmod(world.session.weather.time_of_day+599.0/600.0,1.0)
	cargo._tick_replacements()
	check(is_equal_approx(state.respawn_at,due) and state.phase == "destroyed","No early replacement before 24 hours")
	world.session.weather.time_of_day = fposmod(world.session.weather.time_of_day+1.01/600.0,1.0)
	cargo._tick_replacements()
	check(state.respawn_at < 0 and state.phase == "approach" and state.truck == null,"Exactly one replacement slot opens after 24 hours")
	check(is_instance_valid(cargo.cranes[0].visual),"Shared crane cargo survives truck destruction")
	world.player.teleport(Vector3(298,.1,219))
	world.production.region.set_focus(world.player.position)
	for i in 300:
		await physics_frame
		if i%30==0: cargo._spawn_work_truck(0)
		if is_instance_valid(state.truck): break
	check(is_instance_valid(state.truck) and state.truck.get_instance_id()!=first_id,"Replacement is a new physical truck at the port")
	if is_instance_valid(state.truck):
		check(state.truck.health == state.truck.max_health and not state.loaded,"Replacement has full health and an empty bed")
		var replacement_id: int = state.truck.get_instance_id()
		cargo._tick_replacements()
		check(state.truck.get_instance_id()==replacement_id,"Expired deadline cannot spawn a second replacement")
	print("PORT_LOGISTICS checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
