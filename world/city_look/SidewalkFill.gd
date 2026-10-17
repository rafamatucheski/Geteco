extends RefCounted
## Enche a calçada de Harbor, que lia vazia (relato do jogador em 17/10/2026):
## o sorteio do mobiliário deixa quase metade das vagas em branco, tudo numa fila
## colada no meio-fio, e a faixa entre o meio-fio e a fachada ficava lisa.
##
## Duas camadas, montadas uma vez por chunk no streaming (passos próprios do
## CityChunkDressing, nas mesmas MultiMesh por tipo):
## - árvore de rua na linha do meio-fio, a cada ~13 m, longe de esquina, poste,
##   porta de garagem e das árvores autorais. É a peça que mais preenche a tela
##   com a câmera 25 m acima;
## - o térreo que transborda, conforme o tipo do prédio: mesa de bar com
##   guarda-sol na esquina, banca de fruta na quitanda, lixeiras e bicicletas nas
##   casas, vasos ladeando a porta, paletes e tambores na oficina. Encostado na
##   fachada, nunca na frente de uma porta, deixando passagem até o meio-fio.
##
## Sorteio determinístico (hash da posição/id), como o resto do CityLook.
## GETECO_SIDEWALK_FILL=0 desliga as duas camadas (A/B no mesmo export).

const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const BRIDGE_SURFACE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")

static var enabled := OS.get_environment("GETECO_SIDEWALK_FILL") != "0"

const TREE_KINDS := ["street_tree", "street_tree_b"]
const TREE_SPACING := 13.0
# Tronco a 0,6 m da guia: mesma linha do hidrante e da lixeira, fora da faixa em
# que o pedestre anda (meio da calçada ± 0,4 m, PedestrianSteering).
const TREE_CURB_OFFSET := 0.6
const TREE_TRUNK_RADIUS := 0.22
# Vias sem calçada de cidade (porto de contêineres, estrada rural, ponte, vila da
# Cobra com quintais próprios).
const TREE_SKIP_ROADS := ["south_port_", "vertice_", "map2_", "mountain_bridge", "salvage_", "cobra_"]
# Prédios por onde entra e sai veículo: árvore na frente bloquearia a garagem.
const VEHICLE_KINDS := ["garage", "warehouse", "fire_station", "police_precinct", "artisan_workshop", "hospital"]

## Largura ao longo da fachada e profundidade (m) de cada peça do térreo.
const ITEMS := {
	"cafe_set": Vector2(1.7, 1.5), "cafe_parasol": Vector2(2.3, 1.5), "cafe_parasol_b": Vector2(2.3, 1.5), "produce_stand": Vector2(1.8, 0.9),
	"a_frame": Vector2(0.7, 0.5), "beer_crates": Vector2(0.9, 0.4), "pot_plant": Vector2(0.75, 0.75),
	"wheelie_bins": Vector2(1.4, 0.75), "bike_rack": Vector2(2.6, 0.7), "pallet_stack": Vector2(1.3, 1.05),
	"tire_stack": Vector2(1.5, 0.75), "drums": Vector2(1.3, 0.85), "food_cart": Vector2(2.0, 0.8),
	"ice_freezer": Vector2(1.2, 0.7), "clothes_rack": Vector2(1.6, 0.6), "flower_buckets": Vector2(1.4, 0.6),
	"gas_cylinders": Vector2(1.1, 0.45), "door_bench": Vector2(1.3, 0.5), "motorcycle": Vector2(2.0, 0.8),
}
const FRONTAGE_KINDS := ["cafe_set", "cafe_parasol", "cafe_parasol_b", "produce_stand", "a_frame", "beer_crates", "pot_plant", "wheelie_bins", "bike_rack",
	"pallet_stack", "tire_stack", "drums", "food_cart", "ice_freezer", "clothes_rack", "flower_buckets", "gas_cylinders", "door_bench", "motorcycle"]
# "curb": o que fica no meio-fio, de lado para a rua (moto parada, carrinho de lanche);
# "curb_chance": probabilidade por fachada de pôr uma dessas peças.
const CAFE := {"items": [["cafe_parasol", 0.24], ["cafe_parasol_b", 0.16], ["cafe_set", 0.3], ["a_frame", 0.1], ["beer_crates", 0.08], ["ice_freezer", 0.07], ["gas_cylinders", 0.05]],
	"fill": 0.85, "door_pots": false, "curb": [["motorcycle", 0.6], ["food_cart", 0.4]], "curb_chance": 0.7}
const PRODUCE := {"items": [["produce_stand", 0.4], ["flower_buckets", 0.15], ["a_frame", 0.12], ["pot_plant", 0.13], ["beer_crates", 0.1], ["ice_freezer", 0.1]],
	"fill": 0.8, "door_pots": false, "curb": [["motorcycle", 0.7], ["food_cart", 0.3]], "curb_chance": 0.5}
const STORE := {"items": [["clothes_rack", 0.35], ["a_frame", 0.2], ["flower_buckets", 0.15], ["pot_plant", 0.2], ["bike_rack", 0.1]],
	"fill": 0.7, "door_pots": true, "curb": [["motorcycle", 1.0]], "curb_chance": 0.4}
const HOME := {"items": [["wheelie_bins", 0.3], ["pot_plant", 0.28], ["bike_rack", 0.22], ["door_bench", 0.2]],
	"fill": 0.45, "door_pots": true, "curb": [["motorcycle", 1.0]], "curb_chance": 0.25}
const WORK := {"items": [["pallet_stack", 0.3], ["drums", 0.25], ["tire_stack", 0.3], ["gas_cylinders", 0.15]],
	"fill": 0.5, "door_pots": false, "curb": [["motorcycle", 1.0]], "curb_chance": 0.3}
# Lugares com fachada e acesso próprios (posto, polícia, clínica, bombeiros, oficina do Maciota).
const SKIP_IDS := ["NorthFrontage4", "Police", "Clinic", "NorthFireStation", "Garage"]
# Passagem mínima que a peça deixa até o meio-fio.
const WALK_CLEARANCE := 0.9
const WALL_GAP := 0.15


static func _theme(kind: String, id: String) -> Dictionary:
	match kind:
		"corner_shop": return CAFE
		"shop":
			# Loja de rua: um terço quitanda, um terço bar, um terço loja de roupa/flor.
			var roll := DRESSING._roll(id + "|theme")
			return PRODUCE if roll < 0.34 else (CAFE if roll < 0.67 else STORE)
		"warehouse_shop": return PRODUCE
		"commercial_laundromat": return {"items": [["a_frame", 0.3], ["pot_plant", 0.3], ["wheelie_bins", 0.2], ["bike_rack", 0.2]], "fill": 0.55, "door_pots": false, "curb": [["motorcycle", 1.0]], "curb_chance": 0.3}
		"bank_branch", "office", "urban_deco": return {"items": [["pot_plant", 0.45], ["bike_rack", 0.35], ["wheelie_bins", 0.2]], "fill": 0.4, "door_pots": true, "curb": [["motorcycle", 1.0]], "curb_chance": 0.2}
		"brownstone", "rowhouse", "rowhouse_terrace", "l_shaped_block", "house_duplex", "urban_infill": return HOME
		"warehouse", "artisan_workshop", "garage": return WORK
	return {}


# ---------------------------------------------------------------------------
# Contexto compartilhado: o que já ocupa o chão perto do chunk.

## Árvores, bancos e postes autorais, objetos do editor (a passarela vira
## retângulo) e o que esta camada já pôs. Uma vez por chunk.
static func _prepare(context: Dictionary) -> void:
	if context.has("fill_obstacles"): return
	var obstacles: Array = []
	var rects: Array[Rect2] = []
	var region: Node = context.region
	var records: Variant = region.get("records")
	if records is Dictionary:
		var area: Rect2 = (context.rect as Rect2).grow(8.0)
		var first: Vector2i = region._cell(Vector3(area.position.x, 0, area.position.y))
		var last: Vector2i = region._cell(Vector3(area.end.x, 0, area.end.y))
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				for record in records.get(Vector2i(x, y), []):
					_record_obstacle(record, obstacles, rects)
	context.fill_obstacles = obstacles
	context.fill_rects = rects
	context.occupied = []


static func _record_obstacle(record: Dictionary, obstacles: Array, rects: Array[Rect2]) -> void:
	var position: Variant = record.get("position")
	if not position is Vector3: return
	var point := Vector2(position.x, position.z)
	match str(record.get("kind", "")):
		"harbor_prop":
			var prop_kind := str(record.get("data", {}).get("kind", ""))
			obstacles.append([point, 3.2 if prop_kind == "tree" else 1.4])
		"tree": obstacles.append([point, 3.2])
		"editor_light": obstacles.append([point, 1.4])
		"editor_prop":
			var row: Dictionary = record.get("data", {})
			var size: Array = row.get("size", [1.0, 1.0])
			var extent := Vector2(float(size[0]), float(size[1])) * float(row.get("scale", 1.0)) * 0.5
			var yaw := deg_to_rad(float(row.get("rotation", 0.0)))
			var half := Vector2(absf(cos(yaw)) * extent.x + absf(sin(yaw)) * extent.y, absf(sin(yaw)) * extent.x + absf(cos(yaw)) * extent.y)
			# A passarela tem escada sobre a calçada e tabuleiro a 5,6 m: nada de copa embaixo.
			rects.append(Rect2(point - half, half * 2.0).grow(1.0))


static func _blocked(context: Dictionary, point: Vector2, radius: float) -> bool:
	for obstacle in context.fill_obstacles:
		if point.distance_to(obstacle[0]) < float(obstacle[1]) + radius: return true
	for rect: Rect2 in context.fill_rects:
		if rect.grow(radius).has_point(point): return true
	for taken in context.occupied:
		if point.distance_to(taken[0]) < float(taken[1]) + radius: return true
	return false


static func occupied_near(context: Dictionary, point: Vector2, radius: float) -> bool:
	for taken in context.get("occupied", []):
		if point.distance_to(taken[0]) < float(taken[1]) + radius: return true
	return false


## Regras de chão que o mobiliário já respeita (ponte, oficina, esgoto, metrô).
static func _public_ground(context: Dictionary, point: Vector2, margin: float) -> bool:
	if WORLD_CONNECTION.reserves_approach_for_driving(point): return false
	if BRIDGE_SURFACE.owns_surface_point(point): return false
	if DRESSING._workshop_driving(point): return false
	if point.distance_to(DRESSING.SEWER_ACCESS) < DRESSING.SEWER_CLEARANCE + margin: return false
	for rect: Rect2 in context.get("transit_reservations", []):
		if rect.grow(margin + 0.6).has_point(point): return false
	return true


# ---------------------------------------------------------------------------
# 1. Árvores de rua.

static func street_trees(context: Dictionary, batches: Dictionary) -> void:
	if not enabled: return
	_prepare(context)
	for road in context.roads:
		var id := str(road.id)
		var skipped := false
		for prefix: String in TREE_SKIP_ROADS:
			if id.begins_with(prefix): skipped = true
		# Vielas de 4,5 m (serviço, pátio): calçada estreita, a copa fecharia a rua.
		if skipped or float(road.width) < 5.0: continue
		var points: PackedVector2Array = road.points
		var width: float = road.width
		var travelled := 0.0
		for index in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var length := a.distance_to(b)
			if length < 0.01: continue
			var tangent := (b - a) / length
			var normal := Vector2(tangent.y, -tangent.x)
			# Meio passo de defasagem: a árvore cai entre dois postes, não em cima deles.
			var s := fposmod(-travelled + TREE_SPACING * 0.5, TREE_SPACING)
			while s < length:
				for side in [-1.0, 1.0]:
					var key := "%s|tree|%d|%d|%d" % [id, index, int(s * 10.0), int(side)]
					if DRESSING._roll(key) > 0.8: continue
					var jitter := (DRESSING._roll(key + "j") - 0.5) * 3.0
					var outward: Vector2 = normal * side
					var point := a + tangent * clampf(s + jitter, 0.0, length) + outward * (width * 0.5 + TREE_CURB_OFFSET)
					if not _tree_fits(context, point): continue
					var yaw := DRESSING._roll(key + "yaw") * TAU
					var kind: String = TREE_KINDS[0] if DRESSING._roll(key + "kind") < 0.6 else TREE_KINDS[1]
					DRESSING._add(batches, kind, Vector3(point.x, 0.0, point.y), Vector2(sin(yaw), cos(yaw)), 0.88 + DRESSING._roll(key + "size") * 0.24)
					context.occupied.append([point, 1.3])
					# Gola de terra alinhada com a rua: assenta o tronco no chão.
					var pit_yaw := atan2(tangent.x, tangent.y)
					DRESSING._push(batches, "decal:tree_pit", Transform3D(Basis(Vector3.UP, pit_yaw).scaled(Vector3(1.25, 1, 1.25)), Vector3(point.x, DRESSING.DECAL_Y + 0.002, point.y)))
				s += TREE_SPACING
			travelled += length


static func _tree_fits(context: Dictionary, point: Vector2) -> bool:
	if not DRESSING._in_chunk(context, point): return false
	# Copa (~2,6 m de largura a 3-5 m de altura) longe do braço do semáforo e da cabeça do poste:
	# com 4 m de folga na esquina a árvore nascia colada no poste do semáforo (captura de 17/10).
	if DRESSING._near_junction(context, point, 7.0) or DRESSING._near_lamp(context, point, 4.0): return false
	if DRESSING._road_clearance(context, point) < 0.3: return false
	if DRESSING._inside_building(context, point, 1.6): return false
	for entry in context.buildings:
		if str(entry.data.get("kind", "")) in VEHICLE_KINDS and (entry.rect as Rect2).grow(3.5).has_point(point): return false
	if not _public_ground(context, point, 1.5): return false
	return not _blocked(context, point, 0.0)


## Tronco sólido (o carro para, como nas árvores autorais); a copa não tem colisão.
static func add_trunk_collision(chunk: Node3D, batches: Dictionary) -> void:
	var placements: Array = []
	for kind in TREE_KINDS: placements.append_array(batches.get(kind, []))
	if placements.is_empty(): return
	var body := StaticBody3D.new()
	body.name = "CityStreetTreeTrunks"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = TREE_TRUNK_RADIUS
	shape.height = 3.0
	var to_local := chunk.global_transform.affine_inverse()
	for placement: Transform3D in placements:
		var collision := CollisionShape3D.new()
		collision.shape = shape
		# Sem escala: forma com escala não uniforme desanda na física.
		collision.transform = to_local * Transform3D(Basis.IDENTITY, placement.origin + Vector3(0, 1.5, 0))
		body.add_child(collision)
	chunk.add_child(body)


# ---------------------------------------------------------------------------
# 2. Térreo que transborda para a calçada.

static func frontage(chunk: Node3D, context: Dictionary, batches: Dictionary) -> void:
	if not enabled: return
	_prepare(context)
	var doors := _door_points(chunk)
	for entry in context.buildings:
		var rect: Rect2 = entry.rect
		if not DRESSING._in_chunk(context, rect.get_center()): continue
		var data: Dictionary = entry.data
		var id := str(data.get("id", ""))
		if id in SKIP_IDS: continue
		var theme := _theme(str(data.get("kind", "")), id)
		if theme.is_empty(): continue
		for side in 4: _dress_side(context, batches, rect, side, theme, id, doors)


## Pontos de porta, entrada, escada de entrada e varanda dos prédios já montados
## no chunk (vão pintado `Doorway_*`, folha `Door`, `ShopDoor`, `Stoop_*`...).
static func _door_points(chunk: Node3D) -> PackedVector2Array:
	var result := PackedVector2Array()
	for child in chunk.get_children():
		if not child is Node3D or not child.is_in_group("exterior_reveal_building"): continue
		if child.has_meta("entry_position"):
			var entry: Vector3 = child.get_meta("entry_position")
			result.append(Vector2(entry.x, entry.z))
		for node in child.find_children("*", "Node3D", true, false):
			var label := String(node.name)
			if label.containsn("door") or label.begins_with("Stoop_") or label.contains("Porch") or label.containsn("entrance"):
				var at: Vector3 = node.global_position
				result.append(Vector2(at.x, at.z))
	return result


static func _dress_side(context: Dictionary, batches: Dictionary, rect: Rect2, side: int, theme: Dictionary, id: String, doors: PackedVector2Array) -> void:
	var a: Vector2
	var b: Vector2
	var normal: Vector2
	match side:
		0: a = Vector2(rect.position.x, rect.end.y); b = rect.end; normal = Vector2(0, 1)
		1: a = rect.position; b = Vector2(rect.end.x, rect.position.y); normal = Vector2(0, -1)
		2: a = rect.position; b = Vector2(rect.position.x, rect.end.y); normal = Vector2(-1, 0)
		_: a = Vector2(rect.end.x, rect.position.y); b = rect.end; normal = Vector2(1, 0)
	var length := a.distance_to(b)
	if length < 2.5: return
	var along := (b - a) / length
	# De frente para a rua: andando para fora a via chega quase metro a metro.
	var middle := (a + b) * 0.5
	var near := DRESSING._road_clearance(context, middle + normal * 0.4)
	var far := DRESSING._road_clearance(context, middle + normal * 1.4)
	if far > near - 0.7 or near > 9.0 or near < 1.6: return
	# Vãos de porta desta fachada, em intervalos ao longo dela.
	var blocked: Array = []
	for door in doors:
		var offset := door - a
		var depth := offset.dot(normal)
		if depth < -2.5 or depth > 2.0: continue
		var at := offset.dot(along)
		if at < -1.0 or at > length + 1.0: continue
		blocked.append(Vector2(at - 0.7, at + 0.7))
	blocked = _merge(blocked)
	if theme.door_pots:
		for span: Vector2 in blocked:
			if DRESSING._roll("%s|pots|%d|%d" % [id, side, int(span.x * 10.0)]) > 0.7: continue
			# Um de cada lado, encostado na folga de 0,3 m que _try_place exige do vão.
			for start in [span.x - 0.32 - ITEMS.pot_plant.x, span.y + 0.32]:
				_try_place(context, batches, "pot_plant", a, along, normal, start, length, blocked)
	var cursor := 0.4 + DRESSING._roll(id + "|start|" + str(side)) * 1.0
	var guard := 0
	var last := ""
	var placed := {}
	while cursor < length - 0.4 and guard < 48:
		guard += 1
		var key := "%s|front|%d|%d" % [id, side, int(cursor * 10.0)]
		if DRESSING._roll(key + "gap") > float(theme.fill):
			cursor += 1.4 + DRESSING._roll(key + "skip") * 2.0
			continue
		var kind := _pick_varied(theme, key, last, placed)
		var size: Vector2 = ITEMS[kind]
		if not _try_place(context, batches, kind, a, along, normal, cursor, length, blocked):
			cursor += 0.6
			continue
		last = kind
		placed[kind] = true
		# Mesas de bar saem em grupo: a próxima vem quase colada.
		cursor += size.x + (0.25 if kind.begins_with("cafe") else 0.5 + DRESSING._roll(key + "after") * 1.2)
	_curb_extra(context, batches, a, along, normal, length, theme, id, side, near)


## Peças de vitrine que aparecem uma vez por fachada; repetidas em fila (três freezers
## na bicicletaria, captura de 17/10) liam como cópia e cola.
const SINGLE_KINDS := ["ice_freezer", "food_cart", "flower_buckets", "clothes_rack", "gas_cylinders", "door_bench"]


## Sorteio que não repete a peça anterior (mesa de bar pode, sai em grupo) nem as únicas.
static func _pick_varied(theme: Dictionary, key: String, last: String, placed: Dictionary) -> String:
	var kind := ""
	for attempt in 4:
		kind = DRESSING._pick(theme.items, DRESSING._roll(key + ("" if attempt == 0 else "r%d" % attempt)))
		if kind.is_empty(): kind = str(theme.items[0][0])
		var repeated := kind == last and not kind.begins_with("cafe")
		if not repeated and not (kind in SINGLE_KINDS and placed.has(kind)): return kind
	return kind


## Uma peça de meio-fio por fachada (moto parada, carrinho de lanche), de lado
## para a rua, a 0,55 m da guia; nunca na frente da porta.
static func _curb_extra(context: Dictionary, batches: Dictionary, a: Vector2, along: Vector2, normal: Vector2, length: float, theme: Dictionary, id: String, side: int, near: float) -> void:
	var key := "%s|curb|%d" % [id, side]
	if not theme.has("curb") or DRESSING._roll(key) > float(theme.curb_chance): return
	var kind := DRESSING._pick(theme.curb, DRESSING._roll(key + "kind"))
	if kind.is_empty(): kind = str(theme.curb[0][0])
	var size: Vector2 = ITEMS[kind]
	# Distância da parede à guia medida no meio da fachada (0,4 m para fora + folga).
	var to_curb := near + 0.4
	for attempt in 3:
		var at := (0.2 + DRESSING._roll(key + "at" + str(attempt)) * 0.6) * length
		var center := a + along * at + normal * (to_curb - 0.55 - size.y * 0.5)
		var clearance := DRESSING._road_clearance(context, center)
		if clearance < size.y * 0.5 + 0.2 or clearance > size.y * 0.5 + 1.2: continue
		if not DRESSING._in_chunk(context, center) and not (context.rect as Rect2).grow(12.0).has_point(center): continue
		if DRESSING._inside_building(context, center, 0.3): continue
		if DRESSING._near_junction(context, center, 3.0) or DRESSING._near_lamp(context, center, 0.6 + size.x * 0.5): continue
		if not _public_ground(context, center, size.x * 0.5): continue
		if _blocked(context, center, size.x * 0.5): continue
		# Frente (+Z local) ao longo da rua: a peça fica de lado para o trânsito.
		DRESSING._add(batches, kind, Vector3(center.x, 0.012, center.y), along if DRESSING._roll(key + "dir") < 0.5 else -along)
		context.occupied.append([center, size.x * 0.5])
		return


## `start` é a ponta da peça ao longo da fachada (metros a partir de `a`).
static func _try_place(context: Dictionary, batches: Dictionary, kind: String, a: Vector2, along: Vector2, normal: Vector2, start: float, length: float, blocked: Array) -> bool:
	var size: Vector2 = ITEMS[kind]
	if start < 0.2 or start + size.x > length - 0.2: return false
	for span: Vector2 in blocked:
		if start < span.y + 0.3 and start + size.x > span.x - 0.3: return false
	var center := a + along * (start + size.x * 0.5) + normal * (WALL_GAP + size.y * 0.5)
	if not DRESSING._in_chunk(context, center) and not (context.rect as Rect2).grow(12.0).has_point(center): return false
	if DRESSING._road_clearance(context, center) < size.y * 0.5 + WALK_CLEARANCE: return false
	var ends := [center - along * size.x * 0.5, center + along * size.x * 0.5, center + normal * size.y * 0.5]
	for point: Vector2 in ends:
		if DRESSING._inside_building(context, point, 0.05): return false
	if DRESSING._near_junction(context, center, 1.5) or DRESSING._near_lamp(context, center, 0.9 + size.x * 0.5): return false
	if not _public_ground(context, center, size.x * 0.5): return false
	if _blocked(context, center, maxf(size.x, size.y) * 0.5): return false
	DRESSING._add(batches, kind, Vector3(center.x, 0.012, center.y), normal)
	context.occupied.append([center, maxf(size.x, size.y) * 0.5])
	return true


static func _merge(spans: Array) -> Array:
	if spans.is_empty(): return spans
	spans.sort_custom(func(left: Vector2, right: Vector2): return left.x < right.x)
	var merged: Array = [spans[0]]
	for index in range(1, spans.size()):
		var span: Vector2 = spans[index]
		var last: Vector2 = merged[-1]
		if span.x <= last.y + 0.5: merged[-1] = Vector2(last.x, maxf(last.y, span.y))
		else: merged.append(span)
	return merged
