extends SceneTree
## Capturas da ponte Harbor–Mountain (acabamento de 2026-10-14): vista do jogo sobre o vão e o
## conector, e câmeras livres que mostram pilares, fáscia e guarda-corpo, de dia e à noite.
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_mountain_bridge.gd -- --no-save --label=depois
## Antes: GETECO_BRIDGE_LOOK=0 com --label=antes. PNG em evidence/mountain-bridge-look/ (fora do Git).
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
## id -> [ponto do jogador, posição da câmera livre (ou null = câmera do jogo), alvo da câmera]
var shots := {
	"cima_vao": [Vector3(505.0, 0.0, CONNECTION.CENTER_Z), null, null],
	"cima_conector": [Vector3(440.0, 0.0, CONNECTION.CENTER_Z), null, null],
	"pilares": [Vector3(505.0, 0.0, CONNECTION.CENTER_Z), Vector3(468.0, 3.5, -318.0), Vector3(505.0, -1.0, -288.0)],
	"pilar_perto": [Vector3(505.0, 0.0, CONNECTION.CENTER_Z), Vector3(476.0, 1.2, -302.0), Vector3(489.0, 0.0, -291.0)],
	"guarda_corpo": [Vector3(505.0, 0.0, CONNECTION.CENTER_Z), Vector3(496.0, 2.2, -280.0), Vector3(512.0, 0.4, -292.5)],
}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "medicao"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--pontos="):
			var wanted := argument.trim_prefix("--pontos=").split(",")
			for id in shots.keys():
				if not id in wanted: shots.erase(id)
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/mountain-bridge-look"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	var free_camera := Camera3D.new()
	free_camera.fov = 55.0
	free_camera.near = .05
	free_camera.far = 400.0
	world.add_child(free_camera)
	var game_camera: Camera3D = null
	for hour in [12.0, 22.0]:
		weather.time_of_day = hour / 24.0
		for id in shots:
			var shot: Array = shots[id]
			var point: Vector3 = shot[0]
			world.player.teleport(point + Vector3.UP * .1)
			world.production.region.set_focus(point, true)
			if shot[1] == null:
				if game_camera != null: game_camera.make_current()
			else:
				if game_camera == null: game_camera = root.get_viewport().get_camera_3d()
				free_camera.global_position = shot[1]
				free_camera.look_at(shot[2])
				free_camera.make_current()
			# Streaming das duas regiões, conexão montada e transição de luz da hora.
			for frame in 300:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 90: break
			for frame in 60: await process_frame
			var image := root.get_texture().get_image()
			var path := "%s/%s_%s_%02dh.png" % [folder, id, label, int(hour)]
			image.save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
