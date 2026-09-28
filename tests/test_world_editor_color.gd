extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func color_button(ui: Node) -> ColorPickerButton:
	for child in ui.properties.get_children():
		if child is ColorPickerButton: return child
	return null
func wait_live(ui: Node, previous: int) -> bool:
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if ui.live_preview.applied_revision > previous: return true
		if ui.live_preview.worker_pid > 0 and not OS.is_process_running(ui.live_preview.worker_pid): return false
	return false
func run() -> void:
	var ui := UI.new()
	ui.edits_path = "res://.godot/color_test_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var row := DATA.new_entity("building",Vector2(50,120))
	row.model = "cobra_house"
	ui._commit(row)
	if "--live" in OS.get_cmdline_user_args():
		ui._toggle_live_preview()
		check(await wait_live(ui,0),"Adding a house loads in side-by-side preview")
	var picker := color_button(ui)
	check(picker != null,"Added house exposes color control")
	var before: int = ui.history.size()
	picker.color = Color("a13458")
	picker.popup_closed.emit()
	check(picker.is_inside_tree() and not picker.is_queued_for_deletion(),"Closing signal does not detach its own native popup/control")
	await process_frame
	await process_frame
	check(ui.document.regions.harbor[row.id].color == "a13458","Color commits after popup event finishes")
	check(ui.history.size() == before+1,"One color change creates one undo entry")
	if "--live" in OS.get_cmdline_user_args():
		var previous: int = ui.live_preview.applied_revision
		check(await wait_live(ui,previous),"Changing house color updates live preview without restarting")
		check(ui.live_preview.submitted.document.regions.harbor[row.id].color == "a13458","3D builder receives the chosen house color")
	ui.undo()
	check(ui.document.regions.harbor[row.id].color == row.color,"Undo restores original color")
	ui.redo()
	check(ui.document.regions.harbor[row.id].color == "a13458","Redo restores chosen color")
	var another := DATA.new_entity("building",Vector2(-300,400))
	ui._commit(another)
	ui._select(row.id)
	picker = color_button(ui)
	picker.color = Color("2468ab")
	picker.popup_closed.emit()
	ui._select(another.id)
	await process_frame
	await process_frame
	check(ui.document.regions.harbor[row.id].color == "2468ab","Deferred edit belongs to original house")
	check(ui.document.regions.harbor[another.id].color == another.color,"Changing selection cannot recolor a different house")
	check(ui.canvas.selected_id == another.id,"Deferred color keeps current selection")
	ui._select(row.id)
	picker = color_button(ui)
	picker.color = Color("123456")
	picker.popup_closed.emit()
	ui._delete()
	await process_frame
	check(ui.document.regions.harbor[row.id].deleted,"Stale popup cannot resurrect deleted house")
	ui._select(another.id)
	picker = color_button(ui)
	if DisplayServer.get_name() != "headless":
		for i in 3:
			picker = color_button(ui)
			picker.get_popup().popup()
			await process_frame
			picker.color = Color(["aa3377","44aa66","3355cc"][i])
			picker.get_popup().hide()
			await process_frame
			await process_frame
		check(ui.document.regions.harbor[another.id].color == "3355cc","Real popup can open/change/close repeatedly without crashing")
	check(ui.save(),"New house and color save successfully")
	ui.free()
	print("WORLD_COLOR checks=",checks," failures=",failures)
	quit(1 if failures else 0)
