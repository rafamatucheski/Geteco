extends SceneTree
## Portas de acesso a pé (WeaponShopEntrance) no jogo de verdade (Main.tscn): para cada
## id, o jogador parado 0,9 m à frente da entrada real e depois empurrando até a porta
## passar de 60% aberta, antes da troca para o interior. Feita para conferir de olho o
## que a auditoria de portas mede (folha walk_in ou vão pintado sem folha na entrada).
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_walkup_doors_ingame.gd -- --no-save [--ids=a,b] [--hours=12,21.5] [--label=kit]
## Save isolado de campanha completa (o mesmo da auditoria), nada gravado de volta.
## PNG em evidence/walkup-doors-20261019/ (fora do Git).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const FOLDER := "res://evidence/walkup-doors-20261019"

var world: Variant

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("CAPTURE exige --no-save para não tocar no save do usuário.")
		quit(2)
		return
	var ids: PackedStringArray = ["harbor_hospital", "harbor_fire_station", "cemetery_keeper"]
	var hours := [12.0]
	var label := "kit"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ids="): ids = argument.trim_prefix("--ids=").split(",")
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--hours="):
			hours = []
			for hour in argument.trim_prefix("--hours=").split(","): hours.append(float(hour))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var snapshot := FIXTURE.full_snapshot(Vector3(170.0, .08, 120.0), true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var fixture_path := FOLDER.path_join("fixture-save.json")
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	if STORE.read_valid(fixture_path).is_empty():
		push_error("CAPTURE fixture inválida")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("menu_save_path", fixture_path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	if not (world.session != null and world.session.ready_for_play):
		push_error("CAPTURE o jogo não ficou pronto")
		quit(3)
		return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	var walk = world.session.weapon_shop_entrance
	for hour in hours:
		weather.time_of_day = hour / 24.0
		for id in ids:
			var definition: Dictionary = walk._definition_for(id)
			if definition.is_empty() or str(definition.region) != world.session.state.region_id:
				print("CAPTURE pulado ", id, " (fora da região ", world.session.state.region_id, ")")
				continue
			var door: Vector3 = walk._door_position(id, definition)
			var inward: Vector3 = walk._inward(id)
			var point := door - inward * .9
			await _stand(point, inward)
			_save("%s_porta_%s_%02dh" % [id, label, int(hour)], id, door)
			if await _push_open(id, inward): _save("%s_abrindo_%s_%02dh" % [id, label, int(hour)], id, door)
			else: print("CAPTURE ", id, ": a porta não passou de 60% antes da troca de lugar")
			await _back_out(point, inward)
	quit(0)

func _stand(point: Vector3, inward: Vector3) -> void:
	if world.gameplay.stars > 0: world.gameplay.clear_wanted()
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(point + Vector3.UP * .1)
	world.player.rotation.y = atan2(-inward.x, -inward.z)
	world.production.region.set_focus(point, true)
	for frame in 300:
		await process_frame
		if world.production.region.is_streaming_idle() and frame > 90: break
	for frame in 60: await process_frame

func _facade(id: String) -> Node:
	for candidate in get_nodes_in_group("v2_walkin_facade"):
		if str(candidate.get_meta("place_id", "")) == id: return candidate
	return null

## Anda para a porta até ela passar de 60% aberta, antes da troca para o interior.
func _push_open(id: String, inward: Vector3) -> bool:
	var facade := _facade(id)
	if facade == null: return false
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and float(facade.open_amount) < .6 and world.session.state.place_id.is_empty():
		world.player.automatic_direction = inward
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	await process_frame
	await RenderingServer.frame_post_draw
	return world.session.state.place_id.is_empty() and float(facade.open_amount) >= .6

func _save(name: String, id: String, door: Vector3) -> void:
	var path := ProjectSettings.globalize_path(FOLDER.path_join(name + ".png"))
	root.get_texture().get_image().save_png(path)
	var facade := _facade(id)
	var leaves := []
	if facade != null:
		var art: Node = facade.get_parent() if str(facade.name) == "WalkupDoor" else facade
		for anchor in art.find_children("Doorway_front*", "Node3D", true, false):
			if not anchor.has_meta("walk_in"): continue
			for leaf in anchor.get_children():
				if leaf is PaintedFacadeKit.PaintedDoor: leaves.append(snappedf(leaf.open_amount, .01))
	print("CAPTURE ", path, " entrada=", door, " jogador=", world.player.global_position,
		" abertura=", snappedf(float(facade.open_amount), .01) if facade != null else -1.0, " folhas_kit=", leaves)

## Volta para fora; se a troca de lugar já começou, sai andando pela porta do interior.
func _back_out(point: Vector3, inward: Vector3) -> void:
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and world.session.state.place_id.is_empty(): await physics_frame
	if not world.session.state.place_id.is_empty():
		for frame in 60: await physics_frame
		await world.session.leave_place()
		for frame in 60: await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(point - inward * 5.0 + Vector3.UP * .1)
	for frame in 30: await physics_frame
