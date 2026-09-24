extends SceneTree
## Ursos de Mountain no mundo de produção: nascem perto da toca, a ursa ataca o
## jogador exposto, filhotes existem e o urso morre com dano. Rodar com --no-save.
## Também grava uma captura em res://evidence/mountain-bears-0924/.
## Não mede equilíbrio de dano nem desempenho.

const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const OUTPUT := "res://evidence/mountain-bears-0924/"
var failures: Array[String] = []
var world

func _initialize() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var controller = world.session.controller
	controller.travel("mountain")
	for i in 900:
		await process_frame
		if not controller.travel_busy and controller.state.region_id == "mountain": break
	world.session.weather.time_of_day = .45
	var den: Vector3 = CATALOG._at(Vector2(8220, -1150), "mountain")
	var region = controller.regions.get("mountain")
	var stand := den + Vector3(9, 0, 0)
	stand.y = region.terrain.surface_height_at(Vector2(stand.x, stand.z)) + .2
	world.player.teleport(stand)
	region.set_focus(stand)
	await frames(90)
	var adults := root.get_tree().get_nodes_in_group("bear_adult")
	var cubs := root.get_tree().get_nodes_in_group("bear_cub")
	check(adults.size() >= 1, "a toca da ursa deveria ter uma adulta perto do jogador")
	check(cubs.size() == 2, "a ursa deveria ter dois filhotes (tem %d)" % cubs.size())
	var gameplay = world.gameplay
	var start_health: float = gameplay.health
	var engaged := false
	for i in 600:
		await physics_frame
		for bear in adults:
			if not is_instance_valid(bear): continue
			var gap := Vector2(bear.global_position.x - world.player.global_position.x, bear.global_position.z - world.player.global_position.z).length()
			if i % 60 == 0: print("BEAR t=%d estado=%d dist=%.1f y=%.1f vida_jogador=%.0f" % [i, bear.state, gap, bear.global_position.y, gameplay.health])
			# Perseguir também conta: na V1 a caçada acontece no estado padrão.
			if bear.state != bear.State.WANDER or gap < 2.5: engaged = true
		if gameplay.health < start_health: break
	check(engaged, "a ursa deveria avisar/perseguir/investir com o jogador a 9 m da toca")
	check(gameplay.health < start_health, "a ursa deveria ferir o jogador em até 10 s (vida %.0f → %.0f)" % [start_health, gameplay.health])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + "ursa_atacando.png"))
	if not adults.is_empty() and is_instance_valid(adults[0]):
		adults[0].receive_damage(400.0, null)
		check(adults[0].dead, "400 de dano deveria matar a ursa (vida 360)")
		check(adults[0].collision_layer == 0, "ursa morta não deveria bloquear tiro nem passagem")
	# Longe da toca os ursos saem de cena.
	var away := den + Vector3(0, 0, 400)
	world.player.teleport(away)
	region.set_focus(away)
	await frames(90)
	check(root.get_tree().get_nodes_in_group("bear_adult").filter(func(b): return not b.is_queued_for_deletion()).size() <= 1, "longe da toca da ursa ela deveria sair de cena")
	if failures.is_empty():
		print("PASS test_mountain_bears")
		quit(0)
	else:
		print("FAIL test_mountain_bears: %d falha(s)" % failures.size())
		quit(1)
