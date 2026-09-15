extends Node2D
## The presentation falls into the valley; the actor and camera keep their scale.
## Lives outside the streamed region so unloading a road cannot strand controls.
const DURATION := 0.85
var actor: CharacterBody2D
var passenger: Node2D
var snapshots: Array[Dictionary] = []
var origin := Vector2.ZERO
var direction := Vector2.ZERO
var elapsed := 0.0
var finished := false
var falling_rig: Node3D
var rig_view: SubViewport
var rig_states: Array[Dictionary] = []
var view_mode := SubViewport.UPDATE_DISABLED

func begin(body: CharacterBody2D, outward: Vector2) -> void:
	if body.has_meta("interior_actor_presentation"): body.get_meta("interior_actor_presentation").restore()
	actor = body
	origin = body.global_position
	direction = outward.normalized()
	global_position = origin
	z_as_relative = false
	z_index = body.z_index
	# Reuse the already rendered textures, without another viewport or rig.
	for source in body.find_children("*", "Sprite2D", true, false):
		if not source.is_visible_in_tree(): continue
		var picture := Sprite2D.new()
		picture.texture = source.texture
		picture.centered = source.centered
		picture.offset = source.offset
		picture.flip_h = source.flip_h
		picture.flip_v = source.flip_v
		picture.modulate = source.modulate * body.modulate
		add_child(picture)
		picture.global_transform = source.global_transform
	if body.get("is_driven_by_player") == true:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		# Production vehicles own the driving flag; Player has no current_vehicle field.
		if is_instance_valid(player):
			passenger = player
			_lock(passenger)
	_capture_rig(body)
	_lock(body)
	body.tree_exiting.connect(_actor_exiting, CONNECT_ONE_SHOT)

func _lock(body: Node2D) -> void:
	snapshots.append({"body": body, "process": body.process_mode, "layer": body.collision_layer, "mask": body.collision_mask, "visible": body.visible})
	body.set_meta("mountain_falling", true)
	body.process_mode = Node.PROCESS_MODE_DISABLED
	body.collision_layer = 0
	body.collision_mask = 0
	body.velocity = Vector2.ZERO
	body.hide()

func _process(delta: float) -> void:
	if finished: return
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		_cancel()
		return
	# A recovery or scripted relocation takes precedence over this effect.
	if actor.global_position.distance_to(origin) > 2.0:
		_cancel()
		return
	elapsed += delta
	var t := clampf(elapsed / DURATION, 0.0, 1.0)
	global_position = origin + (direction * 115.0 + Vector2(0, 95)) * t * t
	scale = Vector2.ONE * lerpf(1.0, 0.30, t * t)
	rotation = direction.x * 0.18 * t
	modulate.a = 1.0 - smoothstep(0.78, 1.0, t)
	_pose_fall(t)
	if t >= 1.0: _impact()

func _restore(cancelled: bool) -> void:
	for state in rig_states:
		if is_instance_valid(state.node): state.node.transform = state.transform
	if is_instance_valid(rig_view): rig_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	rig_states.clear()
	for state in snapshots:
		var body: Node2D = state.body
		if not is_instance_valid(body): continue
		body.process_mode = state.process
		body.collision_layer = state.layer
		body.collision_mask = state.mask
		if cancelled:
			body.visible = state.visible
			body.remove_meta("mountain_falling")

func _impact() -> void:
	finished = true
	_restore(false)
	if is_instance_valid(passenger):
		# Choose recovery from the impact, not the last boarding/exit position.
		passenger.global_position = origin
		passenger.take_environment_damage(10000)
		if actor.has_method("force_exit_vehicle"):
			actor.force_exit_vehicle()
	if is_instance_valid(actor):
		if actor.has_method("take_environment_damage"):
			actor.take_environment_damage(10000)
			if actor.get("is_dead") != true: actor.show()
		elif actor.has_method("take_damage"):
			actor.take_damage(10000)
	queue_free()

func _cancel() -> void:
	if finished: return
	finished = true
	_restore(true)
	queue_free()

func _actor_exiting() -> void:
	if finished: return
	_cancel()
	# If a vehicle is unloaded/destroyed, its hidden driver cannot stay attached.
	if is_instance_valid(passenger) and passenger.is_inside_tree():
		passenger.show()
		passenger.set_physics_process(true)
		passenger.is_control_disabled = false
		for collider in passenger.find_children("*", "CollisionShape2D", true, false):
			collider.set_deferred("disabled", false)
		var camera := passenger.get_node_or_null("Camera") as Camera2D
		if camera: camera.make_current()

func _exit_tree() -> void:
	if not finished: _restore(true)

func _capture_rig(body: Node) -> void:
	falling_rig = body.get("model_root") as Node3D
	if falling_rig == null: falling_rig = body.get("body_model") as Node3D
	if falling_rig == null: falling_rig = body.get("model") as Node3D
	if falling_rig == null: return
	rig_view = falling_rig.get_viewport() as SubViewport
	if rig_view:
		view_mode = rig_view.render_target_update_mode
	for node in [falling_rig] + falling_rig.find_children("*", "Node3D", true, false):
		if node == falling_rig or String(node.name) in ["LeftUpperArm","RightUpperArm","LeftLowerArm","RightLowerArm","LeftUpperLeg","RightUpperLeg","LeftLowerLeg","RightLowerLeg"]:
			rig_states.append({"node":node,"transform":node.transform})

func _pose_fall(t: float) -> void:
	if not is_instance_valid(falling_rig): return
	var tumble := smoothstep(.12, 1.0, t)
	for state in rig_states:
		var node: Node3D = state.node
		if not is_instance_valid(node): continue
		node.transform = state.transform
		if node == falling_rig:
			# Animate the real volume: roof/undercarriage and articulated limbs
			# become visible as the actor loses support, not a rotating flat card.
			node.rotation.x += tumble * 2.5
			node.rotation.z += (1.0 if direction.x >= 0 else -1.0) * tumble * 1.7
		elif "UpperArm" in String(node.name):
			node.rotation.x = -.9 - sin(t*PI)*.7
			node.rotation.z = (-1 if String(node.name).begins_with("Left") else 1)*(.3+t*.55)
		elif "LowerArm" in String(node.name): node.rotation.x = -.65
		elif "UpperLeg" in String(node.name):
			node.rotation.x = (.6 if String(node.name).begins_with("Left") else -.35) * sin(t*PI)
		elif "LowerLeg" in String(node.name): node.rotation.x = -.7 * sin(t*PI)
	if is_instance_valid(rig_view): rig_view.render_target_update_mode = SubViewport.UPDATE_ONCE
