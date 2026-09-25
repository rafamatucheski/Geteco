extends SceneTree
## Reproduction only. Does not alter port production scripts or personal saves.
var world
var failures: Array[String] = []
var output := "res://evidence/video-review-phase4-20260924/"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	create_timer(100).timeout.connect(func(): push_error("PORT_BASELINE timeout"); quit(3))
	run.call_deferred()
func frames(count: int) -> void:
	for _i in count: await physics_frame
func photograph(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := output + "phase4-port-before-" + id + ".png"
	print("PORT_BASELINE_PHOTO ", root.get_texture().get_image().save_png(path), " ", path)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.input_locked = false
	world.session.weather.time_of_day = .45
	var point := Vector3(4300, 0, 3550) / 16.0
	world.production.region.set_focus(point)
	for _i in 180:
		await physics_frame
		if world.production.region.prepare_collision_at(point): break
	world.player.teleport(point + Vector3.UP * .1)
	var cargo = world.session.urban_operations.cargo_handling
	for second in 12:
		await frames(60)
		for i in cargo.work_trucks.size():
			var state: Dictionary = cargo.work_trucks[i]
			if is_instance_valid(state.truck):
				print("PORT_BASELINE second=", second + 1, " slot=", i, " phase=", state.phase, " loaded=", state.loaded, " p=", state.truck.global_position, " speed=", state.truck.speed)
	var selected := -1
	for i in cargo.work_trucks.size():
		if is_instance_valid(cargo.work_trucks[i].truck): selected = i; break
	if selected < 0:
		push_error("PORT_BASELINE no truck")
		quit(1)
		return
	var state: Dictionary = cargo.work_trucks[selected]
	var truck: CharacterBody3D = state.truck
	world.camera.focus_on_store(truck.global_position + Vector3.UP, 16, .2)
	await frames(20)
	await photograph("truck-operation")
	print("PORT_BASELINE methods player_actions=", cargo.has_method("nearest_action"), " snapshot=", cargo.has_method("snapshot"))
	truck.stop_boarding_motion()
	world.player.teleport(truck.driver_door_anchor(-1) - truck.global_basis.x * .2)
	print("PORT_BASELINE session_action=", world.session.nearest())
	print("PORT_BASELINE entered=", world.driving.interact(true))
	await frames(150)
	print("PORT_BASELINE occupied=", world.driving.occupied, " phase=", state.phase, " loaded=", state.loaded)
	truck.stop_boarding_motion()
	print("PORT_BASELINE leave=", world.driving.leave())
	await frames(180)
	print("PORT_BASELINE after_exit phase=", state.phase, " traffic=", truck.traffic, " physics=", truck.is_physics_processing(), " loaded=", state.loaded, " speed=", truck.speed)
	await photograph("truck-interrupted")
	world.queue_free()
	await frames(5)
	print("PORT_BASELINE done")
	quit(0)
