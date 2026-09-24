extends RefCounted
## V2 surface identity derived from the active room, authored roads and real floor hit.
const SCALE := 1.0/16.0
const MOUNTAIN_OFFSET := Vector2(4300,-4960)
const TILE_PLACES := [
	"harbor_bank","harbor_police","harbor_hospital","harbor_fire_station",
	"harbor_clothing","harbor_fuel","harbor_ammunation","mountain_gunshop",
	"mountain_outfitters","mountain_boutique","mountain_village_outfitters",
]
const WOOD_PLACES := [
	"westgate_garden","quayside_house","canal_north","cemetery_keeper",
	"mountain_cabin","mountain_cabin_encosta","mountain_cabin_forest",
	"mountain_cabin_village_1","mountain_cabin_village_2",
	"mountain_cabin_village_3","mountain_cabin_village_4",
	"lumberjack_shelter","ski_lodge",
]
const GARDENS := [
	Rect2(545,770,220,70),Rect2(1440,1740,620,330),
	Rect2(4810,1655,600,150),Rect2(5695,1740,625,340),
	Rect2(4780,-235,650,120),Rect2(5690,-235,650,120),
]
const PAVED := [
	Rect2(650,755,15,85),Rect2(1440,1910,620,65),Rect2(1535,1660,70,475),
	Rect2(1785,1765,205,120),Rect2(4810,1711,600,32),
	Rect2(4780,-155,650,35),Rect2(5070,-350,45,235),
	Rect2(5690,-155,650,35),Rect2(5980,-350,45,235),
]
const CEMETERY_PATHS := [
	Rect2(-14,-350,28,700),Rect2(-25,-490,50,140),
	Rect2(-247,-178,24,33),Rect2(-235,-157,235,24),
]

static func resolve(world: Node, raining: bool) -> String:
	var state = world.session.state
	var place := str(state.place_id)
	if not place.is_empty(): return _interior_surface(place)
	var point: Vector3 = world.player.global_position
	var collider_name := _floor_collider_name(world,point)
	var surface := _collider_surface(collider_name)
	if surface.is_empty(): surface = _road_surface(world.production.region,point)
	if surface.is_empty(): surface = _geographic_surface(str(state.region_id),point)
	if raining and state.region_id == "harbor":
		if surface in ["concrete","asphalt","gravel"]: surface = "wet" if surface=="concrete" else surface+"_wet"
		elif surface in ["grass","dirt","metal"]: surface += "_wet"
	return surface

static func _interior_surface(place: String) -> String:
	if place in TILE_PLACES: return "tile"
	if place in WOOD_PLACES: return "wood"
	if place in ["maciota","port_boss_garage"]: return "concrete"
	if place == "harbor_sewer" or place in ["mountain_bunker","mountain_mystery_cave"]: return "concrete"
	return "concrete"

static func _floor_collider_name(world: Node, point: Vector3) -> String:
	if world.get_world_3d() == null: return ""
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.45,point-Vector3.UP*.8,1)
	query.exclude = [world.player.get_rid()]
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return ""
	var node := hit.get("collider") as Node
	var labels: Array[String] = []
	for depth in 4:
		if node == null: break
		labels.append(str(node.name))
		node = node.get_parent()
	return "/".join(labels)

static func _collider_surface(label: String) -> String:
	var lower := label.to_lower()
	if "northstardeck" in lower or "northstargangway" in lower or "rail" in lower: return "metal"
	if "road" in lower: return "asphalt"
	if "eastvaleearth" in lower or "sawmill" in lower: return "dirt"
	# Cemetery paths and lawn share one V2 body; geography below disambiguates them.
	if "cemeterysolids" in lower or "originalcemetery" in lower: return ""
	if "mountainterrain" in lower: return ""
	if "originalportsurface" in lower or "land" in lower: return "concrete"
	return ""

static func _road_surface(region: Node, point: Vector3) -> String:
	if region == null: return ""
	var closest := INF
	var result := ""
	for road in region.roads:
		var points: PackedVector3Array = road.points
		for index in range(points.size()-1):
			var nearest := Geometry3D.get_closest_point_to_segment(point,points[index],points[index+1])
			var distance := Vector2(point.x-nearest.x,point.z-nearest.z).length()
			if distance <= float(road.width)*.5+.15 and distance < closest:
				closest = distance
				result = "dirt" if road.get("surface","asphalt")=="earth" else "asphalt"
	return result

static func _geographic_surface(region: String, point: Vector3) -> String:
	var original := Vector2(point.x,point.z)/SCALE
	if region == "mountain":
		original -= MOUNTAIN_OFFSET
		return "snow" if original.y < -1200 else "grass"
	# Exact V1 cemetery bed and paths, now expressed in native V2 metres.
	var cemetery_local := original-Vector2(-650,1740)
	if Rect2(-390,-350,780,700).has_point(cemetery_local):
		for path in CEMETERY_PATHS:
			if path.has_point(cemetery_local): return "dirt"
		return "grass"
	for path in PAVED:
		if path.has_point(original): return "concrete"
	for garden in GARDENS:
		if garden.has_point(original): return "grass"
	return "concrete"
