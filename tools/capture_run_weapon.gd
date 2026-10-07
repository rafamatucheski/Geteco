extends SceneTree
## Captura o jogador correndo com uma arma. Args: weapon=knuckles tag=antes dir=down
func _initialize() -> void: _run.call_deferred()
func key(letter: String) -> void:
	var e := InputEventKey.new(); e.keycode = letter.to_upper().unicode_at(0); e.physical_keycode = e.keycode; e.unicode = letter.unicode_at(0); e.pressed = true
	Input.parse_input_event(e); await process_frame
	e = e.duplicate(); e.pressed = false; Input.parse_input_event(e); await process_frame
func _run() -> void:
	var weapon := "knuckles"; var tag := "antes"; var dir := Vector2(0, 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("weapon="): weapon = a.trim_prefix("weapon=")
		if a.begins_with("tag="): tag = a.trim_prefix("tag=")
		if a == "dir=right": dir = Vector2(1, 0)
		if a == "dir=left": dir = Vector2(-1, 0)
		if a == "dir=up": dir = Vector2(0, -1)
	var world = load("res://Main.tscn").instantiate(); root.add_child(world); current_scene = world
	for f in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	for i in 30: await physics_frame
	for l in "dukenuke": await key(l)
	print("EQUIP ", world.gameplay.equip_slot(weapon), " ", world.gameplay.equipped())
	for i in 30: await physics_frame
	var player = world.player
	var gi = get_root().get_node("GameInput")
	gi.touch_move = dir; gi.touch_sprint = true
	var cam := Camera3D.new(); world.add_child(cam); cam.fov = 28.0
	for i in 12: await physics_frame
	cam.current = true
	for s in 8:
		for i in 3: await physics_frame
		var side: Vector3 = player.velocity.normalized().cross(Vector3.UP)
		cam.global_position = player.global_position + Vector3.UP * 1.0 + side * 6.5
		cam.look_at(player.global_position + Vector3.UP * 0.95)
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/ual-dante/game/run_%s_%s_%d.png" % [weapon, tag, s]))
	quit()
