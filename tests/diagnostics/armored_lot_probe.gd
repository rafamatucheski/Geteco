extends SceneTree
## Production admission and loading: real bank geometry, crew and physical cars.
## Completed campaign/calendar are isolated fixture setup, not campaign coverage.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
var world
var checks := 0
var failures: Array[String] = []
var folder := ""
var origin := "harbor_bank"
var security_level := 0
var prepared := false
func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("ARMORED_SESSION timeout"); finish(3))
	run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	print("ARMORED_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok
func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if "--desert" in OS.get_cmdline_user_args(): origin = "desert_bank"
	if "--maximum-security" in OS.get_cmdline_user_args(): security_level = SCHEDULE.MAX_SECURITY
	folder = FIXTURE.output_dir("armored-lot-probe")
	var bank: Vector3 = PLACES.get_definition(origin).entry_position
	var point: Vector3 = bank+Vector3(4,.08,1)
	var snapshot := FIXTURE.full_snapshot(point,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var region := "desert" if origin == "desert_bank" else "harbor"
	snapshot.region_id = region
	snapshot.world.pedestrian = {"region":region,"position":[point.x,point.y,point.z]}
	snapshot.world.moon_day = 3 if region == "desert" else 1
	snapshot.world.time = (14.0 if region == "desert" else 9.0)/24.0
	if security_level > 0:
		# Persisted preparation seeds the real scheduler; it must create the event.
		snapshot.world[SCHEDULE.KEY] = {"version":1,"last_event":"","security_level":security_level,"event":{}}
	var path := FIXTURE.write_fixture(folder,"checkpoint.json",snapshot)
	if not check(not path.is_empty(),"isolated scheduled checkpoint accepted"): finish(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for frame in 6000:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if not check(world.session != null and world.session.ready_for_play and not world.production.save_invalid,"real Main ready"): finish(1); return
	var session = world.session
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"compiled C# router active")
	var convoy = session.armored_transport
	world.production.region.set_focus(point)
	for frame in 3: await physics_frame
	if not check(session.position_clear(point),"observer begins on supported clear bank sidewalk"): finish(1); return
	world.player.teleport(point)
	print("ARMORED_SETUP ",JSON.stringify({"bank":str(PLACES.get_definition(origin).entry_position),"fixture":str(point),"cache":world.production._route_cache.keys()}))
	for z in [2.0,6.0,10.0,13.0]:
		var clear: Array = []
		for x in range(8,57,2):
			if convoy._spawn_space_clear(Vector3(x,.08,z),PI,true): clear.append(x)
		print("LOT_CLEAR z=",z," x=",clear)
	world.camera.set_process(false)
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 55
	world.camera.global_position = Vector3(35,55,38)
	world.camera.look_at(Vector3(35,0,8))
	await create_timer(2).timeout
	await photo("lot")
	finish(0)
func finish(code: int):
	print("LOT_PROBE ",folder)
	quit(code)
