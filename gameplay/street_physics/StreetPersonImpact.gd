extends RefCounted
## Carro contra pessoa antes do move_and_slide: varredura da forma do carro, atropelamento (voo,
## sangue, rastro, grito) e encostão abaixo de NUDGE_MAX_SPEED. Separado de StreetPhysics.gd em 01/11
## só para o dono caber na leitura. O estado (_people_cache, _nudges, contadores nudges/nudge_falls,
## blood, tracks), as constantes e os interruptores (vehicle_nudge) continuam no StreetPhysics,
## porque testes e outros sistemas leem esses campos lá; o dono mantém cada função antiga como
## delegação de uma linha com a mesma assinatura (vários testes chamam _hit_people direto). `g` fica
## como Node3D, e não como o script do dono, para não criar preload cíclico. Até as chamadas entre
## funções deste arquivo passam por `g.`: 9 subclasses de teste sobrescrevem _ready, on_body_landed,
## spawn_glass, _shake_if_player e _physics_process. Caminho quente (por veículo e por quadro): o
## auxiliar nasce uma vez com o dono e nada aqui aloca além do que o dono já alocava.

const FLIGHT := preload("res://gameplay/street_physics/BodyFlight3D.gd")
const TRACKS := preload("res://gameplay/street_physics/BloodTracks3D.gd")
const CRUSH := preload("res://gameplay/street_physics/HeavyVehicleCrush.gd")
const CONTACT_AUDIO := preload("res://audio/VehicleCrashAudio.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Varre a forma real do carro (V1 prepare_motion): pessoa atingida acima do
## limiar sai voando e o carro não para nela; pessoa já caída não vira parede.
func _hit_people(vehicle: CharacterBody3D, planar: Vector3, motion: Vector3) -> void:
	var player = g.controller.world.get("player") if g.controller != null else null
	# O trânsito usa o cache de proximidade; o carro do jogador também alcança NPCs fora do cache.
	var half_length: Variant = vehicle.get("half_length")
	var reach := motion.length() + float(half_length if half_length != null else 2.3) + 1.5
	var reach_squared := reach * reach
	var origin := vehicle.global_position
	var anyone := false
	for person in g._people_cache:
		if is_instance_valid(person) and person != player and person.global_position.distance_squared_to(origin) < reach_squared:
			anyone = true
			break
	# O carro controlado também precisa alcançar NPCs definidos/aninhados ausentes do cache.
	if not anyone and vehicle.get("controlled") != true: return
	for attempt in 4:
		var contact := KinematicCollision3D.new()
		var cast_began := STALL_WORK.begin()
		var touched := vehicle.test_move(vehicle.global_transform, motion, contact, vehicle.safe_margin, true, 8)
		STALL_WORK.finish_slow("street.pre.people.cast", cast_began, 5000, vehicle)
		if not touched: return
		var person: CharacterBody3D
		for index in contact.get_collision_count():
			# Ignore support contacts; a floor must not hide a pedestrian at the bumper.
			if absf(contact.get_normal(index).y) > 0.55: continue
			person = contact.get_collider(index) as CharacterBody3D
			break
		if not g._is_person(person) or person == player or PROTECTION.is_protected(person): return
		if person.get("dead") == true or person.has_meta("street_down"):
			g._except(vehicle, person)
			continue
		var toward := person.global_position - vehicle.global_position
		toward.y = 0
		var closing := planar.dot(toward.normalized()) if toward.length_squared() > 0.0001 else planar.length()
		if closing < g.PERSON_MIN_SPEED: return
		var soft_fall := false
		if g.vehicle_nudge and planar.length() < g.NUDGE_MAX_SPEED and not person.is_in_group("skate_boards"):
			if g._nudge(vehicle, person, planar, motion, closing): return
			soft_fall = true
		g._except(vehicle, person)
		if person.is_in_group("skate_boards"):
			# A cápsula montada representa o piloto, não uma barreira sólida na via.
			# Pula fora antes de mover o carro; a prancha solta mantém só a colisão com o piso.
			person.receive_damage(maxf(1.0, closing * 4.0), vehicle)
			person.rotation.y = atan2(-planar.x, -planar.z)
			person.speed = minf(closing * 0.35, 8.0)
			continue
		var gameplay = g.controller.world.get("gameplay") if g.controller != null else null
		var point := person.global_position + Vector3.UP * 0.9
		if soft_fall:
			# Derrubado pelo encostão: cai na frente do carro, sem espirro nem poça; o sangue só vem
			# se a roda passar por cima (run_over_downed).
			g.nudge_falls += 1
			person.set_meta("street_soft_fall", true)
			var flight = FLIGHT.launch(person, planar, false, g, vehicle, true)
			if flight != null: flight.min_down = 1.6
			CONTACT_AUDIO.play_body_impact(vehicle, person, point, closing)
			var fell_voiced: bool = gameplay != null and gameplay.has_method("person_voice") and gameplay.person_voice(person, "heavy")
			if not fell_voiced: g.play("panic", point, -6.0)
			continue
		var lethal: bool = planar.length() >= g.LETHAL_SPEED and person.has_method("receive_damage")
		person.set_meta("vehicle_blood_side", preload("res://gameplay/vehicle_effects/VehicleBlood.gd").impact_side(vehicle, planar))
		FLIGHT.launch(person, planar, lethal, g, vehicle, true)
		var response := CRUSH.light_impact_response(vehicle, planar.length())
		g._scale_vehicle_speed(vehicle, 1.0 - 0.12 * response)
		if gameplay != null and is_instance_valid(gameplay.get("effects")):
			gameplay.effects.blood(point, planar.normalized(), 40.0 if lethal else 18.0)
		if is_instance_valid(g.blood): g.blood.spawn_splatter(person.global_position, planar, clampf(planar.length() / g.LETHAL_SPEED, 0.2, 1.0))
		if is_instance_valid(g.tracks): g.tracks.soak(vehicle, TRACKS.TIRE_DISTANCE)
		CONTACT_AUDIO.play_body_impact(vehicle, person, point, closing)
		# 27/10: o grito do atropelado é o da própria pessoa (PainVoiceBank); o "panic" antigo era a
		# mesma voz masculina para todo mundo e fica só para corpo sem voz gravada.
		var voiced: bool = gameplay != null and gameplay.has_method("person_voice") and gameplay.person_voice(person, "death" if lethal else "heavy")
		if not lethal and not voiced: g.play("panic", point, -4.0)
		if response > 0.01: g._shake_if_player(vehicle, (0.18 if lethal else 0.1) * response)


## Empurra a pessoa junto do para-choque e para o lado do carro onde ela já está. true = continua de
## pé (o carro segue sem exceção de colisão); false = a pressão passou do limite e ela vai ao chão.
func _nudge(vehicle: CharacterBody3D, person: CharacterBody3D, planar: Vector3, motion: Vector3, closing: float) -> bool:
	var now := Time.get_ticks_msec()
	var id := person.get_instance_id()
	var state: Dictionary = g._nudges.get(id, {})
	var fresh: bool = state.is_empty() or now - int(state.last) > g.NUDGE_FORGET_MS
	var forward := planar.normalized()
	var side := Vector3.UP.cross(forward)
	if fresh:
		var lateral := (person.global_position - vehicle.global_position).dot(side)
		# Bem no meio do para-choque o lado é sorte; fora dele, sai pelo lado mais perto da quina.
		var escape := signf(lateral) if absf(lateral) > 0.15 else (1.0 if randf() < 0.5 else -1.0)
		state = {"pressure": 0.0, "side": escape, "react": -100000}
		g._nudges[id] = state
		if g._nudges.size() > 32:
			for key in g._nudges.keys():
				if now - int(g._nudges[key].last) > g.NUDGE_FORGET_MS: g._nudges.erase(key)
	state.last = now
	var delta := motion.length() / maxf(planar.length(), 0.001)
	# A frente acompanha o carro com folga de 2 cm; o passo lateral é a pessoa tentando sair da frente.
	var shove: Vector3 = forward * (motion.length() + 0.02) + side * float(state.side) * g.NUDGE_SIDESTEP_SPEED * delta
	var contact := person.move_and_collide(shove)
	var blocked := false
	if contact != null and absf(contact.get_normal().y) <= 0.55 and contact.get_normal().dot(forward) < -0.4:
		blocked = contact.get_remainder().length() > shove.length() * 0.5
	state.pressure = float(state.pressure) + delta * (g.NUDGE_PRESSURE_BASE + closing / g.NUDGE_MAX_SPEED + (g.NUDGE_PRESSURE_BLOCKED if blocked else 0.0))
	if float(state.pressure) >= 1.0:
		g._nudges.erase(id)
		return false
	g._scale_vehicle_speed(vehicle, 1.0 - g.NUDGE_DRAG * delta)
	if now - int(state.react) >= g.NUDGE_REACT_MS:
		state.react = now
		g.nudges += 1
		var visual := FLIGHT.actor_visual(person)
		if is_instance_valid(visual): preload("res://gameplay/CharacterFallPresentation3D.gd").apply_hit(person, visual, planar, 10.0 + closing * 4.0)
		var point := person.global_position + Vector3.UP * 0.9
		if fresh:
			CONTACT_AUDIO.play_body_impact(vehicle, person, point, closing)
			var gameplay = g.controller.world.get("gameplay") if g.controller != null and g.controller.get("world") != null else null
			if gameplay != null and gameplay.has_method("person_voice"): gameplay.person_voice(person, "light")
	return true
