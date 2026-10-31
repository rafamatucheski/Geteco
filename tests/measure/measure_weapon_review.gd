extends "res://tests/measure/measure_combat.gd"
## Cena de produção, cooldown/recargas normais, entrada fixa; só equipamento da fixture.
## Exige --no-save --skip-arrival --out=res://evidence/.../new-label.
## Mantém a mesma população, janela, renderizador e processos concorrentes para o A/B.
var output := ""
var events: Array[Dictionary] = []
var last_pulse := -1
var previous_magazine := -1
var observed_shots := 0
var observed_reloads := 0

func _arg(key: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(key + "="): return value.trim_prefix(key + "=")
	return fallback

func _baseline_source(name: String, recorded: String, current: String) -> String:
	if name != "Gameplay": return recorded
	# O travamento da ferrovia chegou em paralelo com esta revisão. Preserva esses
	# métodos não relacionados nas duas variantes da comparação de armas.
	for method in ["attack_allowed", "_railway_controls_locked", "_free_play_ok"]:
		var expression := RegEx.new()
		expression.compile("(?ms)^func " + method + "\\(.*?(?=^func |\\z)")
		var fresh := expression.search(current)
		if fresh == null: continue
		var previous := expression.search(recorded)
		if previous != null: recorded = recorded.replace(previous.get_string(), fresh.get_string())
		else: recorded = recorded.replace("func _physics_process(", fresh.get_string() + "func _physics_process(")
	return recorded

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "-" + label + ".png")

func _shoot(seconds: float, id: String) -> void:
	var ammo: Dictionary = gameplay.state.get_ammo(id)
	var magazine := int(ammo.get("magazine", 0))
	if previous_magazine >= 0:
		if magazine < previous_magazine: observed_shots += previous_magazine - magazine
		elif magazine > previous_magazine: observed_reloads += 1
	previous_magazine = magazine
	var pulse := int(seconds / (0.50 if id == "sawed_off" else 0.20))
	if id == "smg":
		Input.action_press("fire")
	elif pulse != last_pulse:
		last_pulse = pulse
		Input.action_release("fire")
	else:
		Input.action_press("fire")

func _run() -> void:
	output = _arg("--out", "")
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or not output.begins_with("res://evidence/") or FileAccess.file_exists(output + ".json"):
		push_error("Requires rendered window, --no-save and a new --out in evidence.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	# Reconstrói a revisão de código registrada desta revisão só neste processo.
	# Arquivos compartilhados e outras sessões nunca são revertidos para rodar uma comparação.
	if "--baseline-sources" in OS.get_cmdline_user_args():
		for name in ["WeaponPoseData", "WeaponRigPose", "WeaponPresentation3D", "WeaponFinish3D", "ArsenalWeapon3D", "CombatAudio", "CombatEffects", "Gameplay"]:
			var path: String = "res://gameplay/" + name + ".gd"
			var original: String = "res://evidence/weapon-review-20261007/baseline-sources/" + name + ".gd"
			if not FileAccess.file_exists(original):
				push_error("Missing recorded baseline: " + original)
				quit(2)
				return
			var source: GDScript = load(path)
			source.source_code = _baseline_source(name, FileAccess.get_file_as_string(original), source.source_code)
			if source.reload(true) != OK:
				push_error("Baseline reconstruction failed: " + path)
				quit(2)
				return
	create_timer(240).timeout.connect(func(): push_error("WEAPON_REVIEW_TIMEOUT"); quit(2))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for frame in 6000:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Production session did not become ready")
		quit(2)
		return
	world.session.state.intro.stage = "complete"
	if not world.session.state.place_id.is_empty(): await world.session.leave_place()
	await create_timer(2).timeout
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null:
		push_error("Weapon review requires the native C# route path")
		quit(2)
		return
	gameplay = world.gameplay
	gameplay.toggle_god_mode()
	gameplay.activate_arsenal_cheat()
	if not gameplay.attack_allowed():
		push_error("Production session is blocking weapons")
		quit(2)
		return
	var controls = root.get_node("GameInput")
	controls.using_gamepad = true
	controls.touch_aim = Vector2.RIGHT
	Input.action_press("aim")
	var started := Time.get_ticks_usec()
	print("WEAPON_REVIEW_READY pid=", OS.get_process_id(), " out=", output)
	for id in ["sawed_off", "smg"]:
		gameplay.state.equip_weapon(id)
		await create_timer(1.0).timeout
		await _capture(id + "-aim")
		last_pulse = -1
		previous_magazine = -1
		observed_shots = 0
		observed_reloads = 0
		var before: Dictionary = gameplay.state.get_ammo(id).duplicate()
		await sample_phase(id, func(seconds: float): _shoot(seconds, id))
		Input.action_release("fire")
		events.append({"weapon": id, "before": before, "after": gameplay.state.get_ammo(id).duplicate(), "observed_shots": observed_shots, "observed_reloads": observed_reloads, "position": str(world.player.global_position), "wanted": gameplay.stars})
		await _capture(id + "-after")
	Input.action_release("aim")
	await sample_phase("recovery", Callable())
	await _capture("recovery")
	var result := {"engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(), "driver": OS.get_video_adapter_driver_info(), "renderer": RenderingServer.get_current_rendering_method(), "native": true,
		"window": str(DisplayServer.window_get_size()), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"arguments": OS.get_cmdline_user_args(), "position": str(world.player.global_position),
		"samples_ms": samples, "summary": {}, "events": events, "duration_s": float(Time.get_ticks_usec() - started) / 1000000.0,
		"note": "Main production scene, arsenal/god-mode fixture, real input/cooldown/reloads, world systems active. Does not validate every terrain or weapon."}
	for name in samples: result.summary[name] = summarize(name)
	var file := FileAccess.open(output + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("WEAPON_REVIEW_RESULT ", JSON.stringify(result.summary))
	quit(0)
