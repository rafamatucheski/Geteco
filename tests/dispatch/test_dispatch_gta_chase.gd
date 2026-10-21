extends SceneTree
## Perseguição de carro estilo GTA (gameplay/dispatch/PursuitRules.gd) em laboratório: anel de ruas
## com avenidas cruzadas, um carro em fuga dirigido por um robô simples (mesma física de Vehicle das
## viaturas) e o despacho real. Confere regras puras, contato/PIT, teto novo, reciclagem da viatura
## deixada para trás, nascimento à frente, busca em leque, bloqueio com pregos à frente, bloqueador
## de cruzamento, prisão dentro do carro parado e o interruptor desligado (comportamento antigo).
## Uma suíte verde prova só estes cenários de laboratório; a sensação no jogo é outra verificação.

const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")
const PATH := preload("res://gameplay/dispatch/PursuitPath.gd")
const RADIO := preload("res://gameplay/dispatch/PursuitRadio.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")
const CONTROLLER := preload("res://gameplay/dispatch/DispatchController.gd")
const ROUTES := preload("res://gameplay/NativeTrafficRoutes.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const RING := 140.0
const EXTENT := 200.0

var failures: Array[String] = []
var checks := 0
var groups_done: Array[String] = []
var _gta_contacts := -1
var _old_contacts := -1

class ChaseWorld extends Node3D:
	var driving: Object

class FakeDriving extends RefCounted:
	var occupied := true
	var car: CharacterBody3D

## Robô de fuga: segue a faixa do anel (polilinha fechada) a uma velocidade alvo, freando nas
## esquinas. Usa as entradas externas do Vehicle, como o piloto das viaturas.
class Fleer extends RefCounted:
	var car: CharacterBody3D
	var points: PackedVector3Array
	var speed := 18.0
	var stopped := false
	func tick() -> void:
		if not is_instance_valid(car): return
		car.set_external_driver(true)
		if stopped:
			car.throttle_input = 0.0
			car.steer_input = 0.0
			car.brake_input = true
			return
		var count := points.size()
		var position := car.global_position
		var best := 0
		var best_distance := INF
		for index in count:
			var closest := Geometry3D.get_closest_point_to_segment(position, points[index], points[(index + 1) % count])
			var distance := closest.distance_squared_to(position)
			if distance < best_distance:
				best_distance = distance
				best = index
		var cursor := Geometry3D.get_closest_point_to_segment(position, points[best], points[(best + 1) % count])
		var left := 9.0
		var index := best
		var aim := cursor
		for guard in count:
			var next := points[(index + 1) % count]
			var span := aim.distance_to(next)
			if span >= left:
				aim = aim.move_toward(next, left)
				break
			left -= span
			aim = next
			index = (index + 1) % count
		var corner := points[(best + 1) % count]
		var wanted := speed if corner.distance_to(position) > 22.0 else 9.0
		var forward := -car.global_basis.z
		var to_aim := aim - position
		to_aim.y = 0.0
		var alpha := forward.signed_angle_to(to_aim.normalized(), Vector3.UP) if to_aim.length_squared() > 0.01 else 0.0
		car.steer_input = clampf(atan2(5.0 * sin(alpha), 9.0) / 0.48, -1.0, 1.0)
		car.brake_input = car.speed > wanted + 1.5
		car.throttle_input = 0.0 if car.brake_input else clampf((wanted - car.speed) * 0.5, 0.0, 1.0)

func done(group: String) -> void:
	groups_done.append(group)
	print("GROUP_OK " + group)

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

func _frames(count: int) -> void:
	for index in count: await physics_frame

func run() -> void:
	var original := PURSUIT.enabled
	PURSUIT.enabled = true
	_rules()
	await _chase(true)
	await _recycle()
	await _spawn_ahead()
	await _search_fan()
	await _roadblock_ahead()
	await _blocker()
	await _offroad()
	await _busted_in_car()
	PURSUIT.enabled = false
	await _chase(false)
	await _toggle_off()
	PURSUIT.enabled = original
	print("GTA_CHASE contacts gta=%d old=%d" % [_gta_contacts, _old_contacts])
	report("DISPATCH_GTA", ["rules", "chase_gta", "recycle", "spawn_ahead", "search_fan", "roadblock_ahead", "blocker", "offroad", "busted_in_car", "chase_old", "toggle_off"], 48)

# --- Cenário -----------------------------------------------------------------------

func _roads() -> Array:
	return KIT.grid_roads(EXTENT, RING)

func _build(car_position: Vector3, car_yaw: float) -> Dictionary:
	var scene := ChaseWorld.new()
	root.add_child(scene)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(520, 1, 520)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	var player := ACTOR.new()
	player.is_player = true
	player.controlled_automatically = true
	player.position = car_position + Vector3(0, 0, 3)
	scene.add_child(player)
	var state := KIT.CombatState.new()
	var gameplay := GAMEPLAY.new()
	gameplay.configure(scene, player, null, state)
	scene.add_child(gameplay)
	var routes := ROUTES.new()
	routes.configure(_roads())
	var controller := CONTROLLER.new()
	controller.configure(scene, gameplay, routes)
	scene.add_child(controller)
	var car := VEHICLE.new()
	car.archetype = "sport_coupe"
	car.vehicle_id = "gta_chase_target"
	scene.add_child(car)
	car.place(car_position + Vector3.UP * 0.12, car_yaw)
	car.set_external_driver(true)
	player.hide()
	var driving := FakeDriving.new()
	driving.car = car
	scene.driving = driving
	var fleer := Fleer.new()
	fleer.car = car
	fleer.points = _ring_lane()
	return {"scene": scene, "gameplay": gameplay, "controller": controller, "routes": routes, "car": car, "fleer": fleer, "player": player, "driving": driving}

## Faixa da direita do anel, 2 m por fora do eixo: sul para leste (+X), leste para o norte (-Z),
## norte para oeste, oeste para o sul. A direita de quem anda em +X é +Z.
func _ring_lane() -> PackedVector3Array:
	var lane := RING + 2.0
	return PackedVector3Array([Vector3(-lane, 0, lane), Vector3(lane, 0, lane), Vector3(lane, 0, -lane), Vector3(-lane, 0, -lane)])

func _event_counts(controller: Node3D) -> Dictionary:
	var counts: Dictionary = {}
	for entry in controller.events:
		counts[entry.name] = int(counts.get(entry.name, 0)) + 1
	return counts

func _teardown(bundle: Dictionary) -> void:
	var scene: Node = bundle.scene
	if is_instance_valid(scene): scene.free()

## Lado sul do anel (z = +RING), na faixa de quem anda para leste (+X).
func _ring_start() -> Vector3:
	return Vector3(-90, 0, RING + 2.0)

# --- Grupos ---------------------------------------------------------------------------

func _rules() -> void:
	check(absf(PURSUIT.corner_speed(1.0 / 8.0) - sqrt(PURSUIT.LATERAL_ACCEL * 8.0)) < 0.01, "velocidade de curva √(a·R) num raio de 8 m")
	check(PURSUIT.corner_speed(0.0) == INF, "reta não limita")
	check(PURSUIT.brake_window(8.0, 30.0) > 20.0, "frenagem até a curva admite chegar rápido de longe")
	check(PURSUIT.speed_cap("patrol") > RULES.speed_cap("patrol") and PURSUIT.speed_cap("interceptor") > PURSUIT.speed_cap("patrol"), "teto da perseguição acima do antigo e interceptor mais rápido")
	var goal := PURSUIT.chase_goal(Vector3.ZERO, Vector3(20, 0, 0))
	check(goal.x >= PURSUIT.GOAL_LEAD_MIN and absf(goal.z) < 0.01, "objetivo da rota fica à frente do alvo (%.0f m)" % goal.x)
	var ahead := PURSUIT.spawn_score(Vector3(50, 0, 0), deg_to_rad(-90.0), Vector3.ZERO, Vector3.RIGHT, 20.0)
	var behind := PURSUIT.spawn_score(Vector3(-50, 0, 0), deg_to_rad(90.0), Vector3.ZERO, Vector3.RIGHT, 20.0)
	check(ahead < behind, "nascimento à frente vence o de trás (%.0f < %.0f)" % [ahead, behind])
	var facing := PURSUIT.spawn_score(Vector3(50, 0, 0), deg_to_rad(90.0), Vector3.ZERO, Vector3.RIGHT, 20.0)
	check(facing < ahead, "à frente e virado para o alvo vence à frente e de costas")
	check(PURSUIT.in_vision(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -65)), "cone frontal enxerga a 65 m")
	check(not PURSUIT.in_vision(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, 50)), "atrás, a 50 m, não enxerga")
	check(PURSUIT.in_vision(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, 25)), "raio curto enxerga atrás a 25 m")
	check(PURSUIT.search_radius(1) > 0.0 and PURSUIT.search_radius(6) > PURSUIT.search_radius(1), "área de busca cresce com as estrelas")
	# Traseira esquerda (x<0, z>0) empurrada para a direita gira o nariz para a esquerda (+Y).
	var spin := PURSUIT.pit_spin(Vector3(-0.8, 0, 1.8), Vector3(5, 0, 0), Basis.IDENTITY, 1.0, 2.2)
	check(spin > 0.5, "PIT na traseira lateral gira o carro (%.2f rad/s)" % spin)
	check(PURSUIT.pit_spin(Vector3(-0.8, 0, -1.8), Vector3(5, 0, 0), Basis.IDENTITY, 1.0, 2.2) == 0.0, "batida na frente não é PIT")
	var follow := PURSUIT.guide(0, false, Vector3(0, 0, 30), Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -15), 1.0, 2.2, 1.0)
	check(follow.mode == "follow" and follow.point.z > 2.2, "sem força autorizada só cola atrás")
	var pit := PURSUIT.guide(0, true, Vector3(-0.5, 0, 6), Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -15), 1.0, 2.2, 1.0)
	check(pit.mode == "pit" and pit.speed > 15.0, "com força o perseguidor faz PIT mais rápido que o alvo")
	check(PURSUIT.next_role([]) == PURSUIT.ROLE_CHASER and PURSUIT.next_role([0]) == PURSUIT.ROLE_FLANK_LEFT and PURSUIT.next_role([0, 1]) == PURSUIT.ROLE_BLOCKER, "papéis preenchidos por prioridade")
	var routes := ROUTES.new()
	routes.configure(_roads())
	var router := preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
	router.configure(routes)
	var prediction := PATH.predict(routes, router, Vector3(-150, 0, -2), Vector3(20, 0, 0), 250.0)
	check(not prediction.junctions.is_empty(), "previsão pelo grafo acha cruzamentos à frente (%d)" % prediction.junctions.size())
	var first_junction: Vector3 = prediction.points[prediction.junctions[0]] if not prediction.junctions.is_empty() else Vector3.INF
	check(first_junction.x > -150.0, "primeiro cruzamento previsto está à frente (x=%.0f)" % first_junction.x)
	check(RADIO.heading_name(Vector3(0, 0, -10)) == "norte" and RADIO.heading_name(Vector3(10, 0, 0)) == "leste", "sentido cardeal do rádio (norte = -Z)")
	check(RADIO.street_name("union_avenue") == "Union Avenue" and RADIO.street_name("mountain_bridge_inbound") == "ponte da serra", "nome de rua do rádio")
	check(RADIO.street_name("desert_route_66") == "Rota 66" and RADIO.street_name("mountain_track_3") == "estrada da serra", "ruas do deserto e da serra têm nome no rádio")
	var fleeing := RADIO.compose("fleeing", "Quay Boulevard", "norte")
	check(fleeing.text == "Suspeito em fuga no Quay Boulevard, sentido norte." and str(fleeing.clips) == str(["phrase:fleeing", "street:Quay Boulevard", "heading:norte"]), "fala montada em PT: texto e pedaços (%s)" % fleeing.text)
	var english := RADIO.compose("fleeing", "Rota 66", "sudoeste", true)
	check(english.text == "Suspect fleeing on Route 66, heading southwest.", "fala montada em inglês (%s)" % english.text)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://audio/police_radio/manifest.json"))
	var voiced: bool = manifest is Dictionary and manifest.phrases.has("fleeing") and manifest.headings.has("norte")
	check(voiced, "rádio tem voz gravada para frase-base e sentido")
	var audio := preload("res://gameplay/dispatch/PursuitRadioAudio.gd").new()
	root.add_child(audio)
	# Em inglês ainda não há gravação (cota da ElevenLabs acabou em 21/10): só confere em português.
	check(audio._language == "en" or (audio.clip("phrase:fleeing").ends_with(".wav") and audio.clip("street:Rua Que Não Existe").is_empty()), "voz do rádio acha o pedaço e pula o que não foi gravado")
	audio.queue_free()
	done("rules")

## Perseguição real no anel: o robô foge a 18 m/s com duas estrelas e contato mantido por
## "testemunhas"; mede contato físico, aproximação, velocidade das viaturas e saltos.
func _chase(gta: bool) -> void:
	var bundle := _build(_ring_start(), deg_to_rad(-90.0))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var car: CharacterBody3D = bundle.car
	var fleer: RefCounted = bundle.fleer
	await _frames(3)
	gameplay.register_crime(30, car.global_position)
	var label := "gta" if gta else "old"
	check(gameplay.stars == 2, "%s: 30 pontos = 2 estrelas" % label)
	var contacts := 0
	var touching := false
	var closest := INF
	var top_speed := 0.0
	var worst_step := 0.0
	var last: Dictionary = {}
	var spawned := 0
	var fled := 0.0
	var fleer_top := 0.0
	var previous_car := car.global_position
	var states: Dictionary = {}
	for tick in 60 * 50:
		fleer.tick()
		await physics_frame
		gameplay.health = 100.0
		if tick % 20 == 0: gameplay.report_contact(car.global_position)
		fled += car.global_position.distance_to(previous_car)
		previous_car = car.global_position
		fleer_top = maxf(fleer_top, car.speed)
		if tick % 60 == 0:
			for unit in controller.units:
				if unit.is_police() and not unit.finished:
					var key := "%s/%s" % [unit.state, unit.guide_mode]
					states[key] = int(states.get(key, 0)) + 1
		var any_touch := false
		for unit in controller.units:
			if not unit.is_police() or unit.finished or not is_instance_valid(unit.vehicle): continue
			var police: CharacterBody3D = unit.vehicle
			var id := police.get_instance_id()
			if last.has(id): worst_step = maxf(worst_step, police.global_position.distance_to(last[id]))
			last[id] = police.global_position
			top_speed = maxf(top_speed, police.speed)
			closest = minf(closest, Vector2(police.global_position.x - car.global_position.x, police.global_position.z - car.global_position.z).length())
			for index in police.get_slide_collision_count():
				if police.get_slide_collision(index).get_collider() == car: any_touch = true
		if any_touch and not touching: contacts += 1
		touching = any_touch
		spawned = maxi(spawned, controller.deployed_this_pursuit)
	print("CHASE_%s contacts=%d closest=%.1f top_speed=%.1f worst_step=%.2f spawned=%d stats=%s" % [label.to_upper(), contacts, closest, top_speed, worst_step, spawned, str(controller.pursuit_stats)])
	print("CHASE_%s_DIAG fled=%.0f m fleer_top=%.1f stars=%d contact_age=%.1f states=%s events=%s" % [label.to_upper(), fled, fleer_top, gameplay.stars, gameplay.contact_age, str(states), str(_event_counts(controller))])
	check(fled > 400.0, "%s: o carro em fuga andou de verdade (%.0f m)" % [label, fled])
	check(spawned >= 1, "%s: viatura despachada na perseguição" % label)
	check(worst_step < 1.0, "%s: sem teletransporte (maior passo %.2f m)" % [label, worst_step])
	if gta:
		_gta_contacts = contacts
		check(top_speed > RULES.SPEED_PATROL + 1.0, "gta: viatura passa do teto antigo de %.0f m/s (%.1f)" % [RULES.SPEED_PATROL, top_speed])
		check(closest < 6.0, "gta: viatura encosta no carro em fuga (menor distância %.1f m)" % closest)
		check(contacts >= 1, "gta: houve contato físico com o carro em fuga (%d)" % contacts)
		check(int(controller.pursuit_stats.get("guide_pit", 0)) + int(controller.pursuit_stats.get("guide_flank", 0)) + int(controller.pursuit_stats.get("guide_swipe", 0)) >= 1, "gta: guiamento final entrou em PIT/flanco")
		check(not controller.radio_line().is_empty() or controller.radio.line != "", "gta: rádio da central falou")
		done("chase_gta")
	else:
		_old_contacts = contacts
		check(top_speed <= RULES.SPEED_FAST + 0.5, "old: viatura respeita o teto antigo (%.1f)" % top_speed)
		done("chase_old")
	_teardown(bundle)
	await process_frame

## Viatura deixada para trás com contato recente: some e devolve vaga e orçamento; desligado, congela.
func _recycle() -> void:
	var bundle := _build(_ring_start(), deg_to_rad(-90.0))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var car: CharacterBody3D = bundle.car
	await _frames(3)
	gameplay.register_crime(30, car.global_position)
	gameplay.report_contact(car.global_position)
	var unit: RefCounted = controller.dispatch_police_to(car.global_position)
	check(unit != null, "recycle: viatura despachada")
	if unit == null:
		_teardown(bundle)
		return
	var deployed: int = controller.deployed_this_pursuit
	# Leva o alvo para longe: a viatura fica a mais de 130 m, fora da vista, com contato recente.
	car.place(Vector3(RING - 2.0, 0.12, -RING + 10.0), 0.0)
	unit.vehicle.place(Vector3(-RING + 2.0, 0.12, RING - 10.0), 0.0)
	gameplay.report_contact(car.global_position)
	await _frames(4)
	check(unit.finished and unit.end_reason == "outrun", "recycle: viatura deixada para trás é reciclada (%s, %s)" % [str(unit.finished), unit.end_reason])
	check(controller.deployed_this_pursuit == deployed - 1, "recycle: orçamento de despacho devolvido (%d -> %d)" % [deployed, controller.deployed_this_pursuit])
	check(int(controller.pursuit_stats.get("outrun", 0)) == 1, "recycle: contador de reciclagem")
	# Sem contato recente ela volta a ser só suspensa (a busca longa não fica gerando viaturas).
	var second: RefCounted = controller.dispatch_police_to(car.global_position)
	if second != null:
		gameplay.contact_age = PURSUIT.RECYCLE_CONTACT_AGE + 5.0
		second.vehicle.place(Vector3(-RING + 2.0, 0.12, RING - 10.0), 0.0)
		await _frames(4)
		check(second.suspended and not second.finished, "recycle: sem contato recente a viatura distante só é suspensa")
	done("recycle")
	_teardown(bundle)
	await process_frame

## Alvo a 20 m/s para leste: o reforço nasce à frente dele.
func _spawn_ahead() -> void:
	var bundle := _build(Vector3(-150, 0, -2), deg_to_rad(-90.0))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var car: CharacterBody3D = bundle.car
	await _frames(3)
	gameplay.register_crime(60, car.global_position)
	var ahead_count := 0
	var total := 0
	for attempt in 3:
		car.horizontal_velocity = Vector3(20, 0, 0)
		gameplay.report_contact(car.global_position)
		var unit: RefCounted = controller.dispatch_police_to(car.global_position)
		if unit == null: continue
		total += 1
		if (unit.vehicle.global_position - car.global_position).dot(Vector3.RIGHT) > 10.0: ahead_count += 1
	check(total >= 2, "spawn_ahead: reforços despachados (%d)" % total)
	check(ahead_count == total and total > 0, "spawn_ahead: todos nasceram à frente do alvo (%d/%d)" % [ahead_count, total])
	check(int(controller.pursuit_stats.get("spawn_ahead", 0)) == total, "spawn_ahead: contador")
	done("spawn_ahead")
	_teardown(bundle)
	await process_frame

## Contato perdido com o alvo de carro: as viaturas vasculham pontos diferentes e ninguém desce.
func _search_fan() -> void:
	var bundle := _build(Vector3(0, 0, -2), deg_to_rad(-90.0))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var car: CharacterBody3D = bundle.car
	await _frames(3)
	gameplay.register_crime(60, car.global_position)
	gameplay.report_contact(car.global_position)
	var first: RefCounted = controller.dispatch_police_to(car.global_position)
	var second: RefCounted = controller.dispatch_police_to(car.global_position)
	await _frames(5)
	check(controller.pursuit_in_car, "search_fan: último contato foi de carro")
	# Some: invisível no lugar, sem novo contato (perto, para as viaturas não serem suspensas por distância).
	car.hide()
	var deployed := false
	for tick in 60 * 8:
		await physics_frame
		gameplay.health = 100.0
		for unit in controller.units:
			if unit.is_police() and not unit.officers.is_empty(): deployed = true
	var points: Array[Vector3] = []
	for unit in [first, second]:
		if unit != null and not unit.finished and unit.search_point != Vector3.INF: points.append(unit.search_point)
	check(points.size() >= 1, "search_fan: viatura recebeu ponto de busca (%d)" % points.size())
	if points.size() == 2: check(points[0].distance_to(points[1]) > 5.0, "search_fan: pontos de busca diferentes por viatura")
	var radius: float = gameplay.police_search_radius()
	for point in points:
		check(Vector2(point.x - gameplay.last_known.x, point.z - gameplay.last_known.z).length() <= radius + 1.0, "search_fan: ponto dentro da área de busca")
	check(not deployed, "search_fan: busca de carro não desce equipe a pé")
	# Fuga: fora da área anda normal; dentro, devagar.
	car.place(gameplay.last_known + Vector3(5, 0.12, 0), 0.0)
	check(is_equal_approx(gameplay._evasion_rate(), PURSUIT.EVASION_INSIDE_RATE), "search_fan: dentro da área a fuga anda devagar")
	car.place(gameplay.last_known + Vector3(radius + 20.0, 0.12, 0), 0.0)
	check(is_equal_approx(gameplay._evasion_rate(), 1.0), "search_fan: fora da área a fuga anda normal")
	done("search_fan")
	_teardown(bundle)
	await process_frame

## Três estrelas, alvo a 20 m/s pela avenida: o bloqueio com pregos vai no caminho dele, à frente.
func _roadblock_ahead() -> void:
	var bundle := _build(Vector3(-170, 0, -2), deg_to_rad(-90.0))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var car: CharacterBody3D = bundle.car
	await _frames(3)
	gameplay.register_crime(60, car.global_position)
	var block: Node3D = controller.roadblocks.try_place_ahead(car.global_position, Vector3(20, 0, 0))
	check(block != null, "roadblock_ahead: bloqueio montado no caminho previsto")
	if block != null:
		var along := (block.global_position - car.global_position).dot(Vector3.RIGHT)
		check(along >= PURSUIT.ROADBLOCK_AHEAD_MIN - 5.0 and along <= PURSUIT.ROADBLOCK_AHEAD_MAX + 5.0, "roadblock_ahead: %.0f m à frente" % along)
		check(absf(block.global_position.z) < 6.0, "roadblock_ahead: sobre a avenida do alvo (z=%.1f)" % block.global_position.z)
	done("roadblock_ahead")
	_teardown(bundle)
	await process_frame

## Bloqueador: alvo indo para leste pela avenida; a viatura perto do cruzamento central chega antes.
func _blocker() -> void:
	var bundle := _build(Vector3(-170, 0, -2), deg_to_rad(-90.0))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var car: CharacterBody3D = bundle.car
	await _frames(3)
	gameplay.register_crime(60, car.global_position)
	gameplay.report_contact(car.global_position)
	var unit: RefCounted = controller.dispatch_police_to(car.global_position)
	check(unit != null, "blocker: viatura despachada")
	if unit == null:
		_teardown(bundle)
		return
	unit.role = PURSUIT.ROLE_BLOCKER
	unit.vehicle.place(Vector3(2, 0.12, 40), PI)
	var picked: Vector3 = unit._pick_block_point(car.global_position, Vector3(20, 0, 0))
	check(picked != Vector3.INF, "blocker: achou cruzamento à frente em que chega antes")
	if picked != Vector3.INF:
		check((picked - car.global_position).dot(Vector3.RIGHT) >= PURSUIT.BLOCK_MIN_DISTANCE, "blocker: cruzamento à frente do alvo (x=%.0f)" % picked.x)
	# Viatura longe demais (atrás do alvo) não tenta: chegaria depois dele.
	unit.vehicle.place(Vector3(-RING + 2.0, 0.12, RING - 10.0), 0.0)
	check(unit._pick_block_point(car.global_position, Vector3(20, 0, 0)) != picked or picked == Vector3.INF, "blocker: viatura atrasada não fica com o mesmo cruzamento")
	done("blocker")
	_teardown(bundle)
	await process_frame

## Alvo circulando fora do asfalto (quadrado de 50 m centrado em (70, 70), a mais de 40 m de qualquer
## rua): com ele à vista a viatura sai da ponta da rua e guia direto até ele.
func _offroad() -> void:
	var bundle := _build(Vector3(45, 0, 45), deg_to_rad(-90.0))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var car: CharacterBody3D = bundle.car
	var fleer: RefCounted = bundle.fleer
	fleer.points = PackedVector3Array([Vector3(45, 0, 45), Vector3(95, 0, 45), Vector3(95, 0, 95), Vector3(45, 0, 95)])
	fleer.speed = 8.0
	await _frames(3)
	gameplay.register_crime(30, car.global_position)
	var closest := INF
	var offroad_seen := false
	for tick in 60 * 35:
		fleer.tick()
		await physics_frame
		gameplay.health = 100.0
		if tick % 20 == 0: gameplay.report_contact(car.global_position)
		for unit in controller.units:
			if not unit.is_police() or unit.finished or not is_instance_valid(unit.vehicle): continue
			if unit.target_offroad: offroad_seen = true
			closest = minf(closest, Vector2(unit.vehicle.global_position.x - car.global_position.x, unit.vehicle.global_position.z - car.global_position.z).length())
	print("OFFROAD closest=%.1f stats=%s" % [closest, str(controller.pursuit_stats)])
	check(offroad_seen, "offroad: viatura reconhece o alvo fora da rua")
	check(int(controller.pursuit_stats.get("guide_offroad", 0)) >= 1, "offroad: guiamento direto de longe com o alvo fora da rua")
	check(closest < 8.0, "offroad: viatura chega até o alvo fora do asfalto (menor distância %.1f m)" % closest)
	done("offroad")
	_teardown(bundle)
	await process_frame

## Duas estrelas sem força autorizada, carro parado: a polícia para, desce e prende quem está nele.
func _busted_in_car() -> void:
	# No meio da quadra: o planejador de parada não estaciona dentro de cruzamento.
	var bundle := _build(Vector3(-70, 0, 2), deg_to_rad(-90.0))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var car: CharacterBody3D = bundle.car
	var driving: RefCounted = bundle.driving
	await _frames(3)
	gameplay.register_crime(30, car.global_position)
	check(gameplay.stars == 2 and not gameplay.police_force_authorized(), "busted: duas estrelas sem força autorizada")
	check(gameplay.police_can_arrest(), "busted: dentro do carro com duas estrelas a prisão é permitida")
	driving.occupied = false
	check(not gameplay.police_can_arrest(), "busted: a pé com duas estrelas continua sem prisão (regra antiga)")
	driving.occupied = true
	var arrested := [false]
	gameplay.player_arrested.connect(func(): arrested[0] = true)
	for tick in 60 * 45:
		await physics_frame
		gameplay.health = 100.0
		if tick % 20 == 0: gameplay.report_contact(car.global_position)
		if arrested[0]: break
	var states: Array[String] = []
	for unit in controller.units:
		if unit.is_police(): states.append("%s/%s d=%.1f" % [unit.state, unit.guide_mode, Vector2(unit.vehicle.global_position.x - car.global_position.x, unit.vehicle.global_position.z - car.global_position.z).length()])
	print("BUSTED_DIAG arrested=%s states=%s events=%s" % [str(arrested[0]), str(states), str(_event_counts(controller))])
	check(arrested[0], "busted: policial chegou à porta do carro parado e prendeu (%s)" % str(controller.status()))
	done("busted_in_car")
	_teardown(bundle)
	await process_frame

## Interruptor desligado: nada do comportamento novo (nascimento mais próximo, suspensão, regra de prisão).
func _toggle_off() -> void:
	var bundle := _build(_ring_start(), deg_to_rad(-90.0))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var car: CharacterBody3D = bundle.car
	await _frames(3)
	gameplay.register_crime(30, car.global_position)
	gameplay.report_contact(car.global_position)
	check(not gameplay.police_can_arrest(), "off: sem prisão dentro do carro com duas estrelas")
	check(is_equal_approx(gameplay._evasion_rate(), 1.0), "off: fuga só por tempo")
	var unit: RefCounted = controller.dispatch_police_to(car.global_position)
	if unit != null:
		unit.vehicle.place(Vector3(-RING + 2.0, 0.12, -RING + 10.0), 0.0)
		car.place(Vector3(RING - 2.0, 0.12, RING - 10.0), 0.0)
		gameplay.report_contact(car.global_position)
		await _frames(4)
		check(unit.suspended and not unit.finished, "off: viatura distante é suspensa, não reciclada")
	check(controller.pursuit_stats.is_empty(), "off: nenhum contador da perseguição nova")
	check(controller.radio_line().is_empty(), "off: rádio calado")
	done("toggle_off")
	_teardown(bundle)
	await process_frame
