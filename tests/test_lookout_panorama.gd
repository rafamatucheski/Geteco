extends SceneTree
## Geometry/source contracts only. The parent run owns rendered panorama/FPS.
const SEA := preload("res://world/places/coastal_lookout/LookoutDistantSea.gd")
const CITY := preload("res://world/places/coastal_lookout/LookoutDistantCity.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")
const OCEAN := preload("res://world/regions/HarborOcean.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ")+message)
	if not value: failures.append(message)

func run() -> void:
	var sea := SEA.build()
	root.add_child(sea)
	var bounds := sea.mesh.get_aabb()
	check(bounds.position.x<=-8192 and bounds.position.z<=-8192 and bounds.end.x>=8192 and bounds.end.z>=8192,"Ocean covers every gallery direction beyond optical far plane")
	var arrays := sea.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var crossings := 0
	var bridge_errors := 0
	var bridge_samples := 0
	for i in range(0,indices.size(),3):
		var center := (vertices[indices[i]]+vertices[indices[i+1]]+vertices[indices[i+2]])/3.0
		if DESERT.BOUNDS.grow(-.0001).has_point(Vector2(center.x,center.z)): crossings += 1
	for point in vertices:
		if Rect2(400,-352,144,128).has_point(Vector2(point.x,point.z)):
			bridge_samples += 1
			if absf(point.y-(OCEAN.surface_y(Vector2(point.x,point.z))-.12))>.0001: bridge_errors += 1
	check(crossings==0,"No panorama ocean triangles cover desert or its below-sea-level quarry")
	check(bridge_samples>0 and bridge_errors==0,"Dense bridge samples preserve native water depression")
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bounded_uv := true
	for point in uv:
		if point.x<-.001 or point.y<-.001 or point.x>256.001 or point.y>256.001: bounded_uv = false; break
	check(bounded_uv,"Ocean shader receives bounded period-aligned UV coordinates")
	var city := CITY.new()
	root.add_child(city)
	city.build({"regions":{}})
	var source_by_id := {}
	for row in city.source_buildings: source_by_id[row.id] = row
	check(source_by_id.has("desert_bank") and source_by_id.desert_bank.position.is_equal_approx(DESERT.BANK),"Distant Cobre bank is at its actual production coordinate")
	check(source_by_id.has("desert_digo") and source_by_id.desert_digo.position.is_equal_approx(DESERT.WORKSHOP),"Distant Digo workshop is at its actual production coordinate")
	check(source_by_id.has("santa_lua_store"),"Authored Santa Lua village is represented")
	check(city.find_children("*","CollisionObject3D",true,false).is_empty() and city.find_children("*","Light3D",true,false).is_empty(),"Distant town mounts no remote physics or lights")
	check(city.get_child_count()>0 and int(city.get_meta("authored_building_count"))==city.source_buildings.size(),"Source buildings produce bounded visual cell batches")
	print("LOOKOUT PANORAMA ",checks," checks, ",failures.size()," failures; vertices=",vertices.size()," cells=",city.get_child_count())
	sea.queue_free()
	city.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
