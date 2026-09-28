extends SceneTree
const GEOMETRY := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const TRAFFIC := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func road(id: String,points: Array) -> Dictionary:
	return {"id":id,"points":PackedVector3Array(points),"width":8.0}
func run() -> void:
	var roads: Array[Dictionary] = [road("main",[Vector3(-40,0,0),Vector3(40,0,0)]),road("branch",[Vector3(0,0,-40),Vector3.ZERO])]
	var geometry := GEOMETRY.new()
	geometry.configure(roads,false)
	check(geometry.crossing_layout.size()==1,"T is one selectable junction")
	var junction: Dictionary = geometry.crossing_layout[0]
	check(junction.entries.size()==3,"T has exactly three independently editable entries")
	var branch := {}
	for entry in junction.entries:
		if entry.road_id=="branch": branch=entry
	check(branch.enabled and branch.fits,"Long straight approach receives crossing")
	var original_position: Vector2 = branch.position
	var stable_key: String = branch.key
	roads[1].crossing_entries = {stable_key:{"mode":"off","offset":3.0,"depth":2.0}}
	geometry.configure(roads,false)
	var edited := {}
	var other_count := 0
	for entry in geometry.crossing_layout[0].entries:
		if entry.road_id=="branch": edited=entry
		elif entry.enabled: other_count += 1
	check(not edited.enabled and other_count==2,"Disabling one zebra preserves other two")
	check(edited.position.is_equal_approx(original_position+Vector2(0,-3)),"Offset moves selected approach only")
	check(edited.stop_line,"Removing zebra does not remove independent stop line")
	check(edited.stop_position.is_equal_approx(edited.position+Vector2(0,-2)),"Retention line follows crossing depth and offset")
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(roads)
	TRAFFIC.configure(graph,geometry.crossing_layout)
	var route := Curve3D.new()
	route.add_point(Vector3(-2,0,-35))
	route.add_point(Vector3(-2,0,0))
	route.add_point(Vector3(-35,0,2))
	var along := TRAFFIC.along(route)
	check(not along.is_empty() and along[0].has("stop_offset"),"Real traffic graph gets approach-specific route stop")
	if not along.is_empty() and along[0].has("stop_offset"):
		var point := route.sample_baked(along[0].stop_offset,true)
		check(absf(point.z-edited.stop_position.y)<.15,"Vehicle route stop lies at visible retention line")
	TRAFFIC.configure(graph)
	check(not TRAFFIC.along(route)[0].has("stop_offset"),"Reconfiguration clears previous-world approach targets")
	var row := {"id":"road/branch","type":"road","points":[[0,-40],[0,0]],"width":8,"crossing_entries":roads[1].crossing_entries}
	var doc := DATA.empty_document()
	doc.regions.harbor[row.id]=row
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(doc))
	check(DATA.validate_document(decoded).is_empty(),"Overrides survive validated JSON round trip")
	row.crossing_entries[stable_key].offset = NAN
	check(not DATA.validate_entity(row).is_empty(),"Non-finite offset rejected")
	row.crossing_entries[stable_key].offset = 3.0
	for r in roads:
		for i in r.points.size(): r.points[i] += Vector3(15,0,30)
	geometry.configure(roads,false)
	var moved := {}
	for entry in geometry.crossing_layout[0].entries:
		if entry.road_id=="branch": moved=entry
	check(moved.key==stable_key and not moved.enabled,"Moving junction preserves approach identity and settings")
	roads[1].crossing_entries[stable_key].stop = false
	roads[1].points.insert(1,Vector3(15,0,28))
	geometry.configure(roads,false)
	for entry in geometry.crossing_layout[0].entries:
		if entry.road_id=="branch":
			check(entry.fits and is_equal_approx(entry.offset,3.0),"Extra collinear control point does not shorten crossing corridor")
			check(not entry.stop_line and entry.stop_position==moved.stop_position,"Hiding paint preserves traffic stop target")
	var bend: Array[Dictionary] = [road("a",[Vector3(-30,0,0),Vector3.ZERO]),road("b",[Vector3.ZERO,Vector3(0,0,30)])]
	geometry.configure(bend,false)
	check(geometry.crossing_layout.is_empty() and geometry._crosswalk_white.is_empty(),"Two-arm bend never becomes a zebra intersection")
	var bent: Array[Dictionary] = [road("main",[Vector3(-30,0,0),Vector3.ZERO,Vector3(0,0,30)]),road("branch",[Vector3.ZERO,Vector3(30,0,0)])]
	geometry.configure(bent,false)
	var directions := []
	for entry in geometry.crossing_layout[0].entries: directions.append(entry.direction)
	check(directions.size()==3 and directions.has(Vector2.DOWN) and directions.has(Vector2.LEFT) and directions.has(Vector2.RIGHT),"Internal bend uses actual outgoing segments")
	var close: Array[Dictionary] = [road("main",[Vector3(-40,0,0),Vector3(40,0,0)]),road("a",[Vector3(0,0,-30),Vector3.ZERO]),road("b",[Vector3(9,0,0),Vector3(9,0,30)])]
	geometry.configure(close,false)
	var suppressed := 0
	for j in geometry.crossing_layout:
		for entry in j.entries:
			if not entry.fits: suppressed+=1; check(not entry.enabled,"Short inter-junction approach is suppressed")
	check(suppressed>=2,"Nearby junctions reserve space for both approaches")
	var wide: Array[Dictionary] = [road("main",[Vector3(-80,0,0),Vector3(80,0,0)]),road("branch",[Vector3(0,0,-80),Vector3.ZERO])]
	for r in wide: r.width=30.0
	wide[1].crossing_entries={stable_key:{"mode":"on","offset":10.0,"depth":5.0}}
	geometry.configure(wide,false)
	graph.configure(wide)
	TRAFFIC.configure(graph,geometry.crossing_layout)
	var wide_route := Curve3D.new()
	wide_route.add_point(Vector3(-7.5,0,-65))
	wide_route.add_point(Vector3(-7.5,0,0))
	wide_route.add_point(Vector3(-60,0,7.5))
	var wide_along := TRAFFIC.along(wide_route)
	check(not wide_along.is_empty() and wide_along[0].has("stop_offset"),"Wide street lane farther than 4 m still obeys junction")
	if not wide_along.is_empty() and wide_along[0].has("stop_offset"):
		check(wide_along[0].offset-wide_along[0].stop_offset>30,"Maximum legal crossing offset stays synchronized")
		check(wide_along[0].approach_distance>40,"Vehicle begins braking before distant stop line")
	print("JUNCTION_ENTRIES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
