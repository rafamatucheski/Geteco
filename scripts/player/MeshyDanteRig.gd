extends Node3D

## Opt-in skinned presentation. Player still owns movement, combat and room depth.
## Legacy anchors remain as lightweight pose targets; their meshes are hidden.
const MODEL_PATH := "res://assets/characters/meshy_dante/dante_grip.glb"
const SCALE := 0.82
const RETARGET := preload("res://scripts/player/MeshyAnchorRetarget.gd")
const APPEARANCE := preload("res://scripts/player/MeshyDanteAppearance.gd")
var material: ShaderMaterial
var _anchors := {}
var _driven_frame := -100
var skeleton: Skeleton3D
var animations: AnimationPlayer
var player: Node2D
var _bones := {}
var _rests: Array[Transform3D] = []
var _phase := 0.0
var _hidden_meshes: Array[GeometryInstance3D] = []
var _last_pose: Array[Transform3D] = []
var _transition := 1.0
var _clip := ""
var _skin_mesh: MeshInstance3D
var left_knuckles: Node3D

func configure(actor: Node2D) -> bool:
	player = actor
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null: return false
	var model := packed.instantiate() as Node3D
	add_child(model)
	model.scale = Vector3.ONE * SCALE
	model.rotation.y = PI
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	animations = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skin_mesh = model.find_child("Mesh0", true, false) as MeshInstance3D
	if skeleton == null or animations == null or _skin_mesh == null: return false
	for clip in ["Running", "Walking", "Walk_Backward"]:
		if not animations.has_animation(clip): return false
	animations.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for i in skeleton.get_bone_count():
		_bones[skeleton.get_bone_name(i)] = i
		_rests.append(skeleton.get_bone_rest(i))
	for bone in ["Hips", "Spine", "Spine01", "Spine02", "neck", "Head", "LeftShoulder", "RightShoulder", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand"]:
		if not _bones.has(bone): return false
	material = APPEARANCE.apply(_skin_mesh, skeleton, player.current_outfit_id)
	_anchors = RETARGET.find_anchors(player.model_root)
	# Roda depois do VehicleBoarding e do esqui, que posam as âncoras em _process.
	process_priority = 200
	for n in player.model_root.find_children("*", "GeometryInstance3D", true, false):
		if is_ancestor_of(n) or player.weapon_mount_node.is_ancestor_of(n): continue
		# Preserve the existing contact shadow and all non-mesh gameplay anchors.
		if n.get_parent() == player.model_root: continue
		if n.visible:
			_hidden_meshes.append(n)
			n.hide()
	return true

func restore() -> void:
	for mesh in _hidden_meshes:
		if is_instance_valid(mesh): mesh.show()
	_hidden_meshes.clear()

func prepare_pose(delta: float, moving: bool, sprinting: bool) -> void:
	if not is_instance_valid(skeleton): return
	_driven_frame = Engine.get_physics_frames()
	var clip := "Running" if moving and sprinting else "Walking"
	var direction := Vector2.ZERO
	if moving:
		var world_direction := Vector3(player.velocity.x, 0, player.velocity.y)
		var local_direction: Vector3 = player.model_root.basis.inverse() * world_direction
		direction = Vector2(local_direction.x, -local_direction.z).normalized()
		if direction.y < -0.5: clip = "Walk_Backward"
	if clip != _clip:
		_last_pose.clear()
		for i in skeleton.get_bone_count(): _last_pose.append(skeleton.get_bone_pose(i))
		_transition = 0.0 if not _clip.is_empty() else 1.0
		_clip = clip
	var animation := animations.get_animation(clip)
	var start := 2.0 / 30.0
	var duration := maxf(animation.length - start, 0.01)
	# Phase comes from actual travel, so a wall does not run the legs in place.
	if moving: _phase = fposmod(player.walk_clock / TAU, 1.0)
	animations.play(clip)
	animations.seek(start + _phase * duration, true)
	_transition = minf(1.0, _transition + delta * 7.0)
	for i in skeleton.get_bone_count():
		var pose := skeleton.get_bone_pose(i)
		# Upper-body aiming is independent of the locomotion clip.
		if i > 0 and i < int(_bones.LeftUpLeg): pose = _rests[i]
		# Blend into a planted standing pose; never leave the model in its T pose.
		pose = _rests[i].interpolate_with(pose, player._move_weight)
		# Upper limbs are solved procedurally below. Blending their previous
		# IK result into the new clip carries stale arm roll into the solver.
		if _transition < 1.0 and _last_pose.size() == skeleton.get_bone_count() and (i == 0 or i >= int(_bones.LeftUpLeg)):
			pose = _last_pose[i].interpolate_with(pose, _transition)
		skeleton.set_bone_pose(i, pose)
	# Remove root travel from the clip: CharacterBody2D owns displacement.
	var hips: int = _bones.Hips
	var hip_pos := skeleton.get_bone_pose_position(hips)
	hip_pos.x = _rests[hips].origin.x
	hip_pos.z = _rests[hips].origin.z
	skeleton.set_bone_pose_position(hips, hip_pos)
	# Stabilize the armed torso above the animated pelvis. Otherwise the
	# walk clip twists the lower shirt into arms already solved in aim space.
	if player.active_weapon_id != "fists":
		var lower_spine: int = _bones.Spine02
		var spine_pose := skeleton.get_bone_global_pose(lower_spine)
		spine_pose.basis = skeleton.get_bone_global_rest(lower_spine).basis
		skeleton.set_bone_global_pose(lower_spine, spine_pose)

func sync_shoulders() -> void:
	var spine: int = _bones.Spine
	var chest := skeleton.get_bone_global_pose(spine)
	chest.basis = Basis(Vector3.UP, player.torso_node.rotation.y) * skeleton.get_bone_global_rest(spine).basis
	skeleton.set_bone_global_pose(spine, chest)
	for side in ["Right", "Left"]:
		# Slight clavicle protraction is part of reaching forward. Leaving the
		# T-pose shoulders pinned behind the chest forced the sleeves inward.
		var clavicle: int = _bones[side + "Shoulder"]
		skeleton.set_bone_pose(clavicle, _rests[clavicle])
		var shoulder_pose := skeleton.get_bone_global_pose(clavicle)
		var shoulder_forward := 0.20
		shoulder_pose.basis = Basis(Vector3.UP, shoulder_forward if side == "Right" else -shoulder_forward) * shoulder_pose.basis
		skeleton.set_bone_global_pose(clavicle, shoulder_pose)
		var arm: Node3D = player.right_upper_arm if side == "Right" else player.left_upper_arm
		arm.position = player.model_root.to_local(skeleton.to_global(skeleton.get_bone_global_pose(_bones[side + "Arm"]).origin))

func update_pose(_delta: float, _moving: bool, _sprinting: bool) -> void:
	# Arms are solved after animation, preserving firing/reload targets and recoil.
	_solve_arm("Right", player.right_lower_arm.get_node("Palm"), 1.0)
	_solve_arm("Left", player.left_lower_arm.get_node("Palm"), -1.0)
	var armed: bool = player.active_weapon_id != "fists"
	var closed_fists: bool = player.active_weapon_id == "knuckles" and _skin_mesh.get_blend_shape_count() >= 4
	if is_instance_valid(_skin_mesh) and _skin_mesh.get_blend_shape_count() >= 2:
		_skin_mesh.set_blend_shape_value(0, 1.0 if armed and not closed_fists and _is_gripping("Right") else 0.0)
		_skin_mesh.set_blend_shape_value(1, 1.0 if armed and not closed_fists and (_is_gripping("Left") or player.active_weapon_id == "knuckles") else 0.0)
		if _skin_mesh.get_blend_shape_count() >= 4:
			_skin_mesh.set_blend_shape_value(2, 1.0 if closed_fists else 0.0)
			_skin_mesh.set_blend_shape_value(3, 1.0 if closed_fists else 0.0)
	sync_knuckles()

func sync_knuckles() -> void:
	if player.active_weapon_id != "knuckles":
		if is_instance_valid(left_knuckles): left_knuckles.hide()
		return
	if not is_instance_valid(left_knuckles):
		left_knuckles = Node3D.new()
		left_knuckles.name = "MeshyLeftKnuckles"
		add_child(left_knuckles)
		preload("res://scripts/player/ArsenalWeapon3D.gd").build(left_knuckles,"knuckles")
	# The imported finger row follows the calibrated palm's Y axis.
	# Turn the symmetric ring row into that axis on both closed fists.
	player.current_gun_mesh.rotation.z = PI/2
	var palm: Node3D = player.left_lower_arm.get_node("Palm")
	left_knuckles.global_transform = palm.global_transform * Transform3D(Basis(Vector3.BACK,PI/2),Vector3.ZERO)
	left_knuckles.show()

func _is_gripping(side: String) -> bool:
	if player.active_weapon_id == "knuckles": return true
	if side == "Right" and player.active_weapon_id == "grenade" and not player.current_gun_mesh.visible: return false
	# A holstered pistol/magnum is one-handed; the off-hand only closes into
	# a grip once it actually joins the gun while aiming or firing.
	if side == "Left" and player.active_weapon_id in ["pistol", "magnum"]:
		return player.combat_pose.is_engaged
	return player.active_weapon_id != "fists" and (side == "Right" or (not player.is_reloading() and player.combat_pose.SUPPORT_GRIPS.has(player.active_weapon_id)))

func _cross_grip(side: String) -> bool:
	return player.active_weapon_id in ["axe", "knife", "bat"] or (side == "Left" and player.active_weapon_id in ["smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle"])

func constrain_hand(target: Vector3, side: String, gun_basis: Basis) -> Vector3:
	var arm: Node3D = player.right_upper_arm if side == "Right" else player.left_upper_arm
	var fore: int = _bones[side + "ForeArm"]
	var hand: int = _bones[side + "Hand"]
	var reach := (_rests[fore].origin.length() + _rests[hand].origin.length()) * SCALE - 0.002
	# Leave a bend reserve in the support elbow instead of locking it across
	# the chest when a long shaft or shoulder-mounted weapon reaches forward.
	if side == "Left" and player.active_weapon_id in ["bat","axe","rpg"]: reach -= 0.025
	elif side == "Left" and player.active_weapon_id in ["smg","hunting_rifle"]: reach -= 0.015
	var offset := gun_basis * Vector3(0, 0, -0.065 * SCALE)
	if _cross_grip(side):
		offset = gun_basis * Vector3(0, 0.065 * SCALE, 0)
	if not _is_gripping(side):
		offset = Vector3.ZERO
		reach += 0.065 * SCALE
	# Constrain the wrist rather than shortening the whole arm by a fixed
	# palm radius. The latter pulled both sleeves back into the jacket.
	return arm.position + (target - offset - arm.position).limit_length(reach) + offset

func _solve_arm(side: String, palm: Node3D, sign_side: float) -> void:
	var upper: int = _bones[side + "Arm"]
	var fore: int = _bones[side + "ForeArm"]
	var hand: int = _bones[side + "Hand"]
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var target := skeleton.to_local(palm.global_position)
	# Hand bone is the wrist; the palm lies halfway along its long local Y axis.
	var model_basis: Basis = skeleton.global_basis.orthonormalized().inverse() * palm.global_basis.orthonormalized()
	# Meshy rolls the hand bone around the fingers. Its Z axis is mostly
	# across the palm (toward the thumb), not the palm normal. Calibrate
	# that roll before pointing the fingers toward the trigger.
	var roll := 0.358 if side == "Right" else -0.392
	var gripping := _is_gripping(side)
	var wrist_alignment := Basis(Vector3.RIGHT, -PI * 0.5 if gripping else PI)
	var hand_basis := model_basis * wrist_alignment * Basis(Vector3.UP, -roll)
	var palm_offset := Vector3(0, 0.065, 0)
	var wrist := target - hand_basis * palm_offset
	var a := _rests[fore].origin.length()
	var b := _rests[hand].origin.length()
	var free_tip := _rests[hand].origin + _rests[hand].basis * palm_offset
	if not gripping:
		# Solve to the palm with a straight wrist as part of the lower arm.
		wrist = target
		b = free_tip.length()
		skeleton.set_bone_pose(hand, _rests[hand])
	var axis := (wrist - shoulder).normalized()
	var distance := clampf(shoulder.distance_to(wrist), absf(a - b) + 0.001, a + b - 0.001)
	# Keep the elbow outside and in front of the jacket instead of folding
	# it down through the rib cage when both hands meet in front of the chest.
	var long_gun: bool = player.active_weapon_id in player.combat_pose.SKIN_LONG_GUNS or player.active_weapon_id in ["axe", "bat", "rpg", "flamethrower"]
	var elbow_width := 1.10 if long_gun else 0.65
	var elbow_forward := -1.35 if long_gun else -0.5
	var pole_world: Vector3 = player.model_root.global_basis * Vector3(sign_side * elbow_width, -1.5, elbow_forward)
	var pole := skeleton.global_basis.inverse() * pole_world
	var bend := (pole - axis * pole.dot(axis)).normalized()
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var elbow := shoulder + axis * along + bend * sqrt(maxf(0.0, a * a - along * along))
	_point_bone(upper, fore, elbow)
	if gripping:
		_point_bone(fore, hand, wrist)
		var fore_pose := skeleton.get_bone_global_pose(fore)
		var axis_fore := (skeleton.get_bone_global_pose(hand).origin - fore_pose.origin).normalized()
		var current_normal := skeleton.get_bone_global_pose(hand).basis.x
		var desired_normal := hand_basis.x
		current_normal = (current_normal - axis_fore * current_normal.dot(axis_fore)).normalized()
		desired_normal = (desired_normal - axis_fore * desired_normal.dot(axis_fore)).normalized()
		var twist := atan2(axis_fore.dot(current_normal.cross(desired_normal)), current_normal.dot(desired_normal))
		# Most grip roll belongs at the wrist. Large forearm roll collapses
		# the mixed upper-arm/forearm sleeve weights through the inner elbow.
		fore_pose.basis = Basis(axis_fore, clampf(twist, -1.2, 1.2)) * fore_pose.basis
		skeleton.set_bone_global_pose(fore, fore_pose)
		var hand_pose := skeleton.get_bone_global_pose(hand)
		hand_pose.basis = hand_basis
		skeleton.set_bone_global_pose(hand, hand_pose)
	else:
		var fore_pose := skeleton.get_bone_global_pose(fore)
		var from := (fore_pose.basis * free_tip).normalized()
		fore_pose.basis = Basis(Quaternion(from, (target - fore_pose.origin).normalized())) * fore_pose.basis
		skeleton.set_bone_global_pose(fore, fore_pose)

func _point_bone(bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var desired := (target - pose.origin).normalized()
	pose.basis = Basis(Quaternion(current, desired)) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)

## Fora da locomoção a pé, quem anima o Dante são as âncoras antigas: embarque
## (meta meshy_anchor_pose), esqui (a física retorna antes do prepare_pose),
## morte e cenas com a física do Player desligada. Sem isso o modelo congelava
## no último quadro de caminhada enquanto o corpo antigo, oculto, se movia.
func uses_anchor_pose() -> bool:
	return player.has_meta("meshy_anchor_pose") or player.is_skiing or player.is_dead \
		or Engine.get_physics_frames() - _driven_frame > 2

func _process(_delta: float) -> void:
	if not is_instance_valid(skeleton) or not uses_anchor_pose(): return
	for i in mini(_skin_mesh.get_blend_shape_count(), 4): _skin_mesh.set_blend_shape_value(i, 0.0)
	RETARGET.apply(skeleton, _bones, _rests, player.model_root, _anchors)

func flash_damage() -> void:
	if material == null: return
	material.set_shader_parameter("hit_flash", 1.0)
	var tween := create_tween()
	tween.tween_method(func(value: float): material.set_shader_parameter("hit_flash", value), 1.0, 0.0, 0.25)

func palm_position(side: String) -> Vector3:
	var pose := skeleton.get_bone_global_pose(_bones[side + "Hand"])
	return skeleton.to_global(pose * Vector3(0, 0.065, 0))
