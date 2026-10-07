extends SceneTree
## Entradas subterrâneas do deserto (`world/desert/underground`): catálogo, posição, salas, moradores e segredos.
## Sem sessão: monta cada sala como o `NativePlace` e confere recompensas, moradores, diálogo e colisão. A entrada pela
## sessão (descida, moradores, coleta, saída) está em `tests/test_desert_underground_session.gd`.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const UNDER := preload("res://world/desert/underground/DesertUnderground.gd")
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
	var region = load("res://world/desert/DesertRegion.gd").new()
	region.initial_prewarm_only = true
	root.add_child(region)
	await process_frame
	region.prepare_data()
	check(UNDER.ids().size() == 4, "quatro entradas subterrâneas no deserto", str(UNDER.ids()))
	for id in UNDER.ids():
		var definition := PLACES.get_definition(id)
		check(not definition.is_empty() and definition.region == "desert", id + ": definido no deserto")
		if definition.is_empty(): continue
		var site := UNDER.site(id)
		var point := Vector2(site.exterior.x, site.exterior.z)
		check(region.contains_point(site.exterior) if region.has_method("contains_point") else preload("res://world/desert/DesertLayout.gd").contains(site.exterior), id + ": dentro do mapa do deserto")
		check(absf(region._ground_height(point)) < 0.05, id + ": em chão plano", "y=%.2f" % region._ground_height(point))
		check(region._decoration_clear(point, 1.5) or id == "desert_under_cellar" or id == "desert_under_culvert", id + ": área livre de reservas", str(region._decoration_clear(point, 1.5)))
		var entry_found := false
		for entry in region.entries:
			if entry.place_id == id: entry_found = true
		check(entry_found, id + ": entrada registrada na região")
		var recorded := false
		for key in region.records:
			for record in region.records[key]:
				if record.get("kind", "") == "desert_underground" and record.data.id == id: recorded = true
		check(recorded, id + ": estrutura externa registrada para streaming")
		var room: Node3D = PLACES.create_place(id)
		root.add_child(room)
		await physics_frame
		var rewards: Array = definition.rewards
		check(rewards.size() >= 2, id + ": tem recompensas", str(rewards.size()))
		check(room.reward_points.size() == rewards.size(), id + ": todas as recompensas cabem no chão livre", "%d de %d" % [room.reward_points.size(), rewards.size()])
		var spawn: Vector3 = definition.spawn
		check(room.is_floor_clear(spawn, 0.3), id + ": ponto de chegada livre")
		var residents: Array = definition.npcs
		check(residents.size() >= 1, id + ": tem morador", str(residents.size()))
		for resident in residents:
			check(room.is_floor_clear(resident.local_position, 0.3), id + ": " + resident.name + " em chão livre")
			check(DIALOGUE.lines(resident.id).size() >= 3, id + ": " + resident.name + " tem diálogo")
			check(room.interaction_points.has(resident.id), id + ": " + resident.name + " é interagível")
		check(room.solid_bodies.size() > 6, id + ": paredes e móveis têm colisão", str(room.solid_bodies.size()))
		var room_size: Vector2 = definition.size
		for item in rewards:
			check(_reachable(room, spawn, item.local_position, room_size), id + ": " + str(item.id) + " alcançável a pé")
		room.queue_free()
	print("DESERT_UNDERGROUND checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

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
			if not room.is_floor_clear(Vector3(origin.x + next.x * step, 0, origin.y + next.y * step), radius): continue
			visited[next] = true
			queue.append(next)
	return false
