extends SceneTree
## No jogo de verdade: Dante com a espada e escudo do gelo (parado, andando, golpes em sequência, escudo
## levantado) e, com `--gym`, uma série na academia Ferro Velho; com `--cabin`, dentro da Cabana do
## Cavaleiro. Folhas em evidence/sword-shield/<rótulo>/ (fora do Git). Janela real, nunca headless.
## Espada (chão aberto do deserto):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_sword_shield_session.gd -- --no-save --skip-arrival --play-at=desert,-1040,-1320 --label=espada
## Academia: ... -- --no-save --skip-arrival --play-at=harbor,22,62 --gym --label=academia
## Cabana:   ... -- --no-save --skip-arrival --play-at=mountain,655,-895 --cabin --label=cabana
const CROP := 320
const SCALE := 2
var world
var controls: Node
var label := "espada"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-save" not in args or DisplayServer.get_name() == "headless": quit(2); return
	for arg in args:
		if arg.begins_with("--label="): label = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/sword-shield/%s" % label))
	world = load("res://Main.tscn").instantiate(); root.add_child(world); current_scene = world
	var loading := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - loading) / 1000000.0 < 240.0:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	controls = root.get_node("GameInput")
	for i in 30: await physics_frame
	# A cortina de carregamento ainda cobre a tela uns segundos depois de `ready_for_play`.
	await seconds(6.0)
	var spots := ""
	for arg in args:
		if arg.begins_with("--spots="): spots = arg.get_slice("=", 1)
	if spots != "": await _spots(spots)
	elif "--gym" in args: await _gym()
	elif "--cabin" in args: await _cabin()
	else: await _sword()
	print("CAPTURE_SWORD_SHIELD ok ", label)
	quit(0)

func _sword() -> void:
	var state = world.session.state
	# Arma longa não vai na bolsa de mão: a captura dá a mochila, como no jogo depois do 1º prêmio.
	if state.economy.grid_enabled(): state.economy._data.grid_inventory.bag = "backpack"
	print("SWORD grant=", state.grant_weapon("sword_shield"), " equip=", state.equip_weapon("sword_shield"), " equipada=", state.equipped_weapon)
	await seconds(1.5)
	await sheet("1_parado", [0.0, 0.6, 0.6])
	controls.touch_move = Vector2(0, -1)
	await seconds(0.8)
	await sheet("2_andando", [0.0, 0.18, 0.18])
	controls.touch_move = Vector2.ZERO
	await seconds(0.8)
	for hit in 3:
		Input.action_press("fire")
		await physics_frame
		await physics_frame
		Input.action_release("fire")
		await sheet("3_golpe_%d" % (hit + 1), [0.0, 0.15, 0.2, 0.25, 0.3])
	await seconds(0.8)
	Input.action_press("aim")
	await seconds(0.6)
	await sheet("4_escudo", [0.0, 0.5])
	print("SHIELD block=", world.gameplay.shield_block)
	# Escudo erguido + ataque: chute espartano. Chamado direto no Gameplay: o clique simulado só pega
	# o 1º golpe (o FullSession quer um aperto novo de verdade para arma não automática).
	var g = world.gameplay
	print("KICK pronto=", g.attack_allowed(), " melee_vazio=", g._melee_action.is_empty(), " contato_pendente=", g._pending_contact.is_empty(), " fire_at=", g.fire_at(g.aim_point), " clip=", g._clip_name)
	await sheet("5_chute", [0.0, 0.2, 0.25])
	Input.action_release("aim")

func _gym() -> void:
	var session = world.session
	var gym: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_gym")
	world.player.teleport(gym.entry_position + Vector3(0, .2, 4))
	await seconds(5.0)
	await sheet("0_fachada", [0.0])
	print("GYM enter=", await session.enter_place("harbor_gym", false))
	await seconds(4.0)
	await sheet("1_entrada", [0.0])
	var room = session.room
	if room == null or not room.has_method("start_game"): print("GYM sem sala"); return
	for station in ["punching_bag", "treadmill", "push_up"]:
		world.player.global_position = room.interaction_points[station]
		await seconds(0.4)
		print("GYM %s action=%s" % [station, JSON.stringify(room.nearest_action(session))])
		print("GYM %s start=%s" % [station, room.start_game(station, session)])
		await sheet("2_" + station, [0.6, 0.8, 0.8])
		await seconds(room.SET_SECONDS)
		print("GYM %s depois=%s" % [station, JSON.stringify(preload("res://activities/gym/GymState.gd").data(session.state.world_state))])

func _cabin() -> void:
	var session = world.session
	var cabin: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition("mountain_cabin_secret")
	world.player.teleport(cabin.entry_position + Vector3(0, 1.0, 3))
	await seconds(6.0)
	await sheet("1_fora", [0.0])
	print("CABIN enter=", await session.enter_place("mountain_cabin_secret", false))
	await seconds(4.0)
	await sheet("2_dentro", [0.0])

## Terrenos candidatos ("x,z;x,z"): uma foto da tela inteira em cada, para ver rua, calçada e vizinhos.
func _spots(spots: String) -> void:
	for spot in spots.split(";"):
		var xz := spot.split(",")
		var at := Vector3(float(xz[0]), 1.0, float(xz[1]))
		world.player.teleport(at)
		await seconds(5.0)
		await sheet("lote_%s_%s" % [xz[0], xz[1]], [0.0])

func seconds(value: float) -> void:
	var start := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start) / 1000000.0 < value: await process_frame

## Uma coluna por espera (s, contada da anterior); recorte quadrado em volta do Dante e a tela inteira da 1ª.
func sheet(name: String, waits: Array) -> void:
	var tile := CROP * SCALE
	var image := Image.create(tile * waits.size(), tile, false, Image.FORMAT_RGBA8)
	for column in waits.size():
		await seconds(float(waits[column]))
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		var center := Vector2(shot.get_width(), shot.get_height()) * 0.5 + Vector2(0, -0.02 * shot.get_height())
		var corner := Vector2i(clampi(int(center.x) - CROP / 2, 0, shot.get_width() - CROP), clampi(int(center.y) - CROP / 2, 0, shot.get_height() - CROP))
		var crop := shot.get_region(Rect2i(corner, Vector2i(CROP, CROP)))
		crop.resize(tile, tile, Image.INTERPOLATE_LANCZOS)
		image.blit_rect(crop, Rect2i(Vector2i.ZERO, Vector2i(tile, tile)), Vector2i(column * tile, 0))
		if column == 0: shot.save_jpg(ProjectSettings.globalize_path("res://evidence/sword-shield/%s/%s_tela.jpg" % [label, name]), 0.85)
		print("SHOT %s %d clip=%s arma=%s" % [name, column, world.player.combat_clip, world.session.state.equipped_weapon])
	image.save_png(ProjectSettings.globalize_path("res://evidence/sword-shield/%s/%s.png" % [label, name]))
