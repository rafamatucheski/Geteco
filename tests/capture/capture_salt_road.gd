extends SceneTree
## Capturas dos lugares da Estrada do Sal (Salinas, Balança, Motel Oásis) na sessão real: vista de
## fora com a câmera do jogo e de dentro dos cômodos abertos, de dia e de noite.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_salt_road.gd -- --no-save --no-traffic
## Saída em evidence/salt-road-20261020/ (fora do Git).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const FOLDER := "res://evidence/salt-road-20261020"
## [lugar, ponto local onde o jogador fica, rótulo]
const SHOTS := [
	["salt_works", Vector3(0, 0, 18), "salinas_galpao"],
	["salt_works", Vector3(0, 0, -16), "salinas_tanques"],
	["salt_works", Vector3(13.0, 0, 27.6), "salinas_escritorio"],
	["weigh_station", Vector3(0, 0, 11), "balanca_faixa"],
	["weigh_station", Vector3(-.6, 0, 2.6), "balanca_cabine"],
	["motel", Vector3(-2, 0, 6), "motel_patio"],
	["motel", Vector3(-14.1, 0, -3.2), "motel_quarto"],
	["motel", Vector3(10.0, 0, -1.6), "motel_recepcao"],
	["chapel", Vector3(0, 0, 6), "capela_frente"],
	["chapel", Vector3(0, 0, -3.5), "capela_dentro"],
	["grandstand", Vector3(0, 0, 8), "arquibancada"],
	["grandstand", Vector3(19.5, 0, .4), "torre_dentro"],
]
var world: Node3D
var session

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): print("SALT_ROAD watchdog"); quit(3))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame

func stand(point: Vector3) -> void:
	var at := Vector3(point.x, HM.surface_height(Vector2(point.x, point.z)) + .1, point.z)
	world.player.teleport(at)
	world.production.region.set_focus(at, true)
	await frames(4)

func shot(label: String) -> void:
	world.camera.initialized = false
	for i in 50: await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("%s/%s.png" % [FOLDER, label])
	root.get_texture().get_image().save_png(path)
	print("SALT_ROAD shot ", path)

func run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var first: Dictionary = LAYOUT.site("salt_works")
	var arrival := Vector3(first.center.x, 0, first.center.y + 70)
	var data := FIXTURE.full_snapshot(arrival, true)
	data.region_id = "desert"
	data.world.pedestrian = {"region": "desert", "position": [arrival.x, 0.1, arrival.z]}
	var path := FIXTURE.write_fixture(FIXTURE.output_dir("salt-road"), "checkpoint.json", data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	session = world.session
	if session.modal: session.close_menu()
	var roadside: Node3D = session.desert.frontier.roadside
	roadside.events._next_at = INF
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 100000.0
	var weather = session.weather
	for hour in [13.0, 21.5]:
		weather.time_of_day = hour / 24.0
		weather.time_scale = 0.0
		var approached := {}
		for entry in SHOTS:
			var id: String = entry[0]
			if not approached.has(id):
				# Passa a ~100 m antes: os carros estacionados nascem fora da tela (60–140 m).
				approached[id] = true
				await stand(LAYOUT.at(LAYOUT.site(id), Vector3(0, 0, 100)))
				for i in 120: await physics_frame
			await stand(LAYOUT.at(LAYOUT.site(id), entry[1]))
			var waited := 0
			while not roadside.sites.has(id) and waited < 600:
				await physics_frame
				waited += 1
			print("SALT_ROAD montado ", id, " ", roadside.sites.has(id))
			await shot("%s_%s" % [entry[2], "dia" if hour < 18.0 else "noite"])
	quit(0)
