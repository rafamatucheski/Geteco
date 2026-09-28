extends Node
## Corpo arremessado por veículo (porte de VehiclePersonImpact + AnimatedPedestrian3D.get_run_over da V1).
##
## V1: pessoa atingida acima de 35 px/s voa na direção do impacto a 85% da
## velocidade do carro, freando a 950 px/s², e para contra parede. Abaixo de
## 200 px/s (12,5 m/s) sobrevive caída esperando ambulância; acima, morre.
## Melhorias do 3D: voo com arco (sobe e cai) e giro em volta do eixo do
## impacto, quique no pouso, respingo alongado no rumo do voo e poça ao parar.
## O sobrevivente levanta sozinho se o socorro não vier (antes ficava no chão
## para sempre quando o incidente saía do orçamento de emergência).

const DECELERATION := 950.0 / 16.0
const GRAVITY := 22.0
const SELF_RECOVERY_SECONDS := 45.0
const GET_UP_SECONDS := 0.9

var actor: CharacterBody3D
var director: Node
var velocity := Vector3.ZERO
var vertical := 0.0
var height := 0.0
var spin_axis := Vector3.RIGHT
var spin_speed := 0.0
var lethal := false
var flying := true
var down_time := 0.0
var bounces := 0
var _visual_base := Transform3D.IDENTITY
var _saved_layer := 2
var _saved_mask := 7
var _getting_up := false
var source: WeakRef
var impact_speed := 0.0


## O dano só é aplicado no pouso (director.on_body_landed): a V2 dispara a
## animação de queda no instante em que a vida zera, e ela brigaria com o giro
## do voo. Crime e socorro saem pelo receive_damage normal, com o carro como
## fonte, então a autoria (jogador x tráfego) continua a mesma.
static func launch(p_actor: CharacterBody3D, impact_velocity: Vector3, p_lethal: bool, p_director: Node, p_source: Node) -> Node:
	if preload("res://gameplay/DamageProtection.gd").is_protected(p_actor): return null
	var existing := p_actor.get_node_or_null("BodyFlight3D")
	if existing != null: existing.queue_free()
	var flight = load("res://gameplay/street_physics/BodyFlight3D.gd").new()
	flight.name = "BodyFlight3D"
	flight.actor = p_actor
	flight.director = p_director
	flight.lethal = p_lethal
	flight.source = weakref(p_source)
	flight.impact_speed = impact_velocity.length()
	var flat := Vector3(impact_velocity.x, 0, impact_velocity.z)
	var speed := minf(flat.length(), 600.0 / 16.0)
	flight.velocity = flat.normalized() * speed * 0.85 if speed > 0.01 else Vector3.ZERO
	# Batida forte joga para cima; leve só derruba.
	flight.vertical = clampf(speed * 0.32, 1.2, 6.5)
	flight.spin_axis = Vector3.UP.cross(flat.normalized()).normalized() if speed > 0.01 else Vector3.RIGHT
	flight.spin_speed = clampf(speed * 0.9, 3.0, 16.0) * (1.0 if randf() < 0.7 else -1.0)
	p_actor.add_child(flight)
	return flight


func _ready() -> void:
	_saved_layer = actor.collision_layer if actor.collision_layer != 0 else 2
	_saved_mask = actor.collision_mask if actor.collision_mask != 0 else 7
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.set_physics_process(false)
	actor.set_meta("street_flying", true)
	actor.set_meta("street_down", true)
	var visual: Node3D = actor.get("visual")
	if is_instance_valid(visual): _visual_base = visual.transform
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor):
		queue_free()
		return
	if flying:
		_fly(delta)
	elif not lethal:
		_wait_for_help(delta)


func _fly(delta: float) -> void:
	var visual: Node3D = actor.get("visual")
	var step := velocity * delta
	# V1 `move_falling_body`: nunca atravessa parede; encosta e cai ali.
	if step.length_squared() > 0.000001:
		var space := actor.get_world_3d().direct_space_state
		var from := actor.global_position + Vector3.UP * (0.6 + height)
		var ray := PhysicsRayQueryParameters3D.create(from, from + step + step.normalized() * 0.3, 1)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			step = Vector3.ZERO
			velocity = -velocity * 0.18
			director.play_body_thud(actor.global_position, 0.6)
	actor.global_position += step
	velocity = velocity.move_toward(Vector3.ZERO, DECELERATION * delta * (1.0 if height <= 0.05 else 0.25))
	vertical -= GRAVITY * delta
	height += vertical * delta
	if height <= 0.0:
		height = 0.0
		if absf(vertical) > 2.4 and bounces < 2:
			vertical = -vertical * 0.32
			bounces += 1
			spin_speed *= 0.45
			director.play_body_thud(actor.global_position, clampf(absf(vertical) / 3.0, 0.3, 1.0))
		else:
			vertical = 0.0
	if is_instance_valid(visual):
		# Gira em volta do eixo do impacto durante o voo; no chão só arrasta.
		var turn := spin_speed * delta * (1.0 if height > 0.05 else 0.2)
		visual.transform = Transform3D(Basis(spin_axis, turn), Vector3.ZERO) * visual.transform
		visual.position = _visual_base.origin + Vector3.UP * height
	if height <= 0.0 and vertical == 0.0 and velocity.length() < 0.75:
		_land()


func _land() -> void:
	flying = false
	actor.remove_meta("street_flying")
	var visual: Node3D = actor.get("visual")
	# Volta à pose de pé e deixa a apresentação de queda da V2 deitar o corpo
	# (membros, quique): uma só animação de queda, a mesma do tiro.
	if is_instance_valid(visual): visual.transform = _visual_base
	var heading := velocity if velocity.length_squared() > 0.01 else spin_axis.cross(Vector3.UP)
	director.on_body_landed(actor, lethal, source.get_ref() if source != null else null, impact_speed, heading)
	if lethal or actor.get("dead") == true: queue_free()


func _wait_for_help(delta: float) -> void:
	if _getting_up: return
	down_time += delta
	# O paramédico (EmergencyManager.complete -> recover_from_injury) devolve a
	# vida para >= 60; sem ele, levanta sozinho depois de um tempo.
	var treated := float(actor.get("health")) >= 60.0
	if actor.get("dead") == true:
		queue_free()
		return
	if treated or down_time >= SELF_RECOVERY_SECONDS:
		_get_up()


func _get_up() -> void:
	_getting_up = true
	var visual: Node3D = actor.get("visual")
	var tween := actor.create_tween()
	if is_instance_valid(visual):
		var start := visual.transform
		tween.tween_method(func(t: float):
			if is_instance_valid(visual): visual.transform = start.interpolate_with(_visual_base, smoothstep(0.0, 1.0, t))
		, 0.0, 1.0, GET_UP_SECONDS)
	tween.tween_callback(func():
		if not is_instance_valid(actor): return
		if actor.get("dead") == true: return
		actor.health = maxf(float(actor.get("health")), 35.0)
		actor.collision_layer = _saved_layer
		actor.collision_mask = _saved_mask
		actor.set_physics_process(true)
		actor.remove_meta("street_down")
		if is_instance_valid(visual): visual.transform = _visual_base
		queue_free())
