extends SceneTree
## R5b: arrest_player real e morte real no meio da prisão, sem acelerar timers.
## A morte prevalece: um único resgate de verdade, na porta do Bay Medical (RecoveryPenalty,
## 0ecd01a0), vivo e com controle, só a conta do hospital. Dois momentos da prisão:
##   1. durante a apresentação "PRESO" (mundo a 0,2×, 2,4 s de relógio de parede);
##   2. durante o próprio _respawn da prisão, já na porta da delegacia com a cortina abrindo.
##      Antes esse _respawn terminava depois da morte, limpava as bandeiras e deixava o corpo
##      morto e travado na delegacia, com a multa cobrada; a morte pulava o próprio resgate.
## No mesmo mundo do caso 2, uma prisão isolada depois ainda sai pela delegacia: a corrotina
## abandonada não deixa nada para trás.
## Uso: "$GODOT" --headless --path . --script res://tests/test_arrest_death_race.gd -- --no-save --isolated-save-root=<pasta>
## --no-save obrigatório; a pasta isolada (preferências) vem do executor (tools/run_core_suite.sh).
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const PENALTY = preload("res://runtime/RecoveryPenalty.gd")
# 2,4 s de mensagem + 0,8 s de escurecer + 0,3 s + 1,0 s de clarear, todos em relógio de parede
# (_hold_recovery_presentation, _finish_recovery_presentation); margem de 50 ms de amostragem.
const PRESENTATION_MIN_SECONDS := 4.45
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

func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

## Porta de retorno do Harbor: Bay Medical na morte, delegacia na prisão.
func _door(arrested: bool) -> Vector3:
	return PLACES.get_definition(PENALTY.place_for("harbor", arrested)).return_position

func _economy():
	return world.session.state.economy

func _carried_ammo() -> int:
	var ammo: Dictionary = _economy().get_ammo("pistol")
	return int(ammo.get("magazine", 0)) + int(ammo.get("reserve", 0))

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
	var exterior: bool = world.production.no_save and world.session.state.place_id.is_empty() and world.session.state.region_id == "harbor"
	check(exterior, "Harbor exterior sem save pessoal")
	if not exterior: return false
	# Dinheiro e munição no bolso separam as contas: o hospital só cobra a taxa; a delegacia
	# cobra a mesma taxa e ainda leva a munição carregada.
	_economy().grant_reward("test_arrest_death_race_wallet", 10000)
	# O dinheiro novo pode liberar conquista com prêmio; liquida antes de medir.
	world.session.activities.refresh_achievements()
	if not _economy().owns_weapon("pistol"): _economy().grant_weapon("pistol")
	_economy().add_ammo("pistol", 24)
	check(_carried_ammo() > 0, "munição carregada para distinguir prisão de morte")
	respawns = 0
	previous_health = world.gameplay.health
	world.gameplay.changed.connect(_health_changed)
	return true

func _health_changed() -> void:
	var health: float = world.gameplay.health
	if previous_health <= 0.0 and health > 0.0: respawns += 1
	previous_health = health

func _overlay_exited(start: int) -> void:
	overlay_lifetime = (Time.get_ticks_usec() - start) / 1000000.0

func _arrest(label: String) -> bool:
	world.gameplay.register_crime(12, world.player.global_position)
	check(world.gameplay.stars == 1, label + ": crime real inicia uma estrela")
	# Depois de um resgate o corpo ainda pode estar assentando; a rendição exige ficar parado.
	var surrendered := false
	var deadline := Time.get_ticks_msec() + 5000
	while not surrendered and Time.get_ticks_msec() < deadline:
		surrendered = world.gameplay.police_case.request_surrender()
		if not surrendered: await physics_frame
	check(surrendered, label + ": rendição real aceita")
	var accepted: bool = surrendered and world.gameplay.arrest_player()
	check(accepted and world.session.arrest_pending, label + ": arrest_player inicia custódia")
	check(is_instance_valid(world.session.death_presentation) and world.session.death_presentation.name == "ArrestPresentation", label + ": overlay de prisão presente")
	return accepted

func _await_completion(label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not world.session.rescue_pending and not world.session.arrest_pending and not world.session.respawn_busy:
			rescued_position = world.player.global_position
			check(world.gameplay.health > 0 and not world.player.input_locked and world.player.is_physics_processing(), label + ": controle vivo restaurado")
			check(world.player.collision_layer == 2 and world.player.collision_mask == 7 and not world.session.is_transition_blocked(), label + ": colisão e transições liberadas")
			return true
	check(false, label + ": prazo finito de conclusão")
	return false

## Dano letal real com a prisão em curso; confere o resgate único da morte e o que vem depois.
func _lethal_hit_and_rescue(label: String, balance: int, ammo: int) -> void:
	var death_start := Time.get_ticks_usec()
	world.gameplay.damage_player(1000.0)
	check(world.gameplay.health <= 0 and world.session.rescue_pending, label + ": dano letal real inicia morte")
	var overlay: CanvasLayer = world.session.death_presentation
	check(is_instance_valid(overlay) and overlay.name == "WastedPresentation", label + ": morte substitui a apresentação da prisão")
	overlay_lifetime = -1.0
	if is_instance_valid(overlay): overlay.tree_exiting.connect(_overlay_exited.bind(death_start), CONNECT_ONE_SHOT)
	check(not world.session.arrest_pending, label + ": morte revoga custódia pendente")
	if not await _await_completion(label): return
	var hospital := _door(false)
	var custody := _door(true)
	check(_planar(rescued_position, hospital) < 1.5, label + ": morte prevalece, acorda no Bay Medical (%.1f m; delegacia a %.1f m; ponto da região a %.1f m)" % [_planar(rescued_position, hospital), _planar(rescued_position, custody), _planar(rescued_position, world.production.region.spawn_position)])
	# Dá oportunidade finita para a corrotina antiga da prisão acordar; não invoca respawn
	# diretamente nem altera suas bandeiras.
	await create_timer(1.3, true, false, true).timeout
	check(overlay_lifetime >= PRESENTATION_MIN_SECONDS, label + ": overlay de morte manteve a apresentação inteira: %.3f s" % overlay_lifetime)
	check(respawns == 1, label + ": exatamente uma recuperação de vida após a morte")
	check(world.gameplay.health > 0 and not world.player.input_locked and _planar(world.player.global_position, hospital) < 1.5 and not world.session.is_transition_blocked(), label + ": a prisão abandonada não volta a mexer no corpo")
	check(_economy().balance == balance - PENALTY.fee(balance) and _carried_ammo() == ammo, label + ": só a conta do hospital, uma vez; sem multa nem apreensão (R$ %d → R$ %d, munição %d → %d)" % [balance, _economy().balance, ammo, _carried_ammo()])
	check(not is_instance_valid(world.session.death_presentation), label + ": overlay limpo ao concluir")

func _observe(label: String, generation: int) -> void:
	print("R5B_OBSERVATION ", JSON.stringify({"case": label, "overlay_seconds": overlay_lifetime, "respawns": respawns, "transition_delta": world.session.transition_generation - generation, "position": str(rescued_position), "hospital": str(_door(false)), "custody": str(_door(true))}))

func _death_during_presentation() -> void:
	if not await _new_world(): return
	var label := "morte na apresentação"
	var balance: int = _economy().balance
	var ammo := _carried_ammo()
	var generation: int = world.session.transition_generation
	if not await _arrest(label): return
	# Relógio de parede: a apresentação roda o mundo a 0,2× (12/10). Um timer de jogo de 1 s
	# acabava depois dela, já no _respawn da prisão (o outro caso).
	await create_timer(1.0, true, false, true).timeout
	check(world.session.arrest_pending and not world.session.respawn_busy and world.gameplay.health > 0, label + ": a morte cai antes do _respawn da prisão")
	await _lethal_hit_and_rescue(label, balance, ammo)
	check(world.session.transition_generation == generation + 1, label + ": exatamente uma transação de resgate")
	_observe(label, generation)

func _death_during_arrest_respawn() -> void:
	if not await _new_world(): return
	var label := "morte no _respawn da prisão"
	var balance: int = _economy().balance
	var ammo := _carried_ammo()
	var generation: int = world.session.transition_generation
	var arrest_site: Vector3 = world.player.global_position
	if not await _arrest(label): return
	# A prisão chegou ao próprio _respawn quando o corpo, vivo, já foi levado para a delegacia
	# e a cortina está abrindo (_finish_recovery_presentation, 1,3 s).
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session.respawn_busy and world.session.arrest_pending and world.player.global_position.distance_to(arrest_site) > 5.0: break
	var custody := _door(true)
	var in_respawn: bool = world.session.respawn_busy and world.session.arrest_pending and world.gameplay.health > 0 and _planar(world.player.global_position, custody) < 1.5
	check(in_respawn, label + ": a morte cai com a prisão já na porta da delegacia (%.1f m)" % _planar(world.player.global_position, custody))
	if not in_respawn: return
	await _lethal_hit_and_rescue(label, balance, ammo)
	# A transação da prisão já tinha começado: ela é abandonada e só a da morte se abre depois.
	check(world.session.transition_generation == generation + 2, label + ": a transação da prisão é abandonada e só a da morte se abre")
	_observe(label, generation)
	await _isolated_arrest("prisão isolada depois da corrida")

func _isolated_arrest(label: String) -> void:
	var balance: int = _economy().balance
	var ammo := _carried_ammo()
	var generation: int = world.session.transition_generation
	if not await _arrest(label): return
	overlay_lifetime = -1.0
	world.session.death_presentation.tree_exiting.connect(_overlay_exited.bind(Time.get_ticks_usec()), CONNECT_ONE_SHOT)
	if not await _await_completion(label): return
	check(_planar(rescued_position, _door(true)) < 1.5, label + ": sai pela porta da delegacia (%.1f m)" % _planar(rescued_position, _door(true)))
	check(world.session.transition_generation == generation + 1, label + ": uma transação")
	check(overlay_lifetime >= PRESENTATION_MIN_SECONDS, label + ": apresentação completa: %.3f s" % overlay_lifetime)
	check(_economy().balance == balance - PENALTY.fee(balance) and ammo > 0 and _carried_ammo() == 0, label + ": multa cobrada uma vez e munição apreendida (R$ %d → R$ %d, munição %d → %d)" % [balance, _economy().balance, ammo, _carried_ammo()])
	_observe(label, generation)

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("R5b exige --no-save e pasta isolada do executor")
		quit(2)
		return
	create_timer(420.0, true, false, true).timeout.connect(func(): print("R5B TIMEOUT"); quit(2))
	await _death_during_presentation()
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	await _death_during_arrest_respawn()
	if is_instance_valid(world): world.queue_free()
	await process_frame
	print("ARREST_DEATH_RACE checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
