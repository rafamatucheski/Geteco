extends CharacterBody3D

const DANTE := preload("res://assets/dante.glb")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
var is_player := false
var identity := 0
var camera: Camera3D
var visual: Node3D
var animation: AnimationPlayer
var skeleton: Skeleton3D
var hips := -1
var hip_rest := Vector3.ZERO
var route := PackedVector3Array()
var waypoint := 0
var speed := 1.6
var automatic_direction := Vector3.ZERO
var controlled_automatically := false
var travelled := 0.0
var phase := 0.0
var last_position := Vector3.ZERO

func _ready() -> void:
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.86
	add_child(shape)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	if is_player:
		var model := DANTE.instantiate() as Node3D
		model.scale = Vector3.ONE * 1.03
		model.rotation.y = PI
		visual.add_child(model)
		animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton:
			hips = skeleton.find_bone("Hips")
			if hips >= 0: hip_rest = skeleton.get_bone_rest(hips).origin
		if animation:
			animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	else:
		var model := CIVILIAN.new()
		model.appearance_locked = true
		model.appearance_variant = identity
		model.coat_color = [Color("426c70"), Color("a35d42"), Color("d3c3a1"), Color("42556f"), Color("8e5362"), Color("70835d")][identity % 6]
		model.pants_color = [Color("293849"), Color("484644"), Color("615342")][identity % 3]
		model.rotation.y = PI
		visual.add_child(model)
	last_position = global_position

func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	var target_speed := speed
	if controlled_automatically:
		direction = automatic_direction
	elif is_player:
		var axis := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if camera:
			var right := camera.global_basis.x
			var back := camera.global_basis.z
			right.y = 0
			back.y = 0
			direction = (right.normalized() * axis.x + back.normalized() * axis.y).limit_length()
		target_speed = 6.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 3.5
	elif route.size() > 1:
		var offset := route[waypoint] - global_position
		offset.y = 0
		if offset.length() < 0.4:
			waypoint = (waypoint + 1) % route.size()
			offset = route[waypoint] - global_position
			offset.y = 0
		direction = offset.normalized()
	velocity.x = direction.x * target_speed
	velocity.z = direction.z * target_speed
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	var displacement := global_position - last_position
	displacement.y = 0
	travelled += displacement.length()
	var actual_speed := displacement.length() / maxf(delta, 0.001)
	last_position = global_position
	if direction.length_squared() > 0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-14.0 * delta))
	if animation:
		var clip := "Running" if target_speed > 4.0 else "Walking"
		var anim := animation.get_animation(clip)
		phase = fposmod(phase + displacement.length() / (3.4 if clip == "Running" else 1.8), 1.0)
		animation.play(clip)
		animation.seek(0.067 + phase * maxf(0.01, anim.length - 0.067), true)
		if hips >= 0:
			var hip_position := skeleton.get_bone_pose_position(hips)
			hip_position.x = hip_rest.x
			hip_position.z = hip_rest.z
			skeleton.set_bone_pose_position(hips, hip_position)
	else:
		visual.get_child(0).walking = actual_speed > 0.1

func teleport(point: Vector3) -> void:
	global_position = point
	last_position = point
	velocity = Vector3.ZERO
	reset_physics_interpolation()
