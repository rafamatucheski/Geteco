extends SceneTree
const LAYOUT := preload("res://activities/skate/SkateParkLayout.gd")
var world
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("SKATE_SESSION ", "PASS " if ok else "FAIL ", title)
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(2); return
	var session = world.session
	var skate = session.skate
	session.state.intro.stage = "complete"
	if not session.state.place_id.is_empty(): await session.leave_place()
	world.player.teleport(LAYOUT.ENTRY + Vector3(.8, .1, 0))
	world.production.region.set_focus(LAYOUT.ENTRY)
	await frames(180)
	print("SKATE_CONTEXT region=", session.state.region_id, " place=", session.state.place_id, " clock=", skate._clock, " processing=", skate.is_physics_processing(), " paused=", paused)
	var query := PhysicsRayQueryParameters3D.create(LAYOUT.CENTER + Vector3.UP * 3, LAYOUT.CENTER - Vector3.UP * 4, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.position.y < -1.5, "terreno produtivo não tampa o bowl")
	check(session.nearest().get("id") == "skate", "interação real encontra shape")
	check(session.interact() and skate.mounted, "pegar skate monta o próprio Dante")
	if not skate.mounted:
		print("SKATE_MOUNT_DIAGNOSTIC player=", world.player.position, " boards=", skate.boards.size(), " nearest=", session.nearest(), " park=", get_nodes_in_group("skate_park").size())
		world.free()
		quit(1)
		return
	await frames(5)
	check(world.player.visible and not world.player.is_physics_processing(), "Dante visível controlado pelo skate")
	var touch = world.find_child("AndroidControls", true, false)
	if touch != null:
		touch._refresh()
		check(touch.playable and touch.skating, "controles de toque continuam ativos com Dante sobre o skate")
		check(touch.buttons.has("skate_ollie") and touch.buttons.has("skate_flip") and touch.buttons.has("skate_shove") and touch.buttons.has("exit_vehicle"), "toque oferece ollie, flip, shove-it e saída")
	check(session.blocks_driving_change() and not session.save_block_reason().is_empty(), "embarque e save bloqueados durante passeio")
	var board = skate.player_board
	board.drive(0, 0, true)
	var before: float = world.gameplay.health
	board.bail(9)
	await frames(1)
	check(skate.recovering and world.gameplay.health < before, "queda tira vida e separa corpo do shape")
	await frames(150)
	check(not skate.controls_locked() and world.player.is_physics_processing() and world.player.collision_layer == 2, "recuperação devolve controles e colisão")
	world.player.teleport(board.position + Vector3(.8, .1, 0))
	await frames(10)
	print("SKATE_REPICK_DIAGNOSTIC player=", world.player.position, " board=", board.position, " speed=", board.speed, " nearest=", session.nearest(), " clear=", skate._clear_for_player(board.position, board), " ambient=", skate.ambient.size())
	check(session.interact() and skate.mounted, "shape caído pode ser pego novamente")
	board.speed = 0
	await frames(5)
	check(skate.dismount() and not skate.mounted, "descer encontra piso livre")
	check(skate.owned and skate.snapshot().owned, "posse integra snapshot")
	check(skate.ambient.size() >= 2, "skatistas ambientes usam física real")
	if not skate.ambient.is_empty():
		var npc_board = skate.ambient[0].board
		var actor = skate.ambient[0].actor
		npc_board.receive_damage(8, world.player)
		await frames(3)
		check(not npc_board.riding and actor.health < 100, "derrubar skatista deixa o skate disponível")
		await frames(100)
		world.player.teleport(npc_board.position + Vector3(.8, .1, 0))
		await frames(3)
		check(skate.nearest_action().get("id") == "skate", "skate do NPC derrubado oferece coleta")
		print("SKATE_NPC_PICK_DIAGNOSTIC nearest=", session.nearest(), " player=", world.player.position, " clear=", skate._clear_for_player(world.player.position, npc_board), " board=", npc_board.position)
		check(session.interact() and skate.mounted, "skate tomado do NPC pode ser usado sem atravessar o corpo")
	if skate.mounted:
		skate.player_board.queue_free()
		await frames(3)
		check(not skate.controls_locked() and world.player.is_physics_processing() and world.player.collision_layer == 2 and world.camera.target == world.player, "remoção do shape recupera Dante, colisão e câmera")
	print("SKATE_SESSION_RESULT checks=", checks, " failures=", failures)
	world.free()
	quit(1 if failures else 0)
