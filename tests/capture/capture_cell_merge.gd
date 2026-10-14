extends SceneTree
## Capturas da fusão geral por trecho (2026-10-14): ponte da fundição, cais do Northstar e dentro do túnel do
## canal (corte ligado), de dia e à noite. Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_cell_merge.gd -- --no-save --label=depois
## Antes: GETECO_CELL_MERGE=0 com --label=antes. PNG em evidence/cell-merge/ (fora do Git).
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
var points := {
	"ponte": Vector3(224.0, 0.0, 30.0),
	"cais": Vector3(220.0, 0.0, 82.0),
	"tunel": Vector3(237.0, 0.0, TUNNEL.CENTER_Z),
}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "medicao"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--pontos="):
			var wanted := argument.trim_prefix("--pontos=").split(",")
			for id in points.keys():
				if not id in wanted: points.erase(id)
	points.tunel.y = TUNNEL.floor_y(points.tunel.x)
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/cell-merge"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in [12.0, 22.0]:
		weather.time_of_day = hour / 24.0
		for id in points:
			var point: Vector3 = points[id]
			world.player.teleport(point + Vector3.UP * .1)
			world.production.region.set_focus(point, true)
			# Streaming, acabamento fatiado, fusão (2 quadros depois do trecho) e o fade do corte.
			for frame in 300:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 90: break
			for frame in 60: await process_frame
			var image := root.get_texture().get_image()
			var path := "%s/%s_%s_%02dh.png" % [folder, id, label, int(hour)]
			image.save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
