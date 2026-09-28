extends "res://tests/test_world_editor_live_preview.gd"
const FACADE := preload("res://assets/maciota/GarageFacade.gd")
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var official_hash := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/garage_preview_test_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui._toggle_live_preview()
	check(await settled(0),"Garage area preview loads")
	if failures: ui.free(); quit(1); return
	var garage := tagged(ui.live_preview.geometry,"building/Garage")
	check(garage != null,"Maciota garage appears in side-by-side preview")
	if garage != null:
		check(garage.global_position.is_equal_approx(Vector3(48.875,0,93.4375)),"Garage matches production placement")
		var original := FACADE.new()
		root.add_child(original)
		var expected := original.find_children("*","MeshInstance3D",true,false)
		var actual := garage.find_children("*","MeshInstance3D",true,false)
		check(actual.size() == expected.size() and actual.size() > 0,"Complete authored facade survives snapshot")
		var matches := actual.size() == expected.size()
		for i in mini(actual.size(),expected.size()):
			matches = matches and actual[i].transform.is_equal_approx(expected[i].transform)
			matches = matches and actual[i].mesh.get_aabb().is_equal_approx(expected[i].mesh.get_aabb())
		check(matches,"Facade dimensions and details match production model")
		check(passive(garage),"Garage preview contains no gameplay behavior")
		original.free()
		ui.live_preview.focus = Vector3(48,0,99)
		ui.live_preview.view_size = 25
		ui.live_preview._pose()
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/world-editor-garage.png")
	check(DATA.disk_hash() == official_hash,"User world remains untouched")
	ui.free()
	print("WORLD_EDITOR_GARAGE ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
