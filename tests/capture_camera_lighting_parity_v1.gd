extends SceneTree

## Rendered V1 reference at the productive on-foot camera scale. The preview
## scene is intentionally used instead of HarborGame so no save/session state
## can be loaded or written.

const OUTPUT_ROOT := "C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c5d4-0aa6-7ba0-819f-d0c3afa28d07/camera-lighting-0922/v1"
const GARAGE_CENTER := Vector2(750, 1644)
const SOUTH_PORT_CENTER := Vector2(3900, 3800)

var preview: Node2D
var player: CharacterBody2D
var camera: Camera2D
var weather: DayNightWeatherManager
var report: Dictionary = {"version":"v1", "resolution":"1280x720", "shots":[]}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("V1 parity capture requires rendered output")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT_ROOT)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	preview = load("res://world/harbor/HarborPreview.tscn").instantiate()
	preview.review_mode = true
	root.add_child(preview)
	for frame in 1800:
		await process_frame
		if preview.world_build_ready:
			break
	if not preview.world_build_ready:
		push_error("V1 Harbor preview did not become ready")
		quit(1)
		return
	player = preview.get_node("Player")
	camera = player.get_node("Camera")
	weather = preview.weather
	weather.is_dynamic_time = false
	if is_instance_valid(preview._panel):
		preview._panel.hide()
	if is_instance_valid(preview._status):
		preview._status.hide()
	preview.get_node("OverviewCamera").enabled = false
	camera.enabled = true
	camera.make_current()
	camera.set_process(false)
	player.set_physics_process(false)
	await _capture_conditions("garage", GARAGE_CENTER)
	await _capture_conditions("south_port", SOUTH_PORT_CENTER)
	player.weapon_inventory["pistol"] = true
	player.weapon_ammo["pistol"] = {"clip":12, "reserve":24}
	player.equip_weapon("pistol")
	await _set_condition(.45, DayNightWeatherManager.WeatherState.CLEAR)
	await _move_to(GARAGE_CENTER)
	await _save("garage-day-pistol")
	var file := FileAccess.open(OUTPUT_ROOT+"/report.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write V1 capture report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	quit(0)

func _capture_conditions(id: String, point: Vector2) -> void:
	for condition in [
		{"id":"day", "time":.45, "weather":DayNightWeatherManager.WeatherState.CLEAR},
		{"id":"night", "time":.90, "weather":DayNightWeatherManager.WeatherState.CLEAR},
		{"id":"rain", "time":.45, "weather":DayNightWeatherManager.WeatherState.DRIZZLE},
	]:
		await _set_condition(condition.time, condition.weather)
		await _move_to(point)
		await _save(id+"-"+condition.id)

func _set_condition(time: float, state: int) -> void:
	weather.time_of_day = time
	weather.set_rain_intensity(.22)
	weather.set_weather(state)
	weather.set_biome(weather.current_biome)
	for frame in 12:
		await process_frame

func _move_to(point: Vector2) -> void:
	player.global_position = point
	player.velocity = Vector2.ZERO
	camera.position = Vector2.ZERO
	camera.zoom = Vector2.ONE * camera.zoom_close
	camera.reset_physics_interpolation()
	camera.reset_smoothing()
	camera.force_update_scroll()
	for frame in 20:
		await process_frame

func _save(id: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUTPUT_ROOT+"/"+id+".png"
	var result := root.get_texture().get_image().save_png(path)
	var rig_image: Image = player.viewport_3d.get_texture().get_image()
	var rig_pixels: Rect2i = rig_image.get_used_rect()
	var apparent_rig_height: float = float(rig_pixels.size.y) * float(player.sprite_3d_display.scale.y) * camera.zoom.y
	if result != OK:
		push_error("Cannot save "+path+": "+str(result))
		report.shots.append({"id":id, "error":result})
		return
	report.shots.append({
		"id":id,
		"path":path,
		"time":weather.time_of_day,
		"weather":weather.weather_state,
		"camera_zoom":camera.zoom.x,
		"camera_center":str(camera.get_screen_center_position()),
		"rig_alpha_height":rig_pixels.size.y,
		"apparent_rig_height_pixels":apparent_rig_height,
	})
	print("CAMERA_LIGHTING_V1 ", path)
