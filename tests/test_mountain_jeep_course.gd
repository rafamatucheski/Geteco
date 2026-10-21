extends SceneTree
const COURSE := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
const ROUTES := preload("res://world/mountain_detail/MountainRouteLayout.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")
const SCENERY := preload("res://world/mountain_jeep/MountainJeepScenery.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	var main := ROUTES.main_route(source.mountain_control_points)
	var paths := COURSE.paths(main)
	var distance := INF
	for i in range(1,main.size()):
		distance=minf(distance,paths[0].points[0].distance_to(Geometry3D.get_closest_point_to_segment(paths[0].points[0],main[i-1],main[i])))
	check(distance<.001,"access joins the real mountain road")
	check(paths[0].points[-1].is_equal_approx(COURSE.start()),"access, staging and loop meet exactly")
	var points := COURSE.centerline()
	check(points[0].is_equal_approx(points[-1]),"loop returns to the staging area and road")
	check(COURSE.length()>250 and COURSE.length()<700,"route offers a complete timed driving course")
	var all_paths: Array[Dictionary]=ROUTES.branches(main)
	all_paths.append({"id":"main","points":main,"width":8.75,"surface":"asphalt"})
	all_paths.append_array(ROUTES.paths())
	all_paths.append_array(paths)
	var terrain := TERRAIN.new()
	terrain.configure(all_paths,CATALOG.definitions(),[])
	var supports := true
	var clear_of_story := true
	var cave := CATALOG._at(Vector2(6200,-320),"mountain")
	var plane := CATALOG._at(Vector2(5450,-1150),"mountain")
	for point in points:
		if absf(terrain.surface_height_at(Vector2(point.x,point.z)))>.02: supports=false
		if point.distance_to(cave)<60 or point.distance_to(plane)<35: clear_of_story=false
	check(supports,"terrain reservation supports full loop without hills blocking wheels")
	check(clear_of_story,"jeep route stays clear of cave pedestrian trail and cargo plane")
	var gates := COURSE.checkpoints()
	check(gates.size()>=8 and gates[-1].distance<COURSE.length()-10,"physical checkpoints leave run-off before paddock")
	var grades_ok := true
	for distance_step in range(1,int(COURSE.length()*10)):
		var s := float(distance_step)*.1
		if absf(COURSE.rise(s)-COURSE.rise(s-.1))/.1>.14: grades_ok=false
	check(grades_ok,"crests stay within a traversable fourteen percent longitudinal grade")
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	for record in COURSE.records(): SCENERY.build(root3d,record)
	var collision_count := 0
	var crests := 0
	for child in root3d.get_children():
		if child.has_meta("mountain_jeep_crest"): crests+=1
		for body in child.find_children("*","CollisionShape3D",true,false):
			if body.shape!=null: collision_count+=1
	check(crests==0,"jeep loop has no detached snow sheets or elevated colliders")
	var grounded_gates := true
	for gate in gates:
		var point: Vector3 = gate.position
		if absf(point.y-terrain.surface_height_at(Vector2(point.x,point.z)))>.02: grounded_gates=false
	check(grounded_gates,"all jeep checkpoints rest on the terrain floor")
	check(collision_count>=gates.size()*2,"visible gate supports have physical collision")
	root3d.free()
	print("MOUNTAIN_JEEP_COURSE_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)
