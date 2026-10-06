extends SceneTree
## Isolated save, actual Main, native routing, physical bridge crossing and real doors.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var failures:=0
var checks:=0
var folder:=""
func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("DESERT_SESSION timeout"); quit(3))
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	print("DESERT_SESSION ","PASS " if value else "FAIL ",label)
	if not value: failures+=1
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	folder=FIXTURE.output_dir("desert-session")
	var snapshot:=FIXTURE.full_snapshot(Vector3(340,2.48,-359),true)
	# A valid saved car avoids adding a second car behind the default spawn.
	snapshot.world.vehicles=[{"archetype":"desert_faisca","vehicle_id":"test_desert_bridge","was_driven":false,"paint":"c79b42ff","position":[343,2.52,-359],"yaw":0.0,"health":float(preload("res://runtime/FleetCatalog.gd").spec("desert_faisca").durability),"region":"harbor","equipment":{}}]
	var path:=FIXTURE.write_fixture(folder,"checkpoint.json",snapshot)
	check(not path.is_empty(),"isolated completed-campaign save valid")
	if path.is_empty(): quit(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session!=null and world.session.ready_for_play,"Main .NET ready")
	if failures: finish(); return
	check(world.production.store.path==path and world.production.loaded_save and not world.production.save_invalid,"actual SaveStore honored isolated checkpoint")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled C# route backend active")
	var session=world.session
	check(is_instance_valid(session.desert),"desert coordinator installed")
	var car=world.driving.car
	check(is_instance_valid(car) and car.archetype=="desert_faisca" and car.vehicle_id=="test_desert_bridge","new car restored on completed physical bridge")
	if not is_instance_valid(car): finish(); return
	world.player.teleport(car.driver_door_anchor(1)+Vector3(.4,.1,0))
	await frames(5)
	check(world.driving.interact(),"ordinary boarding accepted")
	var boarding_deadline:=Time.get_ticks_msec()+8000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<boarding_deadline: await physics_frame
	check(world.driving.occupied and world.driving.car==car and car.controlled and not car.input_locked,"driver entered selected car")
	if failures: finish(); return
	Input.action_press("accelerate",.5)
	var started: Vector3=car.global_position
	var deadline:=Time.get_ticks_msec()+25000
	while car.global_position.z>-465 and Time.get_ticks_msec()<deadline:
		await physics_frame
		if car.position.y<-3: break
	Input.action_release("accelerate")
	Input.action_press("handbrake")
	await frames(180)
	print("DESERT_CROSSING_DIAGNOSTIC ",JSON.stringify({"start":str(started),"end":str(car.global_position),"speed":car.speed,"health":car.health,"region":session.state.region_id,"controlled":car.controlled,"locked":car.input_locked,"ground":car.is_on_floor()}))
	check(car.global_position.z<-445 and car.global_position.distance_to(started)>85,"car physically crosses completed bridge into desert")
	check(car.global_position.y>-.3 and world.production.state.region_id=="desert","supported ramp and actual logical region handoff")
	Input.action_release("handbrake")
	check(world.driving.leave(),"ordinary exit accepted")
	var exit_deadline:=Time.get_ticks_msec()+8000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<exit_deadline: await physics_frame
	check(not world.driving.occupied,"desert disembark restores actor")
	if not world.driving.occupied:
		check(session.save_game(),"desert checkpoint writes through actual save flow")
		var saved:=preload("res://runtime/SaveStore.gd").read_valid(path)
		check(not saved.is_empty() and saved.region_id=="desert","disk save accepts desert and vehicle")
	if DisplayServer.get_name()!="headless":
		await process_frame
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder.path_join("arrival.png")))
	finish()
func finish() -> void:
	print("DESERT_SESSION checks=%d failures=%d evidence=%s"%[checks,failures,folder])
	quit(0 if failures==0 else 1)
