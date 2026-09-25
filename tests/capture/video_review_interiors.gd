extends SceneTree
## Functional screenshots in real Main, not a benchmark. No user saves/settings.
const OUTPUT := "res://evidence/video-review-20260924/"
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world
var records: Array[Dictionary] = []
var failures: Array[String] = []
var capture_prefix := ""
var report_filename := "interior-captures.json"
var silhouette_ablation := false

func _initialize() -> void: run.call_deferred()

func frames(count: int) -> void:
	for index in count: await physics_frame

func wait_startup_curtain() -> void:
	for frame in 600:
		var present := false
		for child in world.get_children():
			if child.get_script() == preload("res://runtime/StartupCurtain.gd"):
				present = true
				break
		if not present: return
		await process_frame
	failures.append("startup curtain did not finish before capture")

func capture(label: String) -> void:
	label = capture_prefix + label
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + label + ".png")
	if error != OK: failures.append("capture: " + label)
	var player: CharacterBody3D = world.player
	var ground := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * .2, player.global_position - Vector3.UP, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ground)
	var row := {"label": label, "place": world.session.state.place_id, "position": str(player.global_position), "visual_position": str(player.visual.position), "visible": player.visible, "floor": str(hit.get("position", Vector3.INF)), "floor_body": str(hit.get("collider", "")), "camera_position": str(world.camera.global_position), "camera_size": world.camera.size, "rain_visible": world.session.weather.precipitation.visible, "rain_emitting": world.session.weather.precipitation.emitting, "prompt": world.session.prompt.text, "occupied": world.driving.occupied}
	var silhouette_count := 0
	for geometry in player.find_children("*", "GeometryInstance3D", true, false):
		var material = geometry.material_overlay
		if material is ShaderMaterial and material.shader == preload("res://world/city_look/occluded_silhouette.gdshader"): silhouette_count += 1
	row["player_silhouette_meshes"] = silhouette_count
	if "--expect-depth-fix" in OS.get_cmdline_user_args():
		if not str(row.place).is_empty() and silhouette_count > 0: failures.append("unexpected indoor silhouette: " + label)
		elif str(row.place).is_empty() and not label.ends_with("without-silhouette") and silhouette_count == 0: failures.append("missing outdoor silhouette: " + label)
	records.append(row)
	print("VIDEO_CAPTURE ", JSON.stringify(row))

func wait_body_transition() -> bool:
	for frame in 240:
		await physics_frame
		if not world.driving.is_body_transition_active(): return true
	failures.append("body transition did not finish")
	return false

func car_cycles() -> void:
	var car: CharacterBody3D = world.driving.car
	for cycle in 2:
		var entered := false
		for side in [-1, 1]:
			var point: Vector3 = car.driver_door_anchor(side) + car.global_basis.x * float(side) * .35
			point.y = car.global_position.y + .08
			if not world.session.position_clear(point): continue
			world.player.teleport(point)
			await frames(3)
			if world.driving.interact(): entered = true; break
		if not entered:
			failures.append("car entry cycle " + str(cycle))
			return
		await frames(18)
		await capture("vehicle-%d-boarding" % cycle)
		if not await wait_body_transition(): return
		car.external_input = true
		car.throttle_input = 0.0
		car.brake_input = true
		await frames(8)
		await capture("vehicle-%d-seated" % cycle)
		if not world.driving.leave():
			failures.append("car exit cycle " + str(cycle))
			return
		if not await wait_body_transition(): return
		await frames(12)
		await capture("vehicle-%d-exited" % cycle)

func motorcycle_theft() -> void:
	var original: CharacterBody3D = world.driving.car
	var spawn: Vector3 = original.global_position
	original.hide()
	original.set_physics_process(false)
	original.collision_layer = 0
	original.remove_from_group("drivable")
	# Reuse an already admitted ground pose; this fixture validates rider/pose,
	# not the bike's driving, collision or streaming behaviour.
	var bike = preload("res://scripts/Vehicle.gd").new()
	bike.archetype = "bike_urban"
	bike.vehicle_id = "video_capture_bike"
	bike.traffic = true
	bike.set_meta("ambient_traffic", true)
	bike.set_meta("region_id", "harbor")
	bike.position = spawn
	world.add_child(bike)
	bike.set_physics_process(false)
	world.production.vehicles.append(bike)
	world.player.teleport(bike.driver_door_anchor(-1))
	await frames(4)
	await capture("motorcycle-before-theft")
	if not world.driving._begin_entry(bike, -1):
		failures.append("motorcycle theft admission")
		return
	if not await wait_body_transition(): return
	await frames(8)
	await capture("motorcycle-after-theft-dante-mounted")
	if silhouette_ablation: await capture_without_silhouette("motorcycle-without-silhouette")
	if not world.driving.leave():
		failures.append("motorcycle exit")
		return
	if not await wait_body_transition(): return
	await frames(8)
	await capture("motorcycle-after-dismount")

func capture_without_silhouette(label: String) -> void:
	var city: Node = world.get_node("CityLook")
	var was_processing: bool = city.is_processing()
	city.set_process(false)
	var removed: Array[Dictionary] = []
	for target in [world.player, world.driving.car]:
		if not is_instance_valid(target): continue
		for geometry in target.find_children("*", "GeometryInstance3D", true, false):
			var material = geometry.material_overlay
			if material is ShaderMaterial and material.shader == preload("res://world/city_look/occluded_silhouette.gdshader"):
				removed.append({"geometry": geometry, "material": material})
				geometry.material_overlay = null
	await capture(label)
	for item in removed:
		if is_instance_valid(item.geometry): item.geometry.material_overlay = item.material
	city.set_process(was_processing)

func enter(id: String) -> bool:
	var exterior: Vector3 = world.maciota_place.entry_position if id == "maciota" else PLACES.get_definition(id).entry_position
	world.player.teleport(exterior + Vector3.UP * .08)
	world.production.region.set_focus(exterior)
	await frames(8)
	if not await world.session.enter_place(id, false, id):
		failures.append("enter " + id)
		return false
	return true

func leave(id: String) -> bool:
	if not await world.session.leave_place():
		failures.append("leave " + id)
		return false
	await capture(id + "-exit-first-render")
	await frames(15)
	return true

func finish() -> void:
	var report := {"type": "functional_render_capture_not_benchmark", "engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "records": records, "failures": failures, "notes": "Production Main, 8 requested pedestrians, dispatch disabled. Setup teleports and direct session admission; vehicle cycles use actual body transition. Motorcycle uses a fixed admitted pose with its vehicle physics suspended. No global settings or saves written. Photos need visual review; floor rays alone do not certify collision or occlusion."}
	var file := FileAccess.open(OUTPUT + report_filename, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args():
		push_error("Functional capture requires rendered Godot and --no-save")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		failures.append("Main failed to start")
		await finish()
		return
	await wait_startup_curtain()
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 1
	world.session.weather.weather_timer = 99999.0
	await frames(30)
	await car_cycles()
	if not world.driving.occupied: await motorcycle_theft()
	if world.driving.occupied:
		await finish()
		return
	if await enter("harbor_ammunation"):
		await capture("ammunation-first-render-rain-outside")
		await frames(15)
		await capture("ammunation-spawn-after-two-car-cycles")
		world.player.automatic_direction = Vector3(0, 0, -1)
		await frames(45)
		world.player.automatic_direction = Vector3.ZERO
		await capture("ammunation-counter-approach")
		if not await leave("harbor_ammunation"):
			await finish()
			return
	if await enter("harbor_bank"):
		await frames(20)
		await capture("bank-spawn-after-two-car-cycles")
		world.session.state.grant_weapon("pistol")
		world.session.state.equip_weapon("pistol")
		world.player.automatic_direction = Vector3(-1, 0, 0)
		await frames(38)
		await capture("bank-walking-armed-guards")
		world.player.automatic_direction = Vector3.ZERO
		await frames(10)
		await capture("bank-standing-armed-guards")
		if not await leave("harbor_bank"):
			await finish()
			return
	if await enter("maciota"):
		await capture("maciota-first-render-rain-outside")
		await frames(15)
		await capture("maciota-settled-rain-outside")
		await leave("maciota")
	await finish()
