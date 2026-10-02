extends RefCounted
## A massa vence carrocerias menores; paredes continuam sendo paredes. O casco
## amassado é uma rampa convexa real: move_and_slide sobe pelas bordas, sem saltos
## de posição, máscaras removidas ou deslocamento extra depois da colisão.

const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const RATIO_META := "heavy_crush_ratio"
const SAVED_META := "heavy_crush_original"
const RIDE_META := "heavy_crush_ride"
const MAX_TARGET_HEIGHT := 2.35
const MAX_MASS := 30.0
const HEAVY_MASS := 3.0


static func mass(vehicle: Node) -> float:
	var handling = vehicle.get("handling")
	if handling != null and handling.get("mass") != null:
		return clampf(float(handling.mass), 0.3, MAX_MASS)
	var width = vehicle.get("half_width")
	var length = vehicle.get("half_length")
	return clampf(float(width) * float(length) * 0.35, 0.3, MAX_MASS) if width != null and length != null else 1.0


## Fator do tranco para corpos/postes. A energia cresce com v²; não se cobra
## a mesma porcentagem de velocidade por pessoa em um tanque e em uma moto.
static func light_impact_response(vehicle: Node, speed: float) -> float:
	var weight := mass(vehicle)
	if weight >= HEAVY_MASS or speed >= 22.0: return 0.0
	var energy := weight * speed * speed
	return clampf(1.0 - smoothstep(55.0, 300.0, energy), 0.0, 1.0) / maxf(1.0, weight)


static func is_large_target(target: CharacterBody3D) -> bool:
	if mass(target) >= HEAVY_MASS: return true
	var archetype := str(target.get("archetype"))
	if archetype.contains("truck") or archetype.contains("bus"): return true
	# Nomes próprios de caminhões/ônibus do catálogo que não contêm a classe.
	if archetype in ["route_city", "towmaster", "boxrunner", "rescue_pumper", "army_tank"]: return true
	var height := float(target.get("body_height"))
	if target.has_meta(SAVED_META): height = float(target.get_meta(SAVED_META).height)
	return height >= 2.65 or float(target.get("half_length")) * 2.0 >= 6.2 or float(target.get("half_width")) * 2.0 >= 3.15


static func eligible(vehicle: CharacterBody3D, target: CharacterBody3D, speed: float) -> bool:
	if target == null or target == vehicle or PROTECTION.is_protected(target): return false
	if not target.is_in_group("drivable") or target.get("horizontal_velocity") == null: return false
	var collider = target.get("shape")
	if not collider is CollisionShape3D or collider.disabled: return false
	if not collider.shape is BoxShape3D and not target.has_meta(SAVED_META): return false
	var original_height := float(target.get("body_height"))
	if target.has_meta(SAVED_META): original_height = float(target.get_meta(SAVED_META).height)
	if original_height < 0.4 or is_large_target(target): return false
	var ours := mass(vehicle)
	# Blindados vencem todo carro comum, incluindo SUVs/vans mais altos ou largos.
	# Caminhões, ônibus e gigantes foram excluídos acima, independentemente da área.
	if ours >= 12.0: return speed >= 2.5
	if original_height > MAX_TARGET_HEIGHT: return false
	var theirs := mass(target)
	var ratio := ours / theirs
	var our_area := float(vehicle.get("half_width")) * float(vehicle.get("half_length"))
	var their_area := float(target.get("half_width")) * float(target.get("half_length"))
	if our_area < their_area * 0.92: return false
	# Caminhões grandes e tanques vencem carros comuns já em velocidade urbana.
	if ours >= HEAVY_MASS and ratio >= 2.5 and speed >= 2.5: return true
	# Um carro rápido só vence outro menor; iguais conservam a batida normal.
	return speed >= 22.0 and ratio >= 1.2 and our_area >= their_area * 1.05


## Um shape cast só para veículos com energia suficiente; mais dois testes
## de folga apenas quando encontra um carro elegível. Nenhuma varredura da frota.
static func prepare(vehicle: CharacterBody3D, planar: Vector3, delta: float) -> CharacterBody3D:
	var speed := planar.length()
	if speed < 2.5 or (mass(vehicle) < HEAVY_MASS and speed < 22.0): return null
	var contact := KinematicCollision3D.new()
	var motion := planar * delta + planar.normalized() * 0.22
	if not vehicle.test_move(vehicle.global_transform, motion, contact): return null
	var target := contact.get_collider() as CharacterBody3D
	if not eligible(vehicle, target, speed): return null
	var toward := -contact.get_normal()
	toward.y = 0.0
	var target_velocity: Vector3 = target.get("horizontal_velocity")
	var closing := (planar - target_velocity).dot(toward.normalized())
	if closing < 2.0 and not target.has_meta(RATIO_META): return null
	var height := clampf(float(target.get("body_height")) * 0.26, 0.26, 0.46)
	if target.has_meta(SAVED_META): height = float(target.get("body_height"))
	# Antes de abaixar a carroceria, confirma espaço para o veículo passar por
	# cima. Teto baixo e uma parede imediatamente à frente impedem a manobra.
	var rise := maxf(0.0, target.global_position.y + height - vehicle.global_position.y) + 0.025
	if rise > 0.58: return null
	if vehicle.test_move(vehicle.global_transform, Vector3.UP * rise): return null
	var raised := vehicle.global_transform.translated(Vector3.UP * rise)
	var upper_contact := KinematicCollision3D.new()
	if vehicle.test_move(raised, motion, upper_contact) and upper_contact.get_collider() != target: return null
	var first := not target.has_meta(RATIO_META)
	if first:
		apply_saved(target, height / float(target.get("body_height")))
	# Saves anteriores podem conter um casco achatado ainda com vida. Só este
	# contato físico termina a destruição; carregar apply_saved não explode.
	if float(target.get("health")) > 0.0:
		target.crush(vehicle)
		set_planar(target, Vector3.ZERO)
	if not is_riding(vehicle, target):
		var prior: Dictionary = vehicle.get_meta(RIDE_META, {})
		vehicle.set_meta(RIDE_META, {"target": weakref(target), "time": 0.0,
			"snap": prior.get("snap", vehicle.floor_snap_length), "base_y": prior.get("base_y", vehicle.global_position.y)})
		# O encaixe padrão de 40 cm saltava do teto ao chão num único quadro
		# em alta velocidade. A descida agora usa gravidade e contatos reais.
		vehicle.floor_snap_length = 0.045
	return target if first else null


## Recupera apenas a componente horizontal que o contato inclinado absorveu.
## Qualquer outra parede cancela a recuperação; gravidade e piso são do motor.
static func finish_move(vehicle: CharacterBody3D, incoming: Vector3, delta: float) -> void:
	if not vehicle.has_meta(RIDE_META): return
	var state: Dictionary = vehicle.get_meta(RIDE_META)
	var target = state.target.get_ref()
	state.time = float(state.time) + delta
	if not is_instance_valid(target) or state.time > 4.0:
		_end_ride(vehicle)
		return
	var local: Vector3 = target.to_local(vehicle.global_position)
	var extent := float(vehicle.get("half_length")) + float(target.get("half_length")) + 1.2
	if Vector2(local.x, local.z).length() > extent and vehicle.is_on_floor() and vehicle.global_position.y <= float(state.base_y) + 0.08:
		_end_ride(vehicle)
		return
	var touching := false
	for index in vehicle.get_slide_collision_count():
		var contact := vehicle.get_slide_collision(index)
		if contact.get_collider() == target:
			touching = true
		elif contact.get_normal().y < 0.65:
			return
	if touching: set_planar(vehicle, incoming)


static func is_riding(vehicle: CharacterBody3D, target: CharacterBody3D) -> bool:
	if not vehicle.has_meta(RIDE_META): return false
	var ride: Dictionary = vehicle.get_meta(RIDE_META)
	return ride.target.get_ref() == target and target.has_meta(RATIO_META)


static func _end_ride(vehicle: CharacterBody3D) -> void:
	if not vehicle.has_meta(RIDE_META): return
	var state: Dictionary = vehicle.get_meta(RIDE_META)
	vehicle.floor_snap_length = float(state.snap)
	vehicle.remove_meta(RIDE_META)


static func apply_saved(vehicle: CharacterBody3D, ratio: float) -> void:
	if PROTECTION.is_protected(vehicle): return
	var collider = vehicle.get("shape")
	if not collider is CollisionShape3D: return
	if not vehicle.has_meta(SAVED_META):
		if not collider.shape is BoxShape3D: return
		var branch_visual: Node3D = vehicle.get("visual")
		vehicle.set_meta(SAVED_META, {"shape": collider.shape, "position": collider.position,
			"height": float(vehicle.get("body_height")), "visual_scale": branch_visual.scale if is_instance_valid(branch_visual) else Vector3.ONE,
			"rotation_shape": vehicle.get("rotation_shape"), "engine_disabled": vehicle.get("engine_disabled") == true})
	var original: Dictionary = vehicle.get_meta(SAVED_META)
	var size: Vector3 = original.shape.size
	ratio = clampf(ratio, 0.18, 0.55)
	var height := clampf(size.y * ratio, 0.26, 0.60)
	var half := size * 0.5
	# Bordas no piso viram rampas até o teto baixo. O volume permanece sólido,
	# inclusive nas laterais e embaixo: carros lentos ainda colidem com ele.
	var inset_x := minf(half.x * 0.84, height * 1.9)
	var inset_z := minf(half.z * 0.70, height * 2.5)
	var points := PackedVector3Array()
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			points.append(Vector3(x * half.x, 0.0, z * half.z))
			points.append(Vector3(x * (half.x - inset_x), height, z * (half.z - inset_z)))
	var crushed := ConvexPolygonShape3D.new()
	crushed.points = points
	collider.shape = crushed
	collider.position = Vector3(original.position.x, 0.0, original.position.z)
	var rotation_hull := BoxShape3D.new()
	rotation_hull.size = Vector3(size.x, maxf(0.1, height - 0.05), size.z)
	vehicle.set("rotation_shape", rotation_hull)
	vehicle.set("body_height", height)
	vehicle.set("engine_disabled", true)
	vehicle.set("traffic", false)
	vehicle.set("brake_input", true)
	var visual: Node3D = vehicle.get("visual")
	if is_instance_valid(visual): visual.scale = original.visual_scale * Vector3(1.02, height / size.y, 1.02)
	vehicle.set_meta(RATIO_META, height / size.y)


static func restore(vehicle: CharacterBody3D) -> void:
	_end_ride(vehicle)
	if not vehicle.has_meta(SAVED_META): return
	var original: Dictionary = vehicle.get_meta(SAVED_META)
	var collider: CollisionShape3D = vehicle.get("shape")
	if is_instance_valid(collider):
		collider.shape = original.shape
		collider.position = original.position
	vehicle.set("body_height", original.height)
	vehicle.set("rotation_shape", original.rotation_shape)
	vehicle.set("engine_disabled", original.engine_disabled)
	var visual: Node3D = vehicle.get("visual")
	if is_instance_valid(visual): visual.scale = original.visual_scale
	vehicle.remove_meta(SAVED_META)
	vehicle.remove_meta(RATIO_META)


static func set_planar(vehicle: CharacterBody3D, planar: Vector3) -> void:
	vehicle.set("horizontal_velocity", planar)
	vehicle.set("speed", planar.dot(-vehicle.global_basis.z))
	vehicle.velocity.x = planar.x
	vehicle.velocity.z = planar.z
