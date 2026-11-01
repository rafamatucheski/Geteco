extends Node3D
## Física de rua da V2: atropelamento, postes e mobília derrubáveis, batida entre
## carros, sangue no chão e rastro. Porte nativo 3D dos sistemas da V1
## (VehiclePersonImpact, StreetLamp/fragile_road_post, GroundBlood, BodyWound,
## BloodTransferSystem) com as melhorias descritas em cada arquivo.
##
## Ganchos: Vehicle.gd chama vehicle_pre_move/vehicle_post_move em volta do
## move_and_slide; ProductionWorld cria este nó. O sangue de tiro/faca/explosão
## não precisa de gancho em Gameplay: o diretor observa a vida dos corpos
## (civil, polícia, Cobra, socorrista) e reage à queda.

const FLIGHT := preload("res://gameplay/street_physics/BodyFlight3D.gd")
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const BLOOD := preload("res://gameplay/street_physics/GroundBlood3D.gd")
const TRACKS := preload("res://gameplay/street_physics/BloodTracks3D.gd")
const CRUSH := preload("res://gameplay/street_physics/HeavyVehicleCrush.gd")
const CONTACT_AUDIO := preload("res://audio/VehicleCrashAudio.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const DEBRIS_GROUND := preload("res://gameplay/street_physics/DebrisGroundProjection.gd")
const SQUISH := preload("res://gameplay/street_physics/RunOverSquish.gd")
## Blocos separados em 01/11 (docs/plano-divisao-arquivos-grandes-20261101.md, Onda 2); o estado
## continua todo aqui e cada função antiga é delegação de uma linha.
const PERSON_IMPACT := preload("res://gameplay/street_physics/StreetPersonImpact.gd")
const VEHICLE_CRASH := preload("res://gameplay/street_physics/StreetVehicleCrash.gd")
const DEBRIS_FX := preload("res://gameplay/street_physics/StreetDebrisFx.gd")

# Even a bumper-start acceleration displaces people; lethal speed stays at 200 px/s.
const PERSON_MIN_SPEED := 0.05
const LETHAL_SPEED := 200.0 / 16.0
# Batida entre carros: velocidade de aproximação mínima para empurrar/rodar.
const CRASH_MIN_CLOSING := 3.0
const CRASH_DAMAGE_PER_SPEED := 0.5
const CRASH_DAMAGE_MAX_RATIO := 0.12
const CRASH_STUN := 2.4
const SLIDE_FRICTION := 7.0
# BodyWoundTrail da V1: 6 s sangrando, gota a cada 1,15 s se andou 28 px.
const WOUND_SECONDS := 6.0
const WOUND_INTERVAL := 1.15
const WOUND_STEP := 28.0 / 16.0
const WATCH_INTERVAL := 0.2
# Carro por cima de corpo caído (playtest 29/10): abaixo de ~7 km/h o pneu só encosta e não
# espirra nada; quem manobra devagar ao lado do corpo não deve ouvir esmagamento.
const RUNOVER_MIN_SPEED := 2.0
# Folga além da carroceria: o corpo deitado se estende ~0,65 m do ponto do ator (queda da V2).
const RUNOVER_BODY_REACH := 0.6
# Um esmagamento por passada: o contato precisa sumir por este tempo para contar outra entrada,
# e o mesmo corpo não repete em menos de RUNOVER_COOLDOWN_MS (dois carros em fila, ré e frente).
const RUNOVER_REENTRY_MS := 250
const RUNOVER_COOLDOWN_MS := 900
# Encostão (playtest 30/10): abaixo de ~14 km/h o carro empurra em vez de atropelar. Até então
# qualquer contato acima de PERSON_MIN_SPEED lançava o ragdoll com sangue, e manobrar ao lado de
# alguém matava. A pessoa é levada pelo para-choque e dá passos para o lado; presa na frente por
# tempo demais (ou contra uma parede) ela cai e o carro passa por cima.
const NUDGE_MAX_SPEED := 4.0
const NUDGE_SIDESTEP_SPEED := 1.8
# Pressão por segundo de contato: ~1,2 s a 1 m/s, ~0,6 s perto do teto; presa numa parede, ~0,2 s.
const NUDGE_PRESSURE_BASE := 0.6
const NUDGE_PRESSURE_BLOCKED := 4.0
const NUDGE_FORGET_MS := 400
const NUDGE_REACT_MS := 550
# Resistência do corpo no para-choque, por segundo de empurrão.
const NUDGE_DRAG := 1.2
# Dano da roda passando por cima de quem está caído vivo (fraco a 2 m/s, forte a LETHAL_SPEED).
const RUNOVER_DAMAGE_MIN := 20.0
const RUNOVER_DAMAGE_MAX := 60.0

static var instance: Node3D

var controller
var blood: Node3D
var tracks: Node3D
var _watch := {}
var _wounds := {}
var _watch_clock := 0.0
var _exceptions: Array[Dictionary] = []
var _crash_pairs := {}
var _audio: Array[AudioStreamPlayer3D] = []
var _audio_next := 0
var _streams := {}
var _geysers: Array[Dictionary] = []
var _litter: Array[Node3D] = []
var _player_wound_pending := false
var _player_wound_lethal := false
var _people_cache: Array = []
## GETECO_RUNOVER_GORE=0 desliga sangue/som/rastro de passar por cima de corpo (A/B e comparação).
var runover_gore := OS.get_environment("GETECO_RUNOVER_GORE").strip_edges() != "0"
## Corpos caídos (mortos ou derrubados, já fora do voo), renovados junto com o cache de pessoas a
## cada WATCH_INTERVAL: o teste por carro só percorre esta lista, normalmente vazia.
var _downed: Array = []
var _runover_seen := {}
var _runover_last := {}
## GETECO_VEHICLE_NUDGE=0 volta ao atropelamento em qualquer velocidade (A/B e comparação).
var vehicle_nudge := OS.get_environment("GETECO_VEHICLE_NUDGE").strip_edges() != "0"
## Encostões em curso por pessoa: {pressure, last, side, react}.
var _nudges := {}
## Contadores para testes e diagnóstico.
var runover_hits := 0
var runover_sounds := 0
var nudges := 0
var nudge_falls := 0
## Criados com o nó, e não em _ready: 9 subclasses de teste sobrescrevem _ready sem chamar super.
var _person_impact: PERSON_IMPACT = PERSON_IMPACT.new(self)
var _vehicle_crash: VEHICLE_CRASH = VEHICLE_CRASH.new(self)
var _debris_fx: DEBRIS_FX = DEBRIS_FX.new(self)


func _ready() -> void:
	name = "StreetPhysics"
	instance = self
	blood = BLOOD.new()
	add_child(blood)
	controller.world.gameplay.player_wounded.connect(_on_player_wounded)
	tracks = TRACKS.new()
	tracks.director = self
	add_child(tracks)
	_setup_audio()
	if runover_gore: SQUISH.prewarm()
	# Sacos soltos da pilha e sons sintetizados de saco/lata/plástico: prontos antes do 1º choque.
	FRAGILE.prewarm()


func _setup_audio() -> void:
	var bus := StringName(preload("res://gameplay/CombatAudio.gd").SFX_BUS_NAME)
	for index in 8:
		var player := AudioStreamPlayer3D.new()
		player.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
		player.max_distance = 45.0
		player.unit_size = 6.0
		add_child(player)
		_audio.append(player)
	for family in ["panic", "hurt"]:
		var list := []
		for index in 3:
			var path := "res://assets/gameplay/audio/%s_%d.wav" % [family, index]
			if ResourceLoader.exists(path): list.append(load(path))
		_streams[family] = list


func _exit_tree() -> void:
	if instance == self: instance = null


static func vehicle_pre_move(vehicle: CharacterBody3D, delta: float) -> void:
	if is_instance_valid(instance): instance._pre_move(vehicle, delta)


static func vehicle_post_move(vehicle: CharacterBody3D, incoming: Vector3, delta: float) -> void:
	if is_instance_valid(instance): instance._post_move(vehicle, incoming, delta)


static func vehicle_repaired(vehicle: CharacterBody3D) -> void:
	CRUSH.restore(vehicle)


# ---------------------------------------------------------------------------
# Antes do move_and_slide: pessoas e objetos quebráveis no caminho.

func _pre_move(vehicle: CharacterBody3D, delta: float) -> void:
	var planar := Vector3(vehicle.velocity.x, 0, vehicle.velocity.z)
	var speed := planar.length()
	if speed < PERSON_MIN_SPEED: return
	var motion := planar * delta
	var stage := STALL_WORK.begin()
	_hit_people(vehicle, planar, motion)
	STALL_WORK.finish_slow("street.pre.people", stage, 5000, vehicle)
	if runover_gore and not _downed.is_empty() and speed >= RUNOVER_MIN_SPEED:
		stage = STALL_WORK.begin()
		run_over_downed(vehicle, planar)
		STALL_WORK.finish_slow("street.pre.runover", stage, 5000, vehicle)
	stage = STALL_WORK.begin()
	_hit_props(vehicle, planar, motion)
	STALL_WORK.finish_slow("street.pre.props", stage, 5000, vehicle)
	stage = STALL_WORK.begin()
	var crushed := CRUSH.prepare(vehicle, planar, delta)
	STALL_WORK.finish_slow("street.pre.crush", stage, 5000, vehicle)
	if is_instance_valid(crushed):
		stage = STALL_WORK.begin()
		CONTACT_AUDIO.play_contact(vehicle, crushed, crushed.global_position, speed, "heavy")
		STALL_WORK.finish_slow("street.pre.crush_audio", stage, 5000, vehicle)


## Carro contra pessoa (varredura da forma, atropelamento, encostão): corpo em StreetPersonImpact.gd
## (delegação de uma linha; mesmo nome e padrões; testes chamam _hit_people direto).
func _hit_people(vehicle: CharacterBody3D, planar: Vector3, motion: Vector3) -> void: _person_impact._hit_people(vehicle, planar, motion)
func _nudge(vehicle: CharacterBody3D, person: CharacterBody3D, planar: Vector3, motion: Vector3, closing: float) -> bool: return _person_impact._nudge(vehicle, person, planar, motion, closing)


func _hit_props(vehicle: CharacterBody3D, planar: Vector3, motion: Vector3) -> void:
	# A velocidade de aproximação não pode passar da velocidade planar. Abaixo do limite de impacto existente,
	# FragileProps.hit não tem efeito; pula a coleta de candidatos para carros se arrastando.
	# Postes que não cedem seguram o carro até parado; abaixo disso nada mais reage.
	if planar.length() < 0.05: return
	var start := vehicle.global_transform
	var inverse := start.affine_inverse()
	var local_motion := inverse.basis * motion
	var half_width := float(vehicle.get("half_width")) if vehicle.get("half_width") != null else 1.0
	var half_length := float(vehicle.get("half_length")) if vehicle.get("half_length") != null else 2.3
	var query_began := STALL_WORK.begin()
	var candidates := FRAGILE.query(start.origin + motion * 0.5, motion.length() * 0.5 + half_length + 2.0)
	STALL_WORK.finish_slow("street.pre.props.query", query_began, 5000, vehicle)
	if candidates.is_empty(): return
	# O índice espacial devolve células inteiras de 8 m. Só consulta o movimento nativo
	# quando uma decoração pode cruzar a varredura; mantém a checagem recortada por parede
	# abaixo como autoridade, incluindo a extensão de margem segura existente.
	var possible_contact := false
	var full_motion := inverse.basis * (motion + motion.normalized() * vehicle.safe_margin)
	for item in candidates:
		var local := inverse * (item.point as Vector3)
		if absf(local.y) > 2.0: continue
		var radius: float = float(item.get("radius",FRAGILE.spec(item).radius))
		if swept_prop_contact(local, full_motion, half_width + radius, half_length + radius):
			possible_contact = true
			break
	if not possible_contact: return
	# Uma parede ou barreira de campanha bloqueia a varredura antes das decorações atrás dela.
	var obstruction := KinematicCollision3D.new()
	var cast_began := STALL_WORK.begin()
	var obstructed := vehicle.test_move(start, motion, obstruction)
	STALL_WORK.finish_slow("street.pre.props.cast", cast_began, 5000, vehicle)
	if obstructed:
		if absf(obstruction.get_normal().y) < 0.55:
			local_motion = inverse.basis * (obstruction.get_travel() + motion.normalized() * vehicle.safe_margin)
	for item in candidates:
		var local := inverse * (item.point as Vector3)
		var radius: float = float(item.get("radius",FRAGILE.spec(item).radius))
		if not swept_prop_contact(local, local_motion, half_width + radius, half_length + radius): continue
		# Decorações em outro nível não podem quebrar debaixo de uma ponte.
		if absf(local.y) > 2.0: continue
		var toward: Vector3 = item.point - vehicle.global_position
		toward.y = 0
		var closing := planar.dot(toward.normalized()) if toward.length_squared() > 0.0001 else planar.length()
		if closing <= 0.0: continue
		if closing < FRAGILE.WOBBLE_SPEED:
			_hold_at_post(vehicle, item, toward)
			continue
		var hit_began := STALL_WORK.begin()
		var yielded := FRAGILE.hit(item, closing, planar, self, vehicle)
		STALL_WORK.finish_slow("street.pre.props.hit", hit_began, 5000, vehicle)
		if not yielded:
			_hold_at_post(vehicle, item, toward)
		if yielded:
			var spec: Dictionary = FRAGILE.spec(item)
			# O objeto toca o material dele (poste: chapa; saco: plástico); o que é pesado também
			# amassa o carro, com a fonte no próprio carro para não disputar a fila do objeto.
			if float(spec.damage) >= 4.0:
				CONTACT_AUDIO.play_contact(vehicle, null, item.point + Vector3.UP * 0.6, closing * 0.6, "bumper", "propcar|%d" % vehicle.get_instance_id())
			var response := CRUSH.light_impact_response(vehicle, planar.length())
			_scale_vehicle_speed(vehicle, 1.0 - float(spec.drag) * response)
			if response > 0.01 and float(spec.damage) > 0 and vehicle.has_method("receive_damage"):
				vehicle.receive_damage(float(spec.damage) * clampf(closing / 8.0, 0.5, 1.5) * response)
			var effects = vehicle.get("effects")
			if is_instance_valid(effects) and is_instance_valid(effects.get("impact_effects")):
				effects.impact_effects.present_impact(item.point + Vector3.UP * 0.6, -toward.normalized(), closing, hash(item.point))
			if spec.family == "post" and response > 0.01: _shake_if_player(vehicle, 0.12 * response)


## Poste em pé que não cedeu é obstáculo: a maioria não tem colisor nativo (a mobília do
## CityLook não atrapalha pedestre), então devagar o carro atravessava o poste.
func _hold_at_post(vehicle: CharacterBody3D, item: Dictionary, toward: Vector3) -> void:
	if item.get("state", "") != "standing" or FRAGILE.spec(item).family != "post": return
	if toward.length_squared() < 0.0001: return
	var normal := toward.normalized()
	var into := vehicle.velocity.x * normal.x + vehicle.velocity.z * normal.z
	if into <= 0.0: return
	var keep := Vector3(vehicle.velocity.x, 0, vehicle.velocity.z) - normal * into
	var factor := keep.length() / maxf(Vector2(vehicle.velocity.x, vehicle.velocity.z).length(), 0.001)
	vehicle.velocity.x = keep.x
	vehicle.velocity.z = keep.z
	var horizontal = vehicle.get("horizontal_velocity")
	if horizontal is Vector3: vehicle.set("horizontal_velocity", Vector3(keep.x, horizontal.y, keep.z))
	var current: Variant = vehicle.get("speed")
	if current is float: vehicle.set("speed", current * factor)


static func swept_prop_contact(point: Vector3, motion: Vector3, width: float, length: float) -> bool:
	# Segmento contra a área do carro expandida pelo prop, incluindo a pose inicial.
	var enter := 0.0
	var leave := 1.0
	for axis in [0, 2]:
		var extent := width if axis == 0 else length
		if absf(motion[axis]) < 0.000001:
			if absf(point[axis]) > extent: return false
			continue
		var a: float = (point[axis] - extent) / motion[axis]
		var b: float = (point[axis] + extent) / motion[axis]
		enter = maxf(enter, minf(a, b))
		leave = minf(leave, maxf(a, b))
		if enter > leave: return false
	return true


func _scale_vehicle_speed(vehicle: CharacterBody3D, factor: float) -> void:
	vehicle.set("speed", float(vehicle.get("speed")) * factor)
	vehicle.velocity.x *= factor
	vehicle.velocity.z *= factor
	var horizontal = vehicle.get("horizontal_velocity")
	if horizontal is Vector3: vehicle.set("horizontal_velocity", horizontal * factor)


func _except(vehicle: CharacterBody3D, body: PhysicsBody3D) -> void:
	vehicle.add_collision_exception_with(body)
	_exceptions.append({"vehicle": weakref(vehicle), "body": weakref(body), "until": Time.get_ticks_msec() + 2500})


static func _is_person(body: Object) -> bool:
	if not body is CharacterBody3D or body.is_in_group("drivable") or body.get("horizontal_velocity") != null: return false
	if body.is_in_group("skate_boards"): return body.get("riding") == true
	return (body.has_method("receive_damage") and body.get("health") != null and body.get("dead") != null) or ((body.collision_layer & 2) != 0 and FLIGHT.actor_visual(body) != null)


# ---------------------------------------------------------------------------
# Depois do move_and_slide: batida carro x carro e deslize de quem foi atingido.

## Batida contra parede e carro x carro, deslize de quem foi atingido: corpo em StreetVehicleCrash.gd
## (delegação de uma linha; mesmo nome e padrões; as estáticas continuam estáticas).
func _post_move(vehicle: CharacterBody3D, incoming: Vector3, delta: float) -> void: _vehicle_crash._post_move(vehicle, incoming, delta)

## Impacto quase inelástico: a carroceria absorve energia. Os dois carros recebem
## a velocidade resultante no mesmo estado usado pela direção e pelas colisões;
## um deslocamento extra por fora fazia o atingido recuar como uma mola.
const CRASH_RESTITUTION := 0.03

func _crash(vehicle: CharacterBody3D, other: CharacterBody3D, normal: Vector3, closing: float, point: Vector3, incoming: Vector3) -> void: _vehicle_crash._crash(vehicle, other, normal, closing, point, incoming)
func _stall_crash(vehicle: CharacterBody3D, other: CharacterBody3D, normal: Vector3, closing: float, point: Vector3, incoming: Vector3) -> void: _vehicle_crash._stall_crash(vehicle, other, normal, closing, point, incoming)
static func _set_impact_velocity(vehicle: CharacterBody3D, planar: Vector3) -> void: VEHICLE_CRASH._set_impact_velocity(vehicle, planar)
static func _vehicle_mass(vehicle: Node) -> float: return VEHICLE_CRASH._vehicle_mass(vehicle)
func _add_slide(vehicle: CharacterBody3D, push: Vector3, spin: float) -> void: _vehicle_crash._add_slide(vehicle, push, spin)
func _update_slide(vehicle: CharacterBody3D, delta: float) -> void: _vehicle_crash._update_slide(vehicle, delta)


# ---------------------------------------------------------------------------
# Pouso do atropelado: dano, queda, poça, socorro.

func on_body_landed(actor: CharacterBody3D, lethal: bool, source: Node, impact_speed: float, heading: Vector3) -> void:
	# Caiu do encostão: ralado, não ferido; sem poça nem gotejamento.
	var soft := actor.has_meta("street_soft_fall")
	if soft: actor.remove_meta("street_soft_fall")
	if PROTECTION.is_protected(actor): return
	# Authored contacts without a combat contract still fall and recover physically.
	if not actor.has_method("receive_damage"): return
	actor.set_meta("street_vehicle_hit", true)
	var health: float = float(actor.get("health"))
	if lethal:
		actor.receive_damage(health + 500.0, source)
		# receive_damage deixa layer 0 e dispara a queda da V2.
	else:
		# Sobrevive caído com pouca vida (V1 deixava 1 de vida esperando a ambulância).
		var damage := maxf(1.0, impact_speed * 3.0) if impact_speed < 3.75 else maxf(1.0, health - clampf(22.0 - impact_speed, 6.0, 18.0))
		if soft: damage = clampf(impact_speed * 2.0, 1.0, 8.0)
		actor.receive_damage(damage, source)
		if actor.get("dead") != true:
			var visual: Node3D = actor.get("visual")
			if is_instance_valid(visual): preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(actor, visual, heading)
			actor.collision_layer = 0
			actor.collision_mask = 0
			actor.set_physics_process(false)
	var dead: bool = actor.get("dead") == true
	if actor.has_meta("vehicle_blood_side"):
		if dead and is_instance_valid(source) and source.has_method("restore_blood_stains"):
			source.restore_blood_stains(int(source.get_meta("blood_stains", 0)) | int(actor.get_meta("vehicle_blood_side")))
		actor.remove_meta("vehicle_blood_side")
	# Centro no tronco: a queda da V2 desloca o corpo ~0,65 m para a frente.
	if not soft or dead: blood.spawn_pool(actor.global_position + heading.normalized() * 0.6, dead, actor if _counts_as_corpse(actor) else null, heading)
	_watch[actor.get_instance_id()] = {"health": float(actor.get("health")), "dead": dead}
	# BodyFlight emite o Foley de chão no contato real, antes da restituição.


func play_prop_hit(point: Vector3, family: String, speed: float) -> void:
	CONTACT_AUDIO.play_contact(self, null, point, speed, family, "prop|" + str(Vector3i((point * 2.0).round())))


func play(family: String, point: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var list: Array = _streams.get(family, [])
	if list.is_empty(): return
	_play_stream(list.pick_random(), point, volume_db, pitch)


func _play_stream(stream: AudioStream, point: Vector3, volume_db: float, pitch: float) -> void:
	if _audio.is_empty() or stream == null: return
	var player := _audio[_audio_next]
	_audio_next = (_audio_next + 1) % _audio.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.95, 1.05)
	player.global_position = point
	player.play()


func _shake_if_player(vehicle: Node, strength: float) -> void:
	if not is_instance_valid(vehicle) or controller == null: return
	var driving = controller.world.get("driving")
	if driving == null or driving.get("car") != vehicle or not driving.get("occupied"): return
	var camera: Camera3D = controller.world.get("camera")
	if not is_instance_valid(camera): return
	# Câmera ortográfica: tremer o `h_offset/v_offset` não briga com o CameraRig,
	# que só escreve posição/tamanho.
	var tween := camera.create_tween()
	for step in 6:
		var amount := strength * (1.0 - step / 6.0)
		tween.tween_property(camera, "h_offset", randf_range(-1, 1) * amount, 0.04)
		tween.parallel().tween_property(camera, "v_offset", randf_range(-1, 1) * amount, 0.04)
	tween.tween_property(camera, "h_offset", 0.0, 0.05)
	tween.parallel().tween_property(camera, "v_offset", 0.0, 0.05)


# ---------------------------------------------------------------------------
# Carro passando por cima de corpo caído. Antes (até 29/10) o corpo já estava fora da colisão
# (layer 0) e _hit_people só criava a exceção: nada de sangue, som nem rastro.

func refresh_downed(people_list: Array) -> void:
	_downed.clear()
	var now := Time.get_ticks_msec()
	for key in _runover_seen.keys():
		if now - int(_runover_seen[key]) > 2000: _runover_seen.erase(key)
	for key in _runover_last.keys():
		if now - int(_runover_last[key]) > 5000: _runover_last.erase(key)
	if not runover_gore: return
	var player = controller.world.get("player") if controller != null and controller.get("world") != null else null
	for person in people_list:
		if not is_instance_valid(person) or not person is Node3D or person == player: continue
		if person.has_meta("street_flying") or person.get_meta("interior_actor", false) or person.get_meta("is_player_body", false): continue
		# Corpo escondido (vigia de NaN, desvanecimento) não espirra sangue invisível.
		if person.has_meta("non_finite_hidden") or not person.is_visible_in_tree(): continue
		if person.get("dead") == true or person.has_meta("street_down"): _downed.append(person)


## Testa a planta do carro (retângulo + folga do corpo deitado) contra os corpos caídos da lista;
## cada entrada nova dispara sangue, som e rastro. Devolve quantos corpos esmagou neste passo.
func run_over_downed(vehicle: CharacterBody3D, planar: Vector3) -> int:
	if not runover_gore or _downed.is_empty() or not is_instance_valid(vehicle): return 0
	if not planar.is_finite() or planar.length() < RUNOVER_MIN_SPEED: return 0
	var origin := vehicle.global_position
	if not origin.is_finite(): return 0
	var half_width := float(vehicle.get("half_width")) if vehicle.get("half_width") != null else 1.0
	var half_length := float(vehicle.get("half_length")) if vehicle.get("half_length") != null else 2.3
	var reach := half_length + half_width + RUNOVER_BODY_REACH
	var inverse := Transform3D(vehicle.global_basis.orthonormalized(), origin).affine_inverse()
	var now := Time.get_ticks_msec()
	var hits := 0
	for body in _downed:
		if not is_instance_valid(body): continue
		var point: Vector3 = body.global_position
		if not point.is_finite() or point.distance_squared_to(origin) > reach * reach: continue
		var local := inverse * point
		if absf(local.y) > 1.6 or absf(local.x) > half_width + RUNOVER_BODY_REACH or absf(local.z) > half_length + RUNOVER_BODY_REACH: continue
		var key := "%d|%d" % [body.get_instance_id(), vehicle.get_instance_id()]
		var fresh := now - int(_runover_seen.get(key, -100000)) > RUNOVER_REENTRY_MS
		_runover_seen[key] = now
		if not fresh: continue
		var id: int = body.get_instance_id()
		if now - int(_runover_last.get(id, -100000)) < RUNOVER_COOLDOWN_MS: continue
		_runover_last[id] = now
		_run_over_effects(vehicle, body, point, planar)
		hits += 1
	return hits


func _run_over_effects(vehicle: CharacterBody3D, body: Node3D, point: Vector3, planar: Vector3) -> void:
	runover_hits += 1
	var strength := clampf(planar.length() / LETHAL_SPEED, 0.2, 1.0)
	if is_instance_valid(blood) and blood.has_method("spawn_splatter"):
		# Respingo esticado no rumo do carro e poça curta sob o tronco, sem registrar outro
		# cadáver: a poça de morte já existe e o orçamento de corpos não muda.
		blood.spawn_splatter(point, planar, strength * 0.75)
		blood.spawn_pool(point, false)
	var gameplay = controller.world.get("gameplay") if controller != null and controller.get("world") != null else null
	if gameplay != null and is_instance_valid(gameplay.get("effects")):
		gameplay.effects.blood(point + Vector3.UP * 0.25, planar.normalized(), 12.0 + 10.0 * strength)
	if is_instance_valid(tracks): tracks.soak(vehicle, TRACKS.TIRE_DISTANCE)
	runover_sounds += 1
	_play_stream(SQUISH.take(), point + Vector3.UP * 0.2, lerpf(-7.0, -2.0, strength), randf_range(0.92, 1.06))
	# Solavanco leve só na câmera do motorista; a velocidade do carro continua com Vehicle.gd.
	_shake_if_player(vehicle, 0.05 + 0.06 * strength)
	body.set_meta("street_runover_count", int(body.get_meta("street_runover_count", 0)) + 1)
	# Caído vivo (encostão que derrubou, atropelamento que não matou): a roda por cima machuca de verdade.
	if body.get("dead") != true and body.has_method("receive_damage") and not PROTECTION.is_protected(body):
		body.set_meta("street_vehicle_hit", true)
		body.receive_damage(lerpf(RUNOVER_DAMAGE_MIN, RUNOVER_DAMAGE_MAX, strength), vehicle)


# ---------------------------------------------------------------------------
# Observação de vida: sangue de tiro, faca, explosão e gotejamento de ferido.

func _physics_process(delta: float) -> void:
	_expire_exceptions()
	_update_geysers(delta)
	_update_wounds(delta)
	_watch_clock += delta
	if _watch_clock < WATCH_INTERVAL: return
	_watch_clock = 0.0
	var now := Time.get_ticks_msec()
	for key in _crash_pairs.keys():
		if now - int(_crash_pairs[key]) > 2500: _crash_pairs.erase(key)
	_watch_people()


func _expire_exceptions() -> void:
	if _exceptions.is_empty(): return
	var now := Time.get_ticks_msec()
	for index in range(_exceptions.size() - 1, -1, -1):
		var entry: Dictionary = _exceptions[index]
		if now < int(entry.until): continue
		var vehicle = entry.vehicle.get_ref()
		var body = entry.body.get_ref()
		if is_instance_valid(vehicle) and is_instance_valid(body):
			vehicle.remove_collision_exception_with(body)
		_exceptions.remove_at(index)


## Cache renovado a cada WATCH_INTERVAL: o rastro consulta a 30 Hz e não deve
## varrer os filhos do mundo em todo passo.
func people() -> Array:
	# Entre duas renovações o rabecão/orçamento pode liberar um corpo.
	if _people_cache.any(func(person): return not is_instance_valid(person)):
		_people_cache = _people_cache.filter(func(person): return is_instance_valid(person))
	return _people_cache


func _collect_people() -> Array:
	var result := []
	if controller == null: return result
	var world: Node = controller.get("world")
	if not is_instance_valid(world): return result
	for child in world.get_children():
		if _is_person(child): result.append(child)
	for child in get_tree().get_nodes_in_group("v2_damageable"):
		if _is_person(child) and not result.has(child): result.append(child)
	return result


func _watch_people() -> void:
	var seen := {}
	_people_cache = _collect_people()
	refresh_downed(_people_cache)
	for person in _people_cache:
		if person.get("health") == null or person.get("dead") == null: continue
		var id: int = person.get_instance_id()
		seen[id] = true
		var health := float(person.get("health"))
		var dead: bool = person.get("dead") == true
		var previous: Dictionary = _watch.get(id, {})
		_watch[id] = {"health": health, "dead": dead}
		if previous.is_empty() or health >= float(previous.health) - 0.01: continue
		if person.get_meta("interior_actor", false): continue
		if person.has_meta("street_flying"): continue
		if dead and not bool(previous.dead):
			if not person.get_meta("street_vehicle_hit", false):
				blood.spawn_pool(person.global_position, true, person if _counts_as_corpse(person) else null)
		elif not dead:
			blood.spawn_pool(person.global_position, false)
			_wound(person)
	for id in _watch.keys():
		if not seen.has(id): _watch.erase(id)
	_watch_player()


## Só ferimentos físicos iniciam sangue; frio não cria nem renova o rastro.
func _on_player_wounded(lethal: bool) -> void:
	_player_wound_pending = true
	_player_wound_lethal = _player_wound_lethal or lethal

func _watch_player() -> void:
	# Preserva o orçamento existente de 0.2 s mesmo para vários chumbos num tiro só.
	if not _player_wound_pending: return
	var lethal := _player_wound_lethal
	_player_wound_pending = false
	_player_wound_lethal = false
	var player = controller.world.get("player")
	if not is_instance_valid(player): return
	if not lethal:
		blood.spawn_pool(player.global_position, false)
		_wound(player)
	else:
		blood.spawn_pool(player.global_position, true)


func _counts_as_corpse(person: Node) -> bool:
	# Orçamento de 5 corpos só para civis: polícia e socorristas têm remoção própria.
	return String(person.get_meta("gameplay_role", "")) == "civilian"


func _wound(person: Node3D) -> void:
	var id := person.get_instance_id()
	var wound: Dictionary = _wounds.get(id, {"actor": weakref(person), "clock": WOUND_INTERVAL, "last": person.global_position, "severity": 0})
	wound.remaining = WOUND_SECONDS
	wound.severity = mini(4, int(wound.severity) + 1)
	_wounds[id] = wound


func _update_wounds(delta: float) -> void:
	for id in _wounds.keys():
		var wound: Dictionary = _wounds[id]
		var person = wound.actor.get_ref()
		if not is_instance_valid(person) or person.get("dead") == true or person.has_meta("street_down"):
			_wounds.erase(id)
			continue
		wound.remaining = float(wound.remaining) - delta
		wound.clock = float(wound.clock) - delta
		if wound.clock <= 0.0:
			wound.clock = WOUND_INTERVAL
			if person.global_position.distance_to(wound.last) >= WOUND_STEP:
				blood.spawn_drip(person.global_position, clampf(float(wound.remaining) / WOUND_SECONDS, 0.0, 1.0))
				wound.last = person.global_position
		if wound.remaining <= 0.0: _wounds.erase(id)


# ---------------------------------------------------------------------------
# Detritos: vidro, lixo espalhado, gêiser de hidrante.

## Vidro, lixo espalhado e gêiser: corpo em StreetDebrisFx.gd (delegação de uma linha; mesmo nome e
## padrões). Os materiais estáticos ficam aqui: pré-aquecimentos e efeitos os chamam por este script.
func spawn_glass(point: Vector3, direction: Vector3) -> void: _debris_fx.spawn_glass(point, direction)
func _stall_spawn_glass(point: Vector3, direction: Vector3) -> void: _debris_fx._stall_spawn_glass(point, direction)

## Materiais dos detritos, com as mesmas flags usadas em jogo: VehicleMaterialVariantPrewarm os
## desenha sob a cortina. Sem isso a primeira batida forte compilava o shader no quadro do choque
## (street.scatter.material 18 ms e street.glass 19 ms no release de 13/10).
## O vidro em lascas não anima o material: um só, vivo a sessão inteira (antes, um por estouro).
static var _glass_shard_material: StandardMaterial3D
static var _glass_shard_mesh: BoxMesh

static func glass_shard_material() -> StandardMaterial3D:
	if _glass_shard_material == null:
		_glass_shard_material = StandardMaterial3D.new()
		_glass_shard_material.albedo_color = Color(0.78, 0.9, 0.95, 0.85)
		_glass_shard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_shard_material.metallic_specular = 1.0
		_glass_shard_material.roughness = 0.05
	return _glass_shard_material

static func glass_shard_mesh() -> BoxMesh:
	if _glass_shard_mesh == null:
		_glass_shard_mesh = BoxMesh.new()
		_glass_shard_mesh.size = Vector3(0.05, 0.01, 0.07)
	return _glass_shard_mesh

## Por pedaço: o alfa de cada mancha some no seu tempo.
static func debris_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic_specular = 1.0 if roughness < 0.2 else 0.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

## Por poça: o alfa seca com a idade.
static func puddle_material() -> StandardMaterial3D:
	var wet := StandardMaterial3D.new()
	wet.albedo_color = Color(0.08, 0.1, 0.12, 0.55)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.roughness = 0.03
	wet.metallic_specular = 1.0
	return wet

static func warm_materials() -> Array[Material]:
	return [glass_shard_material(), debris_material(Color.WHITE, .05), puddle_material()]


func spawn_litter(point: Vector3, direction: Vector3) -> void: _debris_fx.spawn_litter(point, direction)
func _scatter(point: Vector3, direction: Vector3, count: int, size: Vector2, color: Color, roughness: float, lifetime: float, settle_delay := 0.0) -> void: _debris_fx._scatter(point, direction, count, size, color, roughness, lifetime, settle_delay)
func _stall_scatter(point: Vector3, direction: Vector3, count: int, size: Vector2, color: Color, roughness: float, lifetime: float, settle_delay := 0.0) -> void: _debris_fx._stall_scatter(point, direction, count, size, color, roughness, lifetime, settle_delay)


## Alcance em que o gêiser do hidrante quebrado apaga fogo (StreetDebrisFx.spawn_geyser).
const GEYSER_DOUSE_RADIUS := 3.5

func spawn_geyser(point: Vector3) -> void: _debris_fx.spawn_geyser(point)
func _update_geysers(delta: float) -> void: _debris_fx._update_geysers(delta)
func _douse_near(point: Vector3, amount: float) -> void: _debris_fx._douse_near(point, amount)
