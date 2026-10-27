extends SceneTree
## Revisão visual dos prédios da serra na sessão real (renderizada): fachada de cada lugar,
## Refúgio da Serra, forja, cabana do eremita, vila, madeireira e teleférico, e o interior de
## cada lugar com porta. Save de teste isolado com a campanha concluída. Imagens em
## evidence/serra-predios-20261027/ (fora do Git). Não é medição de desempenho.
## Rodar com `-- --no-save`; `--only=refugio,eremita,fachadas,sitios,interiores,loja` limita os
## grupos, `--label=<pasta>` grava numa subpasta (antes/depois) e `--hour=21` muda a hora.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const REFUGE := preload("res://world/mountain_detail/MountainRefuge.gd")
const FORGE_SITE := preload("res://world/mountain_detail/forge/MountainForge.gd")
const HERMIT_SITE := preload("res://world/mountain_detail/forge/ForgeHermitCabin.gd")
const EXTERIORS := ["mountain_bunker", "ski_lodge", "mountain_boutique", "mountain_cabin", "mountain_cabin_encosta", "mountain_cabin_forest", "lumberjack_shelter", "mountain_outfitters", "mountain_gunshop", "mountain_village_outfitters", "mountain_cabin_village_1"]
const INTERIORS := ["mountain_bunker", "ski_lodge", "mountain_cabin", "mountain_cabin_encosta", "mountain_cabin_forest", "lumberjack_shelter", "mountain_boutique", "mountain_gunshop", "mountain_mystery_cave", "mountain_cabin_village_1"]
var world
var folder := ""
var shots: Array[String] = []
var only: PackedStringArray = []
var day_time := .45

func _initialize() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("Captura da serra passou de 900 s")
		quit(2))
	run.call_deferred()

func wants(group: String) -> bool:
	return only.is_empty() or group in only

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Captura precisa de janela e --no-save"); quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=").split(",")
		if arg.begins_with("--label="): folder = arg.trim_prefix("--label=")
		if arg.begins_with("--hour="): day_time = float(arg.trim_prefix("--hour=")) / 24.0
	root.size = Vector2i(1600, 900)
	folder = ProjectSettings.globalize_path("res://evidence/serra-predios-20261027" + ("" if folder.is_empty() else "/" + folder))
	DirAccess.make_dir_recursive_absolute(folder)
	var start: Vector3 = PLACES.get_definition("ski_lodge").exterior_position
	var snapshot := FIXTURE.full_snapshot(start + Vector3(0,0,14), true)
	snapshot.world.time = day_time
	snapshot.world.weather = 0
	var save_path := FIXTURE.write_fixture(FIXTURE.output_dir("mountain-buildings-capture"), "fixture.json", snapshot)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", save_path)
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	print("CAPTURE_STEP carregando")
	while world.session == null or not world.session.ready_for_play: await physics_frame
	var session = world.session
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	session.weather.time_of_day = day_time
	session.weather.weather_state = 0
	session.weather.weather_timer = 99999
	session.weather._update()

	if wants("refugio"):
		var c := REFUGE.CENTER
		await go(c, c + Vector3(-12,0,4))
		var y := ground(c.x - 6, c.z)
		await shot("refugio-01-frente", Vector3(c.x - 15, y + 4.5, c.z + 7), Vector3(c.x, y + 1.0, c.z))
		await shot("refugio-02-alto", Vector3(c.x - 20, y + 16, c.z + 18), Vector3(c.x, y, c.z))
		await shot("refugio-03-chao", Vector3(c.x - 9, y + 1.7, c.z - 7), Vector3(c.x - 2, y + .2, c.z + 2))
		await shot("refugio-04-lado", Vector3(c.x + 4, y + 3, c.z + 14), Vector3(c.x, y + .5, c.z))
	if wants("eremita"):
		var h := HERMIT_SITE.CENTER
		await go(h, h + Vector3(0,0,14))
		var y := ground(h.x, h.z + 6)
		await shot("eremita-01-frente", Vector3(h.x + 7, y + 4.5, h.z + 15), Vector3(h.x, y + 1.0, h.z + 1))
		await shot("eremita-02-alto", Vector3(h.x - 16, y + 15, h.z + 20), Vector3(h.x, y, h.z))
	if wants("loja"):
		await interior("mountain_boutique")
	if wants("fachadas"):
		for id in EXTERIORS:
			var at: Vector3 = PLACES.get_definition(id).exterior_position
			await go(at, at + Vector3(0,0,10))
			var y := ground(at.x, at.z + 8)
			var reach := 26.0 if id == "mountain_bunker" else 15.0
			await shot("fachada-" + id + "-a", Vector3(at.x + reach * .35, y + reach * .28, at.z + reach), Vector3(at.x, y + 2.0, at.z))
			await shot("fachada-" + id + "-b", Vector3(at.x - reach * .7, y + reach * .45, at.z - reach * .6), Vector3(at.x, y + 1.5, at.z))
	if wants("sitios"):
		var sites := {"forja": FORGE_SITE.CENTER, "eremita": HERMIT_SITE.CENTER, "vila": PLACES._at(Vector2(7560,-1650),"mountain"), "madeireira": PLACES._at(Vector2(6350,560),"mountain"), "teleferico": PLACES._at(Vector2(7465,-3952.5),"mountain")}
		for label in sites:
			var at: Vector3 = sites[label]
			await go(at, at + Vector3(0,0,12))
			var y := ground(at.x, at.z + 10)
			await shot("sitio-" + label + "-a", Vector3(at.x + 10, y + 9, at.z + 28), Vector3(at.x, y + 1.5, at.z))
			await shot("sitio-" + label + "-b", Vector3(at.x - 24, y + 18, at.z - 16), Vector3(at.x, y, at.z))
	if wants("interiores"):
		for id in INTERIORS:
			await interior(id)
	print("MOUNTAIN_BUILDINGS_CAPTURE ", folder, " ", shots)
	world.free()
	await process_frame
	quit(0)

func interior(id: String) -> void:
	var definition: Dictionary = PLACES.get_definition(id)
	await go(definition.exterior_position, definition.entry_position)
	world.player.teleport(definition.entry_position + Vector3.UP * .08)
	await frames(8)
	if not await world.session.enter_place(id, false, id):
		print("CAPTURE_STEP falhou entrar ", id)
		return
	await frames(60)
	var room: Node3D = world.session.room
	await game_shot("interior-" + id + "-jogo")
	if is_instance_valid(room):
		var size: Vector2 = definition.size
		await shot("interior-" + id + "-alto", room.to_global(Vector3(size.x * .3, 4.6, size.y * .5 + 1.5)), room.to_global(Vector3(-size.x * .1, .6, -size.y * .2)))
		await shot("interior-" + id + "-olho", room.to_global(Vector3(size.x * .38, 1.65, size.y * .38)), room.to_global(Vector3(-size.x * .3, 1.0, -size.y * .4)))
	await world.session.leave_place()
	await frames(20)

func go(focus: Vector3, stand: Vector3) -> void:
	print("CAPTURE_STEP indo ", focus)
	world.production._update_physical_residency(focus)
	world.production._update_logical_region(focus)
	world.player.teleport(stand)
	await frames(30)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if world.production.region != null and world.production.region.has_method("is_streaming_idle") and world.production.region.is_streaming_idle(): break
		await process_frame
	await frames(60)

func ground(x: float, z: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 900, z), Vector3(x, -200, z), 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else 0.0

func frames(count: int) -> void:
	for i in count: await process_frame

func game_shot(label: String) -> void:
	await frames(10)
	await RenderingServer.frame_post_draw
	print("CAPTURE_STEP foto ", label)
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
	shots.append(label)

func shot(label: String, eye: Vector3, target: Vector3) -> void:
	var camera := Camera3D.new()
	camera.fov = 62
	world.add_child(camera)
	camera.global_position = eye
	camera.look_at(target)
	camera.make_current()
	await frames(25)
	await RenderingServer.frame_post_draw
	print("CAPTURE_STEP foto ", label)
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
	shots.append(label)
	camera.queue_free()
	if is_instance_valid(world.camera): world.camera.make_current()
	await frames(2)
