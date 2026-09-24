extends SceneTree
## Rendered, no-save lighting/geometry diagnosis for the native V2 world.
## Captures identical places with a settled camera, camera motion, zoom, rotation,
## day and night. This is visual evidence, not a performance benchmark.

const OUTPUT_DIR := "res://evidence/lighting_glitch_review"
const DAY_TIME := 0.36
const NIGHT_TIME := 0.84

var world: Node3D
var output_dir := OUTPUT_DIR
var only_location := ""
var report: Dictionary = {
	"renderer": "",
	"gpu": "",
	"resolution": "",
	"locations": [],
}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Lighting glitch review requires rendered output")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=")
		if argument.begins_with("--only="):
			only_location = argument.trim_prefix("--only=")
		if argument.begins_with("--output-suffix="):
			var suffix := argument.trim_prefix("--output-suffix=").validate_filename()
			if not suffix.is_empty():
				output_dir += "-"+suffix
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for frame in 1200:
		await physics_frame
		if world.production != null and world.production.ready_for_play:
			break
	if world.production == null or not world.production.ready_for_play:
		push_error("Native V2 world did not become ready")
		quit(1)
		return
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.set_population(0)
	world.diagnostic_label.hide()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.gpu = RenderingServer.get_video_adapter_name()
	report.resolution = str(root.size)
	var garage: Vector3 = world.maciota_place.exterior_return + Vector3(0, 0, 2.5)
	var locations := [
		{"id":"garage_exterior", "position":garage, "move":Vector3(2.5,0,0), "heading":0.0},
		{"id":"nearby_streets", "position":garage+Vector3(31,0,-9), "move":Vector3(4,0,0), "heading":-PI/8.0},
		{"id":"south_port", "position":Vector3(3900.0/16.0,.08,3800.0/16.0), "move":Vector3(5,0,0), "heading":PI/8.0},
		{"id":"mountain_transition", "position":Vector3(452,.08,-285), "move":Vector3(8.5,0,0), "heading":-PI/2.0},
	]
	for location in locations:
		if not only_location.is_empty() and location.id != only_location:
			continue
		await capture_location(location)
	if "--probe-deck" in OS.get_cmdline_user_args():
		probe_deck()
	if "--measure-frames" in OS.get_cmdline_user_args():
		await measure_frames()
	var output := FileAccess.open(output_dir+"/capture-report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("LIGHTING_GLITCH_CAPTURE ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit()

func measure_frames() -> void:
	var night := "--measure-night" in OS.get_cmdline_user_args()
	await move_to(Vector3(452.0,.08,-285.0),-PI/2.0,28.0,true)
	set_time(NIGHT_TIME if night else DAY_TIME)
	world.session.weather.set_process(false)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(2.0).timeout
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	var stop := previous + 8000000
	while Time.get_ticks_usec() < stop:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous = now
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	var summary := {"frames":samples.size(),"mean_ms":total/samples.size(),
		"p50_ms":samples[int(samples.size()*.5)],"p95_ms":samples[int(samples.size()*.95)],
		"max_ms":samples[-1],"resolution":str(root.size),"gpu":report.gpu}
	var output := FileAccess.open(output_dir+("/bridge-benchmark-night.json" if night else "/bridge-benchmark.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(summary,"  "))
	output.close()
	print("BRIDGE_BENCHMARK ",JSON.stringify(summary))

func probe_deck() -> void:
	for node in world.find_children("*","MultiMeshInstance3D",true,false):
		var instance := node as MultiMeshInstance3D
		if instance.multimesh == null: continue
		for index in instance.multimesh.instance_count:
			var point := instance.global_transform * instance.multimesh.get_instance_transform(index).origin
			if point.x >= 430.0 and point.x <= 456.5 and absf(point.z + 285.0) < 7.5:
				print("DECK_PROP ",node.name," ",point)

func capture_location(location: Dictionary) -> void:
	await move_to(location.position, location.heading, 28.0, true)
	var location_report := {
		"id": location.id,
		"position": str(location.position),
		"move_end": str(location.position+location.move),
		"heading": location.heading,
		"conditions": [],
	}
	for light_condition in ["day", "night"]:
		set_time(DAY_TIME if light_condition == "day" else NIGHT_TIME)
		await create_timer(.45).timeout
		var prefix: String = output_dir+"/"+location.id+"-"+light_condition
		world.camera.heading = location.heading
		world.camera.target_size = 28.0
		await settle_camera(.65)
		var still_a := await capture(prefix+"-still-a.png")
		await create_timer(.45).timeout
		var still_b := await capture(prefix+"-still-b.png")
		var condition := {
			"light": light_condition,
			"time": DAY_TIME if light_condition == "day" else NIGHT_TIME,
			"still_difference": image_difference(still_a, still_b),
			"frames": [],
		}
		condition.frames.append(frame_state("still-a", world.player.position))
		condition.frames.append(frame_state("still-b", world.player.position))
		world.player.teleport(location.position+location.move+Vector3.UP*.08)
		world.production._update_physical_residency(world.player.position)
		await create_timer(.08).timeout
		await capture(prefix+"-camera-moving.png")
		condition.frames.append(frame_state("camera-moving", world.player.position))
		await settle_camera(.75)
		await capture(prefix+"-move-settled.png")
		condition.frames.append(frame_state("move-settled", world.player.position))
		world.camera.target_size = 16.0
		await settle_camera(.55)
		await capture(prefix+"-zoom-near.png")
		condition.frames.append(frame_state("zoom-near", world.player.position))
		world.camera.target_size = 46.0
		await settle_camera(.55)
		await capture(prefix+"-zoom-far.png")
		condition.frames.append(frame_state("zoom-far", world.player.position))
		world.camera.target_size = 28.0
		world.camera.heading = location.heading+PI/2.0
		await settle_camera(.65)
		await capture(prefix+"-rotated.png")
		condition.frames.append(frame_state("rotated", world.player.position))
		location_report.conditions.append(condition)
		await move_to(location.position, location.heading, 28.0, false)
	report.locations.append(location_report)

func move_to(point: Vector3, heading: float, camera_size: float, allow_streaming: bool) -> void:
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	if allow_streaming:
		for frame in 600:
			var ready := true
			for id in world.production.regions:
				if world.production.regions[id].pending.size() > 0:
					ready = false
					break
			if ready:
				break
			await process_frame
	world.player.teleport(point+Vector3.UP*.08)
	world.camera.heading = heading
	world.camera.target_size = camera_size
	world.camera.focus = world.player.position
	world.camera.initialized = true
	await settle_camera(.45)

func settle_camera(seconds: float) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func set_time(value: float) -> void:
	if world.session.weather == null:
		return
	world.session.weather.time_of_day = value
	world.session.weather.weather_state = 0
	world.production.state.world_state.time = value
	world.production.state.world_state.weather = 0
	world.session.weather._update()

func capture(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png(path)
	return picture

func image_difference(first: Image, second: Image) -> Dictionary:
	var samples := 0
	var changed := 0
	var sum := 0.0
	var maximum := 0.0
	for y in range(0, first.get_height(), 4):
		for x in range(0, first.get_width(), 4):
			var a := first.get_pixel(x,y)
			var b := second.get_pixel(x,y)
			var difference := absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
			samples += 1
			sum += difference
			maximum = maxf(maximum, difference)
			if difference > .04:
				changed += 1
	return {
		"sample_count": samples,
		"changed_samples": changed,
		"changed_ratio": float(changed)/maxi(1,samples),
		"mean_rgb_delta": sum/maxi(1,samples),
		"max_rgb_delta": maximum,
	}

func frame_state(label: String, player_position: Vector3) -> Dictionary:
	var regions := {}
	for id in world.production.regions:
		var region = world.production.regions[id]
		regions[id] = {
			"chunk_count": region.chunks.size(),
			"current_cell": str(region.current_cell),
			"pending_chunks": region.pending.size(),
		}
	return {
		"label": label,
		"player": str(player_position),
		"camera_position": str(world.camera.global_position),
		"camera_focus": str(world.camera.focus),
		"camera_size": world.camera.size,
		"camera_heading": world.camera.heading,
		"logical_region": world.production.state.region_id,
		"connection_loaded": is_instance_valid(world.production.connection),
		"regions": regions,
	}
