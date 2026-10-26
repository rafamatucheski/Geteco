extends SceneTree
## Fotos da costa curva de Harbor (etapa 3 do mundo orgânico, 26/10/2026): vista de cima dos bairros prontos
## e uma vista baixa da beira, com o mar do mundo e Harbor montado por inteiro em volta (como
## capture_mountain_island). Inspeção visual; não mede FPS.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_harbor_coast.gd
const SEA := preload("res://world/shape/WorldSea.gd")
const EDITABLE := preload("res://world/editing/EditableRegion.gd")
const COAST := preload("res://world/shape/HarborCoast.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")

class FakeProduction extends Node:
	var regions := {}

func _initialize() -> void:
	create_timer(400).timeout.connect(func(): push_error("HARBOR_COAST_CAPTURE timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var output := "res://evidence/harbor-coast-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600, 1000)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8fb3c4")
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
	# Áreas fixas para a foto com GETECO_HARBOR_COAST=0 sair no mesmo enquadramento: mata a oeste e baía norte.
	var area := Rect2(-615, -295, 535, 510)
	var north := Rect2(-90, -300, 460, 310)
	var region = EDITABLE.build_region("harbor")
	region.initial_focus = Vector3(area.get_center().x, 0, area.get_center().y)
	stage.add_child(region)
	production.regions["harbor"] = region
	# A vista de desenvolvedor para nos registros da região (x ≈ −512); a ponta oeste da costa nova fica
	# além. No jogo o streaming monta as 3 × 3 células em volta do jogador, sem limite.
	var cells := area.merge(north).grow(32.0)
	region.set_developer_view(cells, true, false)
	region.set_process(false)
	for x in range(floori(cells.position.x / 64.0), ceili(cells.end.x / 64.0)):
		for z in range(floori(cells.position.y / 64.0), ceili(cells.end.y / 64.0)):
			region._ensure_chunk(Vector2i(x, z))
			await process_frame
	region.set_process(true)
	var deadline := Time.get_ticks_msec() + 200000
	while not region.is_streaming_idle() and Time.get_ticks_msec() < deadline: await process_frame
	var camera := Camera3D.new()
	camera.far = 6000
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	stage.add_child(camera)
	camera.current = true
	# De cima, levemente inclinada.
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = area.size.y + 120.0
	var center := Vector3(area.get_center().x, 0, area.get_center().y)
	camera.position = center + Vector3(0, 900, 360)
	camera.look_at(center)
	await _shot(output.path_join("oeste-cima.png"))
	# Baixa, da água olhando a praia norte da mata.
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 60
	camera.position = Vector3(-300, 9, -260)
	camera.look_at(Vector3(-300, 2, -150))
	await _shot(output.path_join("oeste-praia-norte.png"))
	# Divisa com a cidade: o corte em x = −80 ao sul.
	camera.position = Vector3(-40, 14, 260)
	camera.look_at(Vector3(-80, 0, 180))
	await _shot(output.path_join("oeste-divisa-sul.png"))
	# Ponta oeste, da água olhando a mata da pesca.
	camera.position = Vector3(-660, 18, -20)
	camera.look_at(Vector3(-560, 0, -20))
	await _shot(output.path_join("oeste-ponta.png"))
	# Baía norte de cima.
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = north.size.y + 120.0
	center = Vector3(north.get_center().x, 0, north.get_center().y)
	camera.position = center + Vector3(0, 900, 360)
	camera.look_at(center)
	await _shot(output.path_join("norte-cima.png"))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	# Da água ao norte olhando a baía e a cidade.
	camera.position = Vector3(100, 22, -330)
	camera.look_at(Vector3(100, 0, -60))
	await _shot(output.path_join("norte-baia.png"))
	# Cabeça da bacia do navio: o cais novo em z = −6,2.
	camera.position = Vector3(237, 12, 70)
	camera.look_at(Vector3(237, 0, -10))
	await _shot(output.path_join("norte-bacia.png"))
	# Começo da ponte norte.
	camera.position = Vector3(300, 16, -330)
	camera.look_at(Vector3(360, 0, -240))
	await _shot(output.path_join("norte-ponte.png"))
	print("HARBOR_COAST_CAPTURE ", output, " células ", region.chunks.size())
	quit()

func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
