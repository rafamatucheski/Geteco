extends SceneTree
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT = preload("res://world/places/amusement_park/AmusementParkLayout.gd")
var world
var park
var folder := ""
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("COASTER_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))

func until_idle(seconds := 50.0) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while park.active and Time.get_ticks_msec()<deadline: await physics_frame
	check(not park.active,"ride releases within bounded deadline")

func run() -> void:
	create_timer(200).timeout.connect(func(): push_error("Coaster session timeout"); quit(3))
	folder = FIXTURE.output_dir("coaster-session")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",FIXTURE.full_snapshot(Vector3(166,.08,112.8),false)))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	# Exercise mapped actions explicitly; unrelated desktop/controller input
	# must not pause this isolated capture while the user keeps working.
	world.session.set_process_input(false)
	world.production.region.set_focus(LAYOUT.BOARDING)
	world.production.region.prepare_collision_at(LAYOUT.BOARDING)
	world.player.teleport(LAYOUT.BOARDING)
	park = world.session.amusement_park
	park._update_residency()
	await create_timer(2).timeout
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"real session retains C# router")
	var wallet = world.session.state.economy
	wallet.spend(wallet.balance,"coaster_test_empty")
	check(not park.start_ride() and not park.active and not world.player.input_locked,"no money refuses boarding without changing controls")
	wallet.grant_reward("coaster_test_four",4)
	check(not park.start_ride() and wallet.balance == 4,"four dollars cannot pay the five-dollar fare")
	wallet.grant_reward("coaster_test_one",1)
	var start: Vector3 = world.player.global_position
	var mask: int = world.player.collision_mask
	await capture("before-entry")
	check(await world.session.interact() and park.active and park.ride_phase == "boarding","mapped action starts animated boarding")
	check(wallet.balance == 0 and not park.start_ride() and wallet.balance == 0,"exact fare debited once, duplicate input cannot charge twice")
	check(world.player.visual.visible and world.player.input_locked,"Dante stays visible while boarding and input is locked")
	check(not world.session.save_block_reason().is_empty(),"save blocked throughout boarding")
	for i in 6:
		await create_timer(.45).timeout
		await capture("entry-%02d"%i)
		check(is_zero_approx(park.ride_distance),"carriage stays docked during boarding %d"%i)
	check(world.player.global_position.distance_to(start)>1.0,"Dante actually approaches and enters the carriage")
	while park.ride_phase == "boarding": await physics_frame
	await create_timer(1).timeout
	check(park.ride_distance>0 and not world.player.visual.visible,"departure follows seating and the camera transition")
	park.request_exit()
	park.request_exit()
	check(park.active and park.return_requested and wallet.balance==0,"repeated exit requests stay on rails and do not charge")
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 4
	blocker.collision_mask = 0
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(.8,1.8,.8)
	blocker_shape.shape = blocker_box
	blocker.add_child(blocker_shape)
	world.add_child(blocker)
	blocker.global_position = start+Vector3.UP*.9
	var deadline := Time.get_ticks_msec()+45000
	while park.ride_phase == "riding" and Time.get_ticks_msec()<deadline: await physics_frame
	check(park.active and park.ride_phase=="waiting" and world.player.input_locked,"occupied platform holds passenger safely at station")
	blocker.queue_free()
	await physics_frame
	await create_timer(.4).timeout
	check(park.ride_phase == "disembarking" and park.ride_speed == 0,"lap brakes at station before disembarking")
	for i in 6:
		await create_timer(.45).timeout
		await capture("exit-%02d"%i)
	await until_idle()
	check(not world.player.input_locked and world.player.visual.visible and not world.player.seated,"exit restores a visible standing controllable Dante")
	check(root.get_camera_3d()==world.camera and world.player.collision_mask==mask and world.player.is_physics_processing(),"exit restores camera collision and physics")
	check(world.session.position_clear(world.player.global_position),"landing has full-body clearance and floor support")
	check(is_zero_approx(park.site.station_gate.rotation.y) and park.site.gate_body.collision_layer==1,"gate closes and physically blocks public access to track")
	var restored = preload("res://runtime/GameState.gd").new()
	check(restored.restore_snapshot(world.session.state.snapshot()) and restored.economy.balance==0,"fare survives state serialization")
	wallet.grant_reward("coaster_more_tickets",20)
	check(park.start_ride(),"repeat ride charges a new fare")
	await create_timer(.8).timeout
	park.request_exit()
	await until_idle(5)
	check(wallet.balance==15 and world.player.global_position.distance_to(start)<.4,"boarding cancellation reverses visible approach without duplicate debit")
	check(park.start_ride(),"pause scenario boards")
	var pause_event := InputEventAction.new()
	pause_event.action = "pause_game"
	pause_event.pressed = true
	check(not park.handle_input(pause_event) and not park.active and not world.player.input_locked,"pause immediately releases ride for the pause owner")
	check(park.start_ride(),"death scenario boards")
	await create_timer(2).timeout
	world.gameplay.damage_player(1000)
	check(not park.active and world.session.rescue_pending,"death interrupts animation immediately")
	deadline = Time.get_ticks_msec()+15000
	while world.session.rescue_pending and Time.get_ticks_msec()<deadline: await physics_frame
	check(world.gameplay.health>0 and not world.player.input_locked and world.player.visual.visible and not world.player.seated,"rescue recovers actor pose and controls")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("COASTER_SESSION_RESULT ",folder," checks=",checks," failures=",failures)
	quit(1 if not failures.is_empty() else 0)
