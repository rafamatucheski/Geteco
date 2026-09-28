extends SceneTree
const PLACE := preload("res://gameplay/urban_v1/VerticeUndercroftPlace.gd")
var world
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("HIDEOUT ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func boot(saved: Dictionary = {}) -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	if not saved.is_empty(): check(world.production.state.restore_snapshot(saved),"Full saved game admits the hidden room")
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.state.world_state.time = .4
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
func walk(point: Vector3) -> bool:
	for i in 600:
		var delta: Vector3 = point-world.player.global_position
		delta.y = 0
		if delta.length()<.18:
			world.player.automatic_direction = Vector3.ZERO
			await frames(5)
			return true
		world.player.automatic_direction = delta.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return false
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180,true,false,true).timeout.connect(func(): push_error("HIDEOUT TIMEOUT"); quit(3))
	await boot()
	var session = world.session
	var company = session.urban_operations.cargo_handling.depot
	var start: Vector3 = company.ORIGIN+Vector3(-24,.1,-8)
	world.production.region.set_focus(start)
	for i in 120:
		await physics_frame
		if world.production.region.prepare_collision_at(start): break
	world.player.teleport(start)
	await frames(30)
	check(not world.production.region.entries.any(func(e): return e.place_id=="vertice_undercroft"),"Secret access is not advertised on the world map")
	check(company.nearest_action().get("target","")!="vertice_hatch","Hatch cannot activate remotely")
	check(await walk(PLACE.HATCH+Vector3(0,0,1)),"Player physically walks the narrow aisle behind the racks")
	print("HATCH_DIAG player=",world.player.global_position," hatch=",company.ORIGIN+company.HATCH_POINT," locked=",world.player.input_locked," transition=",session.is_transition_blocked()," action=",session.nearest())
	check(world.player.is_on_floor() and company.occupied,"Hatch approach has real floor and warehouse camera")
	check(session.nearest().get("target","")=="vertice_hatch","Physical hatch offers the existing interaction action")
	check(company.hatch_marker.visible,"Hatch uses the shared compact door marker")
	check(session.interact(),"Normal interaction enters the hideout")
	for i in 120:
		await physics_frame
		if session.state.place_id=="vertice_undercroft" and not session.is_transition_blocked(): break
	await frames(15)
	check(session.state.place_id=="vertice_undercroft" and is_instance_valid(session.room),"Standard place transition completes")
	if session.state.place_id!="vertice_undercroft": finish(); return
	check(world.camera.current and world.player.camera==world.camera and not world.player.input_locked,"Room restores camera and player control")
	check(world.player.is_on_floor() and session.position_clear(world.player.position+Vector3.UP*.04),"Arrival admits the whole player on the basement floor")
	check(session.room.reward_points.size()==2,"Weapon and a second cache occupy distinct free locations")
	var gun: Dictionary = session.room.reward_points[0]
	check(gun.visual.get_node_or_null("PickupRing")!=null,"Secret weapon has its pickup ring")
	var height: float = gun.visual.get_child(0).position.y
	await frames(20)
	check(not is_equal_approx(height,gun.visual.get_child(0).position.y),"Secret weapon floats while the room is active")
	check(await walk(gun.position+Vector3(0,0,1.1)),"Weapon approach remains physically walkable")
	world.player.teleport(gun.position+Vector3.UP*.04)
	var health: float = world.gameplay.health
	world.gameplay.health = 0
	session._collect_reward(session.room)
	check(not session.state.owns_weapon("m4a1"),"Dead player cannot collect the weapon")
	world.gameplay.health = health
	await frames(20)
	check(session.state.owns_weapon("m4a1") and session.state.world_state.rewards.has("vertice_hidden_m4a1"),"Walking over the secret weapon grants it and its durable receipt")
	check(not gun.visual.visible,"Collected weapon and ring disappear together")
	check(await walk(session.room.to_global(Vector3(0,0,1))),"Central corridor remains clear")
	check(await walk(session.room.to_global(Vector3(3,0,1))),"Player reaches the cache beside the bed without walking over it")
	await frames(20)
	check(session.state.world_state.rewards.has("vertice_undercroft_cache"),"Secondary stash grants its own receipt")
	var economy: Dictionary = session.state.economy.snapshot()
	check(session.save_game(),"Hidden room and both rewards save through the normal session")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(session.state.snapshot()))
	world.queue_free()
	await frames(8)
	await boot(saved)
	session = world.session
	await frames(20)
	check(session.state.place_id=="vertice_undercroft" and is_instance_valid(session.room),"Fresh Main restores the hidden room")
	check(session.state.economy.snapshot()==economy,"Reload does not duplicate weapon, ammo or cash")
	check(session.room.reward_points.all(func(p): return not p.visual.visible),"Both collected secrets remain absent after reload")
	check(world.player.is_on_floor() and not world.player.input_locked,"Restored player is supported and controllable")
	check(await walk(session.room.exit_position),"Player physically reaches the exit ladder")
	check(session.nearest().get("id")=="exit","Ladder exposes the standard exit action")
	check(await session.leave_place(),"Existing transition returns to the same warehouse hatch")
	await frames(20)
	check(world.player.global_position.distance_to(PLACE.RETURN)<.3,"Return is in the clear aisle at the original hatch")
	company = session.urban_operations.cargo_handling.depot
	check(company.occupied and company.interior_camera.current and not world.player.input_locked,"Return restores warehouse camera and controls")
	check(company.perform("vertice_hatch"),"Hatch supports reentry")
	await frames(25)
	check(session.state.place_id=="vertice_undercroft" and session.room.reward_points.all(func(p): return not p.visual.visible),"Reentry cannot respawn collected secrets")
	finish()
func finish() -> void:
	print("HIDEOUT_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
