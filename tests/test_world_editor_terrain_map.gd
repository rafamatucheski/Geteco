extends SceneTree
const MAP := preload("res://addons/geteco_world_editor/WorldTerrainMap.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func progress(_phase: String,_done: int,_total: int,_force: bool) -> void: pass
func cancelled() -> bool: return false
func run() -> void:
	var source := Node3D.new()
	root.add_child(source)
	var terrain := MeshInstance3D.new()
	terrain.name = "QuarryHills"
	terrain.set_meta("editor_id","piece/map_fixture")
	terrain.set_meta("world_edit_piece_id","unit/map_fixture")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,0,0),Vector3(12,6,0),Vector3(0,0,12)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	terrain.mesh = mesh
	source.add_child(terrain)
	var scenery := MeshInstance3D.new()
	scenery.name = "TreeWhichMustNotEnterRaster"
	scenery.mesh = BoxMesh.new()
	scenery.position = Vector3(50,20,50)
	source.add_child(scenery)
	var folder := "res://.godot/terrain_map_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder)
	var paths: Array[String] = ["QuarryHills"]
	var tiles := await MAP.write(source,paths,folder,1,"harbor",self,progress,cancelled)
	check(tiles.size() == 1,"Only requested terrain meshes produce topography tiles")
	if not tiles.is_empty():
		var tile: Dictionary = tiles[0]
		check(tile.bounds == [0.0,0.0,12.0,12.0],"Tile bounds follow actual terrain geometry rather than scenery")
		check(tile.source_ids == ["piece/map_fixture","piece/unit/map_fixture"],"Terrain owners use the exact piece-prefixed identities from the canvas catalog")
		var image := Image.load_from_file(tile.path)
		check(image.get_pixel(1,1).a > .9 and image.get_pixel(image.get_width()-2,image.get_height()-2).a < .01,"Pixels outside authored triangles remain transparent")
		check(image.get_pixel(1,1) != image.get_pixel(image.get_width()-4,1),"The raster communicates the real height gradient")
		DirAccess.remove_absolute(tile.path)
	var doc := {"regions":{"harbor":{}}}
	var signature := MAP.revision(doc,"harbor")
	doc.regions.harbor["new/prop"] = {"type":"prop","position":[0,0]}
	check(MAP.revision(doc,"harbor") == signature,"Moving scenery does not invalidate the terrain cache")
	doc.regions.harbor["terrain/one"] = {"type":"terrain","height":4}
	check(MAP.revision(doc,"harbor") != signature,"Actual terrain changes invalidate the raster cache")
	var grass := Image.create(2,2,false,Image.FORMAT_RGBA8)
	grass.fill(Color("578943"))
	var earth := Image.create(2,2,false,Image.FORMAT_RGBA8)
	earth.fill(Color("39241a"))
	earth.set_pixel(1,0,Color("b28c54"))
	var first: Array = MAP.material_samples(Vector2.ZERO,grass,earth)
	var second: Array = MAP.material_samples(Vector2(1,0),grass,earth)
	check(first[0].is_equal_approx(grass.get_pixel(0,0)),"2D grass samples the actual material image rather than a placeholder swatch")
	check(not first[2].is_equal_approx(second[2]),"Sand follows the same earth texture variation and world UV scale as the terrain shader")
	source.free()
	DirAccess.remove_absolute(folder)
	print("WORLD_EDITOR_TERRAIN_MAP checks=",checks," failures=",failures)
	quit(1 if failures else 0)
