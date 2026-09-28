extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var checks := 0
var failures: Array[String] = []
var folder := "res://evidence/world-editor-20260925/"
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func key(ui: Control,code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.ctrl_pressed = true
	event.pressed = true
	root.push_input(event,true)
func run() -> void:
	root.size = Vector2i(1440,900)
	var ui := UI.new()
	ui.edits_path = folder+"assets_ui_"+str(OS.get_process_id())+".json"
	ui.draft_path = folder+"assets_draft_"+str(OS.get_process_id())+".json"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	check(ui.save_button.text.contains("Salvar mundo") and not ui.save_button.disabled,"Visible save button even when saved")
	ui.asset_search.text = "pallet"
	ui._filter_assets()
	check(ui.visible_assets.size() == 2,"Search finds pallet and stack")
	ui._arm_asset(1)
	check(ui.canvas.armed == "prop","Library arms prop placement")
	ui._place("prop",Vector2(53,112))
	var id: String = ui.canvas.selected_id
	check(ui.document.regions.harbor.has(id) and ui.document.regions.harbor[id].model == "pallet_stack","Library places chosen actualmodel")
	ui._set_value("rotation",35)
	ui._set_value("scale",1.5)
	ui.canvas.grab_focus()
	key(ui,KEY_C)
	check(ui.clipboard_row.model == "pallet_stack","CtrlC copies selectedmodel")
	key(ui,KEY_V)
	check(ui.canvas.armed == "prop","CtrlV arms a copy")
	ui._place("prop",Vector2(56,112))
	var copied: String = ui.canvas.selected_id
	check(copied != id and ui.document.regions.harbor[copied].rotation == 35 and ui.document.regions.harbor[copied].scale == 1.5,"Paste newidentity retainsrotation+scale")
	check(DATA.point(ui.document.regions.harbor[id].position) == Vector2(53,112),"Paste does not mutate source")
	ui.undo()
	check(not ui.document.regions.harbor.has(copied),"Undo paste")
	ui.redo()
	check(ui.document.regions.harbor.has(copied),"Redo paste")
	ui.asset_search.grab_focus()
	var unchanged: Dictionary = ui.clipboard_row.duplicate(true)
	key(ui,KEY_C)
	check(ui.clipboard_row == unchanged,"Search text focus leaves worldclipboard unchanged")
	ui.canvas.grab_focus()
	key(ui,KEY_V)
	ui._place("prop",Vector2(850,-450))
	check(ui.document.regions.mountain.size() == 1,"Paste across regions choosesdestination")
	ui._switch_region("harbor")
	var road := DATA.new_entity("road",Vector2(0,150))
	road.points = [[-5.0,150.0],[0.0,151.0],[9.0,155.0]]
	ui._commit(road)
	ui.canvas.grab_focus()
	key(ui,KEY_C)
	key(ui,KEY_V)
	ui._place("road",Vector2(20,155))
	var roadcopy: Dictionary = ui.document.regions.harbor[ui.canvas.selected_id]
	check((DATA.point(roadcopy.points[2])-DATA.point(roadcopy.points[0])).is_equal_approx(Vector2(14,5)),"Copy street preservesrelativebends")
	var neco: Dictionary = ui.canvas.objects.get("piece/neco/Office",{})
	check(not neco.is_empty() and not neco.locked,"Neko office individuallyeditable")
	if not neco.is_empty():
		ui._select(neco.id)
		ui._set_array("position",0,float(neco.position[0])-5)
		check(ui.document.regions.harbor.has(neco.id),"Neko office movement persisted")
		check(not ui.document.regions.harbor[neco.id].has("parts"),"Piece edits stay sparse")
		check(ui.canvas.objects[neco.id].parts != neco.parts,"Piece triangles move in editor")
	var cobra_id := ""
	for row in ui.canvas.objects.values():
		if row.type == "building" and row.get("model","") == "cobra_house": cobra_id = row.id; break
	check(not cobra_id.is_empty(),"Cobra houses available")
	if not cobra_id.is_empty():
		ui._select(cobra_id)
		var old: Vector2 = DATA.point(ui.canvas.objects[cobra_id].position)
		ui._set_array("position",0,old.x+2)
		check(ui.document.regions.harbor.has(cobra_id),"Cobra house can be moved despite existing lot overlaps")
	ui.asset_search.text = "lixo"
	ui._filter_assets()
	check(ui.visible_assets.size() >= 2,"Search lixo returnsbag+dumpster")
	ui.asset_search.text = "arvore"
	ui._filter_assets()
	check(ui.visible_assets.size() >= 16,"Search ignoresaccents")
	ui.asset_search.text = "neko"
	ui._filter_assets()
	check(ui.visible_assets.size() >= 20,"Neko individualpieces searchable")
	check(ui.canvas.objects.values().any(func(row): return row.type == "road" and row.get("pathway",false) and not row.get("locked",false)),"Mountain trails unlocked")
	ui._switch_region("mountain")
	ui._select("path/cave_trail")
	check(ui.canvas.objects.has("path/cave_trail"),"Cave trail exists")
	var trail: Dictionary = ui.canvas.objects.get("path/cave_trail",{}).duplicate(true)
	if not trail.is_empty():
		trail.points[1][0] += 1
		ui._commit(trail)
		check(ui.document.regions.mountain.has(trail.id),"Narrow mountaintrail edits accepted")
	ui._switch_region("harbor")
	ui._select(id)
	ui.save_button.pressed.emit()
	check(DATA.read_document(ui.edits_path).document.regions.harbor.has(copied),"Savebutton writes realfile")
	check(ui.save_state.text == "Mundo salvo" and ui.save_button.text.contains("Salvar mundo"),"Saved status doesn't hide saveaction")
	var x_input: SpinBox = ui.properties.find_children("*","SpinBox",true,false)[0]
	x_input.get_line_edit().grab_focus()
	x_input.get_line_edit().text = "57"
	print("URBAN_FOCUS ",ui.get_viewport().gui_get_focus_owner()," visible=",x_input.is_visible_in_tree()," selected=",ui.canvas.selected_id)
	key(ui,KEY_S)
	print("URBAN_SAVE_STATUS ",ui.status.text," value=",x_input.value," doc=",ui.document.regions.harbor[id].position)
	check(is_equal_approx(DATA.read_document(ui.edits_path).document.regions.harbor[id].position[0],57.0),"CtrlS commits the numericfield still beingtyped")
	# Composite footprint must not swallow a roadclick.
	var real_objects: Dictionary = ui.canvas.objects
	ui.canvas.objects = {"context/test":{"id":"context/test","type":"context","position":[0,0],"size":[50,50],"locked":true},"road/test":{"id":"road/test","type":"road","points":[[-20,0],[20,0]],"width":7.5}}
	check(ui.canvas.pick(ui.canvas.screen(Vector2.ZERO)) == "road/test","Road selectable overlargebackgroundcontext")
	ui.canvas.objects["piece/ground"] = {"id":"piece/ground","type":"piece","position":[0,0],"size":[100,100],"ground":true}
	check(ui.canvas.pick(ui.canvas.screen(Vector2.ZERO)) == "road/test","Road selectable overmovablegroundpiece")
	ui.canvas.objects = real_objects
	if DisplayServer.get_name() != "headless":
		for child in root.find_children("*","CanvasLayer",true,false): child.hide()
		ui.asset_search.text = ""
		ui._filter_assets()
		ui.canvas.center = Vector2(-46,34)
		ui.canvas.zoom = 11
		ui._select("piece/neco/Office")
		ui.canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"library-editor.png")
	ui.free()
	await process_frame
	print("WORLD_ASSET_UI checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
