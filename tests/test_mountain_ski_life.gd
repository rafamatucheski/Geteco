extends SceneTree
## Esquiadores de fundo e trajes de locação do Cume Branco (20/10/2026) na sessão real: os oito montam
## perto da área, descem e sobem pelo teleférico, ficam escondidos longe; a escolha do traje passa pelo
## save, veste o Dante e protege do frio como o conjunto antigo.
## Uso (com tela): "$GODOT" --path . --script res://tests/test_mountain_ski_life.gd -- --no-save --no-traffic
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PROGRESSION := preload("res://activities/MountainProgression.gd")
const THERMAL := preload("res://runtime/cold/ThermalState.gd")
const SKIERS := preload("res://activities/mountain_ski/MountainSkiers.gd")
var world: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): failures.append("watchdog 300 s"); finish(3))
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("MOUNTAIN_SKI_LIFE ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args(), "--no-save obrigatório"): finish(2); return
	root.size = Vector2i(1280, 720)
	# Save: traje válido entra, traje inventado é recusado, save antigo sem a chave continua válido.
	var base := {"version": 1, "rental": true, "equipment": true, "rental_serial": 1, "best": {}, "shadow_announced": false}
	check(PROGRESSION.validate_snapshot(base), "save antigo sem traje continua válido")
	for suit in PROGRESSION.SUITS:
		var with_suit := base.duplicate()
		with_suit.suit = suit
		check(PROGRESSION.validate_snapshot(with_suit), "traje %s aceito no save" % suit)
		check(float(THERMAL.PROTECTION.get(suit, 0.0)) >= .9, "traje %s protege do frio" % suit)
	var bad := base.duplicate()
	bad.suit = "dante_pijama"
	check(not PROGRESSION.validate_snapshot(bad), "traje inventado recusado")
	var arrival := Vector3(713, .1, -606)
	var data := FIXTURE.full_snapshot(arrival, true)
	data.region_id = "mountain"
	data.world.pedestrian = {"region": "mountain", "position": [arrival.x, arrival.y, arrival.z]}
	data.world.time = 11.0 / 24.0
	var path := FIXTURE.write_fixture(FIXTURE.output_dir("mountain-ski-life"), "checkpoint.json", data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.get("session") != null and world.session.ready_for_play, "sessão da serra carregou"): finish(1); return
	var session = world.session
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	session.weather.time_of_day = 11.0 / 24.0
	session.weather.time_scale = 0.0
	var progression = session.mountain_progression
	var skiers: Node = progression.skiers
	if not check(is_instance_valid(skiers), "MountainProgression instala os esquiadores"): finish(1); return
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and skiers.skiers.size() < SKIERS.COUNT: await physics_frame
	check(skiers.skiers.size() == SKIERS.COUNT, "%d esquiadores montam perto da área" % skiers.skiers.size())
	var states := {}
	var before := []
	for skier in skiers.skiers:
		states[skier.state] = true
		before.append((skier.root as Node3D).global_position)
	check(states.has("ski") and states.has("lift"), "uns descem, outros sobem no teleférico")
	for i in 60: await physics_frame
	var moved := 0
	for i in skiers.skiers.size():
		if (skiers.skiers[i].root as Node3D).global_position.distance_to(before[i]) > 1.0: moved += 1
	check(moved == skiers.skiers.size(), "todos se mexem (%d)" % moved)
	for skier in skiers.skiers:
		if skier.state != "ski": continue
		var at: Vector3 = (skier.root as Node3D).global_position
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20, at - Vector3.UP * 20, 1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and absf(at.y - hit.position.y) < .6, "esquiador na neve (%.2f m)" % (at.y - (hit.position.y if not hit.is_empty() else 0.0)))
		break
	# Traje: alugado com escolha, o Dante veste o escolhido.
	progression.data.rental = true
	progression.data.equipment = true
	progression.data.suit = "dante_ski_neon"
	session.apply_outfit()
	await process_frame
	check(progression.suit_outfit() == "dante_ski_neon" and str(world.player.get("outfit_id")) == "dante_ski_neon", "Dante veste o traje escolhido")
	progression.data.rental = false
	session.apply_outfit()
	# Longe da área, ficam escondidos e não andam.
	var far := Vector3(arrival.x + 400, .1, arrival.z)
	world.player.teleport(far)
	world.production.region.set_focus(far, true)
	for i in 20: await physics_frame
	var hidden := true
	for skier in skiers.skiers: hidden = hidden and not (skier.root as Node3D).visible
	check(hidden, "longe da área os esquiadores ficam escondidos")
	finish(0 if failures.is_empty() else 1)

func finish(code: int) -> void:
	print("MOUNTAIN_SKI_LIFE checks=%d failures=%s" % [checks, failures])
	quit(code if failures.is_empty() or code != 0 else 1)
