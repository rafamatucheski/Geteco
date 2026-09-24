extends RefCounted
class_name EnvironmentalParityFactory

const SCALE := 1.0 / 16.0
const CHAIRLIFT_CENTER := Vector2(7465.0, -3952.5)

static func attach_sawmill(yard: Node3D) -> Node3D:
	if yard == null:
		return null
	var existing := yard.get_node_or_null("SawmillWorkTruck3D") as Node3D
	if existing != null and not existing.is_queued_for_deletion():
		return existing
	var truck := preload("res://world/environmental_parity/StaticSawmillWorkTruck3D.gd").new()
	truck.name = "SawmillWorkTruck3D"
	# V1 MountainSceneryBuilder: position=(120,30), rotation=-0.25.
	truck.position = Vector3(120.0 * SCALE, 0.035, 30.0 * SCALE)
	truck.rotation.y = -0.25
	yard.add_child(truck)
	return truck

static func mountain_records() -> Array[Dictionary]:
	var point: Vector3 = preload("res://world/places/PlaceCatalog.gd")._at(CHAIRLIFT_CENTER, "mountain")
	return [{
		"kind": "environmental_parity",
		"id": "mountain_chairlift",
		"position": point,
		"source_id": "world/mountain_pass/MountainSkiArea.gd:_build_lift",
	}]

static func populate_mountain_chunk(chunk: Node3D, data: Dictionary) -> Node3D:
	if chunk == null or str(data.get("id", "")) != "mountain_chairlift":
		return null
	var lift := preload("res://world/environmental_parity/MountainChairliftParity3D.gd").new()
	lift.name = "MountainChairliftParity3D"
	lift.position = data.get("position", Vector3.ZERO)
	chunk.add_child(lift)
	return lift
