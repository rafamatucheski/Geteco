extends SceneTree
## Vista de cima da serra ilha (etapa 4 do mundo orgânico, 26/10/2026): o mar do mundo e a serra montada
## por inteiro (como capture_desert_compact_overview), com o terreno descendo para o mar e o muro de pedra
## na costa. Inspeção visual; não mede FPS.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_mountain_island.gd
const SEA := preload("res://world/shape/WorldSea.gd")
const EDITABLE := preload("res://world/editing/EditableRegion.gd")
const SHAPE := preload("res://world/shape/WorldShape.gd")

class FakeProduction extends Node:
	var regions := {}

func _initialize() -> void:
	create_timer(400).timeout.connect(func(): push_error("MOUNTAIN_ISLAND_OVERVIEW timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var output := "res://evidence/mountain-island-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1400, 1300)
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
	var island: Rect2
	for item in SHAPE.islands():
		if item.id == "mountain": island = item.bounds
	var region = EDITABLE.build_region("mountain")
	region.initial_focus = Vector3(island.get_center().x, 0, island.get_center().y)
	stage.add_child(region)
	region.set_developer_view(island.grow(64.0), true, true)
	region.set_process(false)
	for key in region.developer_view_cells:
		region._ensure_chunk(key)
		await process_frame
	region.set_process(true)
	var deadline := Time.get_ticks_msec() + 200000
	while not region.is_streaming_idle() and Time.get_ticks_msec() < deadline: await process_frame
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 6000
	camera.size = island.size.y + 260.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	stage.add_child(camera)
	var center := Vector3(island.get_center().x - 60.0, 0, island.get_center().y)
	camera.position = center + Vector3(0, 1800, 700)
	camera.look_at(center)
	camera.current = true
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join("serra.png")))
	print("MOUNTAIN_ISLAND_OVERVIEW ", output, " células ", region.chunks.size())
	quit()
