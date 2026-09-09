class_name Casket3D
extends Node3D

## Modelo 3D de caixão funerário em escala humana coerente com o GETECO (~2.05m x 0.68m x 0.44m).
## Possui tampa com chanfros, detalhes em latão, alças laterais e 6 pontos de pega para carregadores.

# Dimensões gerais (em metros no espaço 3D do modelo)
const LENGTH := 2.05
const WIDTH_HEAD := 0.66
const WIDTH_SHOULDER := 0.74
const WIDTH_FOOT := 0.54
const HEIGHT_BASE := 0.32
const HEIGHT_LID := 0.14

# Cores e materiais
var mat_wood: StandardMaterial3D
var mat_brass: StandardMaterial3D
var mat_interior: StandardMaterial3D

# Nós e pontos de pega
var grip_markers: Array[Marker3D] = []
var casket_body: Node3D
var casket_lid: Node3D

func _init() -> void:
	_setup_materials()
	_build_casket()
	_setup_grip_points()

func _setup_materials() -> void:
	# Mogno escuro acetinado com leve reflexo
	mat_wood = StandardMaterial3D.new()
	mat_wood.albedo_color = Color("#3d2215")
	mat_wood.roughness = 0.48
	mat_wood.metallic = 0.05

	# Latão / bronze polido para as alças e frisos
	mat_brass = StandardMaterial3D.new()
	mat_brass.albedo_color = Color("#d4ac0d")
	mat_brass.roughness = 0.30
	mat_brass.metallic = 0.85

	# Forro interior de cetim suave
	mat_interior = StandardMaterial3D.new()
	mat_interior.albedo_color = Color("#e8e3d5")
	mat_interior.roughness = 0.85

func _build_casket() -> void:
	casket_body = Node3D.new()
	casket_body.name = "CasketBody"
	add_child(casket_body)

	# 1. Base principal do caixão (formato sextavado suave através de caixas unidas)
	# Centro/ombros (mais largo)
	var mid_box := _create_box(Vector3(WIDTH_SHOULDER, HEIGHT_BASE, LENGTH * 0.45), mat_wood)
	mid_box.position = Vector3(0.0, HEIGHT_BASE * 0.5, 0.05)
	casket_body.add_child(mid_box)

	# Seção da cabeça
	var head_box := _create_box(Vector3(WIDTH_HEAD, HEIGHT_BASE, LENGTH * 0.28), mat_wood)
	head_box.position = Vector3(0.0, HEIGHT_BASE * 0.5, -LENGTH * 0.34)
	casket_body.add_child(head_box)

	# Seção dos pés (mais estreita)
	var foot_box := _create_box(Vector3(WIDTH_FOOT, HEIGHT_BASE, LENGTH * 0.32), mat_wood)
	foot_box.position = Vector3(0.0, HEIGHT_BASE * 0.5, LENGTH * 0.38)
	casket_body.add_child(foot_box)

	# Rodapé saliente chanfrado (moldura inferior)
	var trim_bot := _create_box(Vector3(WIDTH_SHOULDER + 0.04, 0.04, LENGTH + 0.04), mat_wood)
	trim_bot.position = Vector3(0.0, 0.02, 0.02)
	casket_body.add_child(trim_bot)

	# Friso decorativo intermediário em latão
	var brass_band := _create_box(Vector3(WIDTH_SHOULDER + 0.02, 0.015, LENGTH + 0.02), mat_brass)
	brass_band.position = Vector3(0.0, HEIGHT_BASE * 0.55, 0.02)
	casket_body.add_child(brass_band)

	# 2. Tampa (Lid) com chanfro piramidal escalonado
	casket_lid = Node3D.new()
	casket_lid.name = "CasketLid"
	casket_lid.position = Vector3(0.0, HEIGHT_BASE, 0.0)
	casket_body.add_child(casket_lid)

	var lid_tier1 := _create_box(Vector3(WIDTH_SHOULDER + 0.03, 0.04, LENGTH + 0.03), mat_wood)
	lid_tier1.position = Vector3(0.0, 0.02, 0.02)
	casket_lid.add_child(lid_tier1)

	var lid_tier2 := _create_box(Vector3(WIDTH_SHOULDER - 0.08, HEIGHT_LID * 0.6, LENGTH - 0.10), mat_wood)
	lid_tier2.position = Vector3(0.0, 0.02 + HEIGHT_LID * 0.3, 0.02)
	casket_lid.add_child(lid_tier2)

	var lid_crown := _create_box(Vector3(WIDTH_FOOT - 0.12, 0.025, LENGTH * 0.65), mat_brass)
	lid_crown.position = Vector3(0.0, 0.02 + HEIGHT_LID * 0.6 + 0.012, 0.0)
	casket_lid.add_child(lid_crown)

	# Cruz sutil em latão na cabeceira da tampa
	var cross_v := _create_box(Vector3(0.035, 0.008, 0.28), mat_brass)
	cross_v.position = Vector3(0.0, 0.02 + HEIGHT_LID * 0.6 + 0.026, -0.32)
	casket_lid.add_child(cross_v)

	var cross_h := _create_box(Vector3(0.18, 0.008, 0.035), mat_brass)
	cross_h.position = Vector3(0.0, 0.02 + HEIGHT_LID * 0.6 + 0.026, -0.36)
	casket_lid.add_child(cross_h)

	# 3. Alças laterais reforçadas (3 de cada lado) e 1 em cada topo
	# Posições longitudinais z: ombro (-0.45), centro (0.05), pé (0.55)
	var z_positions: Array[float] = [-0.50, 0.05, 0.55]
	for side_val in [-1.0, 1.0]:
		var side: float = float(side_val)
		var x_pos: float = side * (WIDTH_SHOULDER * 0.5 + 0.03)
		for z in z_positions:
			_build_drop_handle(casket_body, Vector3(x_pos, HEIGHT_BASE * 0.5, float(z)), side, false)

	# Alças frontais/traseiras
	_build_drop_handle(casket_body, Vector3(0.0, HEIGHT_BASE * 0.5, -LENGTH * 0.48), 1.0, true)
	_build_drop_handle(casket_body, Vector3(0.0, HEIGHT_BASE * 0.5, LENGTH * 0.52), -1.0, true)

func _build_drop_handle(parent: Node3D, pos: Vector3, side: float, is_end: bool) -> void:
	var handle_root := Node3D.new()
	handle_root.position = pos
	parent.add_child(handle_root)

	# Placa de fixação na madeira
	var plate_size := Vector3(0.015, 0.06, 0.14) if not is_end else Vector3(0.14, 0.06, 0.015)
	var plate := _create_box(plate_size, mat_brass)
	handle_root.add_child(plate)

	# Barra da alça
	var bar_size := Vector3(0.02, 0.02, 0.18) if not is_end else Vector3(0.18, 0.02, 0.02)
	var bar := _create_box(bar_size, mat_brass)
	bar.position = Vector3(side * 0.04, -0.02, 0.0) if not is_end else Vector3(0.0, -0.02, side * 0.04)
	handle_root.add_child(bar)

	# Suportes que unem a barra à placa
	for offset_z in [-0.07, 0.07]:
		var mount_size := Vector3(0.035, 0.015, 0.015) if not is_end else Vector3(0.015, 0.015, 0.035)
		var mount := _create_box(mount_size, mat_brass)
		mount.position = Vector3(side * 0.02, -0.01, offset_z) if not is_end else Vector3(offset_z, -0.01, side * 0.02)
		handle_root.add_child(mount)

func _setup_grip_points() -> void:
	# 6 pontos de pega padrão para carregadores:
	# 0: Front-Left  (Cabeça, Esquerda)
	# 1: Mid-Left    (Centro, Esquerda)
	# 2: Rear-Left   (Pés, Esquerda)
	# 3: Front-Right (Cabeça, Direita)
	# 4: Mid-Right   (Centro, Direita)
	# 5: Rear-Right  (Pés, Direita)
	grip_markers.clear()
	var z_offsets := [-0.50, 0.05, 0.55]

	# Lado esquerdo (-X)
	for z in z_offsets:
		var marker := Marker3D.new()
		marker.name = "GripL_" + str(marker.get_instance_id())
		marker.position = Vector3(-(WIDTH_SHOULDER * 0.5 + 0.08), HEIGHT_BASE * 0.48, z)
		add_child(marker)
		grip_markers.append(marker)

	# Lado direito (+X)
	for z in z_offsets:
		var marker := Marker3D.new()
		marker.name = "GripR_" + str(marker.get_instance_id())
		marker.position = Vector3((WIDTH_SHOULDER * 0.5 + 0.08), HEIGHT_BASE * 0.48, z)
		add_child(marker)
		grip_markers.append(marker)

## Retorna a posição global de um dos 6 pontos de pega
func get_grip_world_pos(index: int) -> Vector3:
	if index >= 0 and index < grip_markers.size():
		return grip_markers[index].global_position
	return global_position

## Retorna a posição local do ponto de pega
func get_grip_local_pos(index: int) -> Vector3:
	if index >= 0 and index < grip_markers.size():
		return grip_markers[index].position
	return Vector3.ZERO

func _create_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	return mi
