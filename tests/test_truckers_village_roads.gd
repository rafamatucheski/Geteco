extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var loaded := DATA.read_document()
	check(loaded.error.is_empty(),"Saved map remains valid")
	var region := preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var roads: Dictionary = {}
	for road in region.roads: roads[road.id] = road
	for id in ["vertice_rural_access","new/tonico_asphalt_entry","new/tonico_earth_lane"]:
		check(roads.has(id),"Authored road participates in runtime: "+id)
	if failures.size()>0: region.free(); quit(1); return
	var entry: Dictionary = roads["new/tonico_asphalt_entry"]
	var earth: Dictionary = roads["new/tonico_earth_lane"]
	check(entry.surface=="asphalt" and earth.surface=="earth","Road materials stay distinct")
	check(entry.points[0].is_equal_approx(Vector3(-290,0,10)),"Entry reaches road centerline through shared joins")
	check(entry.points[-1].is_equal_approx(earth.points[0]),"Continuous asphalt-to-earth link")
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(region.roads)
	var main_link := false
	var earth_link := false
	for key in graph.edges:
		var ids := []
		for edge in graph.edges[key]: ids.append(edge.id)
		if "vertice_rural_access" in ids and entry.id in ids: main_link=true
		if entry.id in ids and earth.id in ids: earth_link=true
	check(main_link and earth_link,"Route graph connects highway, apron and dirt lane")
	check(earth.points[-1].is_equal_approx(Vector3(-286,0,55)),"Vehicle lane stops at the outside parking area")
	check(roads.has("new/tonico_footpath"),"A separate narrow path continues on foot")
	var has_internal_traffic := false
	for segment in graph.segments:
		if segment.id=="new/tonico_footpath": has_internal_traffic=true
	check(not has_internal_traffic,"Traffic never routes through the pedestrian village")
	var geometry = region.harbor_road_geometry
	check(not geometry._earth_polygons.is_empty(),"Harbor renders the actual earth road")
	var overlap := false
	for polygon in geometry._earth_polygons:
		for asphalt in geometry._layers[-1].polygons:
			for intersection in Geometry2D.intersect_polygons(polygon,asphalt):
				var area := 0.0
				for i in intersection.size(): area+=intersection[i].cross(intersection[(i+1)%intersection.size()])*.5
				if absf(area)>.005: overlap=true
	check(not overlap,"Dirt never paints over highway/asphalt approach")
	check(earth.points.size()>3,"Approach bends into the village, not a rectangle")
	region.free()
	print("VILLAGE_ROADS checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
