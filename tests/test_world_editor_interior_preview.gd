extends "res://tests/test_world_editor_live_preview.gd"

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/interior_preview_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui._switch_interior("harbor_bank")
	check(await settled(0),"Bank interior loads through the actual worker and production builder")
	if failures: ui.free(); quit(1); return
	var panel = ui.live_preview
	var pid: int = panel.worker_pid
	check(panel.built_interior == "harbor_bank","The rendered snapshot identifies the selected room")
	check(ui.canvas.objects.size() > 10,"Interior furniture and structure populate the 2D object catalog")
	check(panel.edit_control.groups.size() > 10,"Interior furniture and structure are selectable in 3D")
	check(passive(panel.geometry),"Interior snapshot has no active gameplay or collision simulation")
	var physical := false
	for node in panel.geometry.find_children("*","StaticBody3D",true,false):
		if int(node.get_meta("world_snapshot_collision_layer",0)) != 0: physical = true
	check(physical,"Original authored collision layers remain available for copied furniture")
	var previous: int = panel.applied_revision
	ui._switch_interior("maciota")
	check(await settled(previous),"The same worker switches to the real Maciota workshop")
	check(panel.built_interior == "maciota" and panel.worker_pid == pid,"Interior changes reuse the persistent worker")
	check(panel.geometry.find_child("Maciota",true,false) == null and panel.geometry.find_child("Mechanic",true,false) == null,"Protected garage residents never become editable scenery")
	check(panel.edit_control.groups.size() > 10,"Workshop furniture is selectable independently")
	var count: int = panel.manifest_read_count
	for frame in 20: await process_frame
	check(panel.manifest_read_count == count,"An idle room does not repeatedly parse its geometry manifest")
	check(DATA.disk_hash() == official,"Previewing interiors never saves official game data")
	ui.free()
	check(not OS.is_process_running(pid),"Closing an interior stops its own worker")
	print("WORLD_EDITOR_INTERIOR_PREVIEW checks=",checks," failures=",failures)
	# Sai de propósito logo depois do free: todos os recursos aposentados já precisam
	# pertencer à SceneTree em vez de a um coletor adiado órfão.
	quit(1 if failures else 0)
