extends CharacterBody3D
## Equipe civil da mina. O local é dono de um relógio de física/pose para os seis trabalhadores.
signal died(actor: CharacterBody3D)
const FALL := preload("res://gameplay/CharacterFallPresentation3D.gd")
const AUDIO := preload("res://gameplay/CombatAudio.gd")
var health := 100.0
var dead := false
var visual: Node3D
var gameplay: Node
var home := Vector3.ZERO
var home_yaw := 0.0
var phase := 0.0
var frightened := 0.0
var _threat := Vector3.ZERO
var _support_clock := 0.0
var _safe_direction := Vector3.ZERO
var _voice_cooldown := 0.0
var _ground_ready := false

func _ready() -> void:
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .4
	set_meta("gameplay_role", "civilian")
	set_meta("region_id", "desert")
	add_to_group("v2_damageable")
	home = global_position
	home_yaw = rotation.y
	set_physics_process(false)
	set_process(false)

func notice(origin: Vector3, radius := 30.0) -> void:
	if dead or global_position.distance_squared_to(origin) > radius * radius: return
	_threat = origin
	frightened = 5.0
	_support_clock = 0.0
	if _voice_cooldown <= 0:
		_voice("panic")
		_voice_cooldown = 4.0

func tick(delta: float) -> void:
	if dead or not is_instance_valid(visual): return
	# Na primeira visita, a admissão da região vem antes da instalação da colisão em streaming.
	# Mantém a estação definida no piso até esse apoio existir de fato.
	if not _ground_ready:
		var support := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * .3, global_position - Vector3.UP * .4, 1)
		if get_world_3d().direct_space_state.intersect_ray(support).is_empty(): return
		_ground_ready = true
	phase += delta
	_voice_cooldown = maxf(0, _voice_cooldown - delta)
	frightened = maxf(0, frightened - delta)
	var destination := home
	if frightened > 0:
		var away := global_position - _threat
		away.y = 0
		if away.length_squared() < .01: away = Vector3.RIGHT
		destination = home + away.normalized() * 3.5
	elif fposmod(phase, 18.0) > 11.0:
		# Larga a ferramenta para uma inspeção curta do lado livre da estação.
		destination += Vector3(-1.1, 0, -.55).rotated(Vector3.UP, home_yaw)
	var offset := destination - global_position
	offset.y = 0
	var direction := offset.normalized() if offset.length() > .12 else Vector3.ZERO
	_support_clock -= delta
	if _support_clock <= 0:
		_support_clock = .15
		_safe_direction = direction
		if not direction.is_zero_approx():
			var next := global_position + direction * .7
			var ray := PhysicsRayQueryParameters3D.create(next + Vector3.UP * .3, next - Vector3.UP * .5, 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or hit.normal.y < .7 or absf(hit.position.y - global_position.y) > .28:
				_safe_direction = Vector3.ZERO
	if direction.is_zero_approx(): _safe_direction = Vector3.ZERO
	var speed := 2.1 if frightened > 0 else .7
	velocity.x = _safe_direction.x * speed
	velocity.z = _safe_direction.z * speed
	velocity.y = -1.0 if is_on_floor() else maxf(-18.0, velocity.y - 20.0 * delta)
	move_and_slide()
	if Vector2(velocity.x, velocity.z).length_squared() > .01:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), 1 - exp(-7 * delta))
	elif frightened <= 0 and global_position.distance_to(home) < .25:
		rotation.y = lerp_angle(rotation.y, home_yaw, 1 - exp(-5 * delta))

func sample_pose(time: float, delta: float) -> void:
	if dead or not is_instance_valid(visual): return
	var working := frightened <= 0 and global_position.distance_to(home) < .22 and Vector2(velocity.x, velocity.z).length() < .1
	visual.tool.visible = working
	visual.hand_provider = visual._work_hands if working else Callable()
	visual.activity = "shield" if frightened > 0 else ""
	if working: visual.sample_work(time, delta)
	else: visual._process(delta)

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0: return
	health = maxf(0, health - amount)
	var impact: Vector3 = global_position - source.global_position if source is Node3D else Vector3.ZERO
	if health > 0:
		notice(source.global_position if source is Node3D else global_position, 1000)
		FALL.apply_hit(self, visual, impact, amount)
		return
	dead = true
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_voice("hurt")
	if is_instance_valid(visual):
		visual.tool.hide()
		FALL.apply_fall(self, visual, impact)
	if is_instance_valid(gameplay):
		gameplay.drop_cash(self)
		if is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source(): gameplay.report_vehicle_assault(self, source)
	died.emit(self)

func _voice(kind: String) -> void:
	if is_instance_valid(gameplay): gameplay._play_stream(AUDIO.wav(kind + "_0.wav"), global_position + Vector3.UP, -8.0)

func recover_from_injury() -> void:
	if not dead: health = 100.0
