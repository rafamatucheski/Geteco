extends RefCounted
## Floor-specific views keep nearby exterior structures out of the living space.
## Offsets are in the building's local orientation; the runtime applies its yaw.
const FLOOR_OFFSETS := {
	"ColdStorage": {0:Vector3(8,21,12)},
	"NorthFrontage5": {1:Vector3(0,22,11)},
	"FoundryTerraceEast": {0:Vector3(-7,22,11)},
	"FoundryTerraceWest": {0:Vector3(5,21,12)},
}

static func offset(definition: Dictionary, index: int) -> Vector3:
	var floors: Dictionary = FLOOR_OFFSETS.get(str(definition.get("source_id","")),{})
	if floors.has(index): return floors[index]
	if index == 0: return definition.get("ground_camera_offset",Vector3(0,18,15))
	return Vector3(0,18,15)
