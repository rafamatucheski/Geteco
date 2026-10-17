extends "res://tests/measure/measure.gd"
## Build Harbor.csproj with the project's .NET SDK before running Godot 4.7.2 mono.
## --no-save --skip-arrival --benchmark --population=24 --output-dir=<unique path>
## --only=quay-day|quay-night|canal-day|canal-night filters scenarios.
## --temporal captures every rendered frame separately from performance sampling.
## Default: original/pilot pairs, then two temporal pilot recordings in one session.
## --pilot selects one candidate measurement; --temporal selects one recording pass.
## --uncapped is optional diagnosis; normal gameplay settings remain the default.

const WATER_PILOT := preload("res://world/regions/HarborWaterPilot.gd")

var output_dir := ""
var only_site := ""
var temporal := false
var photos := false
var last_summary: Dictionary = {}

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or not ClassDB.class_exists("CSharpScript"):
		push_error("Water validation requires rendered Godot .NET and --no-save")
		quit(2)
		return
	for arg in args:
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
		if arg.begins_with("--only="): only_site = arg.trim_prefix("--only=")
	temporal = "--temporal" in args
	photos = "--photos" in args
	# Explicit A/B switch: original production shaders versus the bounded quay pilot.
	# Never reconstruct the obsolete box-water baseline.
	WATER_PILOT.enabled = "--pilot" in args
	if output_dir.is_empty() or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)):
		push_error("Supply a unique, nonexistent --output-dir; previous evidence is never overwritten")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) != OK:
		quit(2)
		return
	seed(16102026)
	root.size = Vector2i(1280,720)
	if "--uncapped" in args:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled and root.get_node_or_null("LoadingCurtain") == null: break
	if world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled or root.get_node_or_null("LoadingCurtain") != null:
		push_error("Production session did not become ready within 180 seconds")
		quit(3)
		return
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.urban_operations.security.authorized_visit = true
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.session.weather.set_process(false)
	var sites := [
		{"id":"quay-day","point":Vector3(202,.08,219),"heading":PI*.5,"time":.32},
		{"id":"quay-night","point":Vector3(202,.08,219),"heading":PI*.5,"time":.93},
		{"id":"canal-day","point":Vector3(280,.08,80),"heading":PI*.5,"time":.32},
		{"id":"canal-night","point":Vector3(280,.08,80),"heading":PI*.5,"time":.93},
		{"id":"shore-day","point":Vector3(268,.08,203),"heading":0.0,"time":.32,"optional":true},
		{"id":"shore-night","point":Vector3(268,.08,203),"heading":0.0,"time":.93,"optional":true}]
	var paired := not temporal and "--pilot" not in args
	var visited := 0
	for site in sites:
		if only_site.is_empty() and site.get("optional",false): continue
		if not only_site.is_empty() and only_site != site.id: continue
		visited += 1
		if paired:
			var original_summary: Dictionary = {}
			for pilot in [false,true]:
				set_pilot(pilot)
				if not await measure_site(site,site.id+("-pilot" if pilot else "-original"),false): return
				if not pilot: original_summary = last_summary.duplicate()
			# One finite reversed-order confirmation, only for the changed quay.
			# Never repeat until a desirable number appears.
			if not photos and site.id.begins_with("quay-") and (last_summary.p95_ms > original_summary.p95_ms * 1.05 or last_summary.p99_ms > original_summary.p99_ms * 1.05):
				for pilot in [true,false]:
					set_pilot(pilot)
					if not await measure_site(site,site.id+("-confirm-pilot" if pilot else "-confirm-original"),false): return
		else:
			if not await measure_site(site,site.id,temporal): return
	if visited == 0:
		push_error("Unknown --only scenario")
		quit(2)
		return
	if paired and not photos:
		set_pilot(true)
		for site in sites:
			if site.id in ["quay-day","shore-night"]:
				if not await measure_site(site,site.id+"-pilot-temporal",true): return
	world.queue_free()
	await process_frame
	quit()

func set_pilot(active: bool) -> void:
	WATER_PILOT.enabled = active
	var region = world.production.region
	var ocean = region.harbor_ocean
	if active and ocean.pilot_material == null:
		ocean.pilot_material = WATER_PILOT.make_material(WATER_PILOT.SURFACE)
	if active and ocean.shore_wash.pilot_material == null:
		ocean.shore_wash.pilot_material = WATER_PILOT.make_material(WATER_PILOT.SHORE)
	for key in region.chunks:
		var chunk: Node3D = region.chunks[key]
		var rect := Rect2(key.x*64,key.y*64,64,64)
		var selected := WATER_PILOT.includes_chunk(rect)
		var water := chunk.get_node_or_null("Water") as MeshInstance3D
		var shore := chunk.get_node_or_null("Water/ShoreWash") as MeshInstance3D
		if water != null: water.material_override = ocean.pilot_material if selected else ocean.material
		if shore != null: shore.material_override = ocean.shore_wash.pilot_material if selected else ocean.shore_wash.material

func measure_site(site: Dictionary, output_id: String, record_temporal: bool) -> bool:
	world.player.teleport(site.point)
	world.production.region.set_focus(site.point)
	world.camera.heading = site.heading
	world.camera.target_size = 42
	world.camera.initialized = false
	world.session.weather.time_of_day = site.time
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	world.session.weather._process(0)
	var warm := await sample_frames(8.0)
	var report := environment_report(site)
	report.other_godot_before = other_renderers()
	report.output_id = output_id
	report.pilot_enabled = WATER_PILOT.enabled
	report.warmup = stats(warm)
	report.warmup_ms = warm
	if photos:
		report.capture_only = true
	elif record_temporal:
		var capture_site := site.duplicate()
		capture_site.id = output_id
		report.temporal = await capture_temporal(capture_site)
	else:
		var measured := await sample_frames(30.0)
		report.summary = stats(measured)
		last_summary = report.summary
		report.frames_ms = measured
	report.other_godot_after = other_renderers()
	report.isolated_at_boundaries = report.other_godot_before.is_empty() and report.other_godot_after.is_empty()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir+"/"+output_id+".png")
	report.final_position = str(world.player.global_position)
	report.health = world.gameplay.health
	report.place = world.session.state.place_id
	FileAccess.open(output_dir+"/"+output_id+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WATER_NATURAL ",output_id," ",JSON.stringify(report.get("summary",report.get("temporal",{}))))
	if world.gameplay.health <= 0 or not world.session.state.place_id.is_empty():
		push_error("Invalid gameplay state during water validation")
		quit(4)
		return false
	return true

func other_renderers() -> Array:
	var output: Array = []
	var command := "$ErrorActionPreference = 'Stop'; $waterCurrent = Get-CimInstance Win32_Process -Filter 'ProcessId = %d'; Get-CimInstance Win32_Process | Where-Object { ($_.Name -like 'Godot*.exe' -or $_.Name -eq 'GetecoV2.exe' -or $_.ExecutablePath -like 'D:\\geteco\\game\\*.exe') -and $_.ProcessId -ne $waterCurrent.ProcessId -and $_.ProcessId -ne $waterCurrent.ParentProcessId } | Select-Object ProcessId,Name,ExecutablePath | ConvertTo-Json -Compress" % OS.get_process_id()
	var code := OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),output,true)
	var raw := "".join(output).strip_edges()
	if code != 0: return [{"inventory_error":code,"output":raw}]
	if raw.is_empty(): return []
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Array: return parsed
	if parsed is Dictionary: return [parsed]
	return [{"inventory_error":"unparseable","output":raw}]

func sample_frames(seconds: float) -> Array[float]:
	var frames: Array[float] = []
	var last := Time.get_ticks_usec()
	var until := last+int(seconds*1000000)
	while Time.get_ticks_usec() < until:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last = now
	return frames

func environment_report(site: Dictionary) -> Dictionary:
	return {"scenario":site.id,"point":str(site.point),"heading":site.heading,"camera_size":42,
		"time":site.time,"weather":0,"seed":16102026,"engine":Engine.get_version_info().string,
		"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,
		"msaa":root.msaa_3d,"population":world.people.size(),"traffic_children":world.traffic.get_child_count(),
		"arguments":OS.get_cmdline_user_args(),"target_frame_ms":16.67,"regression_confirmation_pct":5,
		"notes":"Compare only equivalent runs without concurrent benchmarks. Temporal readback has capture overhead and cannot certify performance. No legacy material substitution. Paired runs share one live world; traffic/NPC positions evolve between samples, so this is not a restored population snapshot."}

func capture_temporal(site: Dictionary) -> Dictionary:
	var folder: String = output_dir+"/"+str(site.id)+"-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var records: Array[Dictionary] = []
	var begin := Time.get_ticks_usec()
	var previous_draw := Engine.get_frames_drawn()
	var skipped := 0
	while Time.get_ticks_usec()-begin < 30000000:
		await RenderingServer.frame_post_draw
		var timestamp := Time.get_ticks_usec()
		var drawn := Engine.get_frames_drawn()
		skipped += maxi(0,drawn-previous_draw-1)
		previous_draw = drawn
		var name := "%05d.jpg" % records.size()
		var error := root.get_texture().get_image().save_jpg(folder+"/"+name,.9)
		records.append({"file":name,"time_ms":(timestamp-begin)/1000.0,"drawn":drawn,"save_error":error})
		# Static first 10 s, gentle rotation through 20 s, then return to the initial view.
		var elapsed := (timestamp-begin)/1000000.0
		world.camera.heading = site.heading+(.22*sin((elapsed-10.0)*PI/10.0) if elapsed>10.0 else 0.0)
	FileAccess.open(folder+"/timestamps.json",FileAccess.WRITE).store_string(JSON.stringify(records))
	return {"seconds":(Time.get_ticks_usec()-begin)/1000000.0,"captured_frames":records.size(),
		"skipped_rendered_frames":skipped,"cadence":"Every rendered frame, synchronous readback; inspect actual timestamps for capture slowdown", "folder":folder}
