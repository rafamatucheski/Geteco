extends Node3D
## Geometry extracted from V1 PoliceOfficer without its private viewport.
enum UnitTier { REGULAR, DETECTIVE, SWAT, FBI, ARMY }
var tier := 0
var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var right_upper_arm: Node3D
var left_lower_arm: Node3D
var right_lower_arm: Node3D
var left_upper_leg: Node3D
var right_upper_leg: Node3D
var left_lower_leg: Node3D
var right_lower_leg: Node3D
var muzzle_flash_3d: MeshInstance3D
var mat_uniform: StandardMaterial3D
var _uniform_base_color: Color
var clock := 0.0
const POSE_DATA = preload("res://gameplay/WeaponPoseData.gd")
var weapon: Node3D
var weapon_id := "pistol"
var recoil := 0.0
var flash_time := 0.0
var hand := Vector3(0.19, 0.84, -0.20)
var left_hand := Vector3(-0.215, 0.655, -0.055)
var gun_basis := Basis.IDENTITY
var appearance_index := -1
var rappel_equipment: Node3D
var rappel_harness: Marker3D
var rappel_pose_active := false
var _body_aim_weight := 0.0
var _body_reloading := false
var _body_reload_progress := 0.0
var _weapon_hand_contacts: Array = [null, null]
static var _equipment_meshes: Dictionary = {}
const BODY_KIT = preload("res://assets/civilians/CivilianMeshKit.gd")

func equip(id: String) -> void:
	weapon_id = id
	weapon = Node3D.new()
	weapon.name = "PoliceWeapon"
	add_child(weapon)
	var tip := preload("res://gameplay/ArsenalWeapon3D.gd").build_cached(weapon, id)
	muzzle_flash_3d.reparent(weapon)
	muzzle_flash_3d.position = tip
	update_pose(1.0, false, false, 0.0, 0.0)

func muzzle_position() -> Vector3:
	return muzzle_flash_3d.global_position

func attack() -> void:
	recoil = float(POSE_DATA.PROFILES[weapon_id][2])
	flash_time = 0.05 # PoliceOfficer._fire_single_bullet, V1.
	muzzle_flash_3d.show()

func update_pose(delta: float, aiming: bool, reloading: bool, progress: float, gait: float) -> void:
	if rappel_pose_active: return
	if not is_instance_valid(weapon): return
	flash_time = maxf(0.0, flash_time - delta)
	muzzle_flash_3d.visible = flash_time > 0.0
	recoil *= exp(-float(POSE_DATA.PROFILES[weapon_id][3]) * delta)
	if is_instance_valid(body):
		_body_aim_weight = lerpf(_body_aim_weight, 1.0 if aiming else 0.0, 1.0 - exp(-14.0 * delta))
		_body_reloading = reloading
		_body_reload_progress = clampf(progress, 0.0, 1.0)
		# The visible rig is forward +Z, in metres; the retained legacy rig is
		# forward -Z with a different height and shorter arms. Mixing these spaces
		# put the rifle at the back of the head and stretched the visible hands.
		body.hand_provider = _body_weapon_targets
		body.hand_targets = _body_weapon_targets()
		return
	var pistol := weapon_id == "pistol"
	var target := Vector3(0.035, 1.09, -0.32) if aiming else Vector3(0.19, 0.84, -0.20)
	var pitch := 0.0 if aiming else -0.75
	var yaw := 0.0
	if not pistol:
		target = right_upper_arm.position - (POSE_DATA.STOCK_ENDS[weapon_id] - POSE_DATA.GRIPS[weapon_id]) + Vector3(0.065, 0.090, -0.075) if aiming else Vector3(0.16, 0.97, -0.20)
		pitch = 0.0 if aiming else 0.25
		yaw = 0.0 if aiming else 0.65
	var desired_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch + recoil)
	target.z += recoil * 0.22
	var left := Vector3(-0.215, 0.655, -0.055 + sin(gait) * 0.10)
	var support: Vector3 = POSE_DATA.SUPPORT_GRIPS[weapon_id] - POSE_DATA.GRIPS[weapon_id]
	if aiming or not pistol: left = target + desired_basis * support
	var supporting := (aiming or not pistol) and not reloading
	if reloading:
		# V1 magazine fetch, insertion and charging phases, in procedural rig space.
		var weight := smoothstep(0.0, 0.10, progress) * (1.0 - smoothstep(0.88, 1.0, progress))
		target = target.lerp(Vector3(0.24 if weapon_id in ["pistol", "smg"] else 0.19, 0.91, -0.32), weight)
		desired_basis = desired_basis.slerp(Basis.from_euler(Vector3(0.22, 0.55, -0.52 if weapon_id == "m4a1" else -0.38)), weight)
		var fetch := smoothstep(0.09, 0.22, progress) * (1.0 - smoothstep(0.30, 0.47, progress))
		var belt := Vector3(-0.19, 0.65, 0.03)
		var reload_left := Vector3(-0.01, 0.89, -0.22).lerp(Vector3(-0.16, 0.78, -0.02), fetch) if pistol else Vector3(0.02, 0.79, -0.18).lerp(belt, fetch)
		var rack := smoothstep(0.56, 0.65, progress) * (1.0 - smoothstep(0.80, 0.89, progress))
		var stroke := sin(clampf((progress - 0.66) / (0.81 - 0.66), 0.0, 1.0) * PI)
		reload_left = reload_left.lerp(Vector3(0.06, 0.98, -0.25 + stroke * 0.07) if pistol else Vector3(0.07, 0.96, -0.20 + stroke * 0.09), rack)
		reload_left += Vector3(0.10, 0, -0.14) * clampf(reload_left.distance_to(belt) / 0.15, 0.0, 1.0)
		left = left.lerp(reload_left, weight)
	hand = hand.lerp(target, 1.0 - exp(-22.0 * delta))
	left_hand = left_hand.lerp(left, 1.0 - exp(-22.0 * delta))
	gun_basis = gun_basis.slerp(desired_basis, 1.0 - exp(-14.0 * delta))
	if supporting:
		var offset := gun_basis * support
		for i in 8:
			hand = left_upper_arm.position - offset + (hand + offset - left_upper_arm.position).limit_length(0.418)
			hand = right_upper_arm.position + (hand - right_upper_arm.position).limit_length(0.418)
	_solve_arm(right_upper_arm, right_lower_arm, hand, 1.0)
	# The barrel basis is independent of the forearm: -Z always points forward.
	var realised := right_upper_arm.transform * right_lower_arm.transform * Vector3(0, -0.20, 0)
	weapon.transform = Transform3D(gun_basis, realised - gun_basis * POSE_DATA.GRIPS[weapon_id])
	if supporting: left_hand = weapon.transform * POSE_DATA.SUPPORT_GRIPS[weapon_id]
	_solve_arm(left_upper_arm, left_lower_arm, left_hand, -1.0)
	# Mãos do corpo novo no cabo e, apoiando, no guarda-mão. Índice 0 do corpo é o
	# lado direito do policial (o corpo é girado em PI dentro deste modelo).
	if is_instance_valid(body):
		body.hand_targets[0] = weapon.global_transform * POSE_DATA.GRIPS[weapon_id]
		body.hand_targets[1] = weapon.global_transform * POSE_DATA.SUPPORT_GRIPS[weapon_id] if supporting else null

func _solve_arm(upper: Node3D, lower: Node3D, target: Vector3, side: float) -> void:
	# V1 PlayerCombatPose two-bone solver; identical 0.22/0.20 bone lengths.
	var direction := target - upper.position
	var distance := clampf(direction.length(), 0.05, 0.419)
	direction = direction.normalized()
	var bend := Vector3(side * 0.32, -0.80, 0.55)
	bend = (bend - direction * bend.dot(direction)).normalized()
	var along := (0.22 * 0.22 - 0.20 * 0.20 + distance * distance) / (2.0 * distance)
	var elbow := upper.position + direction * along + bend * sqrt(maxf(0.0, 0.22 * 0.22 - along * along))
	upper.quaternion = Quaternion(Vector3.DOWN, (elbow - upper.position).normalized())
	lower.quaternion = Quaternion(Vector3.DOWN, upper.basis.inverse() * (upper.position + direction * distance - elbow).normalized())
func _ready() -> void:
	model_root = self
	scale = Vector3.ONE * 1.28
	var appearances = preload("res://gameplay/PoliceAppearance.gd")
	if appearance_index < 0:
		appearance_index = appearances.next_model % appearances.PROFILES.size()
		appearances.next_model += 1
	var appearance: Dictionary = appearances.PROFILES[posmod(appearance_index, appearances.PROFILES.size())]
	set_meta("police_appearance", appearance)
	scale *= float(appearance.height)
	# Cores e Fardas de Acordo com o Escalão Tático (Tier)
	var uniform_col := Color(0.11, 0.15, 0.24) # Azul Polícia Regular
	if tier == UnitTier.ARMY:
		uniform_col = Color(0.24, 0.32, 0.20) # Camuflado Militar Verde-Oliva
	elif tier == UnitTier.FBI:
		uniform_col = Color(0.08, 0.08, 0.10) # Terno Preto FBI
	elif tier == UnitTier.SWAT:
		uniform_col = Color(0.12, 0.13, 0.16) # Preto Tático SWAT
	elif tier == UnitTier.DETECTIVE:
		uniform_col = Color(0.35, 0.26, 0.18) # Sobretudo Castanho / Couro
		
	mat_uniform = _make_mat(uniform_col, 0.82)
	_uniform_base_color = uniform_col
	var mat_skin := _make_mat(Color(get_meta("police_appearance").skin), 0.65)
	var mat_gold := _make_mat(Color(0.92, 0.78, 0.20), 0.3)
	var mat_black := _make_mat(Color(0.08, 0.08, 0.10), 0.4)
	var mat_gun := _make_mat(Color(0.20, 0.22, 0.25), 0.2)
	var mat_vest := _make_mat(Color(0.05, 0.05, 0.07), 0.3)
	var mat_fbi_yellow := _make_mat(Color(0.95, 0.85, 0.15), 0.3)

	# Torso 3D
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := preload("res://gameplay/PoliceAppearance.gd").uniform_body(mat_uniform, get_meta("police_appearance").get("woman", false))
	torso_mesh.scale = Vector3(float(appearance.width), 1.0, float(appearance.depth))
	torso_node.add_child(torso_mesh)

	# Colete Tático Blindado Kevlar (SWAT, FBI e Exército)
	if tier >= UnitTier.SWAT:
		var vest := MeshInstance3D.new()
		var box_v := BoxMesh.new()
		box_v.size = Vector3(0.38, 0.34, 0.36)
		vest.mesh = box_v
		vest.material_override = mat_vest
		vest.position = Vector3(0.0, 0.05, 0.0)
		torso_node.add_child(vest)
		
		if tier == UnitTier.FBI:
			var fbi_logo := MeshInstance3D.new()
			var box_fl := BoxMesh.new()
			box_fl.size = Vector3(0.18, 0.08, 0.02)
			fbi_logo.mesh = box_fl
			fbi_logo.material_override = mat_fbi_yellow
			fbi_logo.position = Vector3(0.0, 0.08, -0.19)
			torso_node.add_child(fbi_logo)
	else:
		# Distintivo Dourado de Polícia Regular
		var badge := MeshInstance3D.new()
		var box_bg := BoxMesh.new()
		box_bg.size = Vector3(0.06, 0.07, 0.02)
		badge.mesh = box_bg
		badge.material_override = mat_gold
		badge.position = Vector3(-0.07, 0.12, -0.165)
		torso_node.add_child(badge)

	# Cinto Tático de Serviço
	var belt := MeshInstance3D.new()
	var box_bl := BoxMesh.new()
	box_bl.size = Vector3(0.36, 0.05, 0.34)
	belt.mesh = box_bl
	belt.material_override = mat_black
	belt.position = Vector3(0.0, -0.18, 0.0)
	torso_node.add_child(belt)

	# Cabeça 3D (Capacete Tático, Quepe ou Óculos Escuros)
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.21, 0.0)
	# Scale the complete head so the cap, helmet and facial details stay fitted.
	head_node.scale = Vector3(0.62, 0.70, 0.62)
	model_root.add_child(head_node)
	torso_node.add_child(_create_limb(0.05, 0.14, mat_skin, Vector3(0.0, 0.24, 0.0)))

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.17
	sph_h.height = 0.34
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	if tier == UnitTier.SWAT or tier == UnitTier.ARMY:
		# Capacete Tático Balístico Militar / SWAT
		var helmet := MeshInstance3D.new()
		var sph_hl := SphereMesh.new()
		sph_hl.radius = 0.195
		sph_hl.height = 0.32
		helmet.mesh = sph_hl
		helmet.material_override = mat_vest if tier == UnitTier.SWAT else _make_mat(Color(0.20, 0.28, 0.18), 0.4)
		helmet.position = Vector3(0.0, 0.08, 0.0)
		helmet.name = "CoveredCrown"
		head_node.add_child(helmet)
		
		if tier == UnitTier.SWAT:
			var visor_g := MeshInstance3D.new()
			var box_vg := BoxMesh.new()
			box_vg.size = Vector3(0.24, 0.08, 0.08)
			visor_g.mesh = box_vg
			visor_g.material_override = _make_mat(Color(0.1, 0.4, 0.8), 0.1)
			visor_g.position = Vector3(0.0, 0.04, -0.16)
			head_node.add_child(visor_g)
	else:
		# Quepe Policial Clássico com Aba
		var cap_hat := MeshInstance3D.new()
		var box_cp := CylinderMesh.new()
		box_cp.top_radius = 0.185
		box_cp.bottom_radius = 0.17
		box_cp.height = 0.11
		box_cp.radial_segments = 12
		cap_hat.mesh = box_cp
		cap_hat.material_override = mat_uniform
		cap_hat.position = Vector3(0.0, 0.15, 0.0)
		cap_hat.name = "CoveredCrown"
		head_node.add_child(cap_hat)

		var visor := MeshInstance3D.new()
		var box_vs := BoxMesh.new()
		box_vs.size = Vector3(0.24, 0.02, 0.12)
		visor.mesh = box_vs
		visor.material_override = mat_black
		visor.position = Vector3(0.0, 0.08, -0.18)
		head_node.add_child(visor)

	# Braços 3D
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.185, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.042, 0.18, mat_skin if tier < UnitTier.SWAT else mat_black, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.185, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.042, 0.18, mat_skin if tier < UnitTier.SWAT else mat_black, Vector3(0, -0.09, 0)))

	# Weapon geometry is supplied by NPCCombatRig after the articulated rig.
	muzzle_flash_3d = MeshInstance3D.new()
	var sph_f := SphereMesh.new()
	sph_f.radius = 0.07
	sph_f.height = 0.14
	muzzle_flash_3d.mesh = sph_f
	muzzle_flash_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat_fl := StandardMaterial3D.new()
	mat_fl.albedo_color = Color(1.0, 0.85, 0.2)
	mat_fl.emission_enabled = true
	mat_fl.emission = Color(1.0, 0.6, 0.1)
	mat_fl.emission_energy_multiplier = 4.0
	mat_fl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash_3d.material_override = mat_fl
	muzzle_flash_3d.position = Vector3(0.0, -0.18, -0.22 if tier < UnitTier.SWAT else -0.32)
	muzzle_flash_3d.visible = false
	right_lower_arm.add_child(muzzle_flash_3d)

	# Pernas 3D
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.65, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.068, 0.30, mat_uniform, Vector3(0, -0.15, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.30, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.058, 0.30, mat_uniform, Vector3(0, -0.15, 0)))
	left_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.3075, -0.035)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.65, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.068, 0.30, mat_uniform, Vector3(0, -0.15, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.30, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.058, 0.30, mat_uniform, Vector3(0, -0.15, 0)))
	right_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.3075, -0.035)))
	# Keep kinematic bones uniform; diversity changes sleeves, not IK lengths.
	for upper in [left_upper_arm, right_upper_arm]:
		upper.position.x *= float(appearance.width)
		for child in upper.get_children():
			if child is MeshInstance3D: child.scale = Vector3(float(appearance.limb), 1.0, float(appearance.limb))
	# Corpo articulado dos pedestres no lugar da geometria antiga. Diferido para
	# subclasses (segurança do banco) terminarem de refazer farda e escala antes.
	_install_body.call_deferred()

var body: Node3D

func _install_body() -> void:
	if is_instance_valid(body) or not is_inside_tree(): return
	var keep: Array = [muzzle_flash_3d]
	if is_instance_valid(weapon): keep.append(weapon)
	body = preload("res://assets/civilians/RigBodySwap.gd").install(self, _body_look(), keep)
	if tier >= UnitTier.SWAT: _install_tactical_equipment()
	body.hand_provider = _body_weapon_targets
	if is_instance_valid(weapon):
		body.hand_targets = _body_weapon_targets()
		body._pose(0.0)

func _body_weapon_targets() -> Array:
	if not is_instance_valid(body) or not is_instance_valid(weapon) or rappel_pose_active: return [null, null]
	var pistol := weapon_id == "pistol"
	var spine_model: Transform3D = body.pelvis.transform * body.spine.transform
	var right_shoulder: Vector3 = spine_model * body._shoulders[0]
	var left_shoulder: Vector3 = spine_model * body._shoulders[1]
	var ready_grip := Vector3(-.20, .93, .12) if pistol else Vector3(-.15, 1.16, .26)
	var aim_grip := Vector3(-.075, 1.34, .40)
	var pitch := lerpf(-.95 if pistol else -.43, 0.0, _body_aim_weight) + recoil
	var yaw := PI + lerpf(.0 if pistol else -.22, 0.0, _body_aim_weight)
	var desired_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	if not pistol:
		var stock_offset: Vector3 = desired_basis * (POSE_DATA.STOCK_ENDS[weapon_id] - POSE_DATA.GRIPS[weapon_id])
		aim_grip = right_shoulder - stock_offset + Vector3(.015, -.035, .02)
	var grip := ready_grip.lerp(aim_grip, _body_aim_weight)
	grip.z -= recoil * .12
	var support_offset: Vector3 = desired_basis * (POSE_DATA.SUPPORT_GRIPS[weapon_id] - POSE_DATA.GRIPS[weapon_id])
	var supports := not pistol or _body_aim_weight > .35
	if supports:
		# Both hands and the single weapon share one rigid frame. Fit that frame
		# to both anatomical reach spheres instead of solving two unrelated arms.
		for iteration in 8:
			grip = right_shoulder + (grip - right_shoulder).limit_length(.594)
			grip = left_shoulder - support_offset + (grip + support_offset - left_shoulder).limit_length(.594)
	else:
		grip = right_shoulder + (grip - right_shoulder).limit_length(.594)
	var left_target: Variant = grip + support_offset if supports else null
	if _body_reloading:
		var progress := _body_reload_progress
		var weight := smoothstep(0.0, .10, progress) * (1.0 - smoothstep(.88, 1.0, progress))
		var belt := Vector3(.19, .98, .13)
		var magazine := grip + desired_basis * Vector3(.035, -.06, -.025)
		var fetch := smoothstep(.08, .23, progress) * (1.0 - smoothstep(.32, .50, progress))
		var service := magazine.lerp(belt, fetch)
		var rack := smoothstep(.60, .69, progress) * (1.0 - smoothstep(.79, .90, progress))
		service = service.lerp(grip + desired_basis * Vector3(.03, .10, -.055), rack)
		left_target = (grip + support_offset).lerp(service, weight)
		left_target = left_shoulder + ((left_target as Vector3) - left_shoulder).limit_length(.594)
	var world_basis := body.global_basis * desired_basis
	var world_grip := body.to_global(grip)
	weapon.global_transform = Transform3D(world_basis, world_grip - world_basis * POSE_DATA.GRIPS[weapon_id])
	_weapon_hand_contacts = [world_grip, body.to_global(left_target) if left_target is Vector3 else null]
	return _weapon_hand_contacts.duplicate()

func weapon_hand_contacts() -> Array:
	return _weapon_hand_contacts.duplicate()

## Equipment is merged into the articulated native body meshes. Each joint
## retains its original draw surface instead of adding dozens of tiny nodes.
func _install_tactical_equipment() -> void:
	if not is_instance_valid(body) or is_instance_valid(rappel_equipment): return
	var palette := {"top_color": _uniform_base_color, "accent_color": Color("343b40") if tier != UnitTier.ARMY else Color("4b5134")}
	for joint in [body.spine, body.pelvis, body.head_node]:
		var part := "chest" if joint == body.spine else ("belt" if joint == body.pelvis else "helmet")
		_merge_equipment(joint, part)
		for key in palette: joint.set_instance_shader_parameter(key, palette[key])
	for i in 2:
		_merge_equipment(body.forearms[i], "glove")
		_merge_equipment(body.thighs[i], "thigh")
		_merge_equipment(body.shins[i], "knee")
	rappel_equipment = Node3D.new()
	rappel_equipment.name = "RappelHarness"
	body.pelvis.add_child(rappel_equipment)
	rappel_harness = Marker3D.new()
	rappel_harness.name = "DescenderAttachment"
	rappel_harness.position = Vector3(.015, -.025, .174)
	rappel_equipment.add_child(rappel_harness)
	# The same geometry is already part of the rig at all times; this marker
	# names the real attachment for rope simulation and tests.
	rappel_harness.set_meta("load_bearing_attachment", true)

func _merge_equipment(joint: MeshInstance3D, part: String) -> void:
	var key := "%d|%s|%d" % [tier, part, joint.mesh.get_rid().get_id()]
	if not _equipment_meshes.has(key):
		var b = BODY_KIT._builder()
		_build_equipment(b, part)
		var extra: ArrayMesh = b.commit()
		var original: Array = joint.mesh.surface_get_arrays(0)
		var addition: Array = extra.surface_get_arrays(0)
		var offset: int = original[Mesh.ARRAY_VERTEX].size()
		# Godot returns generated tangents on readback even though this rigid
		# cloth shader uses vertex normals only. The old tangent stream cannot
		# keep its old vertex count after equipment vertices are appended.
		original[Mesh.ARRAY_TANGENT] = null
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
			var stream: Variant = original[channel]
			stream.append_array(addition[channel])
			original[channel] = stream
		var indices: PackedInt32Array = original[Mesh.ARRAY_INDEX]
		for index in addition[Mesh.ARRAY_INDEX]: indices.append(int(index) + offset)
		original[Mesh.ARRAY_INDEX] = indices
		var merged := ArrayMesh.new()
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, original)
		merged.surface_set_material(0, BODY_KIT.material())
		for surface in range(1, joint.mesh.get_surface_count()):
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, joint.mesh.surface_get_arrays(surface))
			merged.surface_set_material(surface, joint.mesh.surface_get_material(surface))
		_equipment_meshes[key] = merged
	joint.mesh = _equipment_meshes[key]

func _build_equipment(b: RefCounted, part: String) -> void:
	var cloth := BODY_KIT.SLOT_ACCENT
	var dark := BODY_KIT.SLOT_SHOE
	var metal := BODY_KIT.SLOT_METAL
	match part:
		"chest":
			# Shaped front/back plates, padded shoulders and sewn webbing rows.
			for side in [-1.0, 1.0]:
				var front := .187 if side > 0 else -.168
				b.loft([[.31,.125,.017,cloth,front,4.0],[.255,.172,.028,cloth,front,4.0],[.065,.177,.026,cloth,front,4.0],[.018,.14,.020,cloth,front,4.0]],cloth,Transform3D.IDENTITY,12)
			for side in [-1.0, 1.0]:
				b.ellipsoid(Vector3(side*.12,.34,.014),Vector3(.040,.025,.145),cloth,Basis.IDENTITY,8,4)
				for y in [.08,.125,.17]:
					_equipment_box(b,Vector3(side*.09,y,.221),Vector3(.14,.012,.014),dark)
			# Three soft magazine pouches with angular fabric flaps.
			for x in [-.116,0.0,.116]:
				b.loft([[.15,.042,.03,cloth,.241,4.0],[.135,.047,.037,cloth,.241,4.0],[.01,.047,.036,cloth,.241,4.0],[-.005,.038,.025,cloth,.241,4.0]],cloth,Transform3D(Basis.IDENTITY,Vector3(x,0,0)),8)
				_equipment_box(b,Vector3(x,.14,.279),Vector3(.07,.032,.01),dark)
			# Radio, aerial, shoulder microphone; upper plate and back panel seams.
			_equipment_box(b,Vector3(-.158,.255,.215),Vector3(.065,.10,.065),dark)
			_equipment_box(b,Vector3(-.174,.355,.222),Vector3(.009,.15,.009),dark)
			_equipment_box(b,Vector3(.12,.30,.213),Vector3(.04,.05,.023),dark)
			_equipment_box(b,Vector3(.03,.255,.217),Vector3(.12,.047,.01),BODY_KIT.SLOT_INNER)
			b.loft([[.35,.018,.008,dark],[-.12,.018,.008,dark]],dark,Transform3D(Basis(Vector3.FORWARD,-.50),Vector3(-.03,0,.289)),6)
		"belt":
			# Waist webbing follows the pelvis; descender buckle stands forward.
			b.loft([[.026,.182,.144,dark,0.0,3.0],[-.033,.181,.146,dark,0.0,3.0]],dark,Transform3D.IDENTITY,16,false,false)
			_equipment_box(b,Vector3(.015,-.018,.16),Vector3(.071,.062,.026),metal)
			_equipment_box(b,Vector3(.015,-.018,.177),Vector3(.033,.036,.012),dark)
			for side in [-1.0,1.0]:
				_equipment_box(b,Vector3(side*.18,-.032,-.025),Vector3(.075,.10,.095),cloth)
				var strap := Transform3D(Basis(Vector3.FORWARD,side*.28),Vector3(side*.11,-.09,.123))
				b.loft([[.04,.020,.01,dark,0.0,3.5],[-.1,.020,.01,dark,0.0,3.5]],dark,strap,6)
		"helmet":
			# Rails, headset, NVG bracket and chin restraint fit the anatomical head.
			if tier != UnitTier.FBI:
				for side in [-1.0,1.0]:
					_equipment_box(b,Vector3(side*.118,.177,-.005),Vector3(.028,.042,.105),dark)
					b.ellipsoid(Vector3(side*.123,.10,-.016),Vector3(.027,.053,.041),cloth,Basis.IDENTITY,8,5)
					_equipment_box(b,Vector3(side*.079,.046,.025),Vector3(.012,.081,.018),dark)
				_equipment_box(b,Vector3(0,.23,.122),Vector3(.045,.055,.025),metal)
				_equipment_box(b,Vector3(0,.04,.076),Vector3(.11,.014,.021),dark)
			else:
				b.ellipsoid(Vector3(.113,.095,-.018),Vector3(.012,.024,.014),dark,Basis.IDENTITY,6,4)
		"glove":
			# Layered cuff, glove palm/knuckles and curled leather fingers.
			b.loft([[-.21,.037,.035,dark],[-.255,.034,.032,dark]],dark,Transform3D.IDENTITY,10)
			b.ellipsoid(Vector3(0,-.306,.007),Vector3(.030,.062,.047),dark,Basis.IDENTITY,10,6)
			b.ellipsoid(Vector3(0,-.350,.015),Vector3(.028,.033,.040),dark,Basis(Vector3.RIGHT,-.5),8,5)
			for z in [-.022,.003,.028]:
				b.ellipsoid(Vector3(.019,-.299,z),Vector3(.017,.011,.010),cloth,Basis.IDENTITY,6,4)
		"thigh":
			b.loft([[-.09,.10,.096,dark],[-.128,.098,.095,dark]],dark,Transform3D.IDENTITY,12,false,false)
			_equipment_box(b,Vector3(.065,-.205,.02),Vector3(.055,.125,.10),cloth)
			for y in [-.18,-.285]:
				b.ellipsoid(Vector3(0,y,.072),Vector3(.075,.018,.013),BODY_KIT.SLOT_BOTTOM,Basis(Vector3.FORWARD,.18),8,4)
		"knee":
			b.ellipsoid(Vector3(0,-.018,.051),Vector3(.070,.087,.034),dark,Basis.IDENTITY,10,6)
			b.ellipsoid(Vector3(0,-.018,.075),Vector3(.047,.064,.015),cloth,Basis.IDENTITY,8,5)
			b.loft([[-.20,.059,.06,dark],[-.23,.058,.059,dark]],dark,Transform3D.IDENTITY,10,false,false)
			for y in [-.29,-.34,-.375]:
				_equipment_box(b,Vector3(0,y,.046),Vector3(.06,.014,.018),dark)

func _equipment_box(b: RefCounted, point: Vector3, size: Vector3, slot: int) -> void:
	# Bevelled loft rather than a sharp placeholder box.
	var half := size * .5
	var bevel := minf(.006, minf(half.z, minf(half.x, half.y)) * .3)
	b.loft([[half.y,half.x-bevel,half.z-bevel,slot,0.0,4.0],[half.y-bevel,half.x,half.z,slot,0.0,4.0],[-half.y+bevel,half.x,half.z,slot,0.0,4.0],[-half.y,half.x-bevel,half.z-bevel,slot,0.0,4.0]],slot,Transform3D(Basis.IDENTITY,point),8)

## Farda por escalão, com o perfil persistente (pele, cabelo, biotipo) do PoliceAppearance.
func _body_look() -> Dictionary:
	var a: Dictionary = get_meta("police_appearance", {})
	var width := float(a.get("width", 1.0))
	var look := {
		"variant": 5000 + appearance_index, "lod": false,
		"female": bool(a.get("woman", false)), "build": 2 if width > 1.2 else (0 if width < 0.95 else 1),
		"height": float(a.get("height", 1.0)), "skin": Color(str(a.get("skin", "c99573"))),
		"hair_color": Color(str(a.get("hair", "30251f"))),
		"hair": {"bun": 5, "short": 0, "ponytail": 4}.get(str(a.get("hairstyle", "")), 1),
		"backpack": false, "bag": 0, "glasses": false,
		"top": 6, "bottom": 0, "shoe": 2, "hat": 4,
		"top_color": _uniform_base_color, "bottom_color": _uniform_base_color.darkened(0.25),
		"accent": Color("141a26"), "inner": Color("d9d6cc"), "shoe_color": Color("141416"),
	}
	match tier:
		UnitTier.DETECTIVE:
			look.merge({"top": 9, "hat": 0, "bottom_color": Color("2e2f33"), "inner": Color("e2ddd0"), "shoe_color": Color("3b2619")}, true)
		UnitTier.SWAT:
			look.merge({"top": 8, "hat": 6, "shoe": 1, "accent": Color("1b1d22"), "bottom_color": Color("16181c"), "shoe_color": Color("121214")}, true)
		UnitTier.FBI:
			look.merge({"top": 8, "hat": 0, "glasses": true, "accent": Color("15161a"), "bottom_color": Color("15161a"), "inner": Color("e8d23a")}, true)
		UnitTier.ARMY:
			look.merge({"top": 8, "hat": 6, "shoe": 1, "accent": Color("39452c"), "bottom_color": Color("3a4630"), "shoe_color": Color("2e261d")}, true)
	return look


func _make_mat(col: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = roughness
	return mat

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.85
	cyl.height = height
	m.mesh = cyl
	m.material_override = mat
	m.position = offset
	return m

func _create_shoe(mat: Material, offset: Vector3) -> MeshInstance3D:
	var shoe := MeshInstance3D.new()
	shoe.name = "ServiceShoe"
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.085
	mesh.radial_segments = 12
	mesh.rings = 6
	shoe.mesh = mesh
	shoe.scale.z = 1.75
	shoe.material_override = mat
	shoe.position = offset
	return shoe
