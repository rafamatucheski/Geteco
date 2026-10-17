extends SceneTree
## Ala oeste da clínica (BAY MEDICAL) pintada, no jogo de verdade (Main.tscn), de dia e à noite.
## Uso (com tela, nunca --headless):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_painted_clinic_ingame.gd -- --no-save --label=kit
## Antes: GETECO_PAINTED_CLINIC=0 com --label=caixas. PNG em evidence/painted-clinic-20261016/.
## Pontos: frente reta (+Z do prédio), de um canto sudoeste e do lado da ambulância; a
## frente também com a porta pública aberta (set_open_amount(1)).

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "kit"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/painted-clinic-20261016"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var origin: Vector3 = preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_hospital").exterior_position
	var wing := origin + Vector3(-2.78, 0, 0)
	var front_z := origin.z + 8.32
	# [nome, posição do jogador, yaw (0 = olhando para -Z), porta pública aberta]
	var views := [
		["frente", Vector3(wing.x, 0, front_z + 12.0), 0.0, false],
		["frente_aberta", Vector3(wing.x + 2.8, 0, front_z + 6.0), 0.0, true],
		["canto_sudoeste", Vector3(wing.x - 11.0, 0, front_z + 11.0), deg_to_rad(40.0), false],
		["lado_ambulancia", Vector3(origin.x + 14.0, 0, origin.z + 22.0), deg_to_rad(-35.0), false],
	]
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in [12.0, 21.5]:
		weather.time_of_day = hour / 24.0
		for view in views:
			var point: Vector3 = view[1]
			world.player.teleport(point + Vector3.UP * .1)
			world.player.rotation.y = float(view[2])
			world.production.region.set_focus(point, true)
			for frame in 300:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 90: break
			var clinic: Node = null
			for node in world.production.region.find_children("Clinic", "Node3D", true, false): clinic = node
			if clinic != null and clinic.has_method("set_open_amount"): clinic.set_open_amount(1.0 if bool(view[3]) else 0.0)
			for frame in 60: await process_frame
			var path := "%s/clinica_%s_%s_%02dh.png" % [folder, view[0], label, int(hour)]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path), " clinic=", clinic)
	quit(0)
