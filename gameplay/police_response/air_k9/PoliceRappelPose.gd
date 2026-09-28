extends RefCounted
## Drives the visible anatomical rig, not the hidden legacy police bones.
## The actor's capsule remains under helicopter physics throughout this pose.
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
var officer: CharacterBody3D
var visual: Node3D
var body: Node3D
var phase := "attach"
var clock := 0.0
var active := false
var _body_processing := true
var _weapon_parent: Node
var _weapon_transform := Transform3D.IDENTITY
var _weapon_visible := true
var _body_transform := Transform3D.IDENTITY
var _contacts: Dictionary = {}
var _saved_hands: Array = [null, null]
var _saved_provider: Callable

func configure(actor: CharacterBody3D) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(actor.get("visual")): return false
	officer = actor
	visual = actor.visual
	if not visual.has_method("_install_body"): return false
	visual._install_body()
	body = visual.get("body") as Node3D
	if not is_instance_valid(body) or not is_instance_valid(body.get("pelvis")): return false
	_body_processing = body.is_processing()
	_body_transform = body.transform
	_saved_hands = body.hand_targets.duplicate()
	_saved_provider = body.hand_provider
	body.hand_provider = Callable()
	body.set_process(false)
	body.hand_targets = [null, null]
	visual.rappel_pose_active = true
	visual.flash_time = 0.0
	if is_instance_valid(visual.muzzle_flash_3d): visual.muzzle_flash_3d.hide()
	if is_instance_valid(visual.weapon):
		_weapon_parent = visual.weapon.get_parent()
		_weapon_transform = visual.weapon.transform
		_weapon_visible = visual.weapon.visible
		visual.weapon.reparent(body.spine, false)
		visual.weapon.visible = true
	active = true
	update(0.0, "attach", 0.0, actor.global_position + Vector3.UP * 4.0)
	return true

func update(delta: float, next_phase: String, progress: float, rope_world: Vector3) -> Dictionary:
	if not active or not is_instance_valid(officer) or not is_instance_valid(body): return {}
	phase = next_phase
	clock += maxf(delta, 0.0)
	progress = clampf(progress, 0.0, 1.0)
	var suspended := phase in ["attach", "descend"]
	var land := progress if phase == "land" else (1.0 if phase in ["release", "ready"] else 0.0)
	var release := smoothstep(.15, 1.0, progress) if phase == "release" else (1.0 if phase == "ready" else 0.0)
	var sway := sin(clock * 1.7) * .035 * (1.0 - land)
	var hip_height := lerpf(.91, .925, land) - (sin(progress * PI) * .19 if phase == "land" else 0.0)
	var hip_basis := Basis.from_euler(Vector3(lerpf(-.18, 0.0, land), sway * .65, sway))
	var hip_point := Vector3(sway * .4, hip_height, -.04 * (1.0 - land))
	body.pelvis.transform = Transform3D(hip_basis, hip_point)
	body.spine.transform = Transform3D(Basis.from_euler(Vector3(lerpf(-.12, .045, land), -.4 * sway, -sway * .5)), Vector3(0, .12, 0))
	body.head_node.transform = Transform3D(Basis.from_euler(Vector3(.10 + .12 * land, sin(clock*.8)*.045, 0)), Vector3(0, .4, 0))
	# Weight hangs in the waist/leg harness. Unequal ankle offsets avoid a rigid
	# seated mannequin; both feet plant and knees absorb the actual landing.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hang := Vector3(side * .17, .25 + .035 * sin(clock * 2.0 + i), .31 + .055 * sin(clock * 1.2 + i))
		var planted := Vector3(side * .13, KIT.ANKLE_HEIGHT, .035 if i == 0 else -.035)
		var ankle := hang.lerp(planted, smoothstep(0.0, .55, land))
		body._place_leg(i, hip_basis, hip_point, ankle, -.08 * (1.0 - land))
	var harness: Vector3 = visual.rappel_harness.global_position if is_instance_valid(visual.get("rappel_harness")) else body.pelvis.to_global(Vector3(.015, -.025, .174))
	var rope_direction := (rope_world - harness).normalized()
	if rope_direction.y < .25: rope_direction = Vector3.UP
	# Upper hand clamps the loaded line roughly half a metre above the harness.
	# Reach stays anatomical even while the helicopter gently drifts sideways.
	var upper := harness + rope_direction * (.64 + .025 * sin(clock * 2.1))
	var lower := harness - rope_direction * .11 + body.global_basis * Vector3(.09, -.03, .015)
	if not suspended and phase != "land":
		upper = upper.lerp(body.to_global(Vector3(-.18, 1.05, .26)), release)
		lower = lower.lerp(body.to_global(Vector3(.17, 1.08, .28)), release)
	_pose_arms([upper, lower])
	# Read the actual solved endpoints so the rope touches the gloves, even if
	# a short/tall body clamps a hand to its anatomical reach.
	_contacts = {
		"upper_hand": body.forearms[0].to_global(Vector3(0, -KIT.FOREARM - .06, 0)),
		"lower_hand": body.forearms[1].to_global(Vector3(0, -KIT.FOREARM - .06, 0)),
		"harness": harness,
		"attached": phase not in ["ready"] and not (phase == "release" and progress >= .60),
		"phase": phase,
	}
	if is_instance_valid(visual.weapon):
		# Rifle hangs by its sling against the chest, with muzzle down and away
		# from the rope. It moves into the hands only during the release phase.
		var slung := Transform3D(Basis.from_euler(Vector3(-1.20, PI, -.42)), Vector3(-.08, .06, .27))
		var ready := Transform3D(Basis.from_euler(Vector3(-.30, PI, .05)), Vector3(-.15, .10, .28))
		visual.weapon.transform = slung.interpolate_with(ready, release)
		if release > .6:
			_pose_arms([visual.weapon.to_global(visual.POSE_DATA.GRIPS[visual.weapon_id]), visual.weapon.to_global(visual.POSE_DATA.SUPPORT_GRIPS[visual.weapon_id])])
			_contacts.upper_hand = body.forearms[0].to_global(Vector3(0, -KIT.FOREARM - .06, 0))
			_contacts.lower_hand = body.forearms[1].to_global(Vector3(0, -KIT.FOREARM - .06, 0))
	return _contacts.duplicate()

func _pose_arms(targets: Array) -> void:
	var spine_model: Transform3D = body.pelvis.transform * body.spine.transform
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var local_target: Vector3 = body.to_local(targets[i])
		var solved: Array = body._reach_arm(i, spine_model, local_target, Vector3(side * .8, -.3, -.28))
		body.upper_arms[i].transform = Transform3D(solved[0], body._shoulders[i])
		body.forearms[i].transform = Transform3D(solved[1], Vector3(0, -KIT.UPPER_ARM, 0))
		body.hand_targets[i] = targets[i]

func rope_contact_positions() -> Dictionary:
	return _contacts.duplicate()

func finish() -> void:
	if not active: return
	active = false
	if is_instance_valid(visual):
		visual.rappel_pose_active = false
		if is_instance_valid(visual.weapon) and is_instance_valid(_weapon_parent):
			visual.weapon.reparent(_weapon_parent, false)
			visual.weapon.transform = _weapon_transform
			visual.weapon.visible = _weapon_visible
		if is_instance_valid(body):
			body.transform = _body_transform
			body.hand_targets = _saved_hands.duplicate()
			body.hand_provider = _saved_provider
			body.teleported()
			body.set_process(_body_processing and (not is_instance_valid(officer) or not officer.dead))
			if not is_instance_valid(officer) or not officer.dead: body._pose(0.0)
		if is_instance_valid(officer) and not officer.dead:
			visual.update_pose(.08, false, false, 0.0, 0.0)
	_contacts.clear()
