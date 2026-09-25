extends "res://tests/capture/video_review_interiors.gd"
## Real Main and DispatchController models, staged on admitted outdoor ground.
## Dedicated close views inspect weapons; this is not a benchmark or pursuit run.

var staged_units: Array[RefCounted] = []
var staged_officers: Array[CharacterBody3D] = []

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	capture_prefix = "phase2-police-"
	report_filename = "phase2-police-captures.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-prefix="): capture_prefix = arg.trim_prefix("--capture-prefix=")
		if arg.begins_with("--capture-report="): report_filename = arg.trim_prefix("--capture-report=")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or world.dispatch == null:
		failures.append("Main/dispatch failed to start")
		await finish()
		return
	await wait_startup_curtain()
	world.dispatch.set_physics_process(false)
	world.gameplay.set_physics_process(false)
	world.camera.set_process_unhandled_input(false)
	world.camera.set_process(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	var center: Vector3 = world.player.global_position
	var original: CharacterBody3D = world.driving.car
	original.hide()
	original.collision_layer = 0
	original.set_physics_process(false)
	# Clear the staging footprint while retaining real pavement/scene geometry.
	world.player.teleport(center + Vector3(0, 0, 4))
	var responses := [
		{"level": 2, "variant": "patrol", "weapon": "pistol", "tier": 0},
		{"level": 3, "variant": "interceptor", "weapon": "smg", "tier": 1},
		{"level": 4, "variant": "tactical", "weapon": "m4a1", "tier": 2},
	]
	# Current stars deliberately disagree with the three dispatch identities.
	world.gameplay.stars = 6
	for index in responses.size():
		var response: Dictionary = responses[index]
		var point := center + Vector3(float(index - 1) * 2.5, .12, 0)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, 1))
		if hit.is_empty() or not world.session.position_clear(hit.position + Vector3.UP * .03):
			failures.append("no admitted police staging point: " + response.weapon)
			continue
		point = hit.position + Vector3.UP * .03
		var car: CharacterBody3D = world.dispatch._create_vehicle("police", center + Vector3(12 + index * 6, .03, 0), 0.0)
		car.set_physics_process(false)
		var unit: RefCounted = world.dispatch._make_unit("police", car, 8.0, 60.0)
		unit.level = response.level
		unit.variant = response.variant
		staged_units.append(unit)
		var officer: CharacterBody3D = world.dispatch.spawn_officer(unit, point, -1)
		unit.officers.append(officer)
		staged_officers.append(officer)
		officer.set_physics_process(false)
		officer.global_position = point
		officer.visual.rotation.y = -PI * .40
		if officer.tier != response.tier or officer.weapon_id != response.weapon or officer.visual.weapon_id != response.weapon:
			failures.append("wrong staged loadout: " + response.weapon)
	await frames(5)
	if staged_officers.size() == 3:
		set_capture_camera(center, 7.0)
		for officer in staged_officers: officer.visual.update_pose(1.0, true, false, 0.0, 0.0)
		await frames(3)
		await capture("lineup-aiming")
		for officer in staged_officers:
			set_capture_camera(officer.global_position + Vector3.UP * .6, 3.5)
			await capture(officer.weapon_id + "-aiming")
			var record := {"police_weapon": officer.weapon_id, "tier": officer.tier, "model_tier": officer.visual.tier, "model_weapon": officer.visual.weapon_id, "position": str(officer.global_position), "muzzle": str(officer.visual.muzzle_position()), "source": "actual DispatchController.spawn_officer in Main; fixed admitted floor pose, AI/vehicle physics suspended for comparison"}
			records.append(record)
		set_capture_camera(center, 7.0)
		for officer in staged_officers: officer.visual.update_pose(1.0, false, false, 0.0, 0.0)
		await frames(3)
		await capture("lineup-relaxed")
	for unit in staged_units: unit.finish("capture_complete")
	world.dispatch.units.clear()
	staged_units.clear()
	staged_officers.clear()
	await frames(2)
	await finish()

func set_capture_camera(focus: Vector3, size: float) -> void:
	world.camera.global_position = focus + Vector3(0, 25.3, 25.3)
	world.camera.look_at(focus)
	world.camera.size = size

func finish() -> void:
	var report := {"type": "functional_render_capture_not_benchmark", "engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "records": records, "failures": failures, "notes": "Real Main/DispatchController/PoliceAgent/PoliceModel. Requested 8 pedestrians. Officer poses staged on admitted real pavement; AI and vehicle physics suspended for weapon comparison. Dedicated close camera preserves exterior pitch. Does not validate pursuit, full disembark, or FPS. No settings or saves written."}
	var file := FileAccess.open(OUTPUT + report_filename, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
