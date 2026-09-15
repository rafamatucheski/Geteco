class_name PortStorageDepot3D
extends Node3D

## Composição Pronta 2: Depósito Portuário / Pátio de Armazenamento (Storage Depot).
## Footprint Real: 8.20m (largura) x 1.20m (altura) x 6.00m (profundidade).
## Envelope total e colisores dos objetos são rigorosamente separados.
## get_obstacle_bounds() retorna os obstáculos reais de cada objeto transformados no espaço local.
## Origem no piso Y=0.

const PortMeshOptimizer = preload("res://prototypes/harbor_art_pack/PortMeshOptimizer.gd")

@export var optimize_batch: bool = true

var _obstacle_bounds: Array[AABB] = []
var obstacle_materials: Array[StringName] = []
var _total_envelope: AABB = AABB(Vector3(-4.10, 0.0, -3.20), Vector3(8.20, 1.20, 6.00))
var _is_built: bool = false
var _batch_metrics: Dictionary = {}

func _ready() -> void:
	if not _is_built:
		_build_composition()

func get_dimensions() -> Vector3:
	return Vector3(8.20, 1.20, 6.00)

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
	obstacle_materials.clear()

	# 1. Pilhas de Pallets no fundo esquerdo
	var stack1 := PortPalletStack3D.new()
	stack1.position = Vector3(-3.40, 0.0, -2.50)
	_add_prop_and_register_obstacles(stack1)

	var stack2 := PortPalletStack3D.new()
	stack2.position = Vector3(-2.00, 0.0, -2.50)
	stack2.rotation_degrees.y = 5.0
	_add_prop_and_register_obstacles(stack2)

	# 2. Caixas longas de maquinário alinhadas no fundo
	var long_crate1 := PortLongCrate3D.new()
	long_crate1.position = Vector3(1.50, 0.0, -2.80)
	_add_prop_and_register_obstacles(long_crate1)

	var long_crate2 := PortLongCrate3D.new()
	long_crate2.position = Vector3(1.50, 0.60, -2.80)
	long_crate2.rotation_degrees.y = -1.0
	_add_prop_and_register_obstacles(long_crate2)

	# 3. Caixas de carga pesada organizadas em bancada
	var crate_a := PortCargoCrate3D.new()
	crate_a.position = Vector3(-3.20, 0.0, -0.60)
	_add_prop_and_register_obstacles(crate_a)

	var crate_b := PortCargoCrate3D.new()
	crate_b.position = Vector3(-1.90, 0.0, -0.60)
	_add_prop_and_register_obstacles(crate_b)

	# Pallet isolado com caixa plástica
	var pal_iso := PortWoodenPallet3D.new()
	pal_iso.position = Vector3(-0.50, 0.0, -0.60)
	_add_prop_and_register_obstacles(pal_iso)

	var tote1 := PortPlasticTote3D.new()
	tote1.tote_color = 0 # Blue
	tote1.position = Vector3(-0.50, 0.144, -0.60)
	_add_prop_and_register_obstacles(tote1)

	# 4. Carrinho plataforma de 4 rodas no corredor central com caixas plásticas
	var cart := PortPlatformCart3D.new()
	cart.position = Vector3(1.80, 0.0, 0.20)
	cart.rotation_degrees.y = 15.0
	_add_prop_and_register_obstacles(cart)

	var tote_cart1 := PortPlasticTote3D.new()
	tote_cart1.tote_color = 1 # Grey
	tote_cart1.position = Vector3(1.60, 0.20, 0.15)
	tote_cart1.rotation_degrees.y = 15.0
	_add_prop_and_register_obstacles(tote_cart1)

	var tote_cart2 := PortPlasticTote3D.new()
	tote_cart2.tote_color = 0 # Blue
	tote_cart2.position = Vector3(2.05, 0.20, 0.27)
	tote_cart2.rotation_degrees.y = 15.0
	_add_prop_and_register_obstacles(tote_cart2)

	# 5. Tambores industriais e tambor oxidado em quarentena
	var drum_clean := PortOilDrum3D.new()
	drum_clean.drum_color = 2 # Yellow
	drum_clean.position = Vector3(3.80, 0.0, -1.80)
	_add_prop_and_register_obstacles(drum_clean)

	var drum_rust := PortRustyDrum3D.new()
	drum_rust.position = Vector3(3.80, 0.0, -0.90)
	_add_prop_and_register_obstacles(drum_rust)

	# 6. Cluster de tambores no canto direito
	var drum_pal := PortDrumClusterPallet3D.new()
	drum_pal.position = Vector3(2.50, 0.0, 2.20)
	drum_pal.rotation_degrees.y = -10.0
	_add_prop_and_register_obstacles(drum_pal)

	# 7. Sinalização de segurança na entrada da área
	var sign := PortHazardSign3D.new()
	sign.position = Vector3(-2.80, 0.0, 2.40)
	sign.rotation_degrees.y = -30.0
	_add_prop_and_register_obstacles(sign)

	# 8. Otimização de nós estáticos agrupando malhas por material
	if optimize_batch:
		_batch_metrics = PortMeshOptimizer.optimize_hierarchy(self)

func _add_prop_and_register_obstacles(prop: Node3D) -> void:
	add_child(prop)
	var xform := prop.transform
	var material: StringName = &"metal"
	if prop is PortPalletStack3D or prop is PortWoodenPallet3D or prop is PortLongCrate3D or prop is PortCargoCrate3D:
		material = &"wood"
	elif prop is PortPlasticTote3D:
		# A dull contact is closer to a plastic tote than a ringing steel hit.
		material = &"wood"
	for aabb in prop.get_obstacle_bounds():
		var transformed := _transform_aabb(xform, aabb)
		_obstacle_bounds.append(transformed)
		obstacle_materials.append(material)

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
