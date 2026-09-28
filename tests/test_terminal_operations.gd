extends SceneTree
var checks := 0
var failures := 0
var world
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(26092026)
	Engine.set_meta("geteco_world_edit_document",preload("res://world/editing/WorldEditData.gd").empty_document())
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"Main starts")
	if failures: quit(1); return
	world.player.teleport(Vector3(106,.15,72))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var ops = world.production.urban_transit.terminal_operations
	for frame in 180:
		await physics_frame
		if ops.resident: break
	check(ops.fleet.size()==4,"Four conserved coach services")
	check(ops.gates.size()==2,"Entrance and exit gates")
	if failures: quit(1); return
	var identities := []
	for coach in ops.fleet:
		for person in coach.passengers: identities.append(person.actor.get_instance_id())
	check(identities.size()==16,"Sixteen conserved passengers")
	Engine.time_scale = 4
	Engine.physics_ticks_per_second = 240
	var began := Time.get_ticks_msec()
	var simulated := 0.0
	var stuck := 0.0
	while simulated < 300 and Time.get_ticks_msec()-began < 150000:
		await physics_frame
		simulated += Engine.time_scale/Engine.physics_ticks_per_second
		stuck = stuck+Engine.time_scale/Engine.physics_ticks_per_second if ops.fleet[0].blocked else 0.0
		if stuck > 8 and "--diagnostic" in OS.get_cmdline_user_args(): break
		var trips := 0
		for coach in ops.fleet: trips += coach.trips
		if trips >= 1: break
	var trips := 0
	var boarded := 0
	var alighted := 0
	for coach in ops.fleet:
		trips += coach.trips; boarded += coach.boarded; alighted += coach.alighted
		print("TERMINAL_COACH ",coach.platform," ",coach.state," at=",coach.position," progress=",coach.progress," blocked=",coach.blocked," by=",coach.blocked_by," trips=",coach.trips)
		for p in coach.passengers: check(p.actor.get_instance_id() in identities,"Passenger identity conserved")
	check(boarded>=2 and alighted>=2,"Physical passenger exchange")
	check(trips>=1,"Coach reverses, departs, travels and returns to platform")
	for gate in ops.gates:
		print("TERMINAL_GATE ",gate.state," requests=",gate.requests," passages=",gate.passages)
		check(gate.authorizations>=1 and gate.passages>=1,"Gate authorizes full hull passage")
	if trips >= 1:
		var returned = ops.fleet[0]
		returned.timer = 0
		var again := 0.0
		while again < 35 and (returned.boarded<4 or returned.alighted<4):
			await physics_frame
			again += Engine.time_scale/Engine.physics_ticks_per_second
		check(returned.boarded>=4 and returned.alighted>=4,"Waiting passengers resume walking for the next exchange without replacements")
	if DisplayServer.get_name() != "headless":
		world.camera.target_size = 48
		world.camera.heading = 0
		for frame in 15: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/terminal-20260926/operation.png")
	print("TERMINAL_OPERATIONS ",checks," checks ",failures," failures")
	world.free()
	await process_frame
	quit(1 if failures else 0)
