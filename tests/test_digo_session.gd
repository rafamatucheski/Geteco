extends SceneTree
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
const STORY := preload("res://systems/campaign/DigoProgress.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, title: String) -> void:
	checks += 1
	print("DIGO_SESSION ","PASS " if ok else "FAIL ",title)
	if not ok: failures.append(title)

func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("DIGO_SESSION: world did not become ready")
		quit(1)
		return
	var session = world.session
	session.state.intro.stage = "complete"
	world.player.teleport(COURSE.ENTRY+Vector3.UP*.1)
	world.production.region.set_focus(COURSE.ENTRY)
	for i in 240: await physics_frame
	var mx = session.motocross
	var instructor = get_first_node_in_group("digo_character")
	check(is_instance_valid(instructor),"Digo is present in the streamed production paddock")
	if is_instance_valid(instructor):
		var ray := PhysicsRayQueryParameters3D.create(instructor.global_position+Vector3(2,1,0),instructor.global_position+Vector3(0,1,0),3)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and hit.collider == instructor,"Digo's actual body blocks passage and bullets")
		var floor_ray := PhysicsRayQueryParameters3D.create(instructor.global_position+Vector3(0,.04,0),instructor.global_position-Vector3(0,.3,0),1)
		var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(floor_ray)
		check(not floor_hit.is_empty() and absf(float(floor_hit.position.y)-instructor.global_position.y)<.035,"Digo stands on the real paddock floor")
		world.player.set_physics_process(false)
		world.player.teleport(instructor.global_position+Vector3(1.5,.04,0))
		for i in 45:
			await physics_frame
			world.player.velocity = Vector3(-3,-1,0)
			world.player.move_and_slide()
		check(world.player.position.x > instructor.global_position.x+.4,"real player moving against Digo cannot cross his capsule")
		var start: Vector3 = world.player.position
		for i in 40:
			await physics_frame
			world.player.velocity = Vector3(0,-1,3)
			world.player.move_and_slide()
		check(world.player.position.z > start.z+1.2,"player can leave Digo through the open service corridor")
		world.player.teleport(COURSE.ENTRY+Vector3.UP*.1)
		world.player.set_physics_process(true)
	check(mx.nearest_action().get("label","") == "Conversar com Digo","real interaction identifies Digo")
	check(mx.perform("enter") and STORY.data(session.state.world_state).met,"conversation records meeting Digo")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/digo/conversation.png")
	session.close_menu()
	var balance: int = session.state.economy.balance
	check(mx.start_lesson(),"lesson starts through the production mounting path")
	check(mx.mounted and not mx.active and mx.lesson != null and not world.player.visible,"lesson gives control of a real bike")
	check(session.state.economy.balance == balance and mx.progress.data.rental_serial == 0,"first lesson requires no balance and creates no rental debit")
	check(not mx.start_lesson() and not mx.start_race(0),"nested lesson and race cannot create duplicate bikes")
	session._menu("Pausa da aula")
	for i in 3: await physics_frame
	var parked: Vector3 = mx.player_bike.position
	Input.action_press("move_up")
	for i in 20: await physics_frame
	Input.action_release("move_up")
	check(mx.player_bike.position.distance_to(parked)<.001 and mx.lesson.stage == 0,"menu pauses lesson and bike despite acceleration input")
	session.close_menu()
	for i in 50: await physics_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/digo/lesson.png")
	check(not STORY.data(session.state.world_state).lesson_completed,"mounting and waiting cannot complete the lesson")
	check(mx.dismount(),"normal dismount finds clear supported ground beside the loan bike")
	await physics_frame
	check(not mx.mounted and mx.lesson == null and not is_instance_valid(mx.rental_bike) and world.player.visible,"abandoning lesson releases loan bike and restores player")
	check(world.camera.target == world.player and world.player.is_physics_processing(),"normal dismount restores the player camera and movement")
	check(not STORY.data(session.state.world_state).lesson_completed,"aborted lesson does not award completion")
	check(is_instance_valid(mx.digo_car),"Digo's Gol spawns in the production world")
	if is_instance_valid(mx.digo_car):
		check(session.controller.vehicle_position_clear(mx.digo_car,mx.digo_car.position,mx.digo_car.rotation.y),"Gol is supported with physical hull clearance at its authored parking")
		var identity: int = mx.digo_car.get_instance_id()
		mx._update_digo_car()
		check(mx.digo_car.get_instance_id() == identity and get_nodes_in_group("digo_car").size() == 1,"repeated proximity checks preserve exactly one Gol")
		mx.snapshot()
		check(session.state.world_state.digo_vehicle.vehicle_id == "digo_gol_1993","unselected Gol is captured by ordinary motocross save snapshot")
		check(preload("res://runtime/FleetState.gd").validate(session.state.world_state.digo_vehicle),"Gol snapshot satisfies the real fleet persistence contract")
	check(is_instance_valid(mx.digo_amarok),"Digo's Amarok spawns alongside the Gol")
	if is_instance_valid(mx.digo_amarok) and is_instance_valid(mx.digo_car):
		check(session.controller.vehicle_position_clear(mx.digo_amarok,mx.digo_amarok.position,mx.digo_amarok.rotation.y),"Amarok's actual hull has ground support and clears the Gol and scenery")
		var gol_id: int = mx.digo_car.get_instance_id()
		var amarok_id: int = mx.digo_amarok.get_instance_id()
		mx.digo_amarok = null
		mx.digo_car = null
		mx._update_digo_car()
		check(mx.digo_car.get_instance_id() == gol_id and mx.digo_amarok.get_instance_id() == amarok_id,"existing restored vehicle identities are adopted without spawning duplicates")
		mx.snapshot()
		check(preload("res://runtime/FleetState.gd").validate(session.state.world_state.digo_amarok_vehicle),"unselected Amarok snapshot satisfies fleet persistence")
		var saved_state := preload("res://runtime/GameState.gd").new()
		var store := preload("res://runtime/SaveStore.gd").new()
		store.path = "res://evidence/digo/fleet-test-%d.json"%Time.get_ticks_usec()
		check(store.save(session.state) == OK and store.load_into(saved_state).get("ok",false),"both Digo vehicles survive an isolated disk save and load")
		check(saved_state.world_state.get("digo_vehicle",{}).get("vehicle_id","") == "digo_gol_1993" and saved_state.world_state.get("digo_amarok_vehicle",{}).get("vehicle_id","") == "digo_amarok_2014","load preserves distinct records for both personal vehicles")
		mx.set_physics_process(false)
		var parked_amarok: Vector3 = mx.digo_amarok.position
		mx.digo_amarok.restore_health(mx.digo_amarok.max_health-17)
		var saved_health: float = mx.digo_amarok.health
		mx.digo_amarok.set_meta("distance_despawn",true)
		mx.digo_amarok.queue_free()
		await physics_frame
		await physics_frame
		mx._update_digo_car()
		check(is_instance_valid(mx.digo_amarok) and mx.digo_amarok.position.distance_to(parked_amarok)<.01 and is_equal_approx(mx.digo_amarok.health,saved_health),"stream retirement captures Amarok position and damage before respawn")
		check(get_nodes_in_group("digo_car").size() == 1 and get_nodes_in_group("digo_amarok").size() == 1,"return after retirement leaves exactly one Gol and one Amarok")
		mx.set_physics_process(true)
	world.queue_free()
	await world.tree_exited
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	await process_frame
	print("DIGO_SESSION_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
