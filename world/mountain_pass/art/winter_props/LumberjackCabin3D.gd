class_name LumberjackCabin3D
extends Node3D

## Abrigo / Microchalé de Lenhador (Lumberjack Work Shelter 3D):
## Refúgio rústico e oficina de corte de madeira em escala métrica humana (1:1).
## Diferenciado de um chalé residencial: apresenta ferramentas de lenhador (serra traçadeira de dois homens,
## machados, ganchos de tora), toras brutas entalhadas nos cantos (saddle notch), banco de tora para botas,
## limpador de lama de ferro fundido, pedra de afiar (rebolo), telhado de tábuas irregulares e desgaste discreto.

# Contratos de Integração Exigidos:
@export var footprint_size: Vector2 = Vector2(3.6, 4.2)
@export var entrance_local_position: Vector3 = Vector3(0.0, 0.0, 2.1)
@export var entrance_clearance: float = 0.95

# Customização da cor principal antes ou depois de entrar na árvore:
@export var main_color: Color = Color("#543820"): set = set_main_color
@export var trim_color: Color = Color("#382314")
@export var snow_color: Color = Color("#f0f4f8")

var _materials: Dictionary = {}
var _is_built: bool = false
var _door_parts: Array[MeshInstance3D] = []

func _init(p_main_color: Color = Color("#543820")) -> void:
	main_color = p_main_color

func _ready() -> void:
	if not _is_built:
		_build_cabin()

func set_main_color(new_color: Color) -> void:
	main_color = new_color
	if _materials.has("wood_main"):
		_materials["wood_main"].albedo_color = main_color

func _mat(id: String, color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	_materials[id] = m
	return m

func _add_box(pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi

func _add_door_part(pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var part := _add_box(pos, size, mat, rot_deg)
	part.set_meta("closed_position", pos)
	_door_parts.append(part)

func set_open_amount(value: float) -> void:
	for part in _door_parts:
		var closed: Vector3 = part.get_meta("closed_position")
		part.position = closed + Vector3(-1.05 * clampf(value, 0, 1), 0, 0)

func _add_cyl(pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi

func _build_cabin() -> void:
	_is_built = true
	var wood_main := _mat("wood_main", main_color, 0.88)
	var wood_trim := _mat("wood_trim", trim_color, 0.92)
	var wood_floor := _mat("wood_floor", Color("#3d2716"), 0.80)
	var stone_mat := _mat("stone", Color("#424346"), 0.95)
	var stone_moss := _mat("stone_moss", Color("#343d32"), 0.90) # Desgaste/musgo na base
	var snow_mat := _mat("snow", snow_color, 0.95)
	var iron_mat := _mat("iron", Color("#222225"), 0.35, 0.85)
	var steel_mat := _mat("steel", Color("#7f8c8d"), 0.25, 0.90)
	var glass_mat := _mat("glass", Color(0.68, 0.80, 0.86, 0.9), 0.20)
	var bark_mat := _mat("bark", Color("#2e1c11"), 0.95)
	var cut_end := _mat("cut_end", Color("#d5a86d"), 0.70)

	# 1. Fundação de Pedras de Rio Rústicas com Pátina de Umidade (Y = 0.0 a 0.20)
	for cx in [-1.72, 1.72]:
		for cz in [-2.02, 2.02]:
			_add_box(Vector3(cx, 0.10, cz), Vector3(0.44, 0.20, 0.44), stone_mat)
			# Musgo na base úmida de pedra
			_add_box(Vector3(cx, 0.04, cz), Vector3(0.46, 0.08, 0.46), stone_moss)

	# Soalho de pranchas rústicas de cedro resistente a desgaste
	_add_box(Vector3(0.0, 0.14, 0.0), Vector3(3.40, 0.12, 3.90), wood_floor)

	# Degrau de entrada de tronco chanfrado em +Z (frente livre)
	_add_box(Vector3(0.0, 0.06, 2.08), Vector3(1.20, 0.12, 0.36), wood_trim)

	# Raspador de botas de ferro fundido no degrau (à direita da porta)
	_add_box(Vector3(0.55, 0.15, 2.08), Vector3(0.02, 0.08, 0.18), iron_mat)
	_add_box(Vector3(0.55, 0.19, 2.08), Vector3(0.015, 0.02, 0.16), steel_mat)

	# 2. Cantos de Toras Entalhadas em Sela (Saddle-Notch Corner Logs)
	var wall_h: float = 2.25
	for cx in [-1.68, 1.68]:
		for cz in [-1.92, 1.92]:
			# Pilar principal de canto
			_add_box(Vector3(cx, 0.18 + wall_h * 0.5, cz), Vector3(0.24, wall_h, 0.24), wood_trim)
			# Pontas de toras que ultrapassam a quina (entalhe característico de abrigo de tora)
			for ty in [0.45, 0.95, 1.45, 1.95]:
				var out_dir_x: float = 1.0 if cx > 0 else -1.0
				var out_dir_z: float = 1.0 if cz > 0 else -1.0
				_add_cyl(Vector3(cx + out_dir_x * 0.16, ty, cz), 0.07, 0.32, bark_mat, Vector3(0, 0, 90))
				_add_cyl(Vector3(cx + out_dir_x * 0.32, ty, cz), 0.068, 0.015, cut_end, Vector3(0, 0, 90))
				_add_cyl(Vector3(cx, ty + 0.25, cz + out_dir_z * 0.16), 0.07, 0.32, bark_mat, Vector3(90, 0, 0))
				_add_cyl(Vector3(cx, ty + 0.25, cz + out_dir_z * 0.32), 0.068, 0.015, cut_end, Vector3(90, 0, 0))

	# 3. Paredes de Tábuas Maciças com Ranhuras Rústicas
	# Parede Traseira (-Z = -1.90)
	_add_box(Vector3(0.0, 0.18 + wall_h * 0.5, -1.90), Vector3(3.10, wall_h, 0.14), wood_main)
	for y_step in [0.65, 1.25, 1.85]:
		_add_box(Vector3(0.0, y_step, -1.98), Vector3(3.12, 0.06, 0.04), wood_trim)

	# Paredes Laterais (X = ±1.65)
	for sx in [-1.65, 1.65]:
		_add_box(Vector3(sx, 0.18 + wall_h * 0.5, 0.0), Vector3(0.14, wall_h, 3.60), wood_main)
		for y_step in [0.65, 1.25, 1.85]:
			_add_box(Vector3(sx + (0.07 if sx > 0 else -0.07), y_step, 0.0), Vector3(0.04, 0.06, 3.62), wood_trim)

	# Janela Pequena de Vigia na Parede Direita (+X) com Grades Rústicas
	_add_box(Vector3(1.72, 1.35, 0.20), Vector3(0.06, 0.85, 0.75), wood_trim)
	_add_box(Vector3(1.65, 1.35, 0.20), Vector3(0.02, 0.70, 0.60), glass_mat)
	_add_box(Vector3(1.73, 1.35, 0.20), Vector3(0.07, 0.70, 0.04), wood_trim)
	_add_box(Vector3(1.73, 1.35, 0.20), Vector3(0.07, 0.04, 0.60), wood_trim)
	_add_box(Vector3(1.74, 0.89, 0.20), Vector3(0.12, 0.05, 0.82), wood_trim)
	_add_box(Vector3(1.74, 0.93, 0.20), Vector3(0.10, 0.03, 0.78), snow_mat)

	# 4. Parede Frontal (+Z = 1.90) com Vão da Porta
	_add_box(Vector3(-1.05, 0.18 + wall_h * 0.5, 1.90), Vector3(1.00, wall_h, 0.14), wood_main)
	_add_box(Vector3(1.05, 0.18 + wall_h * 0.5, 1.90), Vector3(1.00, wall_h, 0.14), wood_main)
	_add_box(Vector3(0.0, 2.29, 1.90), Vector3(1.10, 0.28, 0.14), wood_main)

	# Batente Volumétrico da Porta de Lenhador (0.95m livre x 2.05m altura)
	_add_box(Vector3(-0.52, 1.15, 1.94), Vector3(0.10, 2.10, 0.10), wood_trim)
	_add_box(Vector3(0.52, 1.15, 1.94), Vector3(0.10, 2.10, 0.10), wood_trim)
	_add_box(Vector3(0.0, 2.18, 1.94), Vector3(1.14, 0.10, 0.10), wood_trim)

	# Folha da porta rústica com tábuas desiguais e ferragens
	var door_mat := _mat("door_leaf", Color("#3b2415"), 0.82)
	_add_door_part(Vector3(0.0, 1.14, 1.88), Vector3(0.92, 2.00, 0.06), door_mat)
	# Travessas diagonais em Z
	_add_door_part(Vector3(0.0, 0.45, 1.92), Vector3(0.86, 0.10, 0.03), wood_trim)
	_add_door_part(Vector3(0.0, 1.80, 1.92), Vector3(0.86, 0.10, 0.03), wood_trim)
	_add_door_part(Vector3(0.0, 1.12, 1.92), Vector3(0.86, 0.10, 0.03), wood_trim)
	_add_door_part(Vector3(0.0, 1.12, 1.92), Vector3(0.08, 1.30, 0.03), wood_trim, Vector3(0, 0, 32.0))
	# Fechadura e alavanca pesada de ferro forjado
	_add_door_part(Vector3(0.36, 1.05, 1.94), Vector3(0.04, 0.16, 0.04), iron_mat)
	_add_door_part(Vector3(0.34, 1.05, 1.97), Vector3(0.09, 0.03, 0.03), iron_mat)

	# ==============================================================================
	# 5. DIFERENCIAÇÃO: BANCO DE TORA PARA DESCALÇAR BOTAS E ÁREA DE ENTRADA
	# ==============================================================================
	# Banco rústico de meia-tora na fachada frontal, à esquerda da porta (X = -1.15, Z = 2.15)
	# Fora do vão livre da porta (+Z = 2.1, X = 0.0), permitindo acesso desimpedido
	_add_cyl(Vector3(-1.15, 0.44, 2.15), 0.16, 0.90, wood_trim, Vector3(0, 0, 90)) # Assento de meia tora
	_add_cyl(Vector3(-1.45, 0.22, 2.15), 0.08, 0.44, wood_trim)                     # Pé esquerdo
	_add_cyl(Vector3(-0.85, 0.22, 2.15), 0.08, 0.44, wood_trim)                     # Pé direito
	_add_box(Vector3(-1.15, 0.48, 2.15), Vector3(0.85, 0.03, 0.26), snow_mat)      # Neve rala no banco

	# Par de galochas/botas de lenhador encostadas sob o banco
	_add_box(Vector3(-1.30, 0.08, 2.15), Vector3(0.10, 0.16, 0.22), iron_mat)
	_add_box(Vector3(-1.18, 0.08, 2.15), Vector3(0.10, 0.16, 0.22), iron_mat)

	# ==============================================================================
	# 6. DIFERENCIAÇÃO: FERRAMENTAS REAIS DE LENHADOR
	# ==============================================================================
	# A. SERRA TRAÇADEIRA DE DOIS HOMENS (Two-Man Crosscut Saw) pendurada na parede frontal (X = 1.15, Y = 1.35)
	var saw_blade_mat := steel_mat
	var handle_wood := _mat("handle_wood", Color("#b5834b"), 0.70)
	# Lâmina arqueada da serra de 1,4m de comprimento
	_add_box(Vector3(1.15, 1.40, 1.98), Vector3(1.40, 0.12, 0.015), saw_blade_mat)
	# Dentes de corte da serra na borda inferior
	_add_box(Vector3(1.15, 1.33, 1.98), Vector3(1.36, 0.02, 0.012), saw_blade_mat)
	# Cabos verticais de madeira nas duas extremidades
	_add_cyl(Vector3(0.48, 1.40, 1.99), 0.022, 0.24, handle_wood)
	_add_cyl(Vector3(1.82, 1.40, 1.99), 0.022, 0.24, handle_wood)
	# Suportes de ferro onde a serra fica pendurada
	_add_box(Vector3(0.70, 1.48, 1.96), Vector3(0.03, 0.06, 0.06), iron_mat)
	_add_box(Vector3(1.60, 1.48, 1.96), Vector3(0.03, 0.06, 0.06), iron_mat)

	# B. MACHADOS DE DERRUBADA E GANCHO DE TORA (Cant Hook) na parede lateral esquerda (X = -1.74)
	# Prateleira/gancheira de ferramentas
	_add_box(Vector3(-1.76, 1.55, -0.20), Vector3(0.08, 0.08, 1.60), wood_trim)
	# Machado 1 pendurado
	_add_box(Vector3(-1.78, 1.25, -0.70), Vector3(0.03, 0.75, 0.04), handle_wood)
	_add_box(Vector3(-1.78, 1.55, -0.74), Vector3(0.04, 0.12, 0.15), steel_mat)
	# Machado de dois gumes pendurado
	_add_box(Vector3(-1.78, 1.25, -0.35), Vector3(0.03, 0.80, 0.04), handle_wood)
	_add_box(Vector3(-1.78, 1.58, -0.35), Vector3(0.04, 0.14, 0.24), steel_mat)
	# Gancho de tora (Cant Hook / Peavey) com haste longa e garra curva de ferro
	_add_box(Vector3(-1.78, 1.20, 0.10), Vector3(0.035, 1.10, 0.035), handle_wood)
	_add_box(Vector3(-1.78, 1.60, 0.15), Vector3(0.03, 0.16, 0.10), iron_mat, Vector3(0, 0, 30))

	# C. REBOLO / PEDRA DE AFIAR (Grindstone Stand) na lateral (+X = 1.95, Z = -1.0)
	# Cavalete de madeira com roda abrasiva de arenito
	var stone_wheel_mat := _mat("grindstone", Color("#8b8682"), 0.90)
	_add_box(Vector3(1.95, 0.35, -1.0), Vector3(0.24, 0.70, 0.40), wood_trim)
	_add_cyl(Vector3(1.95, 0.78, -1.0), 0.22, 0.08, stone_wheel_mat, Vector3(0, 0, 90)) # Disco de pedra
	_add_cyl(Vector3(2.02, 0.78, -1.0), 0.02, 0.12, iron_mat, Vector3(0, 0, 90))        # Manivela de ferro

	# ==============================================================================
	# 7. PILHA LATERAL DE TORAS DESCASCADAS (X = -1.95, Z = -0.60 a 0.60)
	# ==============================================================================
	_add_box(Vector3(-1.95, 0.15, 0.0), Vector3(0.40, 0.12, 1.60), wood_trim) # Calços de base
	for ly in [0.28, 0.46, 0.64]:
		for lz in [-0.55, -0.20, 0.15, 0.50]:
			_add_cyl(Vector3(-1.95, ly, lz), 0.08, 0.95, bark_mat, Vector3(0, 0, 90))
			_add_cyl(Vector3(-1.47, ly, lz), 0.078, 0.015, cut_end, Vector3(0, 0, 90))
			_add_cyl(Vector3(-2.43, ly, lz), 0.078, 0.015, cut_end, Vector3(0, 0, 90))
	# Lona impermeável verde-oliva parcialmente cobrindo as toras
	var tarp_mat := _mat("tarp", Color("#2e4033"), 0.80)
	_add_box(Vector3(-1.95, 0.74, 0.15), Vector3(0.85, 0.04, 0.95), tarp_mat)
	_add_box(Vector3(-1.95, 0.78, 0.15), Vector3(0.80, 0.04, 0.90), snow_mat)

	# 8. OITÃO / EMPENA TRIANGULAR
	for fz in [-1.90, 1.90]:
		_add_box(Vector3(0.0, 2.65, fz), Vector3(2.30, 0.45, 0.12), wood_main)
		_add_box(Vector3(0.0, 3.00, fz), Vector3(1.30, 0.35, 0.12), wood_main)
		_add_box(Vector3(0.0, 3.25, fz), Vector3(0.50, 0.25, 0.12), wood_main)

	# 9. TELHADO RÚSTICO DE TÁBUAS COM CAIBROS E BEIRAIS VOLUMÉTRICOS
	var roof_thick := _mat("roof_wood", Color("#261b12"), 0.90)
	var roof_len: float = 4.45
	var slope_w: float = 2.28

	# Águas do telhado (caimento a 33.5 graus)
	_add_box(Vector3(-0.95, 2.88, 0.0), Vector3(slope_w, 0.10, roof_len), roof_thick, Vector3(0, 0, 33.5))
	_add_box(Vector3(0.95, 2.88, 0.0), Vector3(slope_w, 0.10, roof_len), roof_thick, Vector3(0, 0, -33.5))

	# Cumeeira de tora grossa
	_add_box(Vector3(0.0, 3.52, 0.0), Vector3(0.20, 0.16, roof_len + 0.10), wood_trim)

	# Caibros aparentes sob o beiral
	for bz in [-2.05, 2.05]:
		for rx in [-1.6, -0.8, 0.0, 0.8, 1.6]:
			var ry: float = 3.40 - absf(rx) * 0.65
			_add_box(Vector3(rx, ry - 0.10, bz), Vector3(0.08, 0.10, 0.26), wood_trim)

	# 10. NEVE LOCALIZADA VOLUMÉTRICA NO TELHADO
	_add_box(Vector3(-0.95, 2.96, 0.0), Vector3(slope_w * 0.98, 0.08, roof_len * 0.98), snow_mat, Vector3(0, 0, 33.5))
	_add_box(Vector3(0.95, 2.96, 0.0), Vector3(slope_w * 0.98, 0.08, roof_len * 0.98), snow_mat, Vector3(0, 0, -33.5))
	_add_box(Vector3(0.0, 3.61, 0.0), Vector3(0.32, 0.10, roof_len), snow_mat)

	# Beirais de neve pendentes (snow drifts)
	for sx in [-1.88, 1.88]:
		_add_box(Vector3(sx, 2.22, 0.0), Vector3(0.12, 0.08, roof_len * 0.95), snow_mat)

	# 11. CHAMINÉ DE TUBO DE FOGÃO COM FULIGEM (Y = 3.35, Z = -0.80)
	var soot_mat := _mat("soot", Color("#111113"), 0.5, 0.7)
	_add_cyl(Vector3(-0.75, 3.35, -0.80), 0.10, 1.10, iron_mat)
	_add_cyl(Vector3(-0.75, 3.75, -0.80), 0.105, 0.35, soot_mat) # Fuligem na ponta superior
	_add_box(Vector3(-0.75, 3.02, -0.80), Vector3(0.32, 0.08, 0.32), iron_mat)
	_add_cyl(Vector3(-0.75, 3.92, -0.80), 0.18, 0.06, iron_mat)
	_add_cyl(Vector3(-0.75, 3.96, -0.80), 0.16, 0.04, snow_mat)
