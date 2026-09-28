extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	world.player.teleport(Vector3(106,.1,72))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var ops = world.production.urban_transit.terminal_operations
	for frame in 120:
		await physics_frame
		if ops.resident: break
	check(ops.resident,"Terminal activates near the player")
	if failures: world.free(); quit(1); return
	var ids := []
	for coach in ops.fleet:
		ids.append(coach.get_instance_id())
		for person in coach.passengers: ids.append(person.actor.get_instance_id())
	world.player.teleport(Vector3(1000,.1,1000))
	for frame in 45: await physics_frame
	check(not ops.running and not ops.visible,"Distant terminal suspends presentation and operation")
	var dormant := true
	for coach in ops.fleet:
		dormant = dormant and coach.collision_layer==0
		for person in coach.passengers: dormant = dormant and person.actor.collision_layer==0 and person.actor.process_mode==Node.PROCESS_MODE_DISABLED
	for gate in ops.gates: dormant = dormant and gate.body.collision_layer==0
	check(dormant,"No distant vehicle, passenger or gate ghost collisions")
	world.player.teleport(Vector3(106,.1,72))
	for frame in 60: await physics_frame
	var restored := []
	for coach in ops.fleet:
		restored.append(coach.get_instance_id())
		for person in coach.passengers: restored.append(person.actor.get_instance_id())
	check(ops.running and restored==ids,"Returning resumes the same four coaches and sixteen people")
	var coach = ops.fleet[0]
	var saved_road = ops.road
	ops.road = null
	coach.state = "closing"; coach.timer = 0; coach.set_doors(0)
	ops.tick_coach(coach,.1)
	check(coach.state=="closing","Disconnected street graph keeps the coach safely at its platform")
	ops.road = saved_road
	world.free()
	await process_frame
	print("TERMINAL_LIFECYCLE ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
