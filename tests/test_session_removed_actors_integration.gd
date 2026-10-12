extends SceneTree
const ZOO_CENTER := Vector3(716,0,-363)
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(150.0, true, false, true).timeout.connect(func():
		push_error("Session removed actors integration exceeded 150 seconds")
		print("SESSION_REMOVED_ACTORS_INTEGRATION ", checks, " checks ", failures, " failures; TIMEOUT")
		quit(2)
	)
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true); root.add_child(world)
	for i in 3000:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main session starts")
	if failures: await finish(world); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(Vector3(106,.15,72))
	var ops = world.production.urban_transit.terminal_operations
	for i in 180:
		await physics_frame
		if ops.resident: break
	check(ops.resident and ops.fleet.size() == 4, "Real terminal activates")
	if failures: await finish(world); return
	var coach = ops.fleet[0]
	var survivor = coach.passengers[3].actor
	var victim: Dictionary = coach.passengers[2]
	victim.actor.queue_free()
	await frames(3)
	check(victim.actor == null, "Real tick retires removed passenger")
	world.player.teleport(Vector3(250,.15,250)); await frames(45)
	check(not ops.running, "Damaged terminal suspends at distance")
	world.player.teleport(Vector3(106,.15,72)); await frames(45)
	check(ops.running and coach.passengers[3].actor == survivor, "Returning preserves surviving passenger identity")
	check(victim.actor == null and not victim.inside, "Removed passenger stays absent after resume")
	var urban = world.session.urban_operations
	var cemetery = urban.cemetery
	world.player.teleport(cemetery.CENTER + Vector3.UP*.05)
	world.production.region.set_focus(cemetery.CENTER)
	urban.refresh_context(); await frames(5)
	check(is_instance_valid(cemetery.keeper), "Real cemetery keeper activates")
	if failures: await finish(world); return
	var keeper = cemetery.keeper
	world.gameplay._damage(keeper, 200.0, null)
	check(keeper.dead and cemetery.deaths.has("keeper"), "Keeper death is recorded by real combat")
	var emergency = world.gameplay.emergency
	var collected := false
	for key in emergency.incidents.keys():
		if emergency.incidents[key].actor == keeper:
			emergency.complete(key); collected = true
	check(collected, "Emergency service collects the registered corpse")
	await frames(3)
	check(not is_instance_valid(cemetery.keeper), "Collected corpse is removed from real world")
	check(cemetery.nearest_action().is_empty(), "Removed keeper cannot offer interaction")
	world.player.teleport(Vector3.ZERO); urban.refresh_context()
	world.player.teleport(cemetery.CENTER + Vector3.UP*.05); urban.refresh_context()
	await frames(3)
	check(not is_instance_valid(cemetery.keeper) and cemetery.deaths.has("keeper"), "Cemetery return preserves death without resurrecting keeper")
	world.production._update_physical_residency(ZOO_CENTER)
	world.production._update_logical_region(ZOO_CENTER)
	world.player.teleport(ZOO_CENTER + Vector3(-5,.08,24))
	var zoo: Node
	var zoo_deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < zoo_deadline:
		zoo = world.production.region.find_child("MountainZoo", true, false)
		if is_instance_valid(zoo) and zoo.is_node_ready(): break
		await process_frame
	check(is_instance_valid(zoo), "Real mountain zoo loaded")
	if failures: await finish(world); return
	var admission = zoo.admission
	for i in 240:
		await physics_frame
		if not admission.visitors.is_empty(): break
	check(not admission.visitors.is_empty(), "Real admission spawns visitors")
	if failures: await finish(world); return
	var visitor: Dictionary = admission.visitors[0]
	visitor.actor.queue_free(); await frames(3)
	check(visitor.actor == null and visitor.phase == "done", "Real zoo tick retires removed visitor")
	world.player.teleport(ZOO_CENTER + Vector3(70,.08,0)); await frames(5)
	check(admission.visitors.is_empty(), "Real admission clears residents at distance")
	world.player.teleport(ZOO_CENTER + Vector3(-5,.08,24))
	for i in 240:
		await physics_frame
		if not admission.visitors.is_empty(): break
	check(admission._initialized and not admission.visitors.is_empty(), "Admission recovers after return")
	await finish(world)
func finish(world: Node) -> void:
	world.free(); await process_frame
	print("SESSION_REMOVED_ACTORS_INTEGRATION ", checks, " checks ", failures, " failures")
	quit(1 if failures else 0)
