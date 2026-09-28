extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	var depot = world.session.urban_operations.cargo_handling.depot
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = 9.0/24
	world.player.teleport(depot.ORIGIN+Vector3(0,.1,82))
	world.production.region.set_focus(world.player.position)
	for i in 150: await physics_frame
	check(depot.business_open() and depot.gate_amount>.99,"Open during 08–18 and gate physically slides aside")
	for state in world.session.urban_operations.cargo_handling.work_trucks: check(is_instance_valid(state.truck),"Fleet starts at the port even when the player visits the remote company first")
	world.player.teleport(depot.ORIGIN+Vector3(0,1.2,18.2))
	world.session.weather.time_of_day = 19.0/24
	for i in 90: await physics_frame
	check(depot.dock_amounts[1]>.99,"Dock shutter cannot close on an actor in its opening")
	world.session.weather.time_of_day = 19.0/24
	world.player.teleport(depot.ORIGIN+Vector3(0,.1,89))
	for i in 150: await physics_frame
	check(not depot.business_open() and depot.gate_amount<.01,"Closes at night")
	world.player.teleport(depot.ORIGIN+Vector3(0,.1,81))
	for i in 45: await physics_frame
	check(depot.gate_amount<.01,"Approaching a closed gate at night does not authorize entry")
	world.player.teleport(depot.ORIGIN+Vector3(0,.1,70))
	for i in 150: await physics_frame
	check(depot.gate_amount>.99,"Visitors inside retain safe exit after hours")
	world.session.weather.time_of_day = 9.0/24
	world.player.teleport(depot.ORIGIN+Vector3(35,.1,32))
	for i in 90: await physics_frame
	check(depot.office_amount>.99,"Office opens by proximity during business hours")
	world.player.teleport(depot.ORIGIN+Vector3(35,.1,27))
	for i in 15: await physics_frame
	check(depot.occupied and depot.interior_camera.current,"Continuous interior activates cutaway and camera")
	world.session.weather.weather_state = 1
	world.session.weather._update()
	check(not world.session.weather.precipitation.visible,"Continuous warehouse shelters the player from rain")
	for x in [27.7,27.9,28.0,28.2]: check(depot.inside(depot.ORIGIN+Vector3(x,0,8)),"Warehouse/office passage keeps one continuous camera")
	world.session.weather.time_of_day = 19.0/24
	world.player.teleport(depot.ORIGIN+Vector3(35,.1,29.5))
	for i in 60: await physics_frame
	world.player.teleport(depot.ORIGIN+Vector3(35,.1,30.5))
	for i in 45: await physics_frame
	check(depot.office_amount>.99,"Office threshold stays clear while leaving after closing")
	world.player.teleport(depot.ORIGIN+Vector3(35,.1,34))
	for i in 60: await physics_frame
	check(depot.office_amount<.01,"Office closes once the threshold is clear")
	world.session.weather.time_of_day = 9.0/24
	var npc = depot.staff[0].actor
	for entry in depot.staff: check(entry.actor.global_position.y>-.1 and entry.actor.global_position.y<.4,"Resident starts and remains on native ground")
	world.player.teleport(npc.global_position+Vector3(1,0,0))
	check(depot.nearest_action().get("target","")=="vertice_staff","Physical guard offers functional conversation")
	check(depot.perform("vertice_staff"),"Guard explains opening hours")
	for secret in depot.secrets:
		world.player.teleport(depot.ORIGIN+secret.point)
		for i in 30: await physics_frame
		var receipt: Dictionary = world.session.state.economy.snapshot().transactions.get("reward:"+secret.id,{})
		check(not receipt.is_empty() and not secret.visual.visible,"Secret grants durable reward "+secret.id)
		var before: Dictionary = world.session.state.economy.snapshot()
		for i in 30: await physics_frame
		check(before==world.session.state.economy.snapshot(),"Secret cannot be collected twice "+secret.id)
	world.player.teleport(depot.ORIGIN+Vector3(35,.1,34))
	for i in 10: await physics_frame
	check(not depot.occupied and world.camera.current,"Exit restores world camera")
	check(not world.player.get_meta("mountain_shelter",false),"Exit releases the weather shelter flag")
	var restored = preload("res://runtime/GameState.gd").new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(world.session.state.snapshot()))),"Company rewards preserve valid full save format")
	for secret in depot.secrets:
		check(restored.economy.snapshot().transactions.has("reward:"+secret.id),"Secret receipt survives full save restore "+secret.id)
	print("VERTICE_COMPANY failures=",failures)
	quit(0 if failures.is_empty() else 1)
