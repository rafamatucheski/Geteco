extends SceneTree
const WEATHER := preload("res://systems/DayNightWeatherManager.gd")
const PALETTE := preload("res://systems/atmosphere/AtmospherePalette.gd")
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
	else: print("PASS ", label)

func _run() -> void:
	root.size = Vector2i(640, 360)
	root.content_scale_size = root.size
	var origin := Vector2(4300, -4960)
	check(is_zero_approx(PALETTE.mountain_weight(Vector2(6300, -4560), origin)), "Port approach keeps its own atmosphere")
	check(is_equal_approx(PALETTE.mountain_weight(Vector2(8800, -4560), origin), 1.0), "Mountain end of bridge has its full atmosphere")
	check(is_zero_approx(PALETTE.mountain_weight(Vector2(8000, 1700), origin)), "East city is not mistaken for the mountain")
	var seam_left := PALETTE.mountain_weight(Vector2(7299, -4560), origin)
	var seam_right := PALETTE.mountain_weight(Vector2(7301, -4560), origin)
	check(absf(seam_right - seam_left) < 0.003, "Crossing the streaming seam has no atmosphere step")
	check(PALETTE.summit_weight(Vector2(6650, 150)) < 0.05 and PALETTE.summit_weight(Vector2(6250, -2050)) > 0.99, "Altitude separates wooded foothills from snowy summit")
	check(PALETTE.resort_weight(Vector2(7190, -2730)) > 0.99 and is_zero_approx(PALETTE.resort_weight(Vector2(6250, -2050))), "Resort warmth stays local to the occupied precinct")
	var snow_profile: Dictionary = PALETTE.WINTER.sample(0.9, 1.0)
	var resort_profile: Dictionary = PALETTE.resort_sample(snow_profile, 1.0)
	check(resort_profile.sunlight_tint.r > snow_profile.sunlight_tint.r and resort_profile.shadow_tint == snow_profile.shadow_tint, "Resort warms highlights while keeping cold shadows")
	check(resort_profile.haze == snow_profile.haze and resort_profile.fog_color == snow_profile.fog_color, "Resort does not erase a snowstorm")
	var lot := Vector2(780, 700)
	check(PALETTE.cemetery_weight(Vector2.ZERO, lot) == 1.0 and PALETTE.cemetery_weight(Vector2(600, 0), lot) == 0.0, "Cemetery mood is local to its lot")
	check(absf(PALETTE.cemetery_weight(Vector2(389, 0), lot) - PALETTE.cemetery_weight(Vector2(391, 0), lot)) < 0.015, "Cemetery wall does not cause a color step")
	var cemetery_night: Dictionary = PALETTE.cemetery_sample(snow_profile, 1.0)
	check(cemetery_night.saturation < snow_profile.saturation and cemetery_night.sunlight_tint == snow_profile.sunlight_tint, "Cemetery mutes colors without removing warm lamps")
	check(cemetery_night.fog_color.get_luminance() < 0.2, "Cemetery night mist stays dark")
	check(PALETTE.cemetery_sample(snow_profile, 0.0) == snow_profile, "Outside cemetery retains the exact regional profile")
	for profile in [PALETTE.HARBOR, PALETTE.FOREST, PALETTE.WINTER, PALETTE.DESERT, PALETTE.COAST]:
		var night: Dictionary = profile.sample(0.0, 0.0)
		var midnight: Dictionary = profile.sample(1.0, 0.0)
		var noon: Dictionary = profile.sample(0.5, 0.0)
		var overcast: Dictionary = profile.sample(0.5, 1.0)
		check(night == midnight, profile.label + ": clock wraps continuously at midnight")
		check(noon.fog_color.get_luminance() > night.fog_color.get_luminance() * 2.0, profile.label + ": night fog cannot glow like daylight")
		check(overcast.haze > noon.haze and overcast.saturation < noon.saturation, profile.label + ": weather changes atmosphere as well as particles")
	check(PALETTE.DESERT.sunlight_tint.r > PALETTE.DESERT.sunlight_tint.b and PALETTE.DESERT.shadow_tint.b > PALETTE.DESERT.shadow_tint.r, "Desert combines warm sunlight with cooler shadows")
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(320, 180)
	camera.make_current()
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2.ZERO, Vector2(640,0), Vector2(640,360), Vector2(0,360)])
	ground.color = Color(0.5, 0.5, 0.5)
	world.add_child(ground)
	var weather := WEATHER.new()
	weather.is_dynamic_time = false
	weather.time_of_day = 0.5
	world.add_child(weather)
	weather.enable_regional_atmosphere()
	weather.enable_regional_atmosphere()
	check(get_nodes_in_group(&"regional_atmosphere").size() == 1, "Repeated enable never stacks composition passes")
	weather.set_weather(WEATHER.WeatherState.DRIZZLE)
	weather.set_regional_rain_exposure(0.0)
	check(not weather.is_raining() and not weather.rain_particles.emitting, "City rain stops fully inside mountain atmosphere")
	check(weather.weather_state == WEATHER.WeatherState.DRIZZLE, "Regional presentation preserves the saved city weather")
	weather.set_regional_rain_exposure(1.0)
	check(weather.is_raining(), "Returning to port restores city rain")
	weather.set_weather(WEATHER.WeatherState.STORM)
	weather.set_regional_rain_exposure(0.0)
	check(not weather.is_dark, "A city storm does not turn clear mountain noon into night")
	check(not weather._flash_tween.is_running(), "Leaving city weather cancels its lightning flash")
	weather.set_weather(WEATHER.WeatherState.CLEAR)
	weather.set_regional_rain_exposure(1.0)
	weather.set_interior_mode(true)
	weather.is_dynamic_time = true
	weather.time_of_day = 0.789
	weather._process(weather.day_length_seconds * 0.02)
	check(weather.time_of_day > 0.8 and weather.is_dark, "Clock and street-light state advance while player is indoors")
	check(weather.color.is_equal_approx(Color.WHITE), "Interior lighting stays independent of exterior night")
	weather.atmosphere._apply(0)
	check(not weather.atmosphere.visible and weather.atmosphere.copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "Interior disables fog, grading and screen copy")
	weather.time_of_day = 0.90
	weather.set_interior_mode(false)
	weather.atmosphere._apply(0)
	check(weather.atmosphere.visible and weather.color.b > weather.color.r, "Exit restores exterior presentation")
	weather.is_dynamic_time = false
	weather.time_of_day = 0.5
	weather._update_lighting()
	weather.atmosphere.refresh_immediately()
	var ui := CanvasLayer.new()
	ui.layer = 50
	world.add_child(ui)
	var ink := ColorRect.new()
	ink.color = Color(0.6, 0.3, 0.15)
	ink.position = Vector2(10, 10)
	ink.size = Vector2(50, 40)
	ui.add_child(ink)
	await process_frame
	var drift: Vector2 = weather.atmosphere._drift
	weather.process_mode = Node.PROCESS_MODE_PAUSABLE
	paused = true
	await create_timer(0.1, true).timeout
	check(weather.atmosphere._drift.is_equal_approx(drift), "Pausing freezes atmospheric movement")
	paused = false
	if DisplayServer.get_name() != "headless":
		# A real 3D object projected into the same canvas must receive the same grade.
		var viewport := SubViewport.new()
		viewport.size = Vector2i(64, 64)
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		world.add_child(viewport)
		var model := MeshInstance3D.new()
		model.mesh = BoxMesh.new()
		var surface := StandardMaterial3D.new()
		surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		surface.albedo_color = ground.color
		model.material_override = surface
		viewport.add_child(model)
		var camera3d := Camera3D.new()
		camera3d.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera3d.size = 1.5
		camera3d.position.z = 3.0
		viewport.add_child(camera3d)
		var projection := Sprite2D.new()
		projection.texture = viewport.get_texture()
		projection.position = Vector2(450, 180)
		world.add_child(projection)
		weather.atmosphere.set_process(false)
		weather.atmosphere.effect.set_shader_parameter("haze", 0.0)
		# Shader compilation and actual pixels, including UI exclusion.
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var ui_pixel := image.get_pixel(25, 25)
		check(absf(ui_pixel.r - ink.color.r) < 0.015 and absf(ui_pixel.b - ink.color.b) < 0.015, "HUD pixels bypass the atmosphere shader")
		var world_pixel := image.get_pixel(320, 180)
		check(world_pixel.r > 0.35 and world_pixel.r < 0.65, "Rendered world remains visible under grading")
		check(world_pixel.b > world_pixel.r, "Harbor shader gives neutral world shadows a cooler cast")
		var projected_pixel := image.get_pixel(450, 180)
		check(absf(projected_pixel.r - world_pixel.r) < 0.025 and absf(projected_pixel.b - world_pixel.b) < 0.025, "Projected 3D and 2D ground receive the same atmospheric treatment")
		DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/regional-atmosphere")
		image.save_png("D:/geteco/artifacts/regional-atmosphere/shader-contract.png")
	world.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("REGIONAL_ATMOSPHERE failures=", failures)
	quit(0 if failures == 0 else 1)
