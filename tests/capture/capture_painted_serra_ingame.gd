extends SceneTree
## Chalés, loja "Casacos da Vila" e terminal da vila da serra com PaintedFacadeKit no
## jogo de verdade (Main.tscn), de dia e à noite.
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_painted_serra_ingame.gd -- --no-save --play-at=mountain,734,-390 --label=kit
## PNG em evidence/painted-facades-20261015/ingame_serra_<prédio>_<label>_<hora>h.png.
## O jogador fica ~10 m à frente de cada prédio (frente em +Z), olhando para -Z.
const VILLAGE := Vector3(745.0, 0.0, -392.0)

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
	print("REGION ", world.session.state.region_id)
	world.production.region.set_focus(VILLAGE, true)
	for frame in 400:
		await process_frame
		if world.production.region.is_streaming_idle() and frame > 120: break
	# Pontos achados na cena: cada prédio pintado da vila e o escritório do terminal.
	var targets := {}
	for node in world.find_children("PaintedPlace_*", "Node3D", true, false):
		targets[str(node.name).trim_prefix("PaintedPlace_")] = node.global_position + Vector3(0, 0, 1.9)
	for node in world.find_children("PaintedTerminalOffice", "Node3D", true, false):
		targets["terminal"] = node.global_transform * Vector3(0, 0, 2.5)
	print("TARGETS ", targets)
	if targets.is_empty():
		push_error("nenhum prédio pintado da serra encontrado")
		quit(1)
		return
	var folder := "res://evidence/painted-facades-20261015"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in [12.0, 21.5]:
		weather.time_of_day = hour / 24.0
		for id in targets:
			var point: Vector3 = targets[id] + Vector3(0, 0, 9.0)
			world.player.teleport(point + Vector3.UP * .4)
			world.player.rotation.y = 0.0
			world.production.region.set_focus(point, true)
			for frame in 240:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 60: break
			for frame in 45: await process_frame
			var path := "%s/ingame_serra_%s_%s_%02dh.png" % [folder, id, label, int(hour)]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path), " player=", world.player.global_position)
	quit(0)
