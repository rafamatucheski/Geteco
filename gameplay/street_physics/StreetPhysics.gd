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

# V1 VehiclePersonImpact: MIN_SPEED 60 px/s, letal a partir de 200 px/s.
const PERSON_MIN_SPEED := 60.0 / 16.0
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


func _ready() -> void:
	name = "StreetPhysics"
	instance = self
	blood = BLOOD.new()
	add_child(blood)
	controller.world.gameplay.player_wounded.connect(_on_player_wounded)
	tracks = TRACKS.new()
	tracks.director = self
	add_child(tracks)
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
	if speed < 0.4: return
	var motion := planar * delta
	_hit_people(vehicle, planar, motion)
	_hit_props(vehicle, planar, motion)
	var crushed := CRUSH.prepare(vehicle, planar, delta)
	if is_instance_valid(crushed):
		CONTACT_AUDIO.play_contact(vehicle, crushed, crushed.global_position, speed, "heavy")


## Varre a forma real do carro (V1 prepare_motion): pessoa atingida acima do
## limiar sai voando e o carro não para nela; pessoa já caída não vira parede.
func _hit_people(vehicle: CharacterBody3D, planar: Vector3, motion: Vector3) -> void:
	var player = controller.world.get("player") if controller != null else null
	# test_move é um shape cast; só vale a pena com alguém perto do carro.
	var reach := motion.length() + float(vehicle.get("half_length") if vehicle.get("half_length") != null else 2.3) + 1.5
	var anyone := false
	for person in _people_cache:
		if is_instance_valid(person) and person != player and person.global_position.distance_squared_to(vehicle.global_position) < reach * reach:
			anyone = true
			break
	if not anyone: return
	for attempt in 4:
		var contact := KinematicCollision3D.new()
		if not vehicle.test_move(vehicle.global_transform, motion, contact): return
		var person := contact.get_collider() as CharacterBody3D
		if not _is_person(person) or person == player or PROTECTION.is_protected(person): return
		if person.get("dead") == true or person.has_meta("street_down"):
			_except(vehicle, person)
			continue
		var toward := person.global_position - vehicle.global_position
		toward.y = 0
		var closing := planar.dot(toward.normalized()) if toward.length_squared() > 0.0001 else planar.length()
		var minimum := 1.8 if _vehicle_mass(vehicle) >= CRUSH.HEAVY_MASS else PERSON_MIN_SPEED
		if closing < minimum: return
		_except(vehicle, person)
		var lethal := planar.length() >= LETHAL_SPEED
		FLIGHT.launch(person, planar, lethal, self, vehicle)
		var response := CRUSH.light_impact_response(vehicle, planar.length())
		_scale_vehicle_speed(vehicle, 1.0 - 0.12 * response)
		var point := person.global_position + Vector3.UP * 0.9
		var gameplay = controller.world.get("gameplay") if controller != null else null
		if gameplay != null and is_instance_valid(gameplay.get("effects")):
			gameplay.effects.blood(point, planar.normalized(), 40.0 if lethal else 18.0)
		if is_instance_valid(blood): blood.spawn_splatter(person.global_position, planar, clampf(planar.length() / LETHAL_SPEED, 0.2, 1.0))
		if is_instance_valid(tracks): tracks.soak(vehicle, TRACKS.TIRE_DISTANCE)
		CONTACT_AUDIO.play_contact(vehicle, person, point, closing, "flesh")
		if not lethal: play("panic", point, -4.0)
		if response > 0.01: _shake_if_player(vehicle, (0.18 if lethal else 0.1) * response)


func _hit_props(vehicle: CharacterBody3D, planar: Vector3, motion: Vector3) -> void:
	var next := vehicle.global_transform.translated(motion)
	var half_width := float(vehicle.get("half_width")) if vehicle.get("half_width") != null else 1.0
	var half_length := float(vehicle.get("half_length")) if vehicle.get("half_length") != null else 2.3
	for item in FRAGILE.query(next.origin, half_length + 1.5):
		var local := next.affine_inverse() * (item.point as Vector3)
		var radius: float = FRAGILE.spec(item).radius
		if absf(local.x) > half_width + radius or absf(local.z) > half_length + radius: continue
		var toward: Vector3 = item.point - vehicle.global_position
		toward.y = 0
		var closing := planar.dot(toward.normalized()) if toward.length_squared() > 0.0001 else planar.length()
		if closing <= 0.0: continue
		if FRAGILE.hit(item, closing, planar, self):
			var spec: Dictionary = FRAGILE.spec(item)
			var response := CRUSH.light_impact_response(vehicle, planar.length())
			_scale_vehicle_speed(vehicle, 1.0 - float(spec.drag) * response)
			if response > 0.01 and float(spec.damage) > 0 and vehicle.has_method("receive_damage"):
				vehicle.receive_damage(float(spec.damage) * clampf(closing / 8.0, 0.5, 1.5) * response)
			var effects = vehicle.get("effects")
			if is_instance_valid(effects) and is_instance_valid(effects.get("impact_effects")):
				effects.impact_effects.present_impact(item.point + Vector3.UP * 0.6, -toward.normalized(), closing, hash(item.point))
			if spec.family == "post" and response > 0.01: _shake_if_player(vehicle, 0.12 * response)


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
	return body is CharacterBody3D and body.has_method("receive_damage") and body.get("health") != null and body.get("dead") != null and not body.is_in_group("drivable") and body.get("horizontal_velocity") == null


# ---------------------------------------------------------------------------
# Depois do move_and_slide: batida carro x carro e deslize de quem foi atingido.

func _post_move(vehicle: CharacterBody3D, incoming: Vector3, delta: float) -> void:
	var stage := STALL_WORK.begin()
	for index in vehicle.get_slide_collision_count():
		var collision := vehicle.get_slide_collision(index)
		var other := collision.get_collider() as CharacterBody3D
		if other == null or other == vehicle or other.get("horizontal_velocity") == null: continue
		if CRUSH.is_riding(vehicle, other) or CRUSH.is_riding(other, vehicle): continue
		var normal := collision.get_normal()
		normal.y = 0
		if normal.length_squared() < 0.0001: continue
		normal = normal.normalized()
		var other_velocity: Vector3 = other.get("horizontal_velocity")
		var closing := incoming.dot(-normal) - other_velocity.dot(-normal)
		CONTACT_AUDIO.play_contact(vehicle, other, collision.get_position(), closing)
		if closing < CRASH_MIN_CLOSING: continue
		var key := "%d|%d" % [mini(vehicle.get_instance_id(), other.get_instance_id()), maxi(vehicle.get_instance_id(), other.get_instance_id())]
		var now := Time.get_ticks_msec()
		if now - int(_crash_pairs.get(key, -100000)) < 500: continue
		_crash_pairs[key] = now
		_crash(vehicle, other, normal, closing, collision.get_position(), incoming)
	STALL_WORK.finish_slow("street.post.contacts",stage,5000,vehicle)
	stage = STALL_WORK.begin()
	_update_slide(vehicle, delta)
	STALL_WORK.finish_slow("street.post.slide",stage,5000,vehicle)
	stage = STALL_WORK.begin()
	CRUSH.finish_move(vehicle, incoming, delta)
	STALL_WORK.finish_slow("street.post.crush",stage,5000,vehicle)


## Impacto quase inelástico: a carroceria absorve energia. Os dois carros recebem
## a velocidade resultante no mesmo estado usado pela direção e pelas colisões;
## um deslocamento extra por fora fazia o atingido recuar como uma mola.
const CRASH_RESTITUTION := 0.03

func _crash(vehicle: CharacterBody3D, other: CharacterBody3D, normal: Vector3, closing: float, point: Vector3, incoming: Vector3) -> void:
	var began := STALL_WORK.begin()
	_stall_crash(vehicle,other,normal,closing,point,incoming)
	STALL_WORK.finish_slow("street.crash",began,5000,vehicle)

func _stall_crash(vehicle: CharacterBody3D, other: CharacterBody3D, normal: Vector3, closing: float, point: Vector3, incoming: Vector3) -> void:
	# Alvos protegidos continuam sendo sólidos, sem dano nem impulso disfarçado.
	if PROTECTION.is_protected(other): return
	# Apply damage here, behind the pair cooldown, instead of every contact frame.
	var stage := STALL_WORK.begin()
	vehicle.receive_damage(minf(closing * CRASH_DAMAGE_PER_SPEED, float(vehicle.get("max_health")) * CRASH_DAMAGE_MAX_RATIO), other)
	STALL_WORK.finish_slow("street.crash.damage_self",stage,5000,vehicle)
	stage = STALL_WORK.begin()
	other.receive_damage(minf(closing * CRASH_DAMAGE_PER_SPEED, float(other.get("max_health")) * CRASH_DAMAGE_MAX_RATIO), vehicle)
	STALL_WORK.finish_slow("street.crash.damage_other",stage,5000,other)
	stage = STALL_WORK.begin()
	var into := -normal
	var mine := _vehicle_mass(vehicle)
	var theirs := _vehicle_mass(other)
	var impulse := (1.0 + CRASH_RESTITUTION) * closing / (1.0 / mine + 1.0 / theirs)
	var push := into * impulse / theirs
	var lever: Vector3 = point - other.global_position
	lever.y = 0
	var spin := clampf(lever.cross(push).y * 0.12, -3.5, 3.5)
	var other_after: Vector3 = other.get("horizontal_velocity") + push
	_set_impact_velocity(other, other_after)
	_add_slide(other, Vector3.ZERO, spin)
	# O move_and_slide já zerou a velocidade de quem bateu contra o corpo cinemático;
	# devolve a parte que o momento preserva, sem empurrão para trás.
	var after := incoming - into * impulse / mine
	_set_impact_velocity(vehicle, after)
	var self_lever: Vector3 = point - vehicle.global_position
	self_lever.y = 0
	_add_slide(vehicle, Vector3.ZERO, clampf(self_lever.cross(into * impulse / mine).y * 0.04, -1.2, 1.2))
	STALL_WORK.finish_slow("street.crash.impulse",stage,5000,vehicle)
	if closing > 7.0:
		spawn_glass(point, into)
	_shake_if_player(vehicle, clampf(closing / 30.0, 0.08, 0.35))
	_shake_if_player(other, clampf(closing / 30.0, 0.08, 0.35))


static func _set_impact_velocity(vehicle: CharacterBody3D, planar: Vector3) -> void:
	vehicle.set("horizontal_velocity", planar)
	vehicle.set("speed", planar.dot(-vehicle.global_basis.z))
	vehicle.velocity.x = planar.x
	vehicle.velocity.z = planar.z


static func _vehicle_mass(vehicle: Node) -> float:
	return CRUSH.mass(vehicle)


func _add_slide(vehicle: CharacterBody3D, push: Vector3, spin: float) -> void:
	var slide: Vector3 = vehicle.get_meta("crash_slide", Vector3.ZERO)
	vehicle.set_meta("crash_slide", slide + push)
	vehicle.set_meta("crash_spin", float(vehicle.get_meta("crash_spin", 0.0)) + spin)
	vehicle.set_meta("crash_stun", CRASH_STUN)
	if vehicle.get("traffic") == true:
		vehicle.set_meta("crash_was_traffic", true)
		vehicle.set("traffic", false)
		vehicle.set("brake_input", true)


func _update_slide(vehicle: CharacterBody3D, delta: float) -> void:
	if not vehicle.has_meta("crash_stun"): return
	var slide: Vector3 = vehicle.get_meta("crash_slide", Vector3.ZERO)
	var spin: float = vehicle.get_meta("crash_spin", 0.0)
	if slide.length_squared() > 0.0001:
		var stage := STALL_WORK.begin()
		var hit := vehicle.move_and_collide(slide * delta)
		STALL_WORK.finish_slow("street.slide.move_and_collide",stage,5000,vehicle)
		if hit != null: slide = slide.slide(hit.get_normal()) * 0.5
	if absf(spin) > 0.001:
		var stage := STALL_WORK.begin()
		vehicle.rotate_y(spin * delta)
		STALL_WORK.finish_slow("street.slide.rotate",stage,5000,vehicle)
	slide = slide.move_toward(Vector3.ZERO, SLIDE_FRICTION * delta)
	spin = move_toward(spin, 0.0, 2.8 * delta)
	var stun: float = float(vehicle.get_meta("crash_stun")) - delta
	vehicle.set_meta("crash_slide", slide)
	vehicle.set_meta("crash_spin", spin)
	vehicle.set_meta("crash_stun", stun)
	if stun <= 0.0 and slide.length_squared() < 0.01:
		vehicle.remove_meta("crash_stun")
		vehicle.remove_meta("crash_slide")
		vehicle.remove_meta("crash_spin")
		if vehicle.get_meta("crash_was_traffic", false):
			vehicle.remove_meta("crash_was_traffic")
			if float(vehicle.get("health")) > 0 and not vehicle.get("controlled"):
				vehicle.set("brake_input", false)
				vehicle.set("traffic", true)


# ---------------------------------------------------------------------------
# Pouso do atropelado: dano, queda, poça, socorro.

func on_body_landed(actor: CharacterBody3D, lethal: bool, source: Node, impact_speed: float, heading: Vector3) -> void:
	if PROTECTION.is_protected(actor): return
	actor.set_meta("street_vehicle_hit", true)
	var health: float = float(actor.get("health"))
	if lethal:
		actor.receive_damage(health + 500.0, source)
		# receive_damage deixa layer 0 e dispara a queda da V2.
	else:
		# Sobrevive caído com pouca vida (V1 deixava 1 de vida esperando a ambulância).
		actor.receive_damage(maxf(1.0, health - clampf(22.0 - impact_speed, 6.0, 18.0)), source)
		if actor.get("dead") != true:
			var visual: Node3D = actor.get("visual")
			if is_instance_valid(visual): preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(actor, visual, heading)
			actor.collision_layer = 0
			actor.collision_mask = 0
			actor.set_physics_process(false)
	var dead: bool = actor.get("dead") == true
	# Centro no tronco: a queda da V2 desloca o corpo ~0,65 m para a frente.
	blood.spawn_pool(actor.global_position + heading.normalized() * 0.6, dead, actor if _counts_as_corpse(actor) else null, heading)
	_watch[actor.get_instance_id()] = {"health": float(actor.get("health")), "dead": dead}
	CONTACT_AUDIO.play_contact(self, actor, actor.global_position, impact_speed, "flesh")


func play_body_thud(point: Vector3, strength: float) -> void:
	CONTACT_AUDIO.play_contact(self, null, point, lerpf(1.0, 6.0, clampf(strength, 0, 1)), "flesh")


func play_prop_hit(point: Vector3, family: String, speed: float) -> void:
	CONTACT_AUDIO.play_contact(self, null, point, speed, family, "prop|" + str(Vector3i((point * 2.0).round())))


func play(family: String, point: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var list: Array = _streams.get(family, [])
	if list.is_empty(): return
	var player := _audio[_audio_next]
	_audio_next = (_audio_next + 1) % _audio.size()
	player.stream = list.pick_random()
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
# Observação de vida: sangue de tiro, faca, explosão e gotejamento de ferido.

func _physics_process(delta: float) -> void:
	_expire_exceptions()
	_update_geysers(delta)
	_update_wounds(delta)
	_watch_clock += delta
	if _watch_clock < WATCH_INTERVAL: return
	_watch_clock = 0.0
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
	for person in _people_cache:
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
	# Preserve the existing 0.2 s budget even for multiple pellets in one shot.
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

func spawn_glass(point: Vector3, direction: Vector3) -> void:
	var began := STALL_WORK.begin()
	_stall_spawn_glass(point,direction)
	STALL_WORK.finish_slow("street.glass",began,5000,self)

func _stall_spawn_glass(point: Vector3, direction: Vector3) -> void:
	var stage := STALL_WORK.begin()
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.amount = 26
	burst.lifetime = 0.9
	burst.explosiveness = 0.95
	var shard := BoxMesh.new()
	shard.size = Vector3(0.05, 0.01, 0.07)
	burst.mesh = shard
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.9, 0.95, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic_specular = 1.0
	material.roughness = 0.05
	burst.material_override = material
	burst.direction = (direction + Vector3.UP * 0.6).normalized()
	burst.spread = 55.0
	burst.initial_velocity_min = 2.0
	burst.initial_velocity_max = 5.0
	burst.gravity = Vector3(0, -12, 0)
	burst.angular_velocity_min = -720
	burst.angular_velocity_max = 720
	STALL_WORK.finish_slow("street.glass.resources",stage,5000,self)
	stage = STALL_WORK.begin()
	add_child(burst)
	burst.global_position = point + Vector3.UP * 0.8
	burst.emitting = true
	burst.finished.connect(burst.queue_free)
	STALL_WORK.finish_slow("street.glass.attach",stage,5000,self)
	_scatter(point, direction, 22, Vector2(0.04, 0.09), Color(0.8, 0.92, 0.98, 0.9), 0.05, 60.0)


func spawn_litter(point: Vector3, direction: Vector3) -> void:
	_scatter(point, direction, 14, Vector2(0.12, 0.3), Color(0.86, 0.84, 0.76), 0.9, 90.0)


## Pedacinhos no chão (vidro, papel): uma malha só, some depois de `lifetime`.
func _scatter(point: Vector3, direction: Vector3, count: int, size: Vector2, color: Color, roughness: float, lifetime: float) -> void:
	var began := STALL_WORK.begin()
	_stall_scatter(point,direction,count,size,color,roughness,lifetime)
	STALL_WORK.finish_slow("street.scatter",began,5000,self)

func _stall_scatter(point: Vector3, direction: Vector3, count: int, size: Vector2, color: Color, roughness: float, lifetime: float) -> void:
	var stage := STALL_WORK.begin()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var flat := Vector3(direction.x, 0, direction.z).normalized() if Vector2(direction.x, direction.z).length() > 0.01 else Vector3.FORWARD
	for index in count:
		var center := flat * randf_range(-0.4, 2.2) + flat.cross(Vector3.UP) * randf_range(-1.1, 1.1)
		var s := randf_range(size.x, size.y)
		var a := randf_range(0, TAU)
		var corners := [Vector3(cos(a), 0, sin(a)), Vector3(cos(a + 2.2), 0, sin(a + 2.2)), Vector3(cos(a + 4.1), 0, sin(a + 4.1))]
		for corner in corners: tool.add_vertex(center + corner * s)
	var mesh := MeshInstance3D.new()
	STALL_WORK.finish_slow("street.scatter.geometry",stage,5000,self)
	stage = STALL_WORK.begin()
	mesh.mesh = tool.commit()
	STALL_WORK.finish_slow("street.scatter.commit",stage,5000,self)
	stage = STALL_WORK.begin()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic_specular = 1.0 if roughness < 0.2 else 0.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	STALL_WORK.finish_slow("street.scatter.material",stage,5000,self)
	stage = STALL_WORK.begin()
	add_child(mesh)
	mesh.global_position = Vector3(point.x, point.y + 0.045, point.z)
	_litter.append(mesh)
	while _litter.size() > 24:
		var oldest = _litter.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()
	STALL_WORK.finish_slow("street.scatter.attach",stage,5000,self)
	var tween := mesh.create_tween()
	tween.tween_interval(lifetime)
	tween.tween_property(material, "albedo_color:a", 0.0, 4.0)
	tween.tween_callback(mesh.queue_free)


## Hidrante quebrado: coluna d'água de verdade (WaterJet3D) caindo em volta, em
## vez de esferas soltas. Apaga fogo que estiver no alcance (GEYSER_DOUSE_RADIUS).
const GEYSER_DOUSE_RADIUS := 3.5

func spawn_geyser(point: Vector3) -> void:
	var jet = preload("res://gameplay/fx/WaterJet3D.gd").new()
	jet.flight_time = 1.5
	add_child(jet)
	jet.aim(point + Vector3.UP * 0.35, point + Vector3(0.9, 0.0, 0.4))
	jet.set_active(true)
	var puddle := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.005
	disc.radial_segments = 18
	puddle.mesh = disc
	var wet := StandardMaterial3D.new()
	wet.albedo_color = Color(0.08, 0.1, 0.12, 0.55)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.roughness = 0.03
	wet.metallic_specular = 1.0
	puddle.material_override = wet
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puddle)
	puddle.global_position = Vector3(point.x, point.y + 0.04, point.z)
	puddle.scale = Vector3(0.2, 1, 0.2)
	_geysers.append({"jet": jet, "puddle": puddle, "material": wet, "age": 0.0})
	CONTACT_AUDIO.play_contact(self, null, point, 8.0, "metal", "prop|" + str(Vector3i((point * 2.0).round())))


## Jorra ~14 s, perde força nos últimos 4 s; a poça cresce e depois seca.
func _update_geysers(delta: float) -> void:
	for index in range(_geysers.size() - 1, -1, -1):
		var geyser: Dictionary = _geysers[index]
		geyser.age = float(geyser.age) + delta
		var age: float = geyser.age
		# Sem tipo na leitura: o jato é liberado aos 16 s e o dicionário continua
		# com a referência; atribuir instância liberada a variável tipada é erro.
		var jet = geyser.jet
		var puddle = geyser.puddle
		if is_instance_valid(jet):
			var force := 1.0 - smoothstep(10.0, 14.0, age)
			jet.pressure = force
			jet.flight_time = lerpf(0.6, 1.5, force)
			jet.aim(jet.drops.global_position, jet.end_point)
			if age > 14.0: jet.set_active(false)
			if age > 16.0: jet.queue_free()
			elif force > 0.2: _douse_near(jet.drops.global_position, delta * force)
		if is_instance_valid(puddle):
			var radius := lerpf(0.2, 3.2, smoothstep(0.0, 12.0, age))
			puddle.scale = Vector3(radius, 1, radius)
			(geyser.material as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - smoothstep(40.0, 60.0, age))
		if age > 60.0:
			if is_instance_valid(puddle): puddle.queue_free()
			_geysers.remove_at(index)

func _douse_near(point: Vector3, amount: float) -> void:
	var gameplay = controller.world.get("gameplay") if controller != null and controller.world != null else null
	var emergency = gameplay.get("emergency") if gameplay != null else null
	if emergency == null: return
	for fire in emergency.fires:
		if is_instance_valid(fire) and fire.global_position.distance_to(point) < GEYSER_DOUSE_RADIUS:
			emergency.extinguish(fire, amount * 0.5)
