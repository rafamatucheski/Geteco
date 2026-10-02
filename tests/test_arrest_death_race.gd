extends SceneTree
## R5b: arrest_player real, morte real após 1 s e resgate sem acelerar timers.
## --no-save obrigatório; APPDATA temporário deve ser fornecido pelo executor.
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const PRESENTATION_MIN_SECONDS := 2.15 # 2.2 s autorados, margem fixa de 50 ms de amostragem.
var world: Node3D
var failures: Array[String] = []
var checks := 0
var respawns := 0
var previous_health := 100.0
var overlay_lifetime := -1.0
var rescued_position := Vector3.INF

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("R5B PASS " if ok else "R5B FAIL ") + label)
	if not ok: failures.append(label)

func _new_world() -> bool:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var ready: bool = world.session != null and world.session.ready_for_play
	check(ready, "sessão real pronta")
	if not ready: return false
	check(world.production.no_save and world.session.state.place_id.is_empty(), "contexto exterior sem save pessoal")
	return world.production.no_save and world.session.state.place_id.is_empty()

func _health_changed() -> void:
	var health: float = world.gameplay.health
	if previous_health <= 0.0 and health > 0.0: respawns += 1
	previous_health = health

func _overlay_exited(start: int) -> void:
	overlay_lifetime = (Time.get_ticks_usec() - start) / 1000000.0

func _arrest() -> bool:
	world.gameplay.register_crime(12, world.player.global_position)
	check(world.gameplay.stars == 1, "crime real inicia uma estrela")
	check(world.gameplay.police_case.request_surrender(), "rendição real aceita")
	var accepted: bool = world.gameplay.arrest_player()
	check(accepted and world.session.arrest_pending, "arrest_player inicia custódia")
	check(is_instance_valid(world.session.death_presentation) and world.session.death_presentation.name == "ArrestPresentation", "overlay de prisão presente")
	return accepted

func _await_completion(label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not world.session.rescue_pending and not world.session.arrest_pending and not world.session.respawn_busy:
			rescued_position = world.player.global_position
			check(world.gameplay.health > 0 and not world.player.input_locked and world.player.is_physics_processing(), label + " controle vivo restaurado")
			check(world.player.collision_layer == 2 and world.player.collision_mask == 7 and not world.session.is_transition_blocked(), label + " colisão e transições liberadas")
			return true
	check(false, label + " prazo finito de conclusão")
	return false

func _race() -> void:
	if not await _new_world(): return
	respawns = 0
	previous_health = world.gameplay.health
	overlay_lifetime = -1.0
	world.gameplay.changed.connect(_health_changed)
	var generation: int = world.session.transition_generation
	var rescue_destination: Vector3 = world.production.region.spawn_position + Vector3.UP * .1
	var custody: Vector3 = PLACES.get_definition("harbor_police").return_position + Vector3.UP * .1
	check(rescue_destination.distance_to(custody) > 5.0, "destinos de prisão e resgate são distinguíveis")
	if not _arrest(): return
	await create_timer(1.0).timeout
	check(world.session.arrest_pending and world.gameplay.health > 0, "morte ocorre durante apresentação da prisão")
	var death_start := Time.get_ticks_usec()
	world.gameplay.damage_player(1000.0)
	check(world.gameplay.health <= 0 and world.session.rescue_pending, "dano letal real inicia morte")
	var overlay: CanvasLayer = world.session.death_presentation
	check(is_instance_valid(overlay) and overlay.name == "WastedPresentation", "morte substitui apresentação da prisão")
	if is_instance_valid(overlay): overlay.tree_exiting.connect(_overlay_exited.bind(death_start), CONNECT_ONE_SHOT)
	check(not world.session.arrest_pending, "morte revoga custódia pendente")
	var completed: bool = await _await_completion("morte durante prisão")
	if completed:
		check(rescued_position.distance_to(rescue_destination) < 1.0 and rescued_position.distance_to(custody) > 5.0, "morte prevalece: destino de resgate, não delegacia")
	# Dá oportunidade finita para a antiga coroutine da prisão e a de morte
	# terminarem; não invoca respawn diretamente nem altera suas flags.
	await create_timer(1.3).timeout
	check(overlay_lifetime >= PRESENTATION_MIN_SECONDS, "overlay de morte manteve seus 2.2 s: %.3f s" % overlay_lifetime)
	check(respawns == 1, "exatamente uma recuperação de vida após morte")
	check(world.session.transition_generation == generation + 1, "exatamente uma transação de resgate")
	check(not is_instance_valid(world.session.death_presentation), "overlay limpo ao concluir")
	print("R5B_OBSERVATION ", JSON.stringify({"overlay_seconds": overlay_lifetime, "respawns": respawns, "transition_delta": world.session.transition_generation - generation, "position": str(rescued_position), "rescue": str(rescue_destination), "custody": str(custody)}))

func _arrest_control() -> void:
	if not await _new_world(): return
	var generation: int = world.session.transition_generation
	var custody: Vector3 = PLACES.get_definition("harbor_police").return_position + Vector3.UP * .1
	if not _arrest(): return
	overlay_lifetime = -1.0
	world.session.death_presentation.tree_exiting.connect(_overlay_exited.bind(Time.get_ticks_usec()), CONNECT_ONE_SHOT)
	if await _await_completion("prisão isolada"):
		check(rescued_position.distance_to(custody) < 1.0, "prisão isolada mantém destino da delegacia")
		check(world.session.transition_generation == generation + 1, "prisão isolada produz uma transação")
		check(overlay_lifetime >= PRESENTATION_MIN_SECONDS, "prisão isolada mantém apresentação completa")

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("R5b exige --no-save e APPDATA temporário do executor")
		quit(2)
		return
	create_timer(180.0).timeout.connect(func(): print("R5B TIMEOUT"); quit(2))
	await _race()
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	await _arrest_control()
	if is_instance_valid(world): world.queue_free()
	await process_frame
	print("ARREST_DEATH_RACE checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
