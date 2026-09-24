extends CharacterBody3D

const VISUAL := preload("res://scripts/VehicleVisual.gd")
const MAX_SPEED := 15.0
const REVERSE_SPEED := 4.5
const WHEELBASE := 2.5
var paint_color := Color("d5a544")
var controlled := false
var traffic := false
var speed := 0.0
var steering := 0.0
var throttle_input := 0.0
var steer_input := 0.0
var brake_input := false
var external_input := false
var distance_travelled := 0.0
var visual: Node3D
var shape: CollisionShape3D
var wheels: Array[Node3D] = []
var wheel_spin := 0.0
var tail_material: StandardMaterial3D
var route: Curve3D
var route_distance := 0.0
var route_laps := 0
var blocked := false
var sensor_clock := 0.0
var sensor_shape := BoxShape3D.new()
var rotation_shape := BoxShape3D.new()

func _ready() -> void:
	collision_layer = 4
	collision_mask = 7
	floor_snap_length = 0.4
	shape = CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(2.08,1.4,4.6)
	shape.shape = hull
	shape.position.y = 0.7
	add_child(shape)
	rotation_shape.size = Vector3(2.08,1.15,4.6)
	sensor_shape.size = Vector3(2.15,1.2,1)
	visual = VISUAL.create(paint_color)
	visual.name = "Coupe"
	add_child(visual)
	var pivots: Dictionary = {}
	for part in visual.get_children():
		if str(part.get_meta("coupe_damage_material_key","")) == "tail":
			if tail_material == null: tail_material = part.material_override.duplicate()
			part.material_override = tail_material
		if part.has_meta("wheel_center"):
			var center: Vector3 = part.get_meta("wheel_center")
			if not pivots.has(center):
				var pivot := Node3D.new()
				pivot.position = center
				pivot.set_meta("front",center.z < 0)
				visual.add_child(pivot)
				pivots[center] = pivot
				wheels.append(pivot)
			part.reparent(pivots[center],false)
			part.position -= center

func _physics_process(delta: float) -> void:
	if traffic:
		_drive_traffic(delta)
	else:
		_drive_player(delta)
	var previous := global_position
	var forward := -global_basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	velocity.y = -1.0 if is_on_floor() else velocity.y-20.0*delta
	move_and_slide()
	var motion := global_position-previous
	motion.y = 0
	distance_travelled += motion.length()
	# Contact removes forward speed, instead of accumulating motion into a wall.
	if is_on_wall(): speed = motion.dot(forward)/maxf(delta,0.001)
	wheel_spin += motion.dot(forward)/0.355
	for pivot in wheels:
		pivot.rotation = Vector3(wheel_spin,steering if pivot.get_meta("front") else 0.0,0)
	if tail_material:
		tail_material.emission_energy_multiplier = 2.5 if brake_input or blocked else 0.65

func _drive_player(delta: float) -> void:
	if not external_input:
		throttle_input = 0
		steer_input = 0
		brake_input = false
		if controlled:
			throttle_input = float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			steer_input = float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))-float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			brake_input = Input.is_physical_key_pressed(KEY_SPACE)
	if not controlled: brake_input = true
	if brake_input:
		speed = move_toward(speed,0,14.0*delta)
	elif absf(throttle_input) > 0.01:
		var acceleration := 11.0 if speed*throttle_input < 0 else 5.0
		speed = clampf(speed+throttle_input*acceleration*delta,-REVERSE_SPEED,MAX_SPEED)
	else:
		speed = move_toward(speed,0,2.0*delta)
	steering = move_toward(steering,steer_input*0.48,delta*2.0)
	var turn := speed/WHEELBASE*tan(steering)*delta
	if absf(turn) > 0.0001 and can_rotate(rotation.y+turn): rotation.y += turn

func can_rotate(yaw: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rotation_shape
	query.transform = Transform3D(Basis(Vector3.UP,yaw),global_position+Vector3.UP*0.8)
	query.collision_mask = 7
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _drive_traffic(delta: float) -> void:
	if route == null: return
	sensor_clock -= delta
	if sensor_clock <= 0:
		sensor_clock = 0.1
		blocked = obstacle_ahead()
	speed = move_toward(speed,0.0 if blocked else 5.5,(12.0 if blocked else 2.5)*delta)
	# Progress uses actual position, so a collision cannot advance the car's route.
	var previous_distance := route_distance
	route_distance = route.get_closest_offset(global_position)
	if previous_distance > route.get_baked_length()-5 and route_distance < 5: route_laps += 1
	var target := route.sample_baked(fposmod(route_distance+3.5,route.get_baked_length()),true)
	var direction := target-global_position
	direction.y = 0
	var desired := atan2(-direction.x,-direction.z)
	var next_yaw := rotate_toward(rotation.y,desired,delta*1.7)
	steering = clampf(angle_difference(rotation.y,desired),-0.48,0.48)
	if can_rotate(next_yaw): rotation.y = next_yaw

func obstacle_ahead() -> bool:
	var length := 2.2+speed*speed/20.0
	sensor_shape.size.z = length
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sensor_shape
	query.transform = Transform3D(global_basis,global_position-global_basis.z*(2.3+length/2)+Vector3.UP*0.8)
	query.collision_mask = 7
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func place(point: Vector3, yaw: float) -> void:
	global_position = point
	rotation.y = yaw
	speed = 0
	velocity = Vector3.ZERO
	reset_physics_interpolation()

func camera_lookahead() -> Vector3:
	return -global_basis.z*clampf(speed*0.4,-2.0,6.0)
