extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const GROUND := preload("res://world/editing/WorldGroundFactory.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var ui := UI.new()
	var path := "res://evidence/world-editor-20260925/shape_ui_"+str(OS.get_process_id())
	ui.edits_path = path+".json"
	ui.draft_path = path+"_draft.json"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 5: await process_frame
	var id := "piece/cobra/cobra_footpath/2"
	ui._select(id)
	check(ui.canvas.objects[id].shape_editable,"Screenshot path supports points")
	var original_size: Vector2 = DATA.point(ui.canvas.objects[id].size)
	ui._resize_piece(0,original_size.x*.5)
	check(ui.document.regions.harbor[id].stretch == [.5,1.0],"Path width shrinks and is preserved by commit")
	ui._toggle_points()
	check(ui.canvas.edit_points and ui.document.regions.harbor[id].outline.size() >= 4,"Point mode starts with original path outline")
	var count: int = ui.document.regions.harbor[id].outline.size()
	ui._add_shape_point()
	check(ui.document.regions.harbor[id].outline.size() == count+1,"Insert point on actual path edge")
	var selected: int = ui.canvas.selected_point
	ui._remove_shape_point()
	check(ui.document.regions.harbor[id].outline.size() == count,"Remove chosen path point")
	ui.undo()
	check(ui.document.regions.harbor[id].outline.size() == count+1,"Undo point deletion")
	ui.redo()
	check(ui.document.regions.harbor[id].outline.size() == count,"Redo point deletion")
	check(ui.save(),"Save point edit and size")
	var loaded := DATA.read_document(ui.edits_path)
	check(loaded.error.is_empty() and loaded.document.regions.harbor[id].has("outline") and loaded.document.regions.harbor[id].has("stretch"),"Shape survives JSON reload")
	var invalid: Dictionary = loaded.document.regions.harbor[id].duplicate(true)
	invalid.outline = [[-2,-2],[2,2],[-2,2],[2,-2]]
	check(not DATA.validate_entity(invalid).is_empty(),"Reject crossed polygon")
	invalid.outline = [[0,0],[2,0],[2,2],[1,1],[0,2]]
	check(DATA.validate_entity(invalid).is_empty(),"Accept valid concave path")
	invalid.stretch = [0,1]
	check(not DATA.validate_entity(invalid).is_empty(),"Reject collapsed size")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440,900)
		ui.canvas.center = Vector2(450,87)
		ui.canvas.zoom = 18
		ui.canvas.queue_redraw()
		for child in root.find_children("*","CanvasLayer",true,false): child.hide()
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/world-editor-20260925/shape-editor.png")
	ui._select("")
	for i in 5: await process_frame
	ui.canvas.center = Vector2(443.125,83.75)
	ui.canvas.zoom = 24
	var start: Vector2 = ui.canvas.screen(Vector2(443.125,83.75))
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start
	ui.canvas._gui_input(down)
	var map_size: Vector2 = ui.canvas.size
	for i in 5: await process_frame
	check(ui.canvas.size == map_size,"Opening inspector does not move map during house drag")
	var move := InputEventMouseMotion.new()
	move.position = start+Vector2(96,24)
	ui.canvas._gui_input(move)
	down.pressed = false
	down.position = move.position
	ui.canvas._gui_input(down)
	check(ui.document.regions.harbor.has("building/PorchHouse"),"House drag commits through full editor")
	check(DATA.point(ui.canvas.objects["building/PorchHouse"].position).distance_to(Vector2(443.125,83.75)) > 3,"House moved more than three meters")
	ui._set_array("size",0,7.0)
	check(ui.document.regions.harbor["building/PorchHouse"].size[0] == 7,"House width can shrink")
	var factory := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
	var original := factory.build_building({"id":"PorchHouse","kind":"cobra_house","size":Vector2(13.75,10)})
	var changed := factory.build_building({"id":"PorchHouse","kind":"cobra_house","size":Vector2(7,10),"height_override":ui.document.regions.harbor["building/PorchHouse"].height})
	check(is_equal_approx(original.height,changed.height),"Moving and shrinking house preserves native height")
	original.free()
	changed.free()
	check(is_equal_approx(factory.resolved_height({"id":"ExchangeTower","kind":"office"}),8.0),"Catalog preserves native skyline override")
	var ground := DATA.new_entity("ground",Vector2(-180,100))
	ui._commit(ground)
	ui._toggle_points()
	check(ui.document.regions.harbor[ground.id].outline.size() == 4,"Terrain point mode starts with rectangle")
	ui._set_array("size",0,16)
	check(absf(float(ui.document.regions.harbor[ground.id].outline[0][0])) == 8,"Terrain resize also resizes edited outline")
	ui.free()
	var row := DATA.new_entity("ground",Vector2.ZERO)
	row.outline = [[-4,-4],[4,-4],[4,0],[0,0],[0,4],[-4,4]]
	var mesh := GROUND.create(row,Rect2(-64,-64,128,128))
	root.add_child(mesh)
	await physics_frame
	await process_frame
	var solid := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-2,2,2),Vector3(-2,-2,2),1))
	var hole := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2,2,2),Vector3(2,-2,2),1))
	check(not solid.is_empty() and hole.is_empty(),"Concave terrain collision respects cut-out")
	mesh.free()
	print("WORLD_SHAPE_UI checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
