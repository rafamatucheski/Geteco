extends SceneTree
## Jogo real: civis sobem a passarela da market_street, cruzam e descem, sem
## travar nem cair. Rodar com --no-save (usa o mapa salvo do editor).
const CROSSERS := preload("res://gameplay/crowd/FootbridgeCrossers.gd")
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1500:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var controller = world.session.controller
	world.player.teleport(Vector3(126, 0.2, 108))
	controller.region.set_focus(world.player.global_position)
	for i in 600:
		await process_frame
		if controller.region.is_streaming_idle(): break
	var bridges: Array = get_nodes_in_group("footbridges")
	check(not bridges.is_empty(), "Passarela carregada no mapa")
	if bridges.is_empty():
		print("FOOTBRIDGE_CROSSERS failures=", failures); quit(1); return
	var bridge: Node3D = bridges[0]
	print("FOOTBRIDGE_CROSSERS ponte em ", bridge.global_position)
	var tracked: Dictionary = {}
	var start := Time.get_ticks_msec()
	# 60 s de jogo a 2x: o circuito completo (~2 × 45 m) leva ~60 s a 1,4 m/s.
	Engine.time_scale = 2.0
	var frames := 0
	while Time.get_ticks_msec() - start < 32000:
		await physics_frame
		frames += 1
		if frames % 10 != 0: continue
		for actor in world.people:
			if not is_instance_valid(actor) or not actor.has_meta("footbridge_crosser"): continue
			var id: int = actor.get_instance_id()
			var local: Vector3 = bridge.global_transform.affine_inverse() * actor.global_position
			var row: Dictionary = tracked.get(id, {"peak": -9.0, "min_z": INF, "max_z": -INF, "ground_after_deck": false, "last": actor.global_position, "still": 0, "fell": false, "worst_still": 0})
			row.peak = maxf(row.peak, local.y)
			if local.y > 5.0: row.min_z = minf(row.min_z, local.z); row.max_z = maxf(row.max_z, local.z)
			if row.peak > 5.0 and local.y < 0.3: row.ground_after_deck = true
			if actor.global_position.distance_to(row.last) < 0.05: row.still += 1
			else: row.still = 0
			if row.still == 13: print("FOOTBRIDGE_CROSSERS parado em local=%s waypoint=%d/%d" % [local.snapped(Vector3.ONE*0.1), actor.waypoint, actor.route.size()])
			row.worst_still = maxi(row.worst_still, row.still)
			# Caiu do tabuleiro: abaixo do piso no meio do vão.
			if absf(local.z) < 6.0 and local.y > 0.5 and local.y < 4.5: row.fell = true
			row.last = actor.global_position
			tracked[id] = row
	Engine.time_scale = 1.0
	if "--capture" in OS.get_cmdline_user_args():
		for i in 30: await process_frame
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/footbridge-20260927/jogo_passarela.png"))
	var crossed := 0
	var climbed := 0
	var stuck := 0
	var fell := 0
	for row in tracked.values():
		if row.peak > 5.3: climbed += 1
		if row.min_z < -6.0 and row.max_z > 6.0 and row.ground_after_deck: crossed += 1
		# 6 amostras parado = ~1 s de jogo: parada longa é travamento.
		if row.worst_still > 12: stuck += 1
		if row.fell: fell += 1
	print("FOOTBRIDGE_CROSSERS civis=%d subiram=%d atravessaram=%d travaram=%d caíram=%d" % [tracked.size(), climbed, crossed, stuck, fell])
	check(tracked.size() >= 3, "Três civis na passarela")
	check(climbed >= 2, "Civis sobem até o tabuleiro")
	check(crossed >= 1, "Civil atravessa o vão inteiro e desce")
	check(stuck == 0, "Nenhum civil trava")
	check(fell == 0, "Ninguém cai do tabuleiro")
	print("FOOTBRIDGE_CROSSERS failures=", failures)
	quit(0 if failures.is_empty() else 1)
