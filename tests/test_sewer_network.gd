extends SceneTree
## Rede de bueiros de Harbor (`world/places/sewers`): catálogo, posição na cidade, salas e moradores.
## Estático e sem sessão: monta cada sala como o `NativePlace` e confere recompensas, moradores e
## colisão. A entrada pela sessão (tampa, escada, saída) está em `tests/urban_detail/test_sewer_network_session.gd`.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SEWERS := preload("res://world/places/sewers/SewerNetwork.gd")
const DIALOGUE := preload("res://data/catalogs/ServiceDialogue.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print(("CASE PASS " if ok else "CASE FAIL ") + label + ((" | " + detail) if detail != "" else ""))
	if not ok: failures.append(label)

func _run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	check(SEWERS.extra_ids().size() == 4, "quatro bueiros novos no catálogo", str(SEWERS.extra_ids()))
	check(PLACES.sewer_openings().size() == 5, "cinco recortes de calçada (o original e quatro novos)")
	var seen: Array[Vector2] = [PLACES.HARBOR_SEWER_OPENING.get_center()]
	for id in SEWERS.extra_ids():
		var definition := PLACES.get_definition(id)
		check(not definition.is_empty() and definition.region == "harbor", id + ": definido em Harbor")
		if definition.is_empty(): continue
		var point: Vector2 = SEWERS.site(id).point
		# Na cidade: calçada ao lado de uma via, fora de prédios e longe dos outros bueiros.
		var nearest_road := 1.0e9
		for road in world.harbor_roads:
			var points: Array = road.points
			for index in points.size() - 1:
				var a := Vector2(points[index][0], points[index][1])
				var b := Vector2(points[index + 1][0], points[index + 1][1])
				var gap := Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) - float(road.width) * 0.5
				nearest_road = minf(nearest_road, gap)
		check(nearest_road > 5.0 and nearest_road < 70.0, id + ": calçada ao lado de uma via", "%.0f px da borda da via" % nearest_road)
		var clearance := 1.0e9
		for building in world.harbor_buildings:
			var center := Vector2(building.position[0], building.position[1])
			var size := Vector2(building.size[0], building.size[1])
			var dx := maxf(absf(point.x - center.x) - size.x * 0.5, 0.0)
			var dy := maxf(absf(point.y - center.y) - size.y * 0.5, 0.0)
			clearance = minf(clearance, Vector2(dx, dy).length())
		check(clearance > 40.0, id + ": fora de prédios", "%.0f px do prédio mais próximo" % clearance)
		var spread := 1.0e9
		for other in seen: spread = minf(spread, point.distance_to(other))
		check(spread > 150.0, id + ": longe dos outros bueiros", "%.0f px" % spread)
		seen.append(point)
		# Sala: monta como o NativePlace e confere o conteúdo.
		var room: Node3D = PLACES.create_place(id)
		root.add_child(room)
		await physics_frame
		check(room.model.get_script().resource_path.ends_with(SEWERS.site(id).model + ".gd"), id + ": usa o modelo próprio")
		var rewards: Array = definition.rewards
		check(rewards.size() >= 2, id + ": tem recompensas", str(rewards.size()))
		check(room.reward_points.size() == rewards.size(), id + ": todas as recompensas cabem no chão livre", "%d de %d" % [room.reward_points.size(), rewards.size()])
		var spawn: Vector3 = definition.spawn
		check(room.is_floor_clear(spawn, 0.3), id + ": pé da escada livre")
		var residents: Array = definition.npcs
		check(residents.size() >= 1, id + ": tem morador de rua", str(residents.size()))
		for resident in residents:
			check(room.is_floor_clear(resident.local_position, 0.3), id + ": " + resident.name + " em chão livre")
			check(DIALOGUE.lines(resident.id).size() >= 3, id + ": " + resident.name + " tem diálogo")
			check(room.interaction_points.has(resident.id), id + ": " + resident.name + " é interagível")
		check(room.solid_bodies.size() > 6, id + ": paredes e móveis têm colisão", str(room.solid_bodies.size()))
		var room_size: Vector2 = definition.size
		var inside := true
		for item in rewards:
			var local: Vector3 = item.local_position
			if absf(local.x) > room_size.x * 0.5 or absf(local.z) > room_size.y * 0.5: inside = false
		check(inside, id + ": recompensas dentro da sala")
		# Os segredos (recompensas atrás de passagem estreita) ficam alcançáveis: há um caminho livre até cada um.
		for item in rewards:
			check(_reachable(room, spawn, item.local_position, room_size), id + ": " + str(item.id) + " alcançável a pé")
		room.queue_free()
	print("SEWER_NETWORK checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

## Busca em grade (0,25 m) a partir do pé da escada, sem atravessar `solid_bounds` com folga de cápsula.
func _reachable(room: Node3D, from: Vector3, to: Vector3, room_size: Vector2) -> bool:
	var step := 0.25
	var radius := 0.28
	var columns := int(room_size.x / step) + 1
	var rows := int(room_size.y / step) + 1
	var origin := Vector2(-room_size.x * 0.5, -room_size.y * 0.5)
	var start := Vector2i(int((from.x - origin.x) / step), int((from.z - origin.y) / step))
	var goal := Vector2i(int((to.x - origin.x) / step), int((to.z - origin.y) / step))
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		if cell.distance_to(goal) <= 1.5: return true
		for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + direction
			if next.x < 0 or next.y < 0 or next.x >= columns or next.y >= rows or visited.has(next): continue
			var point := Vector3(origin.x + next.x * step, 0, origin.y + next.y * step)
			if not room.is_floor_clear(point, radius): continue
			visited[next] = true
			queue.append(next)
	var best := Vector2i.ZERO
	var best_distance := 1.0e9
	for cell in visited:
		var distance := Vector2(cell).distance_to(Vector2(goal))
		if distance < best_distance: best_distance = distance; best = cell
	print("DBGREACH objetivo ", to, " mais perto alcançado ", Vector3(origin.x + best.x * step, 0, origin.y + best.y * step), " solids_perto=", room.solid_bounds.filter(func(b): return Rect2(b.position.x, b.position.z, b.size.x, b.size.z).grow(1.0).has_point(Vector2(to.x, to.z))))
	return false
