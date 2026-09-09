class_name MournerCharacterModel
extends Node3D

## Modelo 3D de personagem para o funeral (carregadores e visitantes).
## Evita replicação de clones: possui variações de paleta de terno/sobretudo,
## tons de pele, cor e estilo de cabelo, além de poses articuladas:
##   - POSE_CARRY: Braço estendido segurando a alça do caixão no ponto de pega.
##   - POSE_RESPECT: Mãos postas à frente em reverência solene.
##   - POSE_WALK: Ciclo cadenciado de caminhada solene.

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
var left_leg: Node3D
var right_leg: Node3D
var left_forearm: Node3D
var right_forearm: Node3D

# Posições de pose
var is_carrying: bool = false
var carry_side: float = -1.0 # -1 = esquerda (usa braço direito), 1 = direita (usa braço esquerdo)
var is_walking: bool = false
var walk_clock: float = 0.0

# Materiais da variação
var mat_suit: StandardMaterial3D
var mat_skin: StandardMaterial3D
var mat_hair: StandardMaterial3D
var mat_pants: StandardMaterial3D
var mat_shoes: StandardMaterial3D

func _init(p_role: int = 0, p_variant: int = 0) -> void:
	role = p_role as Role
	variant_index = p_variant
	_setup_materials()
	_build_rig()

func _setup_materials() -> void:
	# Paletas elegantes e variadas para luto (evita clones monocromáticos)
	var suit_palettes := [
		Color("#1a1a20"), # Preto carvão clássico
		Color("#272932"), # Grafite escuro elegante
		Color("#1e232d"), # Azul marinho meia-noite
		Color("#2c2b30"), # Ardósia escura com toque quente
		Color("#353535"), # Cinza chumbo escovado
		Color("#2b2528")  # Castanho escuro / ameixa muito escuro
	]

	var skin_palettes := [
		Color("#d6a374"), # Moreno claro / oliva
		Color("#b87850"), # Moreno médio quente
		Color("#6d4430"), # Pele negra rica
		Color("#8a583e"), # Pele negra acobreada
		Color("#eac0a2"), # Pele clara suave
		Color("#c98b64")  # Moreno bronzeado
	]

	var hair_palettes := [
		Color("#111113"), # Preto espresso
		Color("#3b2b20"), # Castanho escuro
		Color("#63554d"), # Castanho acinzentado
		Color("#8c8c88"), # Grisalho maduro
		Color("#261c16"), # Café
		Color("#7d6048")  # Castanho médio
	]

	var s_idx: int = variant_index % suit_palettes.size()
	var k_idx: int = (variant_index * 2 + 1) % skin_palettes.size()
	var h_idx: int = (variant_index * 3) % hair_palettes.size()

	mat_suit = StandardMaterial3D.new()
	mat_suit.albedo_color = suit_palettes[s_idx]
	mat_suit.roughness = 0.70

	mat_skin = StandardMaterial3D.new()
	mat_skin.albedo_color = skin_palettes[k_idx]
	mat_skin.roughness = 0.55

	mat_hair = StandardMaterial3D.new()
	mat_hair.albedo_color = hair_palettes[h_idx]
	mat_hair.roughness = 0.85

	mat_pants = StandardMaterial3D.new()
	mat_pants.albedo_color = suit_palettes[s_idx].darkened(0.12)
	mat_pants.roughness = 0.75

	mat_shoes = StandardMaterial3D.new()
	mat_shoes.albedo_color = Color("#121113")
	mat_shoes.roughness = 0.35
	mat_shoes.metallic = 0.15

func _build_rig() -> void:
	# 1. Torso
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.88, 0.0)
	add_child(torso_node)

	var coat := _create_box(Vector3(0.36, 0.48, 0.22), mat_suit)
	torso_node.add_child(coat)

	# Camisa social visível no colarinho
	var mat_shirt := StandardMaterial3D.new()
	mat_shirt.albedo_color = Color("#ebe8e4")
	var shirt_v := _create_box(Vector3(0.10, 0.16, 0.02), mat_shirt)
	shirt_v.position = Vector3(0.0, 0.16, -0.11)
	torso_node.add_child(shirt_v)

	# Gravata preta / xale
	var tie := _create_box(Vector3(0.035, 0.22, 0.015), mat_shoes)
	tie.position = Vector3(0.0, 0.11, -0.115)
	torso_node.add_child(tie)

	# 2. Cabeça
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.28, 0.0)
	add_child(head_node)

	var head_mesh := _create_ellipsoid(Vector3(0.24, 0.28, 0.24), mat_skin)
	head_node.add_child(head_mesh)

	# Cabelo com corte sóbrio
	var hair_mesh := _create_ellipsoid(Vector3(0.26, 0.18, 0.26), mat_hair)
	hair_mesh.position = Vector3(0.0, 0.08, -0.01)
	head_node.add_child(hair_mesh)

	# 3. Braços
	# Braço esquerdo
	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.23, 1.06, 0.0)
	add_child(left_arm)

	var l_uarm := _create_box(Vector3(0.08, 0.24, 0.09), mat_suit)
	l_uarm.position = Vector3(0.0, -0.12, 0.0)
	left_arm.add_child(l_uarm)

	left_forearm = Node3D.new()
	left_forearm.position = Vector3(0.0, -0.24, 0.0)
	left_arm.add_child(left_forearm)

	var l_farm := _create_box(Vector3(0.07, 0.22, 0.08), mat_suit)
	l_farm.position = Vector3(0.0, -0.11, 0.0)
	left_forearm.add_child(l_farm)

	var l_hand := _create_box(Vector3(0.06, 0.08, 0.06), mat_skin)
	l_hand.position = Vector3(0.0, -0.24, 0.0)
	left_forearm.add_child(l_hand)

	# Braço direito
	right_arm = Node3D.new()
	right_arm.position = Vector3(0.23, 1.06, 0.0)
	add_child(right_arm)

	var r_uarm := _create_box(Vector3(0.08, 0.24, 0.09), mat_suit)
	r_uarm.position = Vector3(0.0, -0.12, 0.0)
	right_arm.add_child(r_uarm)

	right_forearm = Node3D.new()
	right_forearm.position = Vector3(0.0, -0.24, 0.0)
	right_arm.add_child(right_forearm)

	var r_farm := _create_box(Vector3(0.07, 0.22, 0.08), mat_suit)
	r_farm.position = Vector3(0.0, -0.11, 0.0)
	right_forearm.add_child(r_farm)

	var r_hand := _create_box(Vector3(0.06, 0.08, 0.06), mat_skin)
	r_hand.position = Vector3(0.0, -0.24, 0.0)
	right_forearm.add_child(r_hand)

	# 4. Pernas
	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.10, 0.65, 0.0)
	add_child(left_leg)

	var l_leg_mesh := _create_box(Vector3(0.11, 0.58, 0.12), mat_pants)
	l_leg_mesh.position = Vector3(0.0, -0.29, 0.0)
	left_leg.add_child(l_leg_mesh)

	var l_shoe := _create_box(Vector3(0.11, 0.08, 0.18), mat_shoes)
	l_shoe.position = Vector3(0.0, -0.60, -0.03)
	left_leg.add_child(l_shoe)

	right_leg = Node3D.new()
	right_leg.position = Vector3(0.10, 0.65, 0.0)
	add_child(right_leg)

	var r_leg_mesh := _create_box(Vector3(0.11, 0.58, 0.12), mat_pants)
	r_leg_mesh.position = Vector3(0.0, -0.29, 0.0)
	right_leg.add_child(r_leg_mesh)

	var r_shoe := _create_box(Vector3(0.11, 0.08, 0.18), mat_shoes)
	r_shoe.position = Vector3(0.0, -0.60, -0.03)
	right_leg.add_child(r_shoe)

## Define se o personagem está carregando o caixão e de qual lado
func set_carrying(carrying: bool, side: float = -1.0) -> void:
	is_carrying = carrying
	carry_side = side
	if not is_carrying:
		set_respect_pose()
		return

	# Lado do carregador em relação ao caixão:
	# side < 0: carregador à esquerda do caixão (usa o braço direito estendido para o caixão)
	# side > 0: carregador à direita do caixão (usa o braço esquerdo estendido para o caixão)
	if carry_side < 0:
		# Braço direito segura a alça
		right_arm.rotation_degrees = Vector3(-18.0, 12.0, -22.0)
		right_forearm.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
		# Braço esquerdo reto junto ao corpo
		left_arm.rotation_degrees = Vector3(0.0, 0.0, 6.0)
		left_forearm.rotation_degrees = Vector3.ZERO
	else:
		# Braço esquerdo segura a alça
		left_arm.rotation_degrees = Vector3(-18.0, -12.0, 22.0)
		left_forearm.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
		# Braço direito reto junto ao corpo
		right_arm.rotation_degrees = Vector3(0.0, 0.0, -6.0)
		right_forearm.rotation_degrees = Vector3.ZERO

## Postura solene de respeito com mãos postas
func set_respect_pose() -> void:
	is_carrying = false
	left_arm.rotation_degrees = Vector3(25.0, -15.0, 28.0)
	left_forearm.rotation_degrees = Vector3(-55.0, 20.0, 0.0)

	right_arm.rotation_degrees = Vector3(25.0, 15.0, -28.0)
	right_forearm.rotation_degrees = Vector3(-55.0, -20.0, 0.0)

	head_node.rotation_degrees = Vector3(10.0, 0.0, 0.0) # Cabeça inclinada respeitosamente

func update_animation(delta: float, moving: bool) -> void:
	is_walking = moving
	if is_walking:
		walk_clock += delta * 4.2
		var leg_swing := sin(walk_clock) * 22.0
		left_leg.rotation_degrees.x = leg_swing
		right_leg.rotation_degrees.x = -leg_swing

		# Se não estiver carregando, os braços balançam levemente
		if not is_carrying:
			var arm_swing := sin(walk_clock) * 12.0
			left_arm.rotation_degrees.x = -arm_swing
			right_arm.rotation_degrees.x = arm_swing
	else:
		left_leg.rotation_degrees.x = lerpf(left_leg.rotation_degrees.x, 0.0, 8.0 * delta)
		right_leg.rotation_degrees.x = lerpf(right_leg.rotation_degrees.x, 0.0, 8.0 * delta)

func _create_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	return mi

func _create_ellipsoid(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 10
	sph.rings = 5
	mi.mesh = sph
	mi.material_override = mat
	mi.scale = size
	return mi
