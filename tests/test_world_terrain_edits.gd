extends SceneTree
## Brush contract plus real terrain collisions; rendered frame time is measured separately.
const DATA := preload("res://world/editing/WorldEditData.gd")
const FIELD := preload("res://world/editing/WorldTerrainEdits.gd")
const MOUNTAIN := preload("res://world/regions/MountainTerrain3D.gd")
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func document(row: Dictionary, area: String) -> Dictionary:
	var result := DATA.empty_document()
	result.regions[area][row.id] = row
	return result

func ray(point: Vector2, expected: float, label: String) -> void:
	var at := Vector3(point.x,expected,point.y)
	var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*30,at-Vector3.UP*30,1)
	var hit := root.world_3d.direct_space_state.intersect_ray(query)
	check(not hit.is_empty(),label+" has physical ground")
	if not hit.is_empty(): check(absf(hit.position.y-expected)<.003,label+" query equals physical triangle")

func run() -> void:
	var official := DATA.disk_hash()
	var previous: Variant = Engine.get_meta("geteco_world_edit_document") if Engine.has_meta("geteco_world_edit_document") else null
	var center := Vector2(704,-352)
	var brush := FIELD.new_brush(center,"mountain")
	brush.height = 8.0
	brush.radius = 40.0
	brush.surface = "snow"
	var doc := document(brush,"mountain")
	check(DATA.validate_document(doc).is_empty(),"Persistent terrain document validates")
	var field := FIELD.new()
	field.configure(doc,"mountain","mountain")
	check(is_equal_approx(field.height_at(center,3),11),"Offset changes the terrain height")
	check(is_equal_approx(field.height_at(center+Vector2(40,0),3),3),"Brush edge preserves surrounding terrain")
	check(is_equal_approx(field.height_at(center,3,true),3),"Default brush does not edit route")
	check(is_equal_approx(field.paint_weights(center)[5],1),"Snow paint has continuous material weight")
	brush.height = 99.0
	check(is_equal_approx(field.height_at(center,3),11),"Worker field owns immutable brush snapshot")
	brush.height = 8.0
	var flatten := brush.duplicate(true)
	flatten.id = "terrain/flatten"
	flatten.mode = "flatten"
	flatten.height = 4.0
	flatten.order = int(brush.order)+1
	doc.regions.mountain[flatten.id] = flatten
	field.configure(doc,"mountain","mountain")
	check(is_equal_approx(field.height_at(center,3),4),"Ordered flatten applies after offset")
	doc.regions.mountain.erase(flatten.id)
	var left_map := field.paint_maps(Rect2(640,-384,64,64))
	var right_map := field.paint_maps(Rect2(704,-384,64,64))
	var seam_ok := true
	for z in left_map.size.y:
		for channel in 4:
			if left_map.b[(z*left_map.size.x+left_map.size.x-1)*4+channel] != right_map.b[z*right_map.size.x*4+channel]: seam_ok = false
	check(seam_ok,"Adjacent paint textures share exact border weights")
	Engine.set_meta("geteco_world_edit_document",DATA.empty_document())
	var baseline := MOUNTAIN.new()
	baseline.configure([],[],[])
	Engine.set_meta("geteco_world_edit_document",doc)
	var production: Variant = preload("res://world/editing/EditableRegion.gd").build_region("mountain")
	production.prepare_data()
	check(production.terrain!=null and production.terrain._editor_terrain.brushes.size()==1,"Production region accepts terrain rows through the ordinary edit adapter without object-origin errors")
	production.free()
	var terrain := MOUNTAIN.new()
	terrain.configure([],[],[])
	check(absf(terrain.height_at(center)-baseline.height_at(center)-8)<.0001,"Production mountain consumes brush before mesh generation")
	var holder := Node3D.new()
	root.add_child(holder)
	var first := terrain.build_chunk(holder,Rect2(640,-384,64,64))
	var second := terrain.build_chunk(holder,Rect2(704,-384,64,64))
	var a: Array = first.mesh.surface_get_arrays(0)
	var b: Array = second.mesh.surface_get_arrays(0)
	var continuous := true
	for z in 17:
		if not a[Mesh.ARRAY_VERTEX][z*17+16].is_equal_approx(b[Mesh.ARRAY_VERTEX][z*17]): continuous = false
	check(continuous,"Edited mountain chunks have no seam")
	check(first.material_override.get_shader_parameter("editor_terrain_paint_enabled") == true,"Production material binds terrain paint")
	await physics_frame
	await physics_frame
	for point in [center+Vector2(-.01,3.2),center+Vector2(.01,3.2),center+Vector2(9.3,-8.1)]:
		ray(point,terrain.surface_height_at(point),"Edited mountain "+str(point))
	holder.free()
	# Motocross source and route-only switch use the actual production constructor.
	Engine.set_meta("geteco_world_edit_document",DATA.empty_document())
	var source := COURSE.new()
	var index := 20
	var track: Vector3 = source.points[index]
	var stamp := FIELD.new_brush(Vector2(track.x,track.z),"motocross")
	stamp.radius = 30.0
	stamp.height = 3.0
	stamp.surface = "earth"
	Engine.set_meta("geteco_world_edit_document",document(stamp,"harbor"))
	var surrounding := COURSE.new()
	check(surrounding.points[index].is_equal_approx(track),"Surroundings brush preserves motocross route by default")
	stamp.affect_track = true
	Engine.set_meta("geteco_world_edit_document",document(stamp,"harbor"))
	var edited := COURSE.new()
	check(absf(edited.points[index].y-track.y-3)<.001,"Include track edits actual route height")
	check(edited._editor_terrain.paint_weights(Vector2(track.x,track.z),true)[1]>.99,"Include track paints actual clay")
	# Build only the two ground surfaces under test; no scenery/AI or staged ready loop.
	edited._build_terrain()
	edited._mesh(edited._terrain_surface,"QuarryHills",true)
	edited._build_ribbon()
	root.add_child(edited)
	edited.set_process(false)
	await physics_frame
	await physics_frame
	var terrain_point := Vector2(-185,-116)
	# Ribbon may cover a quarry point: isolate the quarry collision for this assertion.
	var ribbon: Node3D = edited.get_node("DirtTrack").get_child(0)
	var ribbon_mesh: Node = ribbon.get_parent()
	ribbon_mesh.remove_child(ribbon)
	await physics_frame
	ray(terrain_point,edited.surface_height(terrain_point),"Edited motocross quarry")
	ribbon_mesh.add_child(ribbon)
	var quarry: Node3D = edited.get_node("QuarryHills").get_child(0)
	quarry.get_parent().remove_child(quarry)
	await physics_frame
	ray(Vector2(track.x,track.z),edited._ribbon_vertex(index,0).y,"Edited motocross clay")
	quarry.free()
	edited.free()
	source.free()
	surrounding.free()
	if previous == null: Engine.remove_meta("geteco_world_edit_document")
	else: Engine.set_meta("geteco_world_edit_document",previous)
	check(DATA.disk_hash()==official,"Terrain validation never saves the authored document")
	print("WORLD TERRAIN EDITS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
