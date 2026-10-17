extends SceneTree
## Levantamento visual do oeste verde (vila dos caminhoneiros, Vertice, cemiterio, ferro-velho, motocross).
## Uso (com tela, nunca --headless):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_oeste_levantamento.gd -- --no-save --label=levantamento
## Cada ponto = {posicao, yaw}: o jogador olha para -Z girado por yaw (frente do predio = +Z local).
## PNG em evidence/oeste-levantamento-20261016/.
var points := {
	"vila_casa1": [Vector3(-389.0, 0.0, 87.0), 1.5708],
	"vila_casa2": [Vector3(-392.1, 0.0, 118.3), 1.48],
	"vila_casa3": [Vector3(-378.9, 0.0, 124.1), 3.28],
	"vila_casa4": [Vector3(-341.6, 0.0, 125.2), 2.97],
	"vila_casa5": [Vector3(-312.9, 0.0, 123.3), 3.35],
	"vila_casa6": [Vector3(-268.5, 0.0, 92.1), -0.65],
	"vila_tonico_loja": [Vector3(-359.6, 0.0, 96.0), 0.0],
	"vila_oficina_zeca": [Vector3(-269.0, 0.0, 124.0), 0.0],
	"vertice_galpao": [Vector3(-340.0, 0.0, -35.0), 0.0],
	"cemiterio_casa_zelador": [Vector3(-55.3, 0.0, 106.0), 0.0],
	"ferro_velho_neco": [Vector3(-46.9, 0.0, 52.0), 0.0],
	"motocross_cabana": [Vector3(-215.0, 0.0, -35.0), 1.5708],
}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "levantamento"
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
	var folder := "res://evidence/oeste-levantamento-20261016"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	weather.time_of_day = 12.0 / 24.0
	for id in points:
		var point: Vector3 = points[id][0]
		world.player.teleport(point + Vector3.UP * .1)
		world.player.rotation.y = float(points[id][1])
		world.production.region.set_focus(point, true)
		for frame in 400:
			await process_frame
			if world.production.region.is_streaming_idle() and frame > 120: break
		for frame in 90: await process_frame
		var path := "%s/%s_%s.png" % [folder, id, label]
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
