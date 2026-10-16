extends SceneTree

## Entrada a pé pela fachada pintada da delegacia (jogo de verdade, Main.tscn):
## o jogador anda (controle automático, como o teste de portas) até a porta dupla pintada
## HARBOR PATROL; as duas folhas abrem juntas pelo empurrão e ele passa para o interior.
## Repete com 3 estrelas: a delegacia não está na lista de lojas pacíficas, então a
## admissão não depende de estrelas. Uso: -- --no-save

const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world: Node3D
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PAINTED_POLICE_ENTRY PASS " if ok else "PAINTED_POLICE_ENTRY FAIL ") + label)
	if not ok:
		failures.append(label)
		push_error(label)

func wait_until(predicate: Callable, count: int) -> bool:
	for i in count:
		if predicate.call(): return true
		await physics_frame
	return false

func find_facade() -> Node3D:
	for candidate in get_nodes_in_group("v2_walkin_facade"):
		if candidate.get_meta("place_id", "") == "harbor_police": return candidate
	return null

func leaves_of(facade: Node3D) -> Array:
	# Só a frente: os fundos também têm uma folha pintada (fechada, sem interior).
	var result := []
	for anchor in facade.find_children("Doorway_front", "Node3D", true, false):
		for leaf in anchor.find_children("Door*", "", true, false):
			if leaf is PaintedFacadeKit.PaintedDoor: result.append(leaf)
	return result

## Anda até `target` no plano XZ; devolve a maior abertura vista nas folhas.
func walk_in(player: CharacterBody3D, facade: Node3D, inward: Vector3, seconds: float) -> float:
	var peak := 0.0
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and world.session.state.place_id != "harbor_police":
		player.automatic_direction = inward
		for leaf in leaves_of(facade): peak = maxf(peak, leaf.open_amount)
		await physics_frame
	player.automatic_direction = Vector3.ZERO
	return peak

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Run with --no-save")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play and world.production.ready_for_play, 1800):
		check(false, "world ready")
		quit(1)
		return
	var session = world.session
	var player: CharacterBody3D = world.player
	player.controlled_automatically = true
	player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	var definition: Dictionary = PLACES.get_definition("harbor_police")
	var door: Vector3 = session.weapon_shop_entrance._door_position("harbor_police", definition)
	var inward := Vector3.FORWARD.rotated(Vector3.UP, float(definition.get("editor_rotation", 0)))
	for stars in [0, 3]:
		var tag := "estrelas=%d: " % stars
		world.gameplay.stars = stars
		world.production.region.set_focus(door)
		player.teleport(door - inward * 6.0 + Vector3(0, .08, 0))
		await wait_until(func(): return is_instance_valid(find_facade()), 240)
		var facade := find_facade()
		check(is_instance_valid(facade), tag + "fachada da delegacia carregada")
		if not is_instance_valid(facade): break
		for i in 30: await physics_frame
		var leaves := leaves_of(facade)
		check(leaves.size() == 2, tag + "porta dupla pintada (%d folhas)" % leaves.size())
		for leaf in leaves: check(is_zero_approx(leaf.open_amount), tag + "folha começa fechada")
		var peak := await walk_in(player, facade, inward, 14.0)
		check(peak > .85, tag + "as duas folhas abriram (pico %.2f)" % peak)
		var both := true
		for leaf in leaves_of(facade): both = both and is_instance_valid(leaf)
		check(both, tag + "folhas continuam ligadas")
		var inside: bool = await wait_until(func(): return session.state.place_id == "harbor_police" and is_instance_valid(session.room), 240)
		check(inside, tag + "passou pela porta e entrou na delegacia")
		if inside:
			for i in 10: await physics_frame
			check(session.position_clear(session.room.spawn_position + Vector3.UP * .04), tag + "interior com ponto de entrada livre")
			# Volta para fora andando de costas para a porta (a saída é a mesma folha).
			player.teleport(session.room.exit_position + Vector3(0, .08, -.53))
			for i in 5: await physics_frame
			player.automatic_direction = Vector3.BACK
			var out: bool = await wait_until(func(): return session.state.place_id.is_empty() and not is_instance_valid(session.room), 360)
			player.automatic_direction = Vector3.ZERO
			check(out, tag + "saiu de volta pela mesma porta")
			for i in 60: await physics_frame
		else:
			break
	print("PAINTED_POLICE_ENTRY failures=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
