extends SceneTree
## Vista de cima do mar do mundo orgânico (etapa 1, 26/10/2026): o WorldSea sozinho sobre o mundo inteiro
## e, numa segunda foto, o deserto montado por inteiro (como capture_desert_compact_overview) por cima do
## mar e do chão-base. Inspeção visual; não mede FPS.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_world_sea_overview.gd
const SEA := preload("res://world/shape/WorldSea.gd")
const REGION := preload("res://world/editing/EditableDesertRegion.gd")
const L := preload("res://world/desert/DesertLayout.gd")

class FakeProduction extends Node:
	var regions := {}

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("WORLD_SEA_OVERVIEW timeout"); quit(3))
	run.call_deferred()

func shot(camera: Camera3D, center: Vector3, width: float, path: String) -> void:
	camera.size = width * float(root.size.y) / float(root.size.x)
	camera.position = center + Vector3(0, 1800, 700)
	camera.look_at(center)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var output := "res://evidence/world-sea-overview-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1800, 1100)
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
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 6000
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	stage.add_child(camera)
	camera.current = true
	await shot(camera, Vector3(-300, 0, -520), 2900.0, ProjectSettings.globalize_path(output.path_join("mundo.png")))
	# Deserto inteiro por cima: cordilheiras sobre o chão-base e o mar além da costa.
	var region := REGION.new()
	region.initial_focus = Vector3(L.BOUNDS.get_center().x, 0, L.BOUNDS.get_center().y)
	stage.add_child(region)
	region.set_developer_view(L.BOUNDS, true, true)
	region.set_process(false)
	for key in region.developer_view_cells:
		region._complete_focus_chunk(key)
		await process_frame
	region.set_process(true)
	var deadline := Time.get_ticks_msec() + 180000
	while not region.is_streaming_idle() and Time.get_ticks_msec() < deadline: await process_frame
	await shot(camera, Vector3(-420, 0, -800), 2500.0, ProjectSettings.globalize_path(output.path_join("deserto.png")))
	print("WORLD_SEA_OVERVIEW ", output, " montagem ", sea.build_usec / 1000, " ms")
	quit()
