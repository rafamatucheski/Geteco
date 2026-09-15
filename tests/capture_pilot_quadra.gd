extends SceneTree

## Captures Quadra 1 (Westgate Core) under Day, Night, and Rain.
## Run with Godot console executable (not --headless) for actual texture rendering.

const PREVIEW_PATH := "res://world/harbor/HarborPreview.tscn"
const WEATHER_SCRIPT := preload("res://systems/DayNightWeatherManager.gd")

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)

	var phase := "after"
	var all_args := OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--phase="):
			phase = arg.trim_prefix("--phase=")
		elif arg == "after":
			phase = "after"
		elif arg == "before":
			phase = "before"

	var preview := load(PREVIEW_PATH).instantiate() as Node2D
	root.add_child(preview)
	current_scene = preview

	# Attach weather manager for day/night/rain lighting and particles
	var weather: DayNightWeatherManager = WEATHER_SCRIPT.new()
	weather.is_dynamic_time = false
	preview.add_child(weather)

	# Allow preview scene and physics to initialize
	for frame in 30:
		await process_frame

	var camera := preview.get_node_or_null("OverviewCamera") as Camera2D
	if camera == null:
		camera = Camera2D.new()
		preview.add_child(camera)
	camera.make_current()

	var shots := [
		{"id": "corner", "pos": Vector2(650, 1020), "zoom": 1.15},
		{"id": "street", "pos": Vector2(850, 620), "zoom": 0.95},
		{"id": "overview", "pos": Vector2(845, 825), "zoom": 0.65},
		{"id": "gameplay", "pos": Vector2(650, 1080), "zoom": 1.55},
		{"id": "retail", "pos": Vector2(955, 1040), "zoom": 1.15}
	]

	var conditions := [
		{"name": "day", "time": 0.50, "weather": 0},
		{"name": "night", "time": 0.05, "weather": 0},
		{"name": "rain", "time": 0.50, "weather": 1}
	]

	for cond in conditions:
		weather.time_of_day = cond.time
		weather.set_weather(cond.weather)
		weather._update_lighting()
		
		var is_dark = (cond.name == "night")
		for lamp in preview.find_children("", "StreetLamp", true, false):
			lamp.set_lit(is_dark)

		# Let rain particles spawn if raining
		for frame in 20:
			await process_frame


		for shot in shots:
			camera.position = shot.pos
			camera.zoom = Vector2.ONE * shot.zoom
			for frame in 6:
				await process_frame
			await RenderingServer.frame_post_draw

			var out_path := "d:/geteco/game/tests/quadra_pilot_%s_%s_%s.png" % [phase, shot.id, cond.name]
			var img := root.get_texture().get_image()
			var err := img.save_png(out_path)
			assert(err == OK, "Failed to save screenshot: " + out_path)
			print("CAPTURED: " + out_path)

	print("ALL QUADRA PILOT CAPTURES COMPLETE for phase: " + phase)
	quit(0)
