class_name StreamableMournerModel
extends StreamableActorPresentation

## Modelo 3D de luto com suporte nativo a Streaming sob demanda e cache de geometrias.
##
## Beneficios de Performance:
## 1. Zero alocacao de meshes novas: compartilha BoxMesh e SphereMesh unitarios via escala.
## 2. Zero duplicacao de materiais imutaveis: compartilha as paletas de ternos, pele e cabelo.
## 3. Isolamento estrito de danos/repintura: alteracoes individuais usam create_damage_material
##    ou create_isolated_material sem vazar para outros convidados ou carregadores.
## 4. Reset completo (recycle_presentation): zera rotacoes de membros e limpa danos.

enum Role {
	PALLBEARER,
	GUEST,
	PRIEST_SPEAKER
}

@export var role: Role = Role.PALLBEARER
@export var variant_index: int = 0

var torso_node: Node3D
var head_node: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_forearm: Node3D
var right_forearm: Node3D
var left_leg: Node3D
var right_leg: Node3D

# Referencias para malhas que podem receber dano ou isolamento
var coat_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var l_uarm_mesh: MeshInstance3D
var r_uarm_mesh: MeshInstance3D

# Estados de pose e animacao
var is_carrying: bool = false
var carry_side: float = -1.0 # -1 = esquerda (usa braco direito), 1 = direita (usa braco esquerdo)
var is_walking: bool = false
var walk_clock: float = 0.0

func _init(p_role: int = 0, p_variant: int = 0, p_defer: bool = false) -> void:
	role = p_role as Role
	variant_index = p_variant
	defer_presentation = p_defer

func _setup_fallback_silhouette() -> void:
	if _presentation_fallback != null or is_presentation_ready:
		return
	_presentation_fallback = Node3D.new()
	_presentation_fallback.name = "MournerSilhouette"
	add_child(_presentation_fallback)

	var mi := MeshInstance3D.new()
	mi.mesh = ArtPresentationCache.get_unit_box()
	mi.scale = Vector3(0.36, 1.72, 0.24)
	mi.position = Vector3(0.0, 0.86, 0.0)

	var mat := StandardMaterial3D.new()
	var suit_col: Color = ArtPresentationCache.SUIT_PALETTES[variant_index % ArtPresentationCache.SUIT_PALETTES.size()]
	mat.albedo_color = Color(suit_col.r, suit_col.g, suit_col.b, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat

	_presentation_fallback.add_child(mi)

func _build_presentation_rig() -> void:
	var mat_suit := ArtPresentationCache.get_suit_material(variant_index)
	var mat_pants := ArtPresentationCache.get_pants_material(variant_index)
	var mat_skin := ArtPresentationCache.get_skin_material(variant_index)
	var mat_hair := ArtPresentationCache.get_hair_material(variant_index)
	var mat_shoes := ArtPresentationCache.get_shoes_material()
	var mat_collar := ArtPresentationCache.get_shirt_collar_material()

	# 1. Torso
	torso_node = Node3D.new()
	torso_node.name = "Torso"
	torso_node.position = Vector3(0.0, 0.88, 0.0)
	add_child(torso_node)

	coat_mesh = _create_box_part(Vector3(0.36, 0.48, 0.22), mat_suit)
	torso_node.add_child(coat_mesh)

	var shirt_v := _create_box_part(Vector3(0.10, 0.16, 0.02), mat_collar)
	shirt_v.position = Vector3(0.0, 0.16, -0.11)
	torso_node.add_child(shirt_v)

	var tie := _create_box_part(Vector3(0.035, 0.22, 0.015), mat_shoes)
	tie.position = Vector3(0.0, 0.11, -0.115)
	torso_node.add_child(tie)

	# 2. Cabeca
	head_node = Node3D.new()
	head_node.name = "Head"
	head_node.position = Vector3(0.0, 1.28, 0.0)
	add_child(head_node)

	head_mesh = _create_sphere_part(Vector3(0.24, 0.28, 0.24), mat_skin)
	head_node.add_child(head_mesh)

	var hair_mesh := _create_sphere_part(Vector3(0.26, 0.18, 0.26), mat_hair)
	hair_mesh.position = Vector3(0.0, 0.08, -0.01)
	head_node.add_child(hair_mesh)

	# 3. Bracos
	left_arm = Node3D.new()
	left_arm.name = "LeftArm"
	left_arm.position = Vector3(-0.23, 1.06, 0.0)
	add_child(left_arm)

	l_uarm_mesh = _create_box_part(Vector3(0.08, 0.24, 0.09), mat_suit)
	l_uarm_mesh.position = Vector3(0.0, -0.12, 0.0)
	left_arm.add_child(l_uarm_mesh)

	left_forearm = Node3D.new()
	left_forearm.name = "LeftForearm"
	left_forearm.position = Vector3(0.0, -0.24, 0.0)
	left_arm.add_child(left_forearm)

	var l_farm := _create_box_part(Vector3(0.07, 0.22, 0.08), mat_suit)
	l_farm.position = Vector3(0.0, -0.11, 0.0)
	left_forearm.add_child(l_farm)

	var l_hand := _create_box_part(Vector3(0.06, 0.08, 0.06), mat_skin)
	l_hand.position = Vector3(0.0, -0.24, 0.0)
	left_forearm.add_child(l_hand)

	right_arm = Node3D.new()
	right_arm.name = "RightArm"
	right_arm.position = Vector3(0.23, 1.06, 0.0)
	add_child(right_arm)

	r_uarm_mesh = _create_box_part(Vector3(0.08, 0.24, 0.09), mat_suit)
	r_uarm_mesh.position = Vector3(0.0, -0.12, 0.0)
	right_arm.add_child(r_uarm_mesh)

	right_forearm = Node3D.new()
	right_forearm.name = "RightForearm"
	right_forearm.position = Vector3(0.0, -0.24, 0.0)
	right_arm.add_child(right_forearm)

	var r_farm := _create_box_part(Vector3(0.07, 0.22, 0.08), mat_suit)
	r_farm.position = Vector3(0.0, -0.11, 0.0)
	right_forearm.add_child(r_farm)

	var r_hand := _create_box_part(Vector3(0.06, 0.08, 0.06), mat_skin)
	r_hand.position = Vector3(0.0, -0.24, 0.0)
	right_forearm.add_child(r_hand)

	# 4. Pernas
	left_leg = Node3D.new()
	left_leg.name = "LeftLeg"
	left_leg.position = Vector3(-0.11, 0.64, 0.0)
	add_child(left_leg)

	var l_leg_mesh := _create_box_part(Vector3(0.12, 0.60, 0.12), mat_pants)
	l_leg_mesh.position = Vector3(0.0, -0.30, 0.0)
	left_leg.add_child(l_leg_mesh)

	var l_shoe := _create_box_part(Vector3(0.125, 0.08, 0.20), mat_shoes)
	l_shoe.position = Vector3(0.0, -0.60, -0.03)
	left_leg.add_child(l_shoe)

	right_leg = Node3D.new()
	right_leg.name = "RightLeg"
	right_leg.position = Vector3(0.11, 0.64, 0.0)
	add_child(right_leg)

	var r_leg_mesh := _create_box_part(Vector3(0.12, 0.60, 0.12), mat_pants)
	r_leg_mesh.position = Vector3(0.0, -0.30, 0.0)
	right_leg.add_child(r_leg_mesh)

	var r_shoe := _create_box_part(Vector3(0.125, 0.08, 0.20), mat_shoes)
	r_shoe.position = Vector3(0.0, -0.60, -0.03)
	right_leg.add_child(r_shoe)

func _create_box_part(box_scale: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ArtPresentationCache.get_unit_box() # Compartilhado!
	mi.scale = box_scale
	mi.material_override = mat # Compartilhado!
	return mi

func _create_sphere_part(sphere_scale: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ArtPresentationCache.get_unit_sphere() # Compartilhado!
	mi.scale = sphere_scale
	mi.material_override = mat # Compartilhado!
	return mi

# --- POSES E ANIMACAO ---

func set_carry_pose(side: float) -> void:
	carry_side = side
	is_carrying = true
	if not is_presentation_ready:
		_buffered_pose = 1 if side > 0.0 else 0
		return

	if side < 0.0:
		# Carregador a esquerda do caixao: usa o braco direito
		right_arm.rotation_degrees = Vector3(-35.0, 15.0, -18.0)
		right_forearm.rotation_degrees = Vector3(-20.0, 10.0, 0.0)
		left_arm.rotation_degrees = Vector3(10.0, 0.0, 10.0)
		left_forearm.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
	else:
		# Carregador a direita do caixao: usa o braco esquerdo
		left_arm.rotation_degrees = Vector3(-35.0, -15.0, 18.0)
		left_forearm.rotation_degrees = Vector3(-20.0, -10.0, 0.0)
		right_arm.rotation_degrees = Vector3(10.0, 0.0, -10.0)
		right_forearm.rotation_degrees = Vector3(-15.0, 0.0, 0.0)

func set_respect_pose() -> void:
	is_carrying = false
	if not is_presentation_ready:
		_buffered_pose = 2
		return

	left_arm.rotation_degrees = Vector3(25.0, -15.0, 28.0)
	left_forearm.rotation_degrees = Vector3(-55.0, 20.0, 0.0)
	right_arm.rotation_degrees = Vector3(25.0, 15.0, -28.0)
	right_forearm.rotation_degrees = Vector3(-55.0, -20.0, 0.0)
	head_node.rotation_degrees = Vector3(10.0, 0.0, 0.0)

func _apply_pose_to_rig(pose_idx: int) -> void:
	match pose_idx:
		0: set_carry_pose(-1.0)
		1: set_carry_pose(1.0)
		2: set_respect_pose()
		_:
			pass

func update_animation(delta: float, moving: bool) -> void:
	is_walking = moving
	if not is_presentation_ready:
		_buffered_walking = moving
		return

	if is_walking:
		walk_clock += delta * 4.2
		var leg_swing := sin(walk_clock) * 22.0
		left_leg.rotation_degrees.x = leg_swing
		right_leg.rotation_degrees.x = -leg_swing

		if not is_carrying:
			var arm_swing := sin(walk_clock) * 12.0
			left_arm.rotation_degrees.x = -arm_swing
			right_arm.rotation_degrees.x = arm_swing
	else:
		left_leg.rotation_degrees.x = lerpf(left_leg.rotation_degrees.x, 0.0, 8.0 * delta)
		right_leg.rotation_degrees.x = lerpf(right_leg.rotation_degrees.x, 0.0, 8.0 * delta)

# --- ISOLAMENTO DE DANO E RESTAURACAO ---

func _apply_damage_to_rig(damage_type: String, intensity: float, affected_part: String) -> void:
	var base_suit := ArtPresentationCache.get_suit_material(variant_index)
	var dmg_mat := ArtPresentationCache.create_damage_material(base_suit, damage_type, intensity)

	if affected_part == "head" and head_mesh != null:
		var base_skin := ArtPresentationCache.get_skin_material(variant_index)
		head_mesh.material_override = ArtPresentationCache.create_damage_material(base_skin, damage_type, intensity)
	else:
		if coat_mesh != null:
			coat_mesh.material_override = dmg_mat
		if l_uarm_mesh != null:
			l_uarm_mesh.material_override = dmg_mat

func _restore_shared_materials() -> void:
	var mat_suit := ArtPresentationCache.get_suit_material(variant_index)
	var mat_skin := ArtPresentationCache.get_skin_material(variant_index)

	if coat_mesh != null:
		coat_mesh.material_override = mat_suit
	if l_uarm_mesh != null:
		l_uarm_mesh.material_override = mat_suit
	if r_uarm_mesh != null:
		r_uarm_mesh.material_override = mat_suit
	if head_mesh != null:
		head_mesh.material_override = mat_skin

func _on_recycled_custom() -> void:
	is_carrying = false
	is_walking = false
	walk_clock = 0.0