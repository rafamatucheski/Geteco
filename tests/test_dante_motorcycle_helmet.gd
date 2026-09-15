extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var actor = load("res://Player.gd").new()
	# Contrato do capacete sobre o rig procedural (rosto e cabelo próprios). Com o
	# Dante Meshy, padrão desde 14/09, essas malhas ficam ocultas por design; o
	# encaixe do capacete sobre o cabelo do Meshy ainda não tem teste próprio.
	actor.use_meshy_dante = false
	var camera := Camera2D.new()
	camera.name = "Camera"
	actor.add_child(camera)
	world.add_child(actor)
	actor.set_physics_process(false)
	var state = actor.ensure_motorcycle_helmet()
	state.set_process(false)
	for id in ["bike_sport","bike_cruiser","bike_urban"]:
		var bike = preload("res://emergency/ModernTrafficFactory.gd").spawn_parked_vehicle(world,id,Vector2(100,100),0,id,0)
		bike.set_physics_process(false)
		bike.ensure_presentation()
		state.worn = false
		state.sync_visual()
		bike.enter_vehicle(actor)
		state.advance(4.0)
		check(not state.worn and state.stopped_seconds == 0,"Boarding time does not count")
		while bike.has_meta("vehicle_boarding"): await process_frame
		var model: Node3D = bike.body_model
		var dante: Node3D = model.dante_rider
		check(dante != null and dante.visible,"Actual Dante appears on "+id)
		check(dante.head_node.has_node("Face") and dante.head_node.has_node("ShortBeard"),"Canonical face and beard retained")
		check(dante.torso_node.has_node("OvershirtBody"),"Canonical wardrobe retained")
		check(dante.head_node.get_node("Face").mesh == actor.head_node.get_node("Face").mesh,"Same head geometry, not a generic rider")
		for part in model.rider.get_children():
			check(part == dante or not part.visible,"No overlapping NPC body")
		state.advance(2.9)
		check(not state.worn and state.action.is_empty(),"Bare head before three seconds")
		check(dante.head_node.get_node("Face").visible and not dante.head_node.get_node("MotorcycleHelmet").visible,"Only Dante's normal head before equipping")
		bike.velocity = Vector2(40,0)
		state.advance(1.0)
		bike.velocity = Vector2.ZERO
		state.advance(2.9)
		check(not state.worn and state.action.is_empty(),"Movement resets stationary delay")
		state.advance(.11)
		check(state.action == "put_on","Starts putting helmet on after three stationary seconds")
		state.advance(.76)
		check(state.worn and state.action.is_empty(),"Helmet equipped")
		if id == "bike_sport":
			actor.apply_outfit("dante_classic")
			state.sync_visual()
			check(dante.source_head_id == actor.head_node.get_instance_id(),"Mounted wardrobe rebuild updates actual Dante")
		for angle in [-.58,0.0,.58]:
			model.update_riding_pose(1.0,5.0,angle,true)
			check(dante.head_node.position.distance_to(dante.torso_node.transform*Vector3(0,.36,0)) < .001,"Head stays attached to neck")
			check(dante.head_node.get_node("MotorcycleHelmet").position == Vector3.ZERO,"Helmet stays attached to head")
			check(not dante.head_node.get_node("Face").visible,"Face/hair do not protrude through closed helmet")
		bike.exit_vehicle()
		while bike.has_meta("vehicle_boarding"): await process_frame
		actor.set_physics_process(false)
		check(state.worn and actor.head_node.get_node("MotorcycleHelmet").visible,"Helmet follows Dante off the bike")
		state.advance(9.9)
		check(state.worn and state.action.is_empty(),"Helmet retained for ten seconds")
		bike.enter_vehicle(actor)
		while bike.has_meta("vehicle_boarding"): await process_frame
		state.advance(12.0)
		check(state.worn and state.action.is_empty(),"Reboarding cancels pending removal")
		bike.exit_vehicle()
		while bike.has_meta("vehicle_boarding"): await process_frame
		actor.set_physics_process(false)
		state.advance(10.01)
		check(state.action == "take_off","Starts removal after ten seconds off the bike")
		if id == "bike_sport":
			state.advance(.3)
			bike.enter_vehicle(actor)
			while bike.has_meta("vehicle_boarding"): await process_frame
			check(state.worn and state.action.is_empty(),"Reboarding during removal restores helmet")
			bike.exit_vehicle()
			while bike.has_meta("vehicle_boarding"): await process_frame
			actor.set_physics_process(false)
			state.advance(10.01)
		state.advance(.8)
		check(not state.worn and actor.head_node.get_node("Face").visible,"Face restored after removal")
		check(not actor.head_node.get_node("MotorcycleHelmet").visible,"Helmet hidden after removal")
		var drops := get_nodes_in_group("dropped_motorcycle_helmets")
		check(drops.size() == 1, "Removal creates exactly one world helmet")
		if not drops.is_empty():
			var drop = drops[0]
			drop.set_process(false)
			var ground_position: Vector2 = drop.global_position
			actor.position += Vector2(20, 0)
			check(drop.global_position == ground_position, "Discard stays independent of player movement")
			drop.advance(drop.FLIGHT_SECONDS + 9.9)
			check(drop.modulate.a == 1.0, "Discard stays fully visible for ten seconds on ground")
			drop.advance(.85)
			check(drop.modulate.a > .1 and drop.modulate.a < .9, "Discard fades gradually")
			drop.advance(.8)
			check(drop.is_queued_for_deletion(), "Discard is cleaned up after fading")
			await process_frame
		# Exiting before the idle delay must not equip a helmet later on foot.
		bike.enter_vehicle(actor)
		while bike.has_meta("vehicle_boarding"): await process_frame
		state.advance(1.0)
		bike.exit_vehicle()
		while bike.has_meta("vehicle_boarding"): await process_frame
		actor.set_physics_process(false)
		state.advance(15.0)
		check(not state.worn and state.action.is_empty(),"Early exit cancels pending equipment")
		bike.queue_free()
		await process_frame
	# Costume rebuild while wearing must bind the new head, preserving its shape.
	state.worn = true
	actor.apply_outfit("dante_classic")
	check(actor.head_node.get_node("MotorcycleHelmet").visible and not actor.head_node.get_node("Face").visible,"Wardrobe rebuild preserves helmet")
	state.worn = false
	state.sync_visual()
	check(actor.head_node.get_node("Face").visible,"Wardrobe rebuild restores face")
	# The actor's physics is disabled while riding; its helmet process must still
	# tick, but pause menus must freeze the ten-second countdown.
	state.worn = true
	state.dismount()
	state.set_process(true)
	await create_timer(.15).timeout
	check(state.off_bike_seconds > .05,"Timer runs while player physics is disabled")
	paused = true
	var paused_elapsed: float = state.off_bike_seconds
	await create_timer(.15,true).timeout
	check(state.off_bike_seconds == paused_elapsed,"Pause freezes helmet timers")
	paused = false
	state.set_process(false)
	world.queue_free()
	await process_frame
	print("DANTE MOTORCYCLE HELMET failures=",failures)
	quit(1 if failures else 0)
