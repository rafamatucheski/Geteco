extends SceneTree
## Piloto do prédio alto pintado (CivicTower -> torre-civica) no jogo de verdade
## (Main.tscn), de dia e à noite. Ligado por padrão; --off (GETECO_PAINTED_TALL=0)
## captura o prédio antigo para comparar.
## Uso (com tela, nunca --headless):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_painted_tall_ingame.gd -- --no-save --label=alto
## PNG em evidence/painted-tall-20261016/ (fora do Git).
## CivicTower: centro (331,6; 42,5), 10,6 x 15 m, frente em +Z (z = 50).
var points := {
	"civic_tower": Vector3(331.6, 0.0, 66.0),
	"civic_tower_door": Vector3(330.4, 0.0, 56.0),
}

func _initialize() -> void:
	OS.set_environment("GETECO_PAINTED_TALL", "" if "--off" in OS.get_cmdline_user_args() else "1")
	run.call_deferred()

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
	var folder := "res://evidence/painted-tall-20261016"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in [12.0, 21.5]:
		weather.time_of_day = hour / 24.0
		for id in points:
			var point: Vector3 = points[id]
			world.player.teleport(point + Vector3.UP * .1)
			# Olhando para -Z (fachada sul dos prédios ao norte do ponto).
			world.player.rotation.y = 0.0
			world.production.region.set_focus(point, true)
			for frame in 300:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 90: break
			for frame in 60: await process_frame
			var path := "%s/ingame_%s_%s_%02dh.png" % [folder, id, label, int(hour)]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
