extends SceneTree
const ROADS := preload("res://world/editing/WorldEditRoads.gd")
const REGION := preload("res://world/regions/NativeRegion.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var region := REGION.build_region("mountain")
	region.prepare_data()
	var paths := ROADS.catalog_walkways(region)
	check(paths.size() == region.walkways.size() and paths.size() >= 7,"Every mountain pedestrian route is catalogued")
	var row: Dictionary = paths["path/cave_trail"].duplicate(true)
	check(row.pathway and row.width < 2,"Narrow mountain path remains a pedestrian route")
	var road_count: int = region.roads.size()
	var original_roads: Array = []
	var all_rows := paths.duplicate(true)
	for road in region.roads:
		var points: Array = []
		for point in road.points: points.append([point.x,point.z])
		original_roads.append({"id":road.id,"points":points})
		var id := "road/"+str(road.id)
		all_rows[id] = {"id":id,"type":"road","points":points,"width":road.width,"surface":road.surface}
	for point in row.points:
		point[0] += 4.0
		point[1] += 2.0
	row.width = 1.4
	all_rows[row.id] = row
	for cell in region.records:
		region.records[cell] = region.records[cell].filter(func(record): return record.kind != "road")
	ROADS.rebuild(region,all_rows)
	check(region.roads.size() == road_count,"Editing pedestrian path does not add a traffic street")
	var moved := {}
	for path in region.walkways:
		if path.id == "cave_trail": moved = path
	check(not moved.is_empty() and is_equal_approx(moved.width,1.4),"Edited path width reaches runtime data")
	check(moved.points[0].is_equal_approx(Vector3(row.points[0][0],0,row.points[0][1])),"Edited path points reach runtime data")
	check(moved.surface == "footpath","Runtime retains original footpath renderer")
	var all_preserved := true
	for index in region.roads.size():
		var road: Dictionary = region.roads[index]
		var original: Dictionary = original_roads[index]
		if road.id != original.id or not road.points[0].is_equal_approx(Vector3(original.points[0][0],0,original.points[0][1])): all_preserved = false
	check(all_preserved,"Unedited vehicle road geometry is preserved")
	var segments := 0
	for records in region.records.values():
		for record in records:
			if record.get("road_id","") == "cave_trail":
				segments += 1
				check(record.surface == "footpath" and is_equal_approx(record.width,1.4),"Streamed path segment uses edited pedestrian geometry")
	check(segments > 0,"Moved pedestrian path has streaming geometry")
	check(region.route_geometry.contains(moved.points[0].lerp(moved.points[1],.5)),"Walkable route geometry includes moved path")
	region.free()
	var data = preload("res://world/editing/WorldEditData.gd")
	var doc: Dictionary = data.empty_document()
	doc.regions.mountain[row.id] = row
	Engine.set_meta("geteco_world_edit_document",doc)
	var edited = preload("res://world/editing/EditableRegion.gd").build_region("mountain")
	edited.prepare_data()
	var actual := {}
	for path in edited.walkways:
		if path.id == "cave_trail": actual = path
	check(data.catalog(edited).has(row.id),"Production adapter exposes editable path in shared catalog")
	check(not actual.is_empty() and actual.points[0].is_equal_approx(Vector3(row.points[0][0],0,row.points[0][1])),"Saved edit applies through production adapter without direct helper call")
	check(edited.roads.size() == road_count and actual.surface == "footpath","Production preserves traffic and pedestrian distinction")
	edited.free()
	Engine.remove_meta("geteco_world_edit_document")
	print("WORLD_EDITOR_ROADS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
