extends Node2D
## Cargo keeps its own identity, damage and presentation. Its physical footprint
## joins the forklift while carried, so the load also stops against obstacles.
const MAX_HEIGHT := 1.65
const LIFT_SPEED := .65
var vehicle: CharacterBody2D
var cargo: CharacterBody2D
var height := 0.0
var load_shape: CollisionShape2D
var _relative := Transform2D.IDENTITY
var _saved := {}
var _last_height := -1.0
var _hydraulics: AudioStreamPlayer2D
var _was_operable := false

static func sync_vehicle(body: CharacterBody2D, enabled: bool) -> void:
	var existing := body.get_node_or_null("ForkliftLift")
	if not enabled:
		if existing:
			existing.release()
			body.remove_child(existing)
			existing.queue_free()
		return
	if not existing:
		existing = load("res://world/harbor/ForkliftLift.gd").new()
		existing.name = "ForkliftLift"
		existing.vehicle = body
		body.add_child(existing)
	existing.configure_hull()

func configure_hull() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(39, 25)
	vehicle.collision.shape = shape
	vehicle.collision.position = Vector2(-10, 0)
	vehicle.has_theft_alarm = false

func _ready() -> void:
	process_physics_priority = 10
	load_shape = CollisionShape2D.new()
	load_shape.name = "ForkliftCargoHull"
	load_shape.disabled = true
	vehicle.add_child.call_deferred(load_shape)
	_hydraulics = AudioStreamPlayer2D.new()
	_hydraulics.stream = preload("res://world/shared/salvage/SalvageAudio.gd").hydraulics()
	_hydraulics.bus = &"SFX"
	_hydraulics.volume_db = -19
	_hydraulics.max_distance = 450
	add_child(_hydraulics)

func can_operate() -> bool:
	if not vehicle.is_driven_by_player or vehicle.is_broken or vehicle.has_meta("vehicle_boarding"): return false
	var driver: Node = vehicle.get("_driver")
	if not is_instance_valid(driver): return false
	for flag in ["is_dead", "is_arrested", "is_in_dialogue", "is_control_disabled"]:
		if driver.get(flag) == true: return false
	return not get_node("/root/GameInput").remapping

func speed_limit() -> float:
	return 55.0 if is_instance_valid(cargo) else 90.0

func _physics_process(delta: float) -> void:
	var previous_height := height
	var operable := can_operate()
	if operable and not _was_operable and vehicle._driver.has_method("_show_weapon_notice"):
		var controls := get_node("/root/GameInput")
		vehicle._driver._show_weapon_notice("Garfos: %s ergue · %s abaixa e solta. Pare junto à carga." % [controls.hint("fire"),controls.hint("aim")])
	_was_operable = operable
	if vehicle.is_broken or vehicle.is_exploded:
		height = move_toward(height, 0, LIFT_SPEED * delta)
		if height == 0: release()
	elif operable:
		var direction := Input.get_action_strength("fire") - Input.get_action_strength("aim")
		if direction > 0 and height < .18 and not is_instance_valid(cargo):
			var target := nearby_cargo()
			if target: attach(target)
		height = clampf(height + direction * LIFT_SPEED * delta, 0, MAX_HEIGHT)
		if direction < 0 and height == 0: release()
	if not is_equal_approx(height, previous_height):
		if not _hydraulics.playing: _hydraulics.play()
	elif _hydraulics.playing:
		_hydraulics.stop()
	if is_instance_valid(cargo):
		_pose_cargo()
	elif not _saved.is_empty():
		_saved.clear()
		load_shape.disabled = true
	if is_instance_valid(vehicle.body_model) and vehicle.body_model.has_method("set_fork_height"):
		vehicle.body_model.set_fork_height(height)
		if not is_equal_approx(height, _last_height):
			vehicle.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			vehicle._body_render_visible = false
			_last_height = height

func eligible(target: Node2D) -> bool:
	if target == vehicle or not target is CharacterBody2D or not target.is_visible_in_tree(): return false
	if target.has_meta("forklift_carried") or target.has_meta("tow_carried") or target.has_meta("vehicle_boarding"): return false
	var target_lift := target.get_node_or_null("ForkliftLift")
	if target_lift and is_instance_valid(target_lift.cargo): return false
	if target.is_in_group("forklift_cargo"): return true
	return target.is_in_group("vehicle") and target.get("_detached_from_lane") == true and target.get("is_driven_by_player") == false and target.get("taxi_passenger") != true and target.get("is_exploded") != true and float(target.get("target_length")) <= 95 and not target.is_in_group("mission_vehicle") and target.velocity.length() < 12

func on_forks(target: CharacterBody2D) -> bool:
	var center := vehicle.to_local(target.global_position)
	if center.x < 18 or center.x > 70 or absf(center.y) > 20: return false
	var shape: CollisionShape2D = target.get("collision")
	if not shape or not shape.shape is RectangleShape2D: return false
	var point := shape.to_local(vehicle.to_global(Vector2(27, 0)))
	return Rect2(-shape.shape.size * .5, shape.shape.size).grow(5).has_point(point)

func nearby_cargo() -> CharacterBody2D:
	var nearest: CharacterBody2D
	var best := INF
	for target in get_tree().get_nodes_in_group("vehicle") + get_tree().get_nodes_in_group("forklift_cargo"):
		if not eligible(target) or not on_forks(target): continue
		var distance: float = vehicle.to_global(Vector2(27, 0)).distance_squared_to(target.global_position)
		if distance < best:
			best = distance
			nearest = target
	return nearest

func attach(target: CharacterBody2D) -> bool:
	if is_instance_valid(cargo) or not eligible(target) or not on_forks(target) or height > .18 or vehicle.velocity.length() > 12: return false
	if target.velocity.length() > 12 or vehicle.is_broken: return false
	var ray := PhysicsRayQueryParameters2D.create(vehicle.global_position, target.global_position, 3, [vehicle.get_rid(), target.get_rid()])
	if not vehicle.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): return false
	if target.has_method("ensure_presentation"): target.ensure_presentation()
	cargo = target
	_relative = vehicle.global_transform.affine_inverse() * cargo.global_transform
	_saved = {"layer":cargo.collision_layer, "mask":cargo.collision_mask, "mode":cargo.process_mode,
		"physics":cargo.is_physics_processing(), "idle":cargo.is_processing(), "z":cargo.z_index, "visual_position":cargo.visual.position,
		"floor_offset":_floor_offset(vehicle) - _floor_offset(cargo), "lift_projection":_lift_projection()}
	load_shape.shape = cargo.collision.shape.duplicate()
	load_shape.transform = vehicle.global_transform.affine_inverse() * cargo.collision.global_transform
	load_shape.disabled = false
	cargo.set_meta("forklift_carried", true)
	cargo.collision_layer = 0
	cargo.collision_mask = 0
	cargo.velocity = Vector2.ZERO
	cargo.process_mode = Node.PROCESS_MODE_DISABLED
	cargo.z_index = vehicle.z_index + 1
	_pose_cargo()
	return true

func _pose_cargo() -> void:
	cargo.global_transform = vehicle.global_transform * _relative
	cargo.visual.position = _saved.visual_position
	cargo.visual.global_position += Vector2(0, _saved.floor_offset - height * _saved.lift_projection)
	# Project the carried vehicle's lamps after raising its presentation.
	if cargo.has_method("_update_3d_orientation"):
		cargo._update_3d_orientation(0)
	else:
		cargo.update_orientation()

func _lift_projection() -> float:
	# Height is foreshortened by the orthographic camera: using world pixels
	# directly would make the cargo float above the actual 3D fork blades.
	var camera: Camera3D = vehicle.body_viewport.get_camera_3d()
	return (camera.unproject_position(Vector3.ZERO).y - camera.unproject_position(Vector3.UP).y) * vehicle.visual.scale.y

func _floor_offset(body: CharacterBody2D) -> float:
	if body.is_in_group("forklift_cargo"): return body.visual.project_point(Vector3.ZERO).y
	if not body.has_method("_update_3d_orientation"): return 0.0
	var view: SubViewport = body.body_viewport
	if not is_instance_valid(view): return 0.0
	return (view.get_camera_3d().unproject_position(Vector3.ZERO).y - view.size.y * .5) * body.visual.scale.y

func _clear_at(transform_at: Transform2D) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = load_shape.shape
	query.transform = transform_at * load_shape.transform
	query.collision_mask = 3
	query.exclude = [vehicle.get_rid(), cargo.get_rid()]
	return vehicle.get_world_2d().direct_space_state.intersect_shape(query).is_empty()

func safe_rotation(proposed: float) -> float:
	if not is_instance_valid(cargo): return proposed
	var change := angle_difference(vehicle.rotation, proposed)
	var steps := maxi(1, ceili(absf(change) / .025))
	for i in range(1, steps + 1):
		var angle := vehicle.global_rotation + change * float(i) / steps
		if not _clear_at(Transform2D(angle, vehicle.global_position)): return vehicle.rotation
	return proposed

func release(force := false) -> bool:
	if not is_instance_valid(cargo): return false
	if not force and not _clear_at(vehicle.global_transform): return false
	if cargo.is_inside_tree() and vehicle.is_inside_tree(): _pose_cargo()
	cargo.visual.position = _saved.visual_position
	cargo.collision_layer = _saved.layer
	cargo.collision_mask = _saved.mask
	cargo.process_mode = _saved.mode
	cargo.set_physics_process(_saved.physics)
	cargo.set_process(_saved.idle)
	cargo.z_index = _saved.z
	cargo.remove_meta("forklift_carried")
	cargo.reset_physics_interpolation()
	cargo = null
	_saved.clear()
	load_shape.disabled = true
	return true

func _exit_tree() -> void:
	# Despawning the carrier must never strand an invisible/unusable vehicle.
	if is_instance_valid(cargo) and not cargo.is_queued_for_deletion(): release(true)
	if is_instance_valid(load_shape): load_shape.queue_free()
