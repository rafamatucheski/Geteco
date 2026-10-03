extends SceneTree
const LAYOUT = preload("res://activities/skate/SkateParkLayout.gd")
const OUT = "res://evidence/skate-exit-20261002/rendered-final"
var world
var failures := 0
var observations: Array = []
func _initialize(): run.call_deferred()
func frames(count: int):
	for i in count: await physics_frame
func shot(label: String):
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + label + ".png")
func check(ok: bool, label: String):
	observations.append({"check": label, "passed": ok})
	if not ok: failures += 1
	print("SKATE_EXIT ", "PASS " if ok else "FAIL ", label)
func run():
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(OUT)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	if session == null or not session.ready_for_play: quit(2); return
	if not session.state.place_id.is_empty(): await session.leave_place()
	session.state.intro.stage = "complete"
	session.weather.time_of_day = .45
	session.weather.weather_state = 0
	session.weather.weather_timer = 1000
	session.weather._update()
	world.player.teleport(LAYOUT.CENTER + Vector3(0, -1.5, 0))
	world.production.region.set_focus(LAYOUT.ENTRY)
	world.camera.target_size = 15
	world.camera.initialized = false
	await frames(180)
	var skate = session.skate
	var board = skate._new_board(world.player.position)
	await frames(20)
	check(session.interact() and skate.mounted, "real interaction mounts at bowl bottom")
	if not skate.mounted: world.free(); quit(1); return
	board.rotation.y = PI
	Input.action_press("move_up")
	var outside := false
	for i in 360:
		await physics_frame
		if i % 24 == 0: await shot("climb-%03d" % i)
		if not LAYOUT.FOOTPRINT.has_point(Vector2(board.position.x, board.position.z)) and board.position.y > -.1:
			outside = true
			break
	Input.action_release("move_up")
	check(outside and skate.mounted, "pushes from rest all the way out of the park")
	Input.action_press("move_down")
	var reversed := false
	for i in 180:
		await physics_frame
		if board.speed < -.5: reversed = true; break
	check(reversed and skate.mounted, "S brakes then reverses through actual input")
	await shot("reverse")
	Input.action_press("move_up")
	await frames(60)
	Input.action_release("move_up")
	Input.action_release("move_down")
	if skate.mounted: check(skate.dismount(), "can dismount after braking")
	await frames(140)
	var owner = null
	var taken = null
	for row in skate.ambient:
		if row.park:
			owner = row.actor
			taken = row.board
			break
	check(is_instance_valid(owner), "park rider available for theft recovery")
	if is_instance_valid(owner):
		taken.bail(0)
		await frames(140)
		world.player.teleport(taken.position + Vector3(.8, .15, 0))
		await frames(15)
		check(session.interact() and skate.mounted, "collect the previous rider's loose board")
		var began: Vector3 = owner.position
		world.camera.target = owner
		world.camera.target_size = 12
		for i in 10:
			await frames(24)
			await shot("owner-escape-%02d" % i)
		check(owner.position.distance_to(began) > 3 and not owner.input_locked, "previous owner runs instead of freezing")
		observations.append({"owner_from": str(began), "owner_to": str(owner.position), "route": str(owner.route)})
	FileAccess.open(OUT + "/result.json", FileAccess.WRITE).store_string(JSON.stringify({"engine": Engine.get_version_info().string, "failures": failures, "observations": observations, "performance": "Visual/input diagnostic with other game running, not a benchmark"}, "\t"))
	world.free()
	quit(1 if failures else 0)
