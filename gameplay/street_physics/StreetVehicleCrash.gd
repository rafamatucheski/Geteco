extends RefCounted
## Depois do move_and_slide: batida contra parede, batida carro x carro (impulso quase inelástico,
## dano dos dois lados, moto, vidro, tremor) e o deslize/giro de quem foi atingido. Separado de
## StreetPhysics.gd em 01/11 só para o dono caber na leitura. O estado (_crash_pairs), as constantes
## (CRASH_*, SLIDE_FRICTION) e o resto continuam no StreetPhysics, porque testes (_post_move, _crash,
## _stall_crash, _vehicle_mass), TankCannon (_add_slide) e VehicleTireEffects os chamam lá; o
## dono mantém cada função antiga como delegação de uma linha com a mesma assinatura (as estáticas
## como delegação estática). `g` fica como Node3D, e não como o script do dono, para não criar
## preload cíclico. Até as chamadas entre funções deste arquivo passam por `g.`: subclasses de teste
## sobrescrevem spawn_glass e _shake_if_player. Caminho quente (por veículo e por quadro): o auxiliar
## nasce uma vez com o dono e nada aqui aloca além do que o dono já alocava.

const CRUSH := preload("res://gameplay/street_physics/HeavyVehicleCrush.gd")
const CONTACT_AUDIO := preload("res://audio/VehicleCrashAudio.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _post_move(vehicle: CharacterBody3D, incoming: Vector3, delta: float) -> void:
	var stage := STALL_WORK.begin()
	for index in vehicle.get_slide_collision_count():
		var collision := vehicle.get_slide_collision(index)
		var collider := collision.get_collider()
		if collider is StaticBody3D and absf(collision.get_normal().y) < 0.55:
			var closing := maxf(0.0, -incoming.dot(collision.get_normal()))
			var key := "solid|%d|%d" % [vehicle.get_instance_id(), collider.get_instance_id()]
			var now := Time.get_ticks_msec()
			if closing >= 6.0 and now - int(g._crash_pairs.get(key, -100000)) >= 650:
				g._crash_pairs[key] = now
				g._shake_if_player(vehicle, clampf(closing / 65.0, 0.08, 0.55))
				if closing >= 12.0: g.spawn_glass(collision.get_position(), -collision.get_normal())
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
		if closing < g.CRASH_MIN_CLOSING: continue
		var key := "%d|%d" % [mini(vehicle.get_instance_id(), other.get_instance_id()), maxi(vehicle.get_instance_id(), other.get_instance_id())]
		var now := Time.get_ticks_msec()
		if now - int(g._crash_pairs.get(key, -100000)) < 500: continue
		g._crash_pairs[key] = now
		g._crash(vehicle, other, normal, closing, collision.get_position(), incoming)
	STALL_WORK.finish_slow("street.post.contacts",stage,5000,vehicle)
	stage = STALL_WORK.begin()
	g._update_slide(vehicle, delta)
	STALL_WORK.finish_slow("street.post.slide",stage,5000,vehicle)
	stage = STALL_WORK.begin()
	CRUSH.finish_move(vehicle, incoming, delta)
	STALL_WORK.finish_slow("street.post.crush",stage,5000,vehicle)

func _crash(vehicle: CharacterBody3D, other: CharacterBody3D, normal: Vector3, closing: float, point: Vector3, incoming: Vector3) -> void:
	var began := STALL_WORK.begin()
	g._stall_crash(vehicle,other,normal,closing,point,incoming)
	STALL_WORK.finish_slow("street.crash",began,5000,vehicle)

func _stall_crash(vehicle: CharacterBody3D, other: CharacterBody3D, normal: Vector3, closing: float, point: Vector3, incoming: Vector3) -> void:
	# Alvos protegidos continuam sendo sólidos, sem dano nem impulso disfarçado.
	if PROTECTION.is_protected(other): return
	# Prevê o mesmo movimento resolvido para as peças soltas antes da apresentação de dano.
	# Aplicar a velocidade de jogo fica depois do dano, na ordem existente.
	var driving: Node = g.controller.world.get("driving") if g.controller != null else null
	if driving != null and driving.has_method("motorcycle_crash") and closing >= 5.0:
		driving.motorcycle_crash(vehicle, incoming)
		var other_momentum: Vector3 = other.get("horizontal_velocity")
		if other_momentum.length() < closing: other_momentum = -normal * closing
		driving.motorcycle_crash(other, other_momentum)
	var into := -normal
	var mine: float = g._vehicle_mass(vehicle)
	var theirs: float = g._vehicle_mass(other)
	var impulse: float = (1.0 + g.CRASH_RESTITUTION) * closing / (1.0 / mine + 1.0 / theirs)
	var push := into * impulse / theirs
	var presentation_other: Vector3 = other.get("horizontal_velocity") + push
	var after := incoming - into * impulse / mine
	# Aplica o dano aqui, atrás do cooldown do par, em vez de a cada quadro de contato.
	var stage := STALL_WORK.begin()
	var self_damage:=minf(closing * g.CRASH_DAMAGE_PER_SPEED, float(vehicle.get("max_health")) * g.CRASH_DAMAGE_MAX_RATIO)
	# Mantém a severidade física sem limite para a lataria; a vida mecânica mantém o balanceamento.
	# A normal de contato aponta para dentro deste carro; o outro carro recebe a direção oposta.
	if vehicle.has_method("receive_impact"): vehicle.receive_impact(self_damage,vehicle.to_local(point),other,closing,vehicle.global_basis.inverse()*normal,after)
	else: vehicle.receive_damage(self_damage,other)
	STALL_WORK.finish_slow("street.crash.damage_self",stage,5000,vehicle)
	stage = STALL_WORK.begin()
	var other_damage:=minf(closing * g.CRASH_DAMAGE_PER_SPEED, float(other.get("max_health")) * g.CRASH_DAMAGE_MAX_RATIO)
	if other.has_method("receive_impact"): other.receive_impact(other_damage,other.to_local(point),vehicle,closing,other.global_basis.inverse()*-normal,presentation_other)
	else: other.receive_damage(other_damage,vehicle)
	STALL_WORK.finish_slow("street.crash.damage_other",stage,5000,other)
	stage = STALL_WORK.begin()
	var lever: Vector3 = point - other.global_position
	lever.y = 0
	var spin := clampf(lever.cross(push).y * 0.12, -3.5, 3.5)
	var other_after: Vector3 = other.get("horizontal_velocity") + push
	g._set_impact_velocity(other, other_after)
	g._add_slide(other, Vector3.ZERO, spin)
	# O move_and_slide já zerou a velocidade de quem bateu contra o corpo cinemático;
	# devolve a parte que o momento preserva, sem empurrão para trás.
	g._set_impact_velocity(vehicle, after)
	var self_lever: Vector3 = point - vehicle.global_position
	self_lever.y = 0
	g._add_slide(vehicle, Vector3.ZERO, clampf(self_lever.cross(into * impulse / mine).y * 0.04, -1.2, 1.2))
	STALL_WORK.finish_slow("street.crash.impulse",stage,5000,vehicle)
	if closing > 7.0:
		g.spawn_glass(point, into)
	g._shake_if_player(vehicle, clampf(closing / 30.0, 0.08, 0.35))
	g._shake_if_player(other, clampf(closing / 30.0, 0.08, 0.35))


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
	vehicle.set_meta("crash_stun", g.CRASH_STUN)
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
	slide = slide.move_toward(Vector3.ZERO, g.SLIDE_FRICTION * delta)
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
