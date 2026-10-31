extends RefCounted
## Reserva de circulação na hora da montagem, no plano local do piso da sala.
## O runtime ainda checa o apoio real e varreduras de corpo antes de admitir atores.
const STEP := .45
const RADIUS := .36
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

static func protected_paths(room) -> Array[Vector3]:
	var best := {"points":[], "unreachable":["spawn"]}
	var first := true
	# Uma grade de .45 m pode perder uma passagem estreita existente entre dois móveis.
	# Desloca a origem antes de declará-la desconectada; a folga fica intacta.
	for phase in [Vector2.ZERO, Vector2(STEP * .5, 0), Vector2(0, STEP * .5), Vector2.ONE * STEP * .5]:
		var candidate := _paths_on_grid(room, phase)
		if first or candidate.unreachable.size() < best.unreachable.size():
			best = candidate
			first = false
		if best.unreachable.is_empty(): break
	room.set_meta("cat_layout_unreachable_stations", best.unreachable)
	var result: Array[Vector3] = []
	result.assign(best.points)
	return result

static func _paths_on_grid(room, phase: Vector2) -> Dictionary:
	var cells := _free_cells(room, phase)
	var protected: Array[Vector3] = []
	var unreachable: Array[String] = []
	if cells.is_empty():
		return {"points":protected, "unreachable":["spawn"]}
	var spawn: Vector3 = room.to_local(room.spawn_position)
	var start := _nearest_cell(cells, spawn)
	var parents := {start:start}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var here := queue[cursor]
		cursor += 1
		for direction in DIRECTIONS:
			var next := here + direction
			if not cells.has(next) or parents.has(next): continue
			if not _segment_clear(room, cells[here], cells[next]): continue
			parents[next] = here
			queue.append(next)
	var goals: Dictionary = room.interaction_points.duplicate()
	goals["spawn"] = room.spawn_position
	goals["exit"] = room.exit_position
	var reserved := {}
	for label in goals:
		if not goals[label] is Vector3: continue
		var target: Vector3 = room.to_local(goals[label])
		var nearest := _nearest_cell(cells, target)
		# As estações permitem E a até .95 m. Mantém a célula atravessável mais próxima;
		# um objetivo inalcançável ou distante nunca pode perder a proteção em silêncio.
		if not parents.has(nearest) or Vector2(target.x, target.z).distance_to(Vector2(cells[nearest].x, cells[nearest].z)) > .8:
			unreachable.append(str(label))
			continue
		var cell := nearest
		while not reserved.has(cell):
			reserved[cell] = true
			if cell == start: break
			cell = parents[cell]
		if _segment_clear(room, cells[nearest], target):
			var steps := maxi(1, ceili(cells[nearest].distance_to(target) / (STEP * .5)))
			for i in range(1, steps + 1):
				var endpoint: Vector3 = room.to_global(cells[nearest].lerp(target, float(i) / steps))
				if not protected.has(endpoint): protected.append(endpoint)
	if not unreachable.is_empty():
		# Uma circulação já desconectada não é permissão para piorá-la.
		# Reserva o componente alcançável inteiro até a sala poder ser inspecionada.
		for cell in parents: reserved[cell] = true
	for cell in reserved:
		var point: Vector3 = room.to_global(cells[cell])
		if not protected.has(point): protected.append(point)
	return {"points":protected, "unreachable":unreachable}

static func _free_cells(room, phase: Vector2) -> Dictionary:
	var size: Vector2 = room.definition.get("size", Vector2(14.4, 10.4))
	var half := size * .5 - Vector2.ONE * RADIUS
	var cells := {}
	for z in range(ceili((-half.y - phase.y) / STEP), floori((half.y - phase.y) / STEP) + 1):
		for x in range(ceili((-half.x - phase.x) / STEP), floori((half.x - phase.x) / STEP) + 1):
			var point := Vector3(x * STEP + phase.x, 0, z * STEP + phase.y)
			if room.is_floor_clear(point, RADIUS): cells[Vector2i(x, z)] = point
	return cells

static func _nearest_cell(cells: Dictionary, point: Vector3) -> Vector2i:
	var nearest := Vector2i.ZERO
	var distance := INF
	for key in cells:
		var candidate: Vector3 = cells[key]
		var next := Vector2(candidate.x - point.x, candidate.z - point.z).length_squared()
		if next < distance:
			distance = next
			nearest = key
	return nearest

static func _segment_clear(room, from: Vector3, to: Vector3) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / (STEP * .5)))
	for i in range(steps + 1):
		if not room.is_floor_clear(from.lerp(to, float(i) / steps), RADIUS): return false
	return true
