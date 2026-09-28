extends SceneTree
## Real production scene, frozen after streaming settles. No save or editor simulation cost.
var scene: Node3D
var camera: Camera3D
var focus := Vector3(44.6875,0,112.5)
var area := "harbor"
var camera_size := 55.0
var capture := ""
var ready_preview := false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--x="): focus.x = arg.trim_prefix("--x=").to_float()
		elif arg.begins_with("--z="): focus.z = arg.trim_prefix("--z=").to_float()
		elif arg.begins_with("--region="): area = arg.trim_prefix("--region=")
		elif arg.begins_with("--size="): camera_size = clampf(arg.trim_prefix("--size=").to_float(),20,180)
		elif arg.begins_with("--capture="): capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--edits="):
			var loaded := preload("res://world/editing/WorldEditData.gd").read_document(arg.trim_prefix("--edits="))
			if not loaded.error.is_empty():
				push_error(loaded.error)
				quit(2)
				return
			Engine.set_meta("geteco_world_edit_document",loaded.document)
	scene = load("res://Main.tscn").instantiate()
	scene.set_meta("skip_arrival",true)
	scene.set_meta("skip_dispatch",true)
	root.add_child(scene)
	for i in 3600:
		await physics_frame
		if scene.session != null and scene.session.ready_for_play: break
	if scene.session == null or not scene.session.ready_for_play:
		push_error("Prévia: mundo não ficou pronto.")
		quit(1)
		return
	var region: Node3D = scene.production._mount_region(area,focus)
	if region.terrain != null: focus.y = region.terrain.surface_height_at(Vector2(focus.x,focus.z))
	scene.player.teleport(focus+Vector3.UP*.1)
	scene.player.controlled_automatically = true
	scene.player.hide()
	scene.production._commit_logical_region(area)
	region.set_focus(focus)
	var cell := Vector2i(floori(focus.x/64),floori(focus.z/64))
	var aspect := float(root.size.x)/maxf(1,float(root.size.y))
	var radius := clampi(ceili(camera_size*aspect*.5/64.0+.5),1,3)
	region.retention_radius = radius
	for x in range(-radius,radius+1):
		for z in range(-radius,radius+1): region._ensure_chunk(cell+Vector2i(x,z))
	for i in 8: await process_frame
	for overlay in scene.find_children("*","CanvasLayer",true,false): overlay.hide()
	root.get_node("V2Settings").show_fps = false
	root.get_node("V2Settings")._update_fps_overlay()
	scene.hud.hide()
	scene.diagnostic_label.hide()
	scene.session.weather.time_of_day = .45
	scene.session.weather.weather_state = 0
	scene.session.weather._update()
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_size
	camera.far = 2000
	root.add_child(camera)
	camera.make_current()
	_pose()
	ready_preview = true
	DisplayServer.window_set_title("Geteco · Prévia do mundo · Setas: câmera · Esc: fechar")
	for i in 12: await process_frame
	if not capture.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
		print("WORLD_EDITOR_PREVIEW_OK ",area," ",focus)
		quit()
func _pose() -> void:
	camera.position = focus+Vector3(0,180,145)
	camera.look_at(focus)
func _process(delta: float) -> bool:
	if not ready_preview: return false
	if Input.is_key_pressed(KEY_ESCAPE): quit()
	var direction := Vector3(float(Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_LEFT)),0,float(Input.is_key_pressed(KEY_DOWN))-float(Input.is_key_pressed(KEY_UP)))
	if not direction.is_zero_approx():
		focus += direction*delta*camera.size*.5
		var region: Node3D = scene.production.regions.get(area)
		if region != null:
			region.set_focus(focus)
			region._process(0)
		_pose()
	return false
