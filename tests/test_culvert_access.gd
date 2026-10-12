extends SceneTree
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ID := "desert_under_culvert"
var world
var failures: Array[String] = []
var folder := "res://output/culvert-review-20261011"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("ACCESS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func frames(n: int) -> void:
	for i in n: await physics_frame
func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func walk_to(point: Vector3, count := 900) -> bool:
	for i in count:
		var delta: Vector3 = point-world.player.global_position
		delta.y = 0
		if delta.length() < .18:
			world.player.automatic_direction = Vector3.ZERO
			return true
		world.player.automatic_direction = delta.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	print("WALK_STOP ",world.player.global_position," target=",point)
	return false
func settled() -> void:
	for i in 600:
		await physics_frame
		if not world.session.is_transition_blocked() and not world.session.special_place_entrance.busy: return
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180,true,false,true).timeout.connect(func(): push_error("CULVERT TIMEOUT"); quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var definition := PLACES.get_definition(ID)
	var entry: Vector3 = definition.entry_position
	var snapshot := FIXTURE.full_snapshot(entry+Vector3(0,.08,3), true)
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region":"desert", "position":[entry.x,.08,entry.z+3]}
	var fixture_dir := FIXTURE.output_dir("culvert-access")
	var path := FIXTURE.write_fixture(fixture_dir,"save.json",snapshot)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 3600:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session != null and world.session.ready_for_play,"Main loads isolated desert save")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.prepare_collision_at(entry)
	await frames(60)
	var hatch: Node3D = session._find_sewer_hatch(ID)
	check(is_instance_valid(hatch),"exterior streamed")
	if not is_instance_valid(hatch): quit(1); return
	var inward: Vector3 = -hatch.global_basis.z
	check(await walk_to(hatch.to_global(Vector3(0,.08,.6))),"walk to closed door")
	await frames(30)
	check(hatch.open_amount < .01,"standing at door does not open it")
	check(world.player.test_move(world.player.global_transform,inward),"closed gate blocks capsule")
	await photo("01-exterior")
	world.player.automatic_direction = inward
	var partial := false
	for i in 480:
		await physics_frame
		partial = partial or (hatch.open_amount > .05 and hatch.open_amount < .8)
		if session.state.place_id == ID: break
	world.player.automatic_direction = Vector3.ZERO
	check(partial,"gate opens visibly before entry")
	check(session.state.place_id == ID,"walking enters without interaction button")
	if session.state.place_id != ID:
		print("ENTRY_STOP ",world.player.global_position," local=",hatch.to_local(world.player.global_position)," open=",hatch.open_amount)
		quit(1); return
	await settled()
	await frames(30)
	check(not world.player.input_locked,"entry restores control")
	check(session.room_npcs.size() == 2,"both residents present")
	check(world.camera.size < 15,"close camera")
	await photo("02-west-entry")
	for point in [Vector3(-5,0,0),Vector3(4,0,0),Vector3(13,0,0)]:
		check(await walk_to(session.room.to_global(point)),"walk aisle to %s"%point)
		await frames(35)
		await photo("03-interior-%d"%int(point.x))
	check(session.anchor.position.x > session.room.global_position.x+10,"camera follows along tunnel")
	# Each leg fits the existing 15 s movement window at the real walking speed.
	for x in [4,-5,-17]:
		check(await walk_to(session.room.to_global(Vector3(x,0,0))),"walk back towards western exit x=%d"%x)
	world.player.automatic_direction = Vector3.LEFT
	for i in 480:
		await physics_frame
		if session.state.place_id.is_empty(): break
	world.player.automatic_direction = Vector3.ZERO
	check(session.state.place_id.is_empty(),"walk out without interaction button")
	await settled()
	check(not world.player.input_locked,"exit restores control")
	check(world.player.global_position.distance_to(definition.return_position) < 2,"returns to original exterior")
	await photo("04-return")
	# Second cycle exercises the reentry latch and immediate return from spawn.
	check(await walk_to(hatch.to_global(Vector3(0,.08,.6))),"walk back to gate")
	world.player.automatic_direction = inward
	for i in 480:
		await physics_frame
		if session.state.place_id == ID: break
	world.player.automatic_direction = Vector3.ZERO
	check(session.state.place_id == ID,"reentry works")
	await settled()
	if session.state.place_id == ID:
		world.player.automatic_direction = Vector3.LEFT
		for i in 480:
			await physics_frame
			if session.state.place_id.is_empty(): break
		world.player.automatic_direction = Vector3.ZERO
		await settled()
		check(session.state.place_id.is_empty() and not world.player.input_locked,"can immediately turn around and leave")
	print("CULVERT_ACCESS failures=",failures)
	quit(0 if failures.is_empty() else 1)
