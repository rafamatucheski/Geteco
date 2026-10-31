extends Node3D

## Avião Cargueiro Grande Acidentado no Lago (Crashed Cargo Plane 3D):
## Modelo 3D monumental de avião de transporte tático/militar (escala 1:1, ~24m de fuselagem).
## Apresenta rampa traseira aberta até o solo criando entrada caminhável e desobstruída,
## compartimento de carga penetrável visualmente com assoalho de roletes, costelas estruturais,
## assentos dobráveis, caixas de suprimentos com redes de amarração e cabine de comando frontal.
## Possui o nó dedicado 'CutawayRoof' para remoção/ocultação do teto dorsal em visão isométrica.

# Contratos de Integração:
@export var footprint_size: Vector2 = Vector2(28.0, 24.0)
@export var entrance_local_position: Vector3 = Vector3(0.0, 0.0, 9.2)
@export var entrance_clearance: float = 2.40

# Customização da cor de fuselagem:
@export var main_color: Color = Color("#4a564e"): set = set_main_color # Verde oliva / militar ártico
@export var accent_color: Color = Color("#2980b9")                      # Faixa azul tática
@export var snow_color: Color = Color("#f0f4f8")

# Referência ao nó do teto para cutaway imediato
var cutaway_roof: Node3D = null
var port_shell: Node3D = null
var starboard_shell: Node3D = null

static var _shared_box_mesh: BoxMesh
static var _shared_cylinder_mesh: CylinderMesh

var _materials: Dictionary = {}
var _box_batches: Dictionary = {}
var _cylinder_batches: Dictionary = {}
var _is_built: bool = false

func _init(p_main_color: Color = Color("#4a564e")) -> void:
	main_color = p_main_color

func _ready() -> void:
	if not _is_built:
		_build_model()

func set_main_color(new_color: Color) -> void:
	main_color = new_color
	if _materials.has("fuselage"):
		_materials["fuselage"].albedo_color = main_color

func set_cutaway(revealed: bool) -> void:
	if cutaway_roof and is_instance_valid(cutaway_roof):
		cutaway_roof.visible = not revealed

func set_side_cutaway(side: int, revealed: bool) -> void:
	var shell: Node3D = port_shell if side < 0 else starboard_shell
	if shell and is_instance_valid(shell):
		shell.visible = not revealed

func _mat(id: String, color: Color, roughness: float = 0.8, metallic: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	m.resource_name = id
	_materials[id] = m
	return m

static func _unit_box() -> BoxMesh:
	if _shared_box_mesh == null:
		_shared_box_mesh = BoxMesh.new()
		_shared_box_mesh.size = Vector3.ONE
		_shared_box_mesh.resource_name = "CargoPlaneSharedUnitBox"
	return _shared_box_mesh

static func _unit_cylinder() -> CylinderMesh:
	if _shared_cylinder_mesh == null:
		_shared_cylinder_mesh = CylinderMesh.new()
		_shared_cylinder_mesh.top_radius = 0.5
		_shared_cylinder_mesh.bottom_radius = 0.5
		_shared_cylinder_mesh.height = 1.0
		_shared_cylinder_mesh.radial_segments = 16
		_shared_cylinder_mesh.resource_name = "CargoPlaneSharedUnitCylinder"
	return _shared_cylinder_mesh

func _queue_instance(batches: Dictionary, p: Node3D, mat: Material, p_transform: Transform3D) -> void:
	if not batches.has(p):
		batches[p] = {}
	var material_batches: Dictionary = batches[p]
	if not material_batches.has(mat):
		material_batches[mat] = []
	var transforms: Array = material_batches[mat]
	transforms.append(p_transform)

func _add_box_to(p: Node3D, pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var local_basis := Basis.from_euler(rot_deg * PI / 180.0) * Basis.from_scale(size)
	_queue_instance(_box_batches, p, mat, Transform3D(local_basis, pos))

func _add_cyl_to(p: Node3D, pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var size := Vector3(radius * 2.0, height, radius * 2.0)
	var local_basis := Basis.from_euler(rot_deg * PI / 180.0) * Basis.from_scale(size)
	_queue_instance(_cylinder_batches, p, mat, Transform3D(local_basis, pos))

func _flush_batches(batches: Dictionary, mesh: Mesh, prefix: String) -> void:
	for parent_key in batches:
		var batch_parent := parent_key as Node3D
		var material_batches: Dictionary = batches[parent_key]
		for material_key in material_batches:
			var material := material_key as Material
			var transforms: Array = material_batches[material_key]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = mesh
			multimesh.instance_count = transforms.size()
			for index in range(transforms.size()):
				multimesh.set_instance_transform(index, transforms[index])
			var batch := MultiMeshInstance3D.new()
			batch.name = "%s_%s" % [prefix, material.resource_name]
			batch.multimesh = multimesh
			batch.material_override = material
			batch_parent.add_child(batch)
	batches.clear()

func _build_model() -> void:
	_is_built = true

	# Materiais PBR aeronáuticos
	var fuse_mat := _mat("fuselage", main_color, 0.55, 0.45)
	_mat("belly", Color("#333b35"), 0.65, 0.35)
	var rib_mat := _mat("interior_rib", Color("#5c675f"), 0.70, 0.30)
	var floor_mat := _mat("cargo_floor", Color("#272c29"), 0.60, 0.60)
	var roller_mat := _mat("rollers", Color("#7f8c8d"), 0.30, 0.90)
	_mat("tactical_stripe", accent_color, 0.60, 0.20)
	_mat("cockpit_glass", Color(0.20, 0.35, 0.45, 0.85), 0.15)
	_mat("snow", snow_color, 0.95)
	var crate_wood := _mat("crate_wood", Color("#825a36"), 0.80)
	var crate_metal := _mat("crate_metal", Color("#2c3e50"), 0.40, 0.70)
	var seat_canvas := _mat("jumpseat", Color("#962d24"), 0.90)
	var yellow_hazard := _mat("hazard_yellow", Color("#f1c40f"), 0.50)
	_mat("engine_cowling", Color("#1f2421"), 0.40, 0.75)
	_mat("prop_spinner", Color("#2c3e50"), 0.30, 0.85)
	_mat("prop_tip", Color("#f39c12"), 0.40)
	var red_alert := _mat("interior_light_red", Color("#e74c3c"), 0.4, 0.0, 1.4)

	# Nó dedicado para o teto cutaway (permite que Astra oculte ou aplique tween de fade)
	cutaway_roof = Node3D.new()
	cutaway_roof.name = "CutawayRoof"
	add_child(cutaway_roof)
	port_shell = Node3D.new()
	port_shell.name = "PortShell"
	add_child(port_shell)
	starboard_shell = Node3D.new()
	starboard_shell.name = "StarboardShell"
	add_child(starboard_shell)

	# ==============================================================================
	# 1. ASSOALHO CAMINHÁVEL E FUSOS DO COMPARTIMENTO DE CARGA (Y = 0.08 a 0.20)
	# ==============================================================================
	# Assoalho principal da baía de carga (Z: -9.0m a +6.5m, largura 2.7m)
	_add_box_to(self, Vector3(0.0, 0.12, -1.25), Vector3(2.70, 0.14, 15.5), floor_mat)
	# Trilhos duplos de roletes para paletes
	_add_box_to(self, Vector3(-0.65, 0.20, -1.25), Vector3(0.32, 0.03, 15.4), roller_mat)
	_add_box_to(self, Vector3(0.65, 0.20, -1.25), Vector3(0.32, 0.03, 15.4), roller_mat)
	# Faixas amarelas de aviso na borda do piso
	_add_box_to(self, Vector3(-1.25, 0.20, -1.25), Vector3(0.08, 0.02, 15.4), yellow_hazard)
	_add_box_to(self, Vector3(1.25, 0.20, -1.25), Vector3(0.08, 0.02, 15.4), yellow_hazard)

	# ==============================================================================
	# 2. RAMPA DE CARGA TRASEIRA ABERTA (ENTRADA LIVRE NO SOLO ATÉ Y = 0.0)
	# ==============================================================================
	# Rampa inferior estendida até o chão (Z de 6.5m a 9.5m, tocando Y=0 em Z=9.5)
	_add_box_to(self, Vector3(0.0, 0.06, 8.0), Vector3(2.40, 0.12, 3.20), floor_mat, Vector3(3.5, 0, 0))
	_add_box_to(self, Vector3(-0.60, 0.13, 8.0), Vector3(0.24, 0.03, 3.10), roller_mat, Vector3(3.5, 0, 0))
	_add_box_to(self, Vector3(0.60, 0.13, 8.0), Vector3(0.24, 0.03, 3.10), roller_mat, Vector3(3.5, 0, 0))
	# Porta superior traseira tipo concha (Clamshell) erguida e travada no teto
	_add_box_to(cutaway_roof, Vector3(0.0, 2.75, 7.2), Vector3(2.45, 0.12, 1.80), fuse_mat, Vector3(-25.0, 0, 0))
	# Cilindros hidráulicos da rampa
	_add_cyl_to(self, Vector3(-1.25, 1.40, 6.8), 0.035, 1.60, roller_mat, Vector3(35.0, 0, 0))
	_add_cyl_to(self, Vector3(1.25, 1.40, 6.8), 0.035, 1.60, roller_mat, Vector3(35.0, 0, 0))

	# ==============================================================================
	# 3. COSTELAS E PAREDES LATERAIS DO COMPARTIMENTO DE CARGA
	# ==============================================================================
	# 9 Arcos estruturais / Costelas transversais internas
	for zi in range(9):
		var rz: float = -8.5 + float(zi) * 1.80
		# Recolhidas ao volume das paredes: não criam sólidos no corredor.
		_add_box_to(port_shell, Vector3(-1.49, 1.43, rz), Vector3(0.12, 1.94, 0.14), rib_mat)
		_add_box_to(starboard_shell, Vector3(1.49, 1.43, rz), Vector3(0.12, 1.94, 0.14), rib_mat)
		# Luzes de emergência vermelhas nos arcos internos
		_add_box_to(port_shell, Vector3(-1.45, 2.35, rz), Vector3(0.06, 0.06, 0.06), red_alert)

	# Assentos dobráveis de lona de tropas ao longo da parede esquerda e direita
	for zi in range(6):
		var sz: float = -7.5 + float(zi) * 2.10
		# Bancos recolhidos, com encosto e dobradiça dentro do sólido lateral.
		for side in [-1.0, 1.0]:
			var shell: Node3D = port_shell if side < 0 else starboard_shell
			_add_box_to(shell, Vector3(side * 1.51, 1.0, sz), Vector3(0.12, 0.74, 0.80), seat_canvas)
			_add_cyl_to(shell, Vector3(side * 1.50, 0.61, sz), 0.03, 0.82, roller_mat, Vector3(90, 0, 0))

	# Carga amarrada no meio da baía (Caixas militares e paletes com suprimentos)
	# O MountainCargoPlane alterava estas caixas depois da construção para manter
	# o corredor caminhável aberto. Instâncias de MultiMesh são imutáveis individualmente,
	# então grava a mesma transformação final de gameplay direto no modelo em lote.
	_add_box_to(self, Vector3(-0.95, 0.65, -3.2), Vector3(0.55, 0.90, 1.40), crate_wood)
	_add_box_to(self, Vector3(-0.95, 0.58, -3.2), Vector3(0.55, 0.75, 1.20), crate_metal)
	_add_box_to(self, Vector3(-0.95, 1.22, -3.2), Vector3(0.55, 0.40, 0.90), crate_wood)
	# As amarrações ficam junto à carga, sem atravessar a circulação.
	for z in [-3.68, -2.72]:
		_add_box_to(self, Vector3(-0.95, 1.445, z), Vector3(0.57, 0.04, 0.055), yellow_hazard)
		_add_box_to(self, Vector3(-0.645, 0.81, z), Vector3(0.03, 1.26, 0.055), yellow_hazard)

	# Outro lote de carga perto da rampa
	_add_box_to(self, Vector3(-0.95, 0.55, 2.5), Vector3(0.55, 0.70, 1.10), crate_wood)
	_add_box_to(self, Vector3(-0.95, 0.45, 2.8), Vector3(0.55, 0.52, 0.90), crate_metal)

	# ==============================================================================
	# 4. CABINE DE COMANDO FRONTAL (COCKPIT) — Z = -9.0 a -15.0m
	# ==============================================================================
	# Batentes laterais recolhidos: a ligação com a cabine fica livre.
	_add_box_to(port_shell, Vector3(-1.50, 1.42, -9.0), Vector3(0.12, 1.90, 0.16), rib_mat)
	_add_box_to(starboard_shell, Vector3(1.50, 1.42, -9.0), Vector3(0.12, 1.90, 0.16), rib_mat)
	_add_box_to(cutaway_roof, Vector3(0.0, 2.48, -9.0), Vector3(2.98, 0.14, 0.16), rib_mat)

	# Assoalho e pedestal da cabine de comando (Z = -9.0 a -13.5m)
	_add_box_to(self, Vector3(0.0, 0.55, -11.2), Vector3(2.50, 0.20, 4.4), floor_mat)
	# Mesma inclinação/posição do apoio físico autorado em CargoPlaneNative.
	_add_box_to(self, Vector3(0.0, 0.40, -8.4), Vector3(0.95, 0.06, 1.30), floor_mat, Vector3(20, 0, 0))

	# Assentos de piloto e copiloto
	for px in [-0.60, 0.60]:
		_add_box_to(self, Vector3(px, 0.90, -11.5), Vector3(0.48, 0.55, 0.48), _mat("pilot_seat", Color("#1c2833"), 0.8))
		_add_box_to(self, Vector3(px, 1.35, -11.7), Vector3(0.46, 0.65, 0.12), _mat("pilot_seat", Color("#1c2833"), 0.8))
		_add_cyl_to(self, Vector3(px, 1.10, -11.74), 0.015, 0.35, roller_mat, Vector3(-35.0, 0, 0)) # Manche recolhido ao sólido do assento

	# Painel de instrumentos e consoles
	_add_box_to(self, Vector3(0.0, 1.15, -12.6), Vector3(2.20, 0.65, 0.55), _mat("instrument_panel", Color("#151816"), 0.6))
	_add_box_to(self, Vector3(0.0, 1.10, -12.6), Vector3(0.35, 0.45, 0.50), _mat("center_console", Color("#1e2320"), 0.6)) # Manetes, dentro do bloqueio do painel

	# ==============================================================================
	# 5. NÓ DEDICADO 'CutawayRoof' — TETO DORSAL REMOVÍVEL/CUTAWAY
	# ==============================================================================
	# Vigas de teto das costelas
	for zi in range(9):
		var rz: float = -8.5 + float(zi) * 1.80
		_add_box_to(cutaway_roof, Vector3(0.0, 2.58, rz), Vector3(2.70, 0.14, 0.14), rib_mat)

	# Superfícies aeronáuticas autoradas, agrupadas por material e recorte.
	# Sem processamento por frame; os sólidos e recompensas continuam na Native.
	preload("res://assets/regions/source/world/mountain_pass/art/review_0908/CargoPlaneAirframe.gd").new().build(self)

	_flush_batches(_box_batches, _unit_box(), "CargoBoxes")
	_flush_batches(_cylinder_batches, _unit_cylinder(), "CargoCylinders")
