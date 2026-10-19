extends SceneTree
## Escritórios A/B/C pintados (BridgeCourtEast -> escritorio-a, NorthFrontage5 ->
## escritorio-b, NorthbankFront2 -> escritorio-c) no jogo de verdade (Main.tscn), de
## dia e à noite, a 6 m da porta. A câmera isométrica fica presa no jogador e o
## prédio aparece acima e à direita dele: de mais longe (18 m) ele saía do quadro e
## o topo de 10 m não cabe de nenhum ponto da calçada. --off
## (GETECO_PAINTED_OFFICES=0) captura as caixas antigas para comparar.
## Uso (com tela, nunca --headless):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_painted_offices_ingame.gd -- --no-save --label=kit
## PNG em evidence/painted-offices-20261018/ (fora do Git).
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const IDS := ["BridgeCourtEast", "NorthFrontage5", "NorthbankFront2"]

func _initialize() -> void:
	OS.set_environment("GETECO_PAINTED_OFFICES", "0" if "--off" in OS.get_cmdline_user_args() else "1")
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
	var folder := "res://evidence/painted-offices-20261018"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in [12.0, 21.5]:
		weather.time_of_day = hour / 24.0
		for id in IDS:
			var def: Dictionary = CATALOG.for_source(id)
			if def.is_empty():
				print("SEM CATALOGO ", id)
				continue
			var at: Vector3 = def.exterior_position
			var yaw: float = def.exterior_rotation
			var basis := Basis(Vector3.UP, yaw)
			var entry: Vector3 = def.entrance_local
			for shot in [["porta", Vector3(entry.x, 0, def.size.y * 0.5 + 6.0)]]:
				var point: Vector3 = at + basis * shot[1]
				world.player.teleport(point + Vector3.UP * .1)
				# Rotação 0 olha para -Z; a frente do prédio olha para +Z local.
				world.player.rotation.y = yaw
				world.production.region.set_focus(point, true)
				for frame in 300:
					await process_frame
					if world.production.region.is_streaming_idle() and frame > 90: break
				for frame in 60: await process_frame
				var path := "%s/%s_%s_%s_%02dh.png" % [folder, id, shot[0], label, int(hour)]
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
				print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
