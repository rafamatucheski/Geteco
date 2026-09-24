extends SceneTree
## Comparação renderizada do combate antes/depois da apresentação de ferimentos.
## Usar --baseline antes da alteração; sem a flag, grava o resultado posterior.
## Fases (mesma cena, mesma câmera, mesmo estado): `idle` (parado, sem armas em uso) e `combat` (SMG automática
## contra civis parados + granadas/RPG periódicos). Reporta ms, não FPS convertido. Grava evidence/combat/measure.json.
## Não altera saves (`--no-save`). Comparação válida só na mesma máquina, sem outros benchmarks rodando.
const SECONDS_WARMUP := 8.0
const SECONDS_SAMPLE := 30.0
var world
var gameplay
var samples: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame

func sample_phase(name: String, action: Callable) -> void:
	var list: Array[float] = []
	var elapsed := 0.0
	var warm := 0.0
	var last := Time.get_ticks_usec()
	while elapsed < SECONDS_SAMPLE:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		warm += dt / 1000.0
		if action.is_valid(): action.call(elapsed)
		if warm >= SECONDS_WARMUP:
			list.append(dt)
			elapsed += dt / 1000.0
	samples[name] = list

## Pior tempo de quadro nos 6 quadros seguintes à ação (primeira visita: carga de amostras, compilação de shader/pipeline).
func first_visit_cost(action: Callable) -> float:
	await process_frame
	var last := Time.get_ticks_usec()
	action.call()
	var worst := 0.0
	for i in 6:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) / 1000.0)
		last = now
	return snappedf(worst, 0.01)

func percentile(sorted: Array, p: float) -> float:
	return float(sorted[clampi(int(ceil(p * sorted.size())) - 1, 0, sorted.size() - 1)])

func summarize(name: String) -> Dictionary:
	var list: Array = samples[name].duplicate()
	list.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in list:
		total += float(value)
		if float(value) > 33.3: over33 += 1
		if float(value) > 66.7: over66 += 1
	return {"frames": list.size(), "seconds": snappedf(total / 1000.0, 0.01), "fps_mean": snappedf(float(list.size()) / (total / 1000.0), 0.1),
		"p50_ms": snappedf(percentile(list, 0.5), 0.01), "p95_ms": snappedf(percentile(list, 0.95), 0.01),
		"p99_ms": snappedf(percentile(list, 0.99), 0.01), "max_ms": snappedf(float(list[list.size() - 1]), 0.01),
		"over_33_3ms": over33, "over_66_7ms": over66}

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	await frames(60)
	gameplay = world.gameplay
	var player = world.player
	# fase 1: parado
	await sample_phase("idle", Callable())
	# fase 2: combate contínuo
	gameplay.state.economy.activate_arsenal_cheat()
	gameplay.state.equip_weapon("smg")
	var targets: Array = []
	for index in 3:
		var actor := preload("res://scripts/Actor.gd").new()
		actor.identity = index
		# Alvos vivos durante toda a janela: cada disparo exerce o ferimento.
		actor.health = 100000.0
		world.add_child(actor)
		var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(-5.0 - index * 1.5, 3.0, 0.0), player.global_position + Vector3(-5.0 - index * 1.5, -3.0, 0.0), 1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
		actor.global_position = hit.position if not hit.is_empty() else player.global_position + Vector3(-5.0 - index * 1.5, 0, 0)
		targets.append(actor)
	await frames(10)
	var flat: Vector3 = Vector3.LEFT
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0.0
	down.y = 0.0
	get_root().get_node("GameInput").touch_aim = Vector2(flat.dot(right.normalized()), flat.dot(down.normalized()))
	# Primeira visita, medida à parte (o regime estável só começa depois): primeiro tiro e primeira explosão.
	var first_visit: Dictionary = {}
	first_visit["first_shot_ms"] = await first_visit_cost(func():
		gameplay.cooldown = 0.0
		gameplay.fire_at(player.global_position + Vector3.LEFT * 5.0))
	first_visit["first_explosion_ms"] = await first_visit_cost(func(): gameplay.explode(player.global_position + Vector3(-6.0, 0.0, 0.0), 4.0, 5.0, player))
	await frames(30)
	var state = {"grenade_clock": 0.0}
	# `--suppress-wanted`: zera o procurado a cada quadro para NÃO despachar polícia (isola o custo dos efeitos do custo da resposta).
	var suppress: bool = "--suppress-wanted" in OS.get_cmdline_user_args()
	var fire_tick := func(seconds: float) -> void:
		if suppress: gameplay.clear_wanted()
		gameplay.cooldown = 0.0 if gameplay.cooldown > 0.11 else gameplay.cooldown
		Input.action_press("fire")
		if seconds - float(state.grenade_clock) >= 3.0:
			state.grenade_clock = seconds
			for actor in targets:
				if is_instance_valid(actor): actor.health = 100000.0
			gameplay.explode(player.global_position + Vector3(-6.0, 0.0, 0.0), 4.0, 5.0, player)
	await sample_phase("combat", fire_tick)
	Input.action_release("fire")
	first_visit["three_deaths_ms"] = await first_visit_cost(func():
		for actor in targets:
			if is_instance_valid(actor):
				actor.health = 1.0
				actor.receive_damage(2.0, player))
	var result := {"idle": summarize("idle"), "combat": summarize("combat"), "first_visit": first_visit,
		"note": "janela real, %s, vsync/limite do projeto, sem outros benchmarks; outra sessão do Godot (editor) pode estar aberta" % OS.get_video_adapter_driver_info()}
	print("MEASURE ", JSON.stringify(result))
	var directory := ProjectSettings.globalize_path("res://evidence/hit_reactions")
	DirAccess.make_dir_recursive_absolute(directory)
	var label := "before" if "--baseline" in OS.get_cmdline_user_args() else "after"
	var file := FileAccess.open(directory.path_join(label + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	quit(0)
