extends RefCounted
## Entry poses in Dante's local frame (-Z forward), mirrored at limb targets.
var _saved: Array[Dictionary] = []
var _weapon: Node3D
var _weapon_visible := true
var _yaw := 0.0
var _ready := false
var _arms := preload("res://characters/PlayerCombatPose.gd").new()

func setup(actor: CharacterBody2D) -> void:
	if not "model_root" in actor or not is_instance_valid(actor.model_root): return
	_ready = true
	_yaw = actor.model_root.rotation.y
	for key in ["model_root", "torso_node", "head_node", "left_upper_arm", "left_lower_arm", "right_upper_arm", "right_lower_arm", "left_upper_leg", "left_lower_leg", "right_upper_leg", "right_lower_leg"]:
		var node: Node3D = actor.get(key)
		if not is_instance_valid(node): continue
		_saved.append({"node":node, "transform":node.transform})
		var foot := node.get_node_or_null("Foot") as Node3D
		if foot: _saved.append({"node":foot, "transform":foot.transform})
	_weapon = actor.weapon_mount_node
	if is_instance_valid(_weapon):
		_weapon_visible = _weapon.visible
		_weapon.hide()

func apply(actor: CharacterBody2D, profile: String, side: float, t: float, heading: float) -> void:
	if not _ready: return
	var bike := profile == "motorcycle"
	var climb := 0.22 if profile == "truck" else (0.10 if profile == "high_car" else 0.0)
	var reach := smoothstep(0.14, 0.31, t)
	var step := smoothstep(0.32, 0.53, t)
	var sit := smoothstep(0.54, 0.79, t)
	var turn := smoothstep(0.34, 0.72, t)
	var forward_yaw := -heading - PI * 0.5
	var door_yaw := forward_yaw + side * PI * 0.5
	var yaw := lerp_angle(_yaw, door_yaw, smoothstep(0.0, 0.18, t))
	yaw = lerp_angle(yaw, forward_yaw, turn)
	if bike: yaw = lerp_angle(_yaw, forward_yaw, smoothstep(0.0, 0.30, t))
	actor.model_root.rotation = Vector3(0, yaw, 0)
	# Hips lower into the seat; the torso bends at the waist, never at the feet.
	var hip := climb * step - (0.22 if not bike else 0.08) * sit
	var lean := reach * (0.16 if bike else 0.22) + step * (0.06 if climb > 0 else 0.18) * (1.0 - sit)
	actor.torso_node.position = Vector3(0, 0.85 + hip, -0.035 * step)
	actor.torso_node.rotation = Vector3(lean, -side * 0.13 * reach * (1.0 - sit), 0)
	actor._sync_upper_body_anchors(lean)
	var near_hand := Vector3(side * 0.27, 0.88 + climb, -0.24)
	var far_hand := Vector3(-side * 0.22, 1.08 + climb, -0.20)
	if bike:
		near_hand = Vector3(side * 0.25, 0.89, -0.29)
		far_hand = Vector3(-side * 0.25, 0.89, -0.29)
	var near_target := Vector3(side * 0.21, 0.67, 0).lerp(near_hand, reach)
	var far_target := Vector3(-side * 0.21, 0.67, 0).lerp(far_hand, step if not bike else reach)
	near_target.y += hip * sit
	far_target.y += hip * sit
	_arms._solve_arm(actor.left_upper_arm, actor.left_lower_arm, near_target if side < 0 else far_target, -1)
	_arms._solve_arm(actor.right_upper_arm, actor.right_lower_arm, far_target if side < 0 else near_target, 1)
	var walk := sin(t / 0.18 * TAU) * 0.12 * (1.0 - smoothstep(0.10, 0.18, t))
	var near_foot := Vector3(side * 0.088, 0.045, walk)
	var far_foot := Vector3(-side * 0.088, 0.045, -walk)
	if bike:
		# The near boot supports the body as the opposite leg clears the saddle.
		var swing := smoothstep(0.32, 0.74, t)
		far_foot = Vector3(lerpf(-side * 0.088, -side * 0.23, swing), 0.045 + sin(swing * PI) * 0.66 + sit * 0.10, 0.12 * sin(swing * PI) - sit * 0.12)
		near_foot = near_foot.lerp(Vector3(side * 0.22, 0.12, -0.12), sit)
	else:
		near_foot = near_foot.lerp(Vector3(side * 0.10, 0.20 + climb, -0.28), step)
		far_foot = far_foot.lerp(Vector3(-side * 0.10, 0.10 + climb, -0.28), sit)
	_solve_leg(actor.left_upper_leg, actor.left_lower_leg, near_foot if side < 0 else far_foot, hip)
	_solve_leg(actor.right_upper_leg, actor.right_lower_leg, far_foot if side < 0 else near_foot, hip)

func apply_theft(actor: CharacterBody2D, side: float, t: float, heading: float, lifting: bool, lift_t: float) -> void:
	if not _ready: return
	apply(actor, "motorcycle" if lifting else "car", side, 0.18 * smoothstep(0, 0.22, t), heading)
	var reach := smoothstep(0.20, 0.38, t)
	var pull := smoothstep(0.40, 0.88, t)
	var bend := sin(PI * clampf(lift_t, 0, 1)) if lifting else reach * (1.0 - pull)
	actor.model_root.rotation.y = -heading - PI * 0.5 + side * PI * 0.5
	var hip := -0.24 * bend if lifting else -0.06 * bend
	actor.torso_node.position.y = 0.85 + hip
	actor.torso_node.rotation.x = 0.55 * bend if lifting else 0.20 * bend - 0.12 * pull
	actor._sync_upper_body_anchors(actor.torso_node.rotation.x)
	for arm_side in [-1.0, 1.0]:
		var target := Vector3(arm_side * 0.21, 0.67, 0).lerp(Vector3(arm_side * 0.20, 0.98 + hip, -lerpf(0.42, 0.18, pull)), reach)
		if lifting: target = Vector3(arm_side * 0.24, 0.85 - 0.30 * bend, -0.35)
		_arms._solve_arm(actor.left_upper_arm if arm_side < 0 else actor.right_upper_arm, actor.left_lower_arm if arm_side < 0 else actor.right_lower_arm, target, arm_side)
	_solve_leg(actor.left_upper_leg, actor.left_lower_leg, Vector3(-0.14, 0.045, -0.08), hip)
	_solve_leg(actor.right_upper_leg, actor.right_lower_leg, Vector3(0.14, 0.045, 0.10), hip)

func apply_close(actor: CharacterBody2D, side: float, t: float, heading: float) -> void:
	if not _ready: return
	actor.model_root.rotation.y = -heading - PI * 0.5 + side * PI * 0.5
	var reach := sin(PI * clampf(t, 0, 1))
	var hand := Vector3(side * 0.21, 0.67, 0).lerp(Vector3(side * 0.27, 0.94, -0.32), reach)
	_arms._solve_arm(actor.left_upper_arm if side < 0 else actor.right_upper_arm, actor.left_lower_arm if side < 0 else actor.right_lower_arm, hand, side)

func _solve_leg(upper: Node3D, lower: Node3D, target: Vector3, hip: float) -> void:
	upper.position.y = 0.684 + hip
	var delta := target - upper.position
	var direction := delta.normalized()
	var distance := clampf(delta.length(), 0.05, 0.639)
	var bend := Vector3.FORWARD
	bend = (bend - direction * bend.dot(direction)).normalized()
	var along := (0.34 * 0.34 - 0.30 * 0.30 + distance * distance) / (2.0 * distance)
	var knee := upper.position + direction * along + bend * sqrt(maxf(0, 0.34 * 0.34 - along * along))
	upper.quaternion = Quaternion(Vector3.DOWN, (knee - upper.position).normalized())
	lower.quaternion = Quaternion(Vector3.DOWN, upper.basis.inverse() * (upper.position + direction * distance - knee).normalized())
	var foot := lower.get_node_or_null("Foot") as Node3D
	if foot: foot.basis = (upper.basis * lower.basis).inverse()

func restore() -> void:
	for state in _saved:
		if is_instance_valid(state.node): state.node.transform = state.transform
	if is_instance_valid(_weapon): _weapon.visible = _weapon_visible
