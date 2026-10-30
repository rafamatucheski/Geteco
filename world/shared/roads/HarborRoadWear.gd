extends RefCounted
## Desgaste das ruas do Harbor: buracos rasos, remendos, rachaduras e selante, tampa de bueiro,
## boca de lobo, chapa de vala, óleo, ferrugem, poça em depressão, sujeira no meio-fio, óleo no
## meio da faixa e tinta gasta (playtest 29/10: "as ruas são muito limpas para uma cidade portuária").
##
## Tudo visual, sem colisão: o carro não sente o buraco (raso, no máximo um palmo de asfalto
## esfarelado), então não vale pagar física nem mudar a direção.
##
## Desempenho (o Harbor já passa de 1.000 draw calls):
## - um MeshInstance3D por trecho com DUAS superfícies (fosco e molhado) e um atlas BC7 só
##   (assets/materials/harbor_road_wear, gerado offline por tools/build_road_wear_atlas.py): o
##   desgaste inteiro de um trecho custa 2 draw calls, contra 5 MultiMesh do desgaste antigo
##   (óleo, remendo, rachadura, bueiro e grelha);
## - os dois materiais têm exatamente os recursos do decalque de chão do CityLook
##   (CityLookMaterials.ground_decal: alfa, sem escrita de profundidade, só textura de albedo) e
##   a malha tem o formato de vértice do QuadMesh que aqueles decalques usam: o par shader x formato
##   já é compilado sob a cortina, nada compila no jogo (o teste confere o formato);
## - montado no passo de acabamento do trecho (CityChunkDressing, passo 11), em fatias de ~2 ms;
##   nada roda por quadro, só a troca de dois parâmetros quando a chuva muda.
##
## Determinístico: cada amostra (a cada 3 m de rua) sorteia com a semente do id da rua, do trecho e
## da distância; o decalque pertence ao trecho onde está o centro. Recarregar dá o mesmo chão.
## Densidade: maior no cais e na zona industrial, menor nas ruas residenciais (`grit`).
##
## Ordem de desenho: render_priority -3 (fosco) e -2 (molhado), abaixo dos decalques de chão
## existentes (-1: sombra de contato, sujeira da calçada, sangue), que ficam sempre por cima.
## GETECO_HARBOR_ROAD_WEAR=0 volta ao chão anterior (A/B no mesmo export).

const ATLAS := preload("res://assets/materials/harbor_road_wear/road_wear_atlas.png")
const BRIDGE_SURFACE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const PORT_LAYOUT := preload("res://world/regions/OriginalSouthPortLayout.gd")
## O túnel pré-carrega HarborRoadGeometry3D, que pré-carrega este script: carga tardia evita o ciclo.
static var _canal_tunnel: GDScript
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

static var _enabled := OS.get_environment("GETECO_HARBOR_ROAD_WEAR") != "0"

## Disposição do atlas em pixels (espelha tools/build_road_wear_atlas.py).
const ATLAS_SIZE := 1024.0
const STRIP := 32.0
const CELLS := {
	"pothole": Rect2(0, 0, 256, 256), "pothole_water": Rect2(256, 0, 256, 256),
	"ravel": Rect2(512, 0, 256, 256), "patch": Rect2(768, 0, 256, 256),
	"alligator": Rect2(0, 256, 256, 256), "crack": Rect2(256, 256, 256, 256),
	"manhole": Rect2(512, 256, 256, 256), "plate": Rect2(768, 256, 256, 128), "grate": Rect2(768, 384, 256, 128),
	"oil": Rect2(0, 512, 256, 256), "oil_drips": Rect2(256, 512, 256, 256),
	"rust": Rect2(512, 512, 256, 256), "puddle": Rect2(768, 512, 256, 256),
	# Faixas de 1024x32 (v = 0 encosta no meio-fio nas de sujeira); 1 px de folga contra a vizinha.
	"curb_grime": Rect2(0, 768 + 1, 1024, 30), "curb_sand": Rect2(0, 800 + 1, 1024, 30),
	"lane_oil": Rect2(0, 832 + 1, 1024, 30), "crack_line": Rect2(0, 864 + 1, 1024, 30),
	"tire_grime": Rect2(0, 896 + 1, 1024, 30), "paint_chips": Rect2(0, 928 + 1, 1024, 30),
	"trench": Rect2(0, 960 + 1, 1024, 30), "sealant": Rect2(0, 992 + 1, 1024, 30),
}
## Poça e água parada vão na superfície molhada (brilho do céu quando chove, mancha úmida no seco).
const WET_KINDS := ["puddle"]

## Planos: o mesmo dos decalques do CityLook (DECAL_Y) e, para tinta gasta e borracha sobre a
## pintura, acima das faixas (0,038-0,040).
const Y := 0.034
const Y_PAINT := 0.043
const STEP := 3.0
## Orçamento por trecho de 64 m. Medido em 29/10 no porto (o mais denso): ver teste.
const MAX_DECALS := 520
const SLICE_USEC := 2000
const SEWER_ACCESS := Vector2(1182.0, 2114.0) / 16.0
const SEWER_CLEARANCE := 1.8

## Camadas de desenho dentro do lote (ordem dos índices).
enum {BASE, CRACKS, STAINS, HOLES, FIXTURES, TOP}
const LAYERS := 6

## Contadores para teste e captura (não usados no jogo).
static var stats := {"chunks": 0, "decals": 0, "max_chunk_decals": 0, "dropped": 0, "max_slice_usec": 0, "max_chunk_usec": 0, "total_usec": 0}
static var _materials: Array[StandardMaterial3D] = []
static var _wetness := -1.0
static var _rng := RandomNumberGenerator.new()


static func enabled() -> bool:
	return _enabled


## Quanto da macrovariação do asfalto (coastal_wet_asphalt.gdshader) entra: 0 = asfalto anterior.
static func asphalt_amount() -> float:
	return 1.0 if _enabled else 0.0


# ---------------------------------------------------------------------------
# Materiais: dois, compartilhados por todos os trechos.

static func materials() -> Array[StandardMaterial3D]:
	if not _materials.is_empty(): return _materials
	for wet in [false, true]:
		var material := StandardMaterial3D.new()
		# Mesmos recursos de CityLookMaterials.ground_decal: o shader gerado é o mesmo.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.albedo_texture = ATLAS
		material.roughness = 0.95
		material.render_priority = -2 if wet else -3
		material.resource_name = "HarborRoadWear" + ("Wet" if wet else "")
		_materials.append(material)
	_apply_wetness(maxf(_wetness, 0.0))
	return _materials


## Primeiro uso dos dois materiais com o renderizador de verdade: ~14 ms (compilar o shader do
## decalque e preparar o pipeline no primeiro surface_set_material), medido com janela em 30/10. Caía
## na fatia do primeiro trecho montado (teste com janela: 14,6–15,4 ms; headless não mostra, por isso
## a medida de 2,6 ms antes enganava). Feito aqui, na preparação da região (HarborRoadGeometry3D.
## configure, sob a cortina); a malha de uma face por material fica retida para não liberar nada.
static var _warm: ArrayMesh

static func prewarm() -> void:
	if not enabled() or _warm != null: return
	var span := STALL_WORK.begin()
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	_warm = ArrayMesh.new()
	for material in materials():
		# Mesmas listas do lote (vértice, normal, tangente, UV, índice): mesmo formato, mesmo pipeline.
		_warm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, quad.get_mesh_arrays())
		_warm.surface_set_material(_warm.get_surface_count() - 1, material)
	STALL_WORK.finish("region.prepare.road_wear_prewarm", span, {})


## Chamado por HarborRoadGeometry3D.set_weather_wetness (só quando a umidade muda).
static func set_wetness(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if absf(value - _wetness) < 0.002: return
	_wetness = value
	if not _materials.is_empty(): _apply_wetness(value)


static func _apply_wetness(value: float) -> void:
	# O asfalto do shader escurece ~0,5x (linear) molhado; os decalques acompanham para o remendo
	# não ficar mais claro que a rua na chuva. Fosco ganha um pouco de brilho de película.
	var matte := _materials[0]
	var dark := 1.0 - value * 0.3
	matte.albedo_color = Color(dark, dark, dark, 1.0)
	matte.roughness = lerpf(0.95, 0.6, value)
	matte.metallic_specular = lerpf(0.35, 0.5, value)
	# Poça: no seco só a marca úmida (alfa menor, fosca); na chuva, água lisa que reflete o céu.
	var wet := _materials[1]
	var water := 1.0 - value * 0.2
	wet.albedo_color = Color(water, water, water, lerpf(0.55, 1.0, value))
	wet.roughness = lerpf(0.55, 0.06, value)
	wet.metallic_specular = lerpf(0.5, 0.7, value)


# ---------------------------------------------------------------------------
# Densidade

## 0..1: quão gasto/sujo é o chão neste ponto. Base do trecho pelos prédios em volta (galpão sobe,
## residência desce) e faixa industrial do cais pela mesma regra de CoastalProtection._style
## (sul de z 156 e o corredor 195 < x < 275).
static func grit(point: Vector2, chunk_base: float, road_id: String) -> float:
	var g := chunk_base
	g = maxf(g, smoothstep(140.0, 172.0, point.y))
	var band := maxf(195.0 - point.x, point.x - 275.0)
	if point.y > -40.0: g = maxf(g, 0.8 * (1.0 - smoothstep(0.0, 20.0, band)))
	for hint in ["port", "dock", "quay", "freight", "warehouse", "cargo", "industrial", "container"]:
		if road_id.contains(hint):
			g = maxf(g, 0.9)
			break
	return clampf(g, 0.12, 1.0)


const INDUSTRIAL_KINDS := ["warehouse", "artisan_workshop", "warehouse_sawtooth", "warehouse_loading", "garage", "warehouse_shop", "fire_station"]
const RESIDENTIAL_KINDS := ["brownstone", "rowhouse", "rowhouse_terrace", "house_gable", "house_duplex", "urban_slab", "urban_infill", "l_shaped_block"]

static func chunk_grit(context: Dictionary) -> float:
	var industrial := 0.0
	var residential := 0.0
	var total := 0.0
	for entry in context.get("buildings", []):
		var area := maxf((entry.rect as Rect2).get_area(), 1.0)
		var kind := str((entry.data as Dictionary).get("kind", ""))
		total += area
		if kind in INDUSTRIAL_KINDS: industrial += area
		elif kind in RESIDENTIAL_KINDS: residential += area
	if total <= 0.0: return 0.4
	return clampf(0.4 + 0.45 * industrial / total - 0.24 * residential / total, 0.12, 1.0)


# ---------------------------------------------------------------------------
# Montagem fatiada

static func begin(chunk: Node3D, context: Dictionary) -> Dictionary:
	if not enabled(): return {}
	if _canal_tunnel == null: _canal_tunnel = load("res://world/urban_detail/CanalTunnel3D.gd")
	var rect: Rect2 = context.rect
	var buckets: Array = []
	for surface in 2:
		var layers: Array = []
		# Array comum (referência): PackedArray dentro de dicionário é cópia e o append se perderia.
		for layer in LAYERS: layers.append({"v": [], "uv": [], "t": []})
		buckets.append(layers)
	var junctions: Array = []
	var geometry = context.get("geometry")
	for junction in context.get("junctions", []):
		var widest := 0.0
		if geometry != null:
			for index in junction.roads: widest = maxf(widest, float(geometry._roads[int(index)].width))
		junctions.append([junction.position, widest * 0.68])
	var bridge := false
	if BRIDGE_SURFACE.enabled():
		bridge = rect.grow(4.0).intersects(BRIDGE_SURFACE.east_bounds()) or rect.grow(4.0).intersects(Rect2(328.75, -374.25, 36.55, 126.0))
	return {"chunk": chunk, "context": context, "rect": rect, "count": 0, "dropped": 0, "road": 0,
		"phase": 0, "buckets": buckets, "kinds": {}, "junctions": junctions, "bridge": bridge,
		"base": chunk_grit(context), "usec": 0, "max_slice": 0}


## Avança até o orçamento; devolve true quando o trecho terminou (malha já no trecho).
static func step(state: Dictionary, budget_usec := SLICE_USEC) -> bool:
	if state.is_empty(): return true
	var began := Time.get_ticks_usec()
	var span := STALL_WORK.begin()
	var roads: Array = state.context.get("roads", [])
	while state.phase == 0 and int(state.road) < roads.size():
		_road(state, roads[int(state.road)])
		state.road = int(state.road) + 1
		if Time.get_ticks_usec() - began >= budget_usec:
			_account(state, began)
			STALL_WORK.finish_slow("stream.harbor.road_wear", span, 2000)
			return false
	if state.phase == 0:
		state.phase = 1
		if Time.get_ticks_usec() - began >= budget_usec:
			_account(state, began)
			STALL_WORK.finish_slow("stream.harbor.road_wear", span, 2000)
			return false
	if state.phase == 1:
		_yard(state)
		_markings(state)
		state.phase = 2
		if Time.get_ticks_usec() - began >= budget_usec:
			_account(state, began)
			STALL_WORK.finish_slow("stream.harbor.road_wear", span, 2000)
			return false
	_commit(state)
	_account(state, began)
	STALL_WORK.finish_slow("stream.harbor.road_wear", span, 2000)
	stats.chunks = int(stats.chunks) + 1
	stats.decals = int(stats.decals) + int(state.count)
	stats.max_chunk_decals = maxi(int(stats.max_chunk_decals), int(state.count))
	stats.dropped = int(stats.dropped) + int(state.dropped)
	stats.max_chunk_usec = maxi(int(stats.max_chunk_usec), int(state.usec))
	return true


## Sem fatias (CityChunkDressing.build_chunk, testes).
static func build_chunk(chunk: Node3D, context: Dictionary) -> void:
	var state := begin(chunk, context)
	while not step(state, 1 << 30): pass


static func _account(state: Dictionary, began: int) -> void:
	var spent := Time.get_ticks_usec() - began
	state.usec = int(state.usec) + spent
	state.max_slice = maxi(int(state.max_slice), spent)
	stats.max_slice_usec = maxi(int(stats.max_slice_usec), spent)
	stats.total_usec = int(stats.total_usec) + spent


# ---------------------------------------------------------------------------
# Ruas

static func _road(state: Dictionary, road: Dictionary) -> void:
	var road_id := str(road.id)
	if "bridge" in road_id or "tunnel" in road_id: return
	var points: PackedVector2Array = road.points
	var width := float(road.width)
	var half := width * 0.5
	var area: Rect2 = (state.rect as Rect2).grow(half + 4.0)
	var travelled := 0.0
	for index in points.size() - 1:
		var a := points[index]
		var b := points[index + 1]
		var length := a.distance_to(b)
		if length < 0.01: continue
		var span := _clip_range(a, b, area)
		if span.y > span.x:
			# Amostras alinhadas à distância acumulada da rua: a mesma em qualquer trecho.
			var k := ceili((travelled + span.x) / STEP)
			while k * STEP - travelled <= span.y:
				_sample(state, road, index, k, a, b, length, k * STEP - travelled)
				k += 1
		travelled += length


## Parte [t0, t1] (em metros a partir de a) do segmento dentro do retângulo.
static func _clip_range(a: Vector2, b: Vector2, area: Rect2) -> Vector2:
	var length := a.distance_to(b)
	var direction := (b - a) / length
	var t0 := 0.0
	var t1 := length
	for axis in 2:
		var origin := a[axis]
		var d := direction[axis]
		var low := area.position[axis]
		var high := area.end[axis]
		if absf(d) < 0.000001:
			if origin < low or origin > high: return Vector2(1, 0)
			continue
		var ta := (low - origin) / d
		var tb := (high - origin) / d
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)


static func _sample(state: Dictionary, road: Dictionary, index: int, k: int, a: Vector2, b: Vector2, length: float, s: float) -> void:
	var road_id := str(road.id)
	var width := float(road.width)
	var half := width * 0.5
	var tangent := (b - a) / length
	var normal := Vector2(tangent.y, -tangent.x)
	var p := a + tangent * s
	var rng := _rng
	rng.seed = ("%s|rw|%d|%d" % [road_id, index, k]).hash()
	var g := grit(p, float(state.base), road_id)
	var one_way := road_id.contains("inbound") or road_id.contains("outbound")
	var per_direction := maxi(1, int(road.get("lanes_per_direction", 1)))
	var lanes := per_direction if one_way else per_direction * 2
	var lane_w := width / float(lanes)
	var curb := float(road.get("sidewalk_width", 2.625)) > 0.95
	var lane_center := -half + lane_w * (float(rng.randi() % lanes) + 0.5)
	var wheel := lane_center + (0.8 if rng.randf() < 0.5 else -0.8) * minf(1.0, lane_w / 3.0)
	var near_junction := _near_junction(state, p, 1.0)

	# Sujeira juntada no meio-fio (a cada 6 m, dos dois lados): areia, folha, lodo.
	if curb and k % 2 == 0:
		for side: float in [-1.0, 1.0]:
			if rng.randf() >= 0.32 + 0.6 * g: continue
			var long := rng.randf_range(5.2, 7.6)
			var across := rng.randf_range(0.42, 0.7) * (0.85 + g * 0.35)
			var center: Vector2 = p + tangent * rng.randf_range(-0.6, 0.6) + normal * side * (half - across * 0.5 + 0.12)
			if _near_junction(state, center, 1.5): continue
			_emit(state, "curb_sand" if rng.randf() < 0.2 + 0.4 * g else "curb_grime", center, tangent, long, across, STAINS, Y, rng.randf() < 0.5, normal * side)
	# Óleo pingado no meio da faixa (a cada 6 m, uma faixa por vez).
	if k % 2 == 1 and rng.randf() < 0.22 + 0.45 * g:
		var center := p + normal * (lane_center + rng.randf_range(-0.15, 0.15))
		if not near_junction:
			_emit(state, "lane_oil", center, tangent, rng.randf_range(5.0, 8.0), rng.randf_range(0.8, 1.15), STAINS, Y, rng.randf() < 0.5)
	# Rachadura longitudinal (junta de faixa, borda ou trilha do pneu) ou selante de trinca.
	if k % 3 == 0 and rng.randf() < 0.18 + 0.32 * g:
		var choice := rng.randf()
		var offset := 0.0 if choice < 0.35 else (wheel if choice < 0.7 else (half - 0.55) * (1.0 if rng.randf() < 0.5 else -1.0))
		var sealed := rng.randf() < 0.6 - 0.45 * g
		_emit(state, "sealant" if sealed else "crack_line", p + normal * offset, tangent, rng.randf_range(4.0, 9.0), rng.randf_range(0.22, 0.34) if sealed else rng.randf_range(0.16, 0.26), CRACKS, Y, rng.randf() < 0.5)
	# Trinca transversal (retração), de borda a borda ou só uma parte.
	if rng.randf() < 0.025 + 0.05 * g and not near_junction:
		var reach := width * rng.randf_range(0.35, 0.95)
		var offset := rng.randf_range(-half + reach * 0.5, half - reach * 0.5)
		_emit(state, "sealant" if rng.randf() < 0.5 - 0.3 * g else "crack_line", p + normal * offset, normal, reach, 0.24, CRACKS, Y, rng.randf() < 0.5)
	# Remendo de corte de rede (retângulo de asfalto mais novo) e vala atravessando a faixa.
	if rng.randf() < 0.035 + 0.08 * g:
		var along := rng.randf_range(1.2, 3.0)
		var across := rng.randf_range(1.0, 2.4)
		var offset := clampf(lane_center + rng.randf_range(-0.6, 0.6), -half + across * 0.5, half - across * 0.5)
		_emit(state, "patch", p + normal * offset, tangent.rotated(rng.randf_range(-0.05, 0.05)), along, across, BASE, Y, rng.randf() < 0.5, Vector2.ZERO, rng.randf() < 0.5)
	if rng.randf() < 0.01 + 0.025 * g and not near_junction:
		var reach := lane_w if rng.randf() < 0.6 else width * 0.96
		var offset := lane_center if reach < width * 0.9 else 0.0
		_emit(state, "trench", p + normal * offset, normal, reach, rng.randf_range(0.6, 1.1), BASE, Y, rng.randf() < 0.5)
	# Chapa de aço sobre vala aberta: só na zona do porto, onde o caminhão passa.
	if g > 0.6 and rng.randf() < 0.008:
		_emit(state, "plate", p + normal * lane_center, tangent.rotated(rng.randf_range(-0.08, 0.08)), rng.randf_range(2.2, 2.6), rng.randf_range(1.1, 1.3), FIXTURES, Y, rng.randf() < 0.5, Vector2.ZERO, rng.randf() < 0.5)
	# Pele de jacaré na trilha do pneu.
	if rng.randf() < 0.025 + 0.1 * g:
		var size := rng.randf_range(1.6, 3.2)
		_emit(state, "alligator", p + normal * wheel, tangent.rotated(rng.randf() * TAU), size, size * rng.randf_range(0.75, 1.0), CRACKS, Y, rng.randf() < 0.5, Vector2.ZERO, rng.randf() < 0.5)
	# Buraco raso (trilha do pneu ou beira, onde a água para) e desagregação; parte com água.
	if rng.randf() < 0.006 + 0.055 * g * g:
		var offset := wheel if rng.randf() < 0.5 else (half - rng.randf_range(0.6, 1.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
		var size := rng.randf_range(0.45, 1.25)
		var water := rng.randf() < 0.35
		var center := p + normal * offset
		var heading := tangent.rotated(rng.randf() * TAU)
		_emit(state, "pothole_water" if water else "pothole", center, heading, size, size * rng.randf_range(0.8, 1.0), HOLES, Y, rng.randf() < 0.5, Vector2.ZERO, rng.randf() < 0.5)
		if water: _emit(state, "puddle", center, heading, size * 0.62, size * 0.5, 0, Y, rng.randf() < 0.5)
	if rng.randf() < 0.008 + 0.04 * g * g:
		var size := rng.randf_range(1.4, 2.4)
		_emit(state, "ravel", p + normal * wheel, tangent.rotated(rng.randf() * TAU), size, size, HOLES, Y, rng.randf() < 0.5, Vector2.ZERO, rng.randf() < 0.5)
	# Óleo onde o carro para: meio da faixa, mais perto do cruzamento.
	var stop_zone := _near_junction(state, p, 7.0) and not near_junction
	if rng.randf() < (0.05 + 0.1 * g) * (2.0 if stop_zone else 1.0):
		var size := rng.randf_range(0.8, 1.7)
		_emit(state, "oil", p + normal * (lane_center + rng.randf_range(-0.35, 0.35)), tangent.rotated(rng.randf() * TAU), size, size * rng.randf_range(0.7, 1.0), STAINS, Y, rng.randf() < 0.5, Vector2.ZERO, rng.randf() < 0.5)
	# Pingos de carro estacionado junto ao meio-fio.
	if curb and rng.randf() < 0.035 + 0.06 * g:
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		_emit(state, "oil_drips", p + normal * side * (half - 1.1), tangent, rng.randf_range(1.3, 1.9), rng.randf_range(1.1, 1.5), STAINS, Y, rng.randf() < 0.5, Vector2.ZERO, rng.randf() < 0.5)
	# Ferrugem (contêiner, sucata, chapa): só na zona industrial.
	if g > 0.5 and rng.randf() < (g - 0.5) * 0.22:
		var size := rng.randf_range(1.0, 2.2)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		_emit(state, "rust", p + normal * side * (half - rng.randf_range(0.6, 1.6)), tangent.rotated(rng.randf() * TAU), size, size * rng.randf_range(0.7, 1.0), STAINS, Y, rng.randf() < 0.5)
	# Tampa de bueiro rente ao asfalto (no lugar do disco de 10 lados do kit).
	if rng.randf() < 0.018 and not near_junction:
		var center := p + normal * (0.0 if rng.randf() < 0.4 else lane_center * 0.5)
		if center.distance_to(SEWER_ACCESS) > SEWER_CLEARANCE + 0.6:
			_emit(state, "manhole", center, tangent.rotated(rng.randf() * TAU), 0.92, 0.92, FIXTURES, Y)
	# Boca de lobo na sarjeta, comprida no sentido da rua.
	if curb and rng.randf() < 0.03 and not near_junction:
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		_emit(state, "grate", p + normal * side * (half - 0.3), tangent, 0.96, 0.48, FIXTURES, Y)
	# Poça em depressão: sarjeta ou trilha afundada.
	if rng.randf() < 0.018 + 0.05 * g:
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var offset := side * (half - rng.randf_range(0.5, 0.9)) if rng.randf() < 0.7 else wheel
		var along := rng.randf_range(1.0, 2.6)
		_emit(state, "puddle", p + normal * offset, tangent.rotated(rng.randf_range(-0.2, 0.2)), along, along * rng.randf_range(0.45, 0.7), 0, Y, rng.randf() < 0.5, Vector2.ZERO, rng.randf() < 0.5)


## Pátio do porto sul (concreto do cais): óleo de caminhão e empilhadeira, ferrugem de contêiner,
## junta trincada, remendo de asfalto, poça e trilha de pneu. Grade de 6 m sorteada pela célula
## (mesma em qualquer trecho), fora das ruas (que já têm o desgaste delas), dos contêineres e galpões.
const YARD_CELL := 6.0

static func _yard(state: Dictionary) -> void:
	var rect: Rect2 = state.rect
	var land := Rect2(PORT_LAYOUT.LAND.position / 16.0, PORT_LAYOUT.LAND.size / 16.0)
	var area := rect.intersection(land)
	if not area.has_area(): return
	var blocked: Array[Rect2] = []
	for box in PORT_LAYOUT.containers(): blocked.append(Rect2(box.position / 16.0, box.size / 16.0).grow(0.4))
	for box in PORT_LAYOUT.WAREHOUSES: blocked.append(Rect2(box.position / 16.0, box.size / 16.0).grow(0.6))
	var roads: Array = state.context.get("roads", [])
	for cx in range(floori(area.position.x / YARD_CELL), ceili(area.end.x / YARD_CELL)):
		for cz in range(floori(area.position.y / YARD_CELL), ceili(area.end.y / YARD_CELL)):
			_rng.seed = ("yard|%d|%d" % [cx, cz]).hash()
			var p := Vector2((float(cx) + _rng.randf()) * YARD_CELL, (float(cz) + _rng.randf()) * YARD_CELL)
			if not land.has_point(p) or not rect.has_point(p): continue
			var skip := false
			for box in blocked:
				if box.has_point(p):
					skip = true
					break
			if skip or _on_road(roads, p, 0.8): continue
			var heading := Vector2.RIGHT.rotated(_rng.randf() * TAU)
			var roll := _rng.randf()
			if roll < 0.11:
				var size := _rng.randf_range(0.8, 2.2)
				_emit(state, "oil", p, heading, size, size * _rng.randf_range(0.7, 1.0), STAINS, Y, _rng.randf() < 0.5, Vector2.ZERO, _rng.randf() < 0.5)
			elif roll < 0.15:
				_emit(state, "oil_drips", p, heading, 1.6, 1.3, STAINS, Y, _rng.randf() < 0.5)
			elif roll < 0.24:
				var size := _rng.randf_range(1.0, 2.6)
				_emit(state, "rust", p, heading, size, size * _rng.randf_range(0.7, 1.0), STAINS, Y, _rng.randf() < 0.5, Vector2.ZERO, _rng.randf() < 0.5)
			elif roll < 0.31:
				# Junta de dilatação trincada: alinhada à grade do pátio.
				var axis := Vector2.RIGHT if _rng.randf() < 0.5 else Vector2.DOWN
				_emit(state, "sealant" if _rng.randf() < 0.3 else "crack_line", p, axis, _rng.randf_range(4.0, 8.0), 0.24, CRACKS, Y, _rng.randf() < 0.5)
			elif roll < 0.34:
				var size := _rng.randf_range(1.8, 3.4)
				_emit(state, "patch", p, Vector2.RIGHT if _rng.randf() < 0.5 else Vector2.DOWN, size, size * _rng.randf_range(0.6, 1.0), BASE, Y, _rng.randf() < 0.5, Vector2.ZERO, _rng.randf() < 0.5)
			elif roll < 0.36:
				var size := _rng.randf_range(1.6, 3.0)
				_emit(state, "alligator", p, heading, size, size, CRACKS, Y, _rng.randf() < 0.5)
			elif roll < 0.41:
				var along := _rng.randf_range(1.2, 3.2)
				_emit(state, "puddle", p, heading, along, along * _rng.randf_range(0.45, 0.75), 0, Y, _rng.randf() < 0.5, Vector2.ZERO, _rng.randf() < 0.5)
			elif roll < 0.42:
				var size := _rng.randf_range(0.5, 1.1)
				_emit(state, "pothole", p, heading, size, size * 0.9, HOLES, Y, _rng.randf() < 0.5)
			elif roll < 0.48:
				# Trilha de pneu de caminhão/empilhadeira atravessando o pátio.
				var axis := Vector2.RIGHT if _rng.randf() < 0.5 else Vector2.DOWN
				_emit(state, "tire_grime", p, axis.rotated(_rng.randf_range(-0.25, 0.25)), _rng.randf_range(6.0, 11.0), _rng.randf_range(0.45, 0.6), STAINS, Y, _rng.randf() < 0.5)
			elif roll < 0.485:
				_emit(state, "plate", p, Vector2.RIGHT if _rng.randf() < 0.5 else Vector2.DOWN, 2.4, 1.2, FIXTURES, Y, _rng.randf() < 0.5)


static func _on_road(roads: Array, point: Vector2, margin: float) -> bool:
	for road in roads:
		var points: PackedVector2Array = road.points
		var reach := float(road.width) * 0.5 + margin
		for index in points.size() - 1:
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])) < reach: return true
	return false


## Pintura gasta: tinta lascada nas faixas longitudinais e borracha do pneu sobre faixa de pedestre
## e linha de retenção (por cima da pintura, Y_PAINT).
static func _markings(state: Dictionary) -> void:
	var context: Dictionary = state.context
	var geometry = context.get("geometry")
	if geometry == null: return
	var rect: Rect2 = state.rect
	for road in context.get("roads", []):
		var road_id := str(road.id)
		if "bridge" in road_id or "tunnel" in road_id: continue
		var styles: Array = geometry._marking_styles(road)
		if styles.is_empty(): continue
		var points: PackedVector2Array = road.points
		var travelled := 0.0
		for index in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var length := a.distance_to(b)
			if length < 0.01: continue
			var span := _clip_range(a, b, rect.grow(float(road.width) * 0.5 + 4.0))
			if span.y > span.x:
				var tangent := (b - a) / length
				var normal := tangent.orthogonal()
				var k := ceili((travelled + span.x) / 6.0)
				while k * 6.0 - travelled <= span.y:
					var p := a + tangent * (k * 6.0 - travelled)
					_rng.seed = ("%s|paint|%d|%d" % [road_id, index, k]).hash()
					var g := grit(p, float(state.base), road_id)
					for style in styles:
						if _rng.randf() >= 0.35 + 0.5 * g: continue
						var center: Vector2 = p + normal * float(style.offset)
						if _near_junction(state, center, 2.0): continue
						_emit(state, "paint_chips", center, tangent, _rng.randf_range(4.5, 6.5), 0.22, TOP, Y_PAINT, _rng.randf() < 0.5)
					k += 1
			travelled += length
	# Faixas de pedestre e linhas de retenção dos cruzamentos deste trecho: trilha dos pneus.
	for junction in geometry.get("crossing_layout"):
		for entry in junction.get("entries", []):
			if not bool(entry.get("enabled", false)): continue
			var center: Vector2 = entry.position
			if not rect.has_point(center): continue
			var direction: Vector2 = (entry.direction as Vector2).normalized()
			var across := direction.orthogonal()
			var road_width := float(entry.width)
			_rng.seed = ("cross|%d|%d" % [roundi(center.x * 10.0), roundi(center.y * 10.0)]).hash()
			var g := grit(center, float(state.base), "")
			var lane := road_width * 0.25
			for lane_side in [-1.0, 1.0]:
				for track in [-0.8, 0.8]:
					if _rng.randf() >= 0.45 + 0.45 * g: continue
					var offset: float = lane_side * lane + track
					_emit(state, "tire_grime", center + across * offset, direction, float(entry.depth) + 1.6, _rng.randf_range(0.4, 0.55), TOP, Y_PAINT, _rng.randf() < 0.5)


# ---------------------------------------------------------------------------
# Emissão e lote

static func _near_junction(state: Dictionary, point: Vector2, extra: float) -> bool:
	for junction in state.junctions:
		if point.distance_to(junction[0]) < float(junction[1]) + extra: return true
	return false


## Um quad no chão. `along` dá o eixo do comprimento (u do atlas); `v0_toward`, se não for zero,
## aponta para onde fica v = 0 (meio-fio, nas faixas de sujeira).
static func _emit(state: Dictionary, kind: String, center: Vector2, along: Vector2, length: float, width: float, layer: int, y: float,
		flip_u := false, v0_toward := Vector2.ZERO, flip_v := false) -> void:
	if not (state.rect as Rect2).has_point(center): return
	if not center.is_finite() or not along.is_finite() or not is_finite(length) or not is_finite(width): return
	if length <= 0.01 or width <= 0.01: return
	if center.distance_to(SEWER_ACCESS) < SEWER_CLEARANCE: return
	if _canal_tunnel.reserves(center, maxf(length, width) * 0.5): return
	if bool(state.bridge) and BRIDGE_SURFACE.owns_surface_point(center): return
	if int(state.count) >= MAX_DECALS:
		state.dropped = int(state.dropped) + 1
		return
	var axis := along.normalized()
	var side := Vector2(-axis.y, axis.x)
	if v0_toward != Vector2.ZERO:
		# v0 fica em -side; troca se o meio-fio estiver do outro lado.
		flip_v = side.dot(v0_toward) > 0.0
	var cell: Rect2 = CELLS[kind]
	var u0 := cell.position.x / ATLAS_SIZE
	var u1 := cell.end.x / ATLAS_SIZE
	var v0 := cell.position.y / ATLAS_SIZE
	var v1 := cell.end.y / ATLAS_SIZE
	if flip_u:
		var swap := u0
		u0 = u1
		u1 = swap
	if flip_v:
		var swap := v0
		v0 = v1
		v1 = swap
	var t := axis * length * 0.5
	var n := side * width * 0.5
	var bucket: Dictionary = state.buckets[1 if kind in WET_KINDS else 0][layer]
	var corners := [center - t - n, center + t - n, center + t + n, center - t + n]
	var uvs := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	for corner_index in 4:
		var corner: Vector2 = corners[corner_index]
		(bucket.v as Array).append(Vector3(corner.x, y, corner.y))
		(bucket.uv as Array).append(uvs[corner_index])
	(bucket.t as Array).append(Vector3(axis.x, 0.0, axis.y))
	state.count = int(state.count) + 1
	state.kinds[kind] = int(state.kinds.get(kind, 0)) + 1


## Monta a malha do trecho: superfície 0 fosca, 1 molhada. Formato igual ao do QuadMesh
## (vértice, normal, tangente, UV, índice) que os decalques do CityLook já desenham.
static func _commit(state: Dictionary) -> void:
	var chunk: Node3D = state.chunk
	if int(state.count) == 0 or not is_instance_valid(chunk): return
	var mesh := ArrayMesh.new()
	var mats := materials()
	var to_local := (chunk.global_transform if chunk.is_inside_tree() else chunk.transform).affine_inverse()
	var surface_kinds := []
	for surface in 2:
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var tangents := PackedFloat32Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for layer in LAYERS:
			var bucket: Dictionary = state.buckets[surface][layer]
			var quad_vertices := PackedVector3Array(bucket.v)
			var quad_uvs := PackedVector2Array(bucket.uv)
			var quad_axes := PackedVector3Array(bucket.t)
			for quad in quad_axes.size():
				var base := vertices.size()
				var axis: Vector3 = quad_axes[quad]
				for corner in 4:
					vertices.append(to_local * quad_vertices[quad * 4 + corner])
					uvs.append(quad_uvs[quad * 4 + corner])
					normals.append(Vector3.UP)
					tangents.append_array([axis.x, 0.0, axis.z, 1.0])
				# Frente para cima (CULL_BACK): mesmo sentido dos polígonos de rua (anti-horário em x,z).
				var p0 := Vector2(quad_vertices[quad * 4].x, quad_vertices[quad * 4].z)
				var p1 := Vector2(quad_vertices[quad * 4 + 1].x, quad_vertices[quad * 4 + 1].z)
				var p2 := Vector2(quad_vertices[quad * 4 + 2].x, quad_vertices[quad * 4 + 2].z)
				if (p1 - p0).cross(p2 - p0) > 0.0:
					indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
				else:
					indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		if vertices.is_empty(): continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[surface])
		surface_kinds.append(surface)
	if mesh.get_surface_count() == 0: return
	var instance := MeshInstance3D.new()
	instance.name = "HarborRoadWear"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rente ao asfalto e já fora das rampas do túnel: o recorte do túnel não precisa ler esta malha.
	instance.set_meta(&"canal_carve_skip", true)
	instance.set_meta(&"road_wear_decals", int(state.count))
	instance.set_meta(&"road_wear_kinds", state.kinds.duplicate())
	chunk.add_child(instance)
