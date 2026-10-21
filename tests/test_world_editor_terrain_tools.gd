extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var ui := UI.new()
	ui.background_topography_enabled = false # Pure tool workflow; raster worker has its own rendered coverage.
	ui.edits_path = "res://.godot/terrain_tools_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()]
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui._set_terrain_mode(true)
	ui.terrain_settings.merge({"radius":8.0,"height":2.0,"surface":"rock"},true)
	ui._place("terrain",Vector2(-176,-96))
	var motocross: String = ui.canvas.selected_id
	check(ui.document.regions.harbor.has(motocross) and ui.document.regions.harbor[motocross].target == "motocross","Terrain tool targets the real motocross ground")
	check(ui.document.regions.harbor[motocross].surface == "rock" and is_equal_approx(ui.document.regions.harbor[motocross].height,2),"Brush records actual surface and relief settings")
	check(ui.canvas.armed == "terrain","Terrain tool remains ready for the next stamp")
	ui._place("terrain",Vector2(650,-400))
	var mountain: String = ui.canvas.selected_id
	check(ui.document.regions.mountain.has(mountain) and ui.document.regions.mountain[mountain].target == "mountain","Mountain stamps do not leak into Harbor")
	ui._terrain_value(ui.canvas.objects[mountain],"radius",16.0)
	check(is_equal_approx(ui.document.regions.mountain[mountain].radius,16),"Terrain inspector edits the selected stamp")
	var before: Dictionary = ui.document.duplicate(true)
	ui._place("terrain",Vector2(50,110))
	check(ui.document == before and ui.status.text.contains("disponível"),"Unsupported terrain target is rejected explicitly without creating a decorative flat overlay")
	check(not FileAccess.file_exists(ui.edits_path),"Terrain editing remains unpublished until explicit Save")
	ui._set_terrain_mode(false)
	check(ui.canvas.armed.is_empty(),"Selection mode exits terrain placement")
	ui.free()
	await process_frame
	print("WORLD_EDITOR_TERRAIN_TOOLS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
