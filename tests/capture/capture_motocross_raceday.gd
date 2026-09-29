extends SceneTree
## Visual review of the motocross venue in the real Main scene (day, dry).
## Gameplay framing: orthographic, 45 degree pitch, size 34 as while riding.
## Review captures only, NOT a performance benchmark. --no-save is mandatory.
## Usage: --script res://tests/capture/capture_motocross_raceday.gd -- --no-save --label=after
var world
var label := "after"
var camera: Camera3D

func _initialize() -> void: run.call_deferred()

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://evidence/motocross/raceday-%s-%s.png"%[label,name]
	root.get_texture().get_image().save_png(path)
	print("MOTOCROSS_CAPTURE ",path)

func frame(focus: Vector3, size: float, offset := Vector3(0,25.3,25.3)) -> void:
	camera.size = size
	camera.global_position = focus+offset
	camera.look_at(focus)
	camera.make_current()
	for i in 20: await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Captures need the rendered game"); quit(2); return
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("Refusing to run without --no-save"); quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/motocross"))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Main not ready"); quit(1); return
	var session = world.session
	session.state.intro.stage = "complete"
	session.weather.time_of_day = .42
	session.weather.weather_state = 0
	session.motocross.wetness = 0.0
	session.weather.weather_timer = 1000
	session.weather._update()
	world.player.teleport(Vector3(-205,.3,-45))
	world.production.region.set_focus(world.player.position)
	world.player.controlled_automatically = true
	world.player.speed = 0
	for i in 300: await physics_frame
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 500
	world.add_child(camera)
	var track = session.motocross.track
	await frame(track.sample(-14.0),34)
	await shot("grid")
	await frame(Vector3(-195,1,-54),34)
	await shot("straight")
	await frame(Vector3(-179,4,-90),34)
	await shot("hairpin-west")
	await frame(Vector3(-113,1,-60),34)
	await shot("hairpin-east")
	await frame(Vector3(-221,.2,-33),26)
	await shot("paddock")
	# Diagnostic close-ups: berm shoulder stakes and the bleacher base.
	await frame(Vector3(-175,4.5,-88),9,Vector3(9,6,9))
	await shot("berm-stakes-close")
	await frame(Vector3(-206,1,-66),11,Vector3(-9,7,12))
	await shot("bleacher-close")
	await frame(Vector3(-175,5,-94),125,Vector3(0,130,114))
	await shot("overview")
	# Race start seen through the real gameplay camera and HUD.
	session.state.economy.grant_reward("mx_capture",1000)
	world.player.teleport(Vector3(-224,.15,-37))
	for i in 30: await physics_frame
	world.camera.make_current()
	var mx = session.motocross
	mx.selected_model = 0
	if not mx.start_race(0):
		push_error("Race did not start"); quit(1); return
	mx.autopilot = true
	for i in 156: await physics_frame
	for i in 60:
		await physics_frame
		if mx.countdown > 0 and mx.countdown < 1.2: break
	await shot("countdown-hud")
	await frame(track.sample(-16.0)+Vector3(0,.5,0),14,Vector3(-8,9,12))
	await shot("gate-close")
	world.camera.make_current()
	for i in 60*9: await physics_frame
	await shot("race-hud")
	if mx.has_method("_classify"): mx.finish(false,"quit")
	else: mx.finish(false)
	for i in 20: await process_frame
	await shot("results")
	world.queue_free()
	await process_frame
	print("MOTOCROSS_CAPTURE_COMPLETE ",label)
	quit()
