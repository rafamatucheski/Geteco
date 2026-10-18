extends SceneTree
## Capturas do chão da serra na sessão real (renderizada): estrada do passo, encosta aberta,
## vila, entorno da forja e estrada alta na neve, de dia limpo e na nevasca. Serve de antes/depois
## do acabamento do terreno e do asfalto (GETECO_MOUNTAIN_GROUND=0 desliga o acabamento novo).
## Imagens em evidence/serra-terreno-20261018/<rótulo>/ (fora do Git). Não é medição de desempenho.
## Rodar com `-- --no-save --label=<rótulo>`.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const FORGE_SITE := preload("res://world/mountain_detail/forge/MountainForge.gd")
var world
var folder := ""
var shots: Array[String] = []

func _initialize() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("Captura do chão da serra passou de 900 s")
		quit(2))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Captura precisa de janela e --no-save"); quit(2); return
	var label := "antes"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	root.size = Vector2i(1600, 900)
	folder = ProjectSettings.globalize_path("res://evidence/serra-terreno-20261018/" + label)
	DirAccess.make_dir_recursive_absolute(folder)
	var snapshot := FIXTURE.full_snapshot(Vector3(80,0,80), true)
	snapshot.world.time = .45
	snapshot.world.weather = 0
	var save_path := FIXTURE.write_fixture(FIXTURE.output_dir("mountain-ground-capture"), "fixture.json", snapshot)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", save_path)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	print("CAPTURE_STEP carregando")
	while world.session == null or not world.session.ready_for_play: await physics_frame
	var session = world.session
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	session.weather.weather_state = 0
	session.weather.weather_timer = 9999
	var village: Vector3 = CATALOG._at(Vector2(7640,-1460), "mountain")
	var slope: Vector3 = CATALOG._at(Vector2(6750,-1100), "mountain")
	var views := [
		["estrada-passo", Vector3(650,0,-290)],
		["encosta", slope],
		["vila", village],
		["forja", FORGE_SITE.CENTER],
		["estrada-alta", Vector3(705,0,-470)],
	]
	for view in views:
		var focus: Vector3 = view[1]
		await go(focus, focus + Vector3(2,0,2))
		var road := nearest_road(focus)
		var eye: Vector3 = road[0]
		var ahead: Vector3 = road[1]
		# Jogador na beira da estrada, longe de portas (no centro de um lugar ele entrava no interior).
		await go(eye, eye)
		var terrain = world.production.region.get("terrain")
		for weather in [["dia", 0.0], ["nevasca", 120.0]]:
			set_weather(session, weather[1])
			# Altura de quem dirige: o jogador vê a estrada e o chão daqui.
			await shot("%s-%s-rua" % [view[0], weather[0]], eye + Vector3(0,2.2,0), ahead + Vector3(0,.6,0))
			var high := focus + Vector3(-26,0,30)
			if terrain != null: high.y = terrain.surface_height_at(Vector2(high.x,high.z))
			await shot("%s-%s-alto" % [view[0], weather[0]], high + Vector3(0,16,0), focus)
	print("MOUNTAIN_GROUND_CAPTURE ", folder, " ", shots)
	world.free()
	await process_frame
	quit(0)

## Relógio do frio: 0 = céu limpo, 120 = meio da frente (nevasca com granizo).
func set_weather(session, clock: float) -> void:
	session.cold.model.weather_clock = clock
	session.weather.time_of_day = .45
	session.weather._update()

## Ponto da estrada mais próximo do foco e outro 25 m adiante, para a câmera olhar ao longo dela.
func nearest_road(focus: Vector3) -> Array:
	var best := [focus, focus + Vector3(0,0,-25)]
	var best_distance := INF
	for road in world.production.region.roads:
		var points: PackedVector3Array = road.points
		for i in range(points.size()-1):
			var a := Vector2(points[i].x,points[i].z)
			var b := Vector2(points[i+1].x,points[i+1].z)
			var near := Geometry2D.get_closest_point_to_segment(Vector2(focus.x,focus.z),a,b)
			var distance := near.distance_to(Vector2(focus.x,focus.z))
			if distance < best_distance and a.distance_to(b) > 1.0:
				best_distance = distance
				var direction := (b-a).normalized()
				best = [Vector3(near.x,points[i].y,near.y), Vector3(near.x+direction.x*25.0,points[i].y,near.y+direction.y*25.0)]
	return best

func go(focus: Vector3, stand: Vector3) -> void:
	print("CAPTURE_STEP indo ", focus)
	world.production._update_physical_residency(focus)
	world.production._update_logical_region(focus)
	world.player.teleport(stand + Vector3(0,.2,0))
	await frames(30)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if world.production.region != null and world.production.region.has_method("is_streaming_idle") and world.production.region.is_streaming_idle(): break
		await process_frame
	await frames(90)

func frames(count: int) -> void:
	for i in count: await process_frame

func shot(label: String, eye: Vector3, target: Vector3) -> void:
	var camera := Camera3D.new()
	camera.fov = 62
	world.add_child(camera)
	camera.global_position = eye
	camera.look_at(target)
	camera.make_current()
	await frames(40)
	await RenderingServer.frame_post_draw
	print("CAPTURE_STEP foto ", label)
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
	shots.append(label)
	camera.queue_free()
	if is_instance_valid(world.camera): world.camera.make_current()
	await frames(2)
