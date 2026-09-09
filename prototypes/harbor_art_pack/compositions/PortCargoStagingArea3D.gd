class_name PortCargoStagingArea3D
extends Node3D

## Composição Pronta 1: Área de Carga e Estivação (Cargo Staging Area).
## Footprint Real: 15.22m (largura) x 5.48m (altura) x 9.70m (profundidade).
## Envelope total e colisores dos objetos são rigorosamente separados.
## get_obstacle_bounds() retorna os obstáculos reais de cada objeto transformados no espaço local.
## Origem no piso Y=0.

const PortMeshOptimizer = preload("res://prototypes/harbor_art_pack/PortMeshOptimizer.gd")

@export var optimize_batch: bool = true

var _obstacle_bounds: Array[AABB] = []
var _total_envelope: AABB = AABB(Vector3(-7.50, 0.0, -5.02), Vector3(15.22, 5.48, 9.70))
var _is_built: bool = false
var _batch_metrics: Dictionary = {}

func _ready() -> void:
	if not _is_built:
		_build_composition()

func get_dimensions() -> Vector3:
	return Vector3(15.22, 5.48, 9.70)

func get_envelope() -> AABB:
	return _total_envelope

func get_total_bounds() -> AABB:
	return _total_envelope

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_composition()
	return _obstacle_bounds.duplicate()

func get_batch_metrics() -> Dictionary:
	return _batch_metrics.duplicate()

func _build_composition() -> void:
	_is_built = true
	_obstacle_bounds.clear()

	# 1. Parede de Contêineres de Fundo (Nível 1 e Nível 2 empilhados)
	var c40_base := PortContainer40ft3D.new()
	c40_base.color_theme = 0 # Blue
	c40_base.position = Vector3(0.0, 0.0, -3.80)
	c40_base.rotation_degrees.y = 90.0
	_add_prop_and_register_obstacles(c40_base)

	var c20_top_left := PortContainer20ft3D.new()
	c20_top_left.color_theme = 1 # Rust
	c20_top_left.position = Vector3(-3.05, 2.89, -3.80)
	c20_top_left.rotation_degrees.y = 90.0
	_add_prop_and_register_obstacles(c20_top_left)

	var c20_top_right := PortContainer20ft3D.new()
	c20_top_right.color_theme = 2 # Teal
	c20_top_right.position = Vector3(3.05, 2.89, -3.80)
	c20_top_right.rotation_degrees.y = 90.0
	_add_prop_and_register_obstacles(c20_top_right)

	# 2. Contêiner Frigorífico lateral (+X) formando barreira em 'L'
	var reefer := PortReeferContainer3D.new()
	reefer.position = Vector3(6.50, 0.0, 0.20)
	reefer.rotation_degrees.y = 0.0
	_add_prop_and_register_obstacles(reefer)

	# 3. Torre de Iluminação de 4,5m no canto de observação
	var tower := PortFloodlightTower3D.new()
	tower.position = Vector3(-6.80, 0.0, -3.80)
	tower.rotation_degrees.y = 45.0
	_add_prop_and_register_obstacles(tower)

	# 4. Bordo do Cais (+Z): Cabeço de amarração e defensas de proteção
	var bollard := PortMooringBollard3D.new()
	bollard.position = Vector3(3.50, 0.0, 4.20)
	_add_prop_and_register_obstacles(bollard)

	var fender1 := PortPierFender3D.new()
	fender1.position = Vector3(-1.0, 0.0, 4.40)
	_add_prop_and_register_obstacles(fender1)

	var buoy := PortLifebuoyStand3D.new()
	buoy.position = Vector3(5.50, 0.0, 4.00)
	buoy.rotation_degrees.y = -90.0
	_add_prop_and_register_obstacles(buoy)

	# 5. Empilhadeira em operação no pátio central
	var forklift := PortForklift3D.new()
	forklift.position = Vector3(-1.20, 0.0, 0.20)
	forklift.rotation_degrees.y = -20.0
	_add_prop_and_register_obstacles(forklift)

	# 6. Carga pronta na frente da empilhadeira (Pallet com caixa pesada)
	var pallet_load := PortWoodenPallet3D.new()
	pallet_load.position = Vector3(-1.70, 0.0, 2.20)
	pallet_load.rotation_degrees.y = -20.0
	_add_prop_and_register_obstacles(pallet_load)

	var crate := PortCargoCrate3D.new()
	crate.position = Vector3(-1.70, 0.144, 2.20)
	crate.rotation_degrees.y = -20.0
	_add_prop_and_register_obstacles(crate)

	# 7. Cluster de tambores cintados próximo ao cais
	var drum_cluster := PortDrumClusterPallet3D.new()
	drum_cluster.position = Vector3(1.80, 0.0, 1.80)
	drum_cluster.rotation_degrees.y = 15.0
	_add_prop_and_register_obstacles(drum_cluster)

	# 8. Cavalete de advertência limitando a zona de manobra
	var sign := PortHazardSign3D.new()
	sign.position = Vector3(-4.50, 0.0, 2.50)
	sign.rotation_degrees.y = 45.0
	_add_prop_and_register_obstacles(sign)

	# 9. Otimização de nós estáticos agrupando malhas por material
	if optimize_batch:
		_batch_metrics = PortMeshOptimizer.optimize_hierarchy(self)

func _add_prop_and_register_obstacles(prop: Node3D) -> void:
	add_child(prop)
	var xform := prop.transform
	for aabb in prop.get_obstacle_bounds():
		var transformed := _transform_aabb(xform, aabb)
		_obstacle_bounds.append(transformed)

static func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var corners: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size
	]
	var min_pt: Vector3 = xform * corners[0]
	var max_pt: Vector3 = min_pt
	for i in range(1, 8):
		var p: Vector3 = xform * corners[i]
		min_pt = min_pt.min(p)
		max_pt = max_pt.max(p)
	return AABB(min_pt, max_pt - min_pt)
