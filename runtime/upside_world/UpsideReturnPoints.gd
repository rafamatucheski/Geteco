extends RefCounted
## Existing accessible Harbor pavement approaches, never procedural random X/Z.
## These are candidates only: the live session must stream, sweep and check support.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const IDS := ["harbor_curitiba_cellar","harbor_hospital","harbor_clothing","harbor_fuel","harbor_bank","harbor_fire_station"]

static func candidates() -> Array[Vector3]:
	var result: Array[Vector3]=[]
	for id in IDS:
		var definition: Dictionary=PLACES.get_definition(id)
		if definition.is_empty() or definition.get("region")!="harbor": continue
		var at: Vector3=definition.return_position
		result.append(at+Vector3.UP*.08)
		for offset: Vector3 in definition.get("return_clearance_offsets",[]):
			result.append(at+offset+Vector3.UP*.08)
	return result
