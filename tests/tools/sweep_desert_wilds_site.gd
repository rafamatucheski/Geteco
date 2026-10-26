extends SceneTree
## Procura chão livre para um lugar novo do DesertWilds com as mesmas reservas dos enfeites
## (DesertRegion._decoration_clear, com os lugares atuais já reservados), chão plano no raio pedido
## e distância mínima dos outros lugares. Só imprime candidatos; não grava nada.
## Uso: "$GODOT" --path . --script res://tests/tools/sweep_desert_wilds_site.gd -- --no-save [--radius=26] [--spacing=140] [--xmax=-500] [--zmax=-800]
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): print("SWEEP watchdog"); quit(3))
	run.call_deferred()

func _arg(name: String, fallback: float) -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return float(arg.split("=")[1])
	return fallback

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): print("SWEEP --no-save obrigatório"); quit(2); return
	var radius := _arg("radius", 26.0)
	var spacing := _arg("spacing", 140.0)
	var first: Dictionary = WILDS.SITES[0]
	var arrival := WILDS.ground(first.center) + Vector3(0, .1, 60)
	var output := FIXTURE.output_dir("desert-wilds-sweep")
	var data := FIXTURE.full_snapshot(arrival, true)
	data.region_id = "desert"
	data.world.pedestrian = {"region": "desert", "position": [arrival.x, arrival.y, arrival.z]}
	var path := FIXTURE.write_fixture(output, "checkpoint.json", data)
	var world: Node3D = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	var region: Node3D = world.session.controller.regions.get("desert")
	if not is_instance_valid(region): print("SWEEP sem região do deserto"); quit(1); return
	# --xmax/--zmax restringem a busca a um canto do deserto (ex.: o noroeste vazio).
	var area: Rect2 = LAYOUT.BOUNDS.grow(-40.0)
	area.end = Vector2(minf(area.end.x, _arg("xmax", area.end.x)), minf(area.end.y, _arg("zmax", area.end.y)))
	var found: Array = []
	var x := area.position.x
	while x <= area.end.x:
		var z := area.position.y
		while z <= area.end.y:
			var p := Vector2(x, z)
			var nearest := INF
			for site in WILDS.SITES: nearest = minf(nearest, (site.center as Vector2).distance_to(p))
			if nearest >= spacing and region._decoration_clear(p, radius):
				var low := INF
				var high := -INF
				for k in 16:
					var a := float(k) / 16.0 * TAU
					for r in [0.0, radius * .5, radius]:
						var h := HM.surface_height(p + Vector2(cos(a), sin(a)) * r)
						low = minf(low, h)
						high = maxf(high, h)
				if high - low < 1.5: found.append({"p": p, "nearest": nearest, "relief": high - low})
			z += 20.0
		x += 20.0
	found.sort_custom(func(a, b): return a.nearest > b.nearest)
	print("SWEEP candidatos=%d raio=%.0f espaçamento=%.0f" % [found.size(), radius, spacing])
	for i in mini(15, found.size()):
		var c: Dictionary = found[i]
		print("SWEEP (%.0f, %.0f) vizinho mais perto %.0f m, desnível %.2f m" % [c.p.x, c.p.y, c.nearest, c.relief])
	quit(0)
