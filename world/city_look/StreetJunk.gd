extends RefCounted
## Sujeira de cidade portuária nas ruas de Harbor (pedido do jogador de 29/10: "as ruas de
## Harbor são muito limpas para uma cidade portuária"). Um passo próprio do CityChunkDressing,
## depois do mobiliário e do entorno dos prédios e antes do _flush: só acrescenta colocações
## às MultiMesh por tipo do chunk (malhas em StreetJunkKit, um material de atlas), então custa
## um draw call por tipo presente no chunk, como o resto do kit.
##
## O que entra, em ordem (o orçamento do chunk vale nessa ordem):
## 1. saco, pilha ou papelão encostado nas lixeiras e caçambas que já existem;
## 2. monte de lixo na esquina (o "ponto de lixo" que a coleta ainda não passou);
## 3. beira do cais: rede, cabo, caixa de peixe e tambor no porto; na frente sul, a orla com
##    mesa de boteco, guarda-sol, cadeira de praia e pilha de cadeiras de plástico;
## 4. caçamba de entulho no beco de casas e galpões, com o monte de reforma ao lado;
## 5. o meio-fio inteiro, com chance e cardápio por bairro: o porto e a zona industrial
##    sujam mais (caixote, tambor, pneu, entulho), o centro tem saco e papelão de loja e o
##    bairro residencial é o mais limpo.
##
## Sorteio determinístico (hash do id da via, do trecho, da quina ou do prédio), como o resto
## do CityLook: o mesmo chunk recarregado volta igual. Cada peça só nasce no chunk que contém
## o ponto dela. Tudo o que é leve é registrado no FragileProps3D pelo _flush (o carro
## derruba e empurra). GETECO_STREET_JUNK=0 desliga a camada inteira (A/B no mesmo export).

const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const FILL := preload("res://world/city_look/SidewalkFill.gd")
const JUNK_KIT := preload("res://world/city_look/StreetJunkKit.gd")
const SHAPE := preload("res://world/shape/WorldShape.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const PORT_LAYOUT := preload("res://world/regions/OriginalSouthPortLayout.gd")

static var enabled := OS.get_environment("GETECO_STREET_JUNK") != "0"

## Teto por chunk e por tipo: a pior combinação (porto com cais e via larga) ainda fica em
## poucas centenas de triângulos por tipo e numa MultiMesh por tipo.
const MAX_ITEMS := 64
const MAX_PER_KIND := 14
const CURB_SPACING := 6.5
const QUAY_SPACING := 6.5

## Raio do que a peça ocupa no chão (sobreposição e folga de porta, poste e meio-fio).
const RADIUS := {"bag_single": 0.35, "bag_pile": 0.75, "bag_torn": 0.75, "cardboard": 0.7, "refuse_heap": 1.15,
	"wood_crates": 0.7, "fish_crates": 0.7, "rusty_barrels": 0.75, "rope_coil": 0.7, "fishing_net": 0.85, "loose_tires": 0.65,
	"rubble": 0.9, "rubble_skip": 1.75, "beach_parasol": 0.6, "beach_parasol_b": 0.6, "beach_chairs": 0.9, "plastic_chairs": 0.6, "bar_table": 1.1}

## Cardápio do meio-fio por bairro (pesos somam 1).
const TABLES := {
	"downtown": [["bag_single", 0.3], ["bag_pile", 0.22], ["cardboard", 0.2], ["bag_torn", 0.14], ["wood_crates", 0.06], ["plastic_chairs", 0.04], ["refuse_heap", 0.04]],
	"residential": [["bag_single", 0.36], ["bag_pile", 0.2], ["bag_torn", 0.1], ["cardboard", 0.08], ["rubble", 0.14], ["loose_tires", 0.06], ["refuse_heap", 0.06]],
	"industrial": [["wood_crates", 0.16], ["rusty_barrels", 0.16], ["loose_tires", 0.14], ["cardboard", 0.1], ["bag_pile", 0.1], ["rubble", 0.12], ["bag_torn", 0.06], ["fish_crates", 0.06], ["refuse_heap", 0.1]],
	"port": [["wood_crates", 0.18], ["fish_crates", 0.16], ["rusty_barrels", 0.15], ["rope_coil", 0.12], ["fishing_net", 0.1], ["loose_tires", 0.1], ["bag_pile", 0.06], ["cardboard", 0.07], ["rubble", 0.06]],
	"shore": [["bag_single", 0.22], ["bag_pile", 0.16], ["fish_crates", 0.14], ["rope_coil", 0.12], ["cardboard", 0.1], ["bag_torn", 0.1], ["wood_crates", 0.08], ["plastic_chairs", 0.08]],
}
## Chance por vaga de 6,5 m de meio-fio, por lado: porto e indústria sujam mais.
## Primeira rodada (0,5/0,36/0,26/0,22/0,15 a cada 8 m) deu ~4 peças por chunk no centro e a captura
## quase não mudou (30/10): as folgas de porta, poste e mobiliário recusam boa parte das vagas.
const CURB_CHANCE := {"port": 0.62, "industrial": 0.5, "shore": 0.38, "downtown": 0.4, "residential": 0.28}
const CORNER_CHANCE := {"port": 0.5, "industrial": 0.42, "shore": 0.3, "downtown": 0.32, "residential": 0.24}
const BIN_CHANCE := {"port": 0.7, "industrial": 0.6, "shore": 0.5, "downtown": 0.5, "residential": 0.38}
const QUAY_GEAR := [["rope_coil", 0.28], ["fishing_net", 0.24], ["fish_crates", 0.2], ["wood_crates", 0.1], ["rusty_barrels", 0.12], ["loose_tires", 0.06]]

const INDUSTRIAL_KINDS := ["warehouse", "artisan_workshop", "garage", "warehouse_shop", "fire_station"]
const RESIDENTIAL_KINDS := ["brownstone", "rowhouse", "rowhouse_terrace", "l_shaped_block", "house_duplex", "urban_infill", "cobra_house"]
## Vias sem calçada de cidade nem ocupação (rodovia do mapa 2, ponte da serra, estrada rural).
const SKIP_ROADS := ["map2_", "mountain_bridge", "vertice_"]
## Pegada no chão do mobiliário que já existe no lote (o SidewalkFill só conhece o que ele pôs).
const FURNITURE_RADIUS := {"hydrant": 0.5, "trash_can": 0.5, "news_box": 0.7, "mailbox": 0.5, "phone_booth": 0.8, "bench_seat": 1.1, "dumpster": 1.3,
	"trash_bags": 0.7, "planter": 0.8, "bollard": 0.3, "signal_pole": 0.8, "stop_sign": 0.4, "street_tree": 1.0, "street_tree_b": 1.0}


## Tudo de uma vez (CityChunkDressing.build_chunk, testes).
static func dress(chunk: Node3D, context: Dictionary, batches: Dictionary) -> void:
	var job := begin(chunk, context, batches)
	while not step(job, INF): pass


## Prepara o chunk (obstáculos, costa, portas); o resto anda por step() em fatias.
static func begin(chunk: Node3D, context: Dictionary, batches: Dictionary) -> Dictionary:
	if not enabled: return {"done": true}
	var began := Time.get_ticks_usec()
	FILL._prepare(context)
	if not context.has("fill_doors"): context.fill_doors = FILL._door_points(chunk)
	var job := {"done": false, "chunk": chunk, "context": context, "batches": batches, "phase": 0, "road": 0, "work_usec": 0, "max_usec": 0}
	job.site = _site(context, batches)
	_account(job, began)
	return job


## Uma fatia de até `budget_usec`: as fases curtas (lixeira, esquina, cais, beco) e o meio-fio
## via a via. Devolve true quando terminou. Span próprio: um pico mostra este nome no log.
static func step(job: Dictionary, budget_usec := 1500.0) -> bool:
	if bool(job.done): return true
	var began := Time.get_ticks_usec()
	var span := STALL_WORK.begin()
	var context: Dictionary = job.context
	var batches: Dictionary = job.batches
	var site: Dictionary = job.site
	while int(job.phase) < 5:
		match int(job.phase):
			0: _beside_bins(context, batches, site)
			1: _corners(context, batches, site)
			2: _quay_edge(context, batches, site)
			3: _alley_skips(context, batches, site)
			4:
				var roads: Array = context.roads
				while int(job.road) < roads.size():
					_curb_road(context, batches, site, roads[int(job.road)])
					job.road = int(job.road) + 1
					if int(job.road) < roads.size() and Time.get_ticks_usec() - began >= budget_usec:
						_account(job, began)
						STALL_WORK.finish_slow("stream.harbor.street_junk", span, 2000)
						return false
		job.phase = int(job.phase) + 1
		if int(job.phase) < 5 and Time.get_ticks_usec() - began >= budget_usec:
			_account(job, began)
			STALL_WORK.finish_slow("stream.harbor.street_junk", span, 2000)
			return false
	_account(job, began)
	var chunk: Node3D = job.chunk
	if is_instance_valid(chunk):
		chunk.set_meta("street_junk_items", int(site.count))
		chunk.set_meta("street_junk_ms", float(job.work_usec) / 1000.0)
		chunk.set_meta("street_junk_step_max_ms", float(job.max_usec) / 1000.0)
	job.done = true
	STALL_WORK.finish_slow("stream.harbor.street_junk", span, 2000)
	return true


static func _account(job: Dictionary, began: int) -> void:
	var elapsed := Time.get_ticks_usec() - began
	job.work_usec = int(job.work_usec) + elapsed
	job.max_usec = maxi(int(job.max_usec), elapsed)


# ---------------------------------------------------------------------------
# Contexto do chunk: obstáculos que o CityLook não conhecia (porto, praças, cais).

static func _site(context: Dictionary, batches: Dictionary) -> Dictionary:
	var rect: Rect2 = context.rect
	var site := {"count": 0, "per_kind": {}, "blocks": [], "circles": [], "rails": [], "furniture": [], "coast": [], "quay": [], "polygon": PackedVector2Array()}
	var region: Node = context.region
	var records: Variant = region.get("records")
	if records is Dictionary and region.has_method("_cell"):
		var area := rect.grow(12.0)
		var first: Vector2i = region._cell(Vector3(area.position.x, 0, area.position.y))
		var last: Vector2i = region._cell(Vector3(area.end.x, 0, area.end.y))
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				for record in records.get(Vector2i(x, y), []):
					_record_block(record, site)
	var entries: Variant = region.get("entries")
	if entries is Array:
		for entry in entries:
			var point: Vector3 = entry.get("exterior_position", entry.get("position", Vector3.INF))
			if point.is_finite() and rect.grow(4.0).has_point(Vector2(point.x, point.z)): site.circles.append([Vector2(point.x, point.z), 2.2])
	# Zonas autorais da rota (rodoviária, delegacia, oficina do Maciota): têm mobiliário próprio.
	for zone in [HarborRouteDetail3D.ZONE_RODOVIARIA, HarborRouteDetail3D.ZONE_CONNECTING_STREETS, HarborRouteDetail3D.ZONE_DELEGACIA, HarborRouteDetail3D.ZONE_MACIOTA]:
		var box: AABB = HarborRouteDetail3D.get_zone_bounds(zone)
		site.blocks.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(1.0))
	for kind in FURNITURE_RADIUS:
		for placement: Transform3D in batches.get(kind, []):
			if placement.origin.y < 0.6: site.furniture.append([Vector2(placement.origin.x, placement.origin.z), float(FURNITURE_RADIUS[kind])])
	if region.get("region_id") == "harbor": _coast(site, rect)
	return site


static func _record_block(record: Dictionary, site: Dictionary) -> void:
	var position: Variant = record.get("position")
	var at := Vector2(position.x, position.z) if position is Vector3 else Vector2.INF
	match str(record.get("kind", "")):
		"container":
			var size: Vector2 = record.get("size", Vector2(12, 2.5))
			site.blocks.append(Rect2(at - size * 0.5, size).abs().grow(1.4))
		"south_port_model":
			var footprint: Rect2 = record.get("footprint", Rect2())
			site.blocks.append(Rect2(footprint.position / 16.0, footprint.size / 16.0).abs().grow(2.0))
		"south_port_rail":
			var a: Vector3 = record.get("a", Vector3.ZERO)
			var b: Vector3 = record.get("b", Vector3.ZERO)
			site.rails.append([Vector2(a.x, a.z), Vector2(b.x, b.z)])
		"harbor_restaurant": site.circles.append([at, 3.2])
		"harbor_public_realm": _public_realm(str(record.get("zone_id", "")), at, site)
		"harbor_dressing", "cemetery", "salvage": site.circles.append([at, 32.0])
		"harbor_bridge": site.circles.append([at, 18.0])
		"original_facade":
			var data: Dictionary = record.get("data", {})
			var size: Variant = data.get("size")
			if size is Vector2: site.blocks.append(Rect2(at - size * 0.5, size).grow(1.5))
			else: site.circles.append([at, 6.0])


## Praças e calçadão autorais (HarborPublicRealm3D): o calçadão norte tem canteiros e bancos
## na faixa do cais, exatamente onde a orla entra; o resto vira um círculo largo.
static func _public_realm(zone_id: String, at: Vector2, site: Dictionary) -> void:
	var pieces := []
	match zone_id:
		"northbank_promenade_west": pieces = [[-39.06, Vector2(7.81, 4.06)], [-5.78, Vector2(9.69, 3.88)], [-30.31, Vector2(2.8, 0.72)], [8.75, Vector2(2.8, 0.72)]]
		"northbank_promenade_east": pieces = [[-16.88, Vector2(5.94, 3.63)], [20.94, Vector2(8.13, 4.5)], [-8.13, Vector2(2.8, 0.72)], [10.63, Vector2(2.8, 0.72)]]
		_:
			site.circles.append([at, 14.0])
			return
	for piece in pieces:
		var size: Vector2 = piece[1]
		site.blocks.append(Rect2(at + Vector2(float(piece[0]), 0.0) - size * 0.5, size).grow(1.2))


## Costa de Harbor perto do chunk: todos os trechos (para não pôr nada na água) e, à parte,
## os de cais, com a normal que aponta para a terra.
static func _coast(site: Dictionary, rect: Rect2) -> void:
	var island := {}
	for candidate in SHAPE.islands():
		if candidate.id == "harbor": island = candidate
	if island.is_empty(): return
	var polygon: PackedVector2Array = island.polygon
	var area := rect.grow(20.0)
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		if not Rect2(a, b - a).abs().grow(1.0).intersects(area): continue
		site.coast.append([a, b])
		site.polygon = polygon
		if SHAPE.kind_at(island, i) != "quay" or a.distance_to(b) < 1.0: continue
		var along := (b - a).normalized()
		var normal := Vector2(along.y, -along.x)
		var middle := (a + b) * 0.5
		if not Geometry2D.is_point_in_polygon(middle + normal * 1.5, polygon): normal = -normal
		site.quay.append({"a": a, "b": b, "index": i, "normal": normal})


static func _coast_distance(site: Dictionary, point: Vector2) -> float:
	var best := INF
	for segment in site.coast:
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])))
	return best


# ---------------------------------------------------------------------------
# Bairro de um ponto.

static func zone(context: Dictionary, site: Dictionary, point: Vector2) -> String:
	if _port_land().has_point(point): return "port"
	for segment in site.quay:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, segment.a, segment.b)) < 14.0: return "shore"
	var nearest := INF
	var kind := ""
	for entry in context.buildings:
		var distance := _rect_distance(entry.rect, point)
		if distance < nearest:
			nearest = distance
			kind = str(entry.data.get("kind", ""))
	if nearest > 16.0: return "downtown"
	if kind in INDUSTRIAL_KINDS: return "industrial"
	if kind in RESIDENTIAL_KINDS: return "residential"
	return "downtown"


static func _port_land() -> Rect2:
	return Rect2(PORT_LAYOUT.LAND.position / 16.0, PORT_LAYOUT.LAND.size / 16.0)


static func _rect_distance(rect: Rect2, point: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return Vector2(dx, dy).length()


# ---------------------------------------------------------------------------
# Validação e colocação.

## O ponto `point` aceita uma peça de raio `radius`? `road_margin` é a folga mínima até o asfalto.
static func _fits(context: Dictionary, site: Dictionary, point: Vector2, radius: float, road_margin := 0.15, near_junction := true) -> bool:
	if not DRESSING._in_chunk(context, point): return false
	if near_junction and DRESSING._near_junction(context, point, 0.5 + radius): return false
	if DRESSING._near_lamp(context, point, 0.7 + radius): return false
	if DRESSING._road_clearance(context, point) < radius + road_margin: return false
	if DRESSING._inside_building(context, point, radius + 0.1): return false
	if not FILL._public_ground(context, point, radius): return false
	if FILL._blocked(context, point, radius): return false
	for door: Vector2 in context.get("fill_doors", PackedVector2Array()):
		if point.distance_to(door) < 1.5 + radius: return false
	for item in site.furniture:
		if point.distance_to(item[0]) < float(item[1]) + radius: return false
	for block: Rect2 in site.blocks:
		if block.grow(radius).has_point(point): return false
	for circle in site.circles:
		if point.distance_to(circle[0]) < float(circle[1]) + radius: return false
	for rail in site.rails:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, rail[0], rail[1])) < 2.2 + radius: return false
	if not site.coast.is_empty():
		var shore := _coast_distance(site, point)
		if shore < radius + 0.7: return false
		if shore < 40.0 and not Geometry2D.is_point_in_polygon(point, site.polygon): return false
	return true


static func _place(context: Dictionary, batches: Dictionary, site: Dictionary, kind: String, point: Vector2, forward: Vector2) -> bool:
	if int(site.count) >= MAX_ITEMS or int(site.per_kind.get(kind, 0)) >= MAX_PER_KIND: return false
	DRESSING._add(batches, kind, Vector3(point.x, 0.012, point.y), forward.normalized() if forward.length_squared() > 0.0001 else Vector2(0, 1))
	context.occupied.append([point, float(RADIUS[kind])])
	site.count = int(site.count) + 1
	site.per_kind[kind] = int(site.per_kind.get(kind, 0)) + 1
	return true


## Gira `forward` por até ±`spread` rad, pelo sorteio da chave: a pilha não sai alinhada à régua.
static func _turned(forward: Vector2, key: String, spread := 0.45) -> Vector2:
	return forward.rotated((DRESSING._roll(key + "|yaw") - 0.5) * 2.0 * spread)


# ---------------------------------------------------------------------------
# 1. Junto das lixeiras e caçambas.

static func _beside_bins(context: Dictionary, batches: Dictionary, site: Dictionary) -> void:
	for source in ["trash_can", "dumpster"]:
		for placement: Transform3D in batches.get(source, []):
			var at := Vector2(placement.origin.x, placement.origin.z)
			var key := "junk|bin|%d|%d" % [roundi(at.x * 10.0), roundi(at.y * 10.0)]
			if DRESSING._roll(key) > float(BIN_CHANCE[zone(context, site, at)]): continue
			var along := Vector2(placement.basis.x.x, placement.basis.x.z).normalized()
			var facing := Vector2(placement.basis.z.x, placement.basis.z.z).normalized()
			var kind := DRESSING._pick([["bag_single", 0.34], ["bag_pile", 0.3], ["cardboard", 0.18], ["bag_torn", 0.18]], DRESSING._roll(key + "k"))
			var reach := (1.25 if source == "dumpster" else 0.5) + float(RADIUS[kind])
			for side: float in ([1.0, -1.0] if DRESSING._roll(key + "s") < 0.5 else [-1.0, 1.0]):
				var point := at + along * side * reach
				if _fits(context, site, point, float(RADIUS[kind])):
					_place(context, batches, site, kind, point, _turned(facing, key))
					break


# ---------------------------------------------------------------------------
# 2. Esquinas: monte de lixo na quina da calçada.

static func _corners(context: Dictionary, batches: Dictionary, site: Dictionary) -> void:
	var geometry = context.geometry
	if geometry == null: return
	for junction in context.junctions:
		var center: Vector2 = junction.position
		if not (context.rect as Rect2).grow(10.0).has_point(center): continue
		var widest := 0.0
		for index in junction.roads: widest = maxf(widest, float(geometry._roads[int(index)].width))
		var reach := widest * 0.5 + DRESSING.SIDEWALK * 0.62
		for quadrant in 4:
			var key := "junk|corner|%d|%d|%d" % [roundi(center.x * 10.0), roundi(center.y * 10.0), quadrant]
			var diagonal := Vector2(1.0 if quadrant & 1 else -1.0, 1.0 if quadrant & 2 else -1.0)
			var point := center + diagonal * reach
			var area := zone(context, site, point)
			if DRESSING._roll(key) > float(CORNER_CHANCE[area]): continue
			var kind := DRESSING._pick([["refuse_heap", 0.45], ["bag_pile", 0.35], ["cardboard", 0.2]], DRESSING._roll(key + "k"))
			# Quina de verdade é a do prédio: puxa um pouco para dentro da calçada até caber.
			for pull: float in [0.0, 0.5, 1.0]:
				var spot := point + diagonal * pull
				if _fits(context, site, spot, float(RADIUS[kind]), 0.2, false) and not _on_crossing(context, spot, float(RADIUS[kind])):
					_place(context, batches, site, kind, spot, _turned(-diagonal, key, 0.6))
					break


## Faixa de pedestre tátil da esquina (a mesma que o CityGroundLitter evita).
static func _on_crossing(context: Dictionary, point: Vector2, radius: float) -> bool:
	var geometry = context.geometry
	if geometry == null or not "_crosswalk_tactile" in geometry: return false
	for index in geometry._crosswalk_tactile.size():
		if not (geometry._crosswalk_tactile_bounds[index] as Rect2).grow(radius + 0.4).has_point(point): continue
		for offset in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
			if Geometry2D.is_point_in_polygon(point + offset, geometry._crosswalk_tactile[index]): return true
	return false


# ---------------------------------------------------------------------------
# 3. Beira do cais: material de pesca no porto, orla na frente sul.

static func _quay_edge(context: Dictionary, batches: Dictionary, site: Dictionary) -> void:
	for segment in site.quay:
		var a: Vector2 = segment.a
		var b: Vector2 = segment.b
		var normal: Vector2 = segment.normal
		var length := a.distance_to(b)
		var along := (b - a) / length
		var slot := 0
		var s := QUAY_SPACING * 0.5
		while s < length:
			var key := "junk|quay|%d|%d" % [int(segment.index), slot]
			slot += 1
			var edge := a + along * (s + (DRESSING._roll(key + "j") - 0.5) * 2.0)
			s += QUAY_SPACING
			if not (context.rect as Rect2).grow(6.0).has_point(edge): continue
			if zone(context, site, edge + normal * 3.0) == "port": _quay_gear(context, batches, site, key, edge, normal, along, 0.45)
			else: _shore_set(context, batches, site, key, edge, normal, along)


static func _quay_gear(context: Dictionary, batches: Dictionary, site: Dictionary, key: String, edge: Vector2, normal: Vector2, along: Vector2, chance: float) -> void:
	if DRESSING._roll(key) > chance: return
	var kind := DRESSING._pick(QUAY_GEAR, DRESSING._roll(key + "k"))
	var radius := float(RADIUS[kind])
	for depth: float in [1.2, 2.2, 3.4]:
		var point := edge + normal * (depth + radius)
		if _fits(context, site, point, radius, 0.4):
			_place(context, batches, site, kind, point, _turned(along if DRESSING._roll(key + "d") < 0.5 else -along, key))
			return


## Um conjunto da orla por vaga: mesa de boteco com guarda-sol, cadeiras de praia viradas
## para o mar com o guarda-sol atrás, pilha de cadeiras de plástico ou material de pesca.
static func _shore_set(context: Dictionary, batches: Dictionary, site: Dictionary, key: String, edge: Vector2, normal: Vector2, along: Vector2) -> void:
	if DRESSING._roll(key) > 0.55: return
	var choice := DRESSING._roll(key + "set")
	var parasol := "beach_parasol" if DRESSING._roll(key + "p") < 0.55 else "beach_parasol_b"
	var table_r := float(RADIUS.bar_table)
	var shade_r := float(RADIUS.beach_parasol)
	var chairs_r := float(RADIUS.beach_chairs)
	var stack_r := float(RADIUS.plastic_chairs)
	if choice < 0.36:
		var table := edge + normal * (2.6 + table_r)
		if _fits(context, site, table, table_r, 0.5) and _place(context, batches, site, "bar_table", table, _turned(-normal, key, 0.3)):
			var shade := table + along * (table_r + 0.5)
			if _fits(context, site, shade, shade_r, 0.5): _place(context, batches, site, parasol, shade, _turned(-normal, key + "s", 3.1))
	elif choice < 0.68:
		var chairs := edge + normal * (1.4 + chairs_r)
		# Frente das cadeiras (+Z) para o mar.
		if _fits(context, site, chairs, chairs_r, 0.5) and _place(context, batches, site, "beach_chairs", chairs, _turned(-normal, key, 0.25)):
			var shade := chairs + normal * 1.5 + along * 0.4
			if _fits(context, site, shade, shade_r, 0.5): _place(context, batches, site, parasol, shade, _turned(-normal, key + "s", 3.1))
	elif choice < 0.8:
		var stack := edge + normal * (4.2 + stack_r)
		if _fits(context, site, stack, stack_r, 0.3): _place(context, batches, site, "plastic_chairs", stack, _turned(along, key))
	else:
		_quay_gear(context, batches, site, key + "g", edge, normal, along, 1.0)


# ---------------------------------------------------------------------------
# 4. Caçamba de entulho no beco (reforma da casa, limpeza do galpão).

static func _alley_skips(context: Dictionary, batches: Dictionary, site: Dictionary) -> void:
	for entry in context.buildings:
		var footprint: Rect2 = entry.rect
		var center := footprint.get_center()
		if not DRESSING._in_chunk(context, center): continue
		var kind := str(entry.data.get("kind", ""))
		var chance := 0.24 if kind in INDUSTRIAL_KINDS else (0.12 if kind in RESIDENTIAL_KINDS else 0.0)
		var key := "junk|skip|%s" % str(entry.data.get("id", center))
		if chance <= 0.0 or DRESSING._roll(key) > chance: continue
		for side: float in ([1.0, -1.0] if DRESSING._roll(key + "s") < 0.5 else [-1.0, 1.0]):
			var z := center.y + (DRESSING._roll(key + "z") - 0.5) * footprint.size.y * 0.4
			var point := Vector2(center.x + side * (footprint.size.x * 0.5 + 1.25), z)
			var ok := true
			# Comprida ao longo do beco (eixo X local = z do mundo): confere as duas pontas e o meio.
			for offset: float in [-1.4, 0.0, 1.4]:
				var probe := point + Vector2(0, offset)
				if not _fits(context, site, probe, 0.95, DRESSING.SIDEWALK + 0.2):
					ok = false
					break
			if not ok or not _place(context, batches, site, "rubble_skip", point, Vector2(-side, 0)): continue
			var pile := point + Vector2(0, 2.6 if DRESSING._roll(key + "r") < 0.5 else -2.6)
			if DRESSING._roll(key + "pile") < 0.6 and _fits(context, site, pile, float(RADIUS.rubble), DRESSING.SIDEWALK + 0.2):
				_place(context, batches, site, "rubble", pile, Vector2(-side, 0))
			break


# ---------------------------------------------------------------------------
# 5. Meio-fio inteiro, com chance e cardápio por bairro.

static func _curb_road(context: Dictionary, batches: Dictionary, site: Dictionary, road: Dictionary) -> void:
	var id := str(road.id)
	for prefix: String in SKIP_ROADS:
		if id.begins_with(prefix): return
	var points: PackedVector2Array = road.points
	var width: float = road.width
	var travelled := 0.0
	var reach := (context.rect as Rect2).grow(width * 0.5 + 8.0)
	for index in points.size() - 1:
		var a := points[index]
		var b := points[index + 1]
		var length := a.distance_to(b)
		if length < 0.01: continue
		# Trecho longe do chunk só soma o comprimento (a fase das vagas segue igual).
		if not Rect2(a, Vector2.ZERO).expand(b).intersects(reach, true):
			travelled += length
			continue
		var tangent := (b - a) / length
		var normal := Vector2(tangent.y, -tangent.x)
		var s := fposmod(-travelled + CURB_SPACING * 0.37, CURB_SPACING)
		while s < length:
			for side: float in [-1.0, 1.0]:
				var key := "junk|curb|%s|%d|%d|%d" % [id, index, int(s * 10.0), int(side)]
				var outward: Vector2 = normal * side
				var along := a + tangent * clampf(s + (DRESSING._roll(key + "j") - 0.5) * 3.0, 0.0, length)
				var probe := along + outward * (width * 0.5 + 1.2)
				if not (context.rect as Rect2).grow(2.0).has_point(probe): continue
				var area := zone(context, site, probe)
				if DRESSING._roll(key) > float(CURB_CHANCE[area]): continue
				var kind := DRESSING._pick(TABLES[area], DRESSING._roll(key + "k"))
				if kind.is_empty(): continue
				var radius := float(RADIUS[kind])
				# Lixo vai para o meio-fio (é onde o caminhão recolhe); caixote e tambor
				# encostam na parede. No porto não há calçada: a peça vai para o pátio.
				var against_wall := DRESSING._roll(key + "w") < (0.7 if kind in ["wood_crates", "rusty_barrels", "fish_crates", "loose_tires", "plastic_chairs"] else 0.25)
				var offsets := [0.5 + radius, DRESSING.SIDEWALK - radius - 0.15] if not against_wall else [DRESSING.SIDEWALK - radius - 0.15, 0.5 + radius]
				if area == "port": offsets = [1.2 + radius, 2.6 + radius, 4.2 + radius]
				for offset: float in offsets:
					var point := along + outward * (width * 0.5 + maxf(offset, radius + 0.2))
					if _fits(context, site, point, radius):
						_place(context, batches, site, kind, point, _turned(-outward, key))
						break
			s += CURB_SPACING
		travelled += length
