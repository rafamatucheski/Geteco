extends SceneTree
const LEGACY := preload("res://addons/geteco_world_editor/WorldTerrainLegacy.gd")
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
class WorldRoot extends Node3D:
	var chunks := {}
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func box(parent: Node3D,at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = BoxMesh.new()
	node.position = at
	parent.add_child(node)
	return node
func contains(parts: Array,at: Vector2) -> bool:
	for part: Array in parts:
		if Rect2(part[0],part[1],part[2],part[3]).has_point(at): return true
	return false
func run() -> void:
	var source := WorldRoot.new()
	root.add_child(source)
	var course := Node3D.new()
	course.set_meta("world_unit_session_source","motocross")
	source.add_child(course)
	var terrain := box(course,Vector3.ZERO)
	terrain.set_meta("editor_terrain_surface",true)
	var group := Node3D.new()
	group.set_meta("world_edit_piece_id","unit/harbor/s_motocross/test")
	course.add_child(group)
	box(group,Vector3(7,1,7))
	box(course,Vector3(3,1,3))
	var id := "context/harbor/motocross_course/123"
	var old := {"id":id,"type":"context","kind":"motocross_course","position":[0,0],"size":[20,20],"parts":[[-10,-10,20,20,1,"657c68"]]}
	var forest_id := "context/harbor/session/vertice_woodland"
	var forest := Node3D.new()
	forest.set_meta("editor_id",forest_id)
	source.add_child(forest)
	box(forest,Vector3(-6,1,-6))
	var forest_old := {"id":forest_id,"kind":"woodland","parts":[[-10,-10,20,20,0,"657c68"]]}
	var tiles: Array = [{"bounds":[-10,-10,20,20],"source_ids":["piece/unit/harbor/s_motocross/terrain"],"foreground":{}}]
	LEGACY.bind(source,"harbor",tiles,[{"id":"piece/unit/harbor/s_motocross/test"}],{id:old,forest_id:forest_old})
	check(tiles[0].foreground.has(id) and id in tiles[0].source_ids,"The actual legacy course owner is explicitly bound to the replacement terrain")
	var parts: Array = tiles[0].foreground[id].parts
	check(not contains(parts,Vector2.ZERO),"Flat legacy terrain never repaints the center of the raster")
	check(contains(parts,Vector2(3,3)),"Props missing from the individual unit catalog remain in the foreground")
	check(not contains(parts,Vector2(7,7)),"Individually editable props are excluded from the aggregate foreground, preventing move/delete ghosts")
	check(tiles[0].foreground.has(forest_id) and contains(tiles[0].foreground[forest_id].parts,Vector2(-6,-6)) and not contains(tiles[0].foreground[forest_id].parts,Vector2.ZERO),"The second legacy woodland owner retains its trees while its obsolete green floor no longer covers the hill")
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color("bca778"))
	tiles[0].texture = ImageTexture.create_from_image(image)
	var canvas := CANVAS.new()
	root.add_child(canvas)
	canvas.region = "harbor"
	canvas.objects = {id:old}
	canvas.rebuild_context()
	canvas.set_terrain_topography("harbor",tiles)
	check(canvas._terrain_owner_replaced(id) and canvas._terrain_part_replaced(0),"The production canvas actually discards the legacy opaque parts drawn over the PNG")
	var unprovided: Array = [{"bounds":[-10,-10,20,20],"source_ids":[],"foreground":{}}]
	LEGACY.bind(source,"harbor",unprovided,[],{id:old})
	check(unprovided[0].foreground.is_empty(),"A missing unit manifest cannot silently remove authored scenery")
	canvas.free()
	var chunk := Node3D.new()
	source.add_child(chunk)
	source.chunks[Vector2i.ZERO] = chunk
	var ground := box(chunk,Vector3.ZERO)
	ground.set_meta("desert_base_ground",true)
	box(chunk,Vector3(12,1,12))
	var desert_tiles: Array = [{"bounds":[0,0,48,48],"source_ids":[],"foreground":{}}]
	var desert_id := "context/desert/terrain/0/0"
	LEGACY.bind(source,"desert",desert_tiles,[{"id":"piece/elsewhere"}],{desert_id:{"kind":"terrain"},"context/desert/terrain/2/2":{"kind":"terrain"}})
	check(desert_tiles[0].foreground.has(desert_id),"A desert cell covered by real canyon raster receives a legacy replacement")
	check(contains(desert_tiles[0].foreground[desert_id].parts,Vector2(12,12)) and not contains(desert_tiles[0].foreground[desert_id].parts,Vector2.ZERO),"Desert foreground preserves actual props while removing its duplicate flat base")
	check(not desert_tiles[0].foreground.has("context/desert/terrain/2/2"),"Uncovered desert cells remain unchanged")
	source.free()
	print("WORLD_EDITOR_TERRAIN_LEGACY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
