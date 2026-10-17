extends SceneTree
## Calçadas de Harbor no jogo de verdade (Main.tscn), na câmera de jogo, para comparar
## a camada SidewalkFill (árvores de rua e térreo que transborda) ligada e desligada.
## Uso (com tela, nunca --headless):
##   GETECO_SIDEWALK_FILL=0 tools/run_godot_locked.sh --path . --script res://tests/capture/capture_sidewalk_fill.gd -- --no-save --label=antes
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_sidewalk_fill.gd -- --no-save --label=depois
## Opcional: --night também tira as fotos das 21h30. PNG em evidence/sidewalk-fill-20261017/ (fora do Git).
## Pontos no asfalto, ao sul das fachadas: a câmera olha para o norte.
var points := {
	"mercado": Vector3(52.0, 0.0, 81.0), # lanchonete, lavanderia e oficina da Market Street
	"ilha": Vector3(318.0, 0.0, 140.0), # mercadinho e cinema da ilha
	"sobrados": Vector3(318.0, 0.0, 27.0), # sobrados da Foundry Avenue
	"norte": Vector3(330.0, 0.0, -19.0), # mercadinho e bicicletaria do norte
	"avenida": Vector3(84.0, 0.0, 58.0), # Union Avenue, entre quarteirões
}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "depois"
	var hours := [12.0]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument == "--night": hours.append(21.5)
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/sidewalk-fill-20261017"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in hours:
		weather.time_of_day = hour / 24.0
		for id in points:
			var point: Vector3 = points[id]
			world.player.teleport(point + Vector3.UP * .1)
			world.player.rotation.y = 0.0
			world.production.region.set_focus(point, true)
			for frame in 400:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 120: break
			for frame in 60: await process_frame
			var path := "%s/%s_%s_%02dh.png" % [folder, id, label, int(hour)]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
