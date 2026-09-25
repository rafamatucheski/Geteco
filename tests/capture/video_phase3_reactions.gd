extends SceneTree
const OUT := "res://evidence/video-review-phase3-20260924/"
var world
var label := "before"
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func frames(count: int) -> void:
	for _i in count: await physics_frame

func photograph(id: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + label + "-" + id + ".png"
	if root.get_texture().get_image().save_png(path) != OK: failures.append(path)
	print("REACTION_PHOTO ", path)

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		quit(1)
		return
	for _i in 600:
		var curtain := false
		for child in world.get_children():
			if child.get_script() == preload("res://runtime/StartupCurtain.gd"): curtain = true
		if not curtain: break
		await process_frame
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.input_locked = false
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	var guard: Node3D = world.session.urban_operations.security._staff[0]
	var point := guard.global_position + Vector3(-2, .08, 3)
	world.production.region.set_focus(point)
	for _i in 180:
		await physics_frame
		if world.production.region.prepare_collision_at(point): break
	world.player.teleport(point)
	world.camera.focus_on_store(guard.global_position + Vector3(0, 1, 1), 9, .2)
	await frames(40)
	await photograph("port-worker-idle")
	world.session.state.grant_weapon("pistol")
	world.session.state.equip_weapon("pistol")
	world.gameplay.cooldown = 0
	print("REACTION_SHOT port=", world.gameplay.fire_at(point + Vector3(-8, 0, 0)))
	await frames(35)
	await photograph("port-worker-shot")
	world.camera.clear_store_focus()
	if await world.session.enter_place("harbor_bank", false):
		world.session.state.equip_weapon("fists")
		await frames(40)
		world.camera.focus_on_store(world.session.room.global_position + Vector3(0, .8, -1), 11, .2)
		await frames(20)
		await photograph("bank-clerks-idle")
		world.session.state.equip_weapon("pistol")
		world.gameplay.cooldown = 0
		print("REACTION_SHOT bank=", world.gameplay.fire_at(world.player.global_position + Vector3(8, 0, 0)))
		await frames(35)
		await photograph("bank-clerks-shot")
	else: failures.append("bank entry")
	if label == "after":
		world.camera.clear_store_focus()
		world.session.leave_place()
		await frames(10)
		if await world.session.enter_place("harbor_ammunation", false):
			world.session.state.equip_weapon("fists")
			var vendor: Node3D = world.session.static_service_actor
			world.camera.focus_on_store(vendor.global_position + Vector3(0, .7, 1.3), 8, .2)
			await frames(35)
			await photograph("vance-idle")
			world.session.state.equip_weapon("pistol")
			world.gameplay.cooldown = 0
			print("REACTION_SHOT vance=", world.gameplay.fire_at(world.player.global_position + Vector3(8, 0, 0)))
			await frames(35)
			await photograph("vance-shot")
			await frames(280)
			await photograph("vance-recovered")
		else: failures.append("weapon shop entry")
	print("REACTION_CAPTURE failures=", failures.size())
	world.queue_free()
	await frames(4)
	quit(0 if failures.is_empty() else 1)
