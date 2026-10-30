extends SceneTree
## Sonda dos lugares novos (30/10): chão da Cabana do Cavaleiro na serra e lotes livres para a
## academia no Harbor. Imprime medidas; não falha. Uso: --script res://tests/probe_gym_and_cabin_sites.gd
## -- --no-save --play-at=mountain,655,-905 (cabana) ou --play-at=harbor,3,60 (academia).
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const GYM_SIZE := Vector2(18, 13)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	world.session.state.intro.stage = "complete"
	# A região vem do `--play-at=` (com --no-save): serra mede a cabana, Harbor procura lote.
	if world.session.state.region_id == "mountain": await _probe_cabin(world)
	else: await _probe_gym(world)
	quit(0)

func _settle(world, point: Vector3) -> void:
	world.player.teleport(point + Vector3.UP * 40)
	world.production.region.set_focus(point)
	for i in 600: await physics_frame

func _probe_cabin(world) -> void:
	var definition: Dictionary = CATALOG.get_definition("mountain_cabin_secret")
	var hermit := Vector3(700, 0, -845)
	# Controle (o eremita existe) e candidatos em volta dele; o primeiro é o ponto do catálogo.
	var centers: Array[Vector3] = [definition.get("exterior_position", hermit), hermit]
	for offset in [Vector3(-45, 0, -30), Vector3(-60, 0, 20), Vector3(40, 0, -40), Vector3(-30, 0, 60), Vector3(60, 0, 30), Vector3(-90, 0, -10)]:
		centers.append(hermit + offset)
	for center in centers:
		await _settle(world, center)
		var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		var heights: Array[float] = []
		for x in range(-8, 9, 2):
			for z in range(-6, 11, 2):
				var top := center + Vector3(x, 600, z)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 1200))
				if not hit.is_empty(): heights.append(hit.position.y)
		heights.sort()
		var field: float = preload("res://world/shape/WorldShape.gd").field_distance("mountain", Vector2(center.x, center.z))
		if heights.is_empty():
			print("CABANA sem chão em ", center, " campo=%.1f" % field)
			continue
		print("CABANA centro=", center, " amostras=", heights.size(), " min=%.2f max=%.2f desnível=%.2f campo=%.1f eremita=%.0f m" % [heights[0], heights[-1], heights[-1] - heights[0], field, Vector2(center.x - hermit.x, center.z - hermit.z).length()])

func _probe_gym(world) -> void:
	var bar: Dictionary = preload("res://world/places/bars/BarCatalog.gd").definition("harbor_bar")
	var origin: Vector3 = bar.exterior_position
	await _settle(world, origin)
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var routes: Array = world.production.region.map_routes() if world.production.region.has_method("map_routes") else []
	var box := BoxShape3D.new()
	box.size = Vector3(GYM_SIZE.x, 2.6, GYM_SIZE.y)
	var found := 0
	for dx in range(-60, 61, 6):
		for dz in range(-50, 61, 6):
			var at := origin + Vector3(dx, 0, dz)
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60, at + Vector3.DOWN * 60, 1))
			if down.is_empty(): continue
			var ground: float = down.position.y
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = box
			query.collision_mask = 1 | 4
			query.transform = Transform3D(Basis(), Vector3(at.x, ground + 1.6, at.z))
			if not space.intersect_shape(query, 1).is_empty(): continue
			var road := _road_clearance(routes, Vector2(at.x, at.z))
			if road < GYM_SIZE.length() * .5 + 2.0: continue
			found += 1
			print("ACADEMIA lote livre centro=(%.1f, %.2f, %.1f) rua a %.1f m" % [at.x, ground, at.z, road])
	print("ACADEMIA lotes livres: ", found)

func _road_clearance(routes: Array, point: Vector2) -> float:
	var best := INF
	for route in routes:
		var points: PackedVector3Array = route.get("points", PackedVector3Array())
		var half := float(route.get("width", 0.0)) * .5
		for i in range(points.size() - 1):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
			best = minf(best, point.distance_to(closest) - half)
	return best
