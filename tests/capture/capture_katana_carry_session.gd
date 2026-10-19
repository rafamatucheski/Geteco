extends SceneTree
## No jogo de verdade (Main.tscn, câmera do jogo e Gameplay inteiro): Dante com a katana parado, andando,
## correndo, dando meia-volta, parando e golpeando andando. Recortes em volta do Dante, ampliados, numa
## folha por estado em evidence/katana-locomotion/<rótulo>/jogo_*.png (fora do Git). Janela real.
## Precisa de chão aberto (andando para a frente a partir do ponto inicial do Harbor ele entra num prédio):
## tools/run_godot_locked.sh --path . --script res://tests/capture/capture_katana_carry_session.gd -- --no-save --skip-arrival --play-at=desert,-1040,-1320 --label=jogo
const CROP := 300
const SCALE := 2
var world
var controls: Node
var label := "jogo"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/katana-locomotion/%s" % label))
	world = load("res://Main.tscn").instantiate(); root.add_child(world); current_scene = world
	# O deserto leva bem mais que o Harbor para ficar jogável: espera por tempo, não por quadros.
	var loading := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - loading) / 1000000.0 < 240.0:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	controls = root.get_node("GameInput")
	var state = world.session.state
	for i in 30: await physics_frame
	state.grant_weapon("katana"); state.equip_weapon("katana")
	await seconds(1.5)
	await sheet("jogo_1_parado", [0.0, 0.5, 0.5])
	controls.touch_move = Vector2(0, -1)
	await seconds(0.8)
	await sheet("jogo_2_andando", [0.0, 0.15, 0.15])
	controls.touch_sprint = true
	await seconds(0.8)
	await sheet("jogo_3_correndo", [0.0, 0.15, 0.15])
	controls.touch_move = Vector2(0, 1)
	await sheet("jogo_4_meia_volta", [0.0, 0.08, 0.08, 0.3])
	controls.touch_sprint = false
	controls.touch_move = Vector2.ZERO
	await sheet("jogo_5_parando", [0.0, 0.12, 0.12, 0.5])
	controls.touch_move = Vector2(-1, 0)
	await seconds(0.6)
	Input.action_press("fire")
	await physics_frame
	await physics_frame
	Input.action_release("fire")
	await sheet("jogo_6_golpe_andando", [0.0, 0.15, 0.3, 0.6])
	controls.touch_move = Vector2.ZERO
	print("CAPTURE_KATANA_SESSION ok ", label)
	quit(0)

func seconds(value: float) -> void:
	var start := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start) / 1000000.0 < value: await process_frame

## Uma linha por espera (s, contada da linha anterior); recorte quadrado em volta do Dante.
func sheet(name: String, waits: Array) -> void:
	var tile := CROP * SCALE
	var image := Image.create(tile * waits.size(), tile, false, Image.FORMAT_RGBA8)
	for column in waits.size():
		await seconds(float(waits[column]))
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		# A câmera do jogo segue o Dante no centro da tela (projetar pela câmera do mundo caía longe dele).
		var center := Vector2(shot.get_width(), shot.get_height()) * 0.5 + Vector2(0, -0.02 * shot.get_height())
		var corner := Vector2i(clampi(int(center.x) - CROP / 2, 0, shot.get_width() - CROP), clampi(int(center.y) - CROP / 2, 0, shot.get_height() - CROP))
		var crop := shot.get_region(Rect2i(corner, Vector2i(CROP, CROP)))
		crop.resize(tile, tile, Image.INTERPOLATE_LANCZOS)
		image.blit_rect(crop, Rect2i(Vector2i.ZERO, Vector2i(tile, tile)), Vector2i(column * tile, 0))
		if column == 0: shot.save_jpg(ProjectSettings.globalize_path("res://evidence/katana-locomotion/%s/%s_tela.jpg" % [label, name]), 0.85)
		var pose: Dictionary = world.player.combat_weapon_pose
		print("SHOT %s %d speed=%.2f clip=%s two_hands=%.2f" % [name, column, Vector2(world.player.velocity.x, world.player.velocity.z).length(), world.player.combat_clip, float(pose.get("left_weight", -1.0))])
	image.save_png(ProjectSettings.globalize_path("res://evidence/katana-locomotion/%s/%s.png" % [label, name]))
