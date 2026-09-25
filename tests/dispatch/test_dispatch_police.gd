extends SceneTree
## Viaturas dirigindo por ruas reais até o local do crime, desembarque da dupla,
## limites de entidades e liberação quando a procura termina. Física real
## (CharacterBody3D, colisão com piso e paredes); sem renderização.
## Uma suíte verde prova só estes cenários, não o jogo integrado.

const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const TICK := 1.0 / 60.0
var failures: Array[String] = []
var checks := 0
var groups_done: Array[String] = []

func done(group: String) -> void:
	groups_done.append(group)
	print("GROUP_OK " + group)

## Um erro de script aborta a função no meio e o teste seguiria adiante: só
## vale se todos os grupos esperados chegaram ao fim e houve verificações demais.
func report(tag: String, expected: Array, minimum_checks: int) -> void:
	var missing: Array[String] = []
	for group in expected:
		if not groups_done.has(group): missing.append(group)
	if not missing.is_empty(): failures.append("grupos não concluídos: " + str(missing))
	if checks < minimum_checks: failures.append("poucas verificações: %d < %d" % [checks, minimum_checks])
	print("%s groups=%d/%d checks=%d failures=%d" % [tag, expected.size() - missing.size(), expected.size(), checks, failures.size()])
	for failure in failures: print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func run() -> void:
	await _pursuit_and_release()
	await _garage_rule_holds()
	await _foot_agent_contract()
	await _entity_limits()
	await _blocked_road()
	await _crew_depleted()
	await _disable_restores_legacy()
	report("DISPATCH_POLICE", ["pursuit_and_release", "garage_rule_holds", "foot_agent_contract", "entity_limits", "blocked_road", "crew_depleted", "disable_restores_legacy"], 46)

func _frames(count: int) -> void:
	for index in count: await physics_frame

## Máximo de deslocamento entre dois quadros de física observado no veículo.
class Tracker extends RefCounted:
	var vehicle: Node3D
	var last := Vector3.INF
	var worst := 0.0
	var travelled := 0.0
	func sample() -> void:
		if not is_instance_valid(vehicle): return
		if last != Vector3.INF:
			var step := vehicle.global_position.distance_to(last)
			worst = maxf(worst, step)
			travelled += step
		last = vehicle.global_position

func _pursuit_and_release() -> void:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var scene: Node3D = bundle.scene
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var player: CharacterBody3D = bundle.player
	await _frames(3)
	gameplay.register_crime(60, player.global_position)
	check(gameplay.stars == 3, "60 pontos = 3 estrelas")
	var tracker := Tracker.new()
	var unit: RefCounted = null
	var frames := 0
	# Despacho: atraso inicial de 1 s no patamar 3, com viatura fora do ponto do crime.
	while unit == null and frames < 600:
		await physics_frame
		frames += 1
		gameplay.health = 100.0
		if not controller.units.is_empty(): unit = controller.units[0]
	check(unit != null, "a viatura é despachada em até 10 s")
	if unit == null:
		KIT.teardown(bundle)
		return
	check(frames >= 55, "respeita o atraso inicial da V1 (%d quadros)" % frames)
	check(unit.service == "police" and unit.vehicle.archetype == "police_cruiser", "veículo original police_cruiser")
	var spawn_distance: float = Vector2(unit.vehicle.global_position.x - 30.0, unit.vehicle.global_position.z - 10.0).length()
	check(spawn_distance >= RULES.SPAWN_MIN - 3.0 and spawn_distance <= RULES.SPAWN_MAX + 3.0, "nasce a 32,5–112,5 m do crime (%.0f m)" % spawn_distance)
	check(unit.vehicle.is_in_group("drivable") and unit.vehicle.get_meta("dispatch_unit", false), "viatura policial de serviço é dirigível e conserva vínculo com o despacho")
	check(gameplay.dispatch_owned and gameplay.deployed == 0, "despacho embutido de Gameplay suprimido sem tocar o orçamento da procura")
	check(gameplay.police.is_empty(), "nenhum policial nasce por teletransporte de Gameplay.spawn_officer")
	tracker.vehicle = unit.vehicle
	var reached := false
	var deployed_frames := 0
	for tick in 4200:
		await physics_frame
		gameplay.health = 100.0
		tracker.sample()
		if unit.state == "working" and not unit.officers.is_empty():
			reached = true
			deployed_frames = tick
			break
	check(reached, "viatura chega, para e desembarca a dupla (estado %s)" % unit.state)
	check(tracker.worst < 0.6, "nenhum salto de posição: maior passo %.2f m por quadro" % tracker.worst)
	check(tracker.travelled >= 20.0, "percorreu de fato %.0f m" % tracker.travelled)
	check(absf(unit.vehicle.speed) < 0.6, "parada antes do desembarque")
	var flat := Vector2(unit.vehicle.global_position.x - 30.0, unit.vehicle.global_position.z - 10.0).length()
	check(flat <= RULES.stop_radius(unit.serial) + 2.5, "parou no raio de parada da V1 (%.1f m)" % flat)
	var on_lane: bool = absf(unit.vehicle.global_position.z) < 6.0
	check(on_lane, "parou sobre a rua, não na calçada ou dentro de prédio")
	check(controller.foot_officer_count() >= 1 and controller.foot_officer_count() <= RULES.MAX_FOOT_OFFICERS, "policiais a pé dentro do limite (%d)" % controller.foot_officer_count())
	for officer in unit.officers:
		check(officer.get_meta("gameplay_role", "") == "police" and officer.collision_layer == 2, "policial usa o PoliceAgent original com colisão")
		check(officer.global_position.distance_to(unit.vehicle.global_position) < 6.0, "policial desembarcou ao lado da viatura")
	# Fim da procura: equipe volta a pé, embarca e a viatura parte dirigindo.
	gameplay.clear_wanted()
	await _frames(2)
	check(unit.state in ["recall", "departing"] or not controller.events_named("officer_boarded").is_empty(), "procura zerada chama a equipe de volta")
	var boarded := false
	var finished := false
	for tick in 5400:
		await physics_frame
		gameplay.health = 100.0
		tracker.sample()
		if not controller.events_named("officer_boarded").is_empty(): boarded = true
		if unit.finished:
			finished = true
			break
	check(boarded, "policiais embarcaram andando de volta à viatura")
	check(finished and unit.end_reason == "left", "viatura partiu e saiu de cena (%s)" % unit.end_reason)
	check(tracker.worst < 0.6, "nenhum salto de posição na partida: %.2f m" % tracker.worst)
	check(controller.units.is_empty() and controller.foot_officer_count() == 0, "nada sobra da equipe")
	check(controller.get_children().filter(func(n): return n is CharacterBody3D).is_empty(), "nenhum policial órfão na cena")
	KIT.teardown(bundle)
	done("pursuit_and_release")

func _garage_rule_holds() -> void:
	# Área sem armas (`weapons_allowed()` falso): o despacho não fere o jogador
	# e não cria procura nova. É o mesmo bloqueio central que a garagem usa.
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	await _frames(3)
	gameplay.register_crime(60, bundle.player.global_position)
	bundle.state.safe = true
	var before: float = gameplay.health
	await _frames(1500)
	check(gameplay.health == before, "sem armas permitidas, a polícia não fere o jogador")
	for unit in controller.units:
		for officer in unit.officers:
			check(is_instance_valid(officer), "oficial válido")
	KIT.teardown(bundle)
	done("garage_rule_holds")

func _foot_agent_contract() -> void:
	# Um policial a pé busca por caminho físico, não atira num procurado de uma
	# estrela sem agressão, reage ao agressor real e para quando a procura termina.
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(8, 0, 0))
	var gameplay: Node3D = bundle.gameplay
	var officer := preload("res://gameplay/PoliceAgent.gd").new()
	officer.controller = gameplay
	officer.last_known = bundle.player.global_position
	bundle.scene.add_child(officer)
	officer.global_position = Vector3(-8, 0, 0)
	var wall := KIT.add_wall(bundle.scene, Vector3(0, 1.5, 0), Vector3(1.0, 3.0, 8.0))
	await _frames(3)
	gameplay.register_crime(12, bundle.player.global_position)
	var initial_health: float = gameplay.health
	var start: Vector3 = officer.global_position
	await _frames(360)
	check(officer.global_position.distance_to(start) > 2.0, "policial a pé procura caminho ao perder contato")
	check(gameplay.health == initial_health, "uma estrela sem agressão não autoriza tiro")
	wall.queue_free()
	# A 2 m do jogador, a dispersão real de ±0,13 rad ainda acerta a cápsula
	# de 0,30 m; a 5,5 m, o único tiro nesta janela podia errar por sorte.
	officer.global_position = Vector3(6.0, 0, 0)
	await _frames(5)
	officer.receive_damage(1.0, bundle.player)
	await _frames(90)
	check(officer.response_aggression > 0.0 and gameplay.contact_age < 1.0, "dano identifica o agressor real e renova contato")
	check(gameplay.health < initial_health, "policial vivo reage ao dano com ataque")
	gameplay.clear_wanted()
	await _frames(3)
	check(officer.velocity.x == 0.0 and officer.velocity.z == 0.0 and not officer.sees_player, "fim da procura encerra busca e ataque a pé")
	officer.queue_free()
	KIT.teardown(bundle)
	done("foot_agent_contract")

func _entity_limits() -> void:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	await _frames(3)
	gameplay.register_crime(420, bundle.player.global_position)
	check(gameplay.stars == 6, "420 pontos = 6 estrelas")
	var peak_units := 0
	var peak_active := 0
	var peak_foot := 0
	for tick in 5400:
		await physics_frame
		gameplay.health = 100.0
		peak_units = maxi(peak_units, controller.units.size())
		peak_active = maxi(peak_active, controller._active_police().size())
		peak_foot = maxi(peak_foot, controller.foot_officer_count())
	check(peak_units >= 2, "várias viaturas foram despachadas (%d)" % peak_units)
	check(peak_active <= RULES.MAX_ACTIVE[6], "no máximo %d viaturas ativas no patamar 6 (%d)" % [RULES.MAX_ACTIVE[6], peak_active])
	check(peak_units <= RULES.MAX_UNITS, "teto absoluto de %d veículos (%d)" % [RULES.MAX_UNITS, peak_units])
	check(peak_foot <= RULES.MAX_FOOT_OFFICERS, "no máximo %d policiais a pé (%d)" % [RULES.MAX_FOOT_OFFICERS, peak_foot])
	check(controller.deployed_this_pursuit <= RULES.DEPLOYMENT[6], "orçamento de despacho respeitado (%d)" % controller.deployed_this_pursuit)
	# Dispensar recolhe tudo sem deixar corpos na cena.
	gameplay.clear_wanted()
	controller.dismiss_all("test")
	await _frames(3)
	check(controller.units.is_empty() and controller.foot_officer_count() == 0, "dismiss_all libera todas as viaturas")
	KIT.teardown(bundle)
	done("entity_limits")

func _blocked_road() -> void:
	# Parede sobre a única rua entre a garagem e o crime: a viatura não atravessa,
	# não teleporta, tenta ré e, sem caminho alternativo, desiste da rota.
	var bundle := KIT.build(self, KIT.single_road(), Vector3(40, 0, 6))
	var scene: Node3D = bundle.scene
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	KIT.add_wall(scene, Vector3(-10, 1.5, 0), Vector3(1.0, 3.0, 14.0))
	controller.set_depots("police", [Vector3(-40, 0, 2)])
	await _frames(3)
	gameplay.register_crime(60, bundle.player.global_position)
	var unit: RefCounted = null
	for tick in 900:
		await physics_frame
		gameplay.health = 100.0
		if not controller.units.is_empty():
			unit = controller.units[0]
			break
	check(unit != null, "despacho acontece mesmo com a rua cortada")
	if unit == null:
		KIT.teardown(bundle)
		return
	var start_x: float = unit.vehicle.global_position.x
	check(start_x < -10.0, "a viatura nasceu antes da parede (%.1f)" % start_x)
	var crossed := false
	var tracker := Tracker.new()
	tracker.vehicle = unit.vehicle
	for tick in 5400:
		await physics_frame
		gameplay.health = 100.0
		tracker.sample()
		if is_instance_valid(unit.vehicle) and unit.vehicle.global_position.x > -9.0: crossed = true
		if unit.finished: break
	check(not crossed, "a viatura nunca atravessou a parede")
	check(tracker.worst < 0.6, "nenhum salto de posição diante do obstáculo: %.2f m" % tracker.worst)
	check(not controller.events_named("replanned").is_empty(), "o piloto pediu novo plano ao ficar preso")
	# DispatchUnit.on_gave_up: perto do crime (até SPAWN_MAX) a viatura estaciona e a
	# equipe termina a pé, para a perseguição não ser abandonada num cruzamento travado;
	# longe dele, desiste da rota e sai de cena.
	var anchor: Vector3 = bundle.player.global_position
	var flat := Vector2(start_x - anchor.x, unit.vehicle.global_position.z - anchor.z).length() if is_instance_valid(unit.vehicle) else INF
	if flat <= RULES.SPAWN_MAX:
		check(unit.state in ["parked", "working"], "sem alternativa e perto do crime, a viatura estaciona e a equipe segue a pé (%s)" % unit.state)
	else:
		check(not controller.events_named("route_blocked").is_empty(), "sem alternativa e longe do crime, a viatura desistiu da rota")
		check(unit.finished or unit.state == "departing", "e passou a sair de cena, sem ficar presa para sempre (%s)" % unit.state)
	KIT.teardown(bundle)
	done("blocked_road")

func _crew_depleted() -> void:
	# Morreu toda a dupla que desceu: a viatura não cria outra dupla nem gasta
	# orçamento; fica parada, e reposição só nasce como viatura nova do orçamento.
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	await _frames(3)
	gameplay.register_crime(60, bundle.player.global_position)
	var unit: RefCounted = null
	for tick in 600:
		await physics_frame
		gameplay.health = 100.0
		if not controller.units.is_empty():
			unit = controller.units[0]
			break
	if unit == null:
		check(false, "despacho para equipe abatida")
		KIT.teardown(bundle)
		return
	var deployed := false
	for tick in 4200:
		await physics_frame
		gameplay.health = 100.0
		if unit.state == "working" and not unit.officers.is_empty():
			deployed = true
			break
	check(deployed, "dupla desembarcou antes de ser abatida")
	check(unit.crew_remaining == 0, "a dupla inteira desceu: nenhum policial sobra na viatura (%d)" % unit.crew_remaining)
	var seen := {}
	for officer in unit.officers: seen[officer.get_instance_id()] = true
	var budget_before: int = controller.deployed_this_pursuit
	for officer in unit.officers.duplicate(): officer.receive_damage(1000.0, null)
	var left := false
	for tick in 1800:
		await physics_frame
		gameplay.health = 100.0
		for officer in unit.officers: seen[officer.get_instance_id()] = true
		if unit.finished or unit.state == "departing":
			left = true
			break
	check(not controller.events_named("crew_depleted").is_empty(), "viatura sem equipe foi reconhecida")
	check(left and unit.end_reason == "crew_depleted" and is_instance_valid(unit.vehicle) and not unit.vehicle.controlled, "viatura sem equipe permanece parada e libera a vaga")
	check(seen.size() == 2, "a viatura nunca teve mais de dois policiais (%d)" % seen.size())
	# Cada ponto de orçamento corresponde a uma viatura despachada: repor a dupla
	# escondida na mesma viatura gastaria orçamento sem gerar evento.
	check(controller.events_named("dispatched").size() == controller.deployed_this_pursuit, "orçamento gasto só com viaturas novas (%d eventos, %d gastos, antes %d)" % [controller.events_named("dispatched").size(), controller.deployed_this_pursuit, budget_before])
	check(controller.deployed_this_pursuit <= RULES.DEPLOYMENT[3], "orçamento do patamar não estourou")
	KIT.teardown(bundle)
	done("crew_depleted")

func _disable_restores_legacy() -> void:
	# Desligar o módulo devolve o despacho embutido sem mexer na procura.
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	await _frames(3)
	gameplay.register_crime(60, bundle.player.global_position)
	await _frames(90)
	check(gameplay.dispatch_owned and gameplay.police.is_empty(), "com o módulo ligado o legado não despacha")
	var points: int = gameplay.crime_points
	var stars: int = gameplay.stars
	var deployed: int = gameplay.deployed
	controller.set_enabled(false)
	check(controller.units.is_empty(), "desligar recolhe as viaturas")
	check(not gameplay.dispatch_owned, "ownership do despacho legado restaurado")
	check(gameplay.crime_points == points and gameplay.stars == stars and gameplay.deployed == deployed, "procura e orçamento intocados (pontos %d, estrelas %d, deployed %d)" % [gameplay.crime_points, gameplay.stars, gameplay.deployed])
	check(gameplay.emergency.dispatch_clock < 1.0e8, "despacho médico legado restaurado")
	await _frames(900)
	check(not gameplay.police.is_empty(), "o comportamento legado voltou a despachar policiais")
	KIT.teardown(bundle)
	done("disable_restores_legacy")
