extends SceneTree
## Reproducible exterior photographs in Main; never an FPS benchmark.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const OUT := "res://evidence/video-review-phase2-20260924/"
var world
var label := "before"
var records: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func frames(count: int) -> void:
	for index in count: await physics_frame

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		failures.append("startup")
		await finish()
		return
	for frame in 600:
		var curtain := false
		for child in world.get_children():
			if child.get_script() == preload("res://runtime/StartupCurtain.gd"): curtain = true
		if not curtain: break
		await process_frame
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	for id in ["harbor_bank", "port_boss_garage"]:
		var definition: Dictionary = PLACES.get_definition(id)
		var entry: Vector3 = definition.entry_position
		var focus: Vector3 = definition.exterior_position + Vector3(0, 1.4, 3.5)
		if id == "port_boss_garage": focus = definition.exterior_position + Vector3(-10, 1.2, 0)
		await photograph(id, entry + Vector3(0, .08, 1.5), focus, 17.0)
	await photograph("maciota", world.maciota_place.exterior_return + Vector3.UP * .08, world.maciota_place.exterior_origin + Vector3(0, 1.4, 4), 15.0)
	await photograph("port-yard", Vector3(300, .08, 220), Vector3(302, 1, 216), 28.0)
	await finish()

func photograph(id: String, position: Vector3, focus: Vector3, size: float) -> void:
	world.camera.clear_store_focus()
	world.production.region.set_focus(position)
	for frame in 300:
		await physics_frame
		if world.production.region.prepare_collision_at(position): break
	# Setup only: this photograph does not claim capsule/path admission.
	world.player.teleport(position)
	world.player.input_locked = true
	world.player.velocity = Vector3.ZERO
	await frames(120)
	world.camera.focus_on_store(focus, size, .2)
	await frames(30)
	await RenderingServer.frame_post_draw
	var path := OUT + label + "-" + id + ".png"
	if root.get_texture().get_image().save_png(path) != OK: failures.append("write " + path)
	var row := {"id": id, "image": path, "player": str(world.player.global_position), "camera": str(world.camera.global_position), "size": world.camera.size, "prompt": world.session.prompt.text}
	records.append(row)
	print("PHASE2_PHOTO ", JSON.stringify(row))
	world.player.input_locked = false

func finish() -> void:
	var file := FileAccess.open(OUT + label + "-overview.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"kind":"functional_photographs_not_benchmark", "engine":Engine.get_version_info().string, "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(), "resolution":str(root.size), "records":records, "failures":failures}, "\t"))
		file.close()
	else: failures.append("report write")
	if is_instance_valid(world): world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
