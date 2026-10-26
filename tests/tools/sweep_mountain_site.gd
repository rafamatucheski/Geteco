extends SceneTree
## Procura chão para um lugar novo na serra: longe de estrada, trilha, corrida de jipe, Descida da
## Meia-Noite, pistas de esqui, teleférico, vila, lugares, forja e fontes de calor, com o terreno sem
## desnível grande no raio pedido (a reserva do lugar aplana o chão para y = 0). Só imprime.
## Uso: "$GODOT" --path . --script res://tests/tools/sweep_mountain_site.gd -- --no-save [--radius=14] [--box=640,-520,800,-400]
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const JEEP := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
const VILLAGE := preload("res://world/mountain_detail/OriginalVillageLayout.gd")
const PROGRESSION := preload("res://activities/MountainProgression.gd")
const LIFT := preload("res://world/environmental_parity/MountainChairliftParity3D.gd")
const FORGE := preload("res://world/mountain_detail/forge/MountainForge.gd")
const HERMIT := preload("res://world/mountain_detail/forge/ForgeHermitCabin.gd")
const HEAT := preload("res://runtime/cold/OriginalHeatSources.gd")

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): print("MSWEEP watchdog"); quit(3))
	run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.split("=")[1]
	return fallback

static func _segment_distance(p: Vector2, line: Array) -> float:
	var best := INF
	for i in line.size() - 1: best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])))
	return best

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): print("MSWEEP --no-save obrigatório"); quit(2); return
	var radius := float(_arg("radius", "14"))
	var b := _arg("box", "640,-520,800,-400").split(",")
	var box := Rect2(Vector2(float(b[0]), float(b[1])), Vector2(float(b[2]) - float(b[0]), float(b[3]) - float(b[1])))
	var world: Node3D = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.get("session") == null or not world.session.ready_for_play: print("MSWEEP sessão não carregou"); quit(1); return
	var center3 := Vector3(box.get_center().x, 0, box.get_center().y)
	world.production._update_logical_region(center3)
	world.player.teleport(center3 + Vector3(0, 2, 0))
	var region: Node3D = null
	for i in 600:
		await process_frame
		region = world.production.region
		if is_instance_valid(region) and str(region.get("region_id")) == "mountain" and region.get("terrain") != null: break
	if not is_instance_valid(region) or str(region.get("region_id")) != "mountain":
		print("MSWEEP sem região da serra (%s, %s)" % [region.get("region_id") if is_instance_valid(region) else "nula", world.session.state.region_id])
		quit(1)
		return
	var at := func(v: Vector2) -> Vector2:
		var p := CATALOG._at(v, "mountain")
		return Vector2(p.x, p.z)
	var courses: Array = []
	for id in PROGRESSION.COURSES:
		var line: Array = [at.call(PROGRESSION.COURSES[id].start)]
		for point in PROGRESSION.COURSES[id].points: line.append(at.call(point))
		courses.append(line)
		print("MSWEEP pista %s começa em %s" % [id, line[0]])
	var lift: Array = []
	for point in LIFT.SOURCE_POINTS: lift.append(at.call(point))
	print("MSWEEP teleférico de %s a %s" % [lift[0], lift[-1]])
	var downhill = preload("res://activities/mountain_downhill/MountainDownhillCourse.gd").new()
	var downhill_line: Array = []
	for point in downhill.route.get_baked_points(): downhill_line.append(Vector2(point.x, point.z))
	var start3: Vector3 = downhill.start_position()
	var start := Vector2(start3.x, start3.z)
	print("MSWEEP descida começa em %s" % start)
	print("MSWEEP vila (porta do ônibus) em %s" % at.call(VILLAGE.BUS_DOOR))
	var places: Array = []
	for definition in CATALOG.definitions():
		if definition.region == "mountain": places.append(Vector2(definition.exterior_position.x, definition.exterior_position.z))
	var heat: Array = []
	for source in HEAT.SOURCES:
		var w := HEAT.to_world(source.point)
		heat.append(Vector2(w.x, w.z))
	var found: Array = []
	var x := box.position.x
	while x <= box.end.x:
		var z := box.position.y
		while z <= box.end.y:
			var p := Vector2(x, z)
			var original: Vector2 = p * 16.0 - CATALOG.MOUNTAIN_OFFSET
			var ok: bool = not region.route_geometry.contains(Vector3(p.x, 0, p.y), radius + 3.0) and not JEEP.is_reserved(p, radius + 4.0)
			ok = ok and not VILLAGE.is_reserved(original) and not region._helipad_reserved(original) and not region._fort_exit_reserved(p)
			ok = ok and not FORGE.FOOTPRINT.grow(radius + 30.0).has_point(p) and not HERMIT.FOOTPRINT.grow(radius + 30.0).has_point(p)
			ok = ok and _segment_distance(p, downhill_line) > radius + 8.0 and _segment_distance(p, lift) > radius + 6.0
			for line in courses: ok = ok and _segment_distance(p, line) > radius + 8.0
			for q in places: ok = ok and p.distance_to(q) > radius + 20.0
			for q in heat: ok = ok and p.distance_to(q) > radius + 30.0
			if ok:
				var low := INF
				var high := -INF
				for k in 12:
					var a := float(k) / 12.0 * TAU
					for r in [0.0, radius * .5, radius, radius + 8.0]:
						var h: float = region.terrain.height_at(p + Vector2(cos(a), sin(a)) * r)
						low = minf(low, h)
						high = maxf(high, h)
				if low > -.2: found.append({"p": p, "relief": high - low, "start": p.distance_to(start)})
			z += 6.0
		x += 6.0
	found.sort_custom(func(a, c): return a.start + a.relief * 10.0 < c.start + c.relief * 10.0)
	print("MSWEEP candidatos=%d raio=%.0f caixa=%s" % [found.size(), radius, box])
	for i in mini(15, found.size()):
		var c: Dictionary = found[i]
		print("MSWEEP (%.0f, %.0f) a %.0f m da largada da descida, desnível %.2f m" % [c.p.x, c.p.y, c.start, c.relief])
	quit(0)
