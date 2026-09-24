extends CharacterBody3D
## Lightweight physical actor for cemetery-only routines. It deliberately does
## not implement combat/damage; that contract belongs to the combat front.

signal route_finished
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
	route = points
	route_index = 0
	activity = "walk" if not route.is_empty() else "idle"

func say(text: String, duration := 8.0) -> void:
	if not is_instance_valid(speech): return
	speech.text = text
	speech_left = duration
	speech.show()

func set_working(value: bool) -> void:
	activity = "work" if value else "idle"

func finished() -> bool:
	return route_index >= route.size()

func _physics_process(delta: float) -> void:
	if speech_left > 0:
		speech_left = maxf(0,speech_left-delta)
		if speech_left == 0: speech.hide()
	var direction := Vector3.ZERO
	if route_index < route.size():
		var offset: Vector3 = route[route_index]-global_position
		offset.y = 0
		if offset.length() < .32:
			route_index += 1
			if route_index >= route.size():
				activity = "idle"
				route_finished.emit()
		else:
			direction = offset.normalized()
			activity = "walk"
	velocity.x = direction.x * (2.0 if role != "mourner" else 1.45)
	velocity.z = direction.z * (2.0 if role != "mourner" else 1.45)
	velocity.y = -1.0 if is_on_floor() else velocity.y-20.0*delta
	move_and_slide()
	if direction.length_squared() > .01:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(-direction.x,-direction.z),1.0-exp(-10.0*delta))
		gait += delta * 7.0
	_animate(direction.length_squared() > .01)

func _animate(walking: bool) -> void:
	if role == "mortician":
		visual.left_upper_leg.rotation.x = sin(gait)*(.45 if walking else 0.0)
		visual.right_upper_leg.rotation.x = -sin(gait)*(.45 if walking else 0.0)
		if is_instance_valid(visual.stretcher_mesh):
			visual.stretcher_mesh.visible = activity in ["walk","work"]
			visual.body_bag_mesh.visible = visual.stretcher_mesh.visible
	else:
		var swing := sin(gait)*(.38 if walking else .0)
		visual.left_upper_arm.rotation.x = swing
		visual.right_upper_arm.rotation.x = -swing
		if activity == "work":
			visual.left_upper_arm.rotation.x = .65+sin(gait*.55)*.18
			visual.right_upper_arm.rotation.x = .65-sin(gait*.55)*.18
