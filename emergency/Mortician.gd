class_name Mortician
extends CharacterBody2D

## Agente Funerário do IML / Necrotério
## Responsável por recolher corpos mortos em sacos de cadáver (body bag) e transportá-los ao Rabecão.

enum State { DISEMBARK, APPROACH, BAG_AND_LIFT, RETURN_HEARSE, EMBARKING, EMBARKED }

@export var speed: float = 110.0
@export var max_health: int = 60
@export var is_stretcher_bearer: bool = false

var target: Node2D = null
var hearse: Node2D = null
var state: State = State.APPROACH
## Second leg of a coroner run: the body was already picked up (target is
## gone), this legist just needs to walk to burial_position and place a
## marker there. See EmergencyVehicle.gd's _deploy_morticians_for_burial().
var is_burial_trip: bool = false
var burial_position: Vector2 = Vector2.ZERO

var health: int = 60
var is_dead: bool = false
var fall_presentation := preload("res://CharacterFallPresentation.gd").new()
var is_flying: bool = false
var fly_velocity: Vector2 = Vector2.ZERO
var walk_clock: float = 0.0

var collision_shape: CollisionShape2D
var bag_timer: float = 0.0
var crew_side := 1.0
var crew_longitudinal := 22.0
var boarding_started := false
var _burial_gate_passed := false
var _burial_return_gate_passed := false
var _access_route: Array[Vector2] = []
var _access_index := 0
var _return_route: Array[Vector2] = []
var _return_index := 0
var _passing_point := Vector2.INF

# 3D SubViewport Rig
var viewport_3d: SubViewport
var sprite_3d_display: Sprite2D
var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var left_upper_leg: Node3D
var left_lower_leg: Node3D
var right_upper_leg: Node3D
var right_lower_leg: Node3D
var stretcher_mesh: MeshInstance3D = null
var body_bag_mesh: MeshInstance3D = null

func _ready() -> void:
	if not has_meta("medical_identity"):
		set_meta("medical_identity",get_node("/root/CoronerCare").next_staff_identity())
	set_collision_mask_value(3, true)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	if is_instance_valid(hearse): add_collision_exception_with(hearse)
	add_to_group("mortician")
	add_to_group("damageable")
	health = max_health
	z_index = 6
	
	_build_3d_viewport()
	preload("res://world/shared/pedestrians/CitizenDetails.gd").finish_rig(self, "mortician")
	
	var col := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 5.0
	cap.height = 16.0
	col.shape = cap
	collision_shape = col
	add_child(col)

func _build_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(96, 96)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_3d.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS

	var world_3d := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 1.15
	world_3d.environment = env
	viewport_3d.world_3d = world_3d
	add_child(viewport_3d)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.2, 1.4)
	cam.fov = 30.0
	cam.current = true
	viewport_3d.add_child(cam)
	cam.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	var key_light := DirectionalLight3D.new()
	key_light.position = Vector3(5.0, 12.0, 5.0)
	key_light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	key_light.light_color = Color(1.0, 0.98, 0.94)
	key_light.light_energy = 1.35
	viewport_3d.add_child(key_light)
	preload("res://systems/ContactShadow.gd").add_person(viewport_3d)

	_build_mortician_rig()

	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.name = "Sprite3DDisplay"
	sprite_3d_display.texture = viewport_3d.get_texture()
	# Mesma escala de apresentação da equipe de paramédicos.
	sprite_3d_display.scale = Vector2(0.38, 0.38)
	sprite_3d_display.position = Vector2.ZERO
	add_child(sprite_3d_display)

func _build_mortician_rig() -> void:
	model_root = Node3D.new()
	model_root.name = "MorticianRig"
	viewport_3d.add_child(model_root)

	var mat_suit := _make_mat(Color(0.14, 0.15, 0.18), 0.5) # Terno Chumbo/Preto IML
	var mat_shirt := _make_mat(Color(0.92, 0.94, 0.96), 0.3) # Camisa Social Branca
	var mat_tie := _make_mat(Color(0.05, 0.05, 0.06), 0.7) # Gravata Preta
	var mat_skin := _make_mat(Color(0.88, 0.74, 0.62), 0.4) # Pele
	var mat_gloves := _make_mat(Color(0.22, 0.48, 0.88), 0.2) # Luvas Cirúrgicas Azuis
	var mat_shoes := _make_mat(Color(0.06, 0.06, 0.08), 0.8) # Sapatos Pretos

	# Tronco (Paletó Preto)
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.75, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := MeshInstance3D.new()
	var box_t := BoxMesh.new()
	box_t.size = Vector3(0.38, 0.52, 0.22)
	torso_mesh.mesh = box_t
	torso_mesh.material_override = mat_suit
	torso_node.add_child(torso_mesh)

	# Gravata & Colarinho
	var tie_mesh := MeshInstance3D.new()
	var box_tie := BoxMesh.new()
	box_tie.size = Vector3(0.08, 0.28, 0.03)
	tie_mesh.mesh = box_tie
	tie_mesh.material_override = mat_tie
	tie_mesh.position = Vector3(0.0, 0.08, -0.12)
	torso_node.add_child(tie_mesh)

	# Cabeça
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.22, 0.0)
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.16
	sph_h.height = 0.32
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	# Óculos / Máscara Protetora
	var mask_mesh := MeshInstance3D.new()
	var box_m := BoxMesh.new()
	box_m.size = Vector3(0.18, 0.09, 0.06)
	mask_mesh.mesh = box_m
	mask_mesh.material_override = _make_mat(Color(0.85, 0.90, 0.95), 0.1)
	mask_mesh.position = Vector3(0.0, -0.04, -0.14)
	head_node.add_child(mask_mesh)

	# Braços (com luvas cirúrgicas)
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.24, 1.02, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_suit, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.044, 0.18, mat_gloves, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.24, 1.02, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_suit, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.044, 0.18, mat_gloves, Vector3(0, -0.09, 0)))

	# Pernas & Calça Social
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.50, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.058, 0.24, mat_suit, Vector3(0, -0.12, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.24, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.050, 0.24, mat_shoes, Vector3(0, -0.12, 0)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.50, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.058, 0.24, mat_suit, Vector3(0, -0.12, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.24, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.050, 0.24, mat_shoes, Vector3(0, -0.12, 0)))

	# Maca Retrátil com Saco de Cadáver (se for carregador)
	if is_stretcher_bearer:
		_build_stretcher()

func _build_stretcher() -> void:
	var mat_metal := _make_mat(Color(0.65, 0.68, 0.72), 0.8)
	stretcher_mesh = MeshInstance3D.new()
	var box_s := BoxMesh.new()
	box_s.size = Vector3(0.42, 0.06, 0.85)
	stretcher_mesh.mesh = box_s
	stretcher_mesh.material_override = mat_metal
	stretcher_mesh.position = Vector3(0.0, 0.55, -0.55)
	model_root.add_child(stretcher_mesh)

	# Saco preto de cadáver (inicialmente invisível, aparece após ensacar)
	var mat_bag := _make_mat(Color(0.06, 0.06, 0.08), 0.9)
	body_bag_mesh = MeshInstance3D.new()
	var box_b := BoxMesh.new()
	box_b.size = Vector3(0.36, 0.16, 0.78)
	body_bag_mesh.mesh = box_b
	body_bag_mesh.material_override = mat_bag
	body_bag_mesh.position = Vector3(0.0, 0.10, 0.0)
	body_bag_mesh.visible = false
	stretcher_mesh.add_child(body_bag_mesh)

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat
	mesh_inst.position = offset
	return mesh_inst

func _make_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	return m

func _physics_process(delta: float) -> void:
	if is_dead:
		fall_presentation.update(delta)
		return
	if state == State.EMBARKED: return
		
	var is_moving := false
	var dir_to_look := Vector2.ZERO

	match state:
		State.DISEMBARK:
			if not is_instance_valid(hearse):
				state = State.APPROACH
			else:
				var exit_point: Vector2 = hearse.get_crew_exit_point(crew_side, crew_longitudinal) if hearse.has_method("get_crew_exit_point") else hearse.global_position
				dir_to_look = global_position.direction_to(exit_point)
				if global_position.distance_to(exit_point) > 5.0:
					velocity = _navigate_towards(exit_point, speed * 0.72, delta)
					is_moving = true
				else:
					velocity = Vector2.ZERO
					if not preload("res://emergency/EmergencyCrewTransition.gd").finish_exit(self, hearse, crew_side, delta): return
					state = State.APPROACH
					remove_collision_exception_with(hearse)
		State.APPROACH:
			if is_burial_trip:
				var destination := burial_position
				var crossing_gate := has_meta("burial_gate") and not _burial_gate_passed
				if crossing_gate: destination = get_meta("burial_gate") + Vector2(0,26)
				var dist_b := global_position.distance_to(destination)
				dir_to_look = global_position.direction_to(destination)
				if dist_b > (7.0 if crossing_gate else 20.0):
					velocity = _navigate_towards(destination, speed, delta)
					is_moving = true
				elif crossing_gate:
					_burial_gate_passed = true
				else:
					velocity = Vector2.ZERO
					state = State.BAG_AND_LIFT
					bag_timer = 5.0
			elif not is_instance_valid(target) or target.get_meta("service_complete",false):
				_start_return_to_hearse()
				return
			else:
				var pickup: Vector2 = target.collection_position(self) if target.has_method("collection_position") else target.global_position
				var portal_wait: bool = target.has_method("can_collect") and not target.can_collect(self)
				if target.has_method("can_collect") and not portal_wait: _access_index = _access_route.size()
				var following_route := _access_index < _access_route.size()
				if following_route: pickup = _access_route[_access_index]
				var dist: float = global_position.distance_to(pickup)
				dir_to_look = global_position.direction_to(pickup)
				var sight := PhysicsRayQueryParameters2D.create(global_position, pickup, 3, [get_rid()])
				sight.hit_from_inside = true
				var hit := get_world_2d().direct_space_state.intersect_ray(sight)
				if following_route and dist <= 8.0:
					_access_index += 1
					velocity = Vector2.ZERO
				elif dist > (7.0 if portal_wait else (8.0 if following_route else 28.0)) or (not hit.is_empty() and not _pickup_obstacle_owned(hit.collider)):
					velocity = _navigate_towards(pickup, speed, delta)
					is_moving = true
				elif portal_wait:
					velocity = Vector2.ZERO
				else:
					velocity = Vector2.ZERO
					state = State.BAG_AND_LIFT
					bag_timer = 2.0

		State.BAG_AND_LIFT:
			velocity = Vector2.ZERO
			if is_burial_trip:
				dir_to_look = global_position.direction_to(burial_position)
			elif is_instance_valid(target):
				dir_to_look = global_position.direction_to(target.global_position)
			bag_timer -= delta
			if bag_timer <= 0.0:
				if is_burial_trip:
					if not get_node("/root/CoronerCare").bury(self):
						bag_timer = .5
						return
					_place_grave_marker()
				elif is_instance_valid(target):
					var pickup: Vector2 = target.collection_position(self) if target.has_method("collection_position") else target.global_position
					var ray := PhysicsRayQueryParameters2D.create(global_position,pickup,3,[get_rid()])
					var obstruction := get_world_2d().direct_space_state.intersect_ray(ray)
					if global_position.distance_to(pickup)>28 or (not obstruction.is_empty() and not _pickup_obstacle_owned(obstruction.collider)):
						state = State.APPROACH
						return
					if not is_stretcher_bearer and not target.has_method("collect_piece"):
						_start_return_to_hearse()
						return
					if target.has_method("collect_piece"):
						if body_bag_mesh: body_bag_mesh.visible = true
						if not target.collect_piece(self):
							state = State.APPROACH
							return
					if not get_node("/root/CoronerCare").begin_collection(target, self):
						_start_return_to_hearse()
						return
					target.set_meta("service_complete", true)
					# The saved victim stays hidden; only disposable remains/bags
					# are freed. Cargo enters the van when this worker boards.
					if not target is CharacterBody2D and not target.has_method("return_point"): target.queue_free()
				if body_bag_mesh:
					body_bag_mesh.visible = not is_burial_trip
				_start_return_to_hearse()

		State.RETURN_HEARSE:
			if not is_instance_valid(hearse):
				queue_free()
				return
			var crossing_gate := is_burial_trip and has_meta("burial_gate") and not _burial_return_gate_passed
			var door_point: Vector2 = hearse.get_crew_door_point(crew_side, crew_longitudinal) if hearse.has_method("get_crew_door_point") else hearse.global_position
			if crossing_gate: door_point = get_meta("burial_gate")
			var following_route := _return_index < _return_route.size()
			if following_route: door_point = _return_route[_return_index]
			var portal: Variant = get_meta("coroner_portal") if has_meta("coroner_portal") else null
			var portal_point: Vector2 = portal.return_point(self) if is_instance_valid(portal) else Vector2.INF
			var exiting_interior := portal_point.is_finite()
			if exiting_interior: door_point = portal_point
			var dist_h := global_position.distance_to(door_point)
			dir_to_look = global_position.direction_to(door_point)
			if dist_h > 7.0:
				velocity = _navigate_towards(door_point, speed, delta)
				is_moving = true
			elif exiting_interior:
				velocity = Vector2.ZERO
			elif following_route:
				_return_index += 1
			elif crossing_gate:
				_burial_return_gate_passed = true
			else:
				velocity = Vector2.ZERO
				_board_hearse()

	move_and_slide()
	is_moving = velocity.length_squared() > 1.0

	# Animação e Rotação 3D
	if model_root and dir_to_look.length_squared() > 0.01:
		var target_angle_3d: float = -atan2(dir_to_look.y, dir_to_look.x) - PI * 0.5
		model_root.rotation.y = lerp_angle(model_root.rotation.y, target_angle_3d, minf(1.0, 12.0 * delta))

	if is_moving:
		walk_clock += delta * 5.0
	else:
		walk_clock += delta * 1.5

	var step_angle: float = sin(walk_clock) * 0.35 if is_moving else 0.0
	if left_upper_leg and right_upper_leg:
		left_upper_leg.rotation.x = step_angle
		right_upper_leg.rotation.x = -step_angle
		if left_lower_leg and right_lower_leg:
			left_lower_leg.rotation.x = maxf(0.0, -step_angle * 0.65)
			right_lower_leg.rotation.x = maxf(0.0, step_angle * 0.65)

	if right_upper_arm and left_upper_arm:
		if is_stretcher_bearer:
			# Segura a maca com as duas mãos à frente
			right_upper_arm.rotation = Vector3(1.20, -0.15, 0.0)
			left_upper_arm.rotation = Vector3(1.20, 0.15, 0.0)
		else:
			right_upper_arm.rotation.x = -step_angle * 0.5
			left_upper_arm.rotation.x = step_angle * 0.5

var last_pos: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0

var movement_navigation := preload("res://emergency/ResponderNavigation.gd").new()

func _pickup_obstacle_owned(obstacle: Node) -> bool:
	if not is_instance_valid(target): return false
	return obstacle==target or target.is_ancestor_of(obstacle) or (target.has_method("owns_obstacle") and target.owns_obstacle(obstacle))

func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
	var result: Vector2 = movement_navigation.movement(self, dest, move_speed, delta)
	stuck_timer = movement_navigation.stuck_time
	# Static route planning excludes moving people. Give opposing coworkers a
	# short, swept passing step instead of stopping nose-to-nose on one waypoint.
	if _passing_point.is_finite():
		var step := _passing_point-global_position
		if step.length()>4 and not test_move(global_transform,step):
			return step.normalized()*minf(move_speed,step.length()/maxf(delta,.001))
		_passing_point = Vector2.INF
	if not result.is_zero_approx():
		var hit := KinematicCollision2D.new()
		if test_move(global_transform,result.normalized()*24,hit):
			var other: Variant = hit.get_collider()
			if other is CollisionObject2D and (other.collision_layer & 4) != 0:
				for angle in [.8,1.3,1.8,2.2,-.8,-1.3,-1.8]:
					var step := result.normalized().rotated(angle)*28
					if not test_move(global_transform,step):
						_passing_point = global_position+step
						return step.normalized()*move_speed
				return Vector2.ZERO
	return result


func _start_return_to_hearse() -> void:
	if state != State.RETURN_HEARSE and not is_burial_trip:
		_return_route = _access_route.duplicate()
		_return_route.reverse()
		_return_index = 0
	if is_instance_valid(hearse): add_collision_exception_with(hearse)
	state = State.RETURN_HEARSE
	if not is_instance_valid(hearse):
		queue_free()

## Leaves a permanent grave marker at burial_position -- a simple cross on
## a small dirt mound, same low-poly Polygon2D style used by the other
## props in this file. Registers with the HarborCemetery node if present.
func _place_grave_marker() -> void:
	var identity := String(get_meta("burial_identity", ""))
	if not identity.is_empty():
		var yard := get_tree().get_first_node_in_group("cemetery")
		if yard: yard.restore_burials()
		return
	var grave := Node2D.new()
	grave.name = "GraveMarker"
	grave.global_position = burial_position
	grave.z_index = -1

	var mound := Polygon2D.new()
	mound.polygon = PackedVector2Array([
		Vector2(-11, 6), Vector2(-7, 2), Vector2(0, 0),
		Vector2(7, 2), Vector2(11, 6), Vector2(0, 9)
	])
	mound.color = Color(0.32, 0.24, 0.16, 0.95)
	grave.add_child(mound)

	var upright := Polygon2D.new()
	upright.polygon = PackedVector2Array([Vector2(-2, -14), Vector2(2, -14), Vector2(2, 6), Vector2(-2, 6)])
	upright.color = Color(0.55, 0.52, 0.47)
	grave.add_child(upright)

	var crossbar := Polygon2D.new()
	crossbar.polygon = PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, -4), Vector2(-8, -4)])
	crossbar.color = Color(0.55, 0.52, 0.47)
	grave.add_child(crossbar)

	var parent := get_parent() if get_parent() != null else get_tree().current_scene
	if parent:
		parent.add_child(grave)

	var cemetery := get_tree().get_first_node_in_group("cemetery")
	if cemetery and cemetery.has_method("register_grave"):
		cemetery.register_grave(grave, burial_position)


func begin_service_disembark(vehicle: Node2D, side: float, longitudinal: float) -> void:
	if not is_burial_trip:
		_access_route.assign(vehicle.get_meta("ambulance_walk_route", []))
		_access_index = 0
	hearse = vehicle
	crew_side = side
	crew_longitudinal = longitudinal
	state = State.DISEMBARK

func _board_hearse() -> void:
	if boarding_started:
		return
	boarding_started = true
	state = State.EMBARKING
	if is_instance_valid(hearse) and hearse.has_method("play_crew_door"):
		hearse.play_crew_door(crew_side, crew_longitudinal)
	await get_tree().create_timer(0.42).timeout
	if not is_instance_valid(self):
		return
	state = State.EMBARKED
	hide()
	set_physics_process(false)
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if is_instance_valid(hearse) and hearse.has_method("on_mortician_embarked"):
		get_node("/root/CoronerCare").board(self, hearse)
		hearse.on_mortician_embarked(self)
	queue_free()

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	if amount <= 0 or is_dead: return
	health = maxi(0, health - amount)
	preload("res://audio/combat/CombatImpactAudio.gd").play_hurt(self, amount)
	if health <= 0 and not is_dead:
		is_dead = true
		velocity = Vector2.ZERO
		if collision_shape: collision_shape.set_deferred("disabled", true)
		_start_fall()
		get_node("/root/NPCMedicalCare").report_injury(self)
		if not has_meta("medical_pending"): create_tween().tween_interval(10.0).finished.connect(queue_free)

func _start_fall(impact := Vector2.ZERO) -> void:
	fall_presentation.start(self, model_root, viewport_3d, impact)
