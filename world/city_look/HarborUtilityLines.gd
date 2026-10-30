extends RefCounted
## Postes de energia, fiação aérea e transformadores das ruas do Harbor.
##
## Pedido do jogador (29/10): "qualidade dos postes, fiação da luz, placas". Até então a cidade só
## tinha poste de luz: nenhum fio, nenhum poste de concreto/madeira, nenhum transformador.
##
## Monta no passo 2 do CityChunkDressing, logo depois dos postes de luz, uma vez por chunk:
## - a posição de cada poste sai SÓ da geometria global (CityContextIndex, registros da região,
##   placas e adereços autorados), nunca do estado do chunk: o vão que cruza a borda é o mesmo
##   visto dos dois lados, e o vizinho sabe onde o poste está antes de montá-lo. O vão é do
##   chunk do primeiro poste (ordem da rua);
## - por chunk: um MultiMesh por estilo de poste, um de transformador, um de desgaste (atlas do
##   HarborStreetWear), um de fios esticados e um de fios frouxos. Fio sem colisão, sem sombra e
##   com visibility_range. Malhas e materiais compartilhados (material do CityPropKit: nada de
##   shader novo, mesmo leiaute de vértice dos adereços);
## - estações a 36 m (18 m em rua curva) defasadas 9 m dos postes de luz (que ficam a cada 18 m):
##   o poste de energia nunca nasce em cima do de luz. Árvore e mobília evitam o poste (lamps);
## - o poste entra no FragileProps3D como "lamp" (mesmo limiar, tombo na base e recuperação de 45 s)
##   e leva transformador e desgaste como peças extras. `item.wires` liga o poste aos vãos:
##   FragileProps3D._set_transform chama follow() a cada passo do balanço/tombo e o fio acompanha a
##   ponta do poste até o chão; LampRecovery3D.restore devolve o fio ao lugar. Nada de fio solto
##   no ar: a outra ponta continua no isolador do vizinho e a curva nunca passa abaixo do chão.
## GETECO_HARBOR_POLES=0 desliga (A/B no mesmo build).

const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const KIT := preload("res://world/city_look/CityPropKit.gd")
const FILL := preload("res://world/city_look/SidewalkFill.gd")
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const WEAR := preload("res://world/city_look/HarborStreetWear.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const BRIDGE_SURFACE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const AREA := preload("res://world/urban_detail/HarborAreaDressing3D.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const CACHE_META := &"harbor_utility_stations"

static var enabled := OS.get_environment("GETECO_HARBOR_POLES") != "0"

const SPACING := 36.0
const CURVED_SPACING := 18.0
## Postes de luz a cada 18 m de arco (CityChunkDressing.LAMP_SPACING): 9 m de defasagem e
## empurrões de no máximo 6 m deixam o poste de energia a 3+ m de qualquer poste de luz.
const PHASE := 9.0
const NUDGES := [0.0, 3.0, -3.0, 6.0, -6.0]
## Do meio-fio para dentro da calçada (o poste de luz fica a 0,45 m).
const CURB := 0.42
const MAX_SPAN := 46.0
## Orçamento por chunk (64 m): um chunk cheio de ruas tem uns 10 postes e 80 fios.
const MAX_POLES_PER_CHUNK := 28
const MAX_WIRES_PER_CHUNK := 240
## A câmera ortográfica mostra uns 60-80 m em volta do jogador; o lote soma meia diagonal.
const WIRE_RANGE := 85.0
const GROUND_CLEARANCE := 0.06
## Meia espessura do fio em metros (eixo horizontal); o vertical sai da malha × flecha.
const WIRE_HALF := 0.03
## Malha do fio: catenária normalizada (cosh) de 0 a 1 em X, flecha -1 no meio.
const WIRE_SEGMENTS := 16
const CATENARY_C := 2.0
## Meia altura do losango do fio por metro de flecha: o esticado (~0,6-1,2 m de flecha) e o
## frouxo (~1,8-3 m) têm malhas próprias para a espessura vertical não variar 5x.
const TAUT_V := 0.033
const SLACK_V := 0.0105

## Ruas sem poste de energia: avenidas executivas da ilha e do norte (fiação enterrada), ponte e
## rodovia do mapa 2.
const STYLE_BY_DISTRICT := {"downtown": "downtown", "port": "port", "island": "island", "cobra": "cobra", "rural": "rural"}
const STYLES := {
	# Centro e oeste: concreto duplo T, cruzeta de madeira, três fases, duas de baixa e um cabo de telefonia.
	"downtown": {"pole": "concrete", "height": 9.0, "arm": "wood", "phases": 3, "low": 2, "telecom": 1, "tangle": 0, "transformer": 4, "coil": 0.0, "insulator": Color("d4d7d1"), "tone": Color("9d9b92"), "wear": 0.6},
	# Porto: mais alto, cruzeta de concreto, cabos de telefonia sobrando e emaranhados, rolos de reserva.
	"port": {"pole": "concrete", "height": 9.6, "arm": "concrete", "phases": 3, "low": 2, "telecom": 2, "tangle": 3, "transformer": 3, "coil": 0.45, "insulator": Color("c9ccc6"), "tone": Color("938f86"), "wear": 0.9},
	# Ilha (fora das executivas): o mesmo poste, arrumado.
	"island": {"pole": "concrete", "height": 9.0, "arm": "concrete", "phases": 3, "low": 2, "telecom": 1, "tangle": 0, "transformer": 5, "coil": 0.0, "insulator": Color("d8dbd5"), "tone": Color("a6a49b"), "wear": 0.3},
	# Vila Cobra: madeira, mais baixo, isolador de vidro verde, gato de telefonia e rolos.
	"cobra": {"pole": "wood", "height": 7.6, "arm": "wood", "phases": 2, "low": 2, "telecom": 2, "tangle": 2, "transformer": 3, "coil": 0.5, "insulator": Color("4e8a74"), "tone": Color("7d705f"), "wear": 0.95},
	# Acesso rural/oeste: madeira, duas fases, pouca coisa.
	"rural": {"pole": "wood", "height": 7.8, "arm": "wood", "phases": 2, "low": 1, "telecom": 1, "tangle": 0, "transformer": 4, "coil": 0.0, "insulator": Color("5b917b"), "tone": Color("857868"), "wear": 0.35},
}
## Lado da linha por rua quando a regra geral (norte nas leste-oeste) não serve: na Foundry o
## viaduto do trem corre junto da calçada norte (RailwayWorld, z≈20).
const SOUTH_SIDE := ["foundry_avenue"]
## [razão flecha/vão, espessura (× WIRE_HALF), cor sRGB]. Alumínio nu nas fases (CAA cinza), cabo
## multiplexado preto na baixa, telefonia preta mais grossa (feixe).
const WIRE_LOOK := {
	"phase": [0.016, 0.85, Color("a4aaac")],
	"low": [0.024, 1.0, Color("2b2d2f")],
	"telecom": [0.03, 1.25, Color("1d1e20")],
	"tangle": [0.07, 1.35, Color("26282a")],
	"coil": [0.0, 1.1, Color("1d1e20")],
}
const TANGLE_TONES := [Color("1b1c1e"), Color("3a3d40"), Color("5a5d5f"), Color("2a2622")]

static var _meshes := {}
static var _catenary := PackedFloat32Array()
## Registro dos postes montados (chave da estação) e dos vãos presos em cada um. Referências fracas:
## chunk descarregado não fica vivo por causa disto, e entrada morta é ignorada/podada.
static var _poles := {}
static var _spans := {}
static var last_stats := {}


# --- Bairros e estilos -----------------------------------------------------------------------

static func style_for(road_id: String) -> String:
	return STYLE_BY_DISTRICT.get(WEAR.district(road_id), "")


static func slots(style_id: String) -> Array:
	var style: Dictionary = STYLES[style_id]
	var top: float = style.height
	var result: Array = []
	var phase_z: Array = [-.62, .38, 1.22] if int(style.phases) == 3 else [-.68, .68]
	for i in phase_z.size(): result.append({"id": "p%d" % i, "kind": "phase", "at": Vector3(0, top - .13, phase_z[i])})
	for j in int(style.low):
		var y := top - 1.85 - .3 * j
		result.append({"id": "l%d" % j, "kind": "low", "at": Vector3(0, y, face(style_id, y) + .125)})
	for m in int(style.telecom):
		var y := top - 3.4 - .2 * m
		result.append({"id": "t%d" % m, "kind": "telecom", "at": Vector3(0, y, face(style_id, y) + .05)})
	for n in int(style.tangle):
		var y := top - 3.48 - .17 * n
		result.append({"id": "x%d" % n, "kind": "tangle", "at": Vector3(0, y, face(style_id, y) + .06)})
	return result


## Rolo de reserva técnica: dois laços pendurados na braçadeira da telefonia (lado da rua).
static func coil_slots(style_id: String) -> Array:
	var style: Dictionary = STYLES[style_id]
	var y: float = float(style.height) - 3.4 - .5
	var z := face(style_id, y) + .07
	return [[Vector3(-.13, y, z), Vector3(.13, y, z), .5], [Vector3(-.09, y - .05, z + .01), Vector3(.1, y - .05, z + .01), .66]]


## Meia profundidade (Z, para a rua) do fuste na altura y.
static func face(style_id: String, y: float) -> float:
	var style: Dictionary = STYLES[style_id]
	var t := clampf(y / float(style.height), 0.0, 1.0)
	return lerpf(.15, .085, t) if style.pole == "concrete" else lerpf(.15, .11, t)


static func half_width(style_id: String, y: float) -> float:
	var style: Dictionary = STYLES[style_id]
	var t := clampf(y / float(style.height), 0.0, 1.0)
	return lerpf(.11, .065, t) if style.pole == "concrete" else lerpf(.15, .11, t)


# --- Estações (globais, cacheadas na região) -------------------------------------------------

static func _cache(region, geometry) -> Dictionary:
	var revision := int(geometry.get("context_revision"))
	var cache: Dictionary = region.get_meta(CACHE_META, {})
	if cache.get("revision", -2) != revision or cache.get("geometry") != geometry:
		cache = {"revision": revision, "geometry": geometry, "roads": {}}
		region.set_meta(CACHE_META, cache)
	return cache


static func _road_info(cache: Dictionary, road: Dictionary) -> Dictionary:
	var id := str(road.id)
	var roads: Dictionary = cache.roads
	if roads.has(id): return roads[id]
	var points: PackedVector2Array = road.points
	var cumulative := PackedFloat32Array([0.0])
	for i in points.size() - 1: cumulative.append(cumulative[i] + points[i].distance_to(points[i + 1]))
	var spacing := CURVED_SPACING if points.size() > 2 else SPACING
	var total: float = cumulative[cumulative.size() - 1]
	var first := (points[1] - points[0]).normalized() if points.size() > 1 else Vector2.RIGHT
	var normal := Vector2(first.y, -first.x)
	var desired: Vector2
	if absf(first.x) >= absf(first.y): desired = Vector2(0, 1) if id in SOUTH_SIDE else Vector2(0, -1)
	else: desired = Vector2(1, 0) if posmod(id.hash(), 2) == 0 else Vector2(-1, 0)
	var info := {"cumulative": cumulative, "total": total, "spacing": spacing, "side": 1.0 if normal.dot(desired) >= 0.0 else -1.0,
		"count": maxi(0, int(floor((total - PHASE) / spacing)) + 1), "stations": {}, "style": style_for(id)}
	roads[id] = info
	return info


## Ponto na calçada a `arc` metros do começo da rua e direção para fora (lado da linha).
static func _along(road: Dictionary, info: Dictionary, arc: float) -> Array:
	var points: PackedVector2Array = road.points
	var cumulative: PackedFloat32Array = info.cumulative
	arc = clampf(arc, 0.0, float(info.total))
	var segment := 0
	while segment < points.size() - 2 and cumulative[segment + 1] < arc: segment += 1
	var a := points[segment]
	var b := points[segment + 1]
	var length := maxf(a.distance_to(b), .001)
	var tangent := (b - a) / length
	var outward := Vector2(tangent.y, -tangent.x) * float(info.side)
	var point := a + tangent * (arc - cumulative[segment]) + outward * (float(road.width) * .5 + CURB)
	return [point, outward]


static func _station(cache: Dictionary, region, index, geometry, road: Dictionary, info: Dictionary, k: int) -> Variant:
	var stations: Dictionary = info.stations
	if stations.has(k): return stations[k]
	var result: Variant = null
	if k >= 0 and k < int(info.count):
		for nudge in NUDGES:
			var placed := _along(road, info, PHASE + k * float(info.spacing) + float(nudge))
			var point: Vector2 = placed[0]
			if not _valid(region, index, geometry, point): continue
			var outward: Vector2 = placed[1]
			var key := "%s#%d" % [road.id, k]
			var style_id: String = info.style
			var style: Dictionary = STYLES[style_id]
			var roll := DRESSING._roll(key)
			result = {"key": key, "point": point, "yaw": atan2(-outward.x, -outward.y), "style": style_id, "k": k,
				"transformer": posmod(k + str(road.id).hash(), int(style.transformer)) == 0,
				"coil": DRESSING._roll(key + "coil") < float(style.coil),
				"wear": DRESSING._roll(key + "wear") < float(style.wear),
				"tint": 0.9 + roll * 0.14}
			break
	stations[k] = result
	return result


## Só dados globais: o mesmo ponto dá a mesma resposta em qualquer chunk.
static func _valid(region, index, geometry, point: Vector2) -> bool:
	var local: Dictionary = index.query(Rect2(point - Vector2(20, 20), Vector2(40, 40)))
	var context := {"region": region, "roads": local.roads, "junctions": local.junctions, "buildings": local.buildings, "geometry": geometry}
	if DRESSING._near_junction(context, point, 6.0): return false
	if DRESSING._road_clearance(context, point) < 0.25: return false
	if DRESSING._inside_building(context, point, 0.9): return false
	if WORLD_CONNECTION.reserves_approach_for_driving(point) or BRIDGE_SURFACE.owns_surface_point(point): return false
	if DRESSING._workshop_driving(point) or point.distance_to(DRESSING.SEWER_ACCESS) < 2.5: return false
	for rect: Rect2 in index.street_reservations:
		if rect.grow(1.2).has_point(point): return false
	var signs: Variant = geometry.get("_traffic_signs")
	if signs != null:
		for record in signs.records:
			if point.distance_to(record.position) < 1.6: return false
	for clutter in AREA.cobra_street_clutter():
		if point.distance_to(clutter[0]) < float(clutter[1]) + 0.7: return false
	# Árvore, poste e adereço autorados (registros da região), como o SidewalkFill.
	var records: Variant = region.get("records")
	if records is Dictionary and region.has_method("_cell"):
		var first: Vector2i = region._cell(Vector3(point.x - 4.0, 0, point.y - 4.0))
		var last: Vector2i = region._cell(Vector3(point.x + 4.0, 0, point.y + 4.0))
		var obstacles: Array = []
		var rects: Array[Rect2] = []
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				for record in records.get(Vector2i(x, y), []): FILL._record_obstacle(record, obstacles, rects)
		# Raio do SidewalkFill: 3,2 m (árvore, a copa) e 1,4 m (poste/banco autorado).
		for obstacle in obstacles:
			var radius := float(obstacle[1])
			if point.distance_to(obstacle[0]) < (2.4 if radius > 2.0 else radius + 0.6): return false
		for rect in rects:
			if rect.grow(0.6).has_point(point): return false
	return true


## O fio não atravessa prédio nem a passarela (retângulos dos registros de adereço do editor).
static func _chord_clear(region, index, a: Vector2, b: Vector2) -> bool:
	var bounds := Rect2(a, Vector2.ZERO).expand(b).grow(2.0)
	for entry in index.query(bounds).buildings:
		if _segment_hits_rect(a, b, (entry.rect as Rect2).grow(0.3)): return false
	var records: Variant = region.get("records")
	if records is Dictionary and region.has_method("_cell"):
		var first: Vector2i = region._cell(Vector3(bounds.position.x, 0, bounds.position.y))
		var last: Vector2i = region._cell(Vector3(bounds.end.x, 0, bounds.end.y))
		var obstacles: Array = []
		var rects: Array[Rect2] = []
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				for record in records.get(Vector2i(x, y), []): FILL._record_obstacle(record, obstacles, rects)
		for rect in rects:
			if _segment_hits_rect(a, b, rect): return false
	return true


static func _segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b): return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null: return true
	return false


# --- Montagem do chunk -----------------------------------------------------------------------

static func build_chunk(chunk: Node3D, context: Dictionary) -> void:
	last_stats = {}
	if not enabled or context.get("geometry") == null: return
	var region = context.region
	var index = region.get_meta(DRESSING.CONTEXT_META) if region.has_meta(DRESSING.CONTEXT_META) else null
	if index == null: return
	var began_usec := Time.get_ticks_usec()
	var stall := STALL_WORK.begin()
	var geometry = context.geometry
	var cache := _cache(region, geometry)
	var rect: Rect2 = context.rect
	var near := rect.grow(8.0)
	var owned: Array = []
	var spans: Array = []
	for road in context.roads:
		var info := _road_info(cache, road)
		if str(info.style).is_empty(): continue
		for k in int(info.count):
			var nominal: Vector2 = _along(road, info, PHASE + k * float(info.spacing))[0]
			if not near.has_point(nominal): continue
			var station: Variant = _station(cache, region, index, geometry, road, info, k)
			if station == null: continue
			# Árvore e mobília deste chunk evitam o poste (inclusive o do vizinho colado na borda).
			context.lamps.append(station.point)
			if not rect.has_point(station.point) or owned.size() >= MAX_POLES_PER_CHUNK: continue
			owned.append(station)
			var next: Variant = _station(cache, region, index, geometry, road, info, k + 1)
			if next != null and station.point.distance_to(next.point) <= MAX_SPAN and _chord_clear(region, index, station.point, next.point):
				spans.append([station, next])
	if owned.is_empty():
		STALL_WORK.finish_slow("stream.harbor.utility_lines", stall, 2000)
		return
	_build_visuals(chunk, owned, spans)
	last_stats = {"poles": owned.size(), "spans": spans.size(), "usec": Time.get_ticks_usec() - began_usec}
	STALL_WORK.finish_slow("stream.harbor.utility_lines", stall, 2000)


static func pole_transform(station: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(station.yaw)), Vector3(station.point.x, 0.012, station.point.y))


static func _build_visuals(chunk: Node3D, owned: Array, spans: Array) -> void:
	var to_local := chunk.global_transform.affine_inverse()
	var by_style := {}
	for station in owned:
		if not by_style.has(station.style): by_style[station.style] = []
		by_style[station.style].append(station)
	var registered: Array = []
	for style_id in by_style:
		var group: Array = by_style[style_id]
		var poles := MultiMesh.new()
		poles.transform_format = MultiMesh.TRANSFORM_3D
		poles.use_colors = true
		poles.mesh = pole_mesh(style_id)
		poles.instance_count = group.size()
		var transformer_rows: Array = []
		var wear_rows: Array = []
		for i in group.size():
			var local := to_local * pole_transform(group[i])
			poles.set_instance_transform(i, local)
			var tint: float = group[i].tint
			poles.set_instance_color(i, Color(tint, tint * 0.995, tint * 0.985))
			if group[i].transformer: transformer_rows.append([i, local])
			if group[i].wear and WEAR.available(): wear_rows.append([i, local])
		var pole_visual := MultiMeshInstance3D.new()
		pole_visual.name = "HarborUtilityPoles_" + style_id
		pole_visual.multimesh = poles
		pole_visual.material_override = KIT.material()
		chunk.add_child(pole_visual)
		var extras: Array = []
		for i in group.size(): extras.append([])
		if not transformer_rows.is_empty():
			var transformers := _plain_batch("HarborUtilityTransformers_" + style_id, transformer_mesh(style_id), transformer_rows.map(func(row): return row[1]))
			chunk.add_child(transformers)
			for j in transformer_rows.size():
				extras[transformer_rows[j][0]].append({"multimesh": transformers.multimesh, "index": j, "offset": Transform3D.IDENTITY})
		if not wear_rows.is_empty():
			var height: float = STYLES[style_id].height
			var mesh := WEAR.concrete_mesh(height) if STYLES[style_id].pole == "concrete" else WEAR.wood_mesh(height)
			var wear := WEAR.batch("HarborUtilityWear_" + style_id, mesh, wear_rows.map(func(row): return row[1]))
			chunk.add_child(wear)
			for j in wear_rows.size():
				extras[wear_rows[j][0]].append({"multimesh": wear.multimesh, "index": j, "offset": Transform3D.IDENTITY})
		for i in group.size():
			var station: Dictionary = group[i]
			var item := {"kind": "lamp", "multimesh": poles, "index": i, "visual": weakref(pole_visual), "extra": extras[i],
				"chunk": weakref(chunk), "base": poles.get_instance_transform(i), "point": pole_transform(station).origin,
				"state": "standing", "radius": 0.24 if STYLES[style_id].pole == "concrete" else 0.2, "wires": station.key}
			FRAGILE._register(item)
			registered.append([station, item])
	_build_wires(chunk, owned, spans, registered)


static func _plain_batch(name: String, mesh: Mesh, transforms: Array) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size(): multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = name
	instance.multimesh = multimesh
	instance.material_override = KIT.material()
	# Peça a 6-8 m de altura: a sombra cai longe do poste e só dobra o passe de sombra.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


# --- Fios ------------------------------------------------------------------------------------

static func _build_wires(chunk: Node3D, owned: Array, spans: Array, registered: Array) -> void:
	# Cada poste montado entra no registro com a transformação atual (em pé) antes dos vãos.
	for pair in registered:
		var station: Dictionary = pair[0]
		var item: Dictionary = pair[1]
		_poles[station.key] = {"chunk": weakref(chunk), "multimesh": weakref(item.multimesh), "index": item.index, "style": station.style, "current": item.base}
	var taut: Array = []
	var slack: Array = []
	for pair in spans:
		var a: Dictionary = pair[0]
		var b: Dictionary = pair[1]
		var slots_a := slots(a.style)
		var slots_b := {}
		for slot in slots(b.style): slots_b[slot.id] = slot
		for slot in slots_a:
			if not slots_b.has(slot.id): continue
			var look: Array = WIRE_LOOK[slot.kind]
			var key := "%s>%s" % [a.key, slot.id]
			var ratio: float = look[0] * (0.85 + DRESSING._roll(key) * 0.35)
			var spec := {"a": [a.key, slot.at], "b": [b.key, slots_b[slot.id].at],
				"a_world": pole_transform(a) * slot.at, "b_world": pole_transform(b) * slots_b[slot.id].at,
				"ratio": ratio, "thick": WIRE_HALF * float(look[1]), "lean": 0.0, "fixed": 0.0, "color": look[2], "slack": slot.kind == "tangle"}
			if slot.kind == "tangle":
				# Emaranhado do porto: flechas e inclinações diferentes, os feixes se cruzam.
				spec.lean = (DRESSING._roll(key + "lean") - 0.5) * 0.6
				spec.color = TANGLE_TONES[int(DRESSING._roll(key + "tone") * TANGLE_TONES.size()) % TANGLE_TONES.size()]
			(slack if spec.slack else taut).append(spec)
	for station in owned:
		if not station.coil: continue
		for loop in coil_slots(station.style):
			var look: Array = WIRE_LOOK.coil
			taut.append({"a": [station.key, loop[0]], "b": [station.key, loop[1]], "a_world": pole_transform(station) * loop[0],
				"b_world": pole_transform(station) * loop[1], "ratio": 0.0, "thick": WIRE_HALF * float(look[1]), "lean": 0.0,
				"fixed": loop[2], "color": look[2], "slack": false})
	var budget := MAX_WIRES_PER_CHUNK
	for group in [[taut, "HarborUtilityWires", false], [slack, "HarborUtilityWiresSlack", true]]:
		var specs: Array = group[0]
		if specs.size() > budget: specs = specs.slice(0, budget)
		budget -= specs.size()
		if specs.is_empty(): continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = wire_mesh(group[2])
		multimesh.instance_count = specs.size()
		for i in specs.size():
			var spec: Dictionary = specs[i]
			spec.multimesh = weakref(multimesh)
			spec.index = i
			spec.chunk = weakref(chunk)
			multimesh.set_instance_color(i, spec.color)
			_place(spec)
			# Laço do rolo tem as duas pontas no mesmo poste: entra uma vez só.
			for end in ([spec.a[0]] if spec.a[0] == spec.b[0] else [spec.a[0], spec.b[0]]):
				if not _spans.has(end): _spans[end] = []
				(_spans[end] as Array).append(spec)
		var visual := MultiMeshInstance3D.new()
		visual.name = group[1]
		visual.multimesh = multimesh
		visual.material_override = KIT.material()
		# Fio fino na sombra pisca (serrilhado no shadow map) e dobra o custo: sem sombra.
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = WIRE_RANGE + multimesh.get_aabb().size.length() * .5
		visual.visibility_range_end_margin = 6.0
		preload("res://runtime/GraphicsOptions.gd").tag_detail(visual)
		chunk.add_child(visual)
	# Vãos de vizinhos presos nos postes deste chunk voltam a apontar para o poste em pé
	# (o chunk recarregado remontou o poste que estava caído).
	for pair in registered:
		_prune(pair[0].key)
		for spec in _spans.get(pair[0].key, []): _place(spec)


static func _prune(key: String) -> void:
	if not _spans.has(key): return
	var alive: Array = []
	for spec in _spans[key]:
		var chunk: Variant = spec.chunk.get_ref()
		if spec.multimesh.get_ref() != null and is_instance_valid(chunk) and not chunk.is_queued_for_deletion(): alive.append(spec)
	if alive.is_empty(): _spans.erase(key)
	else: _spans[key] = alive


## FragileProps3D._set_transform (balanço e tombo) e LampRecovery3D.restore: `xform` é a
## transformação atual do poste no espaço do chunk dele.
static func follow(item: Dictionary, xform: Transform3D) -> void:
	var key := str(item.get("wires", ""))
	var entry: Variant = _poles.get(key)
	if entry == null or entry.multimesh.get_ref() != item.get("multimesh") or int(entry.index) != int(item.get("index", -1)): return
	entry.current = xform
	for spec in _spans.get(key, []): _place(spec)


static func _endpoint(reference: Array, fallback: Vector3) -> Vector3:
	var entry: Variant = _poles.get(reference[0])
	if entry == null: return fallback
	var chunk: Variant = entry.chunk.get_ref()
	if not is_instance_valid(chunk) or not chunk.is_inside_tree() or entry.multimesh.get_ref() == null: return fallback
	return (chunk as Node3D).global_transform * (entry.current as Transform3D) * (reference[1] as Vector3)


## Onde as duas pontas do vão estão agora (para teste e para o tombo).
static func endpoints(spec: Dictionary) -> Array:
	return [_endpoint(spec.a, spec.a_world), _endpoint(spec.b, spec.b_world)]


static func _place(spec: Dictionary) -> bool:
	var multimesh: MultiMesh = spec.multimesh.get_ref()
	var chunk: Variant = spec.chunk.get_ref()
	if multimesh == null or not is_instance_valid(chunk) or not chunk.is_inside_tree() or int(spec.index) >= multimesh.instance_count: return false
	var ends := endpoints(spec)
	multimesh.set_instance_transform(int(spec.index), (chunk as Node3D).global_transform.affine_inverse() * wire_transform(ends[0], ends[1], spec))
	return true


## Transformação afim da malha unitária: X = corda (pontas exatas nos isoladores), Y = flecha para
## cima (a malha desce), Z = horizontal perpendicular × espessura.
static func wire_transform(a: Vector3, b: Vector3, spec: Dictionary) -> Transform3D:
	var chord := b - a
	var side := Vector3(-chord.z, 0, chord.x)
	side = side.normalized() if side.length_squared() > 0.0004 else Vector3.RIGHT
	var sag := float(spec.fixed) if float(spec.fixed) > 0.0 else float(spec.ratio) * maxf(chord.length(), 0.3)
	sag = clampf(minf(sag, max_sag(a.y, b.y)), 0.02, 6.0)
	var up := (Vector3.UP + side * float(spec.lean)).normalized()
	return Transform3D(Basis(chord, up * sag, side * float(spec.thick)), a)


## Maior flecha que mantém a curva acima do chão entre pontas de alturas ya e yb.
static func max_sag(ya: float, yb: float) -> float:
	var table := catenary()
	var best := INF
	for i in table.size():
		var f: float = table[i]
		if f > -0.02: continue
		var t := float(i) / (table.size() - 1)
		best = minf(best, (lerpf(ya, yb, t) - GROUND_CLEARANCE) / -f)
	return best


## f(t) da catenária normalizada: 0 nas pontas, -1 no meio (cosh, não parábola).
static func catenary() -> PackedFloat32Array:
	if _catenary.is_empty():
		var top := cosh(CATENARY_C * .5)
		for i in WIRE_SEGMENTS + 1:
			var t := float(i) / WIRE_SEGMENTS
			_catenary.append((cosh(CATENARY_C * (t - .5)) - top) / (top - 1.0))
	return _catenary


## Fio unitário: losango de 4 lados ao longo da catenária, cor de vértice branca (a cor vem da
## cópia). Formato posição/normal/cor, o mesmo dos adereços do CityPropKit.
static func wire_mesh(slack: bool) -> ArrayMesh:
	var key := "wire_slack" if slack else "wire_taut"
	if _meshes.has(key): return _meshes[key]
	var vertical := SLACK_V if slack else TAUT_V
	var table := catenary()
	var ring := [Vector3(0, vertical, 0), Vector3(0, 0, 1), Vector3(0, -vertical, 0), Vector3(0, 0, -1)]
	var normals := [Vector3.UP, Vector3.BACK, Vector3.DOWN, Vector3.FORWARD]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(KIT.material())
	tool.set_color(Color.WHITE)
	for i in WIRE_SEGMENTS:
		var t0 := float(i) / WIRE_SEGMENTS
		var t1 := float(i + 1) / WIRE_SEGMENTS
		var c0 := Vector3(t0, table[i], 0)
		var c1 := Vector3(t1, table[i + 1], 0)
		for side in 4:
			var next := (side + 1) % 4
			var quad := [[c0 + ring[side], normals[side]], [c1 + ring[side], normals[side]], [c1 + ring[next], normals[next]], [c0 + ring[next], normals[next]]]
			# Horário visto de fora (frente no Godot), como o CityPropKit.box: normal para fora.
			for k in [0, 1, 2, 0, 2, 3]:
				tool.set_normal(quad[k][1])
				tool.add_vertex(quad[k][0])
	_meshes[key] = tool.commit()
	return _meshes[key]


# --- Malhas do poste e do transformador -----------------------------------------------------

static func pole_mesh(style_id: String) -> ArrayMesh:
	var key := "pole_" + style_id
	if _meshes.has(key): return _meshes[key]
	var style: Dictionary = STYLES[style_id]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(KIT.material())
	tool.set_smooth_group(-1)
	var top: float = style.height
	if style.pole == "concrete": _concrete_shaft(tool, style_id)
	else: _wood_shaft(tool, style_id)
	var arm_top := top - .3
	var phase_z: Array = [-.62, .38, 1.22] if int(style.phases) == 3 else [-.68, .68]
	var arm_from: float = -.78 if phase_z.size() == 3 else -.85
	var arm_to: float = 1.38 if phase_z.size() == 3 else .85
	var arm_color := Color("a3a199") if style.arm == "concrete" else Color("6c5944")
	KIT.box(tool, Vector3(0, arm_top - .055, (arm_from + arm_to) * .5), Vector3(.1 if style.arm == "concrete" else .09, .11, arm_to - arm_from), arm_color)
	# Mão-francesa: duas tiras de aço do fuste até a cruzeta.
	var steel := Color("7e8588")
	var brace_y := arm_top - .95
	_beam(tool, Vector3(0, brace_y, -face(style_id, brace_y)), Vector3(0, arm_top - .11, arm_from + .3), Vector2(.05, .012), steel)
	_beam(tool, Vector3(0, brace_y, face(style_id, brace_y)), Vector3(0, arm_top - .11, arm_to - .4), Vector2(.05, .012), steel)
	KIT.box(tool, Vector3(0, arm_top - .055, 0), Vector3(half_width(style_id, arm_top) * 2.0 + .04, .16, face(style_id, arm_top) * 2.0 + .03), steel)
	# Isoladores de pino: saia larga embaixo, topo com a canaleta onde o fio apoia (H - 0,13 m).
	var insulator: Color = style.insulator
	for z in phase_z:
		KIT.cylinder(tool, Vector3(0, arm_top, z), .012, .04, steel, 6)
		KIT.cylinder(tool, Vector3(0, arm_top + .03, z), .06, .045, insulator, 10)
		KIT.cylinder(tool, Vector3(0, arm_top + .075, z), .047, .05, insulator.darkened(.05), 10)
		KIT.cylinder(tool, Vector3(0, arm_top + .125, z), .034, .04, insulator.lightened(.04), 10)
		KIT.cylinder(tool, Vector3(0, arm_top + .165, z), .02, .012, insulator.darkened(.1), 8)
	# Armação secundária (baixa tensão) no lado da rua: tira vertical, braços e roldanas.
	var lows: Array = slots(style_id).filter(func(slot): return slot.kind == "low")
	if not lows.is_empty():
		var high: float = lows[0].at.y + .2
		var low: float = lows[lows.size() - 1].at.y - .25
		var mid := (high + low) * .5
		KIT.box(tool, Vector3(0, mid, face(style_id, mid) + .012), Vector3(.05, high - low, .02), steel)
		for slot in lows:
			var y: float = slot.at.y
			var z: float = face(style_id, y)
			for dy in [-.048, .048]: KIT.box(tool, Vector3(0, y + dy, z + .06), Vector3(.035, .012, .1), steel)
			KIT.cylinder(tool, Vector3(0, y - .036, z + .09), .035, .072, Color("e2e3dd"), 10)
	# Braçadeiras da telefonia: o cabo entra nelas (sem fio solto na frente do poste).
	for slot in slots(style_id):
		if slot.kind != "telecom" and slot.kind != "tangle": continue
		var y: float = slot.at.y
		KIT.box(tool, Vector3(0, y, face(style_id, y) + .03), Vector3(.09, .07, .07), Color("1e2022"))
	# Suporte da reserva técnica (rolo de cabo): os laços de coil_slots() penduram nesta barra.
	if float(style.coil) > 0.0:
		var coil_y: float = coil_slots(style_id)[0][0].y
		KIT.box(tool, Vector3(0, coil_y - .025, face(style_id, coil_y) + .065), Vector3(.32, .08, .03), steel)
	if style.pole == "concrete":
		# Cordoalha de aterramento no canal do duplo T e calçada de concreto em volta do pé.
		KIT.box(tool, Vector3(.034, top * .5, 0), Vector3(.012, top - .7, .012), Color("6a6152"))
		KIT.box(tool, Vector3(0, .016, 0), Vector3(.62, .03, .62), Color("8d8a82"))
	else:
		KIT.box(tool, Vector3(0, top * .5 - .1, -face(style_id, top * .5) - .006), Vector3(.03, top - .8, .02), Color("3b3d3e"))
	tool.generate_normals()
	_meshes[key] = tool.commit()
	return _meshes[key]


## Duplo T de concreto: duas abas (±Z) e alma, afinando até o topo; sujeira subindo do chão.
static func _concrete_shaft(tool: SurfaceTool, style_id: String) -> void:
	var style: Dictionary = STYLES[style_id]
	var top: float = style.height
	var tone: Color = style.tone
	var heights := [0.0, .28, .9, 2.0, top * .55, top]
	var colors := [tone.darkened(.42), tone.darkened(.24), tone.darkened(.06), tone, tone.lightened(.03), tone.darkened(.05)]
	var flange := .045
	for side in [-1.0, 1.0]:
		var rings: Array = []
		for i in heights.size():
			var y: float = heights[i]
			var hz := face(style_id, y)
			var z0: float = side * (hz - flange)
			var z1: float = side * hz
			rings.append([y, -half_width(style_id, y), half_width(style_id, y), minf(z0, z1), maxf(z0, z1), colors[i]])
		_prism(tool, rings)
	var web: Array = []
	for i in heights.size():
		var y: float = heights[i]
		var hz := face(style_id, y) - flange
		web.append([y, -.028, .028, -hz, hz, colors[i].darkened(.08)])
	_prism(tool, web)


## Madeira roliça: 10 faces, creosoto escuro no pé, cinza-marrom envelhecido, topo chanfrado.
static func _wood_shaft(tool: SurfaceTool, style_id: String) -> void:
	var style: Dictionary = STYLES[style_id]
	var top: float = style.height
	var tone: Color = style.tone
	var heights := [0.0, .42, .5, 2.4, top * .6, top - .05]
	var colors := [Color("2f2822"), Color("3a3028"), tone.darkened(.1), tone, tone.lightened(.06), tone.lightened(.1)]
	var sides := 10
	for i in heights.size() - 1:
		var y0: float = heights[i]
		var y1: float = heights[i + 1]
		var r0 := face(style_id, y0)
		var r1 := face(style_id, y1)
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			# Veio: cada face com um tom levemente diferente (madeira tratada ao tempo).
			tool.set_color(KIT._mottle(colors[i], 0.0, s + i * 7, 3))
			var b0 := d0 * r0 + Vector3.UP * y0
			var b1 := d1 * r0 + Vector3.UP * y0
			var t0 := d0 * r1 + Vector3.UP * y1
			var t1 := d1 * r1 + Vector3.UP * y1
			tool.add_vertex(b0); tool.add_vertex(b1); tool.add_vertex(t0)
			tool.add_vertex(b1); tool.add_vertex(t1); tool.add_vertex(t0)
	KIT.cylinder(tool, Vector3(0, top - .05, 0), face(style_id, top - .05), .05, tone.darkened(.2), 10, .04)


## Prisma retangular por anéis [y, x0, x1, z0, z1, cor]: quatro lados e tampa no último anel.
static func _prism(tool: SurfaceTool, rings: Array) -> void:
	for i in rings.size() - 1:
		var lo: Array = rings[i]
		var hi: Array = rings[i + 1]
		var corner := func(ring: Array, x: int, z: int) -> Vector3:
			return Vector3(ring[1] if x == 0 else ring[2], ring[0], ring[3] if z == 0 else ring[4])
		# [BL, TL, TR, BR] vistos de fora (horário = frente no Godot), como o CityPropKit.box.
		var faces := [
			[corner.call(lo, 0, 1), corner.call(hi, 0, 1), corner.call(hi, 1, 1), corner.call(lo, 1, 1)],
			[corner.call(lo, 1, 0), corner.call(hi, 1, 0), corner.call(hi, 0, 0), corner.call(lo, 0, 0)],
			[corner.call(lo, 1, 1), corner.call(hi, 1, 1), corner.call(hi, 1, 0), corner.call(lo, 1, 0)],
			[corner.call(lo, 0, 0), corner.call(hi, 0, 0), corner.call(hi, 0, 1), corner.call(lo, 0, 1)],
		]
		for quad in faces:
			for k in [0, 1, 2, 0, 2, 3]:
				tool.set_color(lo[5] if k == 0 or k == 3 else hi[5])
				tool.add_vertex(quad[k])
	var last: Array = rings[rings.size() - 1]
	var cap := [Vector3(last[1], last[0], last[4]), Vector3(last[1], last[0], last[3]), Vector3(last[2], last[0], last[3]), Vector3(last[2], last[0], last[4])]
	tool.set_color(last[5])
	for k in [0, 1, 2, 0, 2, 3]: tool.add_vertex(cap[k])


## Barra retangular de a até b (seção size.x × size.y).
static func _beam(tool: SurfaceTool, a: Vector3, b: Vector3, size: Vector2, color: Color) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.001: return
	var y_axis := along / length
	var x_axis := Vector3.RIGHT if absf(y_axis.dot(Vector3.RIGHT)) < 0.95 else Vector3.BACK
	x_axis = (x_axis - y_axis * x_axis.dot(y_axis)).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	KIT._rotated_box(tool, (a + b) * .5, Vector3(size.x, length, size.y), color, Basis(x_axis, y_axis, z_axis))


## Transformador de poste (lado da calçada, -Z): tanque com aletas, tampa, buchas, cintas, chaves
## fusíveis na cruzeta e jumpers até os isoladores das fases, cabo de baixa até a armação.
static func transformer_mesh(style_id: String) -> ArrayMesh:
	var key := "transformer_" + style_id
	if _meshes.has(key): return _meshes[key]
	var style: Dictionary = STYLES[style_id]
	var top: float = style.height
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(KIT.material())
	tool.set_smooth_group(-1)
	var small: bool = style.pole == "wood"
	var radius := .25 if small else .29
	var y := top - 1.75
	var z := -(face(style_id, y) + radius + .06)
	var tank := Color("848f89") if not small else Color("8b908c")
	KIT.cylinder(tool, Vector3(0, y - .42, z), radius, .82, tank, 12)
	KIT.cylinder(tool, Vector3(0, y + .4, z), radius + .025, .05, tank.darkened(.12), 12)
	KIT.cylinder(tool, Vector3(0, y - .46, z), radius * .8, .04, tank.darkened(.25), 12)
	for angle in [PI * .25, PI * .75, PI * 1.25, PI * 1.75, PI]:
		var direction := Vector3(sin(angle), 0, cos(angle))
		KIT.box(tool, Vector3(0, y - .05, z) + direction * (radius + .03), Vector3(.03, .6, .08), tank.darkened(.08), angle)
	# Ferrugem e escorrido do tanque: faixa mais escura logo abaixo da tampa.
	KIT.cylinder(tool, Vector3(0, y + .3, z), radius + .004, .06, Color("6d5a48"), 12)
	var steel := Color("7b8285")
	for band in [y + .22, y - .25]:
		KIT.box(tool, Vector3(0, band, 0), Vector3(half_width(style_id, band) * 2.0 + .05, .05, face(style_id, band) * 2.0 + .05), steel)
		KIT.box(tool, Vector3(0, band, (z - face(style_id, band)) * .5), Vector3(.07, .07, absf(z) - radius * .6), steel)
	var phase_z: Array = [-.62, .38, 1.22] if int(style.phases) == 3 else [-.68, .68]
	var bushing_x: Array = [-.11, 0.0, .11] if phase_z.size() == 3 else [-.08, .08]
	var arm_top := top - .3
	for i in phase_z.size():
		var bushing := Vector3(bushing_x[i], y + .45, z)
		KIT.cylinder(tool, bushing, .028, .12, Color("e1e2dc"), 8)
		# Chave fusível pendurada na cruzeta, e o jumper do isolador até a bucha passando por ela.
		var fuse := Vector3(0, arm_top - .34, float(phase_z[i]) - .16)
		KIT._rotated_box(tool, fuse, Vector3(.05, .26, .05), Color("8c8f8a"), Basis(Vector3.RIGHT, .35))
		_beam(tool, Vector3(0, top - .13, phase_z[i]), fuse + Vector3(0, .12, .04), Vector2(.018, .018), Color("9da3a5"))
		_beam(tool, fuse - Vector3(0, .12, -.04), bushing + Vector3(0, .12, 0), Vector2(.018, .018), Color("9da3a5"))
	# Baixa tensão: duas buchas pretas na lateral e o cabo grosso até a armação secundária.
	var lows: Array = slots(style_id).filter(func(slot): return slot.kind == "low")
	for dx in [-.08, .08]: KIT.box(tool, Vector3(dx, y + .12, z + radius + .02), Vector3(.05, .07, .05), Color("202224"))
	if not lows.is_empty():
		var rack: Vector3 = lows[0].at
		var start := Vector3(.08, y + .12, z + radius + .05)
		var side := Vector3(half_width(style_id, rack.y) + .05, rack.y + .12, 0)
		_beam(tool, start, side, Vector2(.035, .035), Color("1f2123"))
		_beam(tool, side, rack + Vector3(.02, .05, -.03), Vector2(.035, .035), Color("1f2123"))
	tool.generate_normals()
	_meshes[key] = tool.commit()
	return _meshes[key]


# --- Postes de luz (CityChunkDressing) -------------------------------------------------------

## Pintura do poste de luz por bairro. Antes era MATERIALS.flat(cinza, 0,6), que com metallic 0
## caía no relevo de reboco ("plaster") e rugosidade 1: lia como poste de massa. Aqui é tinta
## sobre aço: relevo "metal", um pouco de metalicidade e brilho. Mesmas opções do flat()
## (albedo/normal/rugosidade triplanar): o shader é o mesmo, só muda o valor.
static var _lamp_materials := {}
const LAMP_PAINT := {"downtown": Color("4a5054"), "port": Color("3e4a43"), "island": Color("2e3337"), "executive": Color("2b2f33"), "cobra": Color("5a636b"), "rural": Color("575c5d")}

static func lamp_material(district: String) -> StandardMaterial3D:
	var color: Color = LAMP_PAINT.get(district, LAMP_PAINT.downtown)
	var key := color.to_html(false)
	if _lamp_materials.has(key): return _lamp_materials[key]
	var material := StandardMaterial3D.new()
	material.metallic = .45
	preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(material, "metal", 1.6, .55)
	material.albedo_color = Color(minf(color.r * material.albedo_color.r, 1.0), minf(color.g * material.albedo_color.g, 1.0), minf(color.b * material.albedo_color.b, 1.0))
	material.roughness = .78
	_lamp_materials[key] = material
	return material
