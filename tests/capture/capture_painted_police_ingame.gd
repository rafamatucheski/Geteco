extends SceneTree
## Delegacia pintada (id Police, editor 18x10 m em 66,120) no jogo de verdade (Main.tscn), de dia e à noite.
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_painted_police_ingame.gd -- --no-save --label=kit [--points=a,b] [--hours=12,21.5]
## Antes: GETECO_PAINTED_FACADES=0 com --label=caixas. PNG em evidence/painted-police-20261016/.
## Ponto = centro da casa (OriginalWorldData /16) + 14 m em +Z, olhando para -Z.
## `police_entrance` e `police_entering` saem da entrada de verdade
## (WeaponShopEntrance._door_position, que segue o editor de mundo): o jogador parado
## 0,9 m à frente dela e depois empurrando, com as folhas pintadas abertas em volta dele.
var points := {
	"police_front": Vector3(66.0, 0.0, 131.0),
	"police_door": Vector3(66.0, 0.0, 128.0),
}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var label := "kit"
	var only: PackedStringArray = []
	var hours := [12.0, 21.5]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--points="): only = argument.trim_prefix("--points=").split(",")
		if argument.begins_with("--hours="):
			hours = []
			for hour in argument.trim_prefix("--hours=").split(","): hours.append(float(hour))
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/painted-police-20261016"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var walk = world.session.weapon_shop_entrance
	var door: Vector3 = walk._door_position("harbor_police", preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_police"))
	var inward: Vector3 = walk._inward("harbor_police")
	points["police_entrance"] = door - inward * .9
	points["police_entering"] = door - inward * .9
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	for hour in hours:
		weather.time_of_day = hour / 24.0
		for id in points:
			if not only.is_empty() and id not in only: continue
			var point: Vector3 = points[id]
			world.player.teleport(point + Vector3.UP * .1)
			# Olhando para -Z (fachada sul dos prédios ao norte do ponto).
			world.player.rotation.y = 0.0
			world.production.region.set_focus(point, true)
			for frame in 300:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 90: break
			for frame in 60: await process_frame
			if id == "police_entering" and not await _push_open(world, inward): continue
			var path := "%s/ingame_%s_%s_%02dh.png" % [folder, id, label, int(hour)]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", ProjectSettings.globalize_path(path), " entrada=", door, " jogador=", world.player.global_position)
			if id == "police_entering": await _back_out(world, point)
	quit(0)

## Anda para a porta até as folhas passarem de 60% abertas, antes da troca para o interior.
func _push_open(world: Variant, inward: Vector3) -> bool:
	var facade: Node = null
	for candidate in get_nodes_in_group("v2_walkin_facade"):
		if candidate.get_meta("place_id", "") == "harbor_police": facade = candidate
	if facade == null: return false
	world.player.controlled_automatically = true
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and float(facade.open_amount) < .6 and world.session.state.place_id.is_empty():
		world.player.automatic_direction = inward
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	await process_frame
	await RenderingServer.frame_post_draw
	return world.session.state.place_id.is_empty() and float(facade.open_amount) >= .6

## Volta para fora; se a troca de lugar já começou, sai pela porta do interior.
func _back_out(world: Variant, point: Vector3) -> void:
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and world.session.state.place_id.is_empty(): await physics_frame
	if not world.session.state.place_id.is_empty():
		for frame in 60: await physics_frame
		world.player.teleport(world.session.room.exit_position + Vector3(0, .08, -.53))
		world.player.automatic_direction = Vector3.BACK
		until = Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < until and not world.session.state.place_id.is_empty(): await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	world.player.controlled_automatically = false
	world.player.teleport(point + Vector3.UP * .1)
	for frame in 30: await physics_frame
