extends RefCounted
## All positions are MountainPass-local V1 pixels, not projected interior coordinates.
const OFFSET := Vector2(4300,-4960)
const RADIUS := 220.0/16.0 # Actual controller radius; ignores larger/smaller Area2D art radii.
const SOURCES := [
	{"id":"logging_camp","point":Vector2(6440,580),"source":"MountainPass.gd:LoggingCamp/CampfireHeatSource"},
	{"id":"summit_camp","point":Vector2(6370,-2780),"source":"MountainPass.gd:AltitudeOutpostBunker/SummitCampfire"},
	{"id":"smuggler_camp","point":Vector2(5655,-990),"source":"MountainSceneryBuilder.gd:SecretMountainLake/SmugglerCampsite/fire_pit"},
	{"id":"outfitters_heater","point":Vector2(5980,715),"source":"MountainExpedition.gd:shop_position+(0,65)"},
	{"id":"patrol_shelter","point":Vector2(6610,-1250),"source":"MountainSettlement.gd:PatrolShelter3D"},
	{"id":"transit_village","point":Vector2(7650,-1553),"source":"MountainTransitVillageLayout.gd:HEAT_SOURCE"},
	{"id":"resort_brazier","point":Vector2(7310,-2700),"source":"ResortPromenade.gd:_build_fire_brazier"},
]
static func to_world(point: Vector2) -> Vector3:
	point = (point+OFFSET)/16.0
	return Vector3(point.x,0,point.y)
static func nearest(point: Vector3) -> Dictionary:
	# Seven immutable positions: no scene-tree traversal or resources per frame.
	var best := RADIUS*RADIUS
	var found: Dictionary = {}
	for source in SOURCES:
		var at := to_world(source.point)
		var distance := Vector2(at.x-point.x,at.z-point.z).length_squared()
		if distance < best and absf(point.y-at.y)<2.5:
			best = distance
			found = source
	return found
static func sheltered(point: Vector3) -> bool:
	if point.y < -.5 or point.y > 3: return false
	var original := Vector2(point.x,point.z)*16.0-OFFSET
	# MountainPass configures the original tunnel to850x150.
	if Rect2(4950,325,850,150).has_point(original): return true
	# Original aircraft interior floor bounds, already authored in metres.
	var plane := to_world(Vector2(5450,-1150))
	return Rect2(-1.37,-13,2.74,22.4).has_point(Vector2(point.x-plane.x,point.z-plane.z))
