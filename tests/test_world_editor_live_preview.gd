extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var ui
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func settled(previous: int) -> bool:
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if ui.live_preview.worker_pid > 0 and not OS.is_process_running(ui.live_preview.worker_pid): break
		if ui.live_preview.applied_revision > previous and ui.live_preview.applied_revision == ui.live_preview.revision and ui.live_preview.submitted == ui.live_preview.desired: return true
	push_error("Preview timeout: "+ui.live_preview.message.text+" log="+ui.live_preview.folder+"/worker.log")
	return false
func tagged(root_node: Node, id: String) -> Node3D:
	if root_node.get_meta("editor_id","") == id: return root_node as Node3D
	for child in root_node.get_children():
		var found := tagged(child,id)
		if found != null: return found
	return null
func passive(node: Node) -> bool:
	if node.get_script() != null: return false
	if node is CollisionObject3D and (node.collision_layer != 0 or node.collision_mask != 0): return false
	for child in node.get_children():
		if not passive(child): return false
	return true
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var official_hash := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/live_test_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var row := DATA.new_entity("prop",Vector2(53,112))
	row.id = "new/live_preview_prop"
	ui._commit(row)
	ui._toggle_live_preview()
	check(await settled(0),"Initial preview loads actual region")
	if failures: ui.free(); quit(1); return
	var panel = ui.live_preview
	var pid: int = panel.worker_pid
	var first_revision: int = panel.applied_revision
	var prop := tagged(panel.geometry,row.id)
	check(prop != null,"Unsaved object is visible in generated scene")
	if prop != null: check(is_equal_approx(prop.global_position.x,53),"3D object matches initial 2D position")
	check(panel.geometry.get_script() == null,"Snapshot has no world gameplay script")
	check(passive(panel.geometry),"All preview nodes are free of gameplay scripts and active collisions")
	check(ui.canvas.get_global_rect().end.x <= panel.get_global_rect().position.x,"2D and 3D are side by side")
	panel.request(ui.document,Vector2(55,113),"harbor")
	check(panel.applied_revision == first_revision and panel.focus.x == 55,"Nearby focus updates immediately without rebuilding")
	ui._sync_live_preview()
	ui._set_array("position",0,57)
	if "--supersede-loading" in OS.get_cmdline_user_args():
		var deadline := Time.get_ticks_msec()+90000
		while panel.loading_path.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		check(not panel.loading_path.is_empty(),"Supersede test catches a real threaded read")
		panel.request(ui.document,Vector2(58,112),"harbor")
		panel.ready_at = Time.get_ticks_msec()+60000
		while not panel.loading_path.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		for poll in 3: panel._poll()
		check(panel.loading_path.is_empty(),"Consumed response cannot reload a deleted snapshot during debounce")
		panel.ready_at = 0
	check(await settled(first_revision),"Moving the object automatically updates 3D")
	check(panel.worker_pid == pid,"Edit reuses persistent builder")
	prop = tagged(panel.geometry,row.id)
	check(prop != null and is_equal_approx(prop.global_position.x,57),"Updated geometry is at the new location")
	var next_revision: int = panel.applied_revision
	ui.undo()
	check(await settled(next_revision),"Undo automatically updates 3D")
	prop = tagged(panel.geometry,row.id)
	check(prop != null and is_equal_approx(prop.global_position.x,53),"Undo restores 3D object")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var old_size: float = panel.view_size
	panel._camera_input(wheel)
	check(panel.view_size < old_size,"Preview camera zoom is interactive")
	var old_yaw: float = panel.yaw
	panel.orbiting = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20,0)
	panel._camera_input(motion)
	panel.orbiting = false
	check(panel.yaw != old_yaw,"Preview camera can orbit")
	ui.hide()
	check(panel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Hidden editor suspends 3D rendering")
	ui.show()
	for dimensions in [Vector2i(640,480),Vector2i(1024,640),Vector2i(1440,900)]:
		root.size = dimensions
		for i in 5: await process_frame
		check(ui.canvas.size.x >= 240 and panel.size.x >= 260,"Both views remain usable at "+str(dimensions))
		check(panel.get_global_rect().end.x <= ui.get_global_rect().end.x+1,"3D stays within editor bounds")
	for child in root.find_children("*","CanvasLayer",true,false): child.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/world-editor-live.png")
	if "--mountain" in OS.get_cmdline_user_args():
		var previous: int = panel.applied_revision
		panel.request(ui.document,Vector2(600,-350),"mountain")
		check(await settled(previous),"Same preview switches to mountain without restarting")
		var reference = preload("res://world/editing/EditableRegion.gd").build_region("mountain")
		reference.prepare_data()
		check(panel.built_area == "mountain" and is_equal_approx(panel.focus.y,reference.terrain.surface_height_at(Vector2(600,-350))),"Mountain camera follows actual terrain height")
		reference.free()
		check(panel.worker_pid == pid,"Region switch keeps the same builder")
		for i in 6: await process_frame
		await RenderingServer.frame_post_draw
		check(panel.geometry.find_children("*","MeshInstance3D",true,false).size() > 0,"Mountain snapshot contains rendered geometry")
		root.get_texture().get_image().save_png("res://evidence/world-editor-live-mountain.png")
	check(DATA.disk_hash() == official_hash,"Preview never saves official map")
	if "--recover-worker" in OS.get_cmdline_user_args():
		var previous: int = panel.applied_revision
		OS.kill(pid)
		for i in 30:
			await process_frame
			if not OS.is_process_running(pid): break
		panel._poll()
		check(await settled(previous),"Preview recovers from worker exit with current unsaved document")
		check(panel.worker_pid != pid and panel.recovery_attempted,"Recovery starts a new builder once")
		pid = panel.worker_pid
		var recovered := tagged(panel.geometry,row.id)
		check(recovered != null and is_equal_approx(recovered.global_position.x,53),"Recovery preserves unsaved object after undo")
	if "--close-loading" in OS.get_cmdline_user_args():
		panel.request(ui.document,Vector2(120,150),"harbor")
		var deadline := Time.get_ticks_msec()+90000
		while panel.loading_path.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		check(not panel.loading_path.is_empty(),"Close test reaches an in-flight resource load")
	ui._toggle_live_preview()
	check(not is_instance_valid(panel),"Closing frees the viewport immediately")
	check(not OS.is_process_running(pid),"Closing preview stops only its builder")
	check(not ui.live_toggle.button_pressed,"Closing restores 2D mode")
	ui.free()
	print("WORLD_LIVE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
