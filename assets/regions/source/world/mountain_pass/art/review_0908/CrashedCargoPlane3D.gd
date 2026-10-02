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
	var stripe_mat := _mat("tactical_stripe", accent_color, 0.60, 0.20)
	var glass_mat := _mat("cockpit_glass", Color(0.20, 0.35, 0.45, 0.85), 0.15)
	var snow_mat := _mat("snow", snow_color, 0.95)
	var crate_wood := _mat("crate_wood", Color("#825a36"), 0.80)
	var crate_metal := _mat("crate_metal", Color("#2c3e50"), 0.40, 0.70)
	var seat_canvas := _mat("jumpseat", Color("#962d24"), 0.90)
	var yellow_hazard := _mat("hazard_yellow", Color("#f1c40f"), 0.50)
	var engine_dark := _mat("engine_cowling", Color("#1f2421"), 0.40, 0.75)
	var prop_blade := _mat("prop_spinner", Color("#2c3e50"), 0.30, 0.85)
	var prop_tip := _mat("prop_tip", Color("#f39c12"), 0.40)
	var red_alert := _mat("interior_light_red", Color("#e74c3c"), 0.4, 0.0, 1.4)

	# Nó dedicado para o teto cutaway (permite que Astra oculte ou aplique tween de fade)
	cutaway_roof = Node3D.new()
	cutaway_roof.name = "CutawayRoof"
	add_child(cutaway_roof)

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
	_add_box_to(self, Vector3(0.0, 2.75, 7.2), Vector3(2.45, 0.12, 1.80), fuse_mat, Vector3(-25.0, 0, 0))
	# Cilindros hidráulicos da rampa
	_add_cyl_to(self, Vector3(-1.25, 1.40, 6.8), 0.035, 1.60, roller_mat, Vector3(35.0, 0, 0))
	_add_cyl_to(self, Vector3(1.25, 1.40, 6.8), 0.035, 1.60, roller_mat, Vector3(35.0, 0, 0))

	# ==============================================================================
	# 3. COSTELAS E PAREDES LATERAIS DO COMPARTIMENTO DE CARGA
	# ==============================================================================
	# Paredes laterais inferiores (fixas no self)
	for sx in [-1.55, 1.55]:
		_add_box_to(self, Vector3(sx, 1.35, -1.25), Vector3(0.22, 2.30, 15.5), fuse_mat)
		# Faixa tática externa na lateral
		_add_box_to(self, Vector3(sx + (0.12 if sx > 0 else -0.12), 1.60, -1.25), Vector3(0.02, 0.35, 15.4), stripe_mat)

	# 9 Arcos estruturais / Costelas transversais internas
	for zi in range(9):
		var rz: float = -8.5 + float(zi) * 1.80
		# Colunas laterais da costela
		_add_box_to(self, Vector3(-1.42, 1.35, rz), Vector3(0.12, 2.20, 0.14), rib_mat)
		_add_box_to(self, Vector3(1.42, 1.35, rz), Vector3(0.12, 2.20, 0.14), rib_mat)
		# Luzes de emergência vermelhas nos arcos internos
		_add_box_to(self, Vector3(-1.38, 2.35, rz), Vector3(0.06, 0.06, 0.06), red_alert)

	# Assentos dobráveis de lona de tropas ao longo da parede esquerda e direita
	for zi in range(6):
		var sz: float = -7.5 + float(zi) * 2.10
		_add_box_to(self, Vector3(-1.30, 0.52, sz), Vector3(0.35, 0.04, 0.85), seat_canvas)
		_add_box_to(self, Vector3(1.30, 0.52, sz), Vector3(0.35, 0.04, 0.85), seat_canvas)

	# Carga amarrada no meio da baía (Caixas militares e paletes com suprimentos)
	# MountainCargoPlane used to mutate these boxes after construction to keep
	# the walkable aisle open. MultiMesh instances are immutable individually,
	# so store the same final gameplay transform directly in the batched model.
	_add_box_to(self, Vector3(-0.95, 0.65, -3.2), Vector3(0.55, 0.90, 1.40), crate_wood)
	_add_box_to(self, Vector3(-0.95, 0.58, -3.2), Vector3(0.55, 0.75, 1.20), crate_metal)
	_add_box_to(self, Vector3(-0.95, 1.22, -3.2), Vector3(0.55, 0.40, 0.90), crate_wood)
	# Tiras de amarração de carga
	_add_box_to(self, Vector3(0.05, 0.75, -3.2), Vector3(2.10, 0.03, 0.03), yellow_hazard)

	# Outro lote de carga perto da rampa
	_add_box_to(self, Vector3(-0.95, 0.55, 2.5), Vector3(0.55, 0.70, 1.10), crate_wood)
	_add_box_to(self, Vector3(-0.95, 0.45, 2.8), Vector3(0.55, 0.52, 0.90), crate_metal)

	# ==============================================================================
	# 4. CABINE DE COMANDO FRONTAL (COCKPIT) — Z = -9.0 a -15.0m
	# ==============================================================================
	# Parede divisória entre carga e cockpit com porta aberta
	_add_box_to(self, Vector3(-0.95, 1.30, -9.0), Vector3(0.95, 2.20, 0.16), rib_mat)
	_add_box_to(self, Vector3(0.95, 1.30, -9.0), Vector3(0.95, 2.20, 0.16), rib_mat)
	_add_box_to(self, Vector3(0.0, 2.15, -9.0), Vector3(1.00, 0.50, 0.16), rib_mat)

	# Assoalho e pedestal da cabine de comando (Z = -9.0 a -13.5m)
	_add_box_to(self, Vector3(0.0, 0.55, -11.2), Vector3(2.50, 0.20, 4.4), floor_mat)

	# Assentos de piloto e copiloto
	for px in [-0.60, 0.60]:
		_add_box_to(self, Vector3(px, 0.90, -11.5), Vector3(0.48, 0.55, 0.48), _mat("pilot_seat", Color("#1c2833"), 0.8))
		_add_box_to(self, Vector3(px, 1.35, -11.7), Vector3(0.46, 0.65, 0.12), _mat("pilot_seat", Color("#1c2833"), 0.8))
		_add_cyl_to(self, Vector3(px, 1.10, -12.1), 0.015, 0.35, roller_mat, Vector3(-35.0, 0, 0)) # Manche

	# Painel de instrumentos e consoles
	_add_box_to(self, Vector3(0.0, 1.15, -12.6), Vector3(2.20, 0.65, 0.55), _mat("instrument_panel", Color("#151816"), 0.6))
	_add_box_to(self, Vector3(0.0, 0.85, -11.6), Vector3(0.35, 0.45, 0.90), _mat("center_console", Color("#1e2320"), 0.6)) # Manetes

	# Nariz Ogival e Radome de Radar (-Z = -13.0 a -16.2m)
	_add_box_to(self, Vector3(0.0, 1.15, -14.2), Vector3(2.20, 1.80, 2.4), fuse_mat)
	_add_cyl_to(self, Vector3(0.0, 1.05, -15.8), 0.95, 1.40, _mat("radome", Color("#272c29"), 0.70), Vector3(90, 0, 0))

	# Para-brisas do Cockpit (Facetado)
	_add_box_to(self, Vector3(-0.65, 1.85, -13.1), Vector3(0.95, 0.60, 0.10), glass_mat, Vector3(30.0, 15.0, 0))
	_add_box_to(self, Vector3(0.65, 1.85, -13.1), Vector3(0.95, 0.60, 0.10), glass_mat, Vector3(30.0, -15.0, 0))

	# ==============================================================================
	# 5. NÓ DEDICADO 'CutawayRoof' — TETO DORSAL REMOVÍVEL/CUTAWAY
	# ==============================================================================
	# Todas as superfícies superiores do teto estão filhas de cutaway_roof!
	# Teto principal da baía de carga (Z: -9.0m a +6.5m, Y = 2.75m)
	_add_box_to(cutaway_roof, Vector3(0.0, 2.72, -1.25), Vector3(2.95, 0.22, 15.5), fuse_mat)
	# Dorso curvo superior
	_add_box_to(cutaway_roof, Vector3(0.0, 3.02, -1.25), Vector3(2.35, 0.38, 15.4), fuse_mat)
	# Teto do cockpit (-Z = -9.0 a -13.2m)
	_add_box_to(cutaway_roof, Vector3(0.0, 2.42, -11.1), Vector3(2.40, 0.25, 4.2), fuse_mat)
	# Vigas de teto das costelas
	for zi in range(9):
		var rz: float = -8.5 + float(zi) * 1.80
		_add_box_to(cutaway_roof, Vector3(0.0, 2.58, rz), Vector3(2.70, 0.14, 0.14), rib_mat)

	# Neve espessa acumulada no topo da fuselagem dorsal (filha do CutawayRoof)
	_add_box_to(cutaway_roof, Vector3(0.0, 3.25, -1.25), Vector3(2.10, 0.16, 15.2), snow_mat)
	_add_box_to(cutaway_roof, Vector3(0.0, 2.58, -11.1), Vector3(2.00, 0.12, 3.8), snow_mat)

	# ==============================================================================
	# 6. ASAS MONUMENTAIS E MOTORES TURBOPROP (ENVERGADURA DE 28 METROS)
	# ==============================================================================
	# Caixa central da asa sobre a fuselagem (Z = -3.5m, Y = 2.95m)
	_add_box_to(cutaway_roof, Vector3(0.0, 2.95, -3.5), Vector3(3.40, 0.55, 3.20), fuse_mat)

	# ASA DIREITA (+X = 1.7 a 14.0m) — Angulada levemente para cima
	_add_box_to(self, Vector3(7.8, 3.30, -3.5), Vector3(12.2, 0.38, 2.80), fuse_mat, Vector3(0, 0, 3.5))
	# Neve na asa direita
	_add_box_to(self, Vector3(7.8, 3.52, -3.5), Vector3(12.0, 0.10, 2.60), snow_mat, Vector3(0, 0, 3.5))

	# ASA ESQUERDA (-X = -1.7 a -14.0m) — Acidentada, tombada e cravada no gelo
	_add_box_to(self, Vector3(-5.5, 2.70, -3.5), Vector3(7.8, 0.38, 2.80), fuse_mat, Vector3(0, 0, -6.5))
	# Ponta esquerda quebrada repousando no solo/gelo
	_add_box_to(self, Vector3(-11.5, 1.45, -3.5), Vector3(5.5, 0.35, 2.50), fuse_mat, Vector3(0, 0, -22.0))
	_add_box_to(self, Vector3(-5.5, 2.92, -3.5), Vector3(7.6, 0.12, 2.60), snow_mat, Vector3(0, 0, -6.5))
	_add_box_to(self, Vector3(-11.5, 1.65, -3.5), Vector3(5.2, 0.15, 2.40), snow_mat, Vector3(0, 0, -22.0))

	# 4 Motores Turboprop com Hélices de 4 Pás
	var engine_coords = [
		{"pos": Vector3(-4.2, 2.60, -4.8), "cracked": false}, # Motor 2 (Interno esquerdo)
		{"pos": Vector3(-8.2, 1.85, -4.8), "cracked": true},  # Motor 1 (Externo esquerdo - soterrado na neve)
		{"pos": Vector3(4.2, 3.05, -4.8),  "cracked": false}, # Motor 3 (Interno direito)
		{"pos": Vector3(8.8, 3.35, -4.8),  "cracked": false}  # Motor 4 (Externo direito)
	]

	for eng in engine_coords:
		var ep: Vector3 = eng["pos"]
		var is_cracked: bool = eng["cracked"]
		# Nacelle cilíndrica do motor
		_add_cyl_to(self, ep, 0.55, 2.80, engine_dark, Vector3(90, 0, 0))
		# Bico do spinner da hélice
		_add_cyl_to(self, ep + Vector3(0, 0, -1.5), 0.35, 0.50, prop_blade, Vector3(90, 0, 0))

		# 4 pás de hélice
		if is_cracked:
			# Pás retorcidas pelo choque no gelo
			_add_box_to(self, ep + Vector3(0.5, 0.4, -1.5), Vector3(0.18, 0.90, 0.04), prop_blade, Vector3(15, 30, 45))
			_add_box_to(self, ep + Vector3(-0.4, -0.3, -1.5), Vector3(0.18, 0.70, 0.04), prop_blade, Vector3(-20, -15, -60))
			# Neve acumulada no motor caído
			_add_box_to(self, ep + Vector3(0, 0.45, 0), Vector3(1.2, 0.35, 2.2), snow_mat)
		else:
			# Hélice em cruz
			_add_box_to(self, ep + Vector3(0, 0, -1.5), Vector3(0.16, 2.20, 0.03), prop_blade)
			_add_box_to(self, ep + Vector3(0, 0, -1.5), Vector3(2.20, 0.16, 0.03), prop_blade)
			# Pontas amarelas de alta visibilidade
			_add_box_to(self, ep + Vector3(0, 1.0, -1.49), Vector3(0.18, 0.22, 0.04), prop_tip)
			_add_box_to(self, ep + Vector3(0, -1.0, -1.49), Vector3(0.18, 0.22, 0.04), prop_tip)
			_add_box_to(self, ep + Vector3(1.0, 0, -1.49), Vector3(0.22, 0.18, 0.04), prop_tip)
			_add_box_to(self, ep + Vector3(-1.0, 0, -1.49), Vector3(0.22, 0.18, 0.04), prop_tip)

	# ==============================================================================
	# 7. EMPENAGEM TRASEIRA MONUMENTAL (LEME VERTICAL E ESTABILIZADOR HORIZONTAL)
	# ==============================================================================
	# Cauda afilada subindo (Z = 6.0 a 10.5m)
	_add_box_to(cutaway_roof, Vector3(0.0, 2.20, 8.2), Vector3(2.40, 1.80, 4.4), fuse_mat, Vector3(-12.0, 0, 0))

	# Estabilizador Vertical (Leme colossal de 5.2m de altura)
	_add_box_to(cutaway_roof, Vector3(0.0, 5.0, 8.4), Vector3(0.32, 4.20, 3.4), fuse_mat, Vector3(-16.0, 0, 0))
	_add_box_to(cutaway_roof, Vector3(0.0, 7.2, 8.2), Vector3(0.34, 0.12, 3.2), snow_mat, Vector3(-16.0, 0, 0))

	# Estabilizadores Horizontais (Em T no alto da cauda)
	_add_box_to(cutaway_roof, Vector3(0.0, 6.8, 8.4), Vector3(9.2, 0.28, 2.2), fuse_mat)
	_add_box_to(cutaway_roof, Vector3(0.0, 7.0, 8.4), Vector3(9.0, 0.12, 2.0), snow_mat)

	_flush_batches(_box_batches, _unit_box(), "CargoBoxes")
	_flush_batches(_cylinder_batches, _unit_cylinder(), "CargoCylinders")
