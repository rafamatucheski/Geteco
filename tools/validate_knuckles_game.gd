extends SceneTree
## Validação em jogo real da soqueira: soco por clipe (os dois lados), andar, correr e as transições.
## Rodar: -- --no-save --skip-arrival
var world; var player; var gameplay; var state
func key(letter: String) -> void:
	var e := InputEventKey.new(); e.keycode = letter.to_upper().unicode_at(0); e.physical_keycode = e.keycode; e.unicode = letter.unicode_at(0); e.pressed = true
	Input.parse_input_event(e); await process_frame
	e = e.duplicate(); e.pressed = false; Input.parse_input_event(e); await process_frame
func _initialize() -> void: _run.call_deferred()
func palm(side: String) -> Vector3: return player.combat_palm_position(side) - player.global_position
func _run() -> void:
	world = load("res://Main.tscn").instantiate(); root.add_child(world); current_scene = world
	for f in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	for i in 30: await physics_frame
	gameplay = world.gameplay; state = world.session.state; player = world.player
	for l in "dukenuke": await key(l)
	gameplay.equip_slot("knuckles")
	for i in 30: await physics_frame
	var gi = get_root().get_node("GameInput")
	var RIG = preload("res://gameplay/WeaponRigPose.gd")
	for a in OS.get_cmdline_user_args():
		if a == "ab=off": RIG.ab_punch_clip = false; RIG.ab_follow_clip = false
	print("MODO ", "anterior (A/B desligado)" if not RIG.ab_punch_clip else "novo")
	print("ARMA ", gameplay.equipped())
	# ---- A. socos parados: sequência do combo
	var wd := 0
	for punch in 6:
		Input.action_press("fire")
		await physics_frame
		Input.action_release("fire")
		if punch % 2 == 1: pass
		var clip_seen := ""; var max_right := 0.0; var max_left := 0.0; var jump := 0.0; var prev_r := palm("Right"); var prev_l := palm("Left")
		var mount_gap := 0.0
		for i in 14:
			await physics_frame
			if player.combat_clip != "" and clip_seen == "": clip_seen = player.combat_clip
			var r := palm("Right"); var l := palm("Left")
			max_right = maxf(max_right, Vector2(r.x, r.z).length()); max_left = maxf(max_left, Vector2(l.x, l.z).length())
			jump = maxf(jump, maxf((r - prev_r).length(), (l - prev_l).length()))
			prev_r = r; prev_l = l
			if is_instance_valid(player.combat_weapon_mount) and player.combat_weapon_mount.visible:
				mount_gap = maxf(mount_gap, (player.combat_weapon_mount.global_position - player.combat_palm_position("Right")).length())
		print("SOCO ", punch, " clipe=", clip_seen, " alcance_dir=", snapped(max_right, 0.01), " alcance_esq=", snapped(max_left, 0.01), " salto_max_por_quadro=", snapped(jump, 0.001), " mount_gap=", snapped(mount_gap, 0.001), " clip_ao_fim='", player.combat_clip, "'")
		for i in (12 if punch % 2 == 0 else 50): await physics_frame
	# ---- B. andar e correr, parado->andar->correr->parado
	var jump_t := 0.0
	var phases := [["parado", Vector2.ZERO, false, 40], ["andando", Vector2(0, 1), false, 70], ["correndo", Vector2(0, 1), true, 70], ["parado2", Vector2.ZERO, false, 50]]
	for ph in phases:
		gi.touch_move = ph[1]; gi.touch_sprint = ph[2]
		var prev_r := palm("Right"); var prev_l := palm("Left")
		var jump := 0.0; var zmin := 9.0; var zmax := -9.0
		for i in ph[3]:
			await physics_frame
			var r := palm("Right"); var l := palm("Left")
			if i > 15: zmin = minf(zmin, r.z); zmax = maxf(zmax, r.z)
			jump = maxf(jump, maxf((r - prev_r).length(), (l - prev_l).length()))
			prev_r = r; prev_l = l
		print("FASE ", ph[0], " vel=", snapped(player.velocity.length(), 0.1), " balanço_mao_dir_z=", snapped(zmax - zmin, 0.01), " salto_max_por_quadro=", snapped(jump, 0.001))
	gi.touch_move = Vector2.ZERO
	quit()
