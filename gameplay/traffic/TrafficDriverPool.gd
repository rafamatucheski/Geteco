extends Node
## Motoristas visíveis no trânsito (playtest 29/10). Antes o carro do trânsito andava vazio e o
## civil só era criado no banco quando o jogador entrava (Driving._eject_civilian_driver): quebrando o
## vidro via-se o banco vazio.
##
## Custo: pool limitado de corpos (TrafficDriverModel), só nos carros do trânsito mais perto do foco
## da câmera. Corpo sem carro fica estacionado (escondido, fora do processamento) e volta no próximo
## carro; nunca se cria e destrói corpo por aparição. A escolha roda a 4 Hz sobre o grupo "drivable" e
## monta no máximo um corpo novo por passo (span `traffic_driver.build`), então o pool enche aos
## poucos depois da cortina. GETECO_TRAFFIC_DRIVERS=0 desliga (A/B); GETECO_TRAFFIC_DRIVERS_MAX muda
## o teto (padrão 8).
##
## Tiro: Gameplay._damage_bullet chama `bullet_hit`. Se a linha do tiro passa pelo tronco do motorista,
## ele morre (cai sobre o volante e o carro para), se fere (curva de dor e o carro segue) ou, com o
## carro devagar, sai e foge (vira Actor civil ao lado da porta e a reação dos civis assume).
const CARJACKING := preload("res://gameplay/VehicleCarjacking.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const MOCAP := preload("res://gameplay/VehicleBoardingMocap.gd")
const MODEL := preload("res://gameplay/traffic/TrafficDriverModel.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const STEP := .25
const RADIUS := 45.0
## Corpo do motorista (tronco) a esta distância da linha do tiro conta como acertado.
const HIT_RADIUS := .32
## Abaixo disso o motorista ferido larga o carro e foge; acima, segue dirigindo.
const FLEE_SPEED := 4.0
const STATE_META := "traffic_driver_state" # "", "hurt", "dead", "gone"

static func enabled() -> bool:
	return OS.get_environment("GETECO_TRAFFIC_DRIVERS") != "0"

static func limit() -> int:
	var raw := OS.get_environment("GETECO_TRAFFIC_DRIVERS_MAX")
	return clampi(int(raw), 0, 32) if raw.is_valid_int() else 8

var world: Node3D
var _clock := 0.0
var _bodies: Array[Node3D] = []
var _parked: Array[Node3D] = []
## car instance id -> {"car": WeakRef, "body": Node3D}
var _assigned: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _max := 8

func configure(owner_world: Node3D) -> void:
	world = owner_world
	_max = limit()
	_rng.randomize()

func _physics_process(delta: float) -> void:
	_clock += delta
	if _clock < STEP: return
	_clock = 0.0
	var began := STALL_WORK.begin()
	_refresh()
	STALL_WORK.finish_slow("traffic_driver.refresh", began, 1000, self)

static func of(owner_world: Node) -> Node:
	if owner_world == null: return null
	var production: Variant = owner_world.get("production")
	if production != null and is_instance_valid(production):
		var pool: Variant = production.get("traffic_drivers")
		if pool != null and is_instance_valid(pool): return pool
	return null

## Carro do trânsito que mostra motorista: carro de passeio guiado pela IA, sem tripulação própria.
static func eligible(car: Node) -> bool:
	if not is_instance_valid(car) or not car.is_inside_tree() or not (car is Node3D): return false
	if car.get("traffic") != true or car.get("controlled") == true or float(car.get("health")) <= 0.0: return false
	if not (car as Node3D).is_visible_in_tree() or not car.has_method("shows_seated_driver") or not car.shows_seated_driver(): return false
	# Viatura, gangue, carro-forte e corrida têm gente própria (DispatchUnit, gang_theft_handler...).
	if car.get_meta("dispatch_unit", false) or car.has_meta("gang_theft_handler") or car.get_meta("armored_transport", false) or car.get_meta("race_owned", false): return false
	return str(car.get_meta(STATE_META, "")) in ["", "hurt"]

func _focus() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null: return Vector3.INF
	if &"target" in camera and is_instance_valid(camera.get("target")):
		var target := camera.get("target") as Node3D
		if target != null: return target.global_position
	return camera.global_position

func _refresh() -> void:
	if not enabled() or _max <= 0 or world == null or not is_instance_valid(world): return
	# Rede de segurança: corpo liberado junto com um carro (não deveria, ver _on_car_exiting) sai da conta.
	for i in range(_bodies.size() - 1, -1, -1):
		if not is_instance_valid(_bodies[i]): _bodies.remove_at(i)
	for i in range(_parked.size() - 1, -1, -1):
		if not is_instance_valid(_parked[i]): _parked.remove_at(i)
	var focus := _focus()
	var wanted: Array = []
	if focus.is_finite():
		var scored: Array = []
		for node in get_tree().get_nodes_in_group("drivable"):
			# Morto continua com o corpo caído enquanto o carro existir (não entra no teto).
			if str(node.get_meta(STATE_META, "")) == "dead" and _assigned.has(node.get_instance_id()): continue
			if not eligible(node): continue
			var d := (node as Node3D).global_position.distance_squared_to(focus)
			if d <= RADIUS * RADIUS: scored.append([d, node])
		scored.sort_custom(func(a, b): return a[0] < b[0])
		for i in mini(scored.size(), _max): wanted.append(scored[i][1])
	# Solta quem saiu da lista (longe, virou do jogador, sumiu).
	for id in _assigned.keys():
		var entry: Dictionary = _assigned[id]
		var car: Object = (entry.car as WeakRef).get_ref()
		var dead := car != null and str(car.get_meta(STATE_META, "")) == "dead"
		if car != null and car in wanted: continue
		if dead and is_instance_valid(car) and (car as Node).is_inside_tree() and car.get("controlled") != true: continue
		if dead and is_instance_valid(car) and car.get("controlled") == true: _drop_corpse(car as Node3D, entry.body)
		_release(id)
	var built := false
	for car in wanted:
		if _assigned.has(car.get_instance_id()): continue
		var winter := _winter(car)
		var body: Node3D = _take_parked(winter)
		if body == null and not built and (_bodies.size() < _max or not _parked.is_empty()):
			# Pool cheio só com corpos do outro clima: troca um estacionado (acontece ao cruzar a ponte).
			if _bodies.size() >= _max:
				var stale: Node3D = _parked.pop_back()
				_bodies.erase(stale)
				stale.free()
			built = true
			var stage := STALL_WORK.begin()
			body = MODEL.create(_identity(car), winter)
			_bodies.append(body)
			STALL_WORK.finish_slow("traffic_driver.build", stage, 1000, self)
		if body == null: continue
		_attach(car, body)

## Na serra ninguém dirige de camiseta: o corpo reaproveitado precisa ser do mesmo clima do carro.
func _winter(car: Node) -> bool:
	return str(car.get_meta("region_id", "")) == "mountain" or WORLD_CONNECTION.logical_region((car as Node3D).global_position) == "mountain"

func _take_parked(winter: bool) -> Node3D:
	for i in range(_parked.size() - 1, -1, -1):
		if bool(_parked[i].get_meta("traffic_driver_winter", false)) == winter:
			var body: Node3D = _parked[i]
			_parked.remove_at(i)
			return body
	return null

func _identity(car: Node) -> int:
	# Aparência não consome o RNG do jogo (pintura, rotas, encontros), como o motoqueiro do trânsito.
	var id := str(car.get("vehicle_id"))
	return posmod(id.hash() if not id.is_empty() else car.get_instance_id(), 10000)

func _attach(car: Node3D, body: Node3D) -> void:
	var stage := STALL_WORK.begin()
	# Corpo reaproveitado mantém a aparência dele: trocar roupa/corpo importado no meio do jogo custaria
	# uma montagem inteira. A identidade guardada acompanha o corpo, então o roubo tira a mesma pessoa.
	if body.get_parent() != null: body.get_parent().remove_child(body)
	car.add_child(body)
	# O carro some com a região ou o despejo: o corpo volta ao pool antes de ser liberado com ele.
	var on_exit := Callable(self, "_on_car_exiting").bind(car.get_instance_id())
	if not car.tree_exiting.is_connected(on_exit): car.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	body.set_meta("traffic_driver_identity", int(body.get("appearance_variant")))
	_seat(car, body)
	body.show()
	body.set_process(true)
	_assigned[car.get_instance_id()] = {"car": weakref(car), "body": body}
	var state := str(car.get_meta(STATE_META, ""))
	body.set("hurt_bend", .45 if state == "hurt" else 0.0)
	body.set("slump", 1.0 if state == "dead" else 0.0)
	body.call("repose")
	STALL_WORK.finish_slow("traffic_driver.attach", stage, 1000, self)

## Pelve no banco medido do interior (o mesmo do Dante e da vítima do roubo), corpo encolhido na
## cabine baixa como em VehicleCarjacking.prepare.
func _seat(car: Node3D, body: Node3D) -> void:
	var hip: Vector3 = car.to_local(MOCAP.seat_pelvis(car))
	var cabin := INTERIOR.spec(car)
	var fit := 1.0
	if not cabin.is_empty():
		var room := float(cabin.roof) - .06 - (float(cabin.floor) + float(cabin.hip))
		fit = clampf(room / (.84 + .08), .78, 1.0)
	body.scale = Vector3.ONE * fit
	body.set("seat_height", maxf(.05, .45 - .08 * fit))
	body.position = Vector3(hip.x, hip.y - .45, hip.z)
	body.rotation = Vector3(0, PI, 0)
	var hands: Array = []
	if not cabin.is_empty() and cabin.has("hub_y"):
		var targets: Dictionary = INTERIOR._limb_targets(cabin)
		var to_body := body.transform.affine_inverse()
		# Índice 0 é o braço direito do corpo (CivilianModel: lado -1), como o motoqueiro do trânsito.
		if targets.hands.has("Right") and targets.hands.has("Left"):
			hands = [to_body * (targets.hands.Right as Transform3D).origin, to_body * (targets.hands.Left as Transform3D).origin]
	body.set("wheel_hands", hands)

func _on_car_exiting(id: int) -> void:
	_release(id)

func _release(id: int) -> void:
	var entry: Dictionary = _assigned.get(id, {})
	_assigned.erase(id)
	var car: Object = (entry.car as WeakRef).get_ref() if entry.has("car") else null
	var on_exit := Callable(self, "_on_car_exiting").bind(id)
	if is_instance_valid(car) and (car as Node).tree_exiting.is_connected(on_exit): (car as Node).tree_exiting.disconnect(on_exit)
	var body: Node3D = entry.get("body")
	if not is_instance_valid(body): return
	if body.get_parent() != null: body.get_parent().remove_child(body)
	body.hide()
	body.set_process(false)
	body.set("slump", 0.0)
	body.set("hurt_bend", 0.0)
	if body not in _parked: _parked.append(body)

func _exit_tree() -> void:
	# Corpos estacionados estão fora da árvore: liberar aqui, senão vazam.
	for body in _bodies:
		if is_instance_valid(body) and not body.is_inside_tree(): body.free()
	_bodies.clear()
	_parked.clear()
	_assigned.clear()

## Roubo/entrada: o corpo do pool sai do banco e o Actor do roubo nasce com a mesma identidade
## (mesma pessoa). Devolve a identidade, ou -1 sem motorista visível.
static func take_driver(owner_world: Node, car: Node) -> int:
	var pool = of(owner_world)
	if pool == null or not is_instance_valid(car): return -1
	return pool._take(car)

func _take(car: Node) -> int:
	var id := car.get_instance_id()
	if not _assigned.has(id): return -1
	var body: Node3D = _assigned[id].body
	var identity := int(body.get_meta("traffic_driver_identity", -1)) if is_instance_valid(body) else -1
	_release(id)
	return identity

## Chamado por Gameplay._damage_bullet para cada tiro que acerta um veículo.
static func bullet_hit(owner_world: Node, car: Node, shot_from: Vector3, shot_to: Vector3, source: Node) -> void:
	var pool = of(owner_world)
	if pool == null or not is_instance_valid(car) or not shot_from.is_finite() or not shot_to.is_finite(): return
	pool._bullet(car, shot_from, shot_to, source)

func _bullet(car: Node, shot_from: Vector3, shot_to: Vector3, source: Node) -> void:
	var id := car.get_instance_id()
	if not _assigned.has(id): return
	var body: Node3D = _assigned[id].body
	if not is_instance_valid(body) or not body.is_inside_tree(): return
	var chest: Vector3 = body.global_position + (car as Node3D).global_basis.y * (.45 + .35 * body.scale.y)
	var closest := Geometry3D.get_closest_point_to_segment(chest, shot_from, shot_to)
	if closest.distance_to(chest) > HIT_RADIUS: return
	var state := str(car.get_meta(STATE_META, ""))
	var roll := _rng.randf()
	var slow := absf(float(car.get("speed"))) < FLEE_SPEED
	if state == "hurt" or roll < .35:
		_kill(car as Node3D, body)
	elif slow and roll < .75:
		_flee(car as Node3D, source)
	else:
		car.set_meta(STATE_META, "hurt")
		body.set("hurt_bend", .45)
		body.call("repose")
	if body.has_method("take_hit"): body.take_hit((shot_to - shot_from).normalized(), .8)

func _kill(car: Node3D, body: Node3D) -> void:
	car.set_meta(STATE_META, "dead")
	body.set("slump", 1.0)
	body.set("hurt_bend", 0.0)
	body.call("repose")
	# Sem motorista o carro para: fora do trânsito e sem pedal, Vehicle freia sozinho.
	car.set("traffic", false)
	car.set("throttle_input", 0.0)
	car.set("brake_input", true)

## Carro com motorista morto que o jogador tomou: o corpo cai na rua pela porta, como no roubo.
func _drop_corpse(car: Node3D, body: Node3D) -> void:
	var identity := int(body.get_meta("traffic_driver_identity", 0)) if is_instance_valid(body) else 0
	var actor := _materialize(car, identity)
	if actor == null: return
	if actor.has_method("receive_damage"): actor.receive_damage(9999.0, null)

func _flee(car: Node3D, source: Node) -> void:
	var id := car.get_instance_id()
	var body: Node3D = _assigned[id].body
	var identity := int(body.get_meta("traffic_driver_identity", 0))
	car.set_meta(STATE_META, "gone")
	car.set("traffic", false)
	car.set("throttle_input", 0.0)
	car.set("brake_input", true)
	_release(id)
	var actor := _materialize(car, identity)
	if actor == null: return
	var reactions: Variant = world.production.get("civilian_reactions") if is_instance_valid(world.get("production")) else null
	if source is Node3D and reactions != null and is_instance_valid(reactions) and reactions.has_method("report_assault"):
		reactions.report_assault(actor, source)

## Civil de verdade (Actor) ao lado da porta do motorista, mesmo jeito do roubo (Driving).
func _materialize(car: Node3D, identity: int) -> CharacterBody3D:
	var side := CARJACKING.driver_side(car)
	var landing: Vector3 = CARJACKING.landing_point(world, car, side)
	if not landing.is_finite(): landing = car.global_position - car.global_basis.x * (float(car.get("half_width")) + .9)
	var civilian = preload("res://scripts/Actor.gd").new()
	civilian.identity = identity
	civilian.speed = _rng.randf_range(1.2, 1.6)
	civilian.position = landing
	civilian.set_meta("region_id", car.get_meta("region_id", ""))
	world.add_child(civilian)
	if world.get("people") != null: world.people.append(civilian)
	return civilian
