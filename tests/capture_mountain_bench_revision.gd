extends SceneTree
const OUTPUT := "D:/geteco/artifacts/vila-bancos-0910"
const VillageLayout = preload("res://world/mountain_pass/MountainVillageLayout.gd")
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func picture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for layer in root.find_children("*", "CanvasLayer", true, false): layer.hide()
	for control in root.find_children("*", "Control", true, false):
		if control.get_script() != null and control.get_script().resource_path.ends_with("SalvageLocator.gd"): control.hide()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(name))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT.path_join("frames"))
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	root.get_node("SaveManager").clear_pending_save()
	var world: Node2D
	var mountain: Node2D
	if OS.get_cmdline_user_args().has("--production"):
		root.get_node("CampaignState").reset_campaign()
		root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
		root.get_node("CampaignState").set_campaign_flag(&"harbor_phone_answered", true)
		world = load("res://world/harbor/HarborGame.tscn").instantiate()
		root.add_child(world)
		current_scene = world
		for frame in 12: await process_frame
		var service = world.get_node("HarborMountainCoachService")
		while service.access_lane == null: await process_frame
		mountain = service.stream.mountain
	else:
		mountain = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
		mountain.connect_to_harbor = false
		mountain.spawn_suv_on_ready = false
		world = mountain
		root.add_child(world)
		current_scene = world
	while not mountain.region_ready: await process_frame
	while not mountain.get_node("MountainSettlement").region_ready: await process_frame
	var pocket: Vector2 = VillageLayout.POCKETS[1]
	var player = get_first_node_in_group("player")
	player.set_physics_process(false)
	player.global_position = mountain.to_global(pocket + Vector2(110, 55))
	player.collision_layer = 0
	player.hide()
	var camera := Camera2D.new()
	mountain.add_child(camera)
	camera.set_meta("mountain_fixed_framing", true)
	camera.global_position = mountain.to_global(Vector2(7480, -1630))
	camera.zoom = Vector2.ONE * 1.2
	camera.make_current()
	for frame in 24: await process_frame
	for layer in mountain.find_children("*", "CanvasLayer", true, false): layer.hide()
	await picture("01_vila_corrigida.png")
	var subject: Node2D
	var external_bench: Node2D = mountain.get_node("MountainSettlement/WinterTrailBench1")
	var residents := get_nodes_in_group("winter_resident")
	residents.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.distance_squared_to(external_bench.global_position) < b.global_position.distance_squared_to(external_bench.global_position))
	for resident in residents:
		if resident.get_parent() != mountain.get_node("MountainSettlement"): continue
		if resident.global_position.distance_to(external_bench.global_position) > 65: continue
		if resident.has_method("request_bench_rest") and resident.request_bench_rest(70.0):
			subject = resident
			break
	if subject == null:
		push_error("No nearby resident could reserve a bench in the real settlement")
		quit(1)
		return
	root.size = Vector2i(960, 720)
	root.content_scale_size = root.size
	camera.global_position = mountain.to_global(pocket + Vector2(15, -15))
	camera.zoom = Vector2.ONE * 2.3
	var seen := {}
	var finished := false
	var previous_state := ""
	for frame in 7200:
		await physics_frame
		var state := String(subject.bench_state())
		if state != previous_state:
			print("BENCH_CAPTURE_STATE ", state, " point=", subject.global_position, " blend=", subject.model.get("sit_amount"))
			previous_state = state
		if not seen.has(state):
			seen[state] = true
			if state == "resting": await picture("02_descanso_no_banco.png")
			if state == "standing": await picture("03_levantando.png")
		if frame % 6 == 0 and captures < 600:
			await picture("frames/frame_%04d.png" % captures)
			captures += 1
		if seen.has("resting") and seen.has("standing") and state in ["idle", "none", ""]:
			finished = true
			await picture("04_ciclo_concluido.png")
			break
	print("BENCH_CAPTURE_RESULT subject=", subject.name, " states=", seen.keys(), " completed=", finished, " frames=", captures)
	var manifest := FileAccess.open(OUTPUT.path_join("capture.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"frames": captures, "states": seen.keys(), "completed": finished}))
	manifest.close()
	world.queue_free()
	for frame in 4: await process_frame
	quit(0 if finished else 1)
