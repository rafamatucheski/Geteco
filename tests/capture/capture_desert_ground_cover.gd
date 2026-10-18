extends SceneTree
## Chão do deserto povoado (arte de carregamento desert_highway.png) no jogo de verdade, dia e noite.
## Uso (com tela, nunca --headless), pela fila:
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_desert_ground_cover.gd -- --label=depois
## A/B no mesmo binário: GETECO_DESERT_GROUND_COVER=0 desliga a cobertura nova.
## PNG em evidence/desert-ground-cover-20261017/. Cada ponto: [posição do jogador, rumo (rotation.y)].
var points := {
	"rota66_sul": [Vector3(349.0, 0.0, -640.0), PI],
	"rota66_norte": [Vector3(349.0, 0.0, -1150.0), PI],
	"deserto_aberto": [Vector3(80.0, 0.0, -1180.0), 0.0],
	"rua_principal_oeste": [Vector3(-760.0, 0.0, -874.0), PI * .5],
	"relevo": [Vector3(-850.0, 0.0, -1700.0), 0.0],
}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "antes"
	var only_noon := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument == "--noon-only": only_noon = true
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/desert-ground-cover-20261017"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	var hours := [12.0] if only_noon else [12.0, 21.5]
	for hour in hours:
		weather.time_of_day = hour / 24.0
		for id in points:
			var point: Vector3 = points[id][0]
			world.production.region.set_focus(point, true)
			world.production.region.prepare_collision_at(point)
			world.player.teleport(point + Vector3.UP * 1.5)
			world.player.rotation.y = float(points[id][1])
			world.production.region.set_focus(point, true)
			for frame in 400:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 90: break
			for frame in 60: await process_frame
			var path := "%s/%s_%s_%02dh.png" % [folder, id, label, int(hour)]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
