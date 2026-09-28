extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const SERVICES := preload("res://world/editing/WorldServiceBuildings.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var failed := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failed += 1; push_error(label)
func run() -> void:
	var official := DATA.disk_hash()
	var ui := preload("res://addons/geteco_world_editor/WorldEditor.gd").new()
	ui.edits_path = "res://.godot/service_controls_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	await process_frame
	var doc := DATA.empty_document()
	var originals := {}
	for id in SERVICES.PLACES:
		var key := "building/"+str(id)
		ui._select(key)
		var row: Dictionary = ui.canvas.objects[key].duplicate(true)
		check(not row.locked and row.service_building,"Service is selectable: "+id)
		originals[id] = PLACES.get_definition(SERVICES.PLACES[id])
		row.position[0] += 3.0
		row.rotation = 25.0
		row.size = [row.size[0]*1.1,row.size[1]*1.15]
		row.height *= 1.1
		if id == "Police": row.position = [5.0,95.0]
		check(DATA.validate_entity(row).is_empty(),"Moved/rotated/enlarged service validates: "+id)
		doc.regions.harbor[key] = row
	ui._select("building/Police")
	ui._set_value("height",float(ui.canvas.objects["building/Police"].height)*1.1)
	check(ui.document.regions.harbor.has("building/Police"),"Police dimensions can be committed from properties")
	ui.undo()
	check(not ui.document.regions.harbor.has("building/Police"),"Undo restores police dimensions")
	ui.redo()
	check(ui.document.regions.harbor.has("building/Police"),"Redo restores police dimensions")
	ui._delete()
	check(not ui.document.regions.harbor["building/Police"].get("deleted",false),"Delete cannot remove service identity")
	var unsafe: Dictionary = ui.canvas.objects["building/Police"].duplicate(true)
	unsafe.position[0] += 2
	unsafe.rotation = 25.0
	unsafe.size = [unsafe.size[0]*1.2,unsafe.size[1]*1.2]
	ui._commit(unsafe)
	check(ui.document.regions.harbor["building/Police"].rotation == 0,"Service edit cannot cover another place's access")
	Engine.set_meta("geteco_world_edit_document",doc)
	for id in SERVICES.PLACES:
		var original: Dictionary = originals[id]
		var definition := PLACES.get_definition(SERVICES.PLACES[id])
		var transform := SERVICES.transform_for(doc.regions.harbor["building/"+id])
		check(definition.entry_position.is_equal_approx(transform*original.entry_position),"Entry follows service transform: "+id)
		check(definition.return_position.is_equal_approx(transform*original.return_position),"Return follows service transform: "+id)
		check(definition.spawn == original.spawn and definition.size == original.size,"Interior remains independent: "+id)
	Engine.remove_meta("geteco_world_edit_document")
	if "--live" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440,900)
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ui.document = doc
		ui._refresh()
		ui._select("building/Police")
		ui.canvas.center = DATA.point(doc.regions.harbor["building/Police"].position)
		ui.canvas.zoom = 6
		ui._toggle_live_preview()
		var deadline := Time.get_ticks_msec()+90000
		while ui.live_preview.applied_revision == 0 and Time.get_ticks_msec() < deadline: await process_frame
		check(ui.live_preview.applied_revision > 0,"Modified service buildings load in editor preview")
		ui.live_preview.view_size = 38
		ui.live_preview.yaw = -.3
		ui.live_preview._pose()
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/service-editor-20260926/editor.png")
	check(DATA.disk_hash() == official,"Official map untouched")
	ui.free()
	print("SERVICE_CONTROLS ",checks," checks ",failed," failures")
	quit(1 if failed else 0)
