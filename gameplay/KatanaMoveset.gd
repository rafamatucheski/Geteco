extends RefCounted
## Two-handed vertical, diagonal and rising cuts, with controlled recovery.
## Reference: https://www.auskf.org/department/iaido/iaido-judging-points
## Keys use V1 rig coordinates; hands are converted to Dante's current scale.
const MOVES = preload("res://gameplay/MeleeMoveset.gd")
const CONTACT := [0.32, 0.32, 0.32]
const CUTS := [
	{"end":0.76,"keys":[
		{"t":0.21,"r":Vector3(0.02,1.36,-0.20),"d":Vector3(0,0.9,0.3),"k":Vector3.RIGHT,"hip":-0.08,"dip":0.02,"ease":"inout"},
		{"t":0.32,"r":Vector3(0.02,1.02,-0.40),"d":Vector3(0,0.05,-1),"hip":0.12,"lean":0.10,"step":0.045,"ease":"in"},
		{"t":0.46,"r":Vector3(0.02,0.82,-0.33),"d":Vector3(0,-0.32,-0.95),"dip":0.035,"ease":"out"}
	]},
	{"end":0.76,"keys":[
		{"t":0.21,"r":Vector3(0.13,1.29,-0.22),"d":Vector3(0.6,0.8,0.05),"k":Vector3(0.8,-0.6,0),"torso":-0.30,"hip":-0.16,"dip":0.02,"ease":"inout"},
		{"t":0.32,"r":Vector3(0.02,1.02,-0.40),"d":Vector3(-0.12,0.05,-1),"torso":0.16,"hip":0.20,"lean":0.09,"step":0.045,"ease":"in"},
		{"t":0.46,"r":Vector3(-0.12,0.84,-0.32),"d":Vector3(-0.65,-0.55,-0.5),"torso":0.32,"hip":0.22,"dip":0.025,"ease":"out"},
	]},
	{"end":0.76,"keys":[
		{"t":0.21,"r":Vector3(0.17,0.79,-0.26),"d":Vector3(0.45,-0.72,-0.5),"k":Vector3(1,0,0),"torso":-0.22,"hip":-0.15,"dip":0.03,"ease":"inout"},
		{"t":0.32,"r":Vector3(0.04,1.00,-0.40),"d":Vector3(0,0.15,-1),"k":Vector3(1,0,0),"torso":0.15,"hip":0.18,"step":0.04,"lean":0.07,"ease":"in"},
		{"t":0.46,"r":Vector3(-0.10,1.18,-0.29),"d":Vector3(-0.6,0.7,-0.3),"k":Vector3(1,0,0),"torso":0.32,"ease":"out"},
	]},
]

static func pose(combo: int, age: float, sprinting: bool, phase: float) -> Dictionary:
	var sway := sin(phase * TAU) * (0.025 if sprinting else 0.008)
	var rest := {"r":Vector3(0.03,0.88,-0.31+sway),
		"d":Vector3(0,-0.30 if sprinting else 0.30,-1),"k":Vector3.RIGHT,"torso":0.0,"hip":0.0,"lean":0.0,"dip":0.0,"step":0.0}
	var active := combo >= 0 and age < 0.76
	var channels: Dictionary = MOVES.sample("katana",CUTS[combo%3],age,rest,rest) if active else rest
	var basis: Basis = MOVES.swing_basis("katana",channels.d,channels.k)
	var hand: Vector3 = channels.r * (1.03 / 0.82)
	var palm_basis := basis * Basis(Vector3.RIGHT, PI * 0.5)
	return {"visible":true,"armed":true,"basis":basis,"right":hand,"left":hand+basis*Vector3(0,0,0.14),
		"right_basis":palm_basis,"left_basis":palm_basis,"grip_solver":true,"forearm_twist_share":0.65,"arm_rate":30.0 if active else 18.0,
		"gun_origin":hand-basis*Vector3(0,0,0.04),"weapon_scale":1.0,"right_solve":true,"left_solve":true,
		"right_grip":true,"left_grip":true,"grip_as_fist":true,"support_locked":true,"support_weight":1.0,
		"support_point":Vector3(0,0,0.18),"long_weapon":true,
		"torso_yaw":channels.torso,"hip_yaw":channels.hip,"lean":channels.lean,
		"dip":channels.dip,"step":channels.step,"melee_action":active}
