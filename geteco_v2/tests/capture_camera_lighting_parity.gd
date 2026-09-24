extends SceneTree

## Rendered V2 reference at the productive CameraRig scale. Uses Main with the
## --no-save contract and does not mutate player settings or personal saves.

const OUTPUT_BASE := "C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c5d4-0aa6-7ba0-819f-d0c3afa28d07/camera-lighting-0922"
const GARAGE_CENTER := Vector3(750.0/16.0, .08, 1644.0/16.0)
const SOUTH_PORT_CENTER := Vector3(3900.0/16.0, .08, 3800.0/16.0)

var world: Node3D
var output_root := OUTPUT_BASE+"/v2-before"
var report: Dictionary = {"version":"v2-before", "resolution":"1280x720", "shots":[]}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("V2 parity capture requires rendered output")
		quit(2)
		return
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("V2 parity capture requires --no-save")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			var label := argument.trim_prefix("--label=").validate_filename()
			if not label.is_empty():
				output_root = OUTPUT_BASE+"/v2-"+label
				report.version = "v2-"+label
	DirAccess.make_dir_recursive_absolute(output_root)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for frame in 1800:
		await physics_frame
		if world.production != null and world.production.ready_for_play:
			break
	if world.production == null or not world.production.ready_for_play:
		push_error("V2 world did not become ready")
		quit(1)
		return
	for frame in 600:
		await physics_frame
		if world.session != null and world.session.weather != null:
			break
	if world.session == null or world.session.weather == null:
		push_error("V2 weather did not become ready")
		quit(1)
		return
	world.set_population(0)
	world.hud.hide()
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	await _capture_conditions("garage", GARAGE_CENTER)
	await _capture_conditions("south_port", SOUTH_PORT_CENTER)
	world.production.state.grant_weapon("pistol")
	world.production.state.add_ammo("pistol", 24)
	world.production.state.equip_weapon("pistol")
	await _set_condition(.45, 0)
	await _move_to(GARAGE_CENTER)
	for frame in 20:
		await physics_frame
	await _save("garage-day-pistol")
	var file := FileAccess.open(output_root+"/report.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write V2 capture report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	world.queue_free()
	await process_frame
	quit(0)

func _capture_conditions(id: String, point: Vector3) -> void:
	for condition in [
		{"id":"day", "time":.45, "weather":0},
		{"id":"night", "time":.90, "weather":0},
		{"id":"rain", "time":.45, "weather":1},
	]:
		await _set_condition(condition.time, condition.weather)
		await _move_to(point)
		await _save(id+"-"+condition.id)

func _set_condition(time: float, state: int) -> void:
	world.session.weather.time_of_day = time
	world.session.weather.weather_state = state
	world.production.state.world_state.time = time
	world.production.state.world_state.weather = state
	world.session.weather._update()
	for frame in 12:
		await process_frame

func _move_to(point: Vector3) -> void:
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	for frame in 600:
		var ready := true
		for id in world.production.regions:
			if world.production.regions[id].pending.size() > 0:
				ready = false
				break
		if ready:
			break
		await process_frame
	world.player.teleport(point)
	world.camera.target = world.player
	world.camera.heading = 0.0
	world.camera.offset = world.camera.EXTERIOR_OFFSET
	world.camera.locked = false
	world.camera.initialized = false
	world.camera._external_size_target_id = 0
	for frame in 30:
		await process_frame

func _save(id: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output_root+"/"+id+".png"
	var result := root.get_texture().get_image().save_png(path)
	var human_pixels: float = world.camera.unproject_position(world.player.global_position+Vector3.UP*1.8).distance_to(world.camera.unproject_position(world.player.global_position))
	report.shots.append({
		"id":id,
		"path":path,
		"error":result,
		"time":world.session.weather.time_of_day,
		"weather":world.session.weather.weather_state,
		"camera_size":world.camera.size,
		"camera_focus":str(world.camera.focus),
		"human_1_8m_pixels":human_pixels,
		"pending_chunks":_pending_chunks(),
	})
	if result != OK:
		push_error("Cannot save "+path+": "+str(result))
	else:
		print("CAMERA_LIGHTING_V2 ", path)

func _pending_chunks() -> int:
	var count := 0
	for id in world.production.regions:
		count += world.production.regions[id].pending.size()
	return count
