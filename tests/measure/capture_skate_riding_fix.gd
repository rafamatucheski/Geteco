extends SceneTree
const LAYOUT := preload("res://activities/skate/SkateParkLayout.gd")
var world
var OUT := "res://evidence/skate-riding-fix-20261002/net"
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + label + ".png")
func action(name: String) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	Input.parse_input_event(event)
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(OUT)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(2); return
	var session = world.session
	if not session.state.place_id.is_empty(): await session.leave_place()
	session.state.intro.stage = "complete"
	session.weather.time_of_day = .45
	session.weather.weather_state = 0
	session.weather.weather_timer = 1000
	session.weather._update()
	if "--street-only" in OS.get_cmdline_user_args():
		await street_capture()
		world.free()
		quit()
		return
	world.player.teleport(LAYOUT.ENTRY + Vector3(.8, .1, 0))
	world.production.region.set_focus(LAYOUT.ENTRY)
	world.camera.heading = PI
	world.camera.target_size = 26
	world.camera.initialized = false
	await frames(180)
	await shot("01-park-gameplay")
	if "--details-only" in OS.get_cmdline_user_args():
		world.free()
		quit()
		return
	for screen_point in [Vector2(750, 340), Vector2(570, 210), Vector2(1080, 380), Vector2(565, 480)]:
		var origin: Vector3 = world.camera.project_ray_origin(screen_point)
		var dir: Vector3 = world.camera.project_ray_normal(screen_point)
		print("SKATE_LOT_POINT ", screen_point, " = ", origin - dir * origin.y / dir.y)
	if not session.interact() or not session.skate.mounted: push_error("Skate not mounted"); quit(1); return
	var board = session.skate.player_board
	world.camera.locked = true
	world.camera.target_size = 5
	board.rotation.y = -PI * .5
	Input.action_press("move_up")
	for i in 18:
		await frames(2)
		if i % 3 == 0: await shot("push-%02d" % i)
	Input.action_release("move_up")
	Input.action_press("move_down")
	await frames(75)
	Input.action_release("move_down")
	await shot("02-both-feet")
	action("skate_ollie")
	await frames(5)
	action("skate_flip")
	for i in 9:
		await frames(3)
		await shot("flip-%02d" % i)
	await frames(40)
	await shot("03-landed")
	action("skate_ollie")
	await frames(28)
	action("skate_flip")
	for i in 12:
		await frames(8)
		await shot("fall-%02d" % i)
	await frames(80)
	await shot("04-recovered")
	var report := {"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "skate": session.skate.snapshot(), "health": world.gameplay.health, "ambient": session.skate.ambient.size(), "note": "Rendered visual diagnostic with other Godot processes present; no performance approval or baseline comparison."}
	FileAccess.open(OUT + "/capture.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	world.free()
	quit()

func street_capture() -> void:
	# Diretor de população real e rotas autorais de pedestres, longe do parque.
	world.player.teleport(Vector3(-65, .1, -65))
	world.production.region.set_focus(world.player.position)
	world.camera.target_size = 24
	world.camera.initialized = false
	await frames(600)
	var row: Dictionary = {}
	for candidate in world.session.skate.ambient:
		if not candidate.park:
			row = candidate
			break
	if row.is_empty():
		push_error("No street skater produced by ordinary population")
		return
	world.camera.target = row.board
	world.camera.target_size = 7
	for i in 8:
		await frames(12)
		await shot("street-%02d" % i)
	print("STREET_CAPTURE identity=", row.actor.identity, " route=", row.route, " pace=", row.pace, " distance_from_park=", row.actor.position.distance_to(LAYOUT.CENTER))
