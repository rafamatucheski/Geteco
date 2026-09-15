extends SceneTree
const OUTPUT := "D:/geteco/artifacts/traffic-signals-3d-0910/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1100, 760)
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var camera := Camera2D.new()
	stage.add_child(camera)
	camera.position = Vector2(500, 350)
	camera.zoom = Vector2.ONE * 4.0
	camera.make_current()
	for index in 3:
		var post = load("res://geodata/roads/traffic/FixedTrafficSignal.gd").new()
		post.position = Vector2(430 + index * 70, 380)
		post.entry_tangent = Vector2.UP.rotated(-0.3)
		post.signal_state = index
		stage.add_child(post)
		post.ensure_presentation()
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + "signal-detail.png")
	stage.queue_free()
	await process_frame
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	world.get_node("Player").set_physics_process(false)
	world.get_node("Player").global_position = Vector2(1180, 2110)
	var street_camera := Camera2D.new()
	world.add_child(street_camera)
	street_camera.position = Vector2(1270, 2150)
	street_camera.zoom = Vector2.ONE * 2.3
	street_camera.set_meta("mountain_fixed_framing", true)
	street_camera.make_current()
	for layer in world.find_children("", "CanvasLayer", true, false): layer.hide()
	for i in 90: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + "signals-street.png")
	print("SIGNAL_CAPTURE posts=", get_nodes_in_group("fixed_traffic_signal").size())
	world.queue_free()
	await process_frame
	quit()
