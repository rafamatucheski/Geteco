extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const BASE := preload("res://world/regions/NativeRegion.gd")
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
var failures: Array[String] = []
var checks := 0
var folder := "res://evidence/world-editor-20260925/"
func _initialize() -> void: call_deferred("run")
func check(condition: bool,label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
func run() -> void:
	var doc := DATA.empty_document()
	var row := DATA.new_entity("tree",Vector2(53,112))
	row.id = "new/test_tree"
	doc.regions.harbor[row.id] = row
	check(DATA.validate_document(doc).is_empty(),"Valid document accepted")
	var bad := doc.duplicate(true)
	bad.regions.harbor[row.id].scale = -1
	check(not DATA.validate_document(bad).is_empty(),"Negative scale rejected")
	bad = doc.duplicate(true)
	bad.regions.harbor[row.id].position = [NAN,0]
	check(not DATA.validate_document(bad).is_empty(),"Nonfinite coordinate rejected")
	var path := folder+"persistence_"+str(OS.get_process_id())+".json"
	check(DATA.save_document(doc,"",path).is_empty(),"Initial save succeeds")
	var loaded := DATA.read_document(path)
	check(loaded.error.is_empty() and equivalent(loaded.document,doc),"Disk reload preserves edits")
	check(not DATA.save_document(DATA.empty_document(),"",path).is_empty(),"Stale writer cannot overwrite saved edits")
	check(equivalent(DATA.read_document(path).document,doc),"Conflict preserves disk content")
	check(DATA.save_document(DATA.empty_document(),DATA.disk_hash(path),path).is_empty(),"Atomic replacement succeeds")
	check(equivalent(DATA.read_document(path+".bak").document,doc),"Backup contains previous version")
	var base := BASE.build_region("harbor")
	base.prepare_data()
	var catalog := DATA.catalog(base)
	check(catalog.has("building/Garage") and catalog["building/Garage"].locked,"Garage protected")
	var building: Dictionary = catalog["building/Apartments"].duplicate(true)
	building.position = [95.0,75.0]
	building.rotation = 30.0
	doc.regions.harbor[building.id] = building
	var lamp := DATA.new_entity("light",Vector2(55,112))
	lamp.id = "new/test_light"
	lamp.energy = 2.0
	doc.regions.harbor[lamp.id] = lamp
	var road := DATA.new_entity("road",Vector2(10,100))
	road.id = "new/test_road"
	road.points = [[-3,100],[18,100]]
	road.width = 5.0
	doc.regions.harbor[road.id] = road
	var native_road: Dictionary = catalog["road/market_street"].duplicate(true)
	native_road.width += 1.0
	doc.regions.harbor[native_road.id] = native_road
	var original_tree := ""
	for id in catalog:
		if catalog[id].type == "tree":
			original_tree = id
			break
	var removed_tree: Dictionary = catalog[original_tree].duplicate(true)
	removed_tree.deleted = true
	doc.regions.harbor[original_tree] = removed_tree
	base.free()
	Engine.set_meta("geteco_world_edit_document",doc)
	var region := REGION.build_region("harbor",Vector3(53,0,112))
	root.add_child(region)
	region.set_process(false)
	region._ensure_chunk(Vector2i(0,1))
	region._ensure_chunk(Vector2i(1,1))
	var edited_building: Dictionary = {}
	for b in region.buildings:
		if b.id == "Apartments": edited_building = b
	check(edited_building.position == Vector3(95,0,75),"Existing building moved in real world data")
	check(region.roads.any(func(r): return r.id == "new/test_road"),"New road feeds production road network")
	check(region.roads.any(func(r): return r.id == "market_street" and is_equal_approx(r.width,native_road.width)),"Existing road width changes")
	var removed_count := 0
	for records in region.records.values():
		for record in records:
			if DATA.record_id(record) == original_tree: removed_count += 1
	check(removed_count == 0,"Existing Harbor tree removed")
	var tree := find_editor_node(region,"new/test_tree")
	var light := find_editor_node(region,"new/test_light")
	var building_node := find_editor_node(region,building.id)
	check(tree != null and tree.position == Vector3(53,0,112),"Authored tree actually instantiated")
	check(light != null and light.find_children("*","OmniLight3D",true,false).size() == 1,"Authored light actually instantiated once")
	check(building_node != null and is_equal_approx(building_node.rotation.y,deg_to_rad(30)),"Building rotation reaches actual mesh/collision root")
	for i in 4: await physics_frame
	var space := root.world_3d.direct_space_state
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(52,1.4,112),Vector3(54,1.4,112),1)).is_empty(),"Tree trunk blocks physical ray")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(54,1,112),Vector3(56,1,112),1)).is_empty(),"Lamp pole blocks physical ray")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(10,3,100),Vector3(10,-1,100),1)).is_empty(),"New road has physical support")
	region.release_chunks()
	await process_frame
	region._ensure_chunk(Vector2i(0,1))
	check(find_editor_node(region,"new/test_tree") != null,"Authored object survives unload/reload")
	region.free()
	Engine.remove_meta("geteco_world_edit_document")
	var mountain_doc := DATA.empty_document()
	var mountain_base := BASE.build_region("mountain")
	mountain_base.prepare_data()
	var mountain_catalog := DATA.catalog(mountain_base)
	var mountain_tree: Dictionary = {}
	for value in mountain_catalog.values():
		if value.type == "tree":
			mountain_tree = value.duplicate(true)
			break
	mountain_tree.position[0] += 3
	mountain_tree.scale = 1.5
	mountain_doc.regions.mountain[mountain_tree.id] = mountain_tree
	mountain_base.free()
	Engine.set_meta("geteco_world_edit_document",mountain_doc)
	var mountain := REGION.build_region("mountain",DATA.xyz(mountain_tree.position))
	root.add_child(mountain)
	mountain.set_process(false)
	var mountain_node := find_editor_node(mountain,mountain_tree.id)
	check(mountain_node != null and is_equal_approx(mountain_node.scale.x,1.5),"Mountain forest edit reaches rendered object")
	check(mountain_node != null and is_equal_approx(mountain_node.position.y,mountain.terrain.surface_height_at(DATA.point(mountain_tree.position))),"Moved mountain tree rests on terrain")
	mountain.free()
	Engine.remove_meta("geteco_world_edit_document")
	root.get_node("BuildWatermark").hide()
	root.get_node("V2Settings").show_fps = false
	root.get_node("V2Settings")._update_fps_overlay()
	var editor := UI.new()
	editor.edits_path = folder+"ui_"+str(OS.get_process_id())+".json"
	editor.draft_path = folder+"draft_"+str(OS.get_process_id())+".json"
	root.add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var coverage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/geteco_world_editor/base_catalog.json"))
	for area in ["harbor","mountain"]:
		check(coverage.regions[area].coverage.record_count == coverage.regions[area].coverage.covered_records,"Every native record represented: "+area)
	var cemetery_id := ""
	for context in coverage.regions.harbor.context.values():
		if context.get("kind","") == "cemetery": cemetery_id = context.id
	check(not cemetery_id.is_empty() and coverage.regions.harbor.context[cemetery_id].parts.size() > 100,"Cemetery includes actual tombs/paths geometry")
	var tomb_min := Vector2(INF,INF)
	var tomb_max := Vector2(-INF,-INF)
	for part in coverage.regions.harbor.context[cemetery_id].parts:
		if part[5] != "777f79": continue
		tomb_min = tomb_min.min(Vector2(part[0],part[1]))
		tomb_max = tomb_max.max(Vector2(part[0],part[1]))
	check(tomb_max.x-tomb_min.x > 25 and tomb_max.y-tomb_min.y > 20,"Tombs distributed across cemetery, not collapsed at origin")
	for kind in ["lake","environmental_parity","mountain_village","sawmill_yard","cargo_plane"]:
		check(coverage.regions.mountain.context.values().any(func(r): return r.get("kind","") == kind and r.get("parts",[]).size() > 0),"Mountain composite visible: "+kind)
	check(editor.canvas.objects.has(cemetery_id),"Cemetery visible in editor")
	check(editor.canvas.objects.values().any(func(r): return r.get("editor_region","") == "mountain"),"Both regions visible together")
	editor._place("tree",Vector2(850,-450))
	check(editor.region == "mountain" and editor.document.regions.mountain.size() == 1,"Placement chooses mountain by world position")
	check(editor.document.regions.harbor.is_empty(),"Mountain placement never leaks into Harbor")
	editor.undo()
	editor._switch_region("harbor")
	var tree_row := DATA.new_entity("tree",Vector2(53,112))
	editor._commit(tree_row)
	check(editor.document.regions.harbor.has(tree_row.id),"UI placement records actual edit")
	editor.undo()
	check(not editor.document.regions.harbor.has(tree_row.id),"UI undo reverses placement")
	editor.redo()
	check(editor.document.regions.harbor.has(tree_row.id),"UI redo restores placement")
	check(editor.save(),"UI saves to disk")
	check(DATA.read_document(editor.edits_path).document.regions.harbor.has(tree_row.id),"UI save survives reload")
	var existing: Dictionary = editor.canvas.objects["building/Garage"].duplicate(true)
	existing.position = [0,0]
	editor._commit(existing)
	check(not editor.document.regions.harbor.has("building/Garage"),"UI cannot modify garage")
	var blocked := DATA.new_entity("tree",Vector2(49,93))
	editor._commit(blocked)
	check(not editor.document.regions.harbor.has(blocked.id),"Placement inside garage footprint blocked")
	editor._select(tree_row.id)
	var origin := editor.canvas.screen(DATA.point(tree_row.position))
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = origin
	editor.canvas._gui_input(down)
	var motion := InputEventMouseMotion.new()
	motion.position = origin+Vector2(8,0)
	motion.relative = Vector2(8,0)
	editor.canvas._gui_input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = motion.position
	editor.canvas._gui_input(up)
	check(is_equal_approx(editor.document.regions.harbor[tree_row.id].position[0],55.0),"Mouse drag changes saved position by snapped metres")
	editor._delete()
	check(not editor.canvas.objects.has(tree_row.id),"Delete removes object from map")
	editor._restore_id(tree_row.id)
	check(not editor.document.regions.harbor.has(tree_row.id),"Restore clears override")
	editor._commit(tree_row)
	editor.status.text = "Alteração pronta. Salve para aplicá-la na próxima execução do jogo."
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"editor.png")
		editor._fit_world()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"editor-whole-world.png")
		var cemetery: Dictionary = editor.canvas.objects[cemetery_id]
		editor.canvas.center = DATA.point(cemetery.position)
		editor.canvas.zoom = 7.0
		editor._select(cemetery_id)
		editor.canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"editor-cemetery.png")
		editor._switch_region("mountain")
		editor.canvas.center = Vector2(700,-360)
		editor.canvas.zoom = 1.8
		editor.canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"editor-mountain.png")
	editor.free()
	await process_frame
	print("WORLD_EDITOR_TESTS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
func find_editor_node(node: Node,id: String) -> Node3D:
	if node.get_meta("editor_id","") == id: return node
	for child in node.get_children():
		var found := find_editor_node(child,id)
		if found != null: return found
	return null

# JSON numbers become floats; compare full structure and numeric values, not Variant storage tags.
func equivalent(a: Variant,b: Variant) -> bool:
	if DATA.number(a) and DATA.number(b): return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	return a == b