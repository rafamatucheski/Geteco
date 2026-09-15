extends SceneTree
## Fixed noon route and matched locations at sunset/night in the production world.
var world: Node
var camera: Camera2D
var player: Node2D
var output := "D:/geteco/artifacts/regional-atmosphere/review"
var _hour := 0.5

func _process(_delta: float) -> bool:
	if is_instance_valid(world) and world.has_node("CobraCampaign"):
		var bridge := world.get_node("CobraCampaign")
		if bridge.ledger != null:
			bridge.ledger.data.day_elapsed = fposmod(_hour - 0.35, 1.0) * preload("res://world/harbor/campaign/CobraCampaignState.gd").DAY_SECONDS
		world.weather.time_of_day = _hour
	return false

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output.path_join("saves"))
	var saves := root.get_node("SaveManager")
	saves._save_dir = output.path_join("saves") + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var state := root.get_node("CampaignState")
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		state.set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	create_timer(180).timeout.connect(func(): push_error("Atmosphere review timed out"); quit(2))
	while current_scene == null: await process_frame
	world = current_scene
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	player = world.get_node("Player")
	player.set_physics_process(false)
	player.set_process(false)
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * 1.1
	camera.set_meta("mountain_fixed_framing", true)
	world.add_child(camera)
	camera.make_current()
	await shot("01-porto-meio-dia", Vector2(3100, 1750), 0.5)
	var stream: Node = world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	stream.mountain.storm_manager.dynamic_weather = false
	stream.mountain.storm_manager.weather_clock = 0
	stream.mountain.storm_manager.advance_weather(0)
	await shot("02-ponte-transicao", Vector2(7600, -4560), 0.5)
	await shot("03-floresta-meio-dia", stream.mountain.to_global(Vector2(6650, 150)), 0.5)
	await shot("04-cume-meio-dia", stream.mountain.to_global(Vector2(6850, -2450)), 0.5)
	await shot("05-cume-entardecer", stream.mountain.to_global(Vector2(6850, -2450)), 0.77)
	await shot("06-cume-noite", stream.mountain.to_global(Vector2(6850, -2450)), 0.9)
	stream.mountain.storm_manager.weather_clock = 120
	stream.mountain.storm_manager.advance_weather(0)
	await shot("07-cume-nevasca", stream.mountain.to_global(Vector2(6850, -2450)), 0.5)
	await shot("08-tunel-abrigado", stream.mountain.to_global(Vector2(5300, 400)), 0.5)
	var atmosphere: Node = world.weather.atmosphere
	if not atmosphere.sheltered or float(atmosphere.effect.get_shader_parameter("haze")) != 0:
		push_error("Tunnel retained exterior haze")
		quit(1)
		return
	print("REGIONAL_ATMOSPHERE_REVIEW completed; tunnel haze suppressed")
	quit(0)

func shot(label: String, position: Vector2, hour: float) -> void:
	_hour = hour
	player.global_position = position
	player.reset_physics_interpolation()
	camera.global_position = position
	camera.reset_smoothing()
	world.weather.time_of_day = hour
	world.weather.set_weather(0)
	world.weather.weather_timer = 1000000.0
	var ledger = world.get_node("CobraCampaign").ledger
	ledger.data.day_elapsed = fposmod(hour - 0.35, 1.0) * preload("res://world/harbor/campaign/CobraCampaignState.gd").DAY_SECONDS
	# Let real streaming, shelters and presentation settle, then hold the exact hour.
	await create_timer(2.0).timeout
	world.weather.time_of_day = hour
	world.weather._update_lighting()
	world.weather.atmosphere.refresh_immediately()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	var counts := {"point_lights_2d": 0, "enabled_2d": 0, "visible_2d": 0, "overlapping_camera_2d": 0, "lights_3d": 0, "viewports": 0, "updating_viewports": 0}
	var view_rect: Rect2 = root.get_canvas_transform().affine_inverse() * root.get_visible_rect()
	for light in root.find_children("*", "PointLight2D", true, false):
		counts.point_lights_2d += 1
		if light.enabled:
			counts.enabled_2d += 1
			if light.is_visible_in_tree():
				counts.visible_2d += 1
				if light.texture != null and light.get_viewport() == root:
					var texture_size: Vector2 = light.texture.get_size() * light.texture_scale
					var light_rect: Rect2 = light.global_transform * Rect2(light.offset - texture_size * 0.5, texture_size)
					if light_rect.intersects(view_rect): counts.overlapping_camera_2d += 1
	for type in ["DirectionalLight3D", "OmniLight3D", "SpotLight3D"]:
		counts.lights_3d += root.find_children("*", type, true, false).size()
	for viewport in root.find_children("*", "SubViewport", true, false):
		counts.viewports += 1
		if viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED: counts.updating_viewports += 1
	FileAccess.open(output.path_join(label + "-inventory.json"), FileAccess.WRITE).store_string(JSON.stringify(counts, "\t"))
	print("CAPTURE ", label, " mountain=", world.weather.atmosphere.mountain_weight, " summit=", world.weather.atmosphere.summit_weight, " night=", world.weather.is_dark)
