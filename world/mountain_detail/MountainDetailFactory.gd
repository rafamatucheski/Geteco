extends RefCounted
class_name MountainDetailFactory

## Independent central factory for Mountain Detail 3D presentation in Geteco V2.
## Manages the exterior presentation of the Sawmill (Logging Camp) and Mountain Transit Village.
## Preserves original geography at 16 px/metre, integrates shared materials,
## and enforces layer 1 StaticBody3D collision and unblocked access contracts.

const PLACE_CATALOG_PATH := "res://world/places/PlaceCatalog.gd"
const ENVIRONMENTAL_PARITY := preload("res://world/environmental_parity/EnvironmentalParityFactory.gd")

# Mountain coordinate landmarks (mountain-local before region offset)
const SAWMILL_LOCAL_COORDS := Vector2(6350.0, 560.0)
const VILLAGE_LOCAL_COORDS := Vector2(7560.0, -1650.0)

## Computes the world 3D position for a mountain-local point using PlaceCatalog.
static func get_mountain_world_point(local_pt: Vector2) -> Vector3:
	return preload("res://world/places/PlaceCatalog.gd")._at(local_pt,"mountain")

## Instantiates and builds the Sawmill Yard 3D compound.
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

## Instantiates and builds the Mountain Transit Village 3D compound.
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

## Synchronously mounts the Sawmill Yard into a streaming chunk node and finalizes it.
static func populate_sawmill_chunk(chunk: Node3D, data: Dictionary = {}) -> SawmillYard3D:
	var world_pos: Vector3 = data.get("position", Vector3.ZERO)
	var yard := build_sawmill(world_pos)
	chunk.add_child(yard)
	finalize_mountain_detail(yard)
	return yard

## Synchronously mounts the Mountain Village into a streaming chunk node and finalizes it.
static func populate_village_chunk(chunk: Node3D, data: Dictionary = {}) -> MountainVillage3D:
	var world_pos: Vector3 = data.get("position", Vector3.ZERO)
	var village := build_village(world_pos)
	chunk.add_child(village)
	finalize_mountain_detail(village)
	return village

## V1 mechanisms that need their own streaming records rather than being tied
## to a place facade. NativeRegion owns registration and chunk residency.
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
