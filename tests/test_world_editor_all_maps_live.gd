extends "res://tests/test_world_editor_live_preview.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	create_timer(300).timeout.connect(func(): push_error("ALL_MAPS_LIVE timeout"); quit(3))
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/all_maps_live_%d.json"%OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui._switch_region("desert")
	ui.canvas.center = Vector2(-315,-914.2)
	ui._set_view_mode(2)
	check(await settled(0),"Desert live geometry loads")
	if failures: ui.free(); quit(1); return
	check(passive(ui.live_preview.geometry),"Desert snapshot has no active scripts or collisions")
	var bench_id := ""
	for id in ui.canvas.objects:
		var row: Dictionary = ui.canvas.objects[id]
		if row.get("editor_region","")=="desert" and row.get("kind","")=="rest_bench": bench_id=id; break
	check(not bench_id.is_empty() and ui.live_preview.edit_control.groups.has(bench_id),"Authored bench selectable in 3D")
	if not bench_id.is_empty():
		ui._select(bench_id)
		var original: Dictionary = ui.canvas.objects[bench_id].duplicate(true)
		var change: Dictionary = original.duplicate(true)
		change.position[0] = float(change.position[0])-3.0
		change.rotation = 30.0
		var previous: int = ui.live_preview.applied_revision
		ui._commit(change)
		check(await settled(previous),"Move and rotate updates actual geometry")
		var bench := tagged(ui.live_preview.geometry,bench_id)
		check(bench!=null and is_equal_approx(bench.global_position.x,float(change.position[0])),"3D geometry matches saved transform")
		ui.undo()
		check(DATA.point(ui.canvas.objects[bench_id].position).is_equal_approx(DATA.point(original.position)),"Undo restores authored placement")
		ui.redo()
		check(is_equal_approx(float(ui.canvas.objects[bench_id].rotation),30),"Redo restores rotation")
	var prop := DATA.new_entity("prop",Vector2(-390,-940))
	prop.model = "desert_cactus"
	prop.id = "new/all_maps_cactus"
	prop.size = [1.5,1.5]
	ui._commit(prop)
	check(ui.document.regions.desert.has(prop.id),"Library prop can be placed in desert")
	var previous: int = ui.live_preview.applied_revision
	check(await settled(previous),"New desert prop appears in live view")
	check(tagged(ui.live_preview.geometry,prop.id)!=null,"New cactus can be selected in 3D")
	ui.save()
	check(DATA.read_document(ui.edits_path).document.regions.desert.has(prop.id),"World save persists desert additions")
	DirAccess.make_dir_recursive_absolute("res://evidence/editor-all-maps-20261006")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/editor-all-maps-20261006/desert-editor.png")
	ui.canvas.selected_id = ""
	var skate_center: Vector3 = preload("res://activities/skate/SkateParkLayout.gd").CENTER
	ui.canvas.center = Vector2(skate_center.x,skate_center.z)
	previous = ui.live_preview.applied_revision
	ui._sync_live_preview()
	check(await settled(previous),"Switch from desert to Harbor")
	check(tagged(ui.live_preview.geometry,"context/harbor/session/skate_park")!=null,"Session-owned skate park visible in 3D")
	var course := preload("res://activities/mountain_downhill/MountainDownhillCourse.gd").new()
	ui.canvas.center = Vector2(course.grid(0).origin.x,course.grid(0).origin.z)
	previous = ui.live_preview.applied_revision
	ui._sync_live_preview()
	check(await settled(previous),"Switch to mountain")
	check(tagged(ui.live_preview.geometry,"context/mountain/session/downhill")!=null,"Downhill course markers visible in 3D")
	check(DATA.disk_hash()==official,"Official world document untouched")
	ui.free()
	print("ALL_MAPS_LIVE ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
