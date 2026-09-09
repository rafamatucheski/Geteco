class_name PortHumanReference3D
extends Node3D

## Referência Humana de 1,80 m - Estivador Portuário
## Manequim com proporções humanas reais (1 unidade = 1 metro)
## Traje de trabalho: botas de segurança, calça resistente, colete de alta visibilidade e capacete.
## Expondo altura total de 1,80 m com régua lateral para verificação métrica imediata.

const HEIGHT: float = 1.80

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_model()

func get_dimensions() -> Vector3:
	return Vector3(0.60, 1.80, 0.40)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-0.25, 0.0, -0.20), Vector3(0.50, 1.80, 0.40)))

	var mat_boot := PortArtMaterials.get_mat("worker_boots", Color("#1f2421"), 0.2, 0.85)
	var mat_pants := PortArtMaterials.get_mat("worker_pants", Color("#2c3e50"), 0.1, 0.80)
	var mat_vest := PortArtMaterials.safety_orange()
	var mat_stripe := PortArtMaterials.reflective_white()
	var mat_helmet := PortArtMaterials.safety_yellow()
	var mat_skin := PortArtMaterials.get_mat("worker_skin", Color("#c68642"), 0.0, 0.70)
	var mat_ruler := PortArtMaterials.get_mat("metric_ruler", Color("#f1c40f"), 0.5, 0.30)

	# 1. Botas com biqueira de aço (Y = 0.0 a 0.14)
	_box(Vector3(-0.13, 0.07, 0.04), Vector3(0.14, 0.14, 0.28), mat_boot)
	_box(Vector3(0.13, 0.07, 0.04), Vector3(0.14, 0.14, 0.28), mat_boot)

	# 2. Pernas / Calça de trabalho reforçada (Y = 0.14 a 0.90)
	_cyl(Vector3(-0.13, 0.52, 0.0), 0.075, 0.76, mat_pants)
	_cyl(Vector3(0.13, 0.52, 0.0), 0.075, 0.76, mat_pants)

	# 3. Tronco e Colete Refletivo (Y = 0.90 a 1.48)
	_box(Vector3(0.0, 1.19, 0.0), Vector3(0.48, 0.58, 0.28), mat_vest)
	# Faixas refletivas horizontais e verticais do colete
	_box(Vector3(0.0, 1.05, 0.0), Vector3(0.49, 0.05, 0.29), mat_stripe)
	_box(Vector3(0.0, 1.25, 0.0), Vector3(0.49, 0.05, 0.29), mat_stripe)
	_box(Vector3(-0.14, 1.35, 0.0), Vector3(0.05, 0.26, 0.29), mat_stripe)
	_box(Vector3(0.14, 1.35, 0.0), Vector3(0.05, 0.26, 0.29), mat_stripe)

	# 4. Braços e Luvas de Couro
	for s in [-1.0, 1.0]:
		var x: float = s * 0.30
		_cyl(Vector3(x, 1.18, 0.0), 0.065, 0.50, mat_pants)
		_box(Vector3(x, 0.88, 0.02), Vector3(0.10, 0.14, 0.10), mat_boot) # luvas pesadas

	# 5. Pescoço e Cabeça (Y = 1.48 a 1.70)
	_cyl(Vector3(0.0, 1.52, 0.0), 0.065, 0.08, mat_skin)
	_box(Vector3(0.0, 1.63, 0.0), Vector3(0.18, 0.18, 0.18), mat_skin)

	# 6. Capacete Industrial (Aba e Domo até Y = 1.80 m exato)
	_box(Vector3(0.0, 1.71, 0.02), Vector3(0.25, 0.03, 0.27), mat_helmet) # aba
	_cyl(Vector3(0.0, 1.75, 0.0), 0.115, 0.10, mat_helmet) # cúpula rígida

	# 7. Régua métrica de validação (haste de 1,80 m com marcas de 0,5m / 1m / 1,5m / 1,8m)
	_cyl(Vector3(0.38, 0.90, 0.0), 0.008, 1.80, mat_ruler)
	for mark_y in [0.50, 1.00, 1.50, 1.80]:
		_box(Vector3(0.38, mark_y, 0.0), Vector3(0.05, 0.015, 0.02), mat_stripe)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _cyl(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
