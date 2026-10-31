extends "res://tests/measure/measure.gd"
## Real Main scene, isolated checkpoint, identical local route in both variants.
const SPAWN := Vector3(746, 8, -434)
var folder := ""
var variant := "after"
var interactive := false
var population_log: Array = []
var sample_clock := 0.0
var fingerprints := {}

func fingerprint() -> Dictionary:
	var result := {}
	for path in ["runtime/ProductionWorld.gd", "runtime/FullSession.gd", "world/regions/NativeRegion.gd", "scripts/Actor.gd", "scripts/CameraRig.gd", "world/editing/world_edits.json", ".godot/mono/temp/bin/Debug/Harbor.dll"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Requires rendered Godot .NET and --no-save"); quit(2); return
	interactive = "--interactive" in args
	variant = "before" if "--terrain3d-baseline" in args else "after"
	folder = "res://evidence/terrain3d-mountain/%s-%d" % [variant, OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var state = preload("res://runtime/GameState.gd").new()
	var intro: Dictionary = state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	if not state.intro.restore_snapshot(intro): quit(2); return
	state.set_location("mountain")
	state.world_state.time = .45
	state.world_state.weather = 0
	state.world_state.pedestrian = {"region":"mountain", "position":[SPAWN.x, SPAWN.y, SPAWN.z]}
	var store = preload("res://runtime/SaveStore.gd").new()
	store.path = folder.path_join("fixture.json")
	if store.save(state) != OK: quit(2); return
	seed(610207)
	fingerprints = fingerprint()
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", store.path)
	root.add_child(world)
	current_scene = world
	var setup_start := Time.get_ticks_msec()
	var setup_note := setup_start
	while Time.get_ticks_msec() - setup_start < 120000:
		await physics_frame
		if Time.get_ticks_msec() - setup_note >= 10000:
			setup_note = Time.get_ticks_msec()
			print("TERRAIN3D_PREPARING seconds=", (setup_note-setup_start)/1000.0, " production=",world.production.ready_for_play," settled=",world.production.startup_streaming_settled)
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play or not world.production.loaded_save:
		push_error("Mountain fixture failed to load"); quit(3); return
	world.dispatch.router.nearest_edge(SPAWN)
	if world.dispatch.router._native == null:
		push_error("C# router unavailable"); quit(3); return
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather._update()
	world.camera.heading = 0
	world.camera.target_size = 32
	world.camera.initialized = false
	world.diagnostic_label.hide()
	var terrain = world.production.region.terrain
	var at := SPAWN
	at.y = terrain.surface_height_at(Vector2(at.x,at.z)) + .08
	world.player.teleport(at)
	var tile: Node3D = world.production.region.chunks.get(Vector2i(11,-7))
	var pilot_count := 0
	if tile != null:
		for surface in tile.find_children("MountainTerrain","MeshInstance3D",true,false):
			if surface.get_meta("terrain3d_baked_pilot",false):
				pilot_count+=1
				print("PILOT_MATERIAL ",surface.material_override.shader.resource_path," origin=",surface.get_instance_shader_parameter("origin"))
	print("TERRAIN3D_READY variant=",variant," spawn=",at," baked_pilots=",pilot_count)
	if variant=="after" and pilot_count!=1: push_error("Baked pilot is not active"); quit(3); return
	if interactive:
		print("TERRAIN3D_COMPARISON ", variant, " at ", at, " (isolated save)")
		return
	create_timer(120).timeout.connect(func(): push_error("Terrain comparison timeout"); quit(3))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	for i in 120: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("comparison.png"))
	route = PackedVector3Array([at + Vector3(-6,0,0), at + Vector3(6,0,0)])
	world.player.speed = 2.0
	started = Time.get_ticks_usec()
	previous = started

func _process(delta: float) -> bool:
	if started > 0:
		sample_clock += delta
		if sample_clock >= 1.0:
			sample_clock = 0
			population_log.append({"people":world.people.size(), "cars":world.production.vehicles.size(), "position":str(world.player.global_position), "on_floor":world.player.is_on_floor()})
	return super._process(delta)

func finish() -> void:
	world.player.automatic_direction = Vector3.ZERO
	var report := {"variant":variant, "engine":Engine.get_version_info().string, "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(), "resolution":str(root.size), "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "summary":stats(samples), "warmup":stats(cold), "cpu":stats(cpu), "physics":stats(physics), "frames_ms":samples, "warmup_ms":cold, "population":population_log, "distance":world.player.travelled, "sources_before":fingerprints, "sources_after":fingerprint(), "save_isolated":world.production.store.path.begins_with(folder), "notes":"Real Main, C# router, local walking route; checkpoint start does not certify regional arrival."}
	FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TERRAIN3D_BENCHMARK ", folder, " ", JSON.stringify(report.summary))
	if "--temporal" in OS.get_cmdline_user_args():
		# Captura todo quadro renderizado numa travessia física curta, depois da cronometragem.
		# A leitura da GPU afeta esta sequência, então não é amostra de FPS.
		var at := Vector3(766,0,-434)
		at.y = world.production.region.terrain.surface_height_at(Vector2(at.x,at.z))+.08
		world.player.teleport(at)
		world.player.speed = 2.0
		world.player.automatic_direction = Vector3.RIGHT
		world.camera.initialized = false
		var images: Array[Image] = []
		var timeline: Array = []
		for i in 120:
			await RenderingServer.frame_post_draw
			images.append(root.get_texture().get_image())
			timeline.append({"frame":i,"usec":Time.get_ticks_usec(),"position":str(world.player.global_position),"on_floor":world.player.is_on_floor()})
		world.player.automatic_direction = Vector3.ZERO
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("sequence")))
		for i in images.size(): images[i].save_png(folder.path_join("sequence/%04d.png" % i))
		FileAccess.open(folder.path_join("sequence/timeline.json"),FileAccess.WRITE).store_string(JSON.stringify(timeline))
	world.queue_free()
	await process_frame
	quit()
