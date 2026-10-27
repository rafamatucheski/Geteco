extends SceneTree
## Canal entre o deserto e a serra (27/10/2026): monta o mar do mundo, a serra e a coluna leste de trechos
## do deserto, sem Main nem HUD, e fotografa com o ângulo da câmera do jogo na ponta da trilha oeste e no
## canto noroeste do gelo, mais uma vista larga do canal. Serve para conferir a "montanha de areia" (selo
## leste do deserto); GETECO_DESERT_ISLAND=0 mostra o selo antigo. Inspeção visual; não mede FPS.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_desert_mountain_canal.gd [-- --label=depois]
const SEA := preload("res://world/shape/WorldSea.gd")
const EDITABLE := preload("res://world/editing/EditableRegion.gd")
const DESERT := preload("res://world/desert/DesertRegion.gd")
const L := preload("res://world/desert/DesertLayout.gd")
const CAMERA_OFFSET := Vector3(0, 25.3, 25.3)
## Ângulo do jogo (CameraRig.EXTERIOR_OFFSET) com o maior zoom automático.
const VIEWS := {"trilha-oeste": [Vector3(505, 0, -470), 52.0], "canto-noroeste": [Vector3(610, 0, -880), 52.0]}

class FakeProduction extends Node:
	var regions := {}

func _initialize() -> void:
	create_timer(500).timeout.connect(func(): push_error("CANAL timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var label := "foto"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.get_slice("=", 1)
	var output := "res://evidence/desert-mountain-canal-%s-%d" % [label, OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1600, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("0c1a20")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d9dde0")
	environment.environment.ambient_light_energy = .6
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -32, 0)
	sun.light_energy = 1.2
	stage.add_child(sun)
	var production := FakeProduction.new()
	stage.add_child(production)
	var sea := SEA.new()
	sea.configure(production)
	stage.add_child(sea)
	await sea.build_sliced(self)
	var mountain = EDITABLE.build_region("mountain")
	mountain.initial_focus = Vector3(560, 0, -650)
	stage.add_child(mountain)
	mountain.set_developer_view(Rect2(440, -980, 260, 560), true, true)
	mountain.set_process(false)
	for key in mountain.developer_view_cells:
		mountain._ensure_chunk(key)
		await process_frame
	mountain.set_process(true)
	var deadline := Time.get_ticks_msec() + 200000
	while not mountain.is_streaming_idle() and Time.get_ticks_msec() < deadline: await process_frame
	var desert := DESERT.new()
	desert.initial_prewarm_only = true
	stage.add_child(desert)
	desert.set_process(false)
	var z := L.BOUNDS.position.y + 8.0
	while z < L.BOUNDS.end.y:
		desert.prepare_collision_at(Vector3(L.BOUNDS.end.x - 8.0, 0, z))
		z += 48.0
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 6000
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	stage.add_child(camera)
	camera.current = true
	for view in VIEWS:
		var target: Vector3 = VIEWS[view][0]
		target.y = mountain.terrain.surface_height_at(Vector2(target.x, target.z))
		camera.size = VIEWS[view][1]
		camera.position = target + CAMERA_OFFSET * 4.0
		camera.look_at(target)
		await _save(output.path_join("%s.png" % view))
	# Vista larga do canal, de sudeste: selo do deserto à esquerda, costa da serra à direita.
	var center := Vector3(500, 0, -700)
	camera.size = 640.0
	camera.position = center + Vector3(900, 1100, 700)
	camera.look_at(center)
	await _save(output.path_join("canal.png"))
	print("CANAL ", ProjectSettings.globalize_path(output), " serra ", mountain.chunks.size(), " deserto ", desert.chunks.size())
	desert.free()
	quit()

func _save(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
