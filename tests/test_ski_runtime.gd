extends SceneTree
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
var world
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	print("SKI_CHECK ", "PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func place(point: Vector3) -> void:
	world.player.set_physics_process(false)
	world.production.region.set_focus(point)
	world.player.teleport(point+Vector3.UP*.1)
	for i in 20: await physics_frame
	world.player.set_physics_process(true)
	for i in 5: await physics_frame
func press_service(prefix: String) -> bool:
	for child in world.session.column.get_children():
		if child is Button and child.text.begins_with(prefix):
			child.pressed.emit()
			return true
	return false
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: check(false,"session ready"); quit(1); return
	check(world.production.travel("mountain"),"mountain travel")
	for i in 600:
		await physics_frame
		if not world.production.travel_busy: break
	var session = world.session
	var ski = session.mountain_progression
	session.weather.time_of_day = .5
	check(await session.enter_place("ski_lodge",false),"enter rental lodge")
	world.player.teleport(session.room.interaction_points.service)
	session.state.economy.grant_reward("ski_test_funds",2000)
	var balance: int = session.state.economy.balance
	ski.show_services()
	check(press_service("Alugar roupa"),"rental offered through real service")
	check(ski.data.rental and ski.data.equipment and session.state.economy.balance == balance-250,"rental debits 250 and supplies full equipment")
	check(await session.leave_place(),"leave lodge with rental")
	session.state.economy.grant_weapon("pistol")
	for clue in ski.CLUES: session.state.economy.collect(clue)
	for id in ski.COURSES:
		ski.cancel_attempt()
		await place(DEFINITIONS.at(ski.COURSES[id].start,"mountain"))
		ski._equip()
		ski._stop()
		ski._equip()
		check(ski.equipment_visual.visible,"equipment visible on re-equip")
		check(ski.nearest_action().get("target") == "ski_start:"+id,"start available with skis on: "+id)
		check(ski.perform("ski_start:"+id),"start accepted: "+id)
		var before_reward: int = session.state.economy.balance
		check(not session.state.equip_weapon("pistol"),"weapons blocked while skiing")
		var starting: Vector3 = world.player.position
		for i in 90: await physics_frame
		check(world.player.position.distance_to(starting)<.4,"countdown holds player")
		for i in 7200:
			if ski.race.mode == "": break
			var direction: Vector3 = ski.race.target_position()-ski._flat(world.player.position)
			var angle: float = ski.heading.signed_angle_to(direction.normalized(),Vector3.UP)
			var speed_limit := 4.5 if absf(angle)>.55 else 9.0
			root.get_node("GameInput").touch_move = Vector2(clampf(-angle*2,-1,1),1 if ski.glide.length()>speed_limit else 0)
			await physics_frame
		root.get_node("GameInput").touch_move = Vector2.ZERO
		check(ski.race.finished and ski.data.best.has(id),"physical downhill completes and records: "+id)
		check(session.state.economy.balance >= before_reward+int(ski.COURSES[id].reward)+int(ski.COURSES[id].bonus),"finish pays reward and first record bonus")
		if not ski.race.finished: print("SKI_DIAGNOSTIC ",world.player.position," gate=",ski.race.gate," health=",world.gameplay.health)
		check(ski.validate_snapshot(ski.snapshot()),"save validates")
		ski._stop()
		if world.gameplay.health <= 0: break
	# Lift service: closed hours, boarding, skip and safe physical landing.
	await place(DEFINITIONS.at(Vector2(7100,-4890),"mountain")+Vector3(0,0,4))
	session.weather.time_of_day = .9
	check(ski.lift.board() and not ski.lift.riding,"closed lift refuses travel")
	session.weather.time_of_day = .5
	check(ski.perform("ski_lift"),"lift interaction accepted")
	check(ski.lift.riding and session.is_transition_blocked(),"lift locks transitions")
	ski.lift.skip()
	for i in 240:
		await physics_frame
		if not ski.lift.riding: break
	check(not ski.lift.riding and not session.is_transition_blocked(),"lift releases transition")
	check(ski._flat(world.player.position).distance_to(DEFINITIONS.at(Vector2(6880,-3015),"mountain")) < 8,"lift arrives at summit")
	check(session.position_clear(world.player.position+Vector3.UP*.04),"summit landing has floor and free capsule")
	check(world.player.is_physics_processing() and not world.player.input_locked,"walking restored")
	await place(DEFINITIONS.at(Vector2(7100,-4890),"mountain")+Vector3(0,0,4))
	var before_lift: Vector3 = world.player.position
	check(ski.lift.board(),"second lift trip accepted")
	for i in 15: await physics_frame
	ski.cancel_attempt()
	check(world.player.position.distance_to(before_lift)<.3 and not ski.lift.riding and not session.is_transition_blocked(),"cancel returns to base and releases lock")
	check(ski.lift.board(),"lift restart after cancel")
	for i in 5: await physics_frame
	var external := DEFINITIONS.at(Vector2(6900,-3060),"mountain")
	world.player.teleport(external)
	await physics_frame
	await physics_frame
	check(not ski.lift.riding and world.player.position.distance_to(external)<.5,"external teleport never overwritten by lift")
	var saved: Dictionary = ski.snapshot()
	ski._equip()
	check(ski.restore_snapshot(saved) and not ski.skiing and ski.race.mode == "","restore cancels transient motion")
	for failure in failures: push_error(failure)
	print("SKI_RUNTIME ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
