extends Node3D
## Shares the vehicle's depth buffer. Body panels occlude the entrant normally;
## no foreground sprite, transparency fade or drawing over the roof.
var vehicle: CharacterBody2D
var rig: Node3D
var seated := false
var start := Vector3.ZERO
var doorway := Vector3.ZERO
var seat := Vector3.ZERO
var actor_scale := 1.0
var ceiling := 1.25
var head_clearance := 0.17
var _pairs: Array[Dictionary] = []
var _final_render_frames := 0
var motorcycle := false
var _rider_pose: Array[Dictionary] = []
var _legs := preload("res://scripts/player/VehicleBoardingPose.gd").new()
var _arms := preload("res://characters/PlayerCombatPose.gd").new()

func setup(car: CharacterBody2D, actor: CharacterBody2D, door: Node3D) -> void:
	vehicle = car
	name = "DanteCabinOccupant"
	rig = Node3D.new()
	add_child(rig)
	for key in ["torso_node", "head_node", "left_upper_arm", "right_upper_arm", "left_upper_leg", "right_upper_leg"]:
		var source: Node3D = actor.get(key)
		var copy := source.duplicate() as Node3D
		rig.add_child(copy)
		_pair(source, copy)
	# Com o Dante Meshy, as malhas copiadas vêm ocultas: o modelo importado
	# segue as âncoras da cópia, que continuam sendo as posadas abaixo.
	if is_instance_valid(actor.get("meshy_rig")):
		var puppet := preload("res://scripts/player/MeshyDantePuppet.gd").new()
		rig.add_child(puppet)
		puppet.configure(rig, actor.current_outfit_id)
	var display: Sprite2D = car.visual if "visual" in car else car.sprite
	var camera: Camera3D = car.body_viewport.get_camera_3d()
	# A just-streamed camera has no previous physics transform yet. Ray queries
	# must use its authored transform, including before the first rendered frame.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.force_update_transform()
	camera.reset_physics_interpolation()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var actor_camera: Camera3D = actor.viewport_3d.get_camera_3d()
	var foot_pixel := actor_camera.unproject_position(Vector3.ZERO)
	var head_pixel := actor_camera.unproject_position(Vector3(0,1.38,0))
	var foot_world: Vector2 = actor.sprite_3d_display.to_global(foot_pixel - Vector2(actor.viewport_3d.size) * 0.5)
	var pixel := display.to_local(foot_world) + Vector2(car.body_viewport.size) * 0.5
	var ray_origin := camera.project_ray_origin(pixel)
	var ray_direction := camera.project_ray_normal(pixel)
	var ground := ray_origin - ray_direction * (ray_origin.y / ray_direction.y)
	start = car.body_model.to_local(ground)
	var native_height := camera.unproject_position(Vector3(0,1.38,0)).distance_to(camera.unproject_position(Vector3.ZERO)) * display.scale.x
	actor_scale = foot_pixel.distance_to(head_pixel) * actor.sprite_3d_display.scale.x / maxf(native_height, 0.01)
	if car.has_meta("interior_vehicle_presentation"):
		var room = car.get_meta("interior_vehicle_presentation").view
		car.get_meta("interior_vehicle_presentation").sync()
		var floor_point: Vector2 = room.unproject_floor(actor.global_position)
		start = car.body_model.to_local(Vector3(floor_point.x,0,floor_point.y))
		actor_scale = 1.8 / 1.45
	rig.scale = Vector3.ONE * actor_scale
	var head := rig.get_node("HeadNode") as Node3D
	head_clearance = _mesh_top(head, Transform3D(Basis.from_scale(head.scale), Vector3.ZERO)) + 0.025
	motorcycle = door == null
	if motorcycle:
		doorway = Vector3(signf(start.x) * 0.62, 0, 0.18)
		seat = Vector3.ZERO
		car.body_model.set_dante_rider(actor)
		var rider: Node3D = car.body_model.dante_rider
		for pair in _pairs:
			var path: NodePath = rig.get_path_to(pair.copy)
			var counterpart := rider.get_node_or_null(path) as Node3D
			if counterpart != null:
				_rider_pose.append({"copy":pair.copy, "transform":counterpart.transform})
		process_priority = 100
		return
	var hinge: Vector3 = door.hinge.position
	# Keep the foot origin behind the hinge, in the opening, not on the hood.
	doorway = Vector3(hinge.x + signf(hinge.x) * 0.43, 0, door.entry_center_z)
	# Hip anchor sits behind the window opening; shoulders need clearance from
	# the tapered pillars/windscreen rather than sharing the door's center plane.
	seat = Vector3(signf(hinge.x) * minf(absf(hinge.x) * 0.34, 0.32), maxf(0, hinge.y - 0.40), doorway.z + 0.20)
	ceiling = door.cabin_ceiling
	if car.body_model.get("vehicle_id") == "port_forklift":
		seat = Vector3(0, 0.80 - 0.464 * actor_scale, 0.45)
	elif car.body_model.has_method("is_open_top") and car.body_model.is_open_top():
		seat = Vector3(signf(hinge.x) * 0.32, 0.50 - 0.464 * actor_scale, 0.12)
		ceiling = 2.5
	process_priority = 100

func _pair(source: Node3D, copy: Node3D) -> void:
	_pairs.append({"source":source, "copy":copy})
	for i in source.get_child_count():
		if source.get_child(i) is Node3D:
			_pair(source.get_child(i), copy.get_child(i))

func _mesh_top(node: Node3D, relative: Transform3D) -> float:
	var top := 0.0
	if node is MeshInstance3D and node.mesh != null:
		top = (relative * node.mesh.get_aabb()).end.y
	for child in node.get_children():
		if child is Node3D: top = maxf(top, _mesh_top(child, relative * child.transform))
	return top

func update_pose(actor: CharacterBody2D, t: float) -> void:
	for pair in _pairs:
		if is_instance_valid(pair.source): pair.copy.transform = pair.source.transform
	rig.rotation = Vector3(0, actor.model_root.rotation.y - vehicle.body_model.rotation.y, 0)
	if t < 0.18:
		position = start.lerp(doorway, smoothstep(0,0.18,t))
	else:
		var enter := smoothstep(0.36,0.80,t)
		position = doorway.lerp(seat, enter)
	if motorcycle:
		# Match the visible rider exactly at the saddle, then articulate the
		# same meshes into the leg swing and the final standing pose.
		var seated_weight := smoothstep(0.55,0.95,t)
		rig.scale = Vector3.ONE * lerpf(actor_scale, 1.2, seated_weight)
		for state in _rider_pose:
			state.copy.transform = state.copy.transform.interpolate_with(state.transform, seated_weight)
		_refresh()
		return
	# Passenger entry ends in the driver's seat while already inside the cabin.
	if seat.x > 0 and vehicle.get("taxi_passenger") != true:
		position.x = lerpf(position.x, -seat.x, smoothstep(0.80,0.94,t))
	# Fit the sitting/ducking pose beneath this cabin's roof at full human scale.
	# Lower hips and bend knees, preserving feet in the footwell (no shrinking).
	var head := rig.get_node("HeadNode") as Node3D
	var excess := maxf(0, position.y + (head.position.y + head_clearance) * actor_scale - ceiling)
	var crouch := excess / actor_scale * smoothstep(0.28,0.62,t)
	for key in ["TorsoNode", "HeadNode", "LeftUpperArm", "RightUpperArm"]:
		rig.get_node(key).position.y -= crouch
	for prefix in ["Left", "Right"]:
		var upper := rig.get_node(prefix + "UpperLeg") as Node3D
		var lower := upper.get_node(prefix + "LowerLeg") as Node3D
		var foot := rig.to_local(lower.to_global(Vector3(0,-0.30,0)))
		_legs._solve_leg(upper, lower, foot, upper.position.y - 0.684 - crouch)
		var shoulder := rig.get_node(prefix + "UpperArm") as Node3D
		var forearm := shoulder.get_node(prefix + "LowerArm") as Node3D
		var hand := rig.to_local(forearm.to_global(Vector3(0,-0.20,0)))
		var arm_side := -1.0 if prefix == "Left" else 1.0
		var wheel := Vector3(arm_side * 0.13, rig.get_node("TorsoNode").position.y + 0.10, -0.28)
		if vehicle.get("taxi_passenger") == true: wheel = Vector3(arm_side*0.14,rig.get_node("TorsoNode").position.y-0.20,-0.12)
		_arms._solve_arm(shoulder, forearm, hand.lerp(wheel, smoothstep(0.65,0.90,t)), arm_side)
	_refresh()

func settle(actor: CharacterBody2D) -> void:
	update_pose(actor, 1.0)
	seated = true
	_final_render_frames = 2
	_pairs.clear()

func _refresh() -> void:
	_final_render_frames = 2
	if is_instance_valid(vehicle) and is_instance_valid(vehicle.body_viewport):
		vehicle.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if "_body_render_visible" in vehicle: vehicle._body_render_visible = false
		if vehicle.has_method("request_appearance_update"): vehicle.request_appearance_update()

func dispose() -> void:
	hide()
	_refresh()
	queue_free()

func _process(_delta: float) -> void:
	if not is_instance_valid(vehicle) or not vehicle.is_driven_by_player:
		dispose()
	elif not seated or _final_render_frames > 0:
		vehicle.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_final_render_frames = maxi(0, _final_render_frames - 1)
