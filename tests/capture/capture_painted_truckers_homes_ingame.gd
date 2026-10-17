extends SceneTree
## Casas rurais da Vila dos Caminhoneiros pintadas, no jogo de verdade, dia e noite, mais uma entrando.
## Uso (com tela): tools/run_godot_locked.sh --path . --script res://tests/capture/capture_painted_truckers_homes_ingame.gd -- --no-save --label=kit
## --label=caixas liga o 3D antigo (A/B). PNG em evidence/painted-truckers-homes-20261016/.
const ORIGIN := Vector3(-330, 0, 108)
const LAYOUT := preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd").HOME_LAYOUT

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "kit"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	OS.set_environment("GETECO_PAINTED_TRUCKERS_HOMES", "0" if label == "caixas" else "1")
	var points := {}
	for index in [0, 2, 3, 5]:
		var entry: Array = LAYOUT[index]
		var yaw: float = entry[2]
		var center: Vector3 = ORIGIN + entry[0]
		points["casa%d" % (index + 1)] = {"at": center + Vector3(sin(yaw), 0, cos(yaw)) * 11.0, "yaw": yaw}
	# Ponto sugerido pelo coordenador (X~-278, Z~109) olhando para a casa 6.
	var from := Vector3(-278, 0, 109)
	var home6: Vector3 = ORIGIN + LAYOUT[5][0]
	var dir := (home6 - from).normalized()
	points["casa6_de_278_109"] = {"at": from, "yaw": atan2(-dir.x, -dir.z)}
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/painted-truckers-homes-20261016"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in [12.0, 21.5]:
		weather.time_of_day = hour / 24.0
		for id in points:
			var point: Vector3 = points[id].at
			world.player.teleport(point + Vector3.UP * .1)
			world.player.rotation.y = float(points[id].yaw)
			world.production.region.set_focus(point, true)
			for frame in 400:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 90: break
			for frame in 90: await process_frame
			var path := "%s/ingame_%s_%s_%02dh.png" % [folder, id, label, int(hour)]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path))
	# Entrando: casa 4, parado no vão, porta aberta, depois dentro.
	var entry: Array = LAYOUT[3]
	var yaw: float = entry[2]
	var basis: Basis = Basis(Vector3.UP, yaw)
	var home: Vector3 = ORIGIN + entry[0]
	weather.time_of_day = 12.0 / 24.0
	for step in [["porta", Vector3(-.73, .1, 6.2)], ["dentro", Vector3(-.73, .1, 1.5)]]:
		world.player.teleport(home + basis * step[1])
		world.player.rotation.y = yaw
		world.production.region.set_focus(home, true)
		for frame in 240: await process_frame
		var path := "%s/ingame_casa4_entrando_%s_%s.png" % [folder, step[0], label]
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
