extends RefCounted
## Acabamento visual "cidade de jogo" aplicado a cada chunk de Harbor depois
## que o NativeRegion termina de montá-lo.
##
## Roda uma única vez por chunk (no streaming, não por quadro) e só acrescenta
## adereços ou troca material de malhas já existentes: não move prédio, não
## mexe em colisão da fonte V1 e não depende de nenhuma arte ser reescrita.
## Quem quiser desligar tudo remove a chamada em NativeRegion._build_chunk.
##
## Tudo que é repetido (hidrante, lixeira, mancha de óleo, ar-condicionado)
## sai em MultiMesh por tipo e por chunk. Jardineiras têm colisão estática;
## mobília quebrável é registrada em FragileProps3D. Decalques e detalhes de
## telhado permanecem apenas visuais.

const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const CONTEXT_INDEX := preload("res://world/city_look/CityContextIndex.gd")
const CONTEXT_META := &"city_context_index"
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const KIT := preload("res://world/city_look/CityPropKit.gd")
const BRANDS := preload("res://world/city_look/CityBrands.gd")
const LIFE := preload("res://world/city_look/BuildingLife.gd")
const STAIRS := preload("res://world/city_look/WalkableStairs.gd")
const ROOFS := preload("res://world/city_look/RoofSurfaces.gd")
const ROOF_CIRCULATION := preload("res://world/places/harbor_buildings/HarborRoofCirculation.gd")
## Meia planta da casinha da escada (x, z), para prendê-la dentro da laje de cima.
const HOUSE_HALF := Vector2(1.04, 0.84)
const GROUND_LITTER := preload("res://world/city_look/CityGroundLitter.gd")
const POLICE := preload("res://world/city_look/PoliceStationDressing.gd")
const NIGHT_GROUP := &"city_look_night"
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const BRIDGE_SURFACE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const PLACEMENTS := preload("res://world/editing/WorldPlacements.gd")
const FILL := preload("res://world/city_look/SidewalkFill.gd")
## FURNITURE, ROOF_* e WORKSHOP_VEHICLE_ACCESS moram em dados; ficam reexportados aqui com o mesmo nome.
const TABLES := preload("res://data/catalogs/CityDressingTables.gd")
## Passos 1-2, 5, 11 (decalques antigos) e 12 em auxiliares estáticos (01/11, Onda 1 do plano de
## divisão); cada função antiga continua aqui como delegação de uma linha.
const NIGHT_LAMPS := preload("res://world/city_look/CityNightLamps.gd")
const ROAD_DECALS := preload("res://world/city_look/CityRoadDecals.gd")
const ROOFTOPS := preload("res://world/city_look/CityRooftopDressing.gd")
const GROUND_FACE_UP := preload("res://world/city_look/CityGroundFaceUp.gd")
## Postes de energia, fiação e desgaste por atlas (pedido de 29/10); GETECO_HARBOR_POLES=0 desliga.
const UTILITY := preload("res://world/city_look/HarborUtilityLines.gd")
const WEAR := preload("res://world/city_look/HarborStreetWear.gd")
const ROAD_WEAR := preload("res://world/shared/roads/HarborRoadWear.gd")
const FRAGILE_KINDS := ["signal_pole", "stop_sign", "hydrant", "trash_can", "news_box", "mailbox", "phone_booth", "bench_seat", "dumpster", "trash_bags", "planter",
	"cafe_set", "cafe_parasol", "cafe_parasol_b", "produce_stand", "a_frame", "beer_crates", "pot_plant", "wheelie_bins", "bike_rack", "pallet_stack", "tire_stack", "drums",
	"food_cart", "ice_freezer", "clothes_rack", "flower_buckets", "gas_cylinders", "door_bench", "motorcycle", "street_tree", "street_tree_b",
	# StreetJunk (lixo, porto, orla; mesma lista de StreetJunkKit.KINDS): tudo é leve o bastante para o carro espalhar.
	"bag_single", "bag_pile", "bag_torn", "cardboard", "refuse_heap", "wood_crates", "fish_crates", "rusty_barrels", "rope_coil",
	"fishing_net", "loose_tires", "rubble", "rubble_skip", "beach_parasol", "beach_parasol_b", "beach_chairs", "plastic_chairs", "bar_table"]
const JUNK := preload("res://world/city_look/StreetJunk.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Fatia dos passos 12 (telhados) e 13 (lotes) no streaming. Cada chamada processa itens
## inteiros até passar disto; um item caro sozinho ainda estoura, mas aparece com nome
## no log (spans stream.harbor.rooftops.* / dressing_flush.*).
const DRESSING_SLICE_USEC := 2000

# Fração de janelas acesas à noite. Residência acende menos que vitrine.
const WINDOW_LIT_RATIO := 0.60
const SHOP_LIT_RATIO := 0.85
# Largura da calçada gerada por HarborRoadGeometry3D (42 px de cada lado).
const SIDEWALK := 42.0 / 16.0
const SEWER_ACCESS := Vector2(1182.0, 2114.0) / 16.0
const SEWER_CLEARANCE := 2.0
const FURNITURE_SPACING := 7.0
# Postes de calçada gerados (2026-09-25: jogador achou a cidade escura demais;
# só havia luz onde a arte autorada trazia um poste). Alterna os lados a cada
# LAMP_SPACING, então cada calçada tem um poste a cada 2×LAMP_SPACING e as
# manchas de luz (~11 m) se emendam em zigue-zague pela rua.
const LAMP_SPACING := 18.0
const LAMP_HEIGHT := 5.4
const LAMP_ARM := 1.3
# Poste autorado ou gerado mais perto que isso já ilumina o trecho.
const LAMP_CLEARANCE := 9.0
static var _lamp_meshes: Dictionary = {}
const DECAL_Y := 0.034
const WORKSHOP_VEHICLE_ACCESS := TABLES.WORKSHOP_VEHICLE_ACCESS
# "ac_unit" fica fora: é a peça de telhado mais numerosa (peso 0.2 em ROOF_PROPS) e só
# aparece no telhado, onde a sombra dela quase não se vê e custa passe de sombra em cada
# instância. Caixa-d'água e torre de resfriamento continuam: são elas que dão a silhueta.
const SHADOW_CASTERS := ["water_tank", "cooling_tower", "signal_pole", "dumpster", "phone_booth", "billboard_frame", "fe_platform", "fe_stair", "fe_stair_m", "window_ac", "laundry",
	# Mobília de calçada: sem sombra, lixeira/hidrante/jornaleiro pareciam soltos,
	# flutuando sobre a calçada (relato do jogador em 2026-09-24).
	"trash_can", "news_box", "mailbox", "hydrant", "stop_sign", "bench_seat", "planter", "bollard", "trash_bags",
	# SidewalkFill: árvore e guarda-sol são as sombras que mais assentam a rua vista de cima.
	"street_tree", "street_tree_b", "cafe_set", "cafe_parasol", "cafe_parasol_b", "produce_stand", "pallet_stack", "food_cart", "motorcycle", "ice_freezer",
	# StreetJunk: só o que tem altura (caçamba, guarda-sol, mesa, pilhas); saco solto, entulho, rede e
	# pneu são baixos e a sombra deles custaria passe de sombra sem aparecer nesta câmera.
	"rubble_skip", "beach_parasol", "beach_parasol_b", "bar_table", "plastic_chairs", "wood_crates", "rusty_barrels", "fish_crates", "bag_pile", "refuse_heap"]
# Corte por distância (m, até a peça) só para peças PEQUENAS de telhado: a câmera do
# jogo fica 25 m acima e 25 m atrás do jogador (CameraRig.EXTERIOR_OFFSET) e o quadro
# cobre uns 50 m em volta dele; nada além de 60-80 m aparece na tela de jogo. Em
# 2026-10-16, quatro pontos da cidade não mostraram peça cortada dentro do quadro. Caixa-d'água, torre de resfriamento,
# outdoor, beacon e neon ficam fora de propósito: formam a silhueta da cidade de longe.
# O MultiMesh cobre o chunk inteiro (CELL = 64 m) e o Godot mede a distância até o
# centro da AABB, por isso _flush soma meia diagonal da AABB a este valor.
const ROOF_SMALL_RANGE := {"pigeons": 60.0, "roof_chairs": 60.0, "laundry": 65.0, "roof_garden": 70.0, "vent": 70.0, "antenna": 80.0, "dish": 75.0, "pipe_run": 65.0, "roof_hatch": 65.0, "skylight": 65.0, "satellite_row": 75.0}


static func _workshop_driving(point: Vector2) -> bool:
	for area in WORKSHOP_VEHICLE_ACCESS:
		if area.has_point(point): return true
	return false

static func build_chunk(region: Node3D, chunk: Node3D, rect: Rect2) -> void:
	var context := _context(region, rect)
	var batches := {}
	_night_pass(chunk, context)
	_sidewalk_lamps(chunk, context)
	UTILITY.build_chunk(chunk, context)
	STAIRS.build_chunk(chunk)
	_texture_walls(chunk)
	_face_ground_up(chunk)
	_junction_signage(context, batches, chunk)
	FILL.street_trees(context, batches)
	FILL.frontage(chunk, context, batches)
	_sidewalk_furniture(context, batches)
	_building_surroundings(context, batches)
	JUNK.dress(chunk, context, batches)
	_road_wear(context, batches)
	ROAD_WEAR.build_chunk(chunk, context)
	_rooftops(chunk, context, batches)
	_flush(chunk, batches)
	GROUND_LITTER.build_chunk(chunk, context, batches, WORKSHOP_VEHICLE_ACCESS)


static func build_chunk_step(state: Dictionary) -> bool:
	if not state.has("step"): state.step = 0
	match state.step:
		0:
			state.context = _context(state.region, state.rect)
			state.batches = {}
		1: _night_pass(state.chunk, state.context)
		2:
			# Postes de luz e, na volta seguinte do mesmo passo, os de energia com a fiação: fatias
			# separadas sem renumerar os passos (o log "dressing_step.N" continua comparável).
			if not state.get("lamps_done", false):
				_sidewalk_lamps(state.chunk, state.context)
				state.lamps_done = true
				return false
			UTILITY.build_chunk(state.chunk, state.context)
		3: STAIRS.build_chunk(state.chunk)
		4: _texture_walls(state.chunk)
		5:
			if not _face_ground_up_step(state): return false
		6: _junction_signage(state.context, state.batches, state.chunk)
		7: FILL.street_trees(state.context, state.batches)
		8: FILL.frontage(state.chunk, state.context, state.batches)
		9: _sidewalk_furniture(state.context, state.batches)
		10:
			# Lixo, porto e orla (StreetJunk) em fatias de ~1,5 ms dentro do mesmo passo, sem renumerar
			# os seguintes (os logs de quadro lento citam os passos pelo número).
			if not state.has("street_junk"):
				_building_surroundings(state.context, state.batches)
				state.street_junk = JUNK.begin(state.chunk, state.context, state.batches)
				if not bool(state.street_junk.done): return false
			if not JUNK.step(state.street_junk): return false
		11:
			# Desgaste novo das ruas (HarborRoadWear) em fatias de ~2 ms dentro do mesmo passo.
			if not state.has("road_wear"):
				_road_wear(state.context, state.batches)
				state.road_wear = ROAD_WEAR.begin(state.chunk, state.context)
				# O sorteio antigo já gastou a fatia: o desgaste começa na próxima chamada.
				if not (state.road_wear as Dictionary).is_empty(): return false
			if not ROAD_WEAR.step(state.road_wear): return false
		12:
			# Telhados em fatias de ~2 ms (playtest 30/10, export release a 110-120 km/h: o
			# passo inteiro num quadro deu 35, 44 e 53 ms). Mesmo número de passo no log.
			if not state.has("rooftops"): state.rooftops = _rooftops_begin(state.chunk)
			if not _rooftops_step(state.rooftops, state.batches, DRESSING_SLICE_USEC): return false
		13:
			# Montagem dos lotes (MultiMesh) um tipo por vez, com o mesmo orçamento do passo 12:
			# antes era um chunk inteiro de tipos num quadro só, logo depois dos telhados.
			if not state.has("flush"):
				state.flush = _flush_begin(state.chunk, state.batches)
				return false
			if not _flush_step(state.flush, DRESSING_SLICE_USEC): return false
		14:
			if not state.has("ground_litter"): state.ground_litter = GROUND_LITTER.begin(state.chunk, state.context, state.batches, WORKSHOP_VEHICLE_ACCESS)
			if not GROUND_LITTER.step(state.ground_litter): return false
	state.step += 1
	return state.step > 14


# ---------------------------------------------------------------------------
# Contexto: só as vias/prédios que tocam o chunk, para os testes de colisão
# visual (não pôr lixeira no asfalto nem dentro de prédio) ficarem baratos.

static func invalidate_context(region: Node) -> void:
	if region.has_meta(CONTEXT_META): region.remove_meta(CONTEXT_META)


static func _context(region: Node3D, rect: Rect2) -> Dictionary:
	var geometry = region.get("harbor_road_geometry")
	var index = region.get_meta(CONTEXT_META) if region.has_meta(CONTEXT_META) else null
	if index == null or not index.matches_geometry(geometry):
		index = CONTEXT_INDEX.new()
		index.configure(geometry, region.get("buildings"))
		region.set_meta(CONTEXT_META, index)
	var selected: Dictionary = index.query(rect.grow(16.0))
	return {"region": region, "rect": rect, "roads": selected.roads, "junctions": selected.junctions, "buildings": selected.buildings, "geometry": geometry, "lamps": [],"transit_reservations":index.street_reservations}

static func _in_chunk(context: Dictionary, point: Vector2) -> bool:
	return (context.rect as Rect2).has_point(point)


## Distância até o eixo da via mais próxima menos a meia largura: <0 é asfalto,
## 0..SIDEWALK é calçada.
static func _road_clearance(context: Dictionary, point: Vector2) -> float:
	# O canteiro entre as antigas pistas agora pertence ao asfalto contínuo.
	if BRIDGE_SURFACE.enabled() and BRIDGE_SURFACE.east_bounds().has_point(point) and Geometry2D.is_point_in_polygon(point,BRIDGE_SURFACE.east_asphalt_footprint()): return -1.0
	var best := INF
	for road in context.roads:
		var points: PackedVector2Array = road.points
		for index in points.size() - 1:
			var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])
			best = minf(best, point.distance_to(closest) - float(road.width) * 0.5)
	return best


static func _inside_building(context: Dictionary, point: Vector2, margin := 0.3) -> bool:
	if context.region.region_id == "harbor" and preload("res://activities/skate/SkateParkLayout.gd").reserved(point, margin): return true
	if context.region.region_id == "harbor" and preload("res://runtime/FishingLocation.gd").reserved(point,margin): return true
	if context.region.region_id == "harbor" and preload("res://world/places/amusement_park/AmusementParkLayout.gd").reserved(point,margin): return true
	if preload("res://world/roadside_parking/RoadsideParkingLayout.gd").is_reserved(point, context.region.get_meta(&"roadside_parking_sites", []), margin): return true
	# Rampas e pórticos do Túnel do canal: nada de poste/banco na boca ou sobre a vala.
	if CANAL_TUNNEL.reserves(point, margin): return true
	for building in context.buildings:
		if (building.rect as Rect2).grow(margin).has_point(point): return true
	return false


static func _near_junction(context: Dictionary, point: Vector2, extra := 5.0) -> bool:
	for junction in context.junctions:
		var widest := 0.0
		for index in junction.roads: widest = maxf(widest, float(context.geometry._roads[int(index)].width))
		if point.distance_to(junction.position) < widest * 0.68 + extra: return true
	return false


static func _near_lamp(context: Dictionary, point: Vector2, radius := 1.6) -> bool:
	for lamp in context.lamps:
		if point.distance_to(lamp) < radius: return true
	return false


static func _roll(key: String) -> float:
	return float(key.hash() % 10007) / 10007.0


static func _add(batches: Dictionary, kind: String, point: Vector3, forward: Vector2, scale := 1.0) -> void:
	# A área inteira dos móveis precisa liberar a quadra e a ligação com a calçada.
	var skate_layout := preload("res://activities/skate/SkateParkLayout.gd")
	if kind in ["dumpster", "trash_bags", "hydrant", "trash_can", "news_box", "mailbox", "phone_booth", "bench_seat", "planter"] and skate_layout.reserved(Vector2(point.x, point.z), 1.5 * scale): return
	# forward: direção (x,z) para onde a frente (+Z local) do adereço aponta.
	var yaw := atan2(forward.x, forward.y)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	if not batches.has(kind): batches[kind] = []
	batches[kind].append(Transform3D(basis, point))


static func _flush(chunk: Node3D, batches: Dictionary) -> void:
	var cursor := _flush_begin(chunk, batches)
	while not _flush_step(cursor, 0): pass


static func _flush_begin(chunk: Node3D, batches: Dictionary) -> Dictionary:
	# Editor de mundo: cada posição do mobiliário é uma peça editável (sem custo se não há edição).
	PLACEMENTS.edit_batches(chunk.get_parent(), chunk, batches)
	# A ordem dos tipos é a do dicionário (inserção), igual ao laço antigo: os nós
	# CityLook_* entram no chunk na mesma ordem e _register_fragile vê o mesmo `built`.
	return {"chunk": chunk, "batches": batches, "kinds": batches.keys(), "index": 0, "built": {}}


## Um tipo de lote por item, até `budget_usec` (<= 0: sem limite, para build_chunk e
## testes). Devolve true quando montou tudo, inclusive colisões e quebráveis.
static func _flush_step(cursor: Dictionary, budget_usec: int) -> bool:
	var chunk: Node3D = cursor.chunk
	var batches: Dictionary = cursor.batches
	var kinds: Array = cursor.kinds
	var began := Time.get_ticks_usec()
	while int(cursor.index) < kinds.size():
		var kind: String = kinds[int(cursor.index)]
		cursor.index = int(cursor.index) + 1
		var span := STALL_WORK.begin()
		_flush_kind(chunk, kind, batches[kind], cursor.built)
		# Rótulo único (o resumo da sessão guarda no máximo 128 rótulos); o tipo vai no detalhe
		# só quando o item passou de 2 ms.
		if span != 0 and Time.get_ticks_usec() - span >= 2000:
			STALL_WORK.finish("stream.harbor.dressing_flush.kind", span, {"kind": kind, "count": (batches[kind] as Array).size()})
		else:
			STALL_WORK.finish_slow("stream.harbor.dressing_flush.kind", span, 2000, chunk)
		if budget_usec > 0 and Time.get_ticks_usec() - began >= budget_usec: return false
	var tail_span := STALL_WORK.begin()
	_flush_tail(chunk, batches, cursor.built)
	STALL_WORK.finish_slow("stream.harbor.dressing_flush.tail", tail_span, 2000, chunk)
	return true


static func _flush_kind(chunk: Node3D, kind: String, transforms: Array, built: Dictionary) -> void:
	if transforms.is_empty(): return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var material: Material
	var shadows := true
	if kind.begins_with("decal:"):
		var spec: Dictionary = _decal_spec(kind.trim_prefix("decal:"))
		multimesh.mesh = _flat_quad()
		material = spec.material
		shadows = false
	elif kind == "signal_amber":
		multimesh.use_colors = true
		multimesh.mesh = _lens_mesh()
		material = MATERIALS.signal_lens()
		shadows = false
	elif kind.begins_with("roofmat:"):
		multimesh.mesh = _flat_quad()
		material = ROOFS.material(kind.trim_prefix("roofmat:").to_int())
		shadows = false
	elif kind == "wall_ao":
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		multimesh.mesh = quad
		material = MATERIALS.wall_ao()
		shadows = false
	elif kind == "beacon_lens":
		multimesh.mesh = _lens_mesh()
		material = MATERIALS.beacon()
		shadows = false
	elif kind.begins_with("graffiti:"):
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		multimesh.mesh = quad
		material = LIFE.graffiti_material(kind.trim_prefix("graffiti:").to_int())
		shadows = false
	else:
		multimesh.mesh = KIT.mesh(kind)
		material = KIT.material_for(kind)
		# Preserve placement identities and trunk physics, including editor saves.
		if kind in ["street_tree","street_tree_b"]:
			for placement: Transform3D in transforms:
				if preload("res://world/places/ResidentialTreeVisual.gd").near_home(placement.origin):
					multimesh.mesh = preload("res://world/places/ResidentialTreeVisual.gd").mesh()
					material = null
					break
		# Peça de telhado pequena (antena, respiro, antena parabólica) segue sem
		# sombra: dobrava as primitivas na passada de sombra sem aparecer nesta câmera.
		shadows = kind in SHADOW_CASTERS
	# Cor e proporção por cópia (KIT.VARIATION); precisa de use_colors antes da contagem.
	var variation := KIT.variation_for(kind)
	if not variation.is_empty(): multimesh.use_colors = true
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		var placement: Transform3D = transforms[index]
		if not variation.is_empty():
			var varied: Array = KIT.vary(kind, placement)
			placement = varied[0]
			multimesh.set_instance_color(index, varied[1])
		multimesh.set_instance_transform(index, chunk.global_transform.affine_inverse() * placement)
	var instance := MultiMeshInstance3D.new()
	instance.name = "CityLook_" + kind.replace(":", "_")
	instance.multimesh = multimesh
	instance.material_override = material
	if not shadows: instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ROOF_SMALL_RANGE.has(kind):
		# Meia diagonal da AABB: sem ela a peça no canto do chunk sumiria a ~25 m.
		instance.visibility_range_end = float(ROOF_SMALL_RANGE[kind]) + multimesh.get_aabb().size.length() * 0.5
		# Margem só como histerese (sem fade), para não piscar na borda do corte.
		instance.visibility_range_end_margin = 4.0
		preload("res://runtime/GraphicsOptions.gd").tag_detail(instance)
	chunk.add_child(instance)
	built[kind] = multimesh
	if kind == "signal_amber":
		var lenses: Array = chunk.get_meta("signal_lenses", [])
		for index in mini(lenses.size(), multimesh.instance_count):
			JUNCTIONS.register_lens(multimesh, index, lenses[index][0], lenses[index][1])
		chunk.remove_meta("signal_lenses")


static func _flush_tail(chunk: Node3D, batches: Dictionary, built: Dictionary) -> void:
	# Os canteiros mantêm a malha em lote; um corpo estático composto por chunk
	# dá a área exata da pedra e é removido junto com o chunk em streaming.
	if batches.has("planter"):
		var body := StaticBody3D.new()
		body.name = "CityPlanterSolids"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.1, .5, 1.1)
		for placement: Transform3D in batches.planter:
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.transform = chunk.global_transform.affine_inverse() * placement * Transform3D(Basis.IDENTITY, Vector3(0, .25, 0))
			body.add_child(collision)
		chunk.add_child(body)
	FILL.add_trunk_collision(chunk, batches)
	_register_fragile(chunk, batches, built)


## Mobília e semáforo viram quebráveis (StreetPhysics). A lente do semáforo é
## outra MultiMesh; vai junto como peça irmã, com o mesmo índice de criação.
static func _register_fragile(chunk: Node3D, batches: Dictionary, built: Dictionary) -> void:
	# Tronco sólido de cada árvore (SidewalkFill.add_trunk_collision): um filho por árvore,
	# na ordem de FILL.TREE_KINDS e dos lotes. Playtest 29/10: sem passar esse colisor ao
	# registro, a árvore tombava mas o tronco invisível continuava de pé e o carro parava
	# nele como num muro ("algumas árvores não derrubam").
	var trunks := chunk.get_node_or_null("CityStreetTreeTrunks")
	var trunk_offset := {}
	var trunk_total := 0
	for tree_kind in FILL.TREE_KINDS:
		trunk_offset[tree_kind] = trunk_total
		trunk_total += (batches.get(tree_kind, []) as Array).size()
	for kind in FRAGILE_KINDS:
		if not built.has(kind): continue
		var multimesh: MultiMesh = built[kind]
		var visual: MultiMeshInstance3D
		for child in chunk.get_children():
			if child is MultiMeshInstance3D and child.multimesh == multimesh:
				visual = child
				break
		for index in multimesh.instance_count:
			var extra := []
			if kind == "signal_pole" and built.has("signal_amber") and index < built.signal_amber.instance_count:
				var pole := multimesh.get_instance_transform(index)
				var lens: Transform3D = built.signal_amber.get_instance_transform(index)
				extra.append({"multimesh": built.signal_amber, "index": index, "offset": pole.affine_inverse() * lens})
			var colliders: Array = []
			if kind == "planter": colliders.append(chunk.get_node("CityPlanterSolids").get_child(index))
			elif trunk_offset.has(kind) and trunks != null and trunks.get_child_count() == trunk_total:
				colliders.append(trunks.get_child(int(trunk_offset[kind]) + index))
			FRAGILE.register_instance("harbor_tree" if kind in ["street_tree","street_tree_b"] else kind, multimesh, index, chunk, extra, colliders, visual)


# ---------------------------------------------------------------------------
# 1. Noite: postes com cabeça emissiva + mancha de luz, janelas acesas.

## Noite e postes de calçada: corpo em CityNightLamps.gd (delegação de uma linha; mesmos nomes).
static func _night_pass(chunk: Node3D, context: Dictionary) -> void: NIGHT_LAMPS._night_pass(chunk, context)
static func _sidewalk_lamps(chunk: Node3D, context: Dictionary) -> void: NIGHT_LAMPS._sidewalk_lamps(chunk, context)
static func _lamp_mesh(part: String) -> ArrayMesh: return NIGHT_LAMPS._lamp_mesh(part)
static func _treat_window(mesh: MeshInstance3D) -> void: NIGHT_LAMPS._treat_window(mesh)


static func _flat_quad() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.orientation = PlaneMesh.FACE_Y
	return quad


static func _lens_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.2
	sphere.radial_segments = 10
	sphere.rings = 5
	return sphere


# ---------------------------------------------------------------------------
# 2. Cruzamentos: semáforo onde há faixa de pedestre, placa de PARE nos
# cruzamentos que a V1 deixou sem sinalização.
#
# O semáforo é de verdade: cada poste registra o cruzamento e a faixa de parada em
# TrafficJunctions, que alterna as fases e que o trânsito respeita. A lente mostra
# a cor da aproximação que ela encara (antes piscava amarelo porque o trânsito
# ignorava sinal).

static func _junction_signage(context: Dictionary, batches: Dictionary, chunk: Node3D) -> void:
	var geometry = context.geometry
	if geometry == null: return
	for junction in context.junctions:
		var center: Vector2 = junction.position
		if not _in_chunk(context, center): continue
		var arms: Array = geometry._crossing_arms(junction)
		if arms.size() < 3: continue
		var widest := 0.0
		for index in junction.roads: widest = maxf(widest, float(geometry._roads[int(index)].width))
		var setback := maxf(1.5, widest * 0.68 + 0.875 - 0.5) + 1.9
		var signalized: bool = not geometry._is_unsignalized(center)
		for arm in arms:
			var d: Vector2 = arm.direction
			var width: float = arm.width
			# Lado direito de quem chega ao cruzamento (mão inglesa não existe
			# em Harbor): mesma convenção de NativeTrafficRoutes._lane_offset.
			var right := Vector2(d.y, -d.x)
			var base := center + d * setback + right * (width * 0.5 + 0.9)
			if _road_clearance(context, base) < 0.2 or _inside_building(context, base): continue
			var point := Vector3(base.x, 0.02, base.y)
			if signalized:
				# Poste: local +X = right, +Z = d (placa e sinal voltados para
				# quem chega).
				var basis := Basis(Vector3(right.x, 0, right.y), Vector3.UP, Vector3(d.x, 0, d.y))
				if not batches.has("signal_pole"): batches["signal_pole"] = []
				batches["signal_pole"].append(Transform3D(basis, point))
				var lens := point + basis * Vector3(-3.3, 4.55, 0.2)
				if not batches.has("signal_amber"): batches["signal_amber"] = []
				batches["signal_amber"].append(Transform3D(Basis.IDENTITY, lens))
				var center3 := Vector3(center.x, 0.0, center.y)
				JUNCTIONS.register_signal(center3, setback - 1.2)
				var lenses: Array = chunk.get_meta("signal_lenses", [])
				lenses.append([center3, Vector3(-d.x, 0.0, -d.y)])
				chunk.set_meta("signal_lenses", lenses)
			else:
				_add(batches, "stop_sign", point, d)
				var placed: Array = batches["stop_sign"]
				placed[placed.size() - 1] = WEAR.lean(placed[placed.size() - 1], WEAR.district_at(context.roads, base), "stop|%d|%d" % [roundi(base.x * 10.0), roundi(base.y * 10.0)])


# ---------------------------------------------------------------------------
# Calçada: hidrante, lixeira, jornaleiro, caixa de correio, orelhão, banco.

const FURNITURE := TABLES.FURNITURE


static func _sidewalk_furniture(context: Dictionary, batches: Dictionary) -> void:
	for road in context.roads:
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
			var s := fposmod(-travelled, FURNITURE_SPACING)
			while s < length:
				for side in [-1.0, 1.0]:
					var key := "%s|%d|%d|%d" % [road.id, index, int(s * 10.0), int(side)]
					var jitter := (_roll(key + "j") - 0.5) * 2.4
					var along := a + tangent * clampf(s + jitter, 0.0, length)
					var outward: Vector2 = normal * side
					var point := along + outward * (width * 0.5 + 0.55)
					if not _in_chunk(context, point): continue
					var kind := _pick(FURNITURE, _roll(key))
					if kind.is_empty(): continue
					if _near_junction(context, point) or _near_lamp(context, point): continue
					if _road_clearance(context, point) < 0.25 or _inside_building(context, point, 0.6): continue
					if FILL.occupied_near(context, point, 1.0): continue
					# Orelhão e banco ficam mais para dentro, encostados no lado
					# do prédio, para não invadir o meio-fio.
					if kind in ["phone_booth", "bench_seat", "planter"]:
						point = along + outward * (width * 0.5 + SIDEWALK - 0.7)
						if _inside_building(context, point, 0.5) or FILL.occupied_near(context, point, 1.2): continue
					# As duas pistas divididas dividem um tabuleiro de ponte estrutural. As
					# "calçadas" internas são o canteiro central da pista, não lugar para mobiliário.
					if WORLD_CONNECTION.reserves_approach_for_driving(point): continue
					# O acesso de veículos autorado da oficina é dono deste pátio. Mantém
					# o mesmo mobiliário na calçada pública oposta da Quay.
					if _workshop_driving(point):
						point = Vector2(197.25,102.8+_roll(key+"workshop_edge")*6.0)
						if not _in_chunk(context,point) or _inside_building(context,point,.5): continue
					if point.distance_to(SEWER_ACCESS) < SEWER_CLEARANCE: continue
					_add(batches, kind, Vector3(point.x, 0.012, point.y), -outward)
				s += FURNITURE_SPACING
			travelled += length


static func _pick(table: Array, roll: float) -> String:
	var acc := 0.0
	for entry in table:
		acc += float(entry[1])
		if roll < acc: return entry[0]
	return ""


# ---------------------------------------------------------------------------
# 3. Entorno dos prédios: sombra de contato (AO falsa) e caçamba/lixo no
# beco lateral. A câmera olha para o norte, então só lateral e frente sul
# aparecem; caçamba no fundo ficaria escondida pelo próprio prédio.

static func _building_surroundings(context: Dictionary, batches: Dictionary) -> void:
	for entry in context.buildings:
		var footprint: Rect2 = entry.rect
		var data: Dictionary = entry.data
		var center := footprint.get_center()
		if not _in_chunk(context, center): continue
		# Sombra de contato em duas camadas: halo largo e suave + faixa estreita
		# e escura colada na parede (é ela que "assenta" o prédio no chão).
		var margin := 1.8
		var ao_size := footprint.size + Vector2.ONE * margin * 2.0
		var basis := Basis.IDENTITY.scaled(Vector3(ao_size.x, 1, ao_size.y))
		_push(batches, "decal:contact", Transform3D(basis, Vector3(center.x, DECAL_Y, center.y)))
		var tight := footprint.size + Vector2.ONE * 0.9
		_push(batches, "decal:contact_tight", Transform3D(Basis.IDENTITY.scaled(Vector3(tight.x, 1, tight.y)), Vector3(center.x, DECAL_Y + 0.001, center.y)))
		# Oclusão na base da fachada sul (a única que a câmera vê): gradiente
		# escuro de 1,3 m subindo do chão.
		var face := Vector3(center.x, 0.65, footprint.end.y + 0.018)
		_push(batches, "wall_ao", Transform3D(Basis.IDENTITY.scaled(Vector3(footprint.size.x + 0.04, 1.3, 1)), face))
		var id := str(data.get("id", ""))
		if str(data.get("kind", "")) in ["cobra_house"]: continue
		for side in [-1.0, 1.0]:
			var key := id + "|alley|" + str(side)
			if _roll(key) > 0.42: continue
			var z := center.y + (_roll(key + "z") - 0.6) * footprint.size.y * 0.6
			var point := Vector2(center.x + side * (footprint.size.x * 0.5 + 1.05), z)
			if _inside_building(context, point, 0.9) or _road_clearance(context, point) < SIDEWALK + 0.4: continue
			if _refuse_overlaps_transit(context,point): continue
			if point.distance_to(SEWER_ACCESS) < SEWER_CLEARANCE: continue
			if FILL.occupied_near(context, point, 1.2): continue
			_add(batches, "dumpster", Vector3(point.x, 0.012, point.y), Vector2(-side, 0), 1.0)
			var bags := point + Vector2(0, 1.5)
			if _roll(key + "bags") < 0.6 and bags.distance_to(SEWER_ACCESS) >= SEWER_CLEARANCE and not _inside_building(context, bags, 0.4) and not _refuse_overlaps_transit(context,bags):
				_add(batches, "trash_bags", Vector3(bags.x, 0.012, bags.y), Vector2(-side, 0.3))
			_push(batches, "decal:grime", Transform3D(Basis.IDENTITY.scaled(Vector3(3.2, 1, 3.6)), Vector3(point.x, DECAL_Y + 0.001, point.y + 0.4)))


static func _refuse_overlaps_transit(context: Dictionary, point: Vector2) -> bool:
	# Inclui o prop de lixo inteiro, não só o pivô; o tubo fica intacto.
	for rect: Rect2 in context.get("transit_reservations",[]):
		if rect.grow(1.1).has_point(point): return true
	return false


static func _push(batches: Dictionary, kind: String, transform: Transform3D) -> void:
	if not batches.has(kind): batches[kind] = []
	batches[kind].append(transform)


# ---------------------------------------------------------------------------
# 3. Desgaste do asfalto: manchas de óleo no meio da faixa, remendos, tampas
# de bueiro e bocas de lobo junto ao meio-fio.

## Desgaste antigo e decalques: corpo em CityRoadDecals.gd (delegação de uma linha; mesmos nomes).
static func _road_wear(context: Dictionary, batches: Dictionary) -> void: ROAD_DECALS._road_wear(context, batches)
static func _decal_spec(kind: String) -> Dictionary: return ROAD_DECALS._decal_spec(kind)


# ---------------------------------------------------------------------------
# 4. Telhados: variação de cor da laje, ar-condicionado, respiros, antenas,
# parabólicas, alçapões e outdoors virados para a câmera.

const ROOF_TINTS := TABLES.ROOF_TINTS
const ROOF_PROPS := TABLES.ROOF_PROPS


## Adereços que leem como saída do telhado (casinha da escada, alçapão): um por prédio.
const ROOF_EXITS := TABLES.ROOF_EXITS
## Laje abaixo disto é de prédio de um andar: sem casinha de escada no sorteio.
const SHED_MIN_ROOF_Y := ROOF_CIRCULATION.HATCH_MAX_ROOF_HEIGHT


## Telhados: corpo em CityRooftopDressing.gd (delegação de uma linha; mesmos nomes).
static func _rooftops(chunk: Node3D, _roof_context: Dictionary, batches: Dictionary) -> void: ROOFTOPS._rooftops(chunk, _roof_context, batches)
static func _rooftops_begin(chunk: Node3D) -> Dictionary: return ROOFTOPS._rooftops_begin(chunk)
static func _rooftops_step(cursor: Dictionary, batches: Dictionary, budget_usec: int) -> bool: return ROOFTOPS._rooftops_step(cursor, batches, budget_usec)
static func _roof_slabs(building: UrbanBuildingBase) -> Array: return ROOFTOPS._roof_slabs(building)
static func _roof_box(building: UrbanBuildingBase) -> AABB: return ROOFTOPS._roof_box(building)
static func _roof_obstacles(building: UrbanBuildingBase, roof_y: float) -> Array: return ROOFTOPS._roof_obstacles(building, roof_y)
static func _other_roofs(chunk: Node3D, _batches: Dictionary) -> void: ROOFTOPS._other_roofs(chunk, _batches)



## Paredes grandes de cor chapada (lojas, galpões, delegacia, Cobra...) ganham
## a mesma textura de alvenaria/reboco/concreto dos brownstones. Só troca
## material_override de caixa grande sem textura e sem emissão: vidro, letreiro,
## toldo e acabamento pequeno ficam como estão.
static func _texture_walls(chunk: Node3D) -> void:
	preload("res://world/city_look/HarborFacadeTones.gd").apply(chunk)


## Piso das quadras virado para cima: corpo em CityGroundFaceUp.gd (delegação de uma linha).
static func _face_ground_up(chunk: Node3D) -> void: GROUND_FACE_UP._face_ground_up(chunk)
static func _face_ground_up_step(state: Dictionary) -> bool: return GROUND_FACE_UP._face_ground_up_step(state)
