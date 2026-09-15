extends SceneTree

var failures: Array[String] = []
var shots := [0]

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func empty_sounds(player: Node) -> int:
	var count := 0
	for child in player.get_children():
		if child is AudioStreamPlayer2D and child.stream == ProceduralAudio.get_empty_weapon_stream():
			if child.bus != &"SFX" or not child.playing:
				check(false, "empty feedback must play through the SFX bus")
			count += 1
	return count

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player := preload("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.weapon_fired.connect(func(): shots[0] += 1)
	await process_frame
	var target := player.global_position + Vector2(300, 0)
	var stream := ProceduralAudio.get_empty_weapon_stream()
	var peak := 0
	for i in stream.data.size() / 2: peak = maxi(peak, absi(stream.data.decode_s16(i * 2)))
	check(stream.get_length() >= 0.1 and stream.get_length() < 0.3 and peak > 4000 and peak < 32767, "dry click has audible unclipped samples and a short duration")
	check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "empty sound never loops")
	if "--export-sound" in OS.get_cmdline_user_args():
		stream.save_to_wav("D:/geteco/artifacts/empty-weapon-click.wav")
	player.active_weapon_id = "pistol"
	player.weapon_ammo.pistol = {"clip": 0, "reserve": 0}
	player.weapon_wheel.notice = ""
	player._shoot_towards(target)
	check(empty_sounds(player) == 1, "empty pistol produces a dry click")
	check(shots[0] == 0 and player.weapon_ammo.pistol == {"clip":0,"reserve":0}, "dry fire produces no shot and changes no ammunition")
	check(player.weapon_wheel.notice.is_empty(), "empty pistol shows no text notification")
	player.active_weapon_id = "smg"
	player.weapon_ammo.smg = {"clip": 0, "reserve": 0}
	Input.action_press("fire")
	for i in 90:
		player.fire_cooldown = 0.0
		player._handle_weapon_fire()
	check(empty_sounds(player) == 1, "held automatic trigger does not spam dry clicks")
	Input.action_release("fire")
	player._handle_weapon_fire()
	player._shoot_towards(target)
	check(empty_sounds(player) == 2, "releasing and pressing again allows another click")
	# All ammo-based weapons take the same empty path, including throwables.
	for id in ["magnum", "shotgun", "sawed_off", "ak47", "m4a1", "rpg", "flamethrower", "grenade"]:
		player.active_weapon_id = id
		player.weapon_ammo[id] = {"clip":0,"reserve":0}
		player._handle_weapon_fire()
		var before := empty_sounds(player)
		player._shoot_towards(target)
		check(empty_sounds(player) == before + 1 and player.weapon_wheel.notice.is_empty(), id + " uses sound without a popup")
	player.active_weapon_id = "pistol"
	player.weapon_ammo.pistol = {"clip":0,"reserve":3}
	var before_reload := empty_sounds(player)
	player._shoot_towards(target)
	check(player.is_reloading() and empty_sounds(player) == before_reload, "reserve ammunition triggers reload instead of an empty warning")
	player._shoot_towards(target)
	check(shots[0] == 0, "attempting fire during reload remains blocked")
	await player.reload_finished
	check(player.weapon_ammo.pistol == {"clip":3,"reserve":0}, "automatic reload preserves the ammunition total")
	player._shoot_towards(target)
	check(shots[0] == 1 and player.weapon_ammo.pistol.clip == 2, "weapon fires normally after reloading")
	player.weapon_ammo.pistol.clip = 0
	player._shoot_towards(target)
	check(empty_sounds(player) == 1, "running empty again produces fresh feedback after a successful shot")
	Input.action_release("fire")
	print("EMPTY_WEAPON_AUDIO failures=", failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
