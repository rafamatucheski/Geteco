extends SceneTree
## "Jogar aqui" do editor de mundo: o jogo de verdade abre na região pedida, com Dante no
## ponto, sem gravar nada e com a peça editada (ainda não salva) já no lugar novo.
## Uso: --script res://tests/test_play_here.gd -- --no-save --skip-arrival --no-prewarm
##        --edits=<json> --play-at=<região>,<x>,<z> --expect-piece=<id> --expect-at=<x>,<z>
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FALHOU: " + label)
	else: print("ok  ", label)

func argument(name: String) -> String:
	for item in OS.get_cmdline_user_args():
		if item.begins_with(name + "="): return item.trim_prefix(name + "=")
	return ""

func run() -> void:
	var play := argument("--play-at").split(",")
	var expect_at := argument("--expect-at").split(",")
	var scene: Node = load("res://Main.tscn").instantiate()
	scene.set_meta("skip_arrival", true)
	root.add_child(scene)
	for i in 7200:
		await physics_frame
		if scene.session != null and scene.session.ready_for_play: break
	check(scene.session != null and scene.session.ready_for_play, "o jogo ficou pronto")
	if scene.session == null or not scene.session.ready_for_play:
		quit(1)
		return
	for i in 520: await physics_frame
	var state = scene.production.state
	check(state.region_id == play[0], "região = %s (%s)" % [play[0], state.region_id])
	var player: Node3D = scene.player
	var at := Vector2(player.global_position.x, player.global_position.z)
	check(at.distance_to(Vector2(play[1].to_float(), play[2].to_float())) < 4.0, "Dante nasceu perto do ponto (%s)" % str(player.global_position))
	check(scene.production.no_save, "nada é gravado (no_save)")
	var piece := argument("--expect-piece")
	if not piece.is_empty():
		var found: Node3D
		for group in PIECES.collect(scene):
			if "piece/" + str(group.get_meta("world_edit_piece_id")) == piece: found = group
		check(found != null, "peça editada existe no jogo: " + piece.substr(0, 60))
		if found != null:
			check(Vector2(found.global_position.x, found.global_position.z).distance_to(Vector2(expect_at[0].to_float(), expect_at[1].to_float())) < .1, "peça está na posição editada (%s)" % str(found.global_position))
	var capture := argument("--capture")
	if not capture.is_empty():
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
		print("CAPTURE ", capture)
	print("RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
