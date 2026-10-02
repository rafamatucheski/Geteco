extends SceneTree
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
var world
var folder := "res://evidence/bench-families-20261002"
var only := ""
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func shot(label: String, target: Vector3, size := 8.0) -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size
	camera.global_position = target + Vector3(5, 6, 7)
	camera.look_at(target + Vector3.UP*.5)
	camera.current = true
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
	camera.queue_free()
	await process_frame
func focus(point: Vector3) -> void:
	world.player.teleport(point + Vector3(0,.08,2))
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	world.production.region.set_focus(point)
	await frames(120)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	for sample in [["cemetery",Vector3(-53.75,0,126.25)], ["ferry_shelter",Vector3(230.4,0,200)], ["truckers",Vector3(-366.58,0,84.6)], ["depot",Vector3(-310.85,0,-55)]]:
		if not only.is_empty() and only != sample[0]: continue
		await focus(sample[1])
		await shot(sample[0],sample[1])
	for sample in [["ski_lodge",Vector3(4.8,0,-1.9)], ["lumberjack_shelter",Vector3(0,0,.35)], ["harbor_clothing",Vector3(-4.8,0,.9)], ["harbor_police",Vector3(4.6,0,-5.0)]]:
		if not only.is_empty() and only != sample[0]: continue
		var definition: Dictionary = CATALOG.get_definition(sample[0])
		await focus(definition.entry_position)
		if not await world.session.enter_place(sample[0],false,sample[0]): push_error("Bench review admission failed "+sample[0]); quit(1); return
		await frames(90)
		await shot(sample[0], world.session.room.to_global(sample[1]), 8.0)
		if sample[0] != "harbor_police" and only.is_empty():
			if not await world.session.leave_place(): push_error("Bench review exit blocked " + sample[0]); quit(1); return
	print("BENCH_REVIEW completed=true filter=" + only + " real_main=true")
	quit()
