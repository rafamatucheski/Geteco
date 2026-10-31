extends SceneTree
## O preenchimento externo precisa continuar sólido e deixar as ruas editadas utilizáveis.
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const FACTORY = preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const SKATE = preload("res://activities/skate/SkateParkLayout.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PATROL_COURT ", "PASS " if ok else "FAIL ", label)

func polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

func clear_of_roads(rect: Rect2, source: Dictionary, edits: Dictionary) -> bool:
	for road: Dictionary in source.harbor_roads:
		var edited: Dictionary = edits.get("road/" + str(road.id), {})
		if edited.get("deleted", false): continue
		var points: Array = edited.get("points", road.points)
		var scale := 1.0 if edited.has("points") else .0625
		var half_width := float(edited.get("width", float(road.width) * .0625)) * .5
		for i in range(points.size() - 1):
			var a := Vector2(points[i][0], points[i][1]) * scale
			var b := Vector2(points[i+1][0], points[i+1][1]) * scale
			var offset := (b-a).normalized().orthogonal() * half_width
			if not Geometry2D.intersect_polygons(polygon(rect), PackedVector2Array([a+offset, b+offset, b-offset, a-offset])).is_empty(): return false
	return true

func run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	var edits: Dictionary = preload("res://world/editing/WorldServiceBuildings.gd").changes()
	var stage := Node3D.new()
	root.add_child(stage)
	var infill: Array[Dictionary] = []
	var styles := {}
	for row: Dictionary in source.harbor_buildings:
		if not str(row.id).begins_with("PatrolCourt"): continue
		infill.append(row)
		var access := CATALOG.for_source(row.id)
		check(not access.is_empty() and bool(access.get("continuous_access", false)), str(row.id) + " painted door has walk-in interior")
		styles[PaintedHarborHouses.style_for(str(row.id), str(row.kind))] = true
		var at := FACTORY.extract_position(row)
		var size := FACTORY.extract_size(row)
		var footprint := Rect2(Vector2(at.x, at.z)-size*.5, size)
		check(clear_of_roads(footprint.grow(2.0), source, edits), str(row.id) + " facade clears roads and pedestrian lanes")
		check(not footprint.intersects(SKATE.FOOTPRINT), str(row.id) + " separate from relocated skate park")
		var props_clear := true
		for prop: Dictionary in preload("res://world/urban_detail/HarborProp3D.gd").records():
			var point: Vector2 = prop.point / 16.0
			var key := "harbor_prop/%s/%.5f/%.5f" % [prop.kind, point.x, point.y]
			var edit: Dictionary = edits.get(key, {})
			if edit.get("deleted", false): continue
			if edit.has("position"): point = Vector2(edit.position[0], edit.position[1])
			var radius := 2.4 if prop.kind == "tree" else (2.1 if prop.kind == "bench" else .8)
			if footprint.grow(radius).has_point(point): props_clear = false
		check(props_clear, str(row.id) + " no authored prop intrudes into building")
		var art := FACTORY.build_building(row)
		stage.add_child(art)
	check(infill.size() == 4, "four low-rise buildings behind police")
	check(styles.size() == 4 and not styles.has(""), "four distinct painted facades")
	check(not CATALOG.for_source("Apartments").is_empty(), "existing apartment interior preserved")
	check(not CATALOG.for_source("Aquarium").is_empty(), "existing aquarium interior preserved")
	check(clear_of_roads(SKATE.FOOTPRINT.grow(.5), source, edits), "skate court and perimeter clear streets")
	check(SKATE.FOOTPRINT.has_point(Vector2(SKATE.ENTRY.x, SKATE.ENTRY.z)), "skate boarding point follows relocated court")
	check(SKATE.reserved(Vector2(SKATE.ENTRY.x, 134.5)), "southern pedestrian approach reserved")
	check(SKATE.reserved(SKATE.FOOTPRINT.position-Vector2(.8, 0), 1.0), "prop footprint crossing court boundary reserved")
	var furniture := {}
	preload("res://world/city_look/CityChunkDressing.gd")._add(furniture, "bench_seat", SKATE.ENTRY+Vector3(0,0,4), Vector2.DOWN)
	check(furniture.is_empty(), "generated bench cannot block the approach")
	preload("res://world/city_look/CityChunkDressing.gd")._add(furniture, "bench_seat", SKATE.CENTER+Vector3(20,0,0), Vector2.DOWN)
	check(not furniture.is_empty(), "furniture outside court preserved")
	await physics_frame
	await physics_frame
	var walker := CharacterBody3D.new()
	walker.collision_layer = 2
	walker.collision_mask = 1
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = .3
	collider.shape = capsule
	collider.position.y = .85
	walker.add_child(collider)
	stage.add_child(walker)
	await physics_frame
	for row in infill:
		var at := FACTORY.extract_position(row)
		var size := FACTORY.extract_size(row)
		var query := PhysicsRayQueryParameters3D.create(at + Vector3(0,1,10), at + Vector3(0,1,-10), 1)
		check(not stage.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), str(row.id) + " facade has solid collision")
		walker.position = at + Vector3(0,.025,size.y*.5+1)
		check(walker.move_and_collide(Vector3(0,0,-3), true) != null, str(row.id) + " swept pedestrian cannot cross wall beside door")
		walker.position = at + Vector3(-size.x*.5-1,.025,-size.y*.5-.5)
		check(walker.move_and_collide(Vector3(0,0,size.y+1), true) == null, str(row.id) + " side passage remains walkable")
	stage.free()
	print("PATROL_COURT_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
