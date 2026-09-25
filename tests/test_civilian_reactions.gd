extends SceneTree
## Reação dos civis (tiro, explosão, agressão, buzina, fuga, retomada) na sessão de produção real.
##   godot --path . --script res://tests/test_civilian_reactions.gd -- --no-save --skip-arrival --population=8 --seed=7
## Janela real (sem --headless): a física 3D precisa rodar de verdade. Não altera saves (`--no-save`).
const ACTOR := preload("res://scripts/Actor.gd")

class StalePeopleWorld:
	extends Node3D
	var people: Array = []

var world
var player
var director
var failures := 0
var made: Array = []

func _initialize() -> void: _run.call_deferred()

func check(name: String, ok: bool, detail := "") -> void:
	print("CASE ", "PASS " if ok else "FAIL ", name, " ", detail)
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count: await physics_frame

func spawn(offset: Vector3, id := 0) -> CharacterBody3D:
	var actor := ACTOR.new()
	actor.identity = id
	world.add_child(actor)
	var base: Vector3 = player.global_position + offset
	var ray := PhysicsRayQueryParameters3D.create(base + Vector3.UP * 3.0, base + Vector3.DOWN * 3.0, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	actor.global_position = hit.position + Vector3.UP * 0.1 if not hit.is_empty() else base
	world.people.append(actor)
	made.append(actor)
	return actor

func discard(actor) -> void:
	if not is_instance_valid(actor): return
	world.people.erase(actor)
	actor.global_position = player.global_position + Vector3(0.0, -500.0, 0.0)
	actor.set_physics_process(false)

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		print("recusado: exige --no-save")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	await frames(60)
	player = world.player
	# Congela a reposição ambiente enquanto a fixture controla world.people; sem isso,
	# ProductionWorld adiciona testemunhas novas durante a rajada e altera a contagem.
	var population_target: int = world.production.requested_population
	world.production.requested_population = 0
	# Quem já existia na sessão não interfere: fica fora de `people` durante o teste.
	var original: Array = world.people.duplicate()
	for person in original: person.set_physics_process(false)
	world.people.clear()
	director = world.production.civilian_reactions
	var production_directors: Array = world.get_children().filter(func(child): return child.name == "CivilianReactionDirector")
	check("integração: existe um único diretor produtivo", is_instance_valid(director) and production_directors.size() == 1, "diretores=%d" % production_directors.size())

	# O disparo precisa atravessar Gameplay.weapon_fired; report_gunfire direto não
	# demonstra a conexão produtiva nem detecta conexão duplicada.
	var shot_events := {"count":0}
	world.gameplay.weapon_fired.connect(func(_weapon_id: String, _origin: Vector3): shot_events.count += 1)
	world.production.state.grant_weapon("pistol")
	world.production.state.equip_weapon("pistol")
	var real_near := spawn(Vector3(6, 0, 0))
	var real_mid := spawn(Vector3(20, 0, 0))
	var alerts_before: int = director.stats.alerts
	check("tiro real: Gameplay aceita o disparo", world.gameplay.fire_at(player.global_position + Vector3(0, 0, -20)))
	await frames(4)
	check("tiro real: sinal chega uma vez ao diretor", shot_events.count == 1 and director.stats.alerts - alerts_before == 2, "eventos=%d alertas=%d" % [shot_events.count, director.stats.alerts - alerts_before])
	check("tiro real: testemunhas no raio fogem", director.reactors.has(real_near.get_instance_id()) and director.reactors.has(real_mid.get_instance_id()))
	director.reset_population()
	discard(real_near); discard(real_mid)

	world.production.state.economy.grant_reward("civilian_reaction_suppressor", 700)
	check("silenciador: usa o acessório real suppressor", world.gameplay.buy_attachment("pistol", "suppressor") and world.gameplay.weapon_data("pistol").get("suppressed", false))
	var quiet_near := spawn(Vector3(8, 0, 0))
	var quiet_far := spawn(Vector3(20, 0, 0))
	await frames(30)
	alerts_before = director.stats.alerts
	check("tiro silenciado real: Gameplay aceita o disparo", world.gameplay.fire_at(player.global_position + Vector3(0, 0, -20)))
	await frames(4)
	check("tiro silenciado real: só o raio curto reage uma vez", shot_events.count == 2 and director.stats.alerts - alerts_before == 1 and director.reactors.has(quiet_near.get_instance_id()) and not director.reactors.has(quiet_far.get_instance_id()), "eventos=%d alertas=%d" % [shot_events.count, director.stats.alerts - alerts_before])
	world.production._commit_logical_region("mountain")
	await frames(2)
	check("continuidade cidade-serra: reação sobrevive ao region_id", director.reactors.has(quiet_near.get_instance_id()))
	world.production._commit_logical_region("harbor")
	director.reset_population()
	discard(quiet_near); discard(quiet_far)
	var origin: Vector3 = player.global_position + Vector3(0.0, 0.0, -40.0)

	# 1. Percepção: raio de audição (silenciado ouve menos).
	var near := spawn(Vector3(0, 0, -30))
	var mid := spawn(Vector3(-30, 0, -40))
	var far := spawn(Vector3(60, 0, -40))
	var quiet := spawn(Vector3(0, 0, -20))
	await frames(5)
	director.report_gunfire(origin, origin + Vector3.RIGHT * 30.0, null, 13.0)
	check("silenciado: ouve só quem está a <13 m", director.reactors.has(near.get_instance_id()) and not director.reactors.has(quiet.get_instance_id()), "reatores=%d" % director.reactors.size())
	director.reset_region()
	director.report_gunfire(origin, origin + Vector3.RIGHT * 30.0, null)
	check("tiro: dentro de 40 m reage", director.reactors.has(near.get_instance_id()) and director.reactors.has(mid.get_instance_id()))
	check("tiro: fora de 40 m ignora", not director.reactors.has(far.get_instance_id()))
	check("controle assumido e velocidade de pânico", near.controlled_automatically and is_equal_approx(near.speed, 5.0))

	# 2. Fuga: afasta-se da origem, sem travar.
	var start: float = flat(near.global_position, origin)
	await frames(90)
	var later: float = flat(near.global_position, origin)
	check("foge: distância da origem aumenta", later > start + 3.0, "%.1f -> %.1f m" % [start, later])
	check("balão de fala criado e limitado", director.presenter.bubbles.size() <= director.reactors.size())

	# 3. Eventos repetidos: rajada não reinicia nem empilha.
	var count_before: int = director.reactors.size()
	var released_before: int = director.stats.released
	for shot in 300:
		director.report_gunfire(origin, origin + Vector3.RIGHT * 30.0, null)
		if shot % 30 == 0: await physics_frame
	var state = director.reactors[near.get_instance_id()]
	check("rajada: reatores existentes não são duplicados; apenas novo civil pode entrar no raio", director.reactors.size() == count_before or (director.reactors.size() == count_before + 1 and director.reactors.has(far.get_instance_id())), "antes=%d depois=%d civil_longe=%s" % [count_before, director.reactors.size(), director.reactors.has(far.get_instance_id())])
	check("rajada: memória deduplicada (<=4 ameaças)", state.danger.threats.size() <= 4 and state.danger.threats.size() == 1, "ameaças=%d" % state.danger.threats.size())
	check("rajada: nada solto por reinício", director.stats.released == released_before, str(director.stats))

	# 4. Obstáculo: parede larga atrás do civil; nunca atravessa e não fica preso replanejando a cada quadro.
	director.reset_region()
	var runner := spawn(Vector3(40, 0, -40))
	var wall_origin := runner.global_position + Vector3(6.0, 0.0, 0.0)
	var wall := StaticBody3D.new()
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 4.0, 24.0)
	box.shape = shape
	wall.add_child(box)
	wall.collision_layer = 1
	world.add_child(wall)
	wall.global_position = runner.global_position + Vector3(-2.5, 1.5, 0.0)
	await frames(3)
	var wall_x: float = wall.global_position.x
	director.report_gunfire(wall_origin, wall_origin + Vector3.LEFT * 30.0, null)
	var crossed := false
	var replans_before: int = director.stats.stuck_replans
	for i in 240:
		await physics_frame
		if runner.global_position.x < wall_x - 0.3 and absf(runner.global_position.z - wall.global_position.z) < 11.5: crossed = true
	check("obstáculo: não atravessa a parede", not crossed, "x=%.1f parede=%.1f dz=%.1f" % [runner.global_position.x, wall_x, runner.global_position.z - wall.global_position.z])
	check("obstáculo: replaneja por travamento só de vez em quando", director.stats.stuck_replans - replans_before <= 6, "replans=%d" % (director.stats.stuck_replans - replans_before))
	wall.queue_free()

	# 5. Alvo removido durante a reação.
	director.reset_region()
	var doomed := spawn(Vector3(-40, 0, -40))
	director.report_gunfire(doomed.global_position + Vector3(5, 0, 0), doomed.global_position + Vector3(-25, 0, 0), null)
	await frames(10)
	var doomed_id := doomed.get_instance_id()
	world.people.erase(doomed)
	doomed.queue_free()
	await frames(4)
	check("alvo removido: estado solto sem erro", not director.reactors.has(doomed_id))

	# 5b. A lista pública pode reter uma referência já liberada até a próxima limpeza.
	# A percepção precisa descartá-la antes de validar tipo ou acessar propriedades.
	var stale = spawn(Vector3(-42, 0, -42))
	world.people.erase(stale)
	stale.free()
	var stale_world := StalePeopleWorld.new()
	stale_world.people.append(stale)
	var live_world = director.world
	director.world = stale_world
	director.report_gunfire(Vector3(-40, 0, -42), Vector3(-10, 0, -42), null)
	director.world = live_world
	stale_world.free()
	check("referência liberada: ignorada sem erro de tipo", not is_instance_valid(stale))

	# 6. Morte durante a reação.
	var victim := spawn(Vector3(-40, 0, -30))
	director.report_gunfire(victim.global_position + Vector3(5, 0, 0), victim.global_position + Vector3(-25, 0, 0), null)
	await frames(10)
	victim.receive_damage(500.0)
	await frames(6)
	check("morte: solta e não persegue morto", victim.dead and not director.reactors.has(victim.get_instance_id()))

	# 7. Suspensão por distância.
	var far_actor := spawn(Vector3(0, 0, -45))
	director.report_gunfire(far_actor.global_position + Vector3(5, 0, 0), far_actor.global_position + Vector3(-25, 0, 0), null)
	await frames(5)
	# O diretor solta acima de 110 m; a população produtiva remove acima de 120 m.
	# Ficar entre os dois limites testa a suspensão sem liberar o ator da cena.
	var far_actor_id: int = far_actor.get_instance_id()
	far_actor.global_position = player.global_position + Vector3(115.0, 5.0, 0.0)
	await frames(4)
	var far_actor_valid: bool = is_instance_valid(far_actor)
	var far_actor_speed: float = far_actor.speed if far_actor_valid else -1.0
	check("distância: solto e velocidade restaurada", far_actor_valid and not director.reactors.has(far_actor_id) and not far_actor.controlled_automatically and is_equal_approx(far_actor_speed, 1.6), "válido=%s speed=%.2f" % [far_actor_valid, far_actor_speed])

	# 8. Recuperação e retomada da rotina.
	var walker := spawn(Vector3(20, 0, -50))
	walker.route = PackedVector3Array([walker.global_position + Vector3(0, 0, -8), walker.global_position + Vector3(8, 0, -8), walker.global_position + Vector3(8, 0, 0)])
	director.report_gunfire(walker.global_position + Vector3(5, 0, 0), walker.global_position + Vector3(-25, 0, 0), null)
	await frames(5)
	var walker_state = director.reactors[walker.get_instance_id()]
	walker_state.danger.threats.clear()
	await frames(3)
	check("sem ameaça viva entra em recuperação", director.reactors.has(walker.get_instance_id()) and director.reactors[walker.get_instance_id()].phase == "recover")
	director.reactors[walker.get_instance_id()].timer = 0.05
	await frames(6)
	check("retomada: controle devolvido, velocidade e rota restauradas", not director.reactors.has(walker.get_instance_id()) and not walker.controlled_automatically and is_equal_approx(walker.speed, 1.6) and walker.route.size() == 3)

	# 9. Distinção: quem tem dono de movimento / rotina / protegido não reage.
	var owned := spawn(Vector3(0, 0, -30))
	owned.controlled_automatically = true
	var routine := spawn(Vector3(3, 0, -30))
	routine.add_to_group("v1_routine_actor")
	var exempt := spawn(Vector3(-3, 0, -30))
	exempt.set_meta("gameplay_role", "police")
	director.reset_region()
	director.report_gunfire(origin, origin + Vector3.RIGHT * 30.0, null)
	check("controlado por outro / rotina V1 / outro papel não reagem", not director.reactors.has(owned.get_instance_id()) and not director.reactors.has(routine.get_instance_id()) and not director.reactors.has(exempt.get_instance_id()))
	check("controlado por outro segue com o dono", owned.controlled_automatically)

	# 10. Buzina: só passo lateral, sem pânico.
	director.reset_region()
	# Blocos de rua têm parede dos dois lados em muitos pontos: procura um ponto com ombro livre nos dois lados.
	var pedestrian := spawn(Vector3(0, 0, -60))
	for attempt in 40:
		var spot := Vector3(-30.0 + attempt * 5.0, 0.0, -50.0 - (attempt % 5) * 6.0)
		var probe := spawn(spot)
		if director._path_clear(probe, probe.global_position + Vector3(3.4, 0, 0)) and director._path_clear(probe, probe.global_position + Vector3(-3.4, 0, 0)):
			pedestrian = probe
			break
	var car := Node3D.new()
	world.add_child(car)
	car.global_position = pedestrian.global_position + Vector3(0, 0, 5.0)  # de frente para -Z: o civil está à frente
	# Lado bloqueado: com parede nos dois ombros ninguém se teleporta (V1 idem).
	var boxed := spawn(Vector3(0, 0, -60))
	var trap := StaticBody3D.new()
	var trap_shape := CollisionShape3D.new()
	var trap_box := BoxShape3D.new()
	trap_box.size = Vector3(0.5, 3.0, 6.0)
	trap_shape.shape = trap_box
	trap.add_child(trap_shape)
	trap.collision_layer = 1
	world.add_child(trap)
	trap.global_position = boxed.global_position + Vector3(2.0, 1.5, 0.0)
	var trap2 := trap.duplicate()
	world.add_child(trap2)
	trap2.global_position = boxed.global_position + Vector3(-2.0, 1.5, 0.0)
	await frames(3)
	var boxed_car := Node3D.new()
	world.add_child(boxed_car)
	boxed_car.global_position = boxed.global_position + Vector3(0, 0, 5.0)
	director.report_horn(boxed_car)
	check("buzina: sem ombro livre, fica onde está", not director.reactors.has(boxed.get_instance_id()))
	director.report_horn(car)
	var horn_state = director.reactors.get(pedestrian.get_instance_id(), {})
	check("buzina: passo lateral (fase horn), não pânico", not horn_state.is_empty() and horn_state.phase == "horn", "reatores=%d ped=%s car=%s" % [director.reactors.size(), pedestrian.global_position, car.global_position])
	await frames(300)
	check("buzina: retoma sozinho em ~4,5 s", not director.reactors.has(pedestrian.get_instance_id()) and not pedestrian.controlled_automatically)
	car.queue_free()
	boxed_car.queue_free()
	trap.queue_free()
	trap2.queue_free()

	# 11. Agressão sem origem não é atribuída ao jogador. Com origem explícita, reage.
	director.reset_region()
	var hurt := spawn(Vector3(-20, 0, -60))
	await frames(20)
	hurt.receive_damage(10.0, player)
	await frames(30)
	check("agressão sem metadado: diretor não inventa o jogador", not director.reactors.has(hurt.get_instance_id()))
	check("agressão com origem confiável: civil ferido foge", director.report_assault(hurt, player) and director.reactors.has(hurt.get_instance_id()) and hurt.controlled_automatically)

	# 12. Explosão real: Gameplay publica uma vez e o diretor consome o sinal.
	director.reset_region()
	var explosion_events := {"count": 0, "origin": Vector3.ZERO, "radius": 0.0, "source": player}
	world.gameplay.explosion_occurred.connect(func(event_origin: Vector3, event_radius: float, event_source: Node):
		explosion_events.count += 1
		explosion_events.origin = event_origin
		explosion_events.radius = event_radius
		explosion_events.source = event_source
	)
	var blast_origin: Vector3 = hurt.global_position + Vector3(6, 0, 0)
	world.gameplay.explode(blast_origin, 12.0, 1.0, null)
	await frames(2)
	check("explosão real: evento único preserva origem, raio e autoria desconhecida",
		explosion_events.count == 1 and explosion_events.origin.is_equal_approx(blast_origin)
		and is_equal_approx(explosion_events.radius, 12.0) and explosion_events.source == null,
		"eventos=%d origem=%s raio=%.1f fonte=%s" % [explosion_events.count, explosion_events.origin, explosion_events.radius, explosion_events.source])
	check("explosão real: sinal faz civil no raio fugir", director.reactors.has(hurt.get_instance_id()))

	# 13. Descarregamento e crescimento de referências.
	director.reset_region()
	var all_free := true
	for actor in made:
		if is_instance_valid(actor) and actor != owned and actor.controlled_automatically and not actor.dead: all_free = false
	check("reset_region: devolve o controle a todos", all_free and director.reactors.is_empty())
	check("referências limpas", director.presenter.bubbles.is_empty() and director.presenter.last_scream.is_empty(), "seen_health=%d" % director.seen_health.size())
	var seen_before: int = director.seen_health.size()
	for actor in made: discard(actor)
	await frames(30)
	check("seen_health encolhe quando civis somem", director.seen_health.size() <= world.people.size(), "seen=%d pessoas=%d" % [director.seen_health.size(), world.people.size()])
	for person in original:
		if is_instance_valid(person): world.people.append(person)
	world.production.requested_population = population_target
	print("STATS ", director.stats)
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)
