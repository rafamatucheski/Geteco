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
	var official := DATA.disk_hash()
	var ui := UI.new()
	ui.edits_path = "res://.godot/interior_ui_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()]
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.active_interior = "mountain_cabin"
	ui.region = "mountain"
	var id := "piece/interior/mountain_cabin/0123456789abcdef"
	var source := {"id":id,"type":"piece","position":[1,1],"rotation":0,"size":[2,2],"parts":[[0,0,2,2,1,"ffffff"]],"source_record":"interior/mountain_cabin/fixture","locked":false}
	ui.interior_catalog[ui._interior_key()] = {"objects":{},"context":{id:source},"bounds":[-8,-6,16,12]}
	ui._refresh()
	check(ui.canvas.objects.size() == 1 and ui.canvas.objects.has(id),"Interior canvas isolates room furniture from exterior world")
	ui._select(id)
	ui._set_array("position",0,3.0)
	check(ui.document.get("interiors",{}).get("mountain_cabin",{}).has(id),"Moving native furniture writes the interior document scope")
	check(ui.document.regions.mountain.is_empty() and ui.document.regions.harbor.is_empty(),"Interior coordinates never become exterior world edits")
	var stale: Dictionary = ui.document.duplicate(true)
	ui._place("prop",Vector2(2,3))
	var added: String = ui.canvas.selected_id
	check(ui.document.interiors.mountain_cabin.has(added),"Interior object placement stays in the same room scope")
	check(not ui.save() and not FileAccess.file_exists(ui.edits_path),"Unvalidated furniture cannot be published")
	ui._interior_validation_ready("mountain_cabin","",stale)
	check(not ui.save(),"A stale validation response cannot approve newer furniture edits")
	ui._interior_validation_ready("mountain_cabin","Objeto bloqueia o acesso",ui.document.duplicate(true))
	check(not ui.save() and ui.status.text.contains("bloqueia"),"Physical validation error is visible and blocks publishing")
	ui.interior_floor = 1
	ui._place("prop",Vector2(4,4))
	ui._interior_validation_ready("mountain_cabin","",ui.document.duplicate(true),1)
	check(not ui.save(),"Validation of a different floor cannot approve a blocked ground floor")
	ui.undo()
	ui.interior_floor = 0
	ui._refresh()
	ui._interior_validation_ready("mountain_cabin","",ui.document.duplicate(true),0)
	check(ui.save(),"Validated room edits can be explicitly saved")
	var restored := DATA.read_document(ui.edits_path)
	check(restored.error.is_empty() and restored.document.interiors.mountain_cabin.has(added),"Furniture survives a real document reload")
	ui.undo()
	check(not ui.document.interiors.mountain_cabin.has(added),"Undo removes newly placed furniture without altering the exterior")
	check(not ui.save(),"History changes require fresh room validation")
	check(DATA.disk_hash() == official,"Editor workflow leaves the official world untouched")
	ui.free()
	await process_frame
	print("WORLD_EDITOR_ENVIRONMENT_SCOPE checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
