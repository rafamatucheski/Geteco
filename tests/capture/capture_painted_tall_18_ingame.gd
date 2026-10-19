extends SceneTree
## Prédios altos pintados da rodada de 18/10 no jogo de verdade (Main.tscn), de dia e
## à noite: ExchangeTower (torre-exchange), UnionApartments (lofts-fundicao) e
## Apartments (predio-misto). --off (GETECO_PAINTED_TALL_18=0) captura os antigos.
## Uso (com tela, nunca --headless):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_painted_tall_18_ingame.gd -- --no-save --label=kit
## PNG em evidence/painted-tall-20261018/ (fora do Git).
## Centros (px V1 / 16) e frente em +Z: Exchange (312,5; 45) 18,75 x 20 m, frente z = 55;
## UnionApartments (388,75; -53,75) 13,1 x 11,25 m, frente z = -48,1;
## Apartments (96,9; 95,6) 11,6 x 14,4 m, frente z = 102,8.
## A câmera isométrica olha de sudoeste: o jogador fica na calçada da frente, perto do
## vão, para o prédio cair no meio da tela (de longe o portal do túnel do canal cobre a
## Exchange e a farmácia cobre os lofts).
var points := {
	"exchange": Vector3(312.5, 0.0, 57.5),
	"lofts": Vector3(388.75, 0.0, -45.5),
	"misto": Vector3(96.9, 0.0, 105.0),
}

func _initialize() -> void:
	OS.set_environment("GETECO_PAINTED_TALL_18", "0" if "--off" in OS.get_cmdline_user_args() else "1")
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
	var folder := "res://evidence/painted-tall-20261018"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in [12.0, 21.5]:
		weather.time_of_day = hour / 24.0
		for id in points:
			var point: Vector3 = points[id]
			world.player.teleport(point + Vector3.UP * .1)
			# Olhando para -Z (fachada sul, a frente dos três prédios).
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
