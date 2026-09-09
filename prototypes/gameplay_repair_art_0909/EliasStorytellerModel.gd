class_name EliasStorytellerModel
extends Node3D

## Modelo 3D exclusivo de Elias, o contador de histórias do cemitério do porto.
## Silhueta inconfundível: sobretudo de tweed com gola alta, cachecol de lã cor de ferrugem,
## boina clássica de marinheiro, barba grisalha distinta, óculos de leitura de armação fina
## e bolsa tiracolo de couro para guardar as cartas antigas.
## Poses:
##   - POSE_WAIT: Espera solene e contemplativa.
##   - POSE_TALK: Gesto expressivo de narração de memórias.
##   - POSE_WALK: Passo tranquilo e cadenciado.
##   - POSE_INSPECT: Inclinação respeitosa examinando uma lápide.

enum Pose {
	WAIT,
	TALK,
	WALK,
	INSPECT
}

var current_pose: Pose = Pose.WAIT
var walking: bool = false
var clock: float = 0.0
var talk_gesture_clock: float = 0.0

# Nós anatômicos
var torso_node: Node3D
var head_node: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_forearm: Node3D
var right_forearm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var satchel_node: Node3D
var spectacles_node: Node3D

# Materiais exclusivos
var mat_overcoat: StandardMaterial3D
var mat_scarf: StandardMaterial3D
var mat_cap: StandardMaterial3D
var mat_skin: StandardMaterial3D
var mat_silver_beard: StandardMaterial3D
var mat_leather_satchel: StandardMaterial3D
var mat_trousers: StandardMaterial3D
var mat_boots: StandardMaterial3D
var mat_brass_chain: StandardMaterial3D

func _init() -> void:
	_setup_materials()
	_build_rig()
	set_pose(Pose.WAIT)

func _setup_materials() -> void:
	# Sobretudo de tweed encorpado cor de turfa/castanho envelhecido
	mat_overcoat = StandardMaterial3D.new()
	mat_overcoat.albedo_color = Color("#4b4034")
	mat_overcoat.roughness = 0.78

	# Cachecol de lã tricotada cor de ferrugem / mostarda outonal
	mat_scarf = StandardMaterial3D.new()
	mat_scarf.albedo_color = Color("#ad6834")
	mat_scarf.roughness = 0.88

	# Boina maruja clássica de lã escura
	mat_cap = StandardMaterial3D.new()
	mat_cap.albedo_color = Color("#292624")
	mat_cap.roughness = 0.70

	# Pele madura morena clara
	mat_skin = StandardMaterial3D.new()
	mat_skin.albedo_color = Color("#c7926e")
	mat_skin.roughness = 0.60

	# Barba e cabelo grisalhos / prateados distintos
	mat_silver_beard = StandardMaterial3D.new()
	mat_silver_beard.albedo_color = Color("#dedbd7")
	mat_silver_beard.roughness = 0.90

	# Bolsa tiracolo de couro legítimo gasto
	mat_leather_satchel = StandardMaterial3D.new()
	mat_leather_satchel.albedo_color = Color("#66432b")
	mat_leather_satchel.roughness = 0.55

	# Calça de alfaiataria em lã cinza escura
	mat_trousers = StandardMaterial3D.new()
	mat_trousers.albedo_color = Color("#32353a")
	mat_trousers.roughness = 0.75

	# Botas pesadas de caminhada
	mat_boots = StandardMaterial3D.new()
	mat_boots.albedo_color = Color("#1e1c1b")
	mat_boots.roughness = 0.50

	# Corrente de latão dourado do relógio de bolso
	mat_brass_chain = StandardMaterial3D.new()
	mat_brass_chain.albedo_color = Color("#d4ac0d")
	mat_brass_chain.roughness = 0.25
	mat_brass_chain.metallic = 0.85

func _build_rig() -> void:
	# 1. Torso com sobretudo longo e gola saliente
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.86, 0.0)
	add_child(torso_node)

	# Tronco superior do sobretudo
	var coat_chest := _create_box(Vector3(0.40, 0.52, 0.26), mat_overcoat)
	torso_node.add_child(coat_chest)

	# Fralda longa do sobretudo descendo até os joelhos (silhueta inconfundível)
	var coat_skirt := _create_box(Vector3(0.43, 0.44, 0.29), mat_overcoat)
	coat_skirt.position = Vector3(0.0, -0.38, 0.01)
	torso_node.add_child(coat_skirt)

	# Gola volumosa dobrada do sobretudo
	for s in [-1.0, 1.0]:
		var lapel := _create_box(Vector3(0.09, 0.24, 0.04), mat_overcoat)
		lapel.position = Vector3(s * 0.14, 0.18, -0.13)
		lapel.rotation_degrees = Vector3(12.0, s * -14.0, s * 16.0)
		torso_node.add_child(lapel)

	# Cachecol enrolado no pescoço
	var scarf_ring := _create_ellipsoid(Vector3(0.32, 0.15, 0.30), mat_scarf)
	scarf_ring.position = Vector3(0.0, 0.26, -0.01)
	torso_node.add_child(scarf_ring)

	# Ponta pendurada do cachecol
	var scarf_tail := _create_box(Vector3(0.08, 0.28, 0.03), mat_scarf)
	scarf_tail.position = Vector3(0.08, 0.07, -0.14)
	scarf_tail.rotation_degrees = Vector3(8.0, 4.0, -6.0)
	torso_node.add_child(scarf_tail)

	# Corrente de relógio de bolso curva sobre o peito
	var chain := _create_box(Vector3(0.12, 0.012, 0.012), mat_brass_chain)
	chain.position = Vector3(-0.06, 0.02, -0.135)
	chain.rotation_degrees = Vector3(0, 0, 15)
	torso_node.add_child(chain)

	# 2. Bolsa tiracolo de couro transversal
	satchel_node = Node3D.new()
	satchel_node.name = "LeatherSatchel"
	torso_node.add_child(satchel_node)

	# Alça de couro que cruza do ombro direito para o quadril esquerdo
	var strap := _create_box(Vector3(0.04, 0.62, 0.02), mat_leather_satchel)
	strap.position = Vector3(-0.02, 0.08, 0.02)
	strap.rotation_degrees = Vector3(0, 0, -42.0)
	satchel_node.add_child(strap)

	# Corpo da bolsa (com aba de fivela)
	var bag := _create_box(Vector3(0.11, 0.19, 0.22), mat_leather_satchel)
	bag.position = Vector3(-0.24, -0.18, 0.02)
	satchel_node.add_child(bag)

	var buckle := _create_box(Vector3(0.02, 0.035, 0.035), mat_brass_chain)
	buckle.position = Vector3(-0.29, -0.16, 0.02)
	satchel_node.add_child(buckle)

	# 3. Cabeça de Elias: barba respeitável, óculos e boina
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.28, 0.0)
	add_child(head_node)

	var head_mesh := _create_ellipsoid(Vector3(0.24, 0.28, 0.24), mat_skin)
	head_node.add_child(head_mesh)

	# Barba grisalha cheia e respeitosa
	var beard_main := _create_ellipsoid(Vector3(0.22, 0.22, 0.18), mat_silver_beard)
	beard_main.position = Vector3(0.0, -0.09, -0.07)
	head_node.add_child(beard_main)

	var mustache := _create_box(Vector3(0.15, 0.045, 0.04), mat_silver_beard)
	mustache.position = Vector3(0.0, -0.035, -0.13)
	head_node.add_child(mustache)

	# Nariz expressivo
	var nose := _create_box(Vector3(0.035, 0.065, 0.05), mat_skin)
	nose.position = Vector3(0.0, 0.015, -0.13)
	head_node.add_child(nose)

	# Óculos de leitura de armação fina sobre o nariz
	spectacles_node = Node3D.new()
	spectacles_node.name = "Spectacles"
	spectacles_node.position = Vector3(0.0, 0.035, -0.125)
	head_node.add_child(spectacles_node)

	for s in [-1.0, 1.0]:
		var frame := _create_box(Vector3(0.05, 0.04, 0.01), mat_brass_chain)
		frame.position = Vector3(s * 0.055, 0.0, 0.0)
		spectacles_node.add_child(frame)
	var bridge := _create_box(Vector3(0.03, 0.01, 0.01), mat_brass_chain)
	spectacles_node.add_child(bridge)

	# Boina clássica de marinheiro
	var cap_base := _create_ellipsoid(Vector3(0.28, 0.10, 0.30), mat_cap)
	cap_base.position = Vector3(0.0, 0.14, -0.01)
	head_node.add_child(cap_base)

	var cap_visor := _create_box(Vector3(0.18, 0.02, 0.08), mat_cap)
	cap_visor.position = Vector3(0.0, 0.11, -0.14)
	cap_visor.rotation_degrees = Vector3(14.0, 0.0, 0.0)
	head_node.add_child(cap_visor)

	# 4. Braços
	# Braço esquerdo
	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.24, 1.04, 0.0)
	add_child(left_arm)

	var l_uarm := _create_box(Vector3(0.09, 0.24, 0.10), mat_overcoat)
	l_uarm.position = Vector3(0.0, -0.12, 0.0)
	left_arm.add_child(l_uarm)

	left_forearm = Node3D.new()
	left_forearm.position = Vector3(0.0, -0.24, 0.0)
	left_arm.add_child(left_forearm)

	var l_farm := _create_box(Vector3(0.08, 0.22, 0.09), mat_overcoat)
	l_farm.position = Vector3(0.0, -0.11, 0.0)
	left_forearm.add_child(l_farm)

	var l_hand := _create_box(Vector3(0.06, 0.08, 0.06), mat_skin)
	l_hand.position = Vector3(0.0, -0.23, 0.0)
	left_forearm.add_child(l_hand)

	# Braço direito (braço de gestos do contador de histórias)
	right_arm = Node3D.new()
	right_arm.position = Vector3(0.24, 1.04, 0.0)
	add_child(right_arm)

	var r_uarm := _create_box(Vector3(0.09, 0.24, 0.10), mat_overcoat)
	r_uarm.position = Vector3(0.0, -0.12, 0.0)
	right_arm.add_child(r_uarm)

	right_forearm = Node3D.new()
	right_forearm.position = Vector3(0.0, -0.24, 0.0)
	right_arm.add_child(right_forearm)

	var r_farm := _create_box(Vector3(0.08, 0.22, 0.09), mat_overcoat)
	r_farm.position = Vector3(0.0, -0.11, 0.0)
	right_forearm.add_child(r_farm)

	var r_hand := _create_box(Vector3(0.06, 0.08, 0.06), mat_skin)
	r_hand.position = Vector3(0.0, -0.23, 0.0)
	right_forearm.add_child(r_hand)

	# 5. Pernas e calças
	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.11, 0.60, 0.0)
	add_child(left_leg)

	var l_pant := _create_box(Vector3(0.12, 0.52, 0.13), mat_trousers)
	l_pant.position = Vector3(0.0, -0.26, 0.0)
	left_leg.add_child(l_pant)

	var l_boot := _create_box(Vector3(0.12, 0.09, 0.20), mat_boots)
	l_boot.position = Vector3(0.0, -0.56, -0.03)
	left_leg.add_child(l_boot)

	right_leg = Node3D.new()
	right_leg.position = Vector3(0.11, 0.60, 0.0)
	add_child(right_leg)

	var r_pant := _create_box(Vector3(0.12, 0.52, 0.13), mat_trousers)
	r_pant.position = Vector3(0.0, -0.26, 0.0)
	right_leg.add_child(r_pant)

	var r_boot := _create_box(Vector3(0.12, 0.09, 0.20), mat_boots)
	r_boot.position = Vector3(0.0, -0.56, -0.03)
	right_leg.add_child(r_boot)

## Aplica uma das posturas expressivas
func set_pose(pose: Pose) -> void:
	current_pose = pose
	match current_pose:
		Pose.WAIT:
			# Mãos postas relaxadas à frente, cabeça serena
			left_arm.rotation_degrees = Vector3(18.0, -10.0, 16.0)
			left_forearm.rotation_degrees = Vector3(-45.0, 20.0, 0.0)
			right_arm.rotation_degrees = Vector3(18.0, 10.0, -16.0)
			right_forearm.rotation_degrees = Vector3(-45.0, -20.0, 0.0)
			head_node.rotation_degrees = Vector3(4.0, 0.0, 0.0)

		Pose.TALK:
			# Braço direito erguido em gesto de contação de histórias, cabeça expressiva
			left_arm.rotation_degrees = Vector3(14.0, -6.0, 10.0)
			left_forearm.rotation_degrees = Vector3(-35.0, 10.0, 0.0)
			right_arm.rotation_degrees = Vector3(-42.0, 28.0, -18.0)
			right_forearm.rotation_degrees = Vector3(-65.0, 25.0, 0.0)
			head_node.rotation_degrees = Vector3(-4.0, 12.0, 0.0)

		Pose.INSPECT:
			# Tronco e cabeça inclinados respeitosamente lendo a inscrição
			torso_node.rotation_degrees = Vector3(14.0, 0.0, 0.0)
			head_node.rotation_degrees = Vector3(25.0, 0.0, 0.0)
			left_arm.rotation_degrees = Vector3(24.0, 0.0, 12.0)
			right_arm.rotation_degrees = Vector3(24.0, 0.0, -12.0)

		Pose.WALK:
			# Postura neutra para marcha
			torso_node.rotation_degrees = Vector3.ZERO
			head_node.rotation_degrees = Vector3.ZERO
			left_arm.rotation_degrees = Vector3.ZERO
			right_arm.rotation_degrees = Vector3.ZERO

func _process(delta: float) -> void:
	clock += delta
	if walking or current_pose == Pose.WALK:
		var leg_swing := sin(clock * 3.8) * 18.0
		left_leg.rotation_degrees.x = leg_swing
		right_leg.rotation_degrees.x = -leg_swing

		var arm_swing := sin(clock * 3.8) * 14.0
		left_arm.rotation_degrees.x = -arm_swing
		if current_pose != Pose.TALK:
			right_arm.rotation_degrees.x = arm_swing
	elif current_pose == Pose.TALK:
		# Gesto sutil de respiração e modulação da mão enquanto fala
		talk_gesture_clock += delta * 2.5
		right_forearm.rotation_degrees.x = -65.0 + sin(talk_gesture_clock) * 12.0
		head_node.rotation_degrees.y = 12.0 + sin(talk_gesture_clock * 0.7) * 8.0

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
	sph.radial_segments = 12
	sph.rings = 6
	mi.mesh = sph
	mi.material_override = mat
	mi.scale = size
	return mi
