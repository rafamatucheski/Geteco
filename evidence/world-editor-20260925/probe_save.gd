extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var ui = load("res://addons/geteco_world_editor/WorldEditor.gd").new()
	ui.edits_path = "res://evidence/world-editor-20260925/probe_save.json"
	ui.draft_path = "res://evidence/world-editor-20260925/probe_draft.json"
	root.add_child(ui)
	await process_frame
	ui._place("tree",Vector2(53,112))
	var id = ui.canvas.selected_id
	var spin = ui.properties.find_children("*","SpinBox",true,false)[0]
	spin.get_line_edit().grab_focus()
	spin.get_line_edit().text = "57"
	print("SPIN_APPLY ",spin.has_method("apply")," parent ",spin.get_line_edit().get_parent().get_class()," focus ",root.gui_get_focus_owner()," before ",spin.value)
	var key = InputEventKey.new()
	key.keycode = KEY_S
	key.ctrl_pressed = true
	key.pressed = true
	root.push_input(key,true)
	print("AFTER_SAVE ",ui.document.regions.harbor[id]," status ",ui.status.text," spin ",spin.value if is_instance_valid(spin) else -99)
	await process_frame
	print("AFTER_FRAME ",ui.document.regions.harbor[id]," saved ",ui.saved_document)
	quit()
