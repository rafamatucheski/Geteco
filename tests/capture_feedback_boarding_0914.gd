extends SceneTree
var OUTPUT := "D:/geteco/artifacts/feedback-0914-teste2/boarding-final/"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var parking := OS.get_cmdline_user_args().has("--parking")
	if parking: OUTPUT = "D:/geteco/artifacts/feedback-0914-teste2/parking-final/"
	create_timer(140,true,false,true).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(OUTPUT+"frames")
	DirAccess.make_dir_recursive_absolute(OUTPUT+"saves")
	root.size = Vector2i(960,640)
	root.content_scale_size = root.size
	var saves := root.get_node("SaveManager")
	saves._save_dir = OUTPUT+"saves/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	for key in ["harbor_arrival_seen","harbor_story_arrival_v2","harbor_police_briefed","harbor_arrival_call_complete"]: state.set_campaign_flag(StringName(key),true)
	seed(14092026)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.gameplay_ready or not current_scene.world_build_ready: await process_frame
	var world := current_scene
	var intro: Node = world.campaign_controller.story_arrival
	var player: Node2D = world.get_node("Player")
	player.global_position = intro.maciota.global_position+Vector2(0,30)
	player.reset_physics_interpolation()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = intro.car.global_position
	camera.zoom = Vector2.ONE*3.0
	camera.make_current()
	world.weather.time_of_day = .42
	world.weather.is_dynamic_time = false
	world.weather.set_weather(0)
	for i in 60: await process_frame
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0,record)
	record.set_recording_active(true)
	intro._board()
	if parking:
		while intro.transition_busy: await process_frame
		if not intro.riding: quit(1); return
		# Isolate the final approach after genuine boarding; this relocation is
		# a capture fixture, never part of production driving.
		var tail: PackedVector2Array = intro.tour_route.slice(intro.tour_route.size()-30)
		intro.car.global_position = tail[0]
		intro.car.heading = (tail[1]-tail[0]).angle()
		intro.car.pose()
		intro.car.reset_physics_interpolation()
		intro.car.start(tail)
	var start := Time.get_ticks_msec()
	var frame := 0
	while Time.get_ticks_msec()-start < (20000 if parking else 9000):
		await create_timer(1.0/20.0).timeout
		camera.global_position = intro.car.global_position
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT+"frames/%04d.png" % frame)
		frame += 1
	record.set_recording_active(false)
	record.get_recording().save_to_wav(OUTPUT+"boarding.wav")
	print("BOARDING_CAPTURE frames=",frame," phase=",world.campaign_controller.phase," player=",player.global_position," car=",intro.car.global_position)
	print("BOARDING_STATE heading=",intro.car.heading," cursor=",intro.car.cursor," reason=",intro.car.pass_reason," obstacle=",intro.car.last_obstacle," exit_pending=",intro.exit_pending)
	if parking and world.campaign_controller.phase != "meet_maciota": quit(1); return
	quit()
