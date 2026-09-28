extends "res://tests/test_world_editor_live_preview.gd"
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var official_hash := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/facade_test_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var row := DATA.new_entity("building",Vector2(5,95))
	row.model = "urban_infill"
	row.size = [6,9]
	row.height = 12
	row.color = "91634e"
	ui._commit(row)
	ui._toggle_live_preview()
	check(await settled(0),"Brick building preview loads")
	if failures: ui.free(); quit(1); return
	var preview := tagged(ui.live_preview.geometry,row.id)
	check(preview != null,"Added building exists in preview")
	var original := FACTORY.build_building({"id":str(row.id).replace("/","_"),"kind":row.model,"size":Vector2(6,9),"height_override":12,"color":row.color})
	root.add_child(original)
	var expected := original.find_children("*","MultiMeshInstance3D",true,false)
	var actual := preview.find_children("*","MultiMeshInstance3D",true,false)
	check(expected.size() > 0 and actual.size() == expected.size(),"All facade material batches survive snapshot")
	var matching := actual.size() == expected.size()
	var instances := 0
	for index in mini(actual.size(),expected.size()):
		var a: MultiMesh = actual[index].multimesh
		var b: MultiMesh = expected[index].multimesh
		matching = matching and a.instance_count == b.instance_count
		for slot in mini(a.instance_count,b.instance_count):
			instances += 1
			matching = matching and a.get_instance_transform(slot).is_equal_approx(b.get_instance_transform(slot))
	check(matching and instances > 100,"Windows, door and trim retain every production transform")
	check(passive(preview),"Facade snapshot remains passive")
	original.free()
	ui.live_preview.view_size = 30
	ui.live_preview._pose()
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/world-editor-facades.png")
	check(DATA.disk_hash() == official_hash,"User world remains untouched")
	ui.free()
	print("WORLD_EDITOR_FACADES ",checks," checks ",failures," failures; ",instances," detail instances")
	quit(1 if failures else 0)
