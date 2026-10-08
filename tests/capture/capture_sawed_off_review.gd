extends "res://tests/capture/capture_melee_filmstrip.gd"
## Comparative rig filmstrips; the same capture works before the break-action
## presentation module exists. Main.tscn supplies the integrated evidence.
var _sawed_parts: Script

func _run() -> void:
	var output := "res://evidence/weapon-review-20261007/rig-after.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="): output = arg.trim_prefix("out=")
	if "--baseline-sources" in OS.get_cmdline_user_args():
		for file in ["WeaponPoseData", "WeaponRigPose", "WeaponPresentation3D", "WeaponFinish3D", "ArsenalWeapon3D"]:
			var old_path: String = "res://evidence/weapon-review-20261007/baseline-sources/" + file + ".gd"
			if not FileAccess.file_exists(old_path):
				push_error("Missing baseline " + old_path)
				quit(2)
				return
			var script: GDScript = load("res://gameplay/" + file + ".gd")
			script.source_code = FileAccess.get_file_as_string(old_path)
			if script.reload(true) != OK:
				quit(2)
				return
	if ResourceLoader.exists("res://gameplay/SawedOffPresentation.gd"):
		_sawed_parts = load("res://gameplay/SawedOffPresentation.gd")
	if DisplayServer.get_name() == "headless":
		push_error("This capture requires a rendered window")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	const CELL := Vector2i(360, 420)
	const COLUMNS := 8
	var view := SubViewport.new()
	view.size = CELL
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("273039")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("cad4df")
	environment.environment.ambient_light_energy = 0.72
	view.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -28, 0)
	key.light_energy = 1.35
	view.add_child(key)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.6
	view.add_child(camera)
	var focus := Vector3(0, 1.05, -0.25)
	camera.position = focus + Vector3(-2.7, 0.75, -1.45)
	camera.look_at(focus)
	var sheet := Image.create(CELL.x * COLUMNS, CELL.y * 3, false, Image.FORMAT_RGBA8)
	for row in 3:
		var actor = ACTOR.new()
		actor.is_player = true
		view.add_child(actor)
		actor.set_physics_process(false)
		await process_frame
		var gun := Node3D.new()
		view.add_child(gun)
		ARSENAL.build(gun, "sawed_off")
		var pose = POSE.new()
		_move = [Vector3.FORWARD, 6.5] if row == 1 else [Vector3.ZERO, 0.0]
		for tick in 50: _step(actor, pose, gun, "sawed_off", false, 0.0, false)
		var captured := 0
		for tick in 97:
			var progress := float(tick) / 96.0
			var aiming := row == 0 and tick >= 24
			if row == 0 and tick in [50, 80]: pose.attack("sawed_off")
			_step(actor, pose, gun, "sawed_off", row == 2, progress, aiming)
			if captured < COLUMNS and tick >= int(round(float(captured) * 96.0 / float(COLUMNS - 1))):
				await RenderingServer.frame_post_draw
				var frame := view.get_texture().get_image()
				frame.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, CELL), Vector2i(captured * CELL.x, row * CELL.y))
				captured += 1
		actor.queue_free()
		gun.queue_free()
		await process_frame
	var result := sheet.save_png(output)
	print("SAWED_REVIEW_CAPTURE ", ProjectSettings.globalize_path(output), " error=", result, " rows=idle-aim-fire,run,reload")
	quit(0 if result == OK else 1)

func _step(actor, pose, gun: Node3D, id: String, reloading: bool, progress: float, aiming := true) -> void:
	super._step(actor, pose, gun, id, reloading, progress, aiming)
	if id == "sawed_off" and _sawed_parts != null:
		_sawed_parts.update_parts(gun, float(actor.combat_weapon_pose.get("break_open", 0.0)))
