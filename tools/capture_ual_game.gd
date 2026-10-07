extends SceneTree
## Captura, no jogo real (Main.tscn), o tiro e a recarga da pistola com os clipes da UAL.
## Rodar: -- --no-save --skip-arrival
var world; var player; var gameplay; var state
func frames(n: int) -> void:
	for i in n: await physics_frame
func shot(name: String) -> void:
	await process_frame; await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/ual-dante/game/%s.png" % name))
func key(letter: String) -> void:
	var e := InputEventKey.new(); e.keycode = letter.to_upper().unicode_at(0); e.physical_keycode = e.keycode; e.unicode = letter.unicode_at(0); e.pressed = true
	Input.parse_input_event(e); await process_frame
	e = e.duplicate(); e.pressed = false; Input.parse_input_event(e); await process_frame
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	world = load("res://Main.tscn").instantiate(); root.add_child(world); current_scene = world
	for f in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	await frames(30)
	gameplay = world.gameplay; state = world.session.state; player = world.player
	for l in "dukenuke": await key(l)
	var e := InputEventKey.new(); e.keycode = KEY_1; e.physical_keycode = KEY_1; e.pressed = true
	Input.parse_input_event(e); await process_frame; e = e.duplicate(); e.pressed = false; Input.parse_input_event(e); await process_frame
	await frames(20)
	print("ARMA ", state.equipped_weapon, " vel ", player.velocity.length())
	# alvo à frente, mira e tiro parado
	var tgt: Vector3 = player.global_position + Vector3.RIGHT * 8.0
	var flat := Vector3.RIGHT
	var right: Vector3 = world.camera.global_basis.x; var down: Vector3 = world.camera.global_basis.z
	right.y = 0; down.y = 0
	get_root().get_node("GameInput").touch_aim = Vector2(flat.dot(right.normalized()), flat.dot(down.normalized()))
	await frames(2)
	Input.action_press("aim"); await frames(30)
	await shot("g_aim")
	Input.action_press("fire")
	for i in 6:
		await physics_frame
		print("TIRO ", i, " clip=", player.combat_clip, " t=", snapped(player.combat_clip_time, 0.01), " w=", snapped(player._combat_weight, 0.01))
		if i == 1 or i == 3: await shot("g_tiro_%d" % i)
	Input.action_release("fire"); await frames(20)
	gameplay.reload_weapon()
	for i in 6:
		await frames(15)
		print("RECARGA ", i, " clip=", player.combat_clip, " t=", snapped(player.combat_clip_time, 0.01), " w=", snapped(player._combat_weight, 0.01))
		if i == 1 or i == 3: await shot("g_recarga_%d" % i)
	Input.action_release("aim")
	quit()
