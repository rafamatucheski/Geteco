extends SceneTree
## Cinco prédios comerciais do porto pintados (lavanderia, marcenaria, mercado, frete, aquário) no jogo de verdade (Main.tscn), de dia e à noite.
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_painted_harbor_ingame.gd -- --no-save --label=kit
## Antes: GETECO_PAINTED_FACADES=0 com --label=caixas. PNG em evidence/painted-facades-20261015/.
## Ponto = centro da casa (OriginalWorldData /16) + 14 m em +Z, olhando para -Z.
var points := {
	"maritime_museum": Vector3(376.25, 0.0, 43.75 + 7.8 + 4.0),
	"cold_storage": Vector3(162.5, 0.0, 44.375 + 8.75 + 4.0),
	"market_hall": Vector3(109.4, 0.0, 41.6 + 6.9 + 4.0),
	"aquarium": Vector3(381.3, 0.0, 96.9 + 8.45 + 4.0),
}

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
	var folder := "res://evidence/painted-facades-20261015"
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
