extends RefCounted

## Presentation only: damage, ammo and fire cadence remain owned by Player.
## Arms use the existing rig lengths. Gun orientation is independent of the
## forearm so raising the elbow never points the barrel into the sky.
const PROFILES := {
	"pistol": [Vector3(0.19, 0.96, -0.27), Vector3.ZERO, 0.11, 15.0],
	"magnum": [Vector3(0.17, 0.99, -0.26), Vector3(-0.10, -0.04, 0.01), 0.22, 9.0],
	"smg": [Vector3(0.07, 0.94, -0.16), Vector3(-0.05, 0.0, -0.12), 0.055, 21.0],
	"shotgun": [Vector3(0.05, 0.98, -0.10), Vector3(-0.04, 0.0, -0.20), 0.24, 8.0],
	"sawed_off": [Vector3(0.19, 0.84, -0.23), Vector3.ZERO, 0.28, 8.0],
	"ak47": [Vector3(0.04, 1.0, -0.12), Vector3(-0.05, 0.0, -0.18), 0.10, 15.0],
	"m4a1": [Vector3(0.04, 1.02, -0.12), Vector3(-0.05, 0.0, -0.16), 0.07, 18.0],
	"hunting_rifle": [Vector3(0.06, 1.0, -0.10), Vector3(-0.025, -0.012, -0.20), 0.18, 9.0],
	"rpg": [Vector3(0.16, 1.07, -0.08), Vector3(-0.12, -0.06, -0.16), 0.18, 7.0],
	"flamethrower": [Vector3(0.06, 0.84, -0.10), Vector3(-0.08, 0.0, -0.20), 0.018, 18.0],
	"grenade": [Vector3(0.23, 0.92, -0.12), Vector3.ZERO, 0.0, 12.0],
	"knife": [Vector3(0.23, 0.84, -0.14), Vector3.ZERO, 0.0, 12.0],
	"fists": [Vector3(0.24, 0.68, -0.02), Vector3.ZERO, 0.0, 12.0],
}

# Mesh-space centres of the actual handles, not the receiver or barrel.
const GRIPS := {
	"pistol": Vector3(0, -0.03, 0.02), "magnum": Vector3(0, -0.05, 0.03),
	"smg": Vector3(0, -0.05, 0.03), "shotgun": Vector3(0, -0.04, 0.07),
	"sawed_off": Vector3(0, -0.05, 0.05), "ak47": Vector3(0, -0.06, 0.04),
	"m4a1": Vector3(0, -0.06, 0.04), "hunting_rifle": Vector3(0, -0.035, 0.035),
	"rpg": Vector3(0, 0, -0.10), "flamethrower": Vector3(0, -0.05, 0.03),
	"grenade": Vector3(0, 0, -0.10), "knife": Vector3(0, 0, 0.025),
	"fists": Vector3.ZERO,
}
const SUPPORT_GRIPS := {
	"magnum": Vector3(-0.035, -0.05, 0.03), "smg": Vector3(-0.02, -0.02, -0.15),
	"shotgun": Vector3(-0.02, -0.025, -0.16), "ak47": Vector3(-0.02, -0.015, -0.15),
	"m4a1": Vector3(-0.02, -0.012, -0.15), "hunting_rifle": Vector3(-0.02, -0.02, -0.18),
	"rpg": Vector3(-0.025, 0.035, -0.20), "flamethrower": Vector3(-0.02, 0, -0.22),
}
const HAND_REACH := 0.20
var _carry_pitch := 0.0

var weapon_id := ""
var recoil := 0.0
var action_age := 10.0
var equip_blend := 0.0
var punch_left := false
var _right_hand := Vector3(0.24, 0.68, -0.02)
var _left_hand := Vector3(-0.24, 0.68, -0.02)

func on_attack(id: String) -> void:
	var profile: Array = PROFILES.get(id, PROFILES.pistol)
	recoil = minf(recoil + float(profile[2]), float(profile[2]) * 1.6)
	action_age = 0.0
	if id == "fists":
		punch_left = not punch_left

func update(player: Node2D, delta: float, aiming: bool, sprinting: bool, arm_swing: float) -> void:
	if player.model_root == null or player.weapon_mount_node == null:
		return
	var id: String = player.active_weapon_id
	if weapon_id != id:
		weapon_id = id
		equip_blend = 0.0
		recoil = 0.0
		action_age = 10.0
	var p: Array = PROFILES.get(id, PROFILES.pistol)
	equip_blend = move_toward(equip_blend, 1.0, delta * 4.5)
	action_age += delta
	recoil *= exp(-float(p[3]) * delta)
	var engaged := aiming or action_age < 0.45
	var hand: Vector3 = p[0]
	var support: Vector3 = SUPPORT_GRIPS.get(id, Vector3.ZERO) - GRIPS.get(id, Vector3.ZERO) if SUPPORT_GRIPS.has(id) else Vector3.ZERO
	var pitch := 0.0
	# Low ready, aimed fire and sprint carry have separate silhouettes.
	if not engaged:
		hand.y -= 0.12 if not sprinting else 0.20
		hand.z += 0.07
		pitch -= 0.30 if not sprinting else 0.65
	hand.y -= (1.0 - equip_blend) * 0.16
	pitch -= (1.0 - equip_blend) * 0.45
	_carry_pitch = lerpf(_carry_pitch, pitch, 1.0 - exp(-14.0 * delta))
	pitch = _carry_pitch + recoil
	hand.z += recoil * 0.22
	var gun_basis := Basis(Vector3.RIGHT, pitch)
	var left_target := Vector3(-0.24, 0.69 if not sprinting else 0.78, arm_swing * (0.35 if sprinting else 0.23))
	if support != Vector3.ZERO:
		left_target = hand + gun_basis * support
		# Pump stroke follows the shot, rather than looping during walking.
		if id == "shotgun" and action_age > 0.10 and action_age < 0.48:
			left_target.z += sin((action_age - 0.10) / 0.38 * PI) * 0.08
	if id == "fists":
		if engaged:
			hand = Vector3(0.19, 0.99, -0.14)
			left_target = Vector3(-0.19, 1.0, -0.14)
		elif sprinting:
			hand = Vector3(0.19, 0.82, -arm_swing * 0.40)
			left_target = Vector3(-0.19, 0.82, arm_swing * 0.40)
		else:
			hand = Vector3(0.24, 0.69, -arm_swing * 0.23)
			left_target = Vector3(-0.24, 0.69, arm_swing * 0.23)
		if action_age < 0.30:
			var jab := sin(action_age / 0.30 * PI) * 0.18
			if punch_left:
				left_target.z -= jab
			else:
				hand.z -= jab
	elif id == "knife" and action_age < 0.36:
		var slash := sin(action_age / 0.36 * PI)
		hand += Vector3(-0.20 * slash, 0.10 * slash, -0.13 * slash)
		gun_basis = Basis(Vector3.UP, slash * 0.8) * gun_basis
	elif id == "grenade" and action_age < 0.45:
		var throw_arc := sin(action_age / 0.45 * PI)
		hand += Vector3(0.0, 0.22 * throw_arc, -0.17 * throw_arc)
	var blend := 1.0 - exp(-22.0 * delta)
	_right_hand = _right_hand.lerp(hand, blend)
	_left_hand = _left_hand.lerp(left_target, blend)
	var pump_stroke := 0.0
	if id == "shotgun" and action_age > 0.10 and action_age < 0.48:
		pump_stroke = sin((action_age - 0.10) / 0.38 * PI) * 0.08
	if support != Vector3.ZERO:
		# Keep both grips within reach, including low carry and torso lean.
		var offset := gun_basis * (support + Vector3(0, 0, pump_stroke))
		for iteration in 8:
			_right_hand = player.left_upper_arm.position - offset + (_right_hand + offset - player.left_upper_arm.position).limit_length(0.418)
			_right_hand = player.right_upper_arm.position + (_right_hand - player.right_upper_arm.position).limit_length(0.418)
	_solve_arm(player.right_upper_arm, player.right_lower_arm, _right_hand, 1.0)
	# Anchor stays on the glove; compensate the parent forearm's orientation.
	player.weapon_mount_node.position = Vector3(0.0, -HAND_REACH, 0.0)
	var forearm_basis: Basis = player.right_upper_arm.basis * player.right_lower_arm.basis
	player.weapon_mount_node.basis = forearm_basis.inverse() * gun_basis
	# Solve support from the realised firing hand (after smoothing and reach limits).
	if support != Vector3.ZERO:
		_left_hand = player.model_root.to_local(player.weapon_mount_node.to_global(support + Vector3(0, 0, pump_stroke)))
	_solve_arm(player.left_upper_arm, player.left_lower_arm, _left_hand, -1.0)
	for arm in [player.right_lower_arm, player.left_lower_arm]:
		var palm: Node3D = arm.get_node_or_null("Palm")
		if palm:
			var arm_basis: Basis = arm.get_parent().basis * arm.basis
			palm.basis = arm_basis.inverse() * gun_basis if id != "fists" and (arm == player.right_lower_arm or support != Vector3.ZERO) else Basis.IDENTITY
	var pump: Node3D = player.current_gun_mesh.get_node_or_null("Pump")
	if pump:
		pump.position.z = -0.16 + pump_stroke

func _solve_arm(upper: Node3D, lower: Node3D, target: Vector3, side: float) -> void:
	var shoulder := upper.position
	var direction := target - shoulder
	var distance := clampf(direction.length(), 0.05, 0.22 + HAND_REACH - 0.001)
	direction = direction.normalized()
	var bend := Vector3(side, -0.7, 0.4)
	bend = (bend - direction * bend.dot(direction)).normalized()
	var along := (0.22 * 0.22 - HAND_REACH * HAND_REACH + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, 0.22 * 0.22 - along * along))
	var elbow := shoulder + direction * along + bend * height
	upper.quaternion = Quaternion(Vector3.DOWN, (elbow - shoulder).normalized())
	var lower_direction := upper.basis.inverse() * (shoulder + direction * distance - elbow).normalized()
	lower.quaternion = Quaternion(Vector3.DOWN, lower_direction)
