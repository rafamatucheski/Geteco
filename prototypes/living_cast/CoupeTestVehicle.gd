extends CharacterBody3D

const MODEL := preload("res://prototypes/living_cast/CoupeDamageModel.gd")
var model: Node3D
var headlights: Array[SpotLight3D] = []
var brake_lights: Array[OmniLight3D] = []
var speed := 0.0
var health := 100.0
var throttle := 0.0
var steering := 0.0
var braking := false
var manual_input := true
var light_mode := 1 # off / dipped / main
var collision_count := 0
var last_hit := Vector3.ZERO
var impact_cooldown := 0.0
var debris: Array[Node] = []
var front_bumper: MeshInstance3D
var wheel_pivots: Array[Node3D] = []
var wheel_spinners: Array[Node3D] = []

func _ready() -> void:
	model = MODEL.new()
	add_child(model)
	for side in [-1.0,1.0]:
		for wheel_z in [-1.28,1.22]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side*0.86,0.36,wheel_z)
			model.add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			for node in model.get_children():
				if node is MeshInstance3D and node.position.x*side >= 0.85 and node.position.y < 0.75 and absf(node.position.z-wheel_z) < 0.36 and node.material_override != model.paint:
					node.reparent(spin,true)
			wheel_pivots.append(pivot)
			wheel_spinners.append(spin)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.82,0.95,4.46)
	shape.shape = box
	shape.position.y = 0.62
	add_child(shape)
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	for side in [-1.0,1.0]:
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(side*0.67,0.81,-1.83)
		lamp.rotation_degrees.x = -7
		lamp.light_color = Color("e3ecff")
		lamp.shadow_enabled = true
		lamp.spot_attenuation = 0.6
		add_child(lamp)
		headlights.append(lamp)
		var tail := OmniLight3D.new()
		tail.position = Vector3(side*0.65,0.65,2.32)
		tail.light_color = Color("ff2520")
		tail.omni_range = 2.0
		add_child(tail)
		brake_lights.append(tail)
	for node in model.get_children():
		if node is MeshInstance3D and node.position.is_equal_approx(Vector3(0,0.41,-2.241)):
			front_bumper = node
	update_lights()

func _physics_process(delta: float) -> void:
	if manual_input:
		throttle = float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		steering = float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D))
		braking = Input.is_physical_key_pressed(KEY_SPACE)
	impact_cooldown = maxf(0,impact_cooldown-delta)
	var engine_factor := lerpf(0.3,1.0,health/100.0)
	if braking: speed = move_toward(speed,0,20*delta)
	elif absf(throttle) > 0:
		speed = move_toward(speed,throttle * (18.0 if throttle > 0 else 6.0) * engine_factor,7*delta)
	else: speed = move_toward(speed,0,2*delta)
	rotate_y(steering * clampf(speed/7.0,-1.0,1.0) * 1.15 * delta)
	velocity = -global_basis.z * speed
	for i in wheel_pivots.size():
		if i % 2 == 0: wheel_pivots[i].rotation.y = lerpf(wheel_pivots[i].rotation.y,steering*0.35,minf(1,delta*10))
		wheel_spinners[i].rotation.x -= speed / 0.355 * delta
	model.rotation.z = lerpf(model.rotation.z,0,minf(1,delta*9))
	var incoming := velocity
	move_and_slide()
	for i in get_slide_collision_count():
		var contact := get_slide_collision(i)
		var normal := contact.get_normal()
		var force := maxf(0,-incoming.dot(normal))
		if force > 2.5 and impact_cooldown <= 0:
			last_hit = contact.get_position()
			model.apply_impact(model.to_local(last_hit),global_basis.inverse()*normal,force)
			health = maxf(0,health-force*2.2)
			collision_count += 1
			impact_cooldown = 0.35
			model.rotation.z = clampf(normal.dot(global_basis.x)*force*0.008,-0.09,0.09)
			if force >= 10 and model.to_local(last_hit).z < -1.2 and not model.detached: detach_piece(normal)
			speed *= -0.12
			break
	update_lights()

func update_lights() -> void:
	for i in headlights.size():
		headlights[i].visible = light_mode > 0 and not model.broken_lamps[i]
		headlights[i].spot_range = 32.0 if light_mode == 2 else 19.0
		headlights[i].spot_angle = 24.0 if light_mode == 2 else 36.0
		headlights[i].light_energy = 5.0 if light_mode == 2 else 3.0
	for tail in brake_lights: tail.light_energy = 2.0 if braking else (0.35 if light_mode > 0 else 0.0)
	if model.materials.has("tail"):
		model.materials["tail"].emission_energy_multiplier = 2.5 if braking else 0.45

func detach_piece(normal: Vector3) -> void:
	model.detached = true
	if front_bumper == null: return
	var body := RigidBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 1
	get_parent().add_child(body)
	body.global_transform = front_bumper.global_transform
	var visible_piece := MeshInstance3D.new()
	visible_piece.mesh = front_bumper.mesh
	visible_piece.material_override = front_bumper.material_override
	body.add_child(visible_piece)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.55,0.095,0.025)
	shape.shape = box
	body.add_child(shape)
	body.apply_central_impulse(normal * 2.0 + Vector3.UP * 2.0)
	body.angular_velocity = Vector3(2,1,3)
	front_bumper.hide()
	debris.append(body)

func reset_vehicle() -> void:
	speed = 0
	velocity = Vector3.ZERO
	health = 100
	model.repair()
	model.rotation = Vector3.ZERO
	collision_count = 0
	impact_cooldown = 0
	if front_bumper: front_bumper.show()
	for node in debris:
		if is_instance_valid(node): node.queue_free()
	debris.clear()
	update_lights()
