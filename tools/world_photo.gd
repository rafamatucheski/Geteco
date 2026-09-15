extends SceneTree
## Standalone photo session: production world, separate user data at launch.
const OUTPUT := "D:/geteco/artifacts/mapa-inteiro"
const FRAME := Rect2(-1800, -8800, 17200, 15400)

class PhotoControls extends Node:
	var camera: Camera2D
	var dragging := false
	var capturing := false
	func fit_map() -> void:
		camera.global_position = FRAME.get_center()
		var size := get_viewport().get_visible_rect().size
		camera.zoom = Vector2.ONE * minf(size.x / FRAME.size.x, size.y / FRAME.size.y) * 0.94
		camera.force_update_scroll()
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
				dragging = event.pressed
			if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var before := camera.get_global_mouse_position()
				var factor := 1.18 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.18
				camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, 0.015, 3.0)
				camera.force_update_scroll()
				camera.global_position += before - camera.get_global_mouse_position()
		if event is InputEventMouseMotion and dragging:
			camera.global_position -= event.relative / camera.zoom.x
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_HOME: fit_map()
				KEY_F12: picture()
				KEY_ESCAPE: get_tree().quit()
		get_viewport().set_input_as_handled()
	func picture() -> void:
		if capturing: return
		capturing = true
		await RenderingServer.frame_post_draw
		var path := OUTPUT.path_join("mapa-%d.png" % Time.get_unix_time_from_system())
		var result := get_viewport().get_texture().get_image().save_png(path)
		print("WORLD_PHOTO_CAPTURE ", path, " result=", result)
		capturing = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.title = "GETECO — Mapa inteiro | Roda: zoom | Arrastar: direito/meio | Home: enquadrar | F12: print"
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)
	root.get_node("SaveManager").clear_pending_save()
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null:
		await process_frame
	var world := current_scene
	while not world.gameplay_ready or not world.world_build_ready:
		await process_frame
	world.campaign_controller.skip_cinematic()
	paused = false
	var stream := world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing:
		await process_frame
	stream.set_process(false)
	stream.mountain.visible = true
	stream.mountain.process_mode = Node.PROCESS_MODE_INHERIT
	stream.mountain.region_selected = false
	stream.mountain.parallax.hide()
	stream.mountain.cold_controller.set_process(false)
	world.weather.time_of_day = 0.45
	world.weather.is_dynamic_time = false
	world.weather.set_weather(0)
	var player := world.get_node("Player")
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	var camera := Camera2D.new()
	camera.name = "WholeWorldPhotoCamera"
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(camera)
	camera.make_current()
	var controls := PhotoControls.new()
	controls.process_mode = Node.PROCESS_MODE_ALWAYS
	controls.camera = camera
	root.add_child(controls)
	controls.fit_map()
	for frame in 90:
		await process_frame
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.hide()
	# Keep the composition still while the photo camera remains interactive.
	paused = true
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT.path_join("mapa-inteiro.png"))
	print("WORLD_PHOTO_READY mountain_visible=%s camera=%s zoom=%s capture=%s" % [stream.mountain.is_visible_in_tree(), camera.global_position, camera.zoom, result])
