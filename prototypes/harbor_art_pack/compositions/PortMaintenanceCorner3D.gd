class_name PortMaintenanceCorner3D
extends Node3D

## Composição Pronta 3: Canto de Manutenção Naval (Maintenance Corner).
## Footprint Real: 6.00m (largura) x 2.59m (altura) x 7.20m (profundidade).
## Envelope total e colisores dos objetos são rigorosamente separados.
## get_obstacle_bounds() retorna os obstáculos reais de cada objeto transformados
## no espaço local da composição, garantindo circulação livre no contêiner aberto.
## Origem no piso Y=0.

const PortMeshOptimizer = preload("res://prototypes/harbor_art_pack/PortMeshOptimizer.gd")

@export var optimize_batch: bool = true

var _obstacle_bounds: Array[AABB] = []
var _total_envelope: AABB = AABB(Vector3(-3.00, 0.0, -4.25), Vector3(6.00, 2.59, 7.20))
var _is_built: bool = false
var _batch_metrics: Dictionary = {}

func _ready() -> void:
	if not _is_built:
		_build_composition()

## Retorna as dimensões máximas do envelope da composição
func get_dimensions() -> Vector3:
	return Vector3(6.00, 2.59, 7.20)

## Retorna o envelope delimitador total da área ocupada pela composição (não usar para colisão direta)
func get_envelope() -> AABB:
	return _total_envelope

## Retorna o envelope delimitador total (sinônimo de get_envelope)
func get_total_bounds() -> AABB:
	return _total_envelope

## Retorna a lista de AABBs de colisão individual de cada prop posicionado na composição,
## com suas respectivas translações e rotações aplicadas.
func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_composition()
	return _obstacle_bounds.duplicate()

func get_batch_metrics() -> Dictionary:
	return _batch_metrics.duplicate()

func _build_composition() -> void:
	_is_built = true
	_obstacle_bounds.clear()

	# 1. Contêiner de 20 pés aberto no fundo (-Z com portas viradas para frente +Z)
	var open_cont := PortContainerOpen3D.new()
	open_cont.color_theme = 1 # Rust Red
	open_cont.position = Vector3(0.0, 0.0, -1.20)
	_add_prop_and_register_obstacles(open_cont)

	# 2. Carga dentro do contêiner aberta encostada na parede esquerda do fundo
	# Mantém o corredor central (X >= 0.0) 100% desimpedido até o fundo
	var inner_crate := PortCargoCrate3D.new()
	inner_crate.position = Vector3(-0.55, 0.08, -3.40)
	_add_prop_and_register_obstacles(inner_crate)

	# Caixa plástica na quina direita do fundo
	var inner_tote := PortPlasticTote3D.new()
	inner_tote.tote_color = 0
	inner_tote.position = Vector3(0.70, 0.08, -3.50)
	_add_prop_and_register_obstacles(inner_tote)

	# 3. Carrinho manual de 2 rodas estacionado na lateral da entrada (-X)
	var hand_truck := PortHandTruck3D.new()
	hand_truck.position = Vector3(-1.80, 0.0, 1.80)
	hand_truck.rotation_degrees.y = 40.0
	_add_prop_and_register_obstacles(hand_truck)

	# 4. Tambor com vazamento de óleo e tambor de lubrificante na lateral direita (+X)
	var rust_drum := PortRustyDrum3D.new()
	rust_drum.position = Vector3(2.30, 0.0, 1.40)
	_add_prop_and_register_obstacles(rust_drum)

	var clean_drum := PortOilDrum3D.new()
	clean_drum.drum_color = 0 # Blue
	clean_drum.position = Vector3(2.60, 0.0, 0.70)
	_add_prop_and_register_obstacles(clean_drum)

	# 5. Pallet com defensa marinha deslocado para a lateral direita externa
	# Deixa a rampa de acesso e o vão frontal (X de -1.10 a +1.10) 100% livres
	var weath_pallet := PortWeatheredPallet3D.new()
	weath_pallet.position = Vector3(1.70, 0.0, 2.70)
	weath_pallet.rotation_degrees.y = 15.0
	_add_prop_and_register_obstacles(weath_pallet)

	var fender := PortPierFender3D.new()
	fender.position = Vector3(1.70, 0.144, 2.70)
	fender.rotation_degrees.y = 15.0
	_add_prop_and_register_obstacles(fender)

	# 6. Cabeço de amarração e boia de inspeção na quina esquerda do cais
	var bollard := PortMooringBollard3D.new()
	bollard.position = Vector3(-2.60, 0.0, 2.30)
	_add_prop_and_register_obstacles(bollard)

	var buoy := PortLifebuoyStand3D.new()
	buoy.position = Vector3(-2.80, 0.0, 0.50)
	buoy.rotation_degrees.y = 80.0
	_add_prop_and_register_obstacles(buoy)

	# 7. Otimização de nós estáticos agrupando malhas por material
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
