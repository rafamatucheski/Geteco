extends SceneTree
## Prédios pintados do deserto (PaintedFacadeKit) no jogo de verdade, dia e noite.
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_painted_desert_ingame.gd -- --play-at=desert,-528,-829 --label=deserto
## PNG em evidence/painted-facades-20261015/. Cada ponto: [posição do jogador, rumo (rotation.y)].
var points := {
	"santa_lua_casa1_adobe": [Vector3(-538.0, 0.0, -842.0), PI * .5],
	"santa_lua_casa2_rancho": [Vector3(-518.0, 0.0, -842.0), -PI * .5],
	"santa_lua_casa3_pedra": [Vector3(-538.0, 0.0, -816.0), PI * .5],
	"santa_lua_casa4_galpao": [Vector3(-518.0, 0.0, -816.0), -PI * .5],
	"santa_lua_armazem": [Vector3(-528.0, 0.0, -806.0), PI],
	"pedagio": [Vector3(336.0, 0.0, -474.0), -PI * .5],
	"posto_miragem": [Vector3(272.0, 0.0, -766.0), 0.0],
	"escritorio_mina": [Vector3(-181.0, 0.0, -1634.0), -PI * .5],
}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "deserto"
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
			var point: Vector3 = points[id][0]
			world.production.region.set_focus(point, true)
			world.production.region.prepare_collision_at(point)
			world.player.teleport(point + Vector3.UP * 1.5)
			world.player.rotation.y = float(points[id][1])
			world.production.region.set_focus(point, true)
			for frame in 300:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 90: break
			for frame in 60: await process_frame
			var path := "%s/ingame_%s_%s_%02dh.png" % [folder, id, label, int(hour)]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
