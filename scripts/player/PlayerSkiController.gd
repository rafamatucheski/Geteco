class_name PlayerSkiController
extends Node

const MAX_SPEED := 455.0
const MIN_GLIDE_SPEED := 24.0
const GRAVITY_ACCEL := 118.0
const BRAKE_FORCE := 235.0
const SKI_VISUAL_NAME := "SkiEquipment"

var actor: CharacterBody2D
var heading := Vector2.UP
var falling := false
var fall_time := 0.0
var race_hold := false
var stored_weapon := "fists"
var visual_root: Node3D
var trail_left: Line2D
var trail_right: Line2D
var trail_clock := 0.0
var turn_stress := 0.0
var pose_rest: Array[Dictionary] = []
var poles: Array[Node3D] = []

func configure(player: CharacterBody2D) -> void:
	actor = player

func enter_skiing(initial_direction := Vector2.UP) -> bool:
	if is_instance_valid(actor) and actor.is_skiing: return true
	if not is_instance_valid(actor) or actor.get("ski_rental_active") != true or actor.get("ski_equipment_ready") != true or actor.get("current_outfit_id") != "dante_ski" or actor.is_dead:
		return false
	if actor.is_recovering or actor.is_control_disabled or actor.get("current_vehicle") != null: return false
	heading = initial_direction.normalized() if initial_direction.length_squared() > 0.01 else Vector2.UP
	stored_weapon = actor.active_weapon_id
	actor.active_weapon_id = "fists"
	actor._update_equipped_weapon_3d_mesh()
	actor.is_skiing = true
	actor.is_recovering = false
	falling = false
	race_hold = false
	actor.velocity = heading * maxf(MIN_GLIDE_SPEED, actor.velocity.length())
	sync_visuals()
	_ensure_trails()
	_clear_trails()
	return true

func leave_skiing() -> void:
	if not is_instance_valid(actor): return
	if not actor.is_skiing and not falling: return
	_restore_pose()
	actor.is_skiing = false
	actor.is_recovering = false
	falling = false
	race_hold = false
	actor.velocity = Vector2.ZERO
	actor.active_weapon_id = stored_weapon if actor.can_carry_weapon(stored_weapon) else "fists"
	actor._update_equipped_weapon_3d_mesh()
	if actor.has_method("_update_locomotion"):
		actor._update_locomotion(0.0, false, false)
	if actor.model_root:
		actor.model_root.rotation = Vector3.ZERO
	_set_visual_visibility(false)
	_clear_trails()
	turn_stress = 0.0

func _clear_trails() -> void:
	trail_clock = 0.0
	for line in [trail_left, trail_right]:
		if is_instance_valid(line): line.clear_points()

func physics_step(delta: float) -> void:
	if not is_instance_valid(actor) or actor.is_dead:
		return
	if actor.is_control_disabled or actor.is_in_dialogue:
		actor.velocity = Vector2.ZERO
		_apply_pose(0.0, 0.0)
		return
	if falling:
		_update_fall(delta)
		return
	if race_hold:
		actor.velocity = Vector2.ZERO
		_apply_pose(0.0, 0.0)
		return

	var game_input := actor.get_node("/root/GameInput")
	var input: Vector2 = game_input.movement()
	var downhill := _downhill_at_actor()
	var speed := actor.velocity.length()
	if speed < 1.0:
		heading = downhill
	var steer := input.x
	var brake := maxf(0.0, input.y)
	if Input.is_action_pressed("handbrake"):
		brake = 1.0
	var tuck := maxf(0.0, -input.y)
	var alignment := clampf(heading.dot(downhill), -0.35, 1.0)
	var acceleration := GRAVITY_ACCEL * maxf(0.12, alignment) + tuck * 42.0
	if Input.is_action_pressed("sprint") and speed < 115.0:
		acceleration += 95.0
	speed += acceleration * delta
	speed -= (18.0 + brake * BRAKE_FORCE) * delta
	speed = clampf(speed, 0.0, MAX_SPEED)

	var speed_factor := clampf(speed / MAX_SPEED, 0.0, 1.0)
	var turn_rate := lerpf(2.05, 0.88, speed_factor)
	heading = heading.rotated(steer * turn_rate * delta).normalized()
	# A borda do ski converte parte do movimento lateral em direção, sem
	# apagar a inércia que dá peso à descida.
	var desired_velocity := heading * speed
	actor.velocity = actor.velocity.lerp(desired_velocity, 1.0 - exp(-4.8 * delta))
	if actor.velocity.length() > MAX_SPEED:
		actor.velocity = actor.velocity.normalized() * MAX_SPEED
	var before := actor.velocity
	actor.move_and_slide()
	var strongest_impact := 0.0
	var impact_normal := Vector2.ZERO
	for i in actor.get_slide_collision_count():
		var hit := actor.get_slide_collision(i)
		var impact := maxf(0.0, before.dot(-hit.get_normal()))
		if impact > strongest_impact:
			strongest_impact = impact
			impact_normal = hit.get_normal()
	if strongest_impact > 112.0:
		crash(clampi(roundi((strongest_impact - 80.0) * 0.18), 6, 42), impact_normal * strongest_impact * 0.42)
		return
	if actor.velocity.length_squared() > 4.0:
		heading = actor.velocity.normalized()

	turn_stress = maxf(0.0, turn_stress - delta * 0.7)
	if absf(steer) > 0.86 and speed > 330.0:
		turn_stress += delta * (speed / 300.0)
	if turn_stress > 0.8:
		crash(clampi(roundi(speed * 0.045), 8, 24), -heading.orthogonal() * signf(steer) * speed * 0.22)
		turn_stress = 0.0
		return
	_apply_pose(speed_factor, steer)
	_update_trails(delta)

func crash(damage: int, impulse := Vector2.ZERO) -> void:
	if falling or not is_instance_valid(actor) or actor.is_dead: return
	falling = true
	fall_time = 1.15
	race_hold = false
	actor.is_recovering = true
	if impulse.length_squared() > 0.01:
		actor.velocity = impulse.limit_length(190.0)
	else:
		actor.velocity *= 0.34
	actor.take_damage(maxi(1, damage))
	if actor.is_dead: return
	var camera := actor.get_node_or_null("Camera")
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(clampf(float(damage) / 32.0, 0.18, 0.75))
	actor._show_weapon_notice("QUEDA NO SKI · -%d VIDA" % damage)

func sync_visuals() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(actor.model_root): return
	for old in actor.model_root.find_children(SKI_VISUAL_NAME, "Node3D", true, false):
		old.queue_free()
	if is_instance_valid(actor.head_node):
		var old_helmet: Node = actor.head_node.get_node_or_null("SkiHelmet")
		if old_helmet:
			actor.head_node.remove_child(old_helmet)
			old_helmet.queue_free()
	for pole in poles:
		if is_instance_valid(pole): pole.free()
	poles.clear()
	pose_rest.clear()
	for node in [actor.torso_node,actor.head_node,actor.left_upper_arm,actor.right_upper_arm,actor.left_upper_leg,actor.right_upper_leg,actor.left_lower_arm,actor.right_lower_arm,actor.left_lower_leg,actor.right_lower_leg]:
		if is_instance_valid(node): pose_rest.append({"node":node,"transform":node.transform})
	for leg in [actor.left_lower_leg,actor.right_lower_leg]:
		if is_instance_valid(leg) and leg.has_node("Foot"):
			var foot: Node3D = leg.get_node("Foot")
			pose_rest.append({"node":foot,"transform":foot.transform})
	visual_root = Node3D.new()
	visual_root.name = SKI_VISUAL_NAME
	actor.model_root.add_child(visual_root)
	var ski_red := _material(Color("b84238"), 0.68, 0.12)
	var steel := _material(Color("88979e"), 0.32, 0.75)
	var black := _material(Color("151b20"), 0.82)
	for side in [-1.0, 1.0]:
		var ski := _box(Vector3(side * 0.088, 0.035, 0.04), Vector3(0.095, 0.055, 1.72), ski_red)
		ski.name = "LeftSki" if side < 0 else "RightSki"
		visual_root.add_child(ski)
		var tip := _box(Vector3(side * 0.088, 0.105, -0.79), Vector3(0.095, 0.17, 0.22), ski_red)
		tip.rotation.x = -0.32
		visual_root.add_child(tip)
		visual_root.add_child(_box(Vector3(side * 0.088, 0.12, 0.06), Vector3(0.14, 0.11, 0.28), black))
		var pole := Node3D.new()
		pole.name = "SkiPole"
		var arm: Node3D = actor.left_lower_arm if side<0 else actor.right_lower_arm
		arm.add_child(pole)
		pole.position = Vector3(0,-.20,0)
		pole.add_child(_cylinder(Vector3(0,-.43,0),.011,.86,steel))
		pole.add_child(_cylinder(Vector3(0,-.79,0),.045,.012,black))
		poles.append(pole)

	# Capacete e óculos seguem a cabeça articulada.
	if is_instance_valid(actor.head_node):
		var helmet_root := Node3D.new()
		helmet_root.name = "SkiHelmet"
		actor.head_node.add_child(helmet_root)
		var helmet := _sphere(Vector3(0, 0.075, 0.01), Vector3(0.285, 0.22, 0.26), black)
		helmet_root.add_child(helmet)
		var goggles := _box(Vector3(0, 0.015, -0.18), Vector3(0.20, 0.07, 0.035), _material(Color("65b9d1"), 0.12, 0.28))
		helmet_root.add_child(goggles)
	_set_visual_visibility(actor.is_skiing)

func _set_visual_visibility(value: bool) -> void:
	if is_instance_valid(visual_root): visual_root.visible = value
	for pole in poles:
		if is_instance_valid(pole): pole.visible = value
	if is_instance_valid(actor) and is_instance_valid(actor.head_node):
		var helmet: Node = actor.head_node.get_node_or_null("SkiHelmet")
		if helmet: helmet.visible = value

func _restore_pose() -> void:
	for state in pose_rest:
		if is_instance_valid(state.node): state.node.transform = state.transform

func _apply_pose(speed_factor: float, steer: float) -> void:
	if not is_instance_valid(actor.model_root): return
	_restore_pose()
	var yaw := -heading.angle() - PI * .5
	actor.model_root.rotation = Vector3(0,yaw,0)
	var bend := .26 + speed_factor*.50
	for upper in [actor.left_upper_leg,actor.right_upper_leg]: upper.rotation.x = bend
	for lower in [actor.left_lower_leg,actor.right_lower_leg]:
		lower.rotation.x = -bend*1.65
		if lower.has_node("Foot"): lower.get_node("Foot").rotation.x = bend*.65
	var sole: Vector3 = actor.left_upper_leg.transform * actor.left_lower_leg.transform * Vector3(0,-.33,0)
	var offset := Vector3(0,.08-sole.y,-sole.z)
	for node in [actor.torso_node,actor.head_node,actor.left_upper_arm,actor.right_upper_arm,actor.left_upper_leg,actor.right_upper_leg]:
		node.position += offset
	actor.torso_node.rotation = Vector3(-.12-speed_factor*.22,0,-steer*.10)
	actor.head_node.position.z -= .07+speed_factor*.06
	actor.left_upper_arm.rotation = Vector3(.20,0,-.12)
	actor.right_upper_arm.rotation = Vector3(.20,0,.12)
	for arm in [actor.left_lower_arm,actor.right_lower_arm]: arm.rotation.x = .9
	for pole in poles:
		if is_instance_valid(pole): pole.rotation.x = -1.4

func _update_fall(delta: float) -> void:
	fall_time -= delta
	actor.velocity = actor.velocity.move_toward(Vector2.ZERO, 210.0 * delta)
	actor.move_and_slide()
	if actor.model_root:
		actor.model_root.rotation.x = lerpf(actor.model_root.rotation.x, PI * 0.48, minf(1.0, delta * 8.0))
		actor.model_root.rotation.z = lerpf(actor.model_root.rotation.z, 1.05, minf(1.0, delta * 7.0))
	if fall_time > 0.0: return
	falling = false
	actor.is_recovering = false
	heading = _downhill_at_actor()
	actor.velocity = heading * MIN_GLIDE_SPEED
	_apply_pose(0.05, 0.0)

func _downhill_at_actor() -> Vector2:
	for area in actor.get_tree().get_nodes_in_group("mountain_ski_area"):
		if area.has_method("downhill_at"):
			return area.downhill_at(actor.global_position)
	return Vector2.UP

func _ensure_trails() -> void:
	if is_instance_valid(trail_left) and is_instance_valid(trail_right): return
	var parent := actor.get_parent()
	for side in [-1.0, 1.0]:
		var line := Line2D.new()
		line.name = "PlayerSkiTrackLeft" if side < 0 else "PlayerSkiTrackRight"
		line.width = 1.4
		line.default_color = Color(0.35, 0.45, 0.50, 0.38)
		line.z_index = 1
		parent.add_child(line)
		line.global_position = Vector2.ZERO
		if side < 0: trail_left = line
		else: trail_right = line

func _update_trails(delta: float) -> void:
	trail_clock += delta
	if trail_clock < 0.055 or not is_instance_valid(trail_left): return
	var sample_delta := trail_clock
	trail_clock = 0.0
	var lateral := heading.orthogonal() * 3.0
	for entry in [[trail_left, -lateral], [trail_right, lateral]]:
		var line: Line2D = entry[0]
		# Respawns and transport must not draw a track across the map.
		if line.get_point_count() > 0 and line.to_global(line.get_point_position(line.get_point_count() - 1)).distance_to(actor.global_position) > MAX_SPEED * sample_delta + 16.0:
			line.clear_points()
		line.add_point(line.to_local(actor.global_position + entry[1]))
		while line.get_point_count() > 100:
			line.remove_point(0)

func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _box(point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = point
	return node

func _cylinder(point: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = material
	node.position = point
	return node

func _sphere(point: Vector3, scale_value: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 8
	node.mesh = mesh
	node.scale = scale_value
	node.position = point
	node.material_override = material
	return node
