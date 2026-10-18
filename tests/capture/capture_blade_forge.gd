extends SceneTree
## Capturas da Forja da Serra na sessão real (renderizada): forja, ferreiro, cabana do
## Mestre Aurélio, acampamento do Tião no deserto e a faca lendária na mão. Save de teste
## isolado com a campanha concluída (o deserto exige). Imagens em evidence/forja-20261017/
## (fora do Git). Não é medição de desempenho. Rodar com `-- --no-save`.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const FORGE_SITE := preload("res://world/mountain_detail/forge/MountainForge.gd")
const HERMIT_SITE := preload("res://world/mountain_detail/forge/ForgeHermitCabin.gd")
const CAMP := preload("res://world/desert/DesertMinerCamp.gd")
const FORGE := preload("res://gameplay/forge/BladeForge.gd")
var world
var folder := ""
var shots: Array[String] = []

func _initialize() -> void:
	create_timer(560.0, true, false, true).timeout.connect(func():
		push_error("Blade forge capture exceeded 420 s")
		quit(2))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Captura precisa de janela e --no-save"); quit(2); return
	root.size = Vector2i(1600, 900)
	folder = ProjectSettings.globalize_path("res://evidence/forja-20261017")
	DirAccess.make_dir_recursive_absolute(folder)
	var snapshot := FIXTURE.full_snapshot(Vector3(80,0,80), true)
	snapshot.world.time = .45
	snapshot.world.weather = 0
	var save_path := FIXTURE.write_fixture(FIXTURE.output_dir("blade-forge-capture"), "fixture.json", snapshot)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", save_path)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	print("CAPTURE_STEP carregando")
	while world.session == null or not world.session.ready_for_play: await physics_frame
	print("CAPTURE_STEP sessao pronta")
	var session = world.session
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	session.weather.time_of_day = .45
	session.weather.weather_state = 0
	session.weather.weather_timer = 9999
	session.weather._update()

	# Forja: vista da porteira e o ferreiro na bigorna.
	await go(FORGE_SITE.CENTER, FORGE_SITE.CENTER + Vector3(4,.1,4))
	var forge: Node = await site("MountainForge")
	if forge != null: await wait_resident(forge.smith)
	await shot("01-forja-entrada", FORGE_SITE.CENTER + Vector3(9,7,34), FORGE_SITE.CENTER + Vector3(0,2,-4))
	await shot("02-forja-oficina", FORGE_SITE.CENTER + Vector3(4.5,2.6,3.5), FORGE_SITE.CENTER + Vector3(-2.5,1.0,-7))
	await shot("03-forja-alto", FORGE_SITE.CENTER + Vector3(-28,22,30), FORGE_SITE.CENTER)

	# Faca lendária na mão do Dante, perto da fornalha.
	session.state.grant_weapon("knife")
	var custom: Dictionary = world.gameplay.customization
	for track in FORGE.TRACKS:
		for i in FORGE.MAX_LEVEL: FORGE.install(custom, "knife", track)
	FORGE.install(custom, "knife", "legendary")
	world.gameplay.refresh_blade_visuals()
	session.state.equip_weapon("knife")
	var hand: Vector3 = FORGE_SITE.CENTER + Vector3(1.5,.1,-1.0)
	world.player.teleport(hand)
	await frames(40)
	var grip: Vector3 = world.gameplay.gun.global_position if is_instance_valid(world.gameplay.gun) else hand + Vector3.UP
	await shot("04-faca-lendaria", grip + Vector3(.55,.25,.75), grip)

	# Cabana do Mestre Aurélio no norte da serra.
	await go(HERMIT_SITE.CENTER, HERMIT_SITE.CENTER + Vector3(-3,.1,10))
	var cabin: Node = await site("ForgeHermitCabin")
	if cabin != null: await wait_resident(cabin.hermit)
	await shot("05-cabana-eremita", HERMIT_SITE.CENTER + Vector3(10,4.5,17), HERMIT_SITE.CENTER + Vector3(-1,1.5,0))
	await shot("06-cabana-alto", HERMIT_SITE.CENTER + Vector3(22,20,26), HERMIT_SITE.CENTER)

	# Acampamento do Tião, no deserto de verdade.
	var camp_at: Vector3 = CAMP.CENTER
	await go(camp_at, camp_at + Vector3(8,1.5,4))
	var camp: Node = null
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline and camp == null:
		for node in root.find_children("DesertMinerCamp", "Node3D", true, false): camp = node
		await process_frame
	if camp != null: await wait_resident(camp.miner)
	var ground: float = camp.global_position.y if camp != null else 0.0
	await shot("07-acampamento-tiao", camp_at + Vector3(9,ground+3.5,7), camp_at + Vector3(0,ground+.8,-.5))
	await shot("08-acampamento-alto", camp_at + Vector3(-20,ground+16,22), camp_at + Vector3(0,ground,0))
	print("BLADE_FORGE_CAPTURE ", folder, " ", shots, " camp=", camp != null)
	world.free()
	await process_frame
	quit(0)

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

func site(name: String) -> Node:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var found: Node = root.find_child(name, true, false)
		if is_instance_valid(found) and found.is_node_ready(): return found
		await process_frame
	return null

func wait_resident(resident: Node) -> void:
	for i in 300:
		await physics_frame
		if resident.available() and resident.actor.is_on_floor(): break
	await frames(20)

func frames(count: int) -> void:
	for i in count: await process_frame

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
	var path := folder.path_join(label + ".png")
	root.get_texture().get_image().save_png(path)
	shots.append(label)
	camera.queue_free()
	if is_instance_valid(world.camera): world.camera.make_current()
	await frames(2)
