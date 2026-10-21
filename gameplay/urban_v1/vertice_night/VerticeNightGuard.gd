extends "res://gameplay/urban_v1/CobraLocalGuard.gd"
## Segurança noturna dos Cobras na Vértice (M06-C). Fora do combate anda a ronda e olha num
## cone; quem decide o alarme é o VerticeNightShift. Em alerta vira o CobraAgent de sempre
## (mesmo tiro, cobertura e saque), sem código de combate novo.
const FALL := preload("res://gameplay/CharacterFallPresentation3D.gd")
const CALM := "calm"
const SUSPICIOUS := "suspicious"
const SEARCHING := "searching"
const ALERT := "alert"
var shift: Node
var route: Array = []
var post_facing := Vector3.ZERO
var mode := CALM
var suspicion := 0.0
var investigate := Vector3.INF
var knocked := false
var view_range := 13.0
var view_cos := cos(deg_to_rad(55.0))
var _waypoint := 0
var _pause := 1.0
var _look_around := 0.0

func _ready() -> void:
	super._ready()
	remove_from_group("cobra_local")
	add_to_group("vertice_night_guard")

## Para onde o modelo olha: o CobraModel encara o -Z do visual.
func facing() -> Vector3:
	var forward := -visual.global_transform.basis.z
	forward.y = 0
	return forward.normalized() if forward.length_squared() > .001 else Vector3.FORWARD

## Cone, distância e linha de visão; contêiner, carreta e empilhadeira cobrem.
func can_see(point: Vector3, target: Node3D, range_scale := 1.0, exclude: Array[RID] = []) -> bool:
	if dead: return false
	var offset := point - global_position
	offset.y = 0
	var distance := offset.length()
	if distance > view_range * range_scale: return false
	# Muito perto sente mesmo de lado, nunca pelas costas (derrubada silenciosa).
	var cone := facing().dot(offset / maxf(distance, .001))
	if distance > 2.2 and cone < view_cos: return false
	if distance <= 2.2 and cone < -.2: return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.55, point + Vector3.UP * 1.1, 7, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == target

## Uma amostra do sensor. Devolve true quando a desconfiança vira alerta.
func perceive(seen: bool, at: Vector3, elapsed: float, range_scale := 1.0) -> bool:
	if dead or engaged: return false
	if seen:
		var distance := global_position.distance_to(at)
		# De perto e de frente o vigia entende na hora; no limite do cone leva uns segundos.
		suspicion += elapsed * lerpf(3.2, .55, clampf(distance / (view_range * range_scale), 0.0, 1.0))
		investigate = at
		if mode == CALM and suspicion >= .35: mode = SUSPICIOUS
		return suspicion >= 1.0
	suspicion = maxf(.5 if mode == SEARCHING else 0.0, suspicion - elapsed * .12)
	return false

func search(point: Vector3) -> void:
	if dead or engaged: return
	mode = SEARCHING
	suspicion = maxf(suspicion, .5)
	investigate = point
	_look_around = 0.0

func calm_down() -> void:
	if dead or engaged: return
	mode = CALM
	suspicion = 0.0
	investigate = Vector3.INF

func alert(point: Vector3) -> void:
	if dead: return
	mode = ALERT
	last_known = point
	alerted = true
	set_engaged(true)

## Por trás, sem tiro: cai e fica no chão. O corpo continua no caminho da ronda.
func knock_out(from: Vector3) -> void:
	if dead: return
	knocked = true
	dead = true
	health = 0.0
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	var direction := global_position - from
	direction.y = 0
	FALL.apply_fall(self, visual, direction.normalized() if direction.length_squared() > .001 else Vector3.ZERO)
	died.emit()

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or amount <= 0: return
	super.receive_damage(amount, source)
	if is_instance_valid(shift): shift.guard_hurt(self, source)

func _physics_process(delta: float) -> void:
	if dead: return
	if engaged:
		super._physics_process(delta)
		return
	var goal := global_position
	var speed := 1.25
	if investigate != Vector3.INF:
		goal = investigate
		speed = 2.1 if mode == SEARCHING else 1.5
	elif not route.is_empty():
		goal = route[_waypoint]
	var offset := goal - global_position
	offset.y = 0
	var moving := false
	if investigate != Vector3.INF:
		if offset.length() < 1.2:
			# Chegou onde viu alguma coisa: olha em volta e, sem nada, volta à ronda.
			_look_around += delta
			visual.rotation.y += delta * 1.4
			if _look_around > (6.0 if mode == SEARCHING else 3.5) and mode != SEARCHING: calm_down()
		else:
			moving = true
	elif not route.is_empty():
		if offset.length() < .7:
			_waypoint = (_waypoint + 1) % route.size()
			_pause = 2.5
		_pause = maxf(0.0, _pause - delta)
		moving = _pause <= 0.0
	elif post_facing != Vector3.ZERO:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-post_facing.x, -post_facing.z), 1.0 - exp(-3.0 * delta))
	var movement := Vector3.ZERO
	if moving and offset.length() > .05:
		movement = _steering.steer(self, offset.normalized(), delta) * speed
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-offset.x, -offset.z), 1.0 - exp(-6.0 * delta))
	velocity.x = movement.x
	velocity.z = movement.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	gait += Vector2(velocity.x, velocity.z).length() * delta * 3.4
	visual.update_pose(delta, false, false, 0.0, gait)
