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
	"hunting_rifle": [Vector3(0.10, 1.0, -0.34), Vector3(-0.025, -0.012, -0.20), 0.18, 9.0],
	"rpg": [Vector3(0.16, 1.07, -0.08), Vector3(-0.12, -0.06, -0.16), 0.18, 7.0],
	"flamethrower": [Vector3(0.06, 0.84, -0.10), Vector3(-0.08, 0.0, -0.20), 0.018, 18.0],
	"grenade": [Vector3(0.23, 0.92, -0.12), Vector3.ZERO, 0.0, 12.0],
	"axe": [Vector3(0.20, 0.88, -0.16), Vector3.ZERO, 0.0, 10.0],
	"knife": [Vector3(0.21, 0.86, -0.16), Vector3.ZERO, 0.0, 14.0],
	"knuckles": [Vector3(0.22, 0.72, -0.06), Vector3.ZERO, 0.0, 14.0],
	"bat": [Vector3(0.18, 0.95, -0.10), Vector3(-0.04, -0.02, 0.08), 0.0, 11.0],
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
	"axe": Vector3(0, 0, 0.105), "knuckles": Vector3.ZERO,
	"bat": Vector3(0, 0, 0.10),
	"fists": Vector3.ZERO,
}
const SUPPORT_GRIPS := {
	"pistol": Vector3(-0.038, -0.033, 0.02),
	"sawed_off": Vector3(-0.012, -0.018, -0.055),
	"axe": Vector3(0, 0, -0.095),
	"magnum": Vector3(-0.035, -0.05, 0.03), "smg": Vector3(-0.02, -0.02, -0.15),
	"shotgun": Vector3(-0.02, -0.025, -0.16), "ak47": Vector3(-0.02, -0.015, -0.15),
	"m4a1": Vector3(-0.02, -0.012, -0.15), "hunting_rifle": Vector3(-0.025, -0.025, -0.14),
	"rpg": Vector3(-0.012, 0.0, -0.22), "flamethrower": Vector3(-0.012, -0.055, -0.14),
	"bat": Vector3(0, 0, 0.035),
}
# Rear faces of the stocks, including the compact SMG wire stock.
const STOCK_ENDS := {"smg": Vector3(0, 0.03, 0.19), "shotgun": Vector3(0, -0.04, 0.27), "ak47": Vector3(0, -0.02, 0.29), "m4a1": Vector3(0, 0, 0.25), "hunting_rifle": Vector3(0, -0.02, 0.19)}
const BAT_HIT_TIME := 0.24
const BAT_SWING_DURATION := 0.58
const AXE_HIT_TIME := 0.28
const AXE_SWING_DURATION := 0.72
const HAND_REACH := 0.20
const SKIN_HANDGUNS := ["pistol", "magnum"]
const SKIN_LONG_GUNS := ["ak47", "m4a1", "smg", "shotgun", "hunting_rifle"]
const SKIN_FIREARMS := ["pistol", "magnum", "ak47", "m4a1", "smg", "shotgun", "sawed_off", "hunting_rifle", "rpg", "flamethrower"]
var _carry_pitch := 0.0
var _carry_yaw := 0.0
var _stance_yaw := 0.0

var weapon_id := ""
var recoil := 0.0
var action_age := 10.0
# Exposed for MeshyDanteRig: idle pistols hang one-handed, the off-hand only
# comes up to support the grip while aiming/firing.
var is_engaged := false
var melee_support_active := false
var melee_support_weight := 0.0
var equip_blend := 0.0
var punch_left := false
var knife_variant := -1
var axe_variant := -1
var knuckle_variant := -1
var _right_hand := Vector3(0.24, 0.68, -0.02)
var _left_hand := Vector3(-0.24, 0.68, -0.02)

func on_attack(id: String, recoil_multiplier: float = 1.0) -> void:
	var profile: Array = PROFILES.get(id, PROFILES.pistol)
	recoil = minf(recoil + float(profile[2]) * recoil_multiplier, float(profile[2]) * 1.6 * recoil_multiplier)
	action_age = 0.0
	if id == "knife": knife_variant = (knife_variant + 1) % 3
	if id == "axe": axe_variant = (axe_variant + 1) % 2
	if id == "knuckles": knuckle_variant = (knuckle_variant + 1) % 4
	if id in ["fists", "knuckles"]:
		punch_left = not punch_left

func update(player: Node2D, delta: float, aiming: bool, sprinting: bool, arm_swing: float) -> void:
	if player.model_root == null or player.weapon_mount_node == null:
		return
	var id: String = player.active_weapon_id
	var skinned: bool = "meshy_rig" in player and is_instance_valid(player.meshy_rig)
	if weapon_id != id:
		weapon_id = id
		equip_blend = 0.0
		recoil = 0.0
		action_age = 10.0
		if skinned and id in SKIN_HANDGUNS:
			_carry_yaw = 0.0
			_right_hand = Vector3(0.035,0.96,-0.365)
		elif skinned and id == "smg":
			_right_hand = Vector3(0.02,0.93,-0.28)
	var p: Array = PROFILES.get(id, PROFILES.pistol)
	equip_blend = move_toward(equip_blend, 1.0, delta * 4.5)
	action_age += delta
	recoil *= exp(-float(p[3]) * delta)
	var engaged := aiming or action_age < 0.45
	is_engaged = engaged
	# A bladed shoulder stance gives the support arm room to reach the
	# fore-end while the stock actually meets the firing shoulder.
	var melee_pose: Dictionary = {}
	if id in ["axe", "bat"]:
		melee_pose = preload("res://scripts/player/MeshyMeleePose.gd").shoulder_swing(id, action_age, player.walk_clock, player._move_weight, player._sprint_weight, player.torso_node.position - Vector3(0, 0.85, 0))
	melee_support_weight = float(melee_pose.support_weight) if not melee_pose.is_empty() else 0.0
	melee_support_active = melee_support_weight > 0.995
	var shouldered := STOCK_ENDS.has(id) or id == "rpg"
	var stance := -0.60 if (shouldered or id == "flamethrower") and engaged else 0.0
	if skinned and id in SKIN_LONG_GUNS and not engaged: stance = -0.30
	if not melee_pose.is_empty(): stance = float(melee_pose.torso)
	_stance_yaw = lerpf(_stance_yaw, stance, 1.0 - exp(-12.0 * delta))
	if "torso_node" in player and player.torso_node and player.has_method("_sync_upper_body_anchors"):
		player.torso_node.rotation.y = sin(player.walk_clock) * 0.035 * player._move_weight + _stance_yaw
		player._sync_upper_body_anchors(player.torso_node.rotation.x)
	if skinned: player.meshy_rig.sync_shoulders()
	var hand: Vector3 = p[0]
	var support: Vector3 = SUPPORT_GRIPS.get(id, Vector3.ZERO) - GRIPS.get(id, Vector3.ZERO) if SUPPORT_GRIPS.has(id) else Vector3.ZERO
	if skinned and id == "axe": support = Vector3(0,0,-0.12)
	# A holstered pistol/magnum hangs from one hand; the off-hand only comes
	# up to brace the grip once the player is actually aiming or firing.
	if id in ["pistol", "magnum"] and not engaged: support = Vector3.ZERO
	var pitch := 0.0
	# Low ready, aimed fire and sprint carry have separate silhouettes.
	if not engaged:
		hand.y -= 0.12 if not sprinting else 0.20
		hand.z += 0.07
		if id == "hunting_rifle": hand.z -= 0.10
		pitch -= 0.30 if not sprinting else 0.65
	var long_gun := id in ["smg", "shotgun", "ak47", "m4a1", "rpg", "flamethrower", "hunting_rifle"]
	var carry_yaw := 0.0
	if long_gun:
		# Across-chest carriage sends the stock outside the ribs and keeps
		# magazines and barrels above the recovering knee.
		if not engaged:
			hand = Vector3(0.19 if id == "flamethrower" else 0.16, 0.97, -0.20)
			pitch = 0.45 if sprinting else 0.25
			carry_yaw = 0.65
			if skinned and id in SKIN_LONG_GUNS:
				# Keep the receiver aligned with the grip and lower the muzzle
				# slightly instead of twisting the rifle across both wrists.
				carry_yaw = 0.18
				pitch = -0.50 if sprinting else -0.40
		else:
			hand = Vector3(0.23, 1.02, 0.015)
			if STOCK_ENDS.has(id):
				hand = player.right_upper_arm.position - (STOCK_ENDS[id] - GRIPS[id]) + Vector3(0.065, 0.090, -0.075)
				if skinned and id in SKIN_LONG_GUNS:
					hand.y -= 0.14
			if id == "flamethrower": hand = Vector3(0.14, 1.00, -0.24)
			if id == "rpg": hand = player.right_upper_arm.position + Vector3(0.065, 0.050, -0.18)
		if id == "rpg" and not engaged: hand.x += 0.04
		if "torso_node" in player and player.torso_node:
			if not (engaged and shouldered): hand.y += player.torso_node.position.y - 0.85
	if id in ["pistol", "magnum"] and engaged:
		hand = Vector3(0.035, 1.09, -0.32)
	elif id in ["pistol", "magnum"]:
		# Keep a one-handed low carry while running. Raising the muzzle during a
		# sprint made the pistol read like a loose vertical prop below the glove.
		var run_weight: float = clampf(float(player.get("_sprint_weight")), 0.0, 1.0) if "_sprint_weight" in player else (1.0 if sprinting else 0.0)
		pitch = lerpf(-0.75, -0.88, run_weight)
		carry_yaw = lerpf(0.0, 0.08, run_weight)
	if id == "flamethrower" and not engaged:
		hand = Vector3(0.14, 0.99, -0.28)
		pitch = 0.18 if sprinting else -0.08
		carry_yaw = 0.30
	if id == "sawed_off":
		hand = Vector3(0.08, 1.02 if engaged else 0.98, -0.29)
	_carry_yaw = lerpf(_carry_yaw, carry_yaw, 1.0 - exp(-14.0 * delta))
	hand.y -= (1.0 - equip_blend) * 0.16
	pitch -= (1.0 - equip_blend) * 0.45
	_carry_pitch = lerpf(_carry_pitch, pitch, 1.0 - exp(-14.0 * delta))
	pitch = _carry_pitch + recoil
	hand.z += recoil * 0.22
	var gun_basis := Basis(Vector3.UP, _carry_yaw) * Basis(Vector3.RIGHT, pitch)
	var offhand_basis := gun_basis
	var left_target := Vector3(-0.215, 0.655 if not sprinting else 0.82, -0.055 + arm_swing * (0.30 if sprinting else 0.25))
	if support != Vector3.ZERO:
		left_target = hand + gun_basis * support
		# Pump stroke follows the shot, rather than looping during walking.
		if id == "shotgun" and action_age > 0.10 and action_age < 0.48:
			left_target.z += sin((action_age - 0.10) / 0.38 * PI) * 0.08
	if id == "fists":
		if action_age < 0.30:
			hand = Vector3(0.215, 0.65, -0.025)
			left_target = Vector3(-0.215, 0.65, -0.025)
		else:
			# Blend the arm carriage with the legs; holding Shift while stopped
			# must not snap the elbows into a running/boxing pose.
			var run: float = float(player.get("_sprint_weight")) if "_sprint_weight" in player else 0.0
			var hand_height := 0.65
			var hand_forward := -0.025
			var swing_scale := 0.22
			var torso: Node3D = player.get("torso_node")
			var body_offset: Vector3 = (torso.position - Vector3(0, 0.85, 0)) if torso != null else Vector3.ZERO
			hand = Vector3(0.215, hand_height, hand_forward - arm_swing * swing_scale) + body_offset
			left_target = Vector3(-0.215, hand_height, hand_forward + arm_swing * swing_scale) + body_offset
			if torso != null and run > 0.0:
				# Real running is not a fixed bent-elbow pose: the rear hand passes
				# behind the shoulder near the hip with a more open elbow, while the
				# forward hand rises with a shorter lever. Sweep that complete arc.
				var swing_limit := lerpf(0.32, 0.55, run)
				var right_cycle := clampf(arm_swing / swing_limit * 0.5 + 0.5, 0.0, 1.0)
				var left_cycle := 1.0 - right_cycle
				var right_angle := lerpf(-0.46, 1.15, right_cycle)
				var left_angle := lerpf(-0.46, 1.15, left_cycle)
				var right_radius := lerpf(0.27, 0.22, right_cycle)
				var left_radius := lerpf(0.27, 0.22, left_cycle)
				var right_run := Vector3(0.185, 0.20, 0) + Basis(Vector3.RIGHT, right_angle) * Vector3(0, -right_radius, 0)
				var left_run := Vector3(-0.185, 0.20, 0) + Basis(Vector3.RIGHT, left_angle) * Vector3(0, -left_radius, 0)
				hand = hand.lerp(torso.transform * right_run, run)
				left_target = left_target.lerp(torso.transform * left_run, run)
		if action_age < 0.30:
			var jab := sin(action_age / 0.30 * PI)
			if punch_left:
				left_target = left_target.lerp(Vector3(-0.12, 1.06, -0.38), jab)
			else:
				hand = hand.lerp(Vector3(0.12, 1.06, -0.38), jab)
	elif id == "knuckles":
		if engaged:
			hand = Vector3(0.18, 0.96, -0.16)
			left_target = Vector3(-0.18, 0.98, -0.16)
		else:
			var run_k: float = float(player.get("_sprint_weight")) if "_sprint_weight" in player else 0.0
			var torso_k: Node3D = player.get("torso_node")
			var body_offset_k: Vector3 = (torso_k.position - Vector3(0, 0.85, 0)) if torso_k != null else Vector3.ZERO
			hand = Vector3(0.20, lerpf(0.70, 0.78, run_k), -0.06 - arm_swing * 0.22) + body_offset_k
			left_target = Vector3(-0.20, lerpf(0.70, 0.78, run_k), -0.06 + arm_swing * 0.22) + body_offset_k
		if action_age < 0.28:
			var strike := sin(action_age / 0.28 * PI)
			var reach := strike * 0.22
			if punch_left:
				left_target += Vector3(0.04 * strike, 0.06 * strike, -reach)
			else:
				hand += Vector3(-0.04 * strike, 0.06 * strike, -reach)
				gun_basis = Basis(Vector3.UP, strike * 0.35) * gun_basis
		if skinned:
			var pose := preload("res://scripts/player/MeshyKnucklePose.gd").sample(knuckle_variant,action_age,engaged,arm_swing,player._sprint_weight)
			hand = pose.right
			left_target = pose.left
			gun_basis = pose.right_basis
			offhand_basis = pose.left_basis
	elif id == "knife":
		if engaged:
			hand = Vector3(0.21, 0.86, -0.16)
			left_target = Vector3(-0.215, 0.65, -0.025 + arm_swing * 0.22) + player.torso_node.position - Vector3(0, 0.85, 0)
		else:
			# A carried knife hangs beside the thigh instead of resting at the
			# waist. Keep a small fore/aft gait response without lifting the hand.
			hand = Vector3(0.21, 0.66 if sprinting else 0.68, -0.11 - arm_swing * 0.12)
			# The empty hand follows the relaxed gait, including torso bob.
			# Do not lift it into the generic armed sprint pose.
			left_target = Vector3(-0.215, 0.65, -0.025 + arm_swing * 0.22) + player.torso_node.position - Vector3(0, 0.85, 0)
		if action_age < 0.32:
			var thrust := sin(action_age / 0.32 * PI)
			hand += [Vector3(-0.035, 0.015, -0.23), Vector3(-0.12, 0.09, -0.16), Vector3(-0.055, -0.07, -0.20)][maxi(knife_variant, 0)] * thrust
			gun_basis = Basis(Vector3.UP, thrust * (0.45 if knife_variant == 1 else 0.08)) * Basis(Vector3.FORWARD, thrust * (0.25 if knife_variant == 2 else 0.05)) * gun_basis
	elif id == "grenade" and action_age < 0.45:
		var throw_arc := sin(action_age / 0.45 * PI)
		hand += Vector3(0.0, 0.22 * throw_arc, -0.17 * throw_arc)
	if id in ["axe", "bat"]:
		hand = melee_pose.hand
		gun_basis = melee_pose.basis
		var torso: Node3D = player.torso_node
		var relaxed := Vector3(-0.215, 0.65, -0.025 + arm_swing * 0.22) + torso.position - Vector3(0, 0.85, 0)
		var run: float = player._sprint_weight
		if run > 0.0:
			# Open the elbow behind the hip, then shorten the lever as the hand
			# swings forward. The free arm follows the opposing leg, not the gun.
			var cycle := 1.0 - clampf(arm_swing / lerpf(0.32, 0.55, run) * 0.5 + 0.5, 0.0, 1.0)
			var angle := lerpf(-0.46, 1.15, cycle)
			var radius := lerpf(0.27, 0.22, cycle)
			var running_hand := Vector3(-0.185, 0.20, 0) + Basis(Vector3.RIGHT, angle) * Vector3(0, -radius, 0)
			relaxed = relaxed.lerp(torso.transform * running_hand, run)
		left_target = relaxed.lerp(hand + gun_basis * support, melee_support_weight)
		if not melee_support_active: support = Vector3.ZERO
	if skinned and id == "grenade":
		var pose := preload("res://scripts/player/MeshyMeleePose.gd").sample(id, action_age, aiming)
		hand = pose.hand
		gun_basis = pose.basis
		left_target = pose.left if pose.has("left") else hand + gun_basis * support
		if id == "grenade":
			var loaded: bool = int(player.weapon_ammo.get(id,{}).get("clip",0)) > 0
			player.current_gun_mesh.visible = action_age < 0.20 or (action_age >= 0.70 and loaded)
	var reloading: bool = player.has_method("is_reloading") and bool(player.is_reloading())
	var reload_pump := 0.0
	if reloading:
		var progress: float = float(player.get_reload_progress()) if player.has_method("get_reload_progress") else 0.0
		var pose := reload_targets(id, progress)
		var weight: float = pose.weight
		hand = hand.lerp(pose.hand, weight)
		left_target = left_target.lerp(pose.left, weight)
		gun_basis = gun_basis.slerp(pose.basis, weight)
		reload_pump = pose.pump
		# The support hand leaves the foregrip to fetch and insert ammunition.
		# Do not snap it back to the firing grip in the two-handed IK pass below.
		support = Vector3.ZERO
	var blend := 1.0 - exp(-22.0 * delta)
	if skinned and id in SKIN_FIREARMS:
		# The imported shoulders are narrower and the sleeves are thicker.
		# Reach forward instead of lifting the elbow to keep the jacket clear.
		if id in SKIN_HANDGUNS and not reloading:
			if engaged:
				hand = Vector3(0.035, 1.08, -0.375)
			else:
				# A sprint is a compact one-handed carry, not the idle hand frozen
				# beside the thigh. Follow the torso and a short opposing gait arc so
				# the elbow stays bent while the actual grip remains locked to the palm.
				var run_weight: float = clampf(float(player.get("_sprint_weight")), 0.0, 1.0) if "_sprint_weight" in player else (1.0 if sprinting else 0.0)
				var body_offset: Vector3 = player.torso_node.position - Vector3(0, 0.85, 0)
				var relaxed_carry: Vector3 = Vector3(0.23, 0.80, -0.15) + body_offset
				var sprint_carry: Vector3 = Vector3(0.19, 0.70, -0.11 - arm_swing * 0.07) + body_offset
				hand = relaxed_carry.lerp(sprint_carry, run_weight)
			hand.z += recoil * 0.22
			# Idle carry stays one-handed; the off-hand only joins the grip
			# once the player actually aims or fires (support is zero until then).
			if engaged:
				left_target = hand + gun_basis * support
		else:
			if id in SKIN_LONG_GUNS and not engaged and not reloading:
				var carry_height: float = (player.right_upper_arm.position.y + player.left_upper_arm.position.y) * 0.5 - 0.17
				left_target.y += carry_height - hand.y
				hand.y = carry_height
			hand.z -= 0.080
			left_target.z -= 0.080
			if id == "sawed_off" and not reloading:
				hand = Vector3(0.055, 1.04 if engaged else 0.95, -0.36)
				left_target = hand + gun_basis * support
			elif id == "flamethrower" and not reloading:
				hand = Vector3(0.09, 0.96 if engaged else 0.90, -0.28)
				left_target = hand + gun_basis * support
			elif id == "rpg" and not reloading:
				hand = Vector3(0.06 if engaged else 0.02,1.10 if engaged else 0.97,-0.28)
				left_target = hand + gun_basis * support
			if reloading and left_target.z > -0.16: left_target.x = minf(left_target.x, -0.24)
			if reloading:
				var reload_hand := Vector3(0.06, 0.96, -0.34) if id in SKIN_HANDGUNS else Vector3(0.0, 0.98, -0.36)
				if left_target.z < -0.16: left_target += reload_hand - hand
				hand = reload_hand
	# The gait is already blended by Player. A second low-pass filter on free
	# hands delayed the arms relative to the opposing foot on every step.
	if id in ["fists", "knuckles"] and not engaged and not reloading and equip_blend >= 1.0:
		blend = 1.0
	_right_hand = _right_hand.lerp(hand, blend)
	_left_hand = _left_hand.lerp(left_target, blend)
	if id in ["axe", "bat"] and melee_support_weight == 0.0 and equip_blend >= 1.0:
		_left_hand = left_target
	if skinned:
		if id in SKIN_HANDGUNS and (engaged or reloading or equip_blend < 1.0):
			# A blend from a rifle reload must not drag the pistol through the
			# chest on the first equip frame.
			_right_hand.x = clampf(_right_hand.x, -0.03, 0.08)
			_right_hand.y = maxf(_right_hand.y, 0.94)
			_right_hand.z = minf(_right_hand.z, -0.33)
		_right_hand = player.meshy_rig.constrain_hand(_right_hand, "Right", gun_basis)
		_left_hand = player.meshy_rig.constrain_hand(_left_hand, "Left", offhand_basis if id == "knuckles" else gun_basis)
	var pump_stroke := 0.0
	if reloading: pump_stroke = reload_pump
	if id == "shotgun" and action_age > 0.10 and action_age < 0.48:
		pump_stroke = sin((action_age - 0.10) / 0.38 * PI) * 0.08
	if support != Vector3.ZERO:
		# Keep both grips within reach, including low carry and torso lean.
		var offset := gun_basis * (support + Vector3(0, 0, pump_stroke))
		for iteration in 8:
			if skinned:
				_right_hand = player.meshy_rig.constrain_hand(_right_hand + offset, "Left", gun_basis) - offset
				_right_hand = player.meshy_rig.constrain_hand(_right_hand, "Right", gun_basis)
			else:
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
			var gripping: bool = id != "fists" and (arm == player.right_lower_arm or support != Vector3.ZERO or (skinned and id == "knuckles"))
			var wrist := Basis.IDENTITY
			# Fore-end/shaft support wraps across its axis; a pistol-style
			# vertical palm on every weapon bent both wrists unnaturally.
			if id in ["axe", "knife", "bat"] or (arm == player.left_lower_arm and id in ["smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle"]):
				wrist = Basis(Vector3.RIGHT, PI * 0.5)
			palm.basis = arm_basis.inverse() * gun_basis * wrist if gripping else Basis.IDENTITY
			if skinned and id == "knuckles" and arm == player.left_lower_arm:
				palm.basis = arm_basis.inverse() * offhand_basis
			_set_grasp(palm, gripping, 1.0 if arm == player.right_lower_arm else -1.0)
	var pump: Node3D = player.current_gun_mesh.get_node_or_null("Pump")
	var loaded_rocket: Node3D = player.current_gun_mesh.get_node_or_null("LoadedRocket")
	if loaded_rocket and "weapon_ammo" in player:
		loaded_rocket.visible = int(player.weapon_ammo.get(id, {}).get("clip", 0)) > 0 or (reloading and player.get_reload_progress() > 0.65)
	if id == "axe":
		var trail: Node = player.current_gun_mesh.get_node_or_null("AxeSwingTrail")
		if trail: trail.update_blade(delta, action_age)
	if pump:
		pump.position.z = -0.16 + pump_stroke
	var cylinder: Node3D = player.current_gun_mesh.get_node_or_null("ReloadCylinder")
	if cylinder:
		var opening := 0.0
		if reloading:
			var phase: float = float(player.get_reload_progress()) if player.has_method("get_reload_progress") else 0.0
			opening = smoothstep(0.05, 0.18, phase) * (1.0 - smoothstep(0.79, 0.92, phase))
		cylinder.position.x = -0.065 * opening
		cylinder.rotation.z = -0.45 * opening

func axe_targets(age: float, engaged: bool, sprinting: bool) -> Dictionary:
	if axe_variant == 1 and age < AXE_SWING_DURATION:
		return axe_lateral_targets(age)
	var ready := Vector3(0.09, 0.94, -0.20)
	var hand := ready
	var tilt := 0.85
	var yaw := 0.0
	if age < AXE_SWING_DURATION:
		# Continuous key poses: load the weight, cut, absorb, return to guard.
		var lifted := Vector3(0.11, 1.10, -0.18)
		var contact := Vector3(0.07, 0.88, -0.27)
		var follow := Vector3(0.015, 0.84, -0.21)
		if age < 0.18:
			var t := smoothstep(0.0, 0.18, age)
			hand = ready.lerp(lifted, t)
			tilt = lerpf(0.85, 1.80, t)
			yaw = lerpf(0.0, -0.18, t)
		elif age < AXE_HIT_TIME:
			var t := smoothstep(0.18, AXE_HIT_TIME, age)
			hand = lifted.lerp(contact, t)
			tilt = lerpf(1.80, -0.05, t)
			yaw = lerpf(-0.18, 0.10, t)
		elif age < 0.39:
			var t := smoothstep(AXE_HIT_TIME, 0.39, age)
			hand = contact.lerp(follow, t)
			tilt = lerpf(-0.05, -0.48, t)
			yaw = lerpf(0.10, 0.20, t)
		else:
			var t := smoothstep(0.39, AXE_SWING_DURATION, age)
			hand = follow.lerp(ready, t)
			tilt = lerpf(-0.48, 0.85, t)
			yaw = lerpf(0.20, 0.0, t)
	elif not engaged:
		hand = Vector3(0.12, 0.86 if sprinting else 0.83, -0.13)
		tilt = 0.40 if sprinting else 0.10
	# Roll the cutting edge into the chopping plane, instead of striking flat.
	return {"hand": hand, "basis": Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt) * Basis(Vector3.BACK, -PI * 0.5)}

func axe_lateral_targets(age: float) -> Dictionary:
	var ready := Vector3(0.09, 0.94, -0.20)
	var loaded := Vector3(0.02, 1.0, -0.12)
	var contact := Vector3(0.055, 0.94, -0.24)
	# Finish ahead of the torso, with the shaft still pointing outward.
	var follow := Vector3(0.14, 0.95, -0.22)
	var hand: Vector3
	var yaw: float
	var pitch: float
	# The lateral sweep moves toward local -X: turn the edge into that motion.
	var roll: float
	if age < 0.18:
		var t := smoothstep(0.0, 0.18, age)
		hand = ready.lerp(loaded,t)
		yaw = lerpf(0,-0.90,t)
		pitch = lerpf(0.85,0.12,t)
		roll = lerpf(-PI * 0.5,-PI,t)
	elif age < AXE_HIT_TIME:
		var t := smoothstep(0.18,AXE_HIT_TIME,age)
		hand = loaded.lerp(contact,t)
		yaw = lerpf(-0.90,0.30,t)
		pitch = lerpf(0.12,0,t)
		roll = -PI
	elif age < 0.39:
		var t := smoothstep(AXE_HIT_TIME,0.39,age)
		hand = contact.lerp(follow,t)
		yaw = lerpf(0.30,0.70,t)
		pitch = 0.0
		roll = -PI
	else:
		var t := smoothstep(0.39,AXE_SWING_DURATION,age)
		hand = follow.lerp(ready,t)
		yaw = lerpf(0.70,0,t)
		pitch = lerpf(0,0.85,t)
		roll = lerpf(-PI,-PI * 0.5,t)
	return {"hand":hand,"basis":Basis(Vector3.UP,yaw) * Basis(Vector3.RIGHT,pitch) * Basis(Vector3.BACK,roll)}

func reload_targets(id: String, progress: float) -> Dictionary:
	# One normalized audio timeline: raise, manipulate, return to ready before
	# the recording finishes. The existing rig keeps the firing grip attached.
	var t := clampf(progress, 0.0, 1.0)
	var weight := smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.88, 1.0, t))
	var hand := Vector3(0.14, 0.91, -0.18)
	var tilt := Vector3(0.22, -0.16, -0.38)
	var insert := Vector3(0.02, 0.79, -0.18)
	var belt := Vector3(-0.19, 0.65, 0.03)
	var left := insert
	var pump := 0.0
	match id:
		"pistol":
			# Keep the magazine hand purposeful at the waist and under the grip;
			# the old hip target left the arm hanging straight down mid-reload.
			var magazine_well := Vector3(-0.01, 0.89, -0.22)
			var waist_magazine := Vector3(-0.16, 0.78, -0.02)
			var fetch := smoothstep(0.09, 0.22, t) * (1.0 - smoothstep(0.30, 0.47, t))
			left = magazine_well.lerp(waist_magazine, fetch)
			var rack := smoothstep(0.56, 0.65, t) * (1.0 - smoothstep(0.80, 0.89, t))
			left = left.lerp(Vector3(0.06, 0.98, -0.25 + _reload_stroke(t, 0.66, 0.81) * 0.07), rack)
		"smg", "ak47", "m4a1":
			var fetch := smoothstep(0.09, 0.22, t) * (1.0 - smoothstep(0.30, 0.47, t))
			left = insert.lerp(belt, fetch)
			var rack := smoothstep(0.56, 0.65, t) * (1.0 - smoothstep(0.80, 0.89, t))
			left = left.lerp(Vector3(0.07, 0.96, -0.20 + _reload_stroke(t, 0.66, 0.81) * 0.09), rack)
			if id in ["ak47", "m4a1"]:
				hand.x = 0.09
				tilt.z = -0.52
		"shotgun", "sawed_off", "hunting_rifle", "magnum":
			hand = Vector3(0.10, 0.87, -0.15)
			tilt = Vector3(0.05, -0.12, -0.62)
			insert = Vector3(-0.035, 0.84, -0.20)
			var load_motion := maxf(_reload_stroke(t, 0.12, 0.35), _reload_stroke(t, 0.39, 0.66))
			left = insert.lerp(belt, load_motion)
			if id == "magnum":
				tilt.z = -0.85
				left.x -= 0.045
			elif id == "shotgun":
				pump = _reload_stroke(t, 0.77, 0.94) * 0.09
				var grab := smoothstep(0.68, 0.77, t)
				var basis := Basis.from_euler(tilt)
				left = left.lerp(hand + basis * (SUPPORT_GRIPS.shotgun - GRIPS.shotgun + Vector3(0, 0, pump)), grab)
			elif id == "hunting_rifle":
				hand = Vector3(0.15, 0.87, -0.30)
				left = left.lerp(Vector3(0.06, 0.94, -0.13), smoothstep(0.68, 0.79, t))
		"rpg":
			hand = Vector3(0.17, 0.91, -0.07)
			tilt = Vector3(0.58, 0.0, -0.28)
			# Seat the rocket at the muzzle, then bring the support hand back to
			# a normal grip on the tube instead of leaving it pinned at the tip.
			var seat := smoothstep(0.16, 0.42, t) * (1.0 - smoothstep(0.58, 0.78, t))
			var regrip := smoothstep(0.58, 0.78, t)
			left = belt.lerp(Vector3(-0.03, 0.96, -0.26), seat).lerp(Vector3(-0.02, 0.90, -0.14), regrip)
		"flamethrower":
			tilt = Vector3(-0.18, 0.0, -0.43)
			left = Vector3(-0.06, 0.83, -0.17) + Vector3(sin(t * TAU * 2.0) * 0.035, cos(t * TAU * 2.0) * 0.025, 0)
		"grenade":
			hand = belt.lerp(Vector3(0.18, 0.92, -0.13), smoothstep(0.2, 0.82, t))
			left = Vector3(-0.17, 0.76, -0.05)
	# Manipulate the weapon ahead of the jacket; preserve the belt reach of
	# the free hand while moving insertion/racking targets with the receiver.
	tilt.y = 0.55
	var clearance_offset := Vector3(0.10, 0, -0.14)
	hand += clearance_offset
	left += clearance_offset * clampf(left.distance_to(belt) / 0.15, 0.0, 1.0)
	if id == "grenade":
		hand = Vector3(0.25, lerpf(0.72, 0.94, smoothstep(0.2, 0.82, t)), -0.16)
	return {"hand":hand, "left":left, "basis":Basis.from_euler(tilt), "weight":weight, "pump":pump}

func _reload_stroke(t: float, start: float, end: float) -> float:
	return sin(clampf((t - start) / (end - start), 0.0, 1.0) * PI)

func _set_grasp(palm: Node3D, gripping: bool, side: float) -> void:
	for part in palm.get_children():
		if not part.has_meta("rest_transform"): continue
		part.transform = part.get_meta("rest_transform")
		if not gripping: continue
		match str(part.name):
			"PalmBack":
				part.position = Vector3(side * 0.023, 0, 0.014)
				part.scale = Vector3(0.42, 1.0, 0.90)
			"Fingers":
				part.position = Vector3(0, -0.011, -0.025)
				part.scale = Vector3(1.0, 1.65, 0.85)
			"Thumb":
				part.position = Vector3(-side * 0.022, 0.019, -0.002)
				part.rotation = Vector3(0.55, 0, side * 0.35)

func _solve_arm(upper: Node3D, lower: Node3D, target: Vector3, side: float) -> void:
	var shoulder := upper.position
	var direction := target - shoulder
	var distance := clampf(direction.length(), 0.05, 0.22 + HAND_REACH - 0.001)
	direction = direction.normalized()
	# Elbows fold behind the ribcage. A predominantly lateral pole made both
	# arms flare out like wings, especially with bent sprint/reload poses.
	var bend := Vector3(side * 0.32, -0.80, 0.55)
	bend = (bend - direction * bend.dot(direction)).normalized()
	var along := (0.22 * 0.22 - HAND_REACH * HAND_REACH + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, 0.22 * 0.22 - along * along))
	var elbow := shoulder + direction * along + bend * height
	upper.quaternion = Quaternion(Vector3.DOWN, (elbow - shoulder).normalized())
	var lower_direction := upper.basis.inverse() * (shoulder + direction * distance - elbow).normalized()
	lower.quaternion = Quaternion(Vector3.DOWN, lower_direction)
