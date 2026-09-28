extends "res://tests/test_world_editor_live_preview.gd"
const PAVING := preload("res://world/editing/WorldPaving.gd")
const ROADS := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
func run() -> void:
	var official := DATA.disk_hash()
	var source: Array[Dictionary] = [
		{"id":"main","points":PackedVector3Array([Vector3(-30,0,0),Vector3(30,0,0)]),"width":8.0},
		{"id":"branch","points":PackedVector3Array([Vector3(0,0,0),Vector3(0,0,30)]),"width":8.0}]
	var road := ROADS.new()
	road.configure(source)
	check(road._crosswalk_stop.size() == 3,"T junction has one approaching stop line per arm")
	for stop in road._crosswalk_stop:
		check(is_equal_approx(stop[0].distance_to(stop[3]),4),"Stop line covers only approaching half of road")
	for mask in road._crossing_masks:
		check(road._marking_hits_junction((mask[0]+mask[2])*.5),"Yellow marking excludes pedestrian crossing")
	var before: Vector2 = road._layers[0].polygons[0][0]
	source[0].sidewalk_width = 5.0
	source[0].crossings = false
	source[1].crossing_offset = 3.0
	road.configure(source)
	check(road._crosswalk_stop.size() == 1,"Disabling main road crossings keeps branch crossing")
	check(road._layers[0].polygons[0][0] != before,"Width changes sidewalk mesh")
	var rows := PAVING.catalog()
	check(rows.size() > 20,"Existing lot paving is exposed")
	var row: Dictionary = rows.values()[1].duplicate(true)
	check(DATA.validate_entity(row).is_empty(),"Existing paving validates")
	row.position = [-100,250]
	row.size = [12,10]
	row.color = "bbaa88"
	var surface := PAVING.SURFACE.new()
	surface.configure()
	PAVING.apply(surface,{row.id:row})
	var found := false
	for item in surface._surfaces:
		if item.rect == Rect2(-106,245,12,10) and item.color == Color("bbaa88"): found = true
	check(found,"Moved resized and recolored paving replaces source geometry")
	row.deleted = true
	surface.configure()
	var count := surface._surfaces.size()
	PAVING.apply(surface,{row.id:row})
	check(surface._surfaces.size() == count-1,"Deleting paving removes source instead of overlaying it")
	ui = UI.new()
	ui.edits_path = "res://.godot/paving_test_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.size = Vector2i(1440,900)
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	check(ui.canvas.objects.has(row.id),"Existing catalog receives paving without manual rebuild")
	row.erase("deleted")
	ui._commit(row)
	check(ui.document.regions.harbor.has(row.id),"Editor commits paving")
	ui.undo()
	check(not ui.document.regions.harbor.has(row.id),"Undo restores authored paving")
	ui.redo()
	check(ui.document.regions.harbor.has(row.id),"Redo restores paving edit")
	ui._write_draft()
	var draft: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ui.draft_path))
	check(DATA.validate_document(draft.document).is_empty() and draft.document.regions.harbor.has(row.id),"Paving survives JSON draft roundtrip")
	var edited_road: Dictionary = {}
	for item in ui.canvas.objects.values():
		if item.type == "road" and not item.get("pathway",false) and item.get("editor_region", "harbor") == "harbor":
			edited_road = item.duplicate(true)
			break
	edited_road.sidewalk_width = 4.0
	edited_road.crossings = false
	ui._commit(edited_road)
	check(ui.document.regions.harbor.has(edited_road.id),"Street settings are editable")
	Engine.set_meta("geteco_world_edit_document",ui.document)
	var runtime := preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	runtime.prepare_data()
	var matched := false
	for item in runtime.roads:
		if item.id == str(edited_road.id).trim_prefix("road/"):
			matched = item.get("sidewalk_width",0) == 4.0 and item.get("crossings",true) == false and item.points[0] == DATA.xyz(edited_road.points[0])
	check(matched,"Production receives sidewalk settings without moving traffic route")
	found = false
	for item in runtime.harbor_urban_surface._surfaces:
		if item.rect == Rect2(-106,245,12,10): found = true
	check(found,"Production replaces edited paving rectangle")
	runtime.free()
	Engine.remove_meta("geteco_world_edit_document")
	if DisplayServer.get_name() != "headless":
		ui.canvas.center = Vector2(25,107)
		ui.canvas.zoom = 8
		ui._select("")
		ui._toggle_live_preview()
		check(await settled(0),"Edited paving and crossings load in live 3D")
		ui.live_preview.view_size = 40
		ui.live_preview.yaw = -.4
		ui.live_preview._pose()
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/world-editor-paving.png")
	check(DATA.disk_hash() == official,"Official world is unchanged")
	ui.free()
	print("WORLD_PAVING ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
