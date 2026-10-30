extends SceneTree
## Postes, fiação aérea e placas do Harbor no jogo de verdade (Main.tscn), com janela.
## Para cada ponto: a câmera de jogo (ortográfica, 45°) e um close de perspectiva no poste mais
## próximo, mais a média de draw calls/primitivas/objetos de 30 quadros com a câmera de jogo parada.
## A/B no mesmo build: GETECO_HARBOR_POLES=0 desliga postes de energia, fios e desgaste.
## Uso (nunca --headless):
##   GETECO_HARBOR_POLES=0 tools/run_godot_locked.sh --path . --script res://tests/capture/capture_harbor_poles.gd -- --no-save --label=antes
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_harbor_poles.gd -- --no-save --label=depois
## Opcional: --night (21h30 também) e --points=mercado,porto. PNG e JSON em evidence/harbor-poles-20261029/.
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
## Pontos no asfalto; a câmera de jogo olha para o norte, 25 m atrás e 25 m acima.
var points := {
	"mercado": Vector3(52.0, 0.0, 80.0), # Market Street, comércio do oeste
	"avenida": Vector3(83.0, 0.0, 52.0), # Union Avenue entre quarteirões
	"doca": Vector3(110.0, 0.0, 139.0), # Dock Street, beira do porto
	"porto_sul": Vector3(300.0, 0.0, 227.0), # pátio do porto sul (south_port_north)
	"cobra": Vector3(440.0, 0.0, 108.0), # entrada da Vila Cobra
	"ilha": Vector3(318.0, 0.0, 80.0), # ilha (rua executiva, fiação enterrada)
	"fundicao": Vector3(230.0, 0.0, 27.0), # Foundry Avenue
}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("capture_harbor_poles exige janela")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var label := "depois"
	var hours := [12.0]
	var only: PackedStringArray = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument == "--night": hours.append(21.5)
		if argument.begins_with("--points="): only = argument.trim_prefix("--points=").split(",")
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/harbor-poles-20261029"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world.player.controlled_automatically = true
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	var report := {"label": label, "poles_env": OS.get_environment("GETECO_HARBOR_POLES"), "points": {}}
	for hour in hours:
		weather.time_of_day = hour / 24.0
		for id in points:
			if not only.is_empty() and not id in only: continue
			var point: Vector3 = points[id]
			world.player.teleport(point + Vector3.UP * .1)
			world.player.rotation.y = 0.0
			world.production.region.set_focus(point, true)
			for frame in 600:
				await process_frame
				if world.production.region.is_streaming_idle() and frame > 120: break
			for frame in 90: await process_frame
			var stamp := "%s_%s_%02dh" % [id, label, int(hour)]
			var draws := await _average_draws(30)
			await _save("%s/%s.png" % [folder, stamp])
			var close := await _close_up(world, point, "%s/%s_close.png" % [folder, stamp])
			var entry: Dictionary = draws.duplicate()
			entry["close_target"] = close
			entry["utility"] = _utility_census(world, point)
			report.points[stamp] = entry
			print("POLES_CAPTURE %s %s" % [stamp, JSON.stringify(entry)])
	var file := FileAccess.open(ProjectSettings.globalize_path("%s/draws_%s.json" % [folder, label]), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	quit(0)

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE ", ProjectSettings.globalize_path(path))

func _average_draws(frames: int) -> Dictionary:
	var totals := {"draw_calls": 0.0, "primitives": 0.0, "objects": 0.0}
	for frame in frames:
		await RenderingServer.frame_post_draw
		totals.draw_calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		totals.primitives += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		totals.objects += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	for key in totals: totals[key] = snappedf(totals[key] / frames, 0.1)
	return totals

## Close de perspectiva: poste de energia mais próximo (se existir) ou o poste de luz gerado.
func _close_up(world: Variant, point: Vector3, path: String) -> String:
	var best: Dictionary = {}
	var best_score := INF
	for item in FRAGILE.query(point, 40.0):
		if item.kind != "lamp" or not item.has("multimesh"): continue
		var score: float = Vector2(item.point.x - point.x, item.point.z - point.z).length() - (30.0 if item.has("wires") else 0.0)
		if score < best_score:
			best_score = score
			best = item
	if best.is_empty(): return ""
	var base: Vector3 = best.point
	var camera := Camera3D.new()
	camera.fov = 52.0
	camera.far = 400.0
	world.add_child(camera)
	var away := Vector3(point.x - base.x, 0, point.z - base.z)
	away = away.normalized() if away.length() > 0.5 else Vector3.BACK
	camera.global_position = base + away.rotated(Vector3.UP, 0.55) * 7.5 + Vector3.UP * 3.2
	camera.look_at(base + Vector3.UP * (5.0 if best.has("wires") else 3.6))
	var previous: Camera3D = world.camera
	camera.make_current()
	for frame in 20: await process_frame
	await _save(path)
	camera.current = false
	if is_instance_valid(previous): previous.make_current()
	camera.queue_free()
	await process_frame
	return "%s (%.1f, %.1f)" % ["utility" if best.has("wires") else "lamp", base.x, base.z]

## Contagem dos lotes novos em volta do ponto (vazio quando o interruptor está desligado).
func _utility_census(world: Variant, point: Vector3) -> Dictionary:
	var census := {"poles": 0, "spans": 0, "multimeshes": 0}
	var region: Node = world.production.region
	for key in region.chunks:
		var chunk: Node3D = region.chunks[key]
		if not is_instance_valid(chunk) or Vector2(chunk.global_position.x + 32.0 - point.x, chunk.global_position.z + 32.0 - point.z).length() > 96.0: continue
		for child in chunk.get_children():
			if not child is MultiMeshInstance3D or not String(child.name).begins_with("HarborUtility"): continue
			census.multimeshes += 1
			if String(child.name).contains("Wires"): census.spans += child.multimesh.instance_count
			elif String(child.name).contains("Pole"): census.poles += child.multimesh.instance_count
	return census
