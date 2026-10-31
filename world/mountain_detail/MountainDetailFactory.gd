extends RefCounted
class_name MountainDetailFactory

## Fábrica central independente da apresentação 3D do Mountain Detail na Geteco V2.
## Gerencia a apresentação externa da Serraria (acampamento madeireiro) e do Mountain Transit Village.
## Preserva a geografia original em 16 px/metro, integra materiais compartilhados
## e impõe colisão StaticBody3D na camada 1 e os contratos de acesso desbloqueado.

const PLACE_CATALOG_PATH := "res://world/places/PlaceCatalog.gd"
const ENVIRONMENTAL_PARITY := preload("res://world/environmental_parity/EnvironmentalParityFactory.gd")

# Mountain coordinate landmarks (mountain-local before region offset)
const SAWMILL_LOCAL_COORDS := Vector2(6350.0, 560.0)
const VILLAGE_LOCAL_COORDS := Vector2(7560.0, -1650.0)

## Calcula a posição 3D no mundo de um ponto local da montanha usando PlaceCatalog.
static func get_mountain_world_point(local_pt: Vector2) -> Vector3:
	return preload("res://world/places/PlaceCatalog.gd")._at(local_pt,"mountain")

## Instancia e monta o complexo 3D do pátio da serraria.
static func build_sawmill(world_pos: Vector3 = Vector3.ZERO) -> SawmillYard3D:
	var yard := SawmillYard3D.new()
	yard.name = "SawmillYard3D"
	if world_pos == Vector3.ZERO:
		world_pos = get_mountain_world_point(SAWMILL_LOCAL_COORDS)
	yard.position = world_pos
	yard.set_meta("_mountain_data", {"kind": "sawmill_yard", "position": world_pos})
	yard.ready.connect(func():
		ENVIRONMENTAL_PARITY.attach_sawmill(yard)
		finalize_mountain_detail(yard)
	)
	return yard

## Instancia e monta o complexo 3D do Mountain Transit Village.
static func build_village(world_pos: Vector3 = Vector3.ZERO) -> MountainVillage3D:
	var village := MountainVillage3D.new()
	village.use_original_sections = true
	village.name = "MountainVillage3D"
	if world_pos == Vector3.ZERO:
		world_pos = get_mountain_world_point(VILLAGE_LOCAL_COORDS)
	village.position = world_pos
	village.set_meta("_mountain_data", {"kind": "mountain_village", "position": world_pos})
	village.ready.connect(func(): finalize_mountain_detail(village))
	return village

## Monta de forma síncrona o pátio da serraria num nó de chunk em streaming e o finaliza.
static func populate_sawmill_chunk(chunk: Node3D, data: Dictionary = {}) -> SawmillYard3D:
	var world_pos: Vector3 = data.get("position", Vector3.ZERO)
	var yard := build_sawmill(world_pos)
	chunk.add_child(yard)
	finalize_mountain_detail(yard)
	return yard

## Monta de forma síncrona o vilarejo da montanha num nó de chunk em streaming e o finaliza.
static func populate_village_chunk(chunk: Node3D, data: Dictionary = {}) -> MountainVillage3D:
	var world_pos: Vector3 = data.get("position", Vector3.ZERO)
	var village := build_village(world_pos)
	chunk.add_child(village)
	finalize_mountain_detail(village)
	return village

## Mecanismos da V1 que precisam de registros de streaming próprios em vez de ficarem presos
## a uma fachada de lugar. O NativeRegion é dono do registro e da residência dos chunks.
static func get_environmental_records() -> Array[Dictionary]:
	return ENVIRONMENTAL_PARITY.mountain_records()

static func populate_environmental_chunk(chunk: Node3D, data: Dictionary) -> Node3D:
	return ENVIRONMENTAL_PARITY.populate_mountain_chunk(chunk, data)

## Post-mount finalization: ensures render layers (layers = 1),
## configures StaticBody3D collision layers/masks, and guarantees unblocked transit.
static func finalize_mountain_detail(root_node: Node3D) -> void:
	if root_node == null:
		return
	if root_node.get_meta("_mountain_finalized", false):
		return
	root_node.set_meta("_mountain_finalized", true)
	
	# Configure all MeshInstance3D rendering layers
	for mesh: MeshInstance3D in root_node.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 1
	
	# Verify and configure all StaticBody3D collision properties
	for body: StaticBody3D in root_node.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 1
		body.collision_mask = 0
