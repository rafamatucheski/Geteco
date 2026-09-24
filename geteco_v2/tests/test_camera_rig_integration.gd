extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool,message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	root.add_child(world)
	for frame in 1200:
		await physics_frame
		if world.production != null and world.production.ready_for_play: break
	check(world.production != null and world.production.ready_for_play,"Productive world starts")
	check(world.production.no_save,"Camera integration fixture cannot touch the player's save")
	if not failures.is_empty(): quit(1); return
	await frames(3)
	var walking_height: float = world.camera.unproject_position(world.player.position+Vector3.UP*1.8).distance_to(world.camera.unproject_position(world.player.position))
	# Escala V1 medida (~34.3 px) ampliada pelo zoom de enquadramento do rig.
	var zoom_scale: float = world.camera.FRAMING_ZOOM_SCALE
	check(walking_height>32/zoom_scale and walking_height<37/zoom_scale,"Walking apparent human scale matches the measured V1 rig times the framing zoom")
	check(absf(world.camera.target_size-world.camera.WALK_SIZE_CLOSE)<.02,"Productive walking mode uses automatic V1 framing")

	var car = world.driving.car
	world.player.teleport(car.to_global(Vector3(-(car.half_width+.61),.04,.15)))
	await frames(2)
	check(world.driving.interact(),"Board the productive vehicle")
	await frames(60)
	check(world.camera.target==car and world.camera.target_size>=world.camera.WALK_SIZE_CLOSE-.01,"Driving switches target without tightening the adapted walking frame")
	car.speed=0
	car.velocity=Vector3.ZERO
	check(world.driving.leave(),"Leave the productive vehicle")
	for frame in 180:
		await physics_frame
		if not world.driving.is_body_transition_active(): break
	check(not world.driving.is_body_transition_active(),"Vehicle exit body transition completes before travel admission")
	await frames(90)
	check(world.camera.target==world.player and absf(world.camera.target_size-world.camera.WALK_SIZE_CLOSE)<.05,"Walking framing returns after vehicle handoff")

	check(world.production.travel("mountain"),"Mountain travel admitted")
	for frame in 600:
		await physics_frame
		if not world.production.travel_busy and world.production.ready_for_play: break
	check(world.session.state.region_id=="mountain","Mountain region active")
	check(await world.session.enter_place("ski_lodge",false),"Enter the real ski lodge")
	var room = world.session.room
	var entry_error: float = world.camera.focus.distance_to(room.camera_target)
	check(entry_error<.001,"Lodge camera lands on its real anchor in the entry frame")
	check(world.camera.locked and world.camera.target==world.session.anchor,"Lodge owns the fixed interior camera")
	check(absf(world.camera.size-room.camera_size)<.001,"Lodge authored size is applied without exterior interpolation")
	await frames(2)
	check(world.camera.focus.distance_to(room.camera_target)<.001,"Lodge framing stays stable after physics interpolation advances")
	var player_screen: Vector2 = world.camera.unproject_position(world.player.position)
	var visible_rect: Rect2 = world.camera.get_viewport().get_visible_rect()
	check(visible_rect.has_point(player_screen),"Lodge entry spawn is visible in the productive frame: "+str(player_screen)+" / "+str(visible_rect))
	check(world.session.leave_place(),"Leave the real ski lodge")
	await frames(2)
	check(not world.camera.locked and world.camera.target==world.player,"Exterior camera restored after lodge exit")

	for failure in failures: push_error(failure)
	print("CAMERA_RIG_INTEGRATION ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size()," walking_px=",walking_height," lodge_entry_error=",entry_error," lodge_player_screen=",player_screen)
	world.queue_free()
	for frame in 8: await process_frame
	quit(0 if failures.is_empty() else 1)
