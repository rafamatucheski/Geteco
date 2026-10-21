extends "res://tests/test_world_editor_live_preview.gd"
const INTERIORS := preload("res://addons/geteco_world_editor/WorldInteriorCatalog.gd")

func free_point(exclude: Array = []) -> Vector2:
	var definition := INTERIORS.definition(ui.active_interior)
	var extent: Vector2 = definition.get("size",Vector2(14,10))
	for z in range(-floori(extent.y*.5)+2,floori(extent.y*.5)-1):
		for x in range(-floori(extent.x*.5)+2,floori(extent.x*.5)-1):
			var point := Vector2(x,z)
			var blocked := false
			for other in exclude:
				if point.distance_to(other) < 2: blocked = true; break
			if blocked: continue
			for field in ["spawn","exit"]:
				var anchor: Vector3 = definition.get(field,Vector3.INF)
				if anchor.is_finite() and point.distance_to(Vector2(anchor.x,anchor.z)) < 1.6: blocked = true
			for npc in definition.get("npcs",[]):
				var anchor: Vector3 = npc.get("local_position",Vector3.INF)
				if anchor.is_finite() and point.distance_to(Vector2(anchor.x,anchor.z)) < 1.6: blocked = true
			if blocked: continue
			for row in ui.canvas.objects.values():
				for part in row.get("parts",[]):
					if float(part[4]) <= .08 or float(part[4]) > 2.1: continue
					if Rect2(float(part[0]),float(part[1]),float(part[2]),float(part[3])).grow(.9).has_point(point): blocked = true; break
				if blocked: break
			if not blocked: return point
	return Vector2.INF

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/interior_flow_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()]
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui._switch_interior("harbor_bank")
	check(await settled(0),"The actual interior selector loads the bank through its worker")
	if failures: ui.free(); quit(1); return
	var panel = ui.live_preview
	var pid: int = panel.worker_pid
	var first := free_point()
	var second := free_point([first])
	var third := free_point([first,second])
	check(first.is_finite() and second.is_finite() and third.is_finite(),"The room has three furniture destinations outside doors, residents and existing solids")
	if failures: ui.free(); quit(1); return
	var before: int = panel.applied_revision
	ui._place("prop",first)
	var original: String = ui.canvas.selected_id
	ui._set_array("position",0,second.x)
	ui._set_array("position",1,second.y)
	ui._set_value("scale",1.25)
	check(await settled(before),"Creating, moving and resizing furniture rebuilds the real room")
	check(ui.document.interiors.harbor_bank.has(original),"The added furniture remains in the bank scope")
	var placed := tagged(panel.geometry,original)
	check(placed != null and Vector2(placed.global_position.x,placed.global_position.z).distance_to(second) < .02,"Rendered furniture reaches the edited room coordinates")
	check(placed != null and is_equal_approx(placed.scale.x,1.25),"Rendered furniture uses the edited scale")
	check(not FileAccess.file_exists(ui.edits_path),"Edits and their visible preview do not publish the world")
	ui._select(original)
	check(ui._copy(),"The UI clipboard copies the selected furniture")
	ui._paste()
	before = panel.applied_revision
	ui._place("prop",third)
	var copy: String = ui.canvas.selected_id
	check(await settled(before),"Pasted furniture is built by the same interior worker")
	check(copy != original and ui.document.interiors.harbor_bank.has(copy),"Paste gives furniture an independent identity")
	check(is_equal_approx(ui.document.interiors.harbor_bank[copy].scale,1.25),"Clipboard retains furniture size")
	before = panel.applied_revision
	ui._delete()
	check(await settled(before),"Deleting furniture rebuilds the room")
	check(not ui.canvas.objects.has(copy) and tagged(panel.geometry,copy) == null,"Deletion removes both the UI item and rendered furniture")
	before = panel.applied_revision
	ui.undo()
	check(await settled(before),"Undo restores the deleted furniture through the real worker")
	check(ui.canvas.objects.has(copy) and tagged(panel.geometry,copy) != null,"Undo restores the same object identity")
	before = panel.applied_revision
	ui._select(copy)
	ui._delete()
	check(await settled(before),"Final layout retains only the intended furniture")
	ui._select(original)
	ui._set_value("scale",1.2)
	check(not str(ui.interior_validation.get("harbor_bank/0","")).is_empty(),"New changes require validation of their own room and floor")
	var building := ""
	for definition in INTERIORS.definitions():
		if int(definition.get("floor_count",0)) > 0: building = str(definition.id); break
	check(not building.is_empty(),"The selector includes a real building with multiple floors")
	if failures: ui.free(); quit(1); return
	before = panel.applied_revision
	ui._switch_interior(building)
	check(await settled(before),"Switching rooms loads a different production interior")
	check(not ui.canvas.objects.has(original),"Furniture from another room is isolated from the current canvas")
	before = panel.applied_revision
	ui.interior_floor_selector.value = 1
	check(await settled(before),"The floor selector loads the real next floor")
	check(panel.built_interior == building and panel.built_floor == 1,"The rendered snapshot identifies the selected building and floor")
	check(not ui.save() and not FileAccess.file_exists(ui.edits_path),"Validation from another room or floor cannot publish pending bank edits")
	before = panel.applied_revision
	ui._switch_interior("harbor_bank")
	check(await settled(before),"Returning restores the edited bank from its draft")
	check(ui.canvas.objects.has(original) and not ui.canvas.objects.has(copy),"Room changes preserve independent additions and deletions")
	check(ui.save(),"Only explicit Save publishes the validated multi-room document")
	var loaded := DATA.read_document(ui.edits_path)
	check(loaded.error.is_empty() and loaded.document.interiors.harbor_bank.has(original),"Saved furniture survives an actual file reload")
	check(is_equal_approx(loaded.document.interiors.harbor_bank[original].scale,1.2),"Saved values preserve the final interior edit")
	check(loaded.document.regions.harbor.is_empty() and loaded.document.regions.mountain.is_empty(),"Room editing never inserts local coordinates into exterior maps")
	check(DATA.disk_hash() == official,"The entire workflow leaves the official world unchanged")
	ui.free()
	check(not OS.is_process_running(pid),"Closing the complete workflow stops its worker")
	print("WORLD_EDITOR_INTERIOR_FLOW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
