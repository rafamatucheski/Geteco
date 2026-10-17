extends SceneTree
const FORGE_CENTER := Vector3(716,0,-363)
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
	# Ferreiro da Forja da Serra (no lugar do caixa do zoológico): removido não ressuscita
	# enquanto o jogador está perto, e volta um só depois que ele sai do raio e retorna.
	world.production._update_physical_residency(FORGE_CENTER)
	world.production._update_logical_region(FORGE_CENTER)
	world.player.teleport(FORGE_CENTER + Vector3(-1,.08,-1.5))
	var forge: Node
	var forge_deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < forge_deadline:
		forge = world.production.region.find_child("MountainForge", true, false)
		if is_instance_valid(forge) and forge.is_node_ready(): break
		await process_frame
	check(is_instance_valid(forge), "Real mountain forge loaded")
	if failures: await finish(world); return
	var smith = forge.smith
	for i in 240:
		await physics_frame
		if smith.available(): break
	check(smith.available(), "Real forge spawns the smith")
	if failures: await finish(world); return
	smith.actor.queue_free(); await frames(20)
	check(not smith.available() and smith.nearest_action().is_empty(), "Removed smith stays absent near the forge")
	world.player.teleport(FORGE_CENTER + Vector3(80,.08,0)); await frames(20)
	check(not smith._initialized, "Smith residency clears at distance")
	world.player.teleport(FORGE_CENTER + Vector3(-1,.08,-1.5))
	for i in 240:
		await physics_frame
		if smith.available(): break
	check(smith.available() and smith.find_children("Forge*", "CharacterBody3D", false, false).size() == 1, "One smith returns after leaving and coming back")
	await finish(world)
func finish(world: Node) -> void:
	world.free(); await process_frame
	print("SESSION_REMOVED_ACTORS_INTEGRATION ", checks, " checks ", failures, " failures")
	quit(1 if failures else 0)
