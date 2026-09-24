extends SceneTree

var world
var output := "user://port-expansion-3d"
var camera_focus: Node3D

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _index in 800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	world.session.weather.time_of_day = .40
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.player.controlled_automatically = true
	world.player.set_physics_process(false)
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.session.urban_operations.security.set_process(false)
	world.gameplay.set_process(false)
	world.gameplay.set_physics_process(false)
	world.gameplay.stars = 0
	world.gameplay.health = 100.0
	world.hud.hide()
	camera_focus = Node3D.new()
	world.add_child(camera_focus)
	await _outdoor("santa-mare-ship",Vector3(297.0,.08,184.0),Vector3(298.0,.08,222.0),48.0)
	await _outdoor("santa-mare-bridge-close",Vector3(257.0,.08,182.0),Vector3(298.0,.08,222.0),23.0)
	await _outdoor("port-yard-and-trucks",Vector3(298.0,.08,211.0),Vector3(298.0,.08,222.0),35.0)
	await _outdoor("northstar-ship",Vector3(223.0,.08,95.0),Vector3(201.0,.08,95.0),49.0)
	var hatch := Vector3(4250.0/16.0,.08,2980.0/16.0)
	world.player.teleport(hatch)
	world.production.region.set_focus(hatch)
	for _index in 45: await process_frame
	if await world.session.enter_place("santa_mare_hold",false):
		for _index in 55: await process_frame
		await _save("santa-mare-cargo-hold")
		world.session.leave_place()
	else:
		push_error("Santa Mare hold did not open during rendered capture")
		quit(1)
		return
	await _outdoor("secret-copper-car",Vector3(7050.0/16.0,.08,2290.0/16.0),Vector3(7050.0/16.0+2.5,.08,2290.0/16.0+4.0),24.0)
	world.queue_free()
	await process_frame
	quit()

func _outdoor(label: String, point: Vector3, safe_player_point: Vector3, size: float) -> void:
	world.player.teleport(safe_player_point)
	world.production.region.set_focus(point)
	camera_focus.position = point
	world.camera.target = camera_focus
	world.camera.heading = 0.0
	world.camera.target_size = size
	world.camera.size = size
	world.camera.initialized = false
	for _index in 110: await process_frame
	await _save(label)

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join(label+".png")
	if root.get_texture().get_image().save_png(path) != OK: push_error("Capture failed: "+path)
	else: print("PORT_EXPANSION_CAPTURE ",path)
