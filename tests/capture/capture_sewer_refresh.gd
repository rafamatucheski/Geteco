extends SceneTree
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const NETWORK := preload("res://world/places/sewers/SewerNetwork.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var tag := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute("res://output/sewer-refresh")
	root.size = Vector2i(1280,720)
	var fixture := Node3D.new()
	root.add_child(fixture)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("0b1112")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("7f95a0")
	environment.environment.ambient_light_energy = .35
	fixture.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.add_child(camera)
	camera.make_current()
	for id in NETWORK.ids():
		var room = CATALOG.create_place(id)
		fixture.add_child(room)
		camera.size = room.camera_size
		camera.position = room.camera_target + Vector3(0,18,15)
		camera.look_at(room.camera_target)
		for i in 45: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/sewer-refresh/%s-%s.png" % [tag,id])
		room.free()
	quit(0)
