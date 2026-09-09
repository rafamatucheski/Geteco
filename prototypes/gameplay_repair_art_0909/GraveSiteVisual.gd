class_name GraveSiteVisual
extends Node3D

## Sepultura com 4 estados visuais dinâmicos e escala coerente (~2.4m x 1.2m).
## Estados:
##   0: OPEN - Cova aberta escavada, pranchas guia laterais, correias de suspensão e pilha de terra ao lado.
##   1: LOWERING - Caixão sendo baixado verticalmente para o fundo da cova pelas correias.
##   2: FILLING - Aterramento da cova, terra subindo e cobrindo o caixão até formar o montículo.
##   3: COMPLETED - Sepultura concluída, montículo de terra fresca, cruz/lápide de cabeceira e flores.

enum State {
	OPEN,
	LOWERING,
	FILLING,
	COMPLETED
}

signal state_changed(new_state: State)
signal lowering_progress(ratio: float)
signal filling_progress(ratio: float)

# Dimensões da sepultura
const PIT_LENGTH := 2.30
const PIT_WIDTH := 0.96
const PIT_DEPTH := 1.15

var current_state: State = State.OPEN

# Nós da geometria
var pit_root: Node3D
var pit_interior: Node3D
var side_dirt_pile: Node3D
var lowering_straps: Node3D
var strap_mesh_1: MeshInstance3D
var strap_mesh_2: MeshInstance3D
var filling_dirt_mesh: MeshInstance3D
var completed_mound: Node3D
var headstone: Node3D
var flowers: Node3D
var wooden_planks: Node3D

# Referência opcional ao caixão sendo sepultado
var hosted_casket: Node3D

# Materiais
var mat_soil_dark: StandardMaterial3D
var mat_soil_fresh: StandardMaterial3D
var mat_grass_trim: StandardMaterial3D
var mat_strap: StandardMaterial3D
var mat_plank: StandardMaterial3D
var mat_stone: StandardMaterial3D
var mat_cross: StandardMaterial3D

func _init() -> void:
	_setup_materials()
	_build_components()
	set_state(State.OPEN)

func _setup_materials() -> void:
	# Terra escura e úmida do fundo da cova
	mat_soil_dark = StandardMaterial3D.new()
	mat_soil_dark.albedo_color = Color("#1e1711")
	mat_soil_dark.roughness = 0.95

	# Terra revolvida fresca da pilha e do montículo
	mat_soil_fresh = StandardMaterial3D.new()
	mat_soil_fresh.albedo_color = Color("#4a3726")
	mat_soil_fresh.roughness = 0.90

	# Grama circundante
	mat_grass_trim = StandardMaterial3D.new()
	mat_grass_trim.albedo_color = Color("#293a2c")
	mat_grass_trim.roughness = 0.85

	# Correias de tecido reforçado para descida do caixão
	mat_strap = StandardMaterial3D.new()
	mat_strap.albedo_color = Color("#5a5142")
	mat_strap.roughness = 0.80

	# Pranchas de apoio de madeira de pinho
	mat_plank = StandardMaterial3D.new()
	mat_plank.albedo_color = Color("#6e553c")
	mat_plank.roughness = 0.75

	# Lápide de pedra calcária envelhecida
	mat_stone = StandardMaterial3D.new()
	mat_stone.albedo_color = Color("#828580")
	mat_stone.roughness = 0.85

	# Cruz de madeira de lei
	mat_cross = StandardMaterial3D.new()
	mat_cross.albedo_color = Color("#554333")
	mat_cross.roughness = 0.80

func _build_components() -> void:
	# 1. Cavidade da cova (pit)
	pit_root = Node3D.new()
	pit_root.name = "PitRoot"
	add_child(pit_root)

	# Fundo da cova
	var pit_floor := _create_box(Vector3(PIT_WIDTH, 0.05, PIT_LENGTH), mat_soil_dark)
	pit_floor.position = Vector3(0.0, -PIT_DEPTH, 0.0)
	pit_root.add_child(pit_floor)

	# Paredes internas da cova (Norte, Sul, Leste, Oeste)
	var wall_n := _create_box(Vector3(PIT_WIDTH, PIT_DEPTH, 0.05), mat_soil_dark)
	wall_n.position = Vector3(0.0, -PIT_DEPTH * 0.5, -PIT_LENGTH * 0.5)
	pit_root.add_child(wall_n)

	var wall_s := _create_box(Vector3(PIT_WIDTH, PIT_DEPTH, 0.05), mat_soil_dark)
	wall_s.position = Vector3(0.0, -PIT_DEPTH * 0.5, PIT_LENGTH * 0.5)
	pit_root.add_child(wall_s)

	var wall_w := _create_box(Vector3(0.05, PIT_DEPTH, PIT_LENGTH), mat_soil_dark)
	wall_w.position = Vector3(-PIT_WIDTH * 0.5, -PIT_DEPTH * 0.5, 0.0)
	pit_root.add_child(wall_w)

	var wall_e := _create_box(Vector3(0.05, PIT_DEPTH, PIT_LENGTH), mat_soil_dark)
	wall_e.position = Vector3(PIT_WIDTH * 0.5, -PIT_DEPTH * 0.5, 0.0)
	pit_root.add_child(wall_e)

	# 2. Pranchas guia nas margens da cova
	wooden_planks = Node3D.new()
	wooden_planks.name = "WoodenPlanks"
	add_child(wooden_planks)
	for s in [-1.0, 1.0]:
		var plank := _create_box(Vector3(0.18, 0.04, PIT_LENGTH + 0.30), mat_plank)
		plank.position = Vector3(s * (PIT_WIDTH * 0.5 + 0.10), 0.02, 0.0)
		wooden_planks.add_child(plank)

	# 3. Correias de descida transversais
	lowering_straps = Node3D.new()
	lowering_straps.name = "LoweringStraps"
	add_child(lowering_straps)

	strap_mesh_1 = _create_box(Vector3(PIT_WIDTH + 0.35, 0.02, 0.09), mat_strap)
	strap_mesh_1.position = Vector3(0.0, 0.04, -0.45)
	lowering_straps.add_child(strap_mesh_1)

	strap_mesh_2 = _create_box(Vector3(PIT_WIDTH + 0.35, 0.02, 0.09), mat_strap)
	strap_mesh_2.position = Vector3(0.0, 0.04, 0.45)
	lowering_straps.add_child(strap_mesh_2)

	# 4. Pilha de terra escavada ao lado da sepultura (usada durante OPEN e consumida em FILLING)
	side_dirt_pile = Node3D.new()
	side_dirt_pile.name = "SideDirtPile"
	side_dirt_pile.position = Vector3(PIT_WIDTH * 0.5 + 0.65, 0.0, 0.0)
	add_child(side_dirt_pile)

	var mound_main := _create_ellipsoid(Vector3(0.85, 0.48, PIT_LENGTH * 0.85), mat_soil_fresh)
	mound_main.position = Vector3(0.0, 0.18, 0.0)
	side_dirt_pile.add_child(mound_main)

	# 5. Volume de terra subindo dentro da cova durante o aterramento
	filling_dirt_mesh = _create_box(Vector3(PIT_WIDTH - 0.02, 0.10, PIT_LENGTH - 0.02), mat_soil_fresh)
	filling_dirt_mesh.position = Vector3(0.0, -PIT_DEPTH, 0.0)
	filling_dirt_mesh.visible = false
	add_child(filling_dirt_mesh)

	# 6. Sepultura concluída (Montículo acabado, grama nas bordas, lápide e flores)
	completed_mound = Node3D.new()
	completed_mound.name = "CompletedMound"
	completed_mound.visible = false
	add_child(completed_mound)

	# Montículo curvado de terra fresca
	var final_soil := _create_ellipsoid(Vector3(PIT_WIDTH + 0.18, 0.32, PIT_LENGTH + 0.15), mat_soil_fresh)
	final_soil.position = Vector3(0.0, 0.10, 0.0)
	completed_mound.add_child(final_soil)

	# Moldura de pedras e terra compactada ao redor
	var border := _create_box(Vector3(PIT_WIDTH + 0.28, 0.06, PIT_LENGTH + 0.28), mat_grass_trim)
	border.position = Vector3(0.0, 0.02, 0.0)
	completed_mound.add_child(border)

	# Lápide / cruz de cabeceira (lado Norte / -Z)
	headstone = Node3D.new()
	headstone.position = Vector3(0.0, 0.0, -PIT_LENGTH * 0.5 - 0.12)
	completed_mound.add_child(headstone)

	var base_stone := _create_box(Vector3(0.55, 0.12, 0.22), mat_stone)
	base_stone.position = Vector3(0.0, 0.06, 0.0)
	headstone.add_child(base_stone)

	var upright_cross := _create_box(Vector3(0.08, 0.72, 0.08), mat_cross)
	upright_cross.position = Vector3(0.0, 0.42, 0.0)
	headstone.add_child(upright_cross)

	var horiz_cross := _create_box(Vector3(0.38, 0.08, 0.08), mat_cross)
	horiz_cross.position = Vector3(0.0, 0.54, 0.0)
	headstone.add_child(horiz_cross)

	# Arranjo de flores memorial no centro do túmulo
	flowers = Node3D.new()
	flowers.position = Vector3(0.0, 0.24, 0.15)
	completed_mound.add_child(flowers)

	var mat_rose := StandardMaterial3D.new()
	mat_rose.albedo_color = Color("#b33939")
	mat_rose.roughness = 0.60

	var mat_stem := StandardMaterial3D.new()
	mat_stem.albedo_color = Color("#218c74")
	mat_stem.roughness = 0.70

	for i in 5:
		var angle := float(i) * TAU / 5.0
		var fl := _create_ellipsoid(Vector3(0.09, 0.07, 0.09), mat_rose)
		fl.position = Vector3(cos(angle) * 0.12, 0.04, sin(angle) * 0.12)
		flowers.add_child(fl)

	var fl_center := _create_ellipsoid(Vector3(0.11, 0.08, 0.11), mat_rose)
	fl_center.position = Vector3(0.0, 0.05, 0.0)
	flowers.add_child(fl_center)

	var ribbon := _create_box(Vector3(0.32, 0.015, 0.04), mat_strap)
	ribbon.position = Vector3(0.0, 0.01, 0.0)
	flowers.add_child(ribbon)

## Configura o estado visual instantaneamente
func set_state(new_state: State) -> void:
	current_state = new_state
	match current_state:
		State.OPEN:
			pit_root.visible = true
			wooden_planks.visible = true
			lowering_straps.visible = true
			side_dirt_pile.visible = true
			side_dirt_pile.scale = Vector3.ONE
			filling_dirt_mesh.visible = false
			completed_mound.visible = false
			strap_mesh_1.position.y = 0.04
			strap_mesh_2.position.y = 0.04

		State.LOWERING:
			pit_root.visible = true
			wooden_planks.visible = true
			lowering_straps.visible = true
			side_dirt_pile.visible = true
			filling_dirt_mesh.visible = false
			completed_mound.visible = false

		State.FILLING:
			pit_root.visible = true
			wooden_planks.visible = true
			lowering_straps.visible = true
			side_dirt_pile.visible = true
			filling_dirt_mesh.visible = true
			completed_mound.visible = false

		State.COMPLETED:
			pit_root.visible = false
			wooden_planks.visible = false
			lowering_straps.visible = false
			side_dirt_pile.visible = false
			filling_dirt_mesh.visible = false
			completed_mound.visible = true
			if is_instance_valid(hosted_casket):
				hosted_casket.visible = false
				hosted_casket.queue_free()
				hosted_casket = null

	state_changed.emit(current_state)

## Posiciona o caixão sobre a cova pronto para a cerimônia e descida
func attach_casket(casket: Node3D) -> void:
	hosted_casket = casket
	if casket.get_parent() != self:
		casket.reparent(self)
	casket.position = Vector3(0.0, 0.06, 0.0)

## Animação suave de descida do caixão para dentro da cavidade
func animate_lowering(duration: float = 3.5) -> Tween:
	set_state(State.LOWERING)
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	var target_depth := -PIT_DEPTH + 0.28
	if is_instance_valid(hosted_casket):
		tween.tween_property(hosted_casket, "position:y", target_depth, duration)

	# As correias descem acompanhando o caixão
	tween.parallel().tween_property(strap_mesh_1, "position:y", target_depth, duration)
	tween.parallel().tween_property(strap_mesh_2, "position:y", target_depth, duration)

	tween.parallel().tween_method(func(val: float):
		lowering_progress.emit(val)
	, 0.0, 1.0, duration)

	return tween

## Animação de aterramento: a terra sobe, a pilha lateral esvazia e fecha o túmulo
func animate_filling(duration: float = 4.0) -> Tween:
	set_state(State.FILLING)
	filling_dirt_mesh.visible = true
	filling_dirt_mesh.position.y = -PIT_DEPTH + 0.10
	filling_dirt_mesh.scale = Vector3(1.0, 0.5, 1.0)

	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Nível de terra sobe até o solo e ultrapassa formando o montículo
	tween.tween_property(filling_dirt_mesh, "position:y", 0.05, duration)
	tween.parallel().tween_property(filling_dirt_mesh, "scale:y", 8.0, duration)

	# Pilha lateral diminui conforme é despejada para a cova
	tween.parallel().tween_property(side_dirt_pile, "scale", Vector3(0.05, 0.05, 0.05), duration)

	# O caixão é coberto: quando a terra passar da metade, podemos ocultá-lo sob a camada de terra
	tween.parallel().tween_method(func(progress: float):
		filling_progress.emit(progress)
		if progress > 0.65 and is_instance_valid(hosted_casket) and hosted_casket.visible:
			hosted_casket.visible = false
	, 0.0, 1.0, duration)

	# Conclusão do aterramento: transição para o túmulo definitivo
	tween.tween_callback(func():
		set_state(State.COMPLETED)
	)

	return tween

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
