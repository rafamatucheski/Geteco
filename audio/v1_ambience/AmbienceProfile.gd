extends RefCounted
## V1 soundscape zones converted from source pixels to V2 native metres.
const SCALE := 1.0/16.0
const SOUTH_PORT := Rect2(3200,3200,2900,2800)
const SALVAGE := Vector2(-750,550)
const NATURAL_AREAS := [
	Rect2(545,770,220,70),Rect2(1440,1740,620,330),
	Rect2(4810,1655,600,150),Rect2(5695,1740,625,340),
	Rect2(4780,-235,650,120),Rect2(5690,-235,650,120),Rect2(10,500,225,1670),
]
const HARBOR_SHORE_SEGMENTS := [
	[Vector2(3200,3500),Vector2(3200,6000)],[Vector2(3200,6000),Vector2(6100,6000)],
	[Vector2(6100,6000),Vector2(6100,3200)],[Vector2(6100,3200),Vector2(3600,3200)],
	[Vector2(-100,2480),Vector2(2853,2480)],[Vector2(2853,2480),Vector2(3200,3500)],
	[Vector2(4380,-2400),Vector2(4380,2600)],[Vector2(4380,2600),Vector2(6760,2600)],
	[Vector2(6760,2600),Vector2(6760,-2400)],
]

static func targets(region: String, place: String, point: Vector3, dark: bool, crowd: float) -> Dictionary:
	var result := {"city":0.0,"water":0.0,"port":0.0,"birds":0.0,"crickets":0.0,"workshop":0.0}
	if not place.is_empty():
		if place in ["maciota","port_boss_garage"]: result.workshop = 1.0
		elif place == "harbor_sewer": result.water = .62
		return result
	var original := Vector2(point.x,point.z)/SCALE
	if region == "mountain":
		original -= Vector2(4300,-4960)
		var forest := 1.0 if original.y > -1500 else .45
		result.birds = forest*.42 if not dark else 0.0
		result.crickets = forest*.22 if dark else 0.0
		return result
	var port := _rect_weight(original,SOUTH_PORT,350.0)
	var coast := _harbor_coast_weight(original)
	var nature := _harbor_nature_weight(original)
	result.port = port*.72
	result.water = maxf(coast*.75,port*.22)
	result.city = (.24 if dark else .42)*crowd*(1.0-port)
	result.birds = nature*.5 if not dark else 0.0
	result.crickets = nature*.22 if dark else 0.0
	return result

static func activity_context(region: String, place: String, point: Vector3) -> String:
	if place in ["maciota","port_boss_garage"]: return "workshop"
	if not place.is_empty(): return ""
	var source := Vector2(point.x,point.z)/SCALE
	if region == "mountain":
		source -= Vector2(4300,-4960)
		return "sawmill" if source.distance_to(Vector2(6350,560))<700 else ""
	if source.distance_to(SALVAGE)<900: return "salvage"
	if source.distance_to(Vector2(3570,1620))<1150: return "dock"
	if _rect_weight(source,SOUTH_PORT,350)>0.2: return "port"
	if _harbor_nature_weight(source)>.12: return "nature"
	return "city"

static func _rect_weight(point: Vector2, rect: Rect2, reach: float) -> float:
	var nearest := point.clamp(rect.position,rect.end)
	return 1.0-smoothstep(0.0,reach,point.distance_to(nearest))

static func _harbor_nature_weight(point: Vector2) -> float:
	var result := _rect_weight(point,Rect2(-1040,1390,780,700),180.0)
	for area in NATURAL_AREAS:
		result = maxf(result,_rect_weight(point,area,65.0))
	return result

static func _harbor_coast_weight(point: Vector2) -> float:
	var distance := INF
	for segment in HARBOR_SHORE_SEGMENTS:
		distance = minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,segment[0],segment[1])))
	return 1.0-smoothstep(60.0,480.0,distance)
