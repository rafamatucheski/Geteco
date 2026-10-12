extends CharacterBody3D
const MODEL := preload("res://world/places/sewers/SewerResidentCombatModel.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
var definition: Dictionary
var ecosystem: Node
var gameplay: Node
var visual: Node3D
var health := 90.0
var dead := false
var hostile := false
var warned := false
var weapon_id := "fists"
var target: Node3D
var attacks := 0
var _cooldown := .9
var _repath := 0.0
var _path := PackedVector3Array()
var _waypoint := 0
var _windup := -1.0
var _warning: Label3D
var _warning_left := 0.0
var _steering := preload("res://gameplay/crowd/PedestrianSteering.gd").new()

func _ready() -> void:
	name = str(definition.id)
	set_meta("interior_npc_id", definition.id)
	set_meta("character_name", definition.name)
	set_meta("gameplay_role", "sewer_resident")
	add_to_group("v2_damageable")
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.75
	collider.shape = capsule
	collider.position.y = .88
	add_child(collider)
	visual = MODEL.new()
	visual.character_name = str(definition.name)
	visual.weapon_id = weapon_id
	visual.appearance_locked = true
	for key in definition.get("appearance", {}): visual.set(key, definition.appearance[key])
	add_child(visual)
	preload("res://audio/VoiceActorBinding.gd").bind_sewer(self, str(definition.name))
	_warning = Label3D.new()
	_warning.position.y = 2.05
	_warning.text = "PARE!"
	_warning.font_size = 48
	_warning.pixel_size = .006
	_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_warning.modulate = Color("ffd280")
	_warning.hide()
	add_child(_warning)

func engage(source: Node3D) -> void:
	if dead or hostile: return
	hostile = true
	target = source
	set_meta("workplace_threatened", true)
	_warning.hide()
	_warning_left = 0
	visual.set_armed(true)
	_cooldown = .75

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0 or PROTECTION.is_protected(self): return
	health = maxf(0, health-amount)
	var impact: Vector3 = global_position-source.global_position if source is Node3D else Vector3.ZERO
	# Only a player's bare-handed blow earns a warning. Blades, fire and bullets escalate immediately.
	if source == gameplay.player and ecosystem.active():
		var bare_hands: bool = gameplay.equipped() in ["", "fists"] and amount <= 12.0
		if bare_hands and not warned and not hostile and health > 0:
			warned = true
			_warning_left = 2.5
			_warning.show()
			var binding := preload("res://audio/VoiceActorBinding.gd").resolve(self, "", "sewer_warning")
			var spoken := preload("res://audio/ActorDialogueVoice.gd").speak(self, "PARE!", binding, _warning)
			_warning.text = str(spoken.get("message", "PARE!"))
			_warning_left = maxf(_warning_left, float(spoken.get("duration", 0.0)))
		else:
			ecosystem.provoke(self, source)
	if health > 0:
		visual.take_hit(impact, clampf(amount/40, .1, 1))
		return
	dead = true
	preload("res://audio/ActorDialogueVoice.gd").stop(self)
	hostile = false
	_windup = -1
	_warning.hide()
	set_meta("workplace_threatened", true)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	visual.set_armed(false)
	visual.hand_provider = Callable()
	if has_meta("v2_burning"): preload("res://gameplay/BurningActor.gd").char_body(self)
	preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self, visual, impact)

func can_see(actor: Node3D) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*1.1, actor.global_position+Vector3.UP, 7, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.collider == actor

func _physics_process(delta: float) -> void:
	if dead: return
	if not is_instance_valid(ecosystem) or not ecosystem.active():
		velocity = Vector3.ZERO
		_windup = -1
		return
	_warning_left = maxf(0, _warning_left-delta)
	if _warning_left <= 0 and _warning.visible:
		_warning_left = preload("res://audio/ActorDialogueVoice.gd").remaining_for(_warning)
	_warning.visible = _warning_left > 0
	_cooldown = maxf(0, _cooldown-delta)
	var movement := Vector3.ZERO
	if hostile and is_instance_valid(target):
		var offset := target.global_position-global_position
		offset.y = 0
		var distance := offset.length()
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(offset.x, offset.z), 1-exp(-12*delta))
		var ranged := weapon_id == "pistol"
		var reach := 14.0 if ranged else 1.4
		var sight := can_see(target)
		if _windup >= 0:
			_windup -= delta
			if _windup < 0 and distance <= reach and sight: _hit_target()
		elif distance <= reach and sight and _cooldown <= 0:
			visual.attack()
			_windup = .22 if ranged else .28
			_cooldown = 1.5 if ranged else .95
		if _windup < 0 and (distance > (5.0 if ranged else 1.1) or not sight):
			_repath -= delta
			if _repath <= 0:
				_repath = .8
				_path = ecosystem.path(global_position, target.global_position)
				_waypoint = 0
			while _waypoint < _path.size() and global_position.distance_to(_path[_waypoint]) < .3: _waypoint += 1
			if _waypoint < _path.size():
				movement = _path[_waypoint]-global_position
				movement.y = 0
				movement = _steering.steer(self, movement.normalized(), delta)*2.3
	velocity.x = movement.x
	velocity.z = movement.z
	velocity.y = -1.0 if is_on_floor() else maxf(-18, velocity.y-20*delta)
	move_and_slide()

func _hit_target() -> void:
	if gameplay.health <= 0 or target.input_locked: return
	attacks += 1
	var damage: float = {"fists": 8.0, "knife": 17.0, "bottle": 13.0, "claw": 12.0, "pistol": 14.0}.get(weapon_id, 8.0)
	if weapon_id == "pistol":
		var origin: Vector3 = visual.muzzle_position()
		var ray := PhysicsRayQueryParameters3D.create(origin, target.global_position+Vector3.UP, 7, [get_rid()])
		ray.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.collider != target: return
		visual.fire()
		gameplay._trace(origin, hit.position, .08, .012)
		gameplay._sound("pistol", origin)
		gameplay.npc_gunfire.emit(origin, (hit.position-origin).normalized(), self)
	else:
		gameplay._sound("knife" if weapon_id in ["knife", "bottle", "claw"] else "fists", global_position)
	gameplay.damage_player(damage, global_position)
