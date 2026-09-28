extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
var checks := 0
var failures: Array[String] = []
var ui
var view: SubViewport
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func settle() -> void:
	for i in 5: await process_frame
func run() -> void:
	view = SubViewport.new()
	view.size = Vector2i(1440,900)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	ui = UI.new()
	var folder := "res://evidence/world-editor-20260925/"
	ui.edits_path = folder+"layout_"+str(OS.get_process_id())+".json"
	ui.draft_path = folder+"layout_draft_"+str(OS.get_process_id())+".json"
	view.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle()
	check(not ui.properties_scroll.visible,"Empty inspector does not consume map space")
	check(ui.canvas.size.x > 1440*.80,"Without selection map uses more than 80 percent of width")
	ui._select("piece/neco/Office")
	ui._select("")
	await settle()
	check(not ui.properties_scroll.visible,"Deselecting hides the empty inspector")
	ui._select("piece/neco/Office")
	ui.canvas.center = Vector2(-47,35)
	ui.canvas.zoom = 9
	var center: Vector2 = ui.canvas.center
	var zoom: float = ui.canvas.zoom
	for dimensions in [Vector2i(1920,1080),Vector2i(1440,900),Vector2i(1024,640),Vector2i(720,480),Vector2i(640,480)]:
		view.size = dimensions
		await settle()
		check(ui.size.x <= dimensions.x+.5 and ui.size.y <= dimensions.y+.5,"Editor fits "+str(dimensions))
		var save_rect: Rect2 = ui.save_button.get_global_rect()
		check(save_rect.position.x >= 0 and save_rect.end.x <= dimensions.x+.5 and save_rect.end.y <= dimensions.y,"Save button reachable "+str(dimensions))
		for button in ui.actions_bar.get_children():
			check(button.get_global_rect().end.x <= dimensions.x+.5,"Toolbar action fits: "+str(button.name)+str(dimensions))
		check(ui.canvas.size.x >= dimensions.x*(.60 if dimensions.x < 1100 else .62),"Map has priority in width "+str(dimensions))
		check(ui.canvas.size.y >= dimensions.y*.72,"Map has priority in height "+str(dimensions))
		check(ui.library_panel.visible != ui.properties_scroll.visible if dimensions.x < 1100 else ui.library_panel.visible and ui.properties_scroll.visible,"Responsive sidebar arrangement "+str(dimensions))
		print("LAYOUT ",dimensions," map=",ui.canvas.size," actions_height=",ui.actions_bar.size.y," minimum=",ui.get_combined_minimum_size())
		if DisplayServer.get_name() != "headless" and dimensions.x in [1440,720]:
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png(folder+"layout-"+str(dimensions.x)+".png")
	ui._select("piece/neco/Office")
	await settle()
	check(ui.properties_scroll.visible and not ui.library_panel.visible,"Selection opens properties in narrow layout")
	ui.library_toggle.pressed.emit()
	await settle()
	check(ui.library_panel.visible and not ui.properties_scroll.visible,"Assets toggle switches narrow sidebar")
	ui.focus_toggle.pressed.emit()
	await settle()
	check(not ui.library_panel.visible and not ui.properties_scroll.visible,"Expand hides both sidebars")
	check(ui.canvas.size.x >= view.size.x*.97 and ui.save_button.visible,"Expanded map uses full width and retains save")
	check(ui.canvas.center == center and ui.canvas.zoom == zoom,"Layout changes preserve map position and zoom")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		view.get_texture().get_image().save_png(folder+"layout-expanded.png")
	ui.focus_toggle.pressed.emit()
	await settle()
	check(ui.library_panel.visible,"Restoring panels preserves previous choice")
	ui.library_toggle.pressed.emit()
	await settle()
	check(not ui.library_requested and ui.properties_scroll.visible,"Closing a sidebar gives room to the other")
	view.size = Vector2i(1440,900)
	await settle()
	check(not ui.library_panel.visible and ui.properties_scroll.visible,"Explicit collapse persists across resizing")
	ui._layout_option(0)
	check(ui.canvas.grid == 0,"Grid remains usable from compact menu")
	ui._layout_option(0)
	check(ui.canvas.grid == 1,"Grid can be restored")
	ui._layout_option(1)
	check(not ui.free_placement,"Placement option remains usable")
	ui.status.text = "Mensagem de gravação longa. ".repeat(50)
	await settle()
	check(ui.size.x <= view.size.x+.5,"Long status cannot stretch editor")
	view.free()
	await process_frame
	print("WORLD_LAYOUT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
