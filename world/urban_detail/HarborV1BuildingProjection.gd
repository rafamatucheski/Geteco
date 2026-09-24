extends RefCounted
class_name HarborV1BuildingProjection

## Compatibility tombstone for an abandoned intermediate migration. Productive
## Harbor must use composed native geometry; a caller cannot silently revive a
## flat atlas projection.
static func attach(building: Node3D, data: Dictionary) -> MeshInstance3D:
	push_error("HarborV1BuildingProjection was removed: %s must remain native 3D" % String(data.get("id",building.name if building!=null else "unknown")))
	return null
