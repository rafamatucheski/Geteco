extends SceneTree
## Quartel de bombeiros pintado (NorthFireStation) no jogo de verdade (Main.tscn), de dia e à noite.
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_painted_harbor_ingame.gd -- --no-save --label=kit
## Antes: GETECO_PAINTED_FACADES=0 com --label=caixas. PNG em evidence/painted-fire-station-20261016/.
## Ponto = centro da casa (OriginalWorldData /16) + 14 m em +Z, olhando para -Z.
var points := {}

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
	# Posição real do quartel: o carregamento é por região; teleporta até o ponto do
	# catálogo e procura o kit depois. Ponto de partida = exterior do lugar harbor_fire_station.
	var catalog: Variant = load("res://world/places/PlaceCatalog.gd")
	var fire: Dictionary = catalog.get_definition("harbor_fire_station")
	var base: Vector3 = fire.exterior_position
	points["fire_station"] = base + Vector3(9.0, 0.0, 6.9 + 3.0)
	points["fire_station_wide"] = base + Vector3(-1.0, 0.0, 6.9 + 3.0)
	var folder := "res://evidence/painted-fire-station-20261016"
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
