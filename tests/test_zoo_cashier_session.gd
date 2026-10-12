extends SceneTree
const ZOO_CENTER := Vector3(716,0,-363)
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(150.0, true, false, true).timeout.connect(func():
		push_error("Session removed actors integration exceeded 150 seconds")
		print("ZOO_CASHIER_SESSION ", checks, " checks ", failures, " failures; TIMEOUT")
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
	world.session.state.economy.grant_outfit("dante_ski")
	world.session.state.economy.equip_outfit("dante_ski")
	world.session.apply_outfit()
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
	var clerk = admission.cashier
	check(admission._cashier_available(), "Actual session cashier is alive")
	await frames(30)
	check(clerk.is_on_floor() and absf(clerk.position.y)<.2, "Cashier settles on real ground")
	world.player.teleport(ZOO_CENTER + Vector3(-3.2,.08,24.7))
	check(not admission.nearest_action().is_empty(), "Real player can buy at counter")
	world.gameplay._damage(clerk,200.0,null)
	check(clerk.dead and admission.nearest_action().is_empty(), "Real combat disables ticket sales")
	await frames(30)
	check(admission.cashier == clerk, "No immediate respawn beside player")
	var collected := false
	for key in world.gameplay.emergency.incidents.keys():
		if world.gameplay.emergency.incidents[key].actor == clerk:
			world.gameplay.emergency.complete(key); collected = true
	check(collected, "Actual emergency service receives cashier death")
	await frames(3)
	check(not admission._cashier_available(), "Collected cashier remains absent nearby")
	world.player.teleport(ZOO_CENTER + Vector3(70,.08,0)); await frames(5)
	check(not admission._initialized, "Departure clears booth residency")
	world.player.teleport(ZOO_CENTER + Vector3(-3.2,.08,24.7))
	for i in 240:
		await physics_frame
		if admission._cashier_available(): break
	check(admission._cashier_available(), "Return spawns living cashier")
	var count := 0
	for child in admission.get_children():
		if child is CharacterBody3D and child.identity == 624: count += 1
	check(count == 1, "Exactly one cashier after returning")
	check(not admission.nearest_action().is_empty(), "Sales resume on return")
	await finish(world)
func finish(world: Node) -> void:
	world.free(); await process_frame
	print("ZOO_CASHIER_SESSION ", checks, " checks ", failures, " failures")
	quit(1 if failures else 0)
