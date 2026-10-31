extends Node
## Só evidência visual: o custo da captura e o limite de 30 Hz invalidam o uso para FPS.
## Todo quadro renderizado é guardado como JPEG; cada fase também tem um PNG de referência.
const MAX_FRAMES := 2400
var world
var race
var output := ""
var segment := "day_static"
var recording := false
var samples: Array[Dictionary] = []
var failure := ""
var _started := 0
var _previous_stamp := 0
var _previous_render_frame := -1
var _phase_pngs: Dictionary = {}
var _skipped_render_frames := 0
var _old_max_fps := 60
var _old_size := Vector2i.ZERO
var _report: Dictionary = {}
var _frame_limit := MAX_FRAMES

func begin(scene, activity, requested_path: String = "", frame_limit: int = MAX_FRAMES) -> bool:
	world = scene
	race = activity
	if DisplayServer.get_name()=="headless": return false
	output = requested_path if not requested_path.is_empty() else "res://evidence/desert-drag-temporal-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	# A new directory below evidence prevents overwriting any previous session.
	var suffix := output.trim_prefix("res://evidence/")
	if not output.begins_with("res://evidence/") or suffix.is_empty() or suffix.contains("\\"): return false
	for component in suffix.split("/",true):
		if component in ["",".",".."]: return false
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)): return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))!=OK: return false
	_old_max_fps = Engine.max_fps
	_old_size = get_viewport().size
	Engine.max_fps = 30
	get_viewport().size = Vector2i(1280,720)
	_started = Time.get_ticks_usec()
	_previous_stamp = _started
	_frame_limit = clampi(frame_limit,1,7200)
	_report = {
		"purpose":"Temporal lighting/camera review; NOT a performance benchmark",
		"engine":Engine.get_version_info().string,
		"renderer":RenderingServer.get_current_rendering_method(),
		"gpu":RenderingServer.get_video_adapter_name(),
		"resolution":[1280,720],"vsync":DisplayServer.window_get_vsync_mode(),
		"msaa_3d":get_viewport().msaa_3d,"physics_ticks_per_second":Engine.physics_ticks_per_second,
		"capture_process_fps_cap":30,"previous_fps_cap":_old_max_fps,
		"bounded_frame_limit":_frame_limit,
		"capture_format":"JPEG quality 0.85 every rendered frame + first-phase PNG",
		"capture_overhead_included":true,"no_save":bool(world.session.controller.no_save),
		"clock_control":"Fixture fixes day/night and sweeps 0.72–0.90 in six seconds through the production weather updater",
		"coverage":"Main, desert strip: static day, continuous dusk, static night, two-car physical drag and cleanup",
		"not_covered":["whole town","bank interior","truck stop","rain","other car profiles","audible audio quality"],
		"visual_verdict":"pending manual frame inspection",
		"cadence_note":"Timestamps describe capture cadence only. Slow or skipped rendered frames limit flicker conclusions; no FPS approval is inferred."
	}
	_write_report(false)
	recording = true
	RenderingServer.frame_post_draw.connect(_capture)
	print("DESERT_DRAG_TEMPORAL output=",ProjectSettings.globalize_path(output))
	return true

func _phase() -> String:
	if segment=="drag" and is_instance_valid(race) and race.active:
		var result := "night_drag_"+str(race.phase)
		if world.session.modal: result += "_paused"
		return result
	return "night_cleanup" if segment=="drag" else segment

func _capture() -> void:
	if not recording: return
	var render_frame := Engine.get_frames_drawn()
	if render_frame==_previous_render_frame: return
	if samples.size()>=_frame_limit:
		failure = "Bounded capture limit reached before scenario ended"
		stop()
		return
	var now := Time.get_ticks_usec()
	var phase_name := _phase()
	var texture := get_viewport().get_texture()
	var frame := texture.get_image()
	if frame==null or frame.is_empty():
		failure = "Rendered viewport returned no image"
		stop()
		return
	var filename := "%05d.jpg"%samples.size()
	var began := Time.get_ticks_usec()
	var saved := frame.save_jpg(output.path_join(filename),.85)
	if saved!=OK:
		failure = "JPEG save failed: "+str(saved)
		stop()
		return
	if not _phase_pngs.has(phase_name):
		var png := phase_name.validate_filename()+".png"
		if frame.save_png(output.path_join(png))==OK: _phase_pngs[phase_name]=png
	var capture_usec := Time.get_ticks_usec()-began
	if _previous_render_frame>=0: _skipped_render_frames += maxi(0,render_frame-_previous_render_frame-1)
	var camera := get_viewport().get_camera_3d()
	var point: Vector3 = camera.global_position if is_instance_valid(camera) else Vector3.ZERO
	var player_point: Vector3 = world.player.global_position
	var emitters := {}
	var racers: Array[Dictionary] = []
	if is_instance_valid(race) and race.active:
		for index in race.racers.size():
			var car = race.racers[index].car
			if is_instance_valid(car) and is_instance_valid(camera):
				var screen := camera.unproject_position(car.global_position+Vector3.UP*.7)
				racers.append({"index":index,"position":[car.global_position.x,car.global_position.y,car.global_position.z],"screen":[screen.x,screen.y],"in_view":not camera.is_position_behind(car.global_position) and get_viewport().get_visible_rect().has_point(screen),"camera_distance":camera.global_position.distance_to(car.global_position)})
			if is_instance_valid(car) and is_instance_valid(car.equipment):
				var lights: Array[Dictionary] = []
				for mount in car.equipment.lamps:
					var lamp: Light3D = mount.lamp
					if is_instance_valid(lamp): lights.append({"enabled":lamp.is_visible_in_tree(),"energy":lamp.light_energy})
				var npc_beam: Light3D = car.equipment.npc_beam
				if is_instance_valid(npc_beam): lights.append({"npc_beam":true,"enabled":npc_beam.is_visible_in_tree(),"energy":npc_beam.light_energy})
				emitters[str(index)]={"requested":bool(car.equipment.headlights_on),"sources":lights}
	samples.append({
		"file":filename,"timestamp_usec":now,"seconds_since_start":float(now-_started)/1000000.0,
		"capture_gap_usec":now-_previous_stamp,"write_usec":capture_usec,
		"render_frame":render_frame,"physics_frame":Engine.get_physics_frames(),
		"phase":phase_name,"time_of_day":float(world.session.weather.time_of_day),
		"camera":str(camera.name) if is_instance_valid(camera) else "none",
		"camera_position":[point.x,point.y,point.z],
		"player_position":[player_point.x,player_point.y,player_point.z],
		"race_elapsed":float(race.elapsed) if is_instance_valid(race) else 0.0,
		"headlights":emitters,"racers":racers,
		"desert_neon":_neon_state(),
		"rival_indicator":int(race.hud.rival_offscreen) if is_instance_valid(race) and is_instance_valid(race.hud) else 0
	})
	_previous_stamp = now
	_previous_render_frame = render_frame
	# A bounded checkpoint preserves evidence if a later gameplay assertion fails.
	if samples.size()%150==0: _write_report(false)

func _neon_state() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for kit in get_tree().get_nodes_in_group("desert_car_neon"):
		if not is_instance_valid(kit.car): continue
		result.append({"car":kit.car.archetype,"strength":kit.strength,"grounded":kit.car.is_on_floor(),"source_visible":kit.ground_light.is_visible_in_tree(),"energy":kit.ground_light.light_energy,"pool_visible":kit.ground_pool.is_visible_in_tree(),"position":str(kit.car.global_position)})
	return result

func stop() -> Dictionary:
	if recording:
		recording = false
		if RenderingServer.frame_post_draw.is_connected(_capture): RenderingServer.frame_post_draw.disconnect(_capture)
		Engine.max_fps = _old_max_fps
		get_viewport().size = _old_size
	if not output.is_empty(): _write_report(true)
	return _report.duplicate(true)

func _write_report(complete: bool) -> void:
	var duration := 0.0
	if samples.size()>1: duration = float(samples.back().timestamp_usec-samples.front().timestamp_usec)/1000000.0
	_report["recording_complete"] = complete
	_report["failure"] = failure
	_report["frame_count"] = samples.size()
	_report["duration_seconds"] = duration
	_report["skipped_rendered_frames"] = _skipped_render_frames
	_report["phase_reference_pngs"] = _phase_pngs
	_report["frames"] = samples
	var file := FileAccess.open(output.path_join("sequence.json"),FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(_report,"\t"))
		file.close()

func _exit_tree() -> void:
	if recording: stop()
