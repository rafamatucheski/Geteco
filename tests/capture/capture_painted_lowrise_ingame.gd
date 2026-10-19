extends SceneTree
## Pacotes baixos pintados (mercearia, estação, galpão, oficina, garagem) no jogo de verdade
## (Main.tscn), de dia e à noite, de frente e de perto da porta de entrada.
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_painted_lowrise_ingame.gd -- --no-save --label=kit
## Antes: GETECO_PAINTED_LOWRISE=0 com --label=caixas. PNG em evidence/painted-lowrise-20261018/ (fora do Git).
## O ponto sai do catálogo: frente + 9 m (ou entrada + 5 m, "porta") para fora, olhando para a fachada.
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "kit"
	var only: PackedStringArray = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	# Na frente da TransitHouse o jogador morria atropelado e a foto seguinte saía no respawn.
	world.player.set_meta(preload("res://gameplay/DamageProtection.gd").META, true)
	var folder := "res://evidence/painted-lowrise-20261018"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in [12.0, 21.5]:
		weather.time_of_day = hour / 24.0
		for id in PaintedHarborHouses.LOWRISE:
			if not only.is_empty() and id not in only: continue
			var def: Dictionary = CATALOG.for_source(id)
			if def.is_empty(): continue
			var yaw := float(def.exterior_rotation)
			var basis := Basis(Vector3.UP, yaw)
			var size: Vector2 = def.size
			var shots := {"frente": 9.0, "porta": 5.0}
			for shot in shots:
				# Frente: centro da fachada; porta: diante da entrada do catálogo.
				var local: Vector3 = Vector3(0, 0, size.y * 0.5) if shot == "frente" else def.entrance_local
				var point: Vector3 = def.exterior_position + basis * (local + Vector3.BACK * float(shots[shot]))
				point.y = 0.0
				world.player.teleport(point + Vector3.UP * .1)
				world.player.rotation.y = yaw
				world.production.region.set_focus(point, true)
				for frame in 300:
					await process_frame
					if world.production.region.is_streaming_idle() and frame > 90: break
				for frame in 60: await process_frame
				var path := "%s/%s_%s_%s_%02dh.png" % [folder, id, shot, label, int(hour)]
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
				print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
