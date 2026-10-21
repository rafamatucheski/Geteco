extends SceneTree
## Before/after actual Digo room presentation, same Main/car/save/cameras.
## Baseline is captured before connecting new props/materials/music. No legacy UI.
## Stable samples exclude JPEG/PNG encoding. Never run concurrently.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://runtime/GameState.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
const DRIVE := preload("res://runtime/desert/DigoWorkshopDrive.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const CAR_ID := "measure_digo_service_car"
const CAR_TYPE := "desert_coyote"
const TUNED := {"paint":"paint_ocean","finish":"finish_satin","spoiler":"spoiler_sport","sunroof":"sunroof_glass","taillights":"taillights_amber","wheel_model":"wheel_mesh","wheel_size":"wheel_size_sport","wheels":"wheels_bronze"}
var world: Node3D
var folder := ""
var path := ""
var old_path := ""
var _temporal := false
var _capture_only := false
var _temporal_day_only := false
var _hide_diagnostics := false
var _cases: Array[String] = ["live_tuned","room_occupied","night_service"]
var _report: Dictionary = {}
var _stationary_case := false

func _initialize() -> void:
	create_timer(360).timeout.connect(func(): push_error("DIGO_MEASURE timeout"); _finish(3))
	_run.call_deferred()

func _seed() -> Dictionary:
	var state := STATE.new()
	if not state.restore_snapshot(FIXTURE.full_snapshot(Vector3(-137.8,.08,-942),true)): return {}
	state.set_location("desert",DRIVE.PLACE)
	state.checkpoint_id = DRIVE.PLACE
	state.world_state.erase("pedestrian")
	state.world_state.time = .55
	DIGO.complete_desert_race(state.world_state,DIGO.DESERT_RACE_ID,true)
	state.economy.grant_reward("measure_digo_funds",100000)
	state.world_state.vehicles = [{"archetype":CAR_TYPE,"vehicle_id":CAR_ID,"was_driven":true,"paint":"284d79ff","position":[0,.12,-2400],"yaw":PI,"health":float(preload("res://runtime/FleetCatalog.gd").spec(CAR_TYPE).durability),"region":"desert","equipment":{}}]
	state.world_state[DRIVE.KEY] = {"version":1,"vehicle_id":CAR_ID,"garage_owned":false,"was_driven":true}
	return state.snapshot()

func _run() -> void:
	TranslationServer.set_locale("pt_BR")
	if DisplayServer.get_name() == "headless": push_error("Rendered renderer required"); _finish(2); return
	if "--no-save" in OS.get_cmdline_user_args(): push_error("Use isolated fixture without --no-save"); _finish(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): folder = argument.trim_prefix("--output=")
		if argument == "--digo-temporal": _temporal = true
		if argument == "--capture-only": _capture_only = true
		if argument == "--temporal-day-only": _temporal_day_only = true
		if argument == "--hide-diagnostics": _hide_diagnostics = true
		if argument.begins_with("--cases="):
			_cases.clear()
			for variant in argument.trim_prefix("--cases=").split(",",false):
				if variant not in ["live_tuned","room_occupied","night_service"]: push_error("Unknown case: "+variant); _finish(2); return
				_cases.append(variant)
	if folder.is_empty(): folder = FIXTURE.output_dir("measure-digo-workshop-refresh")
	if DirAccess.make_dir_recursive_absolute(folder) != OK: push_error("Cannot create output folder"); _finish(2); return
	path = FIXTURE.write_fixture(folder,"checkpoint.json",_seed())
	if path.is_empty(): push_error("Isolated benchmark fixture rejected"); _finish(1); return
	var launch := root.get_node_or_null("V2Launch")
	if launch == null: push_error("Missing launch autoload"); _finish(1); return
	old_path = str(launch.selected_path)
	launch.selected_path = path
	# Control the same 1280x720 viewport throughout startup too. User display
	# preferences can change in concurrent sessions; never persist this override.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	# Deterministic read-only capture: real desktop input must not navigate the
	# panel while the runner records it. Main UI interaction has its own runner.
	root.gui_disable_input = true
	seed(19102026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	var boot_started := Time.get_ticks_msec()
	var boot_stages: Array[Dictionary] = []
	var last_stage := ""
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		var curtain := world.get_node_or_null("LoadingCurtain")
		var stage: String = str(curtain.get("stage_message")) if is_instance_valid(curtain) else "curtain_absent"
		if stage != last_stage:
			var observed := {"elapsed_ms":Time.get_ticks_msec()-boot_started,"stage":stage}
			boot_stages.append(observed)
			print("DIGO_MEASURE_BOOT ",JSON.stringify(observed))
			last_stage = stage
		if _boot_complete() and world.driving.occupied: break
	if not _boot_complete() or not world.driving.occupied or world.session.state.place_id != DRIVE.PLACE:
		_report = {"failed_phase":"bootstrap","elapsed_ms":Time.get_ticks_msec()-boot_started,"stages":boot_stages,"diagnostic":_boot_diagnostic()}
		_write_report()
		print("DIGO_MEASURE_BOOT_FAILED ",JSON.stringify(_report))
		push_error("Actual Main seated workshop restore failed"); _finish(1); return
	if world.production.store.path != path or world.production.no_save: push_error("Fixture save isolation failed"); _finish(1); return
	print("DIGO_MEASURE startup_streaming_settled=",world.production.startup_streaming_settled,"; residual streaming, if any, remains active during warmup and samples")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	world.gameplay.god_mode = true
	world.session.weather.time_of_day = .55
	world.session.weather.weather_state = 0
	world.session.weather.weather_locked = true
	world.session.weather._update()
	world.session.weather.set_process(false)
	world.diagnostic_label.hide()
	if _hide_diagnostics:
		var settings := root.get_node_or_null("V2Settings")
		if settings != null and is_instance_valid(settings.get("_fps_layer")): settings.get("_fps_layer").visible = false
		var watermark := root.get_node_or_null("BuildWatermark")
		if watermark is CanvasLayer: watermark.visible = false
	for frame in 6: await process_frame
	_report = {"scene":"res://Main.tscn","place":DRIVE.PLACE,"car":CAR_TYPE,"identity":CAR_ID,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"window_size":str(DisplayServer.window_get_size()),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"time_of_day":.55,"weather_state":0,"sample_kind":"before/after actual room presentation; no cloned showroom or legacy panel","source_hashes":_source_hashes(),"temporal_requested":_temporal,"cases":[],"population_start":world.people.size(),"vehicles_start":world.production.vehicles.size()}
	_report["startup_streaming_settled"] = world.production.startup_streaming_settled
	_report["user_arguments"] = OS.get_cmdline_user_args()
	_report["startup_note"] = "Boot and curtain release checked independently; false settled flag means residual streaming remains enabled, not an empty queue."
	_report["capture_only"] = _capture_only
	_report["diagnostic_overlays_hidden"] = _hide_diagnostics
	_report["stationary_fixture_note"] = "Ordinary room sample keeps real physics active and locks physical controller input; motion, fall, place and seated identity are checked every sampled frame. Earlier unguarded room/night baseline samples are invalid after vehicle fell from room."
	_report["boot_elapsed_ms"] = Time.get_ticks_msec()-boot_started
	_report["boot_stages"] = boot_stages
	for variant in _cases:
		var opened := Time.get_ticks_usec()
		_show_case(variant)
		await RenderingServer.frame_post_draw
		var first_present_ms := float(Time.get_ticks_usec()-opened)/1000.0
		var warmup := await _sample(1.0 if _capture_only else 5.0)
		await _capture(variant+".png")
		var stable: Dictionary = {"summary":{"not_measured":"capture-only"}}
		if not _capture_only: stable = await _sample(30.0)
		var camera := root.get_camera_3d()
		var data := {"variant":variant,"first_present_ms":first_present_ms,"warmup":warmup,"stable":stable,"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"population":world.people.size(),"vehicles":world.production.vehicles.size(),"camera_transform":str(camera.global_transform) if is_instance_valid(camera) else "none","screenshot":folder.path_join(variant+".png"),"room_inventory":_room_inventory(),"time_of_day":world.session.weather.time_of_day}
		_report.cases.append(data)
		print("DIGO_MEASURE ",variant," ",JSON.stringify(stable.summary))
		_write_report()
	if "live_tuned" in _cases:
		_show_case("live_tuned")
		for slot in ["wheel_model","spoiler","sunroof","taillights"]:
			world.session.desert.tuning_panel._select_slot(slot)
			world.session.desert.workshop_drive.focus_slot(slot)
			await _sample(.2)
			await _capture("focus-"+slot+".png")
		world.session.desert.workshop_drive.focus_slot("wheel_model")
		for angle in [-.95,0.0,.95]:
			world.session.desert.workshop_drive._yaw = angle
			world.session.desert.workshop_drive._update_camera()
			await _capture("orbit-extreme-"+str(angle)+".png")
	if _temporal:
		_show_case("live_tuned")
		await _sample(2.0)
		_report["temporal"] = await _capture_temporal()
		_write_report()
		if not _temporal_day_only:
			_show_case("night_service")
			await _sample(2.0)
			_report["temporal_night"] = await _capture_temporal("night-service")
			_write_report()
	_finish(0)

func _boot_complete() -> bool:
	if not is_instance_valid(world) or world.get("session") == null or world.get("production") == null: return false
	var curtain := world.get_node_or_null("LoadingCurtain")
	return world.session.ready_for_play and world.production.ready_for_play and (curtain == null or curtain.is_queued_for_deletion())

func _boot_diagnostic() -> Dictionary:
	var data := {"world_valid":is_instance_valid(world)}
	if not is_instance_valid(world): return data
	var curtain := world.get_node_or_null("LoadingCurtain")
	data["curtain"] = {"present":is_instance_valid(curtain),"stage":str(curtain.get("stage_message")) if is_instance_valid(curtain) else "absent","queued_for_deletion":curtain.is_queued_for_deletion() if is_instance_valid(curtain) else false}
	if world.get("production") != null:
		data["production"] = {"ready":world.production.ready_for_play,"startup_streaming_settled":world.production.startup_streaming_settled,"save_invalid":world.production.save_invalid,"save_invalid_reason":world.production.save_invalid_reason}
	if world.get("session") != null:
		var session = world.session
		data["session"] = {"ready":session.ready_for_play,"region":session.state.region_id,"place":session.state.place_id,"modal":session.modal,"transition":str(session.transition_kind),"room_valid":is_instance_valid(session.room),"restoring_saved_driver":session._restoring_saved_driver}
		if session.get("desert") != null and session.desert.get("workshop_drive") != null: data["workshop_restore"] = session.desert.workshop_drive.restore_diagnostic.duplicate(true)
	if world.get("driving") != null:
		data["occupied"] = world.driving.occupied
		data["body_transition_active"] = world.driving.is_body_transition_active()
		var car: CharacterBody3D = world.driving.car
		if is_instance_valid(car): data["car"] = {"identity":car.vehicle_id,"archetype":car.archetype,"position":str(car.global_position),"yaw":car.rotation.y,"health":car.health,"input_locked":car.input_locked,"physics_processing":car.is_physics_processing(),"visible":car.is_visible_in_tree(),"garage_place":str(car.get_meta("garage_place","")),"collision_layer":car.collision_layer}
	return data

func _show_case(variant: String) -> void:
	var session = world.session
	session.close_menu()
	session.weather.time_of_day = .0 if variant == "night_service" else .55
	session.weather._update()
	var car: CharacterBody3D = world.driving.car
	var parts: Dictionary = TUNED.duplicate(true)
	ADAPTER.attach(car,parts)
	_stationary_case = variant == "room_occupied"
	# This is a stationary visual/performance sample, not a driving test. Keep
	# physics active but reject physical keyboard/controller input during it.
	if _stationary_case:
		car.input_locked = true
		return
	session._menu("Digo")
	session.panel.hide()
	session.desert.tuning_car = car
	session.desert._workshop_site = "town"
	session.menu_closed = session.desert._dismiss_tuning
	session.desert.tuning_panel.set_live_vehicle(car)
	session.desert.tuning_panel.show_vehicle(ADAPTER.profile_of(car),parts,parts.values(),10,100000,{"archetype":car.archetype,"paint":car.paint_color})
	session.desert.workshop_drive.open_service_view(car)
	session.desert.tuning_panel.show_visual_menu()
	session.desert.workshop_drive.camera_action("reset",0.0)

func _source_hashes() -> Dictionary:
	var hashes := {}
	for source in ["res://world/desert/DesertWorkshopInterior.gd","res://world/desert/DesertInteriorFinish.gd","res://world/desert/DigoWorkshopProps.gd","res://world/desert/DigoWorkshopMaterials.gd","res://audio/workshop/DigoWorkshopMusic.gd","res://audio/WorldAudio.gd","res://runtime/desert/DesertRuntime.gd","res://runtime/desert/DigoWorkshopDrive.gd"]:
		if FileAccess.file_exists(source): hashes[source] = FileAccess.get_sha256(source)
	return hashes

func _room_inventory() -> Dictionary:
	var result := {"lights":[],"meshes":0,"surfaces":0,"triangles":0,"audio":[]}
	if not is_instance_valid(world.session.room): return result
	for light: Light3D in world.session.room.find_children("*","Light3D",true,false):
		result.lights.append({"path":str(world.session.room.get_path_to(light)),"visible":light.is_visible_in_tree(),"energy":light.light_energy,"color":str(light.light_color),"shadows":light.shadow_enabled,"range":light.omni_range if light is OmniLight3D else -1.0})
	for part: MeshInstance3D in world.session.room.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or not part.is_visible_in_tree(): continue
		result.meshes += 1
		result.surfaces += part.mesh.get_surface_count()
		for surface in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			if arrays.size()<=Mesh.ARRAY_INDEX: continue
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			result.triangles += int((indices.size() if not indices.is_empty() else vertices.size())/3)
	for player: AudioStreamPlayer in world.find_children("*","AudioStreamPlayer",true,false):
		if player.playing: result.audio.append({"path":str(world.get_path_to(player)),"bus":player.bus,"volume_db":player.volume_db,"stream":player.stream.resource_path if player.stream != null else ""})
	return result

func _sample(seconds: float) -> Dictionary:
	var values: Array[float] = []
	var focused := 0
	var started := Time.get_ticks_usec()
	var last := started
	while Time.get_ticks_usec()-started < int(seconds*1000000.0):
		await process_frame
		var car: CharacterBody3D = world.driving.car
		if not world.driving.occupied or world.session.state.place_id != DRIVE.PLACE or not is_instance_valid(car) or car.vehicle_id != CAR_ID or Vector2(car.global_position.x,car.global_position.z+2400).length() > .25 or car.global_position.y < -.3:
			_report["failed_phase"] = "stationary_sample_invariant"
			_report["diagnostic"] = _boot_diagnostic()
			_report["input"] = str(root.get_node("GameInput").vehicle_input())
			_write_report()
			push_error("DIGO_MEASURE stationary fixture moved or left workshop; sample invalid")
			_finish(1)
			return {"summary":{"invalid":true}}
		var now := Time.get_ticks_usec()
		values.append(float(now-last)/1000.0)
		last = now
		if DisplayServer.window_is_focused(): focused += 1
	return {"summary":_stats(values),"frame_intervals_ms":values,"focused_frames":focused,"focus_ratio":float(focused)/maxf(1.0,values.size())}

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"frames":0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in values:
		total += value
		if value > 33.3: over33 += 1
		if value > 66.7: over66 += 1
	return {"frames":values.size(),"seconds":total/1000.0,"fps":float(values.size())*1000.0/total,"p50_ms":sorted[int((sorted.size()-1)*.50)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over_33_3_ms":over33,"over_66_7_ms":over66}

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name))

func _capture_temporal(label := "live-tuned") -> Dictionary:
	# Every rendered frame is captured in this separate QA pass. Encoding and the
	# temporary 30 FPS cap never contaminate the earlier performance samples.
	var destination := folder.path_join("temporal-"+label)
	DirAccess.make_dir_recursive_absolute(destination)
	var original_max_fps := Engine.max_fps
	Engine.max_fps = 30
	var frames: Array = []
	var started := Time.get_ticks_usec()
	var phase := -1
	var encoding_error := OK
	var expected_parts: Dictionary = world.session.desert.tuning_panel._draft_parts.duplicate(true)
	while Time.get_ticks_usec()-started < 30000000:
		await process_frame
		if world.session.desert.tuning_panel._draft_parts != expected_parts or not world.session.modal:
			push_error("DIGO_MEASURE temporal UI changed unexpectedly; sequence invalid")
			encoding_error = ERR_INVALID_DATA
			break
		var now := Time.get_ticks_usec()
		var wanted_phase := mini(2,int((now-started)/10000000))
		if wanted_phase != phase:
			phase = wanted_phase
			var slot := "taillights" if phase == 1 else "wheel_model"
			world.session.desert.tuning_panel._select_slot(slot)
			world.session.desert.workshop_drive.focus_slot(slot)
			if phase != 1: world.session.desert.workshop_drive.camera_action("reset",0.0)
			world.session.desert.workshop_drive.camera_action("rotate",1.0 if phase == 2 else 0.0)
		await RenderingServer.frame_post_draw
		var presented := Time.get_ticks_usec()
		var filename := "%04d.jpg" % frames.size()
		encoding_error = root.get_texture().get_image().save_jpg(destination.path_join(filename),.88)
		if encoding_error != OK: break
		var camera := root.get_camera_3d()
		frames.append({"file":filename,"elapsed_ms":float(presented-started)/1000.0,"phase":["front_fixed","rear_taillights_fixed","front_orbit"][phase],"camera_transform":str(camera.global_transform),"camera_fov":camera.fov})
	world.session.desert.workshop_drive.camera_action("rotate",0.0)
	Engine.max_fps = original_max_fps
	return {"folder":destination,"capture":"every rendered frame","temporary_max_fps":30,"restored_max_fps":original_max_fps,"jpeg_quality":.88,"duration_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"encoding_error":encoding_error,"frames":frames,"note":"separate 10s front / 10s rear / 10s front orbit QA; JPEG encoding and temporary cap excluded from benchmark metrics; timestamps report actual cadence"}

func _write_report() -> void:
	var file := FileAccess.open(folder.path_join("results.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(_report,"  "))

func _finish(code: int) -> void:
	if is_instance_valid(world) and world.get("session") != null: world.session.close_menu()
	var launch := root.get_node_or_null("V2Launch")
	if launch != null: launch.selected_path = old_path
	print("DIGO_MEASURE output=",folder," exit=",code)
	quit(code)
