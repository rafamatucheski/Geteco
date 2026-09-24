extends CharacterBody3D
## Urso da serra, portado de world/mountain_pass/MountainBear.gd da V1 (ramo v1-legado).
##
## Adulto: vaga em volta da toca; se o jogador chega perto (e a toca está perto),
## persegue, morde de perto e, de meia distância, avisa (para, baixa a cabeça,
## grunhe) e investe em linha reta. Filhote: foge do jogador e chama a mãe, que
## fica mais agressiva por uns segundos. Distâncias e velocidades da V1 em px
## convertidas a 16 px/m.

const MODEL := preload("res://gameplay/wildlife/MountainBearModel.gd")
const AUDIO := preload("res://audio/wildlife/BearAudio.gd")
enum State { WANDER, WARNING, CHARGE, RECOVER }

const PX := 1.0 / 16.0
const HUNT_RANGE := 235.0 * PX
const HUNT_RANGE_THREATENED := 310.0 * PX
const HOME_LEASH := 370.0 * PX
const ROAM_RADIUS := 48.0 * PX
const WANDER_SPEED := 30.0 * PX
const CHASE_SPEED := 135.0 * PX
const CHARGE_SPEED := 320.0 * PX
const BITE_RANGE := 32.0 * PX
const CHARGE_HIT_RANGE := 36.0 * PX
const WARNING_MIN := 62.0 * PX
const WARNING_MAX := 210.0 * PX
const CUB_FLEE_RANGE := 155.0 * PX
const CUB_FLEE_SPEED := 82.0 * PX
const CUB_SPEED := 36.0 * PX
const BITE_DAMAGE := 38.0
const CHARGE_DAMAGE := 60.0
const GRAVITY := 9.8
const CONTACT_STOP := 1.7

var controller
var is_cub := false
var family_guardian # MountainBear3D; sem tipo para ler `dead` e `threat_time`.
var family_offset := Vector3.ZERO
var home := Vector3.ZERO
var health := 360.0
var dead := false
var state := State.WANDER
var state_time := 0.0
var charge_direction := Vector3.ZERO
var charge_hit := false
var charge_cooldown := 2.0
var bite_cooldown := 0.0
var threat_time := 0.0
var sound_cooldown := 0.0
var elapsed := 0.0
var model: Node3D
var voice: AudioStreamPlayer3D
var breath: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("mountain_wildlife")
	add_to_group("bear_cub" if is_cub else "bear_adult")
	set_meta("gameplay_role", "wildlife")
	health = 55.0 if is_cub else 360.0
	# Camada 2 (corpos): tiro e soco da V2 acertam por ela e chamam receive_damage.
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5 if is_cub else 0.85
	capsule.height = 1.2 if is_cub else 2.2
	shape.shape = capsule
	shape.rotation.x = PI * 0.5
	shape.position.y = capsule.radius
	add_child(shape)
	model = MODEL.new()
	model.is_cub = is_cub
	add_child(model)
	voice = _voice_player("BearVoice", 40.0, -4.0)
	breath = _voice_player("BearBreathing", 12.0, -14.0)
	breath.stream = AUDIO.get_breathing_stream()

func _voice_player(label: String, reach: float, volume: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = label
	player.max_distance = reach
	player.unit_size = 6.0
	player.volume_db = volume
	player.position.y = 1.0
	if AudioServer.get_bus_index("SFX") >= 0: player.bus = &"SFX"
	add_child(player)
	return player

func _player() -> Node3D:
	return controller.world.player if controller != null and controller.world != null else null

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector3(0, velocity.y - GRAVITY * delta, 0)
		move_and_slide()
		return
	var player := _player()
	if player == null: return
	var flat_to_player := Vector3(player.global_position.x - global_position.x, 0, player.global_position.z - global_position.z)
	var distance := flat_to_player.length()
	elapsed += delta
	bite_cooldown = maxf(0, bite_cooldown - delta)
	charge_cooldown = maxf(0, charge_cooldown - delta)
	sound_cooldown = maxf(0, sound_cooldown - delta)
	threat_time = maxf(0, threat_time - delta)
	var exposed: bool = player.is_visible_in_tree() and player.get("dead") != true and String(controller.state.place_id).is_empty()
	var breathe := exposed and distance < 10.0 and not is_cub and state != State.CHARGE
	if breathe and not breath.playing: breath.play()
	elif not breathe and breath.playing: breath.stop()
	var fall := velocity.y - GRAVITY * delta if not is_on_floor() else -0.5
	if is_cub: _update_cub(player, exposed, distance)
	else: _update_adult(player, exposed, distance, flat_to_player, delta)
	velocity.y = fall
	# Encostou no jogador: para. O corpo do jogador colide com a camada 2, e a
	# investida a 20 m/s empurrava o jogador junto, às vezes chão abaixo até o mar
	# de Harbor sob Mountain (relato do jogador em 2026-09-24).
	if distance < CONTACT_STOP and Vector2(velocity.x, velocity.z).dot(Vector2(flat_to_player.x, flat_to_player.z)) > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		if state == State.CHARGE:
			state = State.RECOVER
			state_time = 0.7
	move_and_slide()
	if state == State.CHARGE and get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			if absf(get_slide_collision(i).get_normal().y) < 0.5:
				state = State.RECOVER
				state_time = 0.75
				break
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.3: model.rotation.y = lerp_angle(model.rotation.y, atan2(flat.x, flat.y), minf(1.0, delta * 9.0))
	model.walking = flat.length() > 0.3
	model.alert = state == State.WARNING
	model.charging = state == State.CHARGE

func _set_flat_velocity(direction: Vector3, speed: float) -> void:
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

func _update_adult(player: Node3D, exposed: bool, distance: float, to_player: Vector3, delta: float) -> void:
	var hunt_range := HUNT_RANGE_THREATENED if threat_time > 0 else HUNT_RANGE
	var player_home := Vector2(player.global_position.x - home.x, player.global_position.z - home.z).length()
	var hunting := exposed and distance < hunt_range and player_home < HOME_LEASH
	if not hunting:
		state = State.WANDER
		var roam := home + Vector3(sin(elapsed * 0.11), 0, cos(elapsed * 0.08)) * ROAM_RADIUS
		var to_roam := Vector3(roam.x - global_position.x, 0, roam.z - global_position.z)
		_set_flat_velocity(to_roam.normalized(), WANDER_SPEED if to_roam.length() > 0.6 else 0.0)
		return
	# A V1 mostrava um aviso em texto aqui; tirado a pedido do jogador (2026-09-24):
	# o grunhido e a cabeça baixa já avisam.
	var toward := to_player.normalized()
	match state:
		State.WARNING:
			_set_flat_velocity(Vector3.ZERO, 0.0)
			model.rotation.y = lerp_angle(model.rotation.y, atan2(toward.x, toward.z), delta * 4.0)
			state_time -= delta
			if state_time <= 0:
				charge_direction = toward
				state = State.CHARGE
				state_time = 0.8
				charge_hit = false
				charge_cooldown = 2.4
				_voice("charge", true)
		State.CHARGE:
			_set_flat_velocity(charge_direction, CHARGE_SPEED)
			state_time -= delta
			if not charge_hit and distance < CHARGE_HIT_RANGE and _clear_attack(player):
				_hurt_player(CHARGE_DAMAGE)
				charge_hit = true
				bite_cooldown = 1.4
			if state_time <= 0:
				state = State.RECOVER
				state_time = 0.7
		State.RECOVER:
			var flat := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, delta * 700.0 * PX)
			velocity.x = flat.x
			velocity.z = flat.z
			state_time -= delta
			if state_time <= 0: state = State.WANDER
		_:
			_set_flat_velocity(toward, CHASE_SPEED)
			if distance < BITE_RANGE and bite_cooldown == 0 and _clear_attack(player):
				_hurt_player(BITE_DAMAGE)
				bite_cooldown = 1.2
				_voice("warning")
			elif distance > WARNING_MIN and distance < WARNING_MAX and charge_cooldown == 0 and _clear_attack(player):
				state = State.WARNING
				state_time = 0.72
				_set_flat_velocity(Vector3.ZERO, 0.0)
				_voice("warning", true)

func _update_cub(player: Node3D, exposed: bool, distance: float) -> void:
	var guardian_alive: bool = is_instance_valid(family_guardian) and not family_guardian.dead
	var den: Vector3 = family_guardian.global_position if guardian_alive else home
	var target := den + family_offset
	if exposed and distance < CUB_FLEE_RANGE:
		var away := Vector3(global_position.x - player.global_position.x, 0, global_position.z - player.global_position.z).normalized()
		target = home + away * 110.0 * PX
		_set_flat_velocity(Vector3(target.x - global_position.x, 0, target.z - global_position.z).normalized(), CUB_FLEE_SPEED)
		if guardian_alive: family_guardian.threat_time = 5
		_voice("cub_call")
	else:
		target += Vector3(sin(elapsed * 0.21), 0, cos(elapsed * 0.17)) * 15.0 * PX
		var to_target := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
		_set_flat_velocity(to_target.normalized(), CUB_SPEED if to_target.length() > 0.9 else 0.0)

func _clear_attack(player: Node3D) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.9, player.global_position + Vector3.UP * 0.9, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _hurt_player(amount: float) -> void:
	var gameplay = controller.world.get("gameplay") if controller != null else null
	if gameplay != null and gameplay.has_method("damage_player"): gameplay.damage_player(amount)

## Contrato de dano da V2 (Gameplay._damage): tiro, soco e fogo chamam isto.
func receive_damage(amount: float, _source: Node = null) -> void:
	if dead or amount <= 0: return
	health = maxf(0.0, health - amount)
	threat_time = 6
	if is_instance_valid(family_guardian) and not family_guardian.dead: family_guardian.threat_time = 6
	_voice("hurt", true)
	if health > 0:
		model.hurt_flash = 0.18
		return
	dead = true
	breath.stop()
	collision_layer = 0
	model.walking = false
	model.alert = false
	model.charging = false
	model.dead = true
	_voice("death", true)
	var tween := create_tween()
	tween.tween_property(model, "rotation:z", -PI * 0.45, 0.45).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(model, "position:y", 0.26 if is_cub else 0.45, 0.45)

func _voice(event: String, urgent := false) -> void:
	if sound_cooldown > 0 and not urgent: return
	var stream: AudioStream = AUDIO.get_charge_stream() if event == "charge" else AUDIO.get_grunt_alert_stream()
	if stream == null: return
	voice.stream = stream
	voice.pitch_scale = 1.1 if is_cub else 0.96
	voice.play()
	sound_cooldown = 4
