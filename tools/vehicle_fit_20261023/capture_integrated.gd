extends "res://tests/capture/capture_sport_coupe_redesign.gd"
## Evidência renderizada contínua de um arquétipo da frota na cena Main real.
## Godot .NET --script res://tests/capture/capture_fleet_redesign_temporal.gd --
## --no-save --skip-arrival --population=24 --id=police_cruiser --label=after
## Rode sozinho, depois do benchmark independente. Codifique com
## tools/build_sport_coupe_review_video.py <a pasta resultante>.
## Todo quadro renderizado é gravado; a cadência de leitura NÃO é desempenho de gameplay.

const VEHICLE_SCENE := preload("res://scripts/Vehicle.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const REDESIGNED := preload("res://runtime/RedesignedFleet.gd")

var target_id := "police_cruiser"
var capture_label := "after"
var original_wheels := 0
var door_angle_by_phase: Dictionary = {}
var braking_frames := 0
var moving_brake_frames := 0
var service_brake_frames := 0
var parked_brake_frames := 0
var siren_expected := false
var siren_frames := 0
var siren_state_failures := 0
var beacon_phases: Dictionary = {}
var saved_render_frames: Array[int] = []
var capture_gaps_ms: Array[float] = []
var skipped_render_frames := 0
var has_emergency_lights := false
var write_failures := 0
var fixture_world_position := Vector3.ZERO
var snapshot_sources: Dictionary = {}
var batch_label := "final-a"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless" or "--no-save" not in args:
		push_error("Rendered .NET and --no-save required"); quit(2); return
	var ids: Array = ["porto_rosso","beach_cabriolet","orbita_micro","vale_crossover","ranch_pickup","ranch_single","boxrunner","toco_minitruck"]
	for arg in args:
		if arg.begins_with("--ids="): ids=Array(arg.trim_prefix("--ids=").split(","))
		if arg.begins_with("--label="): batch_label=arg.trim_prefix("--label=").validate_filename()
	seed(23102026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	normal_max_fps=Engine.max_fps
	Engine.max_fps=30
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	var deadline := Time.get_ticks_msec()+300000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play or not world.production.no_save:
		push_error("Actual isolated Main did not become ready"); quit(3); return
	world.production.set_population(24)
	world.gameplay.health=1000000
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.set_process(false)
	var results := []
	for id: String in ids:
		target_id=id
		reset_case()
		await run_case()
		results.append({"id":id,"ok":failures.is_empty(),"failures":failures.duplicate(),"frames":rows.size(),"distance":travelled})
		if not failures.is_empty(): break
		world.production.vehicles.erase(car)
		if world.driving.car==car: world.driving.car=null
		car.free()
		await process_frame
	var batch_folder := "res://artifacts/vehicle-fit-20261023/temporal/"+batch_label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(batch_folder))
	FileAccess.open(batch_folder+"/batch-results-"+str(Time.get_unix_time_from_system())+".json",FileAccess.WRITE).store_string(JSON.stringify({"requested":ids,"results":results},"\t"))
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func reset_case() -> void:
	failures.clear(); rows.clear(); events.clear(); snapshot_sources.clear()
	capture_gaps_ms.clear(); saved_render_frames.clear(); door_angle_by_phase.clear(); beacon_phases.clear()
	capture_start=0; recording=false; recording_finished=false; travelled=0; max_steering=0
	night_lamp_frames=0; night_lamp_failures=0; braking_frames=0; moving_brake_frames=0
	service_brake_frames=0; parked_brake_frames=0; siren_frames=0; siren_state_failures=0
	skipped_render_frames=0; write_failures=0; expected_night_lamps=false; siren_expected=false
	capture_label="vehicle-fit-20261023-"+batch_label
	folder="res://artifacts/vehicle-fit-20261023/temporal/"+batch_label+"/"+target_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder+"/frames"))

func run_case() -> void:
	var deadline := 0
	car = VEHICLE_SCENE.new()
	car.archetype = target_id
	car.vehicle_id = "fleet_temporal_" + target_id
	car.position = world.player.global_position + Vector3.UP * 30.0
	car.set_physics_process(false)
	world.add_child(car)
	car.ensure_equipment(world)
	world.production.vehicles.append(car)
	original_wheels = car.wheels.size()
	has_emergency_lights = not car.equipment.beacons.is_empty()
	if not record_check(original_wheels >= 4, "vehicle has at least four physical wheel pivots"):
		await finish(); return
	if not record_check(await prepare_road_pose(), "fifty metres of authored road pass target hull and gameplay camera admission"):
		await finish(); return
	fixture_world_position = car.global_position
	car.external_input = false
	car.controlled = false
	car.brake_input = true
	car.set_physics_process(true)
	for frame in 20: await physics_frame
	var approached := false
	for side in car.boarding_sides():
		var approach: Vector3 = car.driver_door_anchor(int(side)) + car.global_basis.x * float(side) * .16
		var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(approach + Vector3.UP * .3, approach - Vector3.UP * .5, 1))
		if ground.is_empty(): continue
		approach.y = ground.position.y + .04
		if not world.session.position_clear(approach): continue
		world.player.teleport(approach)
		approached = true
		break
	if not record_check(approached, "player stands on solid ground beside the actual cab door"):
		await finish(); return
	world.production.region.set_focus(car.global_position)
	world.camera.target = world.player
	world.camera.target_size = maxf(15.0, car.half_length * 3.2)
	world.camera.set_preview_view(false)
	world.camera.heading = float(admitted_route.get("camera_heading", 0.0))
	world.camera.offset = Vector3(0, 25.3, 25.3)
	world.camera.initialized = false
	set_time(false)
	await hold(1.0)
	last_car_position = car.global_position
	capture_start = Time.get_ticks_usec()
	recording = true
	_capture_loop()
	phase = "day-parked"
	await hold(1.5)
	await shot("01-day-parked")
	phase = "entry"
	if not record_check(world.driving.interact(), "Driving.interact accepts real entry"):
		await finish(); return
	if not await transition_done(true): await finish(); return
	if not record_check(world.driving.car == car and car.controlled and world.player.seated and world.player.visible, "entry seats a visible driver in the selected target"):
		await finish(); return
	world.camera.target_size = maxf(15.0, car.half_length * 3.2)
	await shot("02-day-inside")
	if has_emergency_lights:
		record_check(car.equipment.toggle_siren(), "normal equipment API enables emergency beacons")
		await hold(.35)
		siren_expected = true
	phase = "day-driving"
	await drive_for(7.0)
	if not failures.is_empty(): await finish(); return
	await shot("03-day-moving")
	phase = "night-transition"
	set_time(true)
	await hold(.35)
	expected_night_lamps = true
	phase = "night-driving"
	await drive_for(8.0)
	if not failures.is_empty(): await finish(); return
	await shot("04-night-moving")
	phase = "braking"
	release_inputs()
	Input.action_press("brake")
	deadline = Time.get_ticks_msec() + 8000
	while absf(car.speed) > .2 and Time.get_ticks_msec() < deadline and failures.is_empty(): await physics_frame
	if not record_check(absf(car.speed) <= .2, "real service brake stops the target vehicle"):
		await finish(); return
	# O eixo do freio vira ré depois de parar. Solta-o na velocidade zero e
	# segura o freio de mão real, como nos controles normais e na captura de referência.
	release_inputs()
	Input.action_press("handbrake")
	await hold(1.5)
	# A leitura em JPEG na resolução nativa pode render menos de dez quadros em1.5s.
	# Mantém o mesmo limiar de estado do freio; estende a observação uma vez, no máximo10s.
	# É uma proteção de cobertura da captura, independente do desempenho de gameplay.
	var brake_observation_deadline := Time.get_ticks_msec()+10000
	while braking_frames<10 and Time.get_ticks_msec()<brake_observation_deadline and failures.is_empty(): await process_frame
	if not record_check(absf(car.speed) <= .2 and car.equipment._tail_state == 2, "handbrake keeps the vehicle stopped and rear brake lamps bright"):
		await finish(); return
	await shot("05-night-braking")
	if has_emergency_lights:
		siren_expected = false
		record_check(car.equipment.toggle_siren(), "normal equipment API disables emergency beacons")
		await hold(.35)
	expected_night_lamps = false # Intentional engine/headlight shutdown during exit.
	phase = "exit"
	release_inputs()
	if not record_check(world.driving.leave(), "Driving.leave accepts a stopped, safe exit"):
		await finish(); return
	if not await transition_done(false): await finish(); return
	record_check(not world.driving.occupied and not world.player.seated and world.player.visible, "exit restores the visible on-foot player")
	phase = "night-exited"
	await shot("06-night-exited")
	while Time.get_ticks_usec() - capture_start < 35000000 and failures.is_empty(): await process_frame
	record_check(travelled > 16.0, "day/night physical driving exceeds sixteen metres")
	record_check(max_steering > .025, "front wheel steering changes during the drive")
	record_check(absf(car.wheel_spin) > .1 and car.wheels.size() == original_wheels, "every original wheel pivot remains present and spins")
	record_check(float(door_angle_by_phase.get("entry", 0.0)) > .3 and float(door_angle_by_phase.get("exit", 0.0)) > .3, "cab door opens during both real boarding transitions")
	record_check(night_lamp_frames > 30 and night_lamp_failures == 0, "both headlight projectors and emissive lenses stay enabled through night driving and braking")
	record_check(braking_frames >= 10, "continuous capture includes at least ten rendered frames with brake lamps lit")
	if has_emergency_lights:
		record_check(siren_frames > 30 and siren_state_failures == 0 and beacon_phases.has(0) and beacon_phases.has(1), "emergency beacons alternate both intentional phases without blank enabled frames")
	record_check(write_failures == 0, "all rendered-frame image writes succeeded")
	await finish()

func shot(snapshot_name: String) -> void:
	# Escolhe um quadro contínuo real; exporta o PNG dele depois da gravação. A compressão
	# PNG síncrona durante a direção escondia o transiente breve do freio de serviço.
	await RenderingServer.frame_post_draw
	if not rows.is_empty(): snapshot_sources[snapshot_name] = rows[-1].file

func _capture_loop() -> void:
	var previous_us := capture_start
	var previous_render_frame := -1
	while recording:
		await RenderingServer.frame_post_draw
		if not recording: break
		var now := Time.get_ticks_usec()
		var render_frame := Engine.get_frames_drawn()
		var file := "frames/%06d.jpg" % rows.size()
		var result := root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(folder + "/" + file), .88)
		if result != OK: write_failures += 1
		capture_gaps_ms.append(float(now - previous_us) / 1000.0)
		previous_us = now
		if previous_render_frame >= 0: skipped_render_frames += maxi(0, render_frame - previous_render_frame - 1)
		previous_render_frame = render_frame
		saved_render_frames.append(render_frame)
		var lamps := 0
		var lenses := 0
		var lamp_states: Array[Dictionary] = []
		for item in car.equipment.lamps:
			if item.lamp.is_visible_in_tree(): lamps += 1
			lamp_states.append({"side": item.side, "visible": item.lamp.is_visible_in_tree(), "position": str(item.lamp.global_position), "energy": item.lamp.light_energy, "range": item.lamp.spot_range})
		for item in car.equipment.lens_materials:
			if item.material.emission_enabled and item.material.emission_energy_multiplier > 0: lenses += 1
		if expected_night_lamps:
			night_lamp_frames += 1
			if lamps != 2 or lenses < 2: night_lamp_failures += 1
		if phase == "braking" and car.equipment._tail_state == 2:
			braking_frames += 1
			if absf(car.speed) > .2: moving_brake_frames += 1
			if Input.is_action_pressed("brake"): service_brake_frames += 1
			if absf(car.speed) <= .2 and Input.is_action_pressed("handbrake"): parked_brake_frames += 1
		var lit_beacons: Array[int] = []
		for beacon in car.equipment.beacons:
			if beacon.material.emission_enabled and beacon.material.emission_energy_multiplier > 0:
				lit_beacons.append(int(beacon.side))
				if siren_expected: beacon_phases[int(beacon.side)] = true
		if siren_expected:
			siren_frames += 1
			if lit_beacons.is_empty() or not car.equipment.siren_on: siren_state_failures += 1
		var doors: Dictionary = {}
		if is_instance_valid(car.door_presentation):
			for side in car.door_presentation.hinges:
				var hinge: Node3D = car.door_presentation.hinges[side]
				doors[str(side)] = hinge.rotation.y
				door_angle_by_phase[phase] = maxf(float(door_angle_by_phase.get(phase, 0.0)), absf(hinge.rotation.y))
		var wheel_states: Array[Dictionary] = []
		for wheel in car.wheels:
			wheel_states.append({"position": str(wheel.global_position), "rotation": str(wheel.rotation), "front": wheel.get_meta("front", false)})
		travelled += car.global_position.distance_to(last_car_position)
		last_car_position = car.global_position
		max_steering = maxf(max_steering, absf(car.steering))
		rows.append({"file": file, "seconds": float(now - capture_start) / 1000000.0, "render_frame": render_frame, "phase": phase,
			"night": night, "position": str(car.global_position), "yaw": car.rotation.y, "speed": car.speed,
			"steering": car.steering, "wheel_spin": car.wheel_spin, "wheels": wheel_states, "doors_rad": doors,
			"lamps_visible": lamps, "lenses_lit": lenses, "projectors": lamp_states,
			"tail_state": car.equipment._tail_state, "brake_input": car.brake_input,
			"siren_on": car.equipment.siren_on, "beacons_lit_sides": lit_beacons,
			"health": car.health, "controlled": car.controlled, "player_seated": world.player.seated,
			"player_visible": world.player.visible, "player_position": str(world.player.global_position),
			"player_visual_position": str(world.player.visual.global_position), "player_visual_scale": str(world.player.visual.global_basis.get_scale()),
			"camera_position": str(world.camera.global_position), "camera_size": world.camera.size})
		if now - capture_start > 90000000:
			record_check(false, "ninety-second capture watchdog exceeded")
			recording = false
	recording_finished = true

func finish() -> void:
	release_inputs()
	recording = false
	if capture_start > 0:
		while not recording_finished: await process_frame
	for snapshot_name in snapshot_sources:
		var captured_image := Image.load_from_file(folder + "/" + str(snapshot_sources[snapshot_name]))
		if captured_image != null:
			if captured_image.save_png(ProjectSettings.globalize_path(folder + "/" + str(snapshot_name) + ".png")) != OK: write_failures += 1
	var cadence := frame_stats(capture_gaps_ms)
	var report := {"ok": failures.is_empty(), "archetype": target_id, "label": capture_label,
		"failures": failures, "events": events, "frames": rows,
		"continuous_seconds": rows[-1].seconds if not rows.is_empty() else 0.0,
		"travelled_m": travelled, "maximum_steering_rad": max_steering,
		"wheel_pivots": original_wheels, "maximum_door_angle_by_phase": door_angle_by_phase,
		"night_lamp_frames": night_lamp_frames, "night_lamp_state_failures": night_lamp_failures,
		"brake_lamp_frames": braking_frames, "moving_brake_lamp_frames": moving_brake_frames,
		"service_brake_input_lamp_frames": service_brake_frames, "parked_handbrake_lamp_frames": parked_brake_frames,
		"snapshot_source_frames": snapshot_sources, "emergency_lights_applicable": has_emergency_lights,
		"siren_frames": siren_frames, "siren_state_failures": siren_state_failures,
		"beacon_phases_observed": beacon_phases.keys(), "skipped_rendered_frames": skipped_render_frames,
		"image_write_failures": write_failures, "capture_cadence_only": cadence,
		"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": str(root.size), "msaa": root.msaa_3d,
		"capture_max_fps": Engine.max_fps, "original_max_fps": normal_max_fps,
		"vsync": DisplayServer.window_get_vsync_mode(), "external_capture": false,
		"normal_settings_skipped": false, "startup_prewarm_skipped": "--no-prewarm" in OS.get_cmdline_user_args(), "admitted_route": admitted_route,
		"fixture_position": str(fixture_world_position), "population_requested": 24,
		"visual_review_status": "pending human/agent frame inspection",
		"coverage": ["real Main city1", "day/night dry weather", "parked", "actual boarding", "normal-input driving", "gentle steering", "service brake", "normal exit", "wheel and door transforms", "projector/lens/brake lamp states", "emergency beacons when fitted"],
		"not_covered": ["other archetypes", "other maps", "rain", "tunnels", "save restore", "full speed", "reverse", "damage", "turn signals absent from current equipment", "armored cargo-door interaction", "performance"],
		"notes": "Continuous viewport frame sequence with monotonic timestamps. Main and production Vehicle/FleetCatalog are real; fixture placement occurs only before recording. Each subsequent vehicle movement is produced by normal player inputs and physics. Siren is operated through the normal equipment API. Headlights intentionally shut down during exit. Capture cadence includes JPEG readback and cannot be used as FPS or CPU/GPU performance. State assertions do not certify beam pixels, joins or visual flicker: inspect the video and suspicious frames. Scope is only this vehicle, route, camera and recorded interval."}
	FileAccess.open(folder + "/flow.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FLEET_TEMPORAL ", target_id, " ", "PASS" if failures.is_empty() else "FAIL", " frames=", rows.size(), " distance=", travelled, " failures=", failures)
	await process_frame
