extends SceneTree
const CONTEXT := preload("res://addons/geteco_world_editor/WorldContextCatalog.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var region := Node3D.new()
	root.add_child(region)
	var course := Node3D.new()
	course.set_meta("editor_id","context/harbor/session/motocross")
	region.add_child(course)
	var soil := MeshInstance3D.new()
	soil.mesh = BoxMesh.new()
	soil.mesh.size = Vector3(10,.1,10)
	soil.set_meta("editor_terrain_surface",true)
	course.add_child(soil)
	var crate := MeshInstance3D.new()
	crate.mesh = BoxMesh.new()
	crate.position.y = 1
	course.add_child(crate)
	var whole := CONTEXT.from_node(course,"context/course","Course","course",Vector3.ZERO)
	check(whole.parts.any(func(value): return value.size()>7 and value[7] == true),"Baked terrain parts retain explicit surface identity")
	var rows := CONTEXT.terrain_foreground(region)
	check(rows.has("context/harbor/session/motocross"),"Terrain owner has a foreground replacement")
	var foreground: Dictionary = rows["context/harbor/session/motocross"]
	check(not foreground.parts.is_empty(),"Course decorations remain visible above the relief raster")
	check(foreground.parts.all(func(value): return value.size()<8 or value[7] != true),"Terrain is excluded from the foreground instead of covering relief")
	check(foreground.parts.size() < whole.parts.size(),"Only original terrain triangles are removed from foreground")
	var coarse := CONTEXT._coarse([[0,0,1,1,0,"657c68",[[0,0],[1,0],[1,1]],true],[0,0,1,1,2,"ff0000",[[0,0],[1,0],[1,1]],false]])
	check(coarse.all(func(value): return value.size()>7 and value[7] == false),"Coarse reduction preserves decoration identity when it covers terrain")
	check(coarse.all(func(value): return value[6].size() == 4),"Coarse cells preserve valid polygons after adding terrain metadata")
	region.free()
	print("TERRAIN FOREGROUND: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
