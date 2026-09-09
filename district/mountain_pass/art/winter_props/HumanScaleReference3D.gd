class_name HumanScaleReference3D
extends Node3D

## Referência Métrica Humana de 1,80 m:
## Manequim anatômico em escala 1:1 (metros) para validação visual imediata
## de portas, janelas, bancadas e bancos dos modelos 3D de montanha.

@export var main_color: Color = Color("#2c3e50"): set = set_main_color
@export var jacket_color: Color = Color("#d35400")

const TOTAL_HEIGHT: float = 1.80

var _materials: Dictionary = {}

func _init(p_main_color: Color = Color("#2c3e50"), p_jacket_color: Color = Color("#d35400")) -> void:
	main_color = p_main_color
	jacket_color = p_jacket_color

func _ready() -> void:
	_build_model()

func set_main_color(new_color: Color) -> void:
	main_color = new_color
	if is_inside_tree() and _materials.has("pants"):
		_materials["pants"].albedo_color = main_color

func _mat(id: String, color: Color, roughness: float = 0.8) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	_materials[id] = m
	return m

func _add_box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _add_cyl(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _build_model() -> void:
	# 1. Botas de inverno (Y = 0.0 a 0.12)
	var boot_mat := _mat("boots", Color("#1b1b1b"), 0.9)
	_add_box(Vector3(-0.12, 0.06, 0.03), Vector3(0.12, 0.12, 0.26), boot_mat)
	_add_box(Vector3(0.12, 0.06, 0.03), Vector3(0.12, 0.12, 0.26), boot_mat)

	# 2. Pernas / Calça de montanha (Y = 0.12 a 0.90)
	var pants_mat := _mat("pants", main_color, 0.75)
	_add_cyl(Vector3(-0.12, 0.51, 0.0), 0.07, 0.78, pants_mat)
	_add_cyl(Vector3(0.12, 0.51, 0.0), 0.07, 0.78, pants_mat)

	# 3. Tronco com Parka Térmica (Y = 0.90 a 1.50)
	var jacket_mat := _mat("jacket", jacket_color, 0.7)
	_add_box(Vector3(0.0, 1.20, 0.0), Vector3(0.46, 0.60, 0.28), jacket_mat)

	# Cinto utilitário
	var belt_mat := _mat("belt", Color("#111111"), 0.8)
	_add_box(Vector3(0.0, 0.92, 0.0), Vector3(0.48, 0.08, 0.30), belt_mat)

	# 4. Braços e Luvas
	var arm_mat := jacket_mat
	var glove_mat := _mat("gloves", Color("#1b1b1b"), 0.8)
	for side in [-1.0, 1.0]:
		var x: float = side * 0.28
		_add_cyl(Vector3(x, 1.18, 0.0), 0.06, 0.50, arm_mat)
		_add_box(Vector3(x, 0.90, 0.02), Vector3(0.10, 0.12, 0.10), glove_mat)

	# 5. Pescoço e Cabeça (Y = 1.50 a 1.80)
	var skin_mat := _mat("skin", Color("#d29e74"), 0.6)
	_add_cyl(Vector3(0.0, 1.52, 0.0), 0.06, 0.08, skin_mat)
	_add_box(Vector3(0.0, 1.63, 0.0), Vector3(0.18, 0.18, 0.18), skin_mat)

	# Gorro Ushanka / Touca de Inverno (Topo em 1,80 m exato)
	var hat_mat := _mat("hat", Color("#2c2c2c"), 0.85)
	_add_box(Vector3(0.0, 1.74, 0.0), Vector3(0.21, 0.12, 0.21), hat_mat)
	# Abas do gorro
	_add_box(Vector3(-0.10, 1.66, 0.0), Vector3(0.04, 0.12, 0.16), hat_mat)
	_add_box(Vector3(0.10, 1.66, 0.0), Vector3(0.04, 0.12, 0.16), hat_mat)

	# Régua / Marcação de 1,80m (haste sutil na lateral para verificação visual)
	var ruler_mat := _mat("ruler", Color(1.0, 0.9, 0.2), 0.5)
	_add_cyl(Vector3(0.35, 0.90, 0.0), 0.008, 1.80, ruler_mat)
	_add_box(Vector3(0.35, 1.80, 0.0), Vector3(0.06, 0.015, 0.06), ruler_mat)
