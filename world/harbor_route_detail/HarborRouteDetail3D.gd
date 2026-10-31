extends Node3D
class_name HarborRouteDetail3D

## Componente visual e físico de paisagem de rua para a rota principal do Harbor:
## Rodoviária (Coach Terminal) → Delegacia (Police Precinct) → Garagem do Maciota.
##
## Arquitetura modular por zona:
## - ZONE_RODOVIARIA: bancos de trânsito, canteiros e bicicletário no calçamento do distrito.
## - ZONE_CONNECTING_STREETS: marcações de pedestre, iluminação municipal e hidrantes.
## - ZONE_DELEGACIA: frades de segurança anti-impacto e luminárias cívicas de globo num pátio rente.
## - ZONE_MACIOTA: mobiliário de frente da oficina no chão nativo compartilhado.
## As coordenadas legadas de laje/meio-fio/rampa abaixo ficam como âncoras vazias do editor;
## as dimensões antigas explicam os slots originais, não a geometria elevada atual.
##
## RESTRIÇÕES E GARANTIAS DE ARQUITETURA:
## - Ciclo de vida independente por zona: mount_zone(), unmount_zone(), has_zone(), get_zone().
## - Zero duplicação de prédios, fachadas, NPCs ou veículos.
## - Zero texto descritivo/decorativo (AGENTS.md).
## - Flush level crossing at Rodoviária disembark corridor (Y ≈ 0.01m), matching Arrival.gd and HarborTerminalModel3D.
## - Exterior support belongs to NativeRegion; route furniture adds no second paving layer.

const ZONE_RODOVIARIA := "rodoviaria"
const ZONE_CONNECTING_STREETS := "connecting_streets"
const ZONE_DELEGACIA := "delegacia"
const ZONE_MACIOTA := "maciota"
const PLACE_CATALOG := preload("res://world/places/PlaceCatalog.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

const ALL_ZONES := [
	ZONE_RODOVIARIA,
	ZONE_CONNECTING_STREETS,
	ZONE_DELEGACIA,
	ZONE_MACIOTA
]

# Dictionary tracking mounted zone instances: zone_id -> Node3D
var _mounted_zones: Dictionary = {}

## Se verdadeiro e nenhuma zona tiver sido montada antes de entrar na árvore,
## monta todas as zonas no _ready(). O padrão é falso para que montar uma zona só
## ou usar streaming de chunks nunca dispare mount_all() sem querer.
@export var auto_mount_all: bool = false

func _ready() -> void:
	if auto_mount_all and _mounted_zones.is_empty():
		mount_all()

# ==============================================================================
# Zone Lifecycle API (Public)
# ==============================================================================

## Monta e devolve um Node3D sem pai contendo todos os props e a geometria de uma zona específica.
## O nó devolvido não está anexado a nenhum pai.
static func build_zone(zone_id: String) -> Node3D:
	var zone_node: Node3D = null
	match zone_id:
		ZONE_RODOVIARIA:
			zone_node = _build_rodoviaria_zone()
		ZONE_CONNECTING_STREETS:
			zone_node = _build_connecting_streets()
		ZONE_DELEGACIA:
			zone_node = _build_delegacia_zone()
		ZONE_MACIOTA:
			zone_node = _build_maciota_zone()
		_:
			push_warning("HarborRouteDetail3D: Unknown zone_id '%s'." % zone_id)
			return null
	if zone_node != null:
		zone_node.name = "Zone_" + zone_id
	return zone_node

## O streaming monta a mesma zona em partes, fora da árvore. A ordem dos
## filhos é a ordem original dos IDs piece/route, inclusive âncoras sem malha.
## Não há estado global: cancelar o job libera somente a zona deste pedido.
static func begin_zone(zone_id: String) -> Dictionary:
	var count := {ZONE_RODOVIARIA: 18, ZONE_CONNECTING_STREETS: 12, ZONE_DELEGACIA: 18, ZONE_MACIOTA: 7}
	if not count.has(zone_id): return {}
	var root := Node3D.new()
	root.name = "Zone_" + zone_id
	return {"zone_id": zone_id, "root": root, "index": 0, "count": count[zone_id], "complete": false}

static func step_zone(job: Dictionary, budget_usec: float = 1500.0) -> bool:
	if job.is_empty() or bool(job.get("complete", false)): return true
	var root := job.get("root") as Node3D
	if not is_instance_valid(root):
		job.complete = true
		return true
	var began := Time.get_ticks_usec()
	while int(job.index) < int(job.count):
		var piece_began := STALL_WORK.begin()
		var fragment: Node3D
		match str(job.zone_id):
			ZONE_RODOVIARIA: fragment = _build_rodoviaria_zone(int(job.index))
			ZONE_CONNECTING_STREETS: fragment = _build_connecting_streets(int(job.index))
			ZONE_DELEGACIA: fragment = _build_delegacia_zone(int(job.index))
			ZONE_MACIOTA: fragment = _build_maciota_zone(int(job.index))
		if fragment == null:
			cancel_zone(job)
			return true
		root.transform = fragment.transform
		for child in fragment.get_children():
			fragment.remove_child(child)
			root.add_child(child)
		fragment.free()
		STALL_WORK.finish_slow("harbor_route_zone.%s.piece.%d" % [str(job.zone_id), int(job.index)], piece_began, 2000)
		job.index = int(job.index) + 1
		# Um móvel ainda é indivisível; a próxima peça só começa se houver orçamento.
		if Time.get_ticks_usec() - began >= budget_usec: break
	job.complete = int(job.index) >= int(job.count)
	return bool(job.complete)

static func cancel_zone(job: Dictionary) -> void:
	var root := job.get("root") as Node3D
	if is_instance_valid(root) and root.get_parent() == null: root.free()
	job.clear()


## Pavimento aposentado mantém o slot de filho para que edições salvas em piece/route/<zone>/<index>
## ainda apontem para o mesmo mobiliário. Nenhuma malha ou colisor é alocado:
## o calçamento do distrito e o gerador de ruas são donos do piso contínuo e rente.
static func _ground_anchor(label: String) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = label
	anchor.set_meta("district_ground_owned",true)
	return anchor

## Monta uma zona específica por ID como filha desta instância de HarborRouteDetail3D.
## Devolve o Node3D da zona montada, ou o existente se já estiver montada.
func mount_zone(zone_id: String) -> Node3D:
	if _mounted_zones.has(zone_id) and is_instance_valid(_mounted_zones[zone_id]):
		return _mounted_zones[zone_id]
	
	var zone_node := build_zone(zone_id)
	if zone_node != null:
		add_child(zone_node)
		_mounted_zones[zone_id] = zone_node
	
	return zone_node

## Desmonta e libera uma zona específica por ID desta instância de HarborRouteDetail3D.
func unmount_zone(zone_id: String) -> void:
	if not _mounted_zones.has(zone_id):
		return
	var node: Node3D = _mounted_zones[zone_id]
	_mounted_zones.erase(zone_id)
	if is_instance_valid(node):
		node.queue_free()

## Devolve verdadeiro se a zona indicada estiver montada nesta instância.
func has_zone(zone_id: String) -> bool:
	return _mounted_zones.has(zone_id) and is_instance_valid(_mounted_zones[zone_id])

## Devolve o Node3D raiz da zona montada, ou null se não estiver montada.
func get_zone(zone_id: String) -> Node3D:
	if has_zone(zone_id):
		return _mounted_zones[zone_id]
	return null

## Monta todas as zonas nesta instância de HarborRouteDetail3D.
func mount_all() -> void:
	for zone_id in ALL_ZONES:
		mount_zone(zone_id)

## Desmonta e libera todas as zonas montadas desta instância de HarborRouteDetail3D.
func unmount_all() -> void:
	for zone_id in ALL_ZONES:
		unmount_zone(zone_id)

## Devolve o AABB espacial aproximado de uma zona em coordenadas globais.
static func get_zone_bounds(zone_id: String) -> AABB:
	match zone_id:
		ZONE_RODOVIARIA:
			return AABB(Vector3(92.0, 0.0, 68.0), Vector3(31.0, 5.5, 7.5))
		ZONE_CONNECTING_STREETS:
			return AABB(Vector3(81.0, 0.0, 72.0), Vector3(8.0, 5.5, 57.0))
		ZONE_DELEGACIA:
			return AABB(Vector3(58.0, 0.0, 129.0), Vector3(20.0, 5.0, 9.0))
		ZONE_MACIOTA:
			return AABB(Vector3(152.6, 0.0, 97.1), Vector3(25.6, 5.4, 15.1))
	return AABB()

## Returns designated physical transition anchors for gameplay navigation.
static func get_transition_point(point_id: String) -> Vector3:
	match point_id:
		"rodoviaria_bus_crossing":
			return Vector3(107.0, 0.05, 74.55)
		"rodoviaria_arrival_anchor":
			return Vector3(106.25, 0.06, 70.625)
		"market_union_crossing":
			return Vector3(82.5, 0.005, 78.125)
		"delegacia_curb_ramp":
			return Vector3(67.5, 0.05, 134.3)
		"delegacia_approach":
			return Vector3(67.5, 0.10, 132.5)
		"maciota_driveway_ramp":
			return Vector3(164.275, 0.04, 109.625)
		"maciota_bay_entry":
			return Vector3(166.0, 0.08, 109.8)
	return Vector3.ZERO

# ==============================================================================
# Zone 1: Rodoviária (Coach Terminal Plaza & Passenger Corridor)
# ==============================================================================

static func _build_rodoviaria_zone(selected_piece := -1) -> Node3D:
	var zone := Node3D.new()
	
	# O passeio da calçada é dividido em Ala Oeste (X: 92.0 a 103.5) e Ala Leste (X: 110.5 a 122.0).
	# O corredor central de trânsito (X: 103.5 a 110.5, vão de 7.0m) é uma travessia de pedestres rente
	# no nível Y = 0.05m, batendo com a superfície da pista da Market Street e a trajetória de desembarque do Arrival.gd!
	
	# 1. West Wing Slab (11.5m x 4.2m at Y = 0.12m)
	if selected_piece < 0 or selected_piece == 0:
		var slab_w := _ground_anchor("SidewalkSlab")
		slab_w.position = Vector3(97.75, 0.0, 72.4)
		zone.add_child(slab_w)
	
	# West Curb along Market St edge (Z = 74.55)
	if selected_piece < 0 or selected_piece == 1:
		var curb_w := _ground_anchor("CurbSegment")
		curb_w.rotation_degrees = Vector3(0, 90, 0)
		curb_w.position = Vector3(97.75, 0.0, 74.55)
		zone.add_child(curb_w)
	
	# Preserva a faixa de saída intermunicipal centrada em X=121.875. A antiga ala,
	# o bicicletário e o poste ocupavam a carcaça varrida do ônibus e bloqueavam a rota da V1.
	if selected_piece < 0 or selected_piece == 2:
		var slab_e := _ground_anchor("SidewalkSlab")
		slab_e.position = Vector3(114.75, 0.0, 72.4)
		zone.add_child(slab_e)
	
	# East Curb along Market St edge (Z = 74.55)
	if selected_piece < 0 or selected_piece == 3:
		var curb_e := _ground_anchor("CurbSegment")
		curb_e.rotation_degrees = Vector3(0, 90, 0)
		curb_e.position = Vector3(114.75, 0.0, 74.55)
		zone.add_child(curb_e)
	
	# 3. Travessia rente central de desembarque de passageiros (X: 103.5 a 110.5, Z: 70.3 a 75.0)
	# Calçamento nivelado (altura = 0.05m, topo em Y = 0.05m) batendo exatamente com a caixa da pista da Market St.
	# O Dante anda da porta do ônibus (X ≈ 108.56, Z ≈ 76.31) até ARRIVAL (X = 106.25, Z = 70.625)
	# com folga > 1.29m até side_ramp_e e zero degraus verticais ou pedras de meio-fio.
	if selected_piece < 0 or selected_piece == 4:
		var level_crossing := _ground_anchor("SidewalkSlab")
		level_crossing.position = Vector3(107.0, 0.0, 72.65)
		zone.add_child(level_crossing)
	
	# Linha tátil amarela de borda marcando o limite de pedestres em Z = 74.55
	if selected_piece < 0 or selected_piece == 5:
		var edge_marker := MeshInstance3D.new()
		edge_marker.name = "BusBayEdgeMarker"
		var em_box := PlaneMesh.new()
		em_box.size = Vector2(7.0, 0.30)
		edge_marker.mesh = em_box
		edge_marker.material_override = HarborRouteMaterials.curb_yellow_marking()
		edge_marker.position = Vector3(107.0, 0.010, 74.55)
		edge_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		zone.add_child(edge_marker)
	
	# Side curb ramps transitioning elevated wings down into central corridor
	if selected_piece < 0 or selected_piece == 6:
		var side_ramp_w := _ground_anchor("CurbRamp")
		side_ramp_w.rotation_degrees = Vector3(0, 90, 0)
		side_ramp_w.position = Vector3(103.5, 0.0, 72.4)
		zone.add_child(side_ramp_w)

	if selected_piece < 0 or selected_piece == 7:
		var side_ramp_e := _ground_anchor("CurbRamp")
		side_ramp_e.rotation_degrees = Vector3(0, -90, 0)
		side_ramp_e.position = Vector3(110.5, 0.0, 72.4)
		zone.add_child(side_ramp_e)
	
	# 4. Comodidades postas só nas alas laterais:
	# Comodidades da Ala Oeste (X ≤ 101.5):
	if selected_piece < 0 or selected_piece == 8:
		var bench_w := HarborRouteProps.create_bench(2.2)
		bench_w.position = Vector3(98.5, 0.008, 71.0)
		zone.add_child(bench_w)

	if selected_piece < 0 or selected_piece == 9:
		var bin_w := HarborRouteProps.create_trash_bin()
		bin_w.position = Vector3(95.0, 0.008, 71.2)
		zone.add_child(bin_w)

	if selected_piece < 0 or selected_piece == 10:
		var light_w := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(90.0))
		light_w.position = Vector3(93.5, 0.008, 73.8)
		zone.add_child(light_w)

	if selected_piece < 0 or selected_piece == 11:
		var planter_w := HarborRouteProps.create_planter_box(Vector3(1.8, 0.45, 0.85))
		planter_w.position = Vector3(101.5, 0.008, 73.4)
		zone.add_child(planter_w)
	
	# East Wing Amenities (X ≥ 113.0):
	if selected_piece < 0 or selected_piece == 12:
		var planter_e := HarborRouteProps.create_planter_box(Vector3(1.8, 0.45, 0.85))
		planter_e.position = Vector3(112.8, 0.008, 73.4)
		zone.add_child(planter_e)

	if selected_piece < 0 or selected_piece == 13:
		var bench_e := HarborRouteProps.create_bench(2.2)
		bench_e.position = Vector3(115.5, 0.008, 71.0)
		zone.add_child(bench_e)

	if selected_piece < 0 or selected_piece == 14:
		var bin_e := HarborRouteProps.create_trash_bin()
		bin_e.position = Vector3(118.0, 0.008, 71.2)
		zone.add_child(bin_e)

	if selected_piece < 0 or selected_piece == 15:
		var light_e := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(90.0))
		light_e.position = Vector3(118.5, 0.008, 73.8)
		zone.add_child(light_e)

	if selected_piece < 0 or selected_piece == 16:
		var bike_rack := HarborRouteProps.create_bike_rack(4, 0.85)
		bike_rack.position = Vector3(115.5, 0.008, 73.8)
		zone.add_child(bike_rack)
	
	# Storm drain grate in street gutter outside west wing
	if selected_piece < 0 or selected_piece == 17:
		var drain := HarborRouteProps.create_drain_grate()
		drain.position = Vector3(101.5, 0.0, 74.85)
		zone.add_child(drain)
	
	return zone

# ==============================================================================
# Zone 2: Connecting Streets (Market Street & Union Avenue Corridors)
# ==============================================================================

static func _build_connecting_streets(selected_piece := -1) -> Node3D:
	var zone := Node3D.new()
	
	# 1. Calçada norte da Market St rumo à Union Ave (X: 85.6 a 92.0, Z: 72.5 a 74.5)
	# Começa em 85.6, alinhada à calçada leste da Union Ave: a Union Ave ocupa X 77.2–85.3
	# e a versão anterior (X 83.0) avançava 2.3 m sobre a pista, bloqueando carros no cruzamento.
	if selected_piece < 0 or selected_piece == 0:
		var slab_market := _ground_anchor("SidewalkSlab")
		slab_market.position = Vector3(88.8, 0.0, 73.5)
		zone.add_child(slab_market)
	
	# Meio-fio na borda da Market St, aparado para começar depois da rampa de pedestres em X = 87.8 (X: 87.8 a 92.0, vão de 4.2m)
	# Elimina a sobreposição de colisores entre o meio-fio vertical e a cunha chanfrada da rampa (X: 85.6 a 87.8)
	if selected_piece < 0 or selected_piece == 1:
		var curb_market := _ground_anchor("CurbSegment")
		curb_market.rotation_degrees = Vector3(0, 90, 0)
		curb_market.position = Vector3(89.9, 0.0, 74.55)
		zone.add_child(curb_market)
	
	# Rampa de rebaixo de meio-fio na esquina do cruzamento Market/Union (X: 85.6 a 87.8, vão de 2.2m)
	if selected_piece < 0 or selected_piece == 2:
		var ramp_market := _ground_anchor("CurbRamp")
		ramp_market.position = Vector3(86.7, 0.0, 74.55)
		zone.add_child(ramp_market)
	
	# 2. Pedestrian crosswalk across Market St at Union Ave corner
	if selected_piece < 0 or selected_piece == 3:
		var crosswalk_market := HarborRouteProps.create_crosswalk_stripes(3.5, 7.5, 6)
		crosswalk_market.position = Vector3(82.5, 0.0, 78.125)
		zone.add_child(crosswalk_market)
	
	# 3. Calçada leste ao longo da Union Avenue (corre de norte a sul de Z: 82.0 a 128.0 em X: 86.8)
	if selected_piece < 0 or selected_piece == 4:
		var slab_union_n := _ground_anchor("SidewalkSlab")
		slab_union_n.position = Vector3(86.8, 0.0, 94.0)
		zone.add_child(slab_union_n)
	
	# Medical Garden Lane crosses here (Z 119.875–125.125). The former
	# continuous slab and curb cut across both lanes beside Harbor Patrol.
	if selected_piece < 0 or selected_piece == 5:
		for span in [Vector2(105.0,119.4), Vector2(125.6,127.0)]:
			var slab := _ground_anchor("SidewalkSlab")
			slab.position = Vector3(86.8, 0.0, (span.x+span.y)*.5)
			zone.add_child(slab)
			var curb := _ground_anchor("CurbSegment")
			curb.position = Vector3(85.5, 0.0, (span.x+span.y)*.5)
			zone.add_child(curb)

		# Meios-fios virados para a pista da Union Ave (em X = 85.5)
	if selected_piece < 0 or selected_piece == 6:
		var curb_union_n := _ground_anchor("CurbSegment")
		curb_union_n.position = Vector3(85.5, 0.0, 94.0)
		zone.add_child(curb_union_n)
	
	# Streetlights spaced every ~20m along Union Avenue
	if selected_piece < 0 or selected_piece == 7:
		var light_u1 := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(-90.0))
		light_u1.position = Vector3(87.5, 0.008, 94.0)
		zone.add_child(light_u1)
	
	if selected_piece < 0 or selected_piece == 8:
		var light_u2 := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(-90.0))
		light_u2.position = Vector3(87.5, 0.008, 115.0)
		zone.add_child(light_u2)
	
	# Municipal fire hydrant near the midway junction
	if selected_piece < 0 or selected_piece == 9:
		var hydrant_mid := HarborRouteProps.create_fire_hydrant()
		hydrant_mid.position = Vector3(87.4, 0.008, 102.5)
		zone.add_child(hydrant_mid)
	
	# Storm drains along curb
	if selected_piece < 0 or selected_piece == 10:
		var drain_u1 := HarborRouteProps.create_drain_grate(Vector2(0.45, 0.85))
		drain_u1.position = Vector3(85.2, 0.0, 92.0)
		zone.add_child(drain_u1)
	
	if selected_piece < 0 or selected_piece == 11:
		var drain_u2 := HarborRouteProps.create_drain_grate(Vector2(0.45, 0.85))
		drain_u2.position = Vector3(85.2, 0.0, 118.0)
		zone.add_child(drain_u2)
	
	return zone

# ==============================================================================
# Zone 3: Delegacia (Harbor Patrol Precinct Forecourt)
# ==============================================================================

static func _build_delegacia_zone(selected_piece := -1) -> Node3D:
	var zone := Node3D.new()
	
	# A Dock Street agora tem 14 m de largura: a borda norte do asfalto é Z = 130.5.
	# Mantém toda parte elevada atrás dessa borda; a abertura do esgoto continua na rua.
	# Quatro painéis de calçamento preservam os IDs de filho existentes do editor (faixa de pedestres = 17).
	var paving := [
		Rect2(56.0, 125.0, 10.0, 2.35),
		Rect2(56.0, 127.35, 10.0, 2.35),
		Rect2(66.0, 125.0, 10.0, 2.35),
		Rect2(66.0, 127.35, 10.0, 2.35)
	]
	for index in range(paving.size()):
		if selected_piece >= 0 and selected_piece != index: continue
		var piece: Rect2 = paving[index]
		if not piece.has_area(): continue
		var slab := _ground_anchor("SidewalkSlab")
		slab.position = Vector3(piece.get_center().x, 0.0, piece.get_center().y)
		zone.add_child(slab)

	# Os meios-fios ladeiam o acesso central acessível, inteiramente na calçada.
	if selected_piece < 0 or selected_piece == 4:
		var curb_w := _ground_anchor("CurbSegment")
		curb_w.rotation_degrees = Vector3(0, 90, 0)
		curb_w.position = Vector3(59.5, 0.0, 129.85)
		zone.add_child(curb_w)

	if selected_piece < 0 or selected_piece == 5:
		var curb_e := _ground_anchor("CurbSegment")
		curb_e.rotation_degrees = Vector3(0, 90, 0)
		curb_e.position = Vector3(72.5, 0.0, 129.85)
		zone.add_child(curb_e)
	
	# Antigo slot da rampa de seis metros: acesso e pátio agora são rentes.
	if selected_piece < 0 or selected_piece == 6:
		var p_ramp := _ground_anchor("CurbRamp")
		p_ramp.position = Vector3(66.0, 0.0, 130.1)
		zone.add_child(p_ramp)
	
	# Institutional Police streetlights (Twin globe civic lamps with navy blue base)
	if selected_piece < 0 or selected_piece == 7:
		var p_light_w := HarborRouteProps.create_streetlight(4.8, 1.2, "police", 0.0)
		p_light_w.position = Vector3(57.0, 0.008, 128.8)
		zone.add_child(p_light_w)
	
	if selected_piece < 0 or selected_piece == 8:
		var p_light_e := HarborRouteProps.create_streetlight(4.8, 1.2, "police", 0.0)
		p_light_e.position = Vector3(75.0, 0.008, 128.8)
		zone.add_child(p_light_e)
	
	# Frades de segurança anti-impacto com acabamento azul-marinho da polícia e faixas refletivas
	# Ladeiam a entrada, mantendo desobstruída a rampa central de seis metros.
	var bollard_xs := [57.5, 59.0, 60.5, 71.5, 74.5]
	for index in range(bollard_xs.size()):
		if selected_piece >= 0 and selected_piece != 9 + index: continue
		var bollard := HarborRouteProps.create_bollard("police")
		bollard.position = Vector3(bollard_xs[index], 0.008, 129.1)
		zone.add_child(bollard)

	# Banco cívico público no lado oeste tranquilo do pátio
	if selected_piece < 0 or selected_piece == 14:
		var bench := HarborRouteProps.create_bench(2.0)
		bench.position = Vector3(58.0, 0.008, 126.8)
		bench.rotation_degrees = Vector3(0, 90, 0)
		zone.add_child(bench)
	
	# Litter bin near east corner
	if selected_piece < 0 or selected_piece == 15:
		var bin := HarborRouteProps.create_trash_bin()
		bin.position = Vector3(74.0, 0.008, 127.5)
		zone.add_child(bin)
	
	# Mantém o bueiro ao lado do pátio livre para a tampa e o acesso pela escada.
	
	# Grade de boca de lobo na sarjeta ao lado da ala oeste do meio-fio (longe da rampa de pedestres)
	if selected_piece < 0 or selected_piece == 16:
		var drain := HarborRouteProps.create_drain_grate()
		drain.position = Vector3(62.0, 0.0, 130.35)
		zone.add_child(drain)
	
	# Crosswalk across Dock Street connecting to harbor quays
	if selected_piece < 0 or selected_piece == 17:
		var crosswalk_dock := HarborRouteProps.create_crosswalk_stripes(3.6, 7.5, 6)
		crosswalk_dock.position = Vector3(67.5, 0.0, 137.5)
		zone.add_child(crosswalk_dock)
	
	return zone

# ==============================================================================
# Zone 4: Garagem do Maciota (Westgate Motor Co. Frontage & Apron)
# ==============================================================================

static func _build_maciota_zone(selected_piece := -1) -> Node3D:
	var zone := Node3D.new()
	# Existing apron props follow the workshop's new industrial anchor.
	zone.position = Vector3(2696.0/16-790.0/16,0,1624.0/16-1495.0/16)
	
	# Frente de calçada passando diante da oficina (X: 39.5 a 57.0, Z: 101.25 a 104.6).
	# Sem malha de laje separada aqui: qualquer caixa elevada ou de cor diferente parece uma segunda
	# calçada empilhada sobre o calçamento plano do próprio distrito embaixo, por mais fina
	# ou mais parecida que seja a cor. O calçamento plano do HarborUrbanSurface3D (já
	# exposto aqui, veja HarborUrbanSurface3D._RAISED_APRON_HOLES) é a calçada; esta zona
	# só acrescenta meio-fio/rampa/props por cima.

	# A frente do pátio de cargas tem calçamento nativo contínuo no nível da rua.
	# A antiga cunha de 3 cm ligava um pátio elevado na garagem anterior; aqui ela
	# não ligava nenhuma mudança de altura e o lado vertical obstruía veículos
	# sentido oeste. O piso nativo continua sendo o acesso apoiado de largura total.

	# Meio-fio de granito no flanco leste da calçada de pedestres (X: 50.8 a 57.0)
	if selected_piece < 0 or selected_piece == 0:
		var curb_e := _ground_anchor("CurbSegment")
		curb_e.rotation_degrees = Vector3(0, 90, 0)
		curb_e.position = Vector3(55.375, 0.0, 91.9375)
		zone.add_child(curb_e)

	# Frade amarelo de segurança de alta visibilidade na esquina leste do meio-fio (X = 51.2, longe da baia de veículos)
	# Nota: o frade oeste em X = 42.5 foi removido para liberar a parada de chegada do carro do passeio do Arrival.gd em (42.5, 0, 104.55).
	if selected_piece < 0 or selected_piece == 1:
		var bollard_e := HarborRouteProps.create_bollard("hazard")
		bollard_e.position = Vector3(54.575, 0.03, 91.7375)
		zone.add_child(bollard_e)

	# A esquina de serviço ilumina a quadra pelo leste. O poste fica fora
	# da carcaça de manobra inteira e do sensor de obstáculo dianteiro do carro.
	if selected_piece < 0 or selected_piece == 2:
		var ind_light := HarborRouteProps.create_streetlight(5.2, 1.1, "industrial", deg_to_rad(45.0))
		ind_light.position = Vector3(55.675, 0.03, 90.9375)
		zone.add_child(ind_light)

	# Hidrante na esquina mais a leste da calçada (X = 56.2)
	if selected_piece < 0 or selected_piece == 3:
		var hydrant := HarborRouteProps.create_fire_hydrant()
		hydrant.position = Vector3(55.675, 0.03, 93.0375)
		zone.add_child(hydrant)

	# Caçamba pesada de sucata / tambores de óleo no pátio leste
	if selected_piece < 0 or selected_piece == 4:
		var drum := MeshInstance3D.new()
		drum.name = "ScrapOilDrum"
		var d_cyl := CylinderMesh.new()
		d_cyl.top_radius = 0.32
		d_cyl.bottom_radius = 0.32
		d_cyl.height = 0.85
		drum.mesh = d_cyl
		drum.material_override = HarborRouteMaterials.cast_iron_dark()
		drum.position = Vector3(54.875, 0.03 + 0.425, 92.7375)
		zone.add_child(drum)

	if selected_piece < 0 or selected_piece == 5:
		var drum_body := StaticBody3D.new()
		drum_body.name = "DrumCollision"
		drum_body.collision_layer = 1
		drum_body.collision_mask = 0
		var d_col := CollisionShape3D.new()
		var d_shape := CylinderShape3D.new()
		d_shape.radius = 0.35
		d_shape.height = 0.85
		d_col.shape = d_shape
		d_col.position = Vector3(54.875, 0.03 + 0.425, 92.7375)
		drum_body.add_child(d_col)
		zone.add_child(drum_body)
	
	# Grade de boca de lobo na sarjeta em frente à entrada de garagem
	if selected_piece < 0 or selected_piece == 6:
		var drain := HarborRouteProps.create_drain_grate()
		drain.position = Vector3(55.375, 0.0, 102.6875)
		zone.add_child(drain)
	
	return zone
