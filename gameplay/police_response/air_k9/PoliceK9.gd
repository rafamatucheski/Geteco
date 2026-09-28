extends CharacterBody3D
const MODELS = preload("res://gameplay/police_response/air_k9/AirK9Models.gd")
const STEERING = preload("res://gameplay/crowd/PedestrianSteering.gd")
const BARKS := [preload("res://audio/living_city/dog_detail_0.wav"), preload("res://audio/living_city/dog_detail_1.wav"), preload("res://audio/living_city/dog_detail_2.wav")]
const BITE_RANGE := 1.35
const HANDLER_RANGE := 24.0
const BODY_SIZE := Vector3(0.56, 1.18, 1.66)
const BODY_CENTER := Vector3(0, 0.6, -0.13)
var director: Node3D
var handler: CharacterBody3D
var health := 45.0
var dead := false
var sees_player := false
var visual: Node3D
var bark: AudioStreamPlayer3D
var last_known := Vector3.ZERO
var mode := "heel"
var withdrawing := false
var _rig: Dictionary
var _steering := STEERING.new()
var _sensor := 0.0
var _repath := 0.0
var _cooldown := 0.0
var _bark_timer := 0.0
var _retire_time := 0.0
var _gait := 0.0
var _path := PackedVector3Array()
var _path_index := 0
var _safe_step := true

func _ready() -> void:
	name = "PoliceK9"
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = 0.3
	set_meta("gameplay_role", "police")
	set_meta("police_k9", true)
	add_to_group("v2_damageable")
	var capsule := BoxShape3D.new()
	capsule.size = BODY_SIZE
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position = BODY_CENTER
	add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	_rig = MODELS.dog(visual)
	bark = AudioStreamPlayer3D.new()
	bark.max_distance = 30.0
	bark.unit_size = 5.0
	bark.volume_db = -7.0
	add_child(bark)
	if is_instance_valid(handler): last_known = handler.global_position

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(director): return
	if director.response_paused(): return
	var gameplay: Node3D = director.gameplay
	_cooldown = maxf(0.0, _cooldown - delta)
	_bark_timer = maxf(0.0, _bark_timer - delta)
	_sensor -= delta
	_repath -= delta
	var handler_alive: bool = is_instance_valid(handler) and handler.get("dead") != true and not handler.is_queued_for_deletion()
	var usable: bool = not withdrawing and handler_alive and director.exterior_active() and str(handler.get_meta("police_place_id", "")).is_empty()
	if not usable:
		sees_player = false
		mode = "retire"
		_retire_time += delta
		_move(Vector3.ZERO, delta)
		if _retire_time > 3.0 and not director.point_on_screen(global_position): queue_free()
		return
	_retire_time = 0.0
	var target: Node3D = gameplay.pursuit_target()
	if _sensor <= 0.0:
		_sensor = 0.2
		sees_player = is_instance_valid(target) and target.visible and director.has_line_of_sight(self, target.global_position + Vector3.UP * 0.7, target, 23.0)
		if sees_player:
			last_known = target.global_position
			gameplay.report_contact(last_known)
		elif gameplay.last_known_valid: last_known = gameplay.last_known
	var restrained: bool = gameplay.police_surrendering()
	var force: bool = gameplay.police_force_authorized()
	var handler_near := global_position.distance_to(handler.global_position) <= HANDLER_RANGE
	var chase: bool = force and not restrained and handler_near and (sees_player or gameplay.last_known_valid)
	mode = "pursue" if chase and sees_player else ("search" if chase else "heel")
	var destination: Vector3 = last_known if chase else handler.global_position + handler.global_basis.x * 1.1
	if _repath <= 0.0:
		_repath = 1.3
		_path = gameplay.find_path(global_position, destination)
		_path_index = 0
	var next := destination
	if _path_index < _path.size():
		next = _path[_path_index]
		if global_position.distance_to(next) < 0.7: _path_index += 1
	var direction := next - global_position
	direction.y = 0.0
	var distance := global_position.distance_to(destination)
	var speed := 6.5 if chase else 3.8
	var movement := direction.normalized() * speed if distance > (1.0 if chase else 1.7) else Vector3.ZERO
	if movement.length_squared() > 0.01:
		# The full nose-to-rump collider turns with the dog, so the long model
		# cannot stick its head through a wall while a small central capsule passes.
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, delta * 12.0))
		# One support query per sensor tick prevents routing off bridge/tunnel edges.
		if _sensor >= 0.199:
			var support: Dictionary = director.ground_hit(global_position + movement.normalized() * 0.8, 0.65)
			_safe_step = not support.is_empty() and absf((support.position as Vector3).y - global_position.y) < 0.6
		if not _safe_step: movement = Vector3.ZERO; _repath = minf(_repath, 0.3)
	if chase and sees_player and _bark_timer <= 0.0:
		_bark_timer = 3.5
		bark.stream = BARKS[posmod(get_instance_id(), BARKS.size())]
		bark.play()
	if can_bite(target) and _cooldown <= 0.0:
		_cooldown = 1.4
		# K9 restrains; the bite cannot kill a critically wounded player.
		gameplay.damage_player(minf(8.0, maxf(0.0, float(gameplay.health) - 1.0)))
		if gameplay.has_method("police_k9_restraint"): gameplay.police_k9_restraint(1.2)
	_move(movement, delta)

func can_bite(target: Node3D) -> bool:
	if dead or withdrawing or not is_instance_valid(director) or not director.exterior_active(): return false
	if not is_instance_valid(handler) or handler.get("dead") == true or handler.is_queued_for_deletion(): return false
	if global_position.distance_to(handler.global_position) > HANDLER_RANGE: return false
	var gameplay: Node3D = director.gameplay
	if target != gameplay.player or gameplay.health <= 0.0: return false
	if not gameplay.police_force_authorized() or gameplay.police_surrendering(): return false
	if global_position.distance_to(target.global_position) > BITE_RANGE: return false
	return director.has_line_of_sight(self, target.global_position + Vector3.UP * 0.55, target, BITE_RANGE + 0.6)

func begin_withdrawal() -> void:
	withdrawing = true
	sees_player = false
	mode = "retire"

func _move(movement: Vector3, delta: float) -> void:
	if movement.length_squared() > 0.01: movement = _steering.steer(self, movement.normalized(), delta) * movement.length()
	velocity.x = movement.x
	velocity.z = movement.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	_gait += Vector2(velocity.x, velocity.z).length() * delta * 5.0
	for index in 4:
		var leg: Node3D = _rig.legs[index]
		leg.rotation.x = sin(_gait + (PI if index in [1, 2] else 0.0)) * 0.65 if movement.length_squared() > 0.01 else lerpf(leg.rotation.x, 0.0, minf(1.0, delta * 12.0))
	_rig.tail.rotation.y = sin(_gait * 0.45) * 0.18
	if _steering.stuck: _repath = 0.0

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0.0: return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		dead = true
		sees_player = false
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		visual.rotation.z = PI * 0.5
		visual.position.y = 0.1
		bark.stop()
		set_physics_process(false)
		get_tree().create_timer(12.0).timeout.connect(queue_free)
	if is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source():
		director.gameplay.report_vehicle_assault(self, source)
