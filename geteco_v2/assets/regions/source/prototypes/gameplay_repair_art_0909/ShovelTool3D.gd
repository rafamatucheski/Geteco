extends Node3D

## Modelo 3D de pá de trabalho em escala humana e ergonômica (~1.08m).
## Possui cabo de madeira de freixo, empunhadura D superior, colarinho de aço
## e lâmina forjada curva com borda de corte e degrau de apoio.
## Permite 3 poses dinâmicas ancoradas às mãos sem atravessar o chão:
##   1. HOLD (Segurar em repouso)
##   2. CARRY (Carregar ao caminhar, lâmina elevada sem clipping com o solo)
##   3. DIG (Cavar com pegada dupla articulada)

enum ShovelPose {
	HOLD,
	CARRY,
	DIG
}

const TOTAL_LENGTH := 1.08
const SHAFT_LENGTH := 0.68
const BLADE_LENGTH := 0.28
const BLADE_WIDTH := 0.22

var current_pose: ShovelPose = ShovelPose.HOLD

var shaft_mesh: MeshInstance3D
var d_handle: Node3D
var blade_node: Node3D
var blade_mesh: MeshInstance3D
var soil_on_blade: MeshInstance3D

var mat_wood: StandardMaterial3D
var mat_steel: StandardMaterial3D
var mat_dirt: StandardMaterial3D

func _init() -> void:
	_setup_materials()
	_build_shovel()
	set_pose(ShovelPose.HOLD)

func _setup_materials() -> void:
	# Madeira de freixo envernizada com veios sutis
	mat_wood = StandardMaterial3D.new()
	mat_wood.albedo_color = Color("#8c6f48")
	mat_wood.roughness = 0.65

	# Aço forjado escovado com marcas de uso
	mat_steel = StandardMaterial3D.new()
	mat_steel.albedo_color = Color("#55595c")
	mat_steel.roughness = 0.40
	mat_steel.metallic = 0.80

	# Resquícios de terra fresca na lâmina
	mat_dirt = StandardMaterial3D.new()
	mat_dirt.albedo_color = Color("#3e2b1d")
	mat_dirt.roughness = 0.95

func _build_shovel() -> void:
	# O pivô principal (origem 0,0,0) é a empunhadura superior (onde a mão principal segura)

	# 1. Empunhadura em "D" ergonômica no topo
	d_handle = Node3D.new()
	d_handle.name = "DHandle"
	add_child(d_handle)

	# Barra de pega horizontal onde a mão fecha
	var grip_bar := _create_cylinder(0.016, 0.12, mat_wood)
	grip_bar.rotation_degrees = Vector3(0, 0, 90)
	grip_bar.position = Vector3(0.0, 0.0, 0.0)
	d_handle.add_child(grip_bar)

	# Braços laterais do "D" em aço
	for s in [-1.0, 1.0]:
		var arm := _create_box(Vector3(0.018, 0.08, 0.024), mat_steel)
		arm.position = Vector3(s * 0.06, -0.035, 0.0)
		d_handle.add_child(arm)

	# Base do "D" conectando ao cabo
	var base_d := _create_box(Vector3(0.14, 0.02, 0.026), mat_steel)
	base_d.position = Vector3(0.0, -0.075, 0.0)
	d_handle.add_child(base_d)

	# 2. Cabo cilíndrico de madeira (Shaft)
	shaft_mesh = _create_cylinder(0.018, SHAFT_LENGTH, mat_wood)
	shaft_mesh.position = Vector3(0.0, -0.08 - SHAFT_LENGTH * 0.5, 0.0)
	add_child(shaft_mesh)

	# 3. Colarinho metálico (soquete de fixação cabo-lâmina)
	var socket := _create_cylinder(0.022, 0.10, mat_steel)
	socket.position = Vector3(0.0, -0.08 - SHAFT_LENGTH + 0.02, 0.0)
	add_child(socket)

	# 4. Lâmina da pá (Spade blade)
	blade_node = Node3D.new()
	blade_node.name = "BladeNode"
	blade_node.position = Vector3(0.0, -0.08 - SHAFT_LENGTH - 0.02, 0.0)
	add_child(blade_node)

	# Lâmina principal de aço chanfrado
	blade_mesh = _create_box(Vector3(BLADE_WIDTH, BLADE_LENGTH, 0.014), mat_steel)
	blade_mesh.position = Vector3(0.0, -BLADE_LENGTH * 0.5, 0.01)
	blade_mesh.rotation_degrees = Vector3(6.0, 0.0, 0.0) # Leve curvatura côncava
	blade_node.add_child(blade_mesh)

	# Ponta em bisel triangular afiado
	var tip := _create_box(Vector3(BLADE_WIDTH * 0.85, 0.04, 0.008), mat_steel)
	tip.position = Vector3(0.0, -BLADE_LENGTH - 0.015, 0.016)
	blade_node.add_child(tip)

	# Degraus laterais superiores onde a bota pressiona para cavar
	for s in [-1.0, 1.0]:
		var step_rim := _create_box(Vector3(0.045, 0.015, 0.035), mat_steel)
		step_rim.position = Vector3(s * (BLADE_WIDTH * 0.42), 0.0, 0.01)
		blade_node.add_child(step_rim)

	# Respingos de terra fresca incrustada na lâmina
	soil_on_blade = _create_box(Vector3(BLADE_WIDTH * 0.75, BLADE_LENGTH * 0.45, 0.022), mat_dirt)
	soil_on_blade.position = Vector3(0.0, -BLADE_LENGTH * 0.6, 0.014)
	blade_node.add_child(soil_on_blade)

## Aplica uma das 3 poses relativas ao personagem
func set_pose(pose: ShovelPose) -> void:
	current_pose = pose
	match current_pose:
		ShovelPose.HOLD:
			# Segurar em repouso: Pá quase vertical junto à perna, lâmina descansando próximo ao chão
			# Não atravessa o solo porque o pivô da mão está a Y ~0.85m e a pá mede 1.08m inclinada a 24°
			rotation_degrees = Vector3(18.0, 0.0, -8.0)
			position = Vector3(0.0, 0.0, 0.0)

		ShovelPose.CARRY:
			# Carregar em movimento: Pá transportada na diagonal no ombro ou inclinada para trás
			# A lâmina fica elevada em ~0.45m do solo durante a caminhada, NUNCA tocando o piso
			rotation_degrees = Vector3(-65.0, 15.0, -25.0)
			position = Vector3(0.06, 0.08, -0.08)

		ShovelPose.DIG:
			# Cavar: Pá inclinada para a frente fincada em ângulo de penetração no solo
			rotation_degrees = Vector3(42.0, -10.0, 12.0)
			position = Vector3(0.12, -0.15, 0.22)

func _create_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	return mi

func _create_cylinder(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	cyl.rings = 2
	mi.mesh = cyl
	mi.material_override = mat
	return mi
