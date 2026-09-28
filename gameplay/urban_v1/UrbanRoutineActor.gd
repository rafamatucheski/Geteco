extends CharacterBody3D
## Cemetery-only actor. Shares the native combat contract, never garage actors.

signal route_finished
signal died(actor: CharacterBody3D)
signal threatened(actor: CharacterBody3D)
var health := 100.0
var dead := false
var frightened := false
var departure_delay := 0.0
var carrying_body := true
var attention := Vector3.ZERO
var has_attention := false
var gameplay: Node
var role := "resident"
var display_name := "Morador"
var visual: Node3D
var route := PackedVector3Array()
var route_index := 0
var activity := "idle"
var gait := 0.0
var speech: Label3D
var speech_left := 0.0
var shirt_override := Color.TRANSPARENT

func configure(next_role: String, next_name: String, next_shirt_override := Color.TRANSPARENT) -> void:
	role = next_role
	display_name = next_name
	shirt_override = next_shirt_override
	name = next_name.validate_node_name()
	set_meta("gameplay_role","urban_routine")
	set_meta("persistent_id","cemetery_"+next_role)

func _ready() -> void:
	add_to_group("v2_damageable")
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	collision.shape = capsule
	collision.position.y = .86
	add_child(collision)
	if role == "mortician":
		visual = preload("res://gameplay/emergency/MorticianModel.gd").new()
		visual.is_stretcher_bearer = true
	else:
		visual = preload("res://world/places/ServiceResidentModel.gd").new()
		visual.character_name = display_name
		visual.is_female = role == "mourner" and display_name in ["Lúcia", "Marta"]
		visual.shirt_color = shirt_override if shirt_override.a > 0.0 else (Color("343543") if role == "mourner" else Color("514b43"))
		visual.pants_color = Color("252b2d")
		visual.skin_color = Color("ad8063")
		visual.has_hat = role == "keeper"
		visual.hat_color = Color("3d4038")
	add_child(visual)
	visual.rotation.y = PI
	speech = Label3D.new()
	speech.position = Vector3(0,2.15,0)
	speech.font_size = 34
	speech.outline_size = 8
	speech.modulate = Color("eee4cf")
	speech.no_depth_test = true
	speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	speech.hide()
	add_child(speech)

func set_route(points: PackedVector3Array) -> void:
	if dead: return
	route = points
	route_index = 0
	activity = "walk" if not route.is_empty() else "idle"

func say(text: String, duration := 8.0) -> void:
	if dead or frightened: return
	if not is_instance_valid(speech): return
	speech.text = text
	speech_left = duration
	speech.show()

func set_working(value: bool) -> void:
	if dead or frightened: return
	activity = "work" if value else "idle"

func finished() -> bool:
	return route_index >= route.size()

func _physics_process(delta: float) -> void:
	if dead: return
	if speech_left > 0:
		speech_left = maxf(0,speech_left-delta)
		if speech_left == 0: speech.hide()
	var direction := Vector3.ZERO
	departure_delay = maxf(0.0, departure_delay - delta)
	if route_index < route.size() and departure_delay == 0.0:
		var offset: Vector3 = route[route_index]-global_position
		offset.y = 0
		# .20 m arrival slack leaves clearance between .30 m capsules on the
		# cemetery's .85 m lanes, without backing into the following visitor.
		if offset.length() < .20:
			route_index += 1
			if route_index >= route.size():
				activity = "idle"
				route_finished.emit()
		else:
			direction = offset.normalized()
			activity = "walk"
	var pace := 3.1 if frightened else (2.0 if role != "mourner" else 1.45)
	velocity.x = direction.x * pace
	velocity.z = direction.z * pace
	velocity.y = -1.0 if is_on_floor() else velocity.y-20.0*delta
	move_and_slide()
	if direction.length_squared() > .01:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(-direction.x,-direction.z),1.0-exp(-10.0*delta))
	elif has_attention and not frightened:
		var facing := attention - global_position
		if Vector2(facing.x, facing.z).length_squared() > .01:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-facing.x,-facing.z), 1.0-exp(-4.0*delta))
	gait += delta * 7.0
	_animate(direction.length_squared() > .01)

func bind_combat(owner_gameplay: Node) -> void:
	gameplay = owner_gameplay
	if not is_instance_valid(gameplay): return
	gameplay.weapon_fired.connect(_weapon_fired)
	gameplay.npc_gunfire.connect(_npc_gunfire)
	gameplay.explosion_occurred.connect(_explosion)

func _weapon_fired(weapon_id: String, origin: Vector3) -> void:
	if weapon_id in ["fists", "grenade"]: return
	var data: Dictionary = gameplay.weapon_data(weapon_id)
	notice_threat(origin, 13.0 if data.get("suppressed", false) else 30.0)

func _npc_gunfire(origin: Vector3, _direction: Vector3, _shooter: Node3D) -> void:
	notice_threat(origin, 30.0)

func _explosion(origin: Vector3, radius: float, _source: Node) -> void:
	notice_threat(origin, maxf(30.0, radius * 2.0))

func notice_threat(origin: Vector3, radius: float) -> void:
	if dead or global_position.distance_squared_to(origin) > radius * radius: return
	frightened = true
	departure_delay = 0.0
	speech.hide()
	threatened.emit(self)

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0.0: return
	health = maxf(0.0, health - amount)
	if health == 0.0:
		dead = true
		activity = "dead"
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		speech.hide()
		if has_meta("v2_burning"): preload("res://gameplay/BurningActor.gd").char_body(self)
		var impact: Vector3 = global_position - source.global_position if source is Node3D else Vector3.ZERO
		preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self, visual, impact)
		died.emit(self)
	else:
		notice_threat(global_position, 1.0)
	if is_instance_valid(gameplay):
		if is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source():
			gameplay.report_vehicle_assault(self, source)
		if is_instance_valid(gameplay.emergency): gameplay.emergency.report_injury(self, dead)

func recover_from_injury() -> void:
	if not dead: health = 100.0

func _animate(walking: bool) -> void:
	if role == "mortician":
		visual.left_upper_leg.rotation.x = sin(gait)*(.45 if walking else 0.0)
		visual.right_upper_leg.rotation.x = -sin(gait)*(.45 if walking else 0.0)
		if is_instance_valid(visual.stretcher_mesh):
			visual.stretcher_mesh.visible = not frightened and activity in ["walk","work"]
			visual.body_bag_mesh.visible = visual.stretcher_mesh.visible and carrying_body
	else:
		var swing := sin(gait)*(.38 if walking else .0)
		visual.left_upper_arm.rotation.x = swing
		visual.right_upper_arm.rotation.x = -swing
		if activity == "work":
			visual.left_upper_arm.rotation.x = .65+sin(gait*.55)*.18
			visual.right_upper_arm.rotation.x = .65-sin(gait*.55)*.18
		var body: Node3D = visual.get_meta("rig_body") if visual.has_meta("rig_body") else null
		if is_instance_valid(body):
			body.activity = "talk" if speech.visible else ""
			if not body.hand_provider.is_valid(): body.hand_provider = _work_hands

func _work_hands() -> Array:
	if dead or frightened or activity != "work": return [null, null]
	return [visual.to_global(Vector3(-.24, .9 + sin(gait*.55)*.06, -.35)), visual.to_global(Vector3(.24, .9 - sin(gait*.55)*.06, -.35))]
