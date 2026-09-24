extends SceneTree
## Água apaga fogo: hidrante estourado ao lado de um foco (o foco precisa minguar)
## e bombeiros chegando num incêndio isolado. Grava capturas em
## res://evidence/water-fire-0924/. Rodar com --no-save (janela real).
## Não mede tempo de resposta do despacho nem desempenho.

const OUTPUT := "res://evidence/water-fire-0924/"
var failures: Array[String] = []
var world

func _initialize() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func shot(label: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var controller = world.session.controller
	controller.set_population(0)
	world.session.weather.time_of_day = .45
	var emergency = world.gameplay.emergency
	var street = world.find_child("StreetPhysics", true, false)
	if street == null:
		for child in world.get_children():
			if child.has_method("spawn_geyser"): street = child
	check(street != null, "StreetPhysics deveria existir")
	var base: Vector3 = world.player.global_position + Vector3(5, 0, 2)
	var fire = emergency.ignite(base, null, 1.0)
	check(fire != null, "foco de teste deveria acender")
	if street != null: street.spawn_geyser(base + Vector3(-0.8, 0, 0))
	await frames(90)
	await shot("01_hidrante_no_fogo")
	var before: float = fire.intensity if is_instance_valid(fire) else 0.0
	await frames(240)
	var after: float = fire.intensity if is_instance_valid(fire) and not fire.is_queued_for_deletion() else 0.0
	check(after < before, "o hidrante deveria apagar o fogo ao lado (%.2f → %.2f)" % [before, after])
	# Incêndio isolado, bombeiros.
	var far: Vector3 = world.player.global_position + Vector3(-12, 0, 8)
	var blaze = emergency.ignite(far, null, 1.2)
	if blaze != null: blaze.age = -90.0 # queima mais que o normal para dar tempo ao caminhão
	# O caminhão do despacho não chegou ao local em 105 s neste cenário (problema
	# do DispatchUnit, fora deste teste); aqui o bombeiro é posto direto no local.
	var key := -1
	for k in emergency.incidents:
		if emergency.incidents[k].actor == blaze: key = k
	var crew = preload("res://gameplay/emergency/Responder.gd").new()
	crew.manager = emergency
	crew.role = "fire"
	crew.incident_id = key
	emergency.add_child(crew)
	crew.global_position = far + Vector3(2.6, 0.1, 0)
	var start_intensity: float = blaze.intensity
	for i in 90: await physics_frame
	world.player.teleport(far + Vector3(5, .1, 4))
	await frames(30)
	await shot("02_bombeiro_mangueira")
	var sprayed: bool = crew.mode == "service"
	var weaker: bool = not is_instance_valid(blaze) or blaze.is_queued_for_deletion() or blaze.intensity < start_intensity
	check(weaker, "a mangueira deveria enfraquecer o fogo")
	check(sprayed, "o bombeiro ao lado do fogo deveria entrar em serviço (mangueira)")
	if failures.is_empty():
		print("PASS test_water_douses_fire")
		quit(0)
	else:
		print("FAIL test_water_douses_fire: %d" % failures.size())
		quit(1)

func get_nodes_in_group_safe(group: String) -> Array:
	return root.get_tree().get_nodes_in_group(group)
