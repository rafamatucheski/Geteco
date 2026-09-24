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

func equip(id: String) -> void:
	weapon_id = id
	weapon = Node3D.new()
	weapon.name = "PoliceWeapon"
	add_child(weapon)
	var tip := preload("res://gameplay/ArsenalWeapon3D.gd").build(weapon, id)
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
	if not is_instance_valid(weapon): return
	flash_time = maxf(0.0, flash_time - delta)
	muzzle_flash_3d.visible = flash_time > 0.0
	recoil *= exp(-float(POSE_DATA.PROFILES[weapon_id][3]) * delta)
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
