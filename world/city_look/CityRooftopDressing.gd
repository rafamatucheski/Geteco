extends RefCounted
## Passo 12 (telhados: acabamento da laje, adereços, saída do telhado, outdoor, vida da fachada)
## separado do CityChunkDressing em 01/11 (Onda 1). Mesma ordem de itens e de sorteios, mesmos
## spans stream.harbor.rooftops.*.
## Tudo estático, como o dono. `g` é o script do CityChunkDressing (preload cíclico, o mesmo que
## SidewalkFill/StreetJunk já fazem): o que continua no dono (_roll, _pick, _add, _push, _in_chunk,
## _context, constantes de calçada e de poste, _lamp_meshes) é lido por `g.`; o dono mantém cada
## função antiga como delegação de uma linha com a mesma assinatura, então testes e
## SidewalkFill/StreetJunk/HarborUtilityLines que chamam pelo dono não mudam.

const g := preload("res://world/city_look/CityChunkDressing.gd")
const BRANDS := preload("res://world/city_look/CityBrands.gd")
const LIFE := preload("res://world/city_look/BuildingLife.gd")
const POLICE := preload("res://world/city_look/PoliceStationDressing.gd")
const ROOFS := preload("res://world/city_look/RoofSurfaces.gd")
const ROOF_CIRCULATION := preload("res://world/places/harbor_buildings/HarborRoofCirculation.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const TABLES := preload("res://data/catalogs/CityDressingTables.gd")
const ROOF_PROPS := TABLES.ROOF_PROPS
const ROOF_EXITS := TABLES.ROOF_EXITS

static func _rooftops(chunk: Node3D, _roof_context: Dictionary, batches: Dictionary) -> void:
	var cursor := _rooftops_begin(chunk)
	while not _rooftops_step(cursor, batches, 0): pass


## Passo 12 retomável. No playtest de 30/10 (export release, 110-120 km/h no Harbor)
## `stream.harbor.dressing_step.12` custou 35, 44 e 53 ms num quadro só: o passo varria
## todos os telhados do chunk de uma vez, e cada prédio pede vários find_children
## (acabamento, lajes, obstáculos por laje, fachada) mais os nós de BuildingLife. Agora o
## cursor anda em itens pequenos — um telhado avulso, a leitura das lajes de um prédio,
## uma laje com seus adereços, a vida da fachada — e devolve o controle ao passar do
## orçamento. A ordem dos itens é a do laço antigo, então os lotes recebem as mesmas
## transformações na mesma ordem (mesmas malhas, materiais e MultiMesh no fim).
static func _rooftops_begin(chunk: Node3D) -> Dictionary:
	return {"chunk": chunk, "phase": 0, "others": chunk.get_children(), "index": 0, "buildings": [], "billboards": 0, "item": {}}


## Devolve true quando terminou. budget_usec <= 0: sem limite (build_chunk síncrono e testes).
static func _rooftops_step(cursor: Dictionary, batches: Dictionary, budget_usec: int) -> bool:
	var chunk: Node3D = cursor.chunk
	var began := Time.get_ticks_usec()
	# Pelo menos um item por chamada (began acabou de ser lido), então sempre avança.
	while budget_usec <= 0 or Time.get_ticks_usec() - began < budget_usec:
		if int(cursor.phase) == 0:
			var others: Array = cursor.others
			if int(cursor.index) >= others.size():
				# Mesma lista do laço antigo: tirada depois dos telhados avulsos.
				var span := STALL_WORK.begin()
				cursor.buildings = _rooftop_buildings(chunk)
				STALL_WORK.finish_slow("stream.harbor.rooftops.collect", span, 2000, chunk)
				cursor.index = 0
				cursor.phase = 1
			else:
				var child: Variant = others[int(cursor.index)]
				cursor.index = int(cursor.index) + 1
				if is_instance_valid(child) and (child as Node).get_parent() == chunk:
					var span := STALL_WORK.begin()
					_other_roof(child)
					STALL_WORK.finish_slow("stream.harbor.rooftops.other_roof", span, 2000, child)
		elif (cursor.item as Dictionary).is_empty():
			var buildings: Array = cursor.buildings
			if int(cursor.index) >= buildings.size(): return true
			var node: Variant = buildings[int(cursor.index)]
			cursor.index = int(cursor.index) + 1
			# Entre um quadro e outro o prédio pode ter saído do trecho.
			if is_instance_valid(node) and chunk.is_ancestor_of(node):
				var span := STALL_WORK.begin()
				cursor.item = _rooftop_building_begin(node, batches)
				STALL_WORK.finish_slow("stream.harbor.rooftops.building_slabs", span, 2000, node)
		else:
			var item: Dictionary = cursor.item
			if not is_instance_valid(item.building) or not chunk.is_ancestor_of(item.building):
				cursor.item = {}
			elif int(item.slab_index) < (item.slabs as Array).size():
				var span := STALL_WORK.begin()
				_rooftop_slab(chunk, item, batches)
				STALL_WORK.finish_slow("stream.harbor.rooftops.slab_props", span, 2000, item.building)
			else:
				var span := STALL_WORK.begin()
				_rooftop_building_finish(chunk, item, cursor, batches)
				STALL_WORK.finish_slow("stream.harbor.rooftops.building_life", span, 2000, item.building)
				cursor.item = {}
	return false


static func _rooftop_buildings(chunk: Node3D) -> Array:
	var result := []
	for node in chunk.find_children("*", "Node3D", true, false):
		if node is UrbanBuildingBase: result.append(node)
	return result


## Primeiro item do prédio: acabamento da laje existente, leitura das lajes e casinha da
## escada. Dicionário vazio = prédio sem laje plana (o laço antigo pulava o resto dele).
static func _rooftop_building_begin(building: UrbanBuildingBase, batches: Dictionary) -> Dictionary:
	var key := building.building_id
	# Primeira aparição de uma superfície gera a textura 256 px em GDScript (RoofSurfaces._image)
	# dentro deste item: span separado para o log dizer se o pico foi isso.
	var surfaces_before: int = ROOFS._materials.size()
	var finish_span := STALL_WORK.begin()
	ROOFS.replace_existing(building, building.building_kind, key)
	if ROOFS._materials.size() != surfaces_before:
		STALL_WORK.finish_slow("stream.harbor.rooftops.surface_first_build", finish_span, 0, building)
	# A laje real (maior caixa horizontal mais alta do prédio) manda na
	# altura e no tamanho: altura nominal de UrbanBuildingBase não bate
	# com arquétipo que monta platibanda/penthouse próprio, e o tom de laje
	# ficava flutuando sobre a rua.
	var slabs := _roof_slabs(building)
	if slabs.is_empty(): return {}
	var main_roof: AABB = slabs[0]
	# Saída do telhado: UMA por prédio (playtest 29/10: o quartel tinha três casinhas
	# sorteadas em fila e a escada pintada chegava a nenhuma). Prédio com telhado
	# caminhável recebe a casinha onde a escada de verdade sai (HarborRoofCirculation);
	# os outros aceitam no máximo uma casinha ou alçapão do sorteio.
	var roof_exit_placed := false
	var cover := _pitched_cover(building, main_roof)
	var stair_house: Variant = ROOF_CIRCULATION.stair_house(building)
	if stair_house is Transform3D:
		var house: Transform3D = stair_house
		house.origin.y = main_roof.end.y + 0.012
		# Prédio escalonado: a laje de cima é menor que o terreno e a saída no canto do terreno ficava
		# metade para fora dela (30/10: "objeto tá para fora do prédio"). Prende dentro da laje de cima.
		var margin := Vector2(g.HOUSE_HALF.x + 0.25, g.HOUSE_HALF.y + 0.25)
		if main_roof.size.x > margin.x * 2.0: house.origin.x = clampf(house.origin.x, main_roof.position.x + margin.x, main_roof.end.x - margin.x)
		else: house.origin.x = main_roof.get_center().x
		if main_roof.size.z > margin.y * 2.0: house.origin.z = clampf(house.origin.z, main_roof.position.z + margin.y, main_roof.end.z - margin.y)
		else: house.origin.z = main_roof.get_center().z
		# Playtest 30/10: casa térrea com casinha de escada de 2 m lia como escada para um
		# segundo andar que não existe, e na casa de duas águas ela furava a telha. Térreo
		# e telhado inclinado saem por alçapão rente ao telhado (deitado na água).
		if cover.size != Vector3.ZERO:
			g._push(batches, "roof_hatch", building.global_transform * _hatch_on_slope(house, cover))
		elif ROOF_CIRCULATION.uses_hatch(ROOF_CIRCULATION.definition_for(building)):
			g._push(batches, "roof_hatch", building.global_transform * house)
		else:
			ROOF_CIRCULATION.build_house(building, house)
		roof_exit_placed = true
	return {"building": building, "key": key, "slabs": slabs, "slab_index": 0, "main_occupied": [], "roof_exit_placed": roof_exit_placed, "pitched": cover.size != Vector3.ZERO}


## Telhado de duas águas por cima da laje (casa pintada com beiral, PaintedFacadeKit):
## a malha "Roof" do kit. AABB vazio quando a laje é o próprio telhado. A laje lida por
## _roof_slabs fica no topo da parede, embaixo da telha: adereço posto nela fura a água.
static func _pitched_cover(building: UrbanBuildingBase, slab: AABB) -> AABB:
	var inverse := building.global_transform.affine_inverse()
	for node in building.find_children("Roof", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not String(mesh.get_parent().name).begins_with("PaintedFacade_"): continue
		var box := inverse * (mesh.global_transform * mesh.get_aabb())
		if box.size.y > 0.5 and box.end.y > slab.end.y + 0.5: return box
	return AABB()


## Alçapão deitado na água do telhado (cumeeira no centro em z, paralela a X, como o
## _pitched_roof do kit), na água do lado em que a escada sai, longe da cumeeira e do beiral.
static func _hatch_on_slope(house: Transform3D, cover: AABB) -> Transform3D:
	var center_z := cover.get_center().z
	var half_z := cover.size.z * 0.5
	var slope := cover.size.y / maxf(0.01, half_z)
	var side := 1.0 if house.origin.z >= center_z else -1.0
	var low := minf(0.9, half_z * 0.5)
	var run := clampf(absf(house.origin.z - center_z), low, maxf(half_z - 0.8, low))
	var x := clampf(house.origin.x, cover.position.x + 0.9, maxf(cover.end.x - 0.9, cover.position.x + 0.9))
	var tilt := Basis(Vector3.RIGHT, side * atan(slope))
	var surface := Vector3(x, cover.end.y - slope * run, center_z + side * run)
	return Transform3D(tilt * house.basis, surface + tilt * Vector3.UP * 0.01)


## Uma laje do prédio com seus adereços (um item do cursor por laje: as casas geminadas
## têm uma laje por unidade e cada uma lê os obstáculos do prédio inteiro).
static func _rooftop_slab(chunk: Node3D, item: Dictionary, batches: Dictionary) -> void:
	var building: UrbanBuildingBase = item.building
	var key: String = item.key
	var slab_index := int(item.slab_index)
	item.slab_index = slab_index + 1
	var roof: AABB = (item.slabs as Array)[slab_index]
	var roof_exit_placed: bool = item.roof_exit_placed
	var unit_key := key if slab_index == 0 else "%s|u%d" % [key, slab_index]
	var branch_roof_y := roof.end.y + 0.012
	var branch_roof_center := Vector2(roof.get_center().x, roof.get_center().z)
	var branch_size := Vector2(roof.size.x, roof.size.z)
	if branch_size.x < 2.8 or branch_size.y < 2.8: return
	# Laje embaixo da telha de duas águas: só o alçapão (posto no começo do prédio).
	if bool(item.get("pitched", false)): return
	var xform := building.global_transform
	var branch_occupied := _roof_obstacles(building, branch_roof_y)
	branch_occupied.append_array(preload("res://world/places/harbor_buildings/HarborRoofCirculation.gd").occupied(building))
	# Delegacia antes dos adereços genéricos: heliponto e torre pedem espaço.
	if key == "Police" and slab_index == 0:
		var police_span := STALL_WORK.begin()
		POLICE.decorate(chunk, building, branch_roof_y, branch_roof_center, branch_size, branch_occupied, batches)
		STALL_WORK.finish_slow("stream.harbor.rooftops.police", police_span, 2000, building)
	# Acabamento da laje: textura de verdade (manta, brita, placas, zinco...)
	# por tipo de prédio, sem tocar no material compartilhado da fábrica.
	# The source roof mesh owns its finish, including baked wear. Never
	# add a second roofmat/tar plane over the existing roof surface.
	# Laje é o que mais aparece nesta câmera: mais ocupação que o comum.
	var wanted := clampi(int(branch_size.x * branch_size.y / 18.0), 2, 10)
	var placed := 0
	for attempt in wanted * 12:
		if placed >= wanted: break
		var akey := unit_key + "|roof|" + str(attempt)
		var kind := g._pick(ROOF_PROPS, g._roll(akey) * 1.0)
		if kind.is_empty(): continue
		if kind in ROOF_EXITS and roof_exit_placed: continue
		# Casinha de escada em prédio térreo lê como escada para um andar que não existe.
		if kind == "roof_shed" and roof.end.y < g.SHED_MIN_ROOF_Y: continue
		# "vent" cai no 0.5 padrão. BuildingLife._roof_life empurra outro vent (com
		# vapor) fora deste sorteio, com STEAM_VENT_RADIUS 0.6; mantenha os dois coerentes.
		var radius := 0.9 if kind in ["ac_unit", "roof_hatch"] else 0.5
		if kind == "pipe_run": radius = 2.2
		if kind in ["roof_shed", "roof_garden"]: radius = 1.6
		if kind == "roof_chairs": radius = 0.9
		if kind in ["water_tank", "cooling_tower"]: radius = 1.4
		if kind == "solar_row": radius = 2.1
		if kind == "skylight": radius = 1.0
		# Laje estreita (unidade de casa geminada): peça que não cabe fica de fora.
		if branch_size.x < radius * 2.0 + 0.8 or branch_size.y < radius * 2.0 + 0.8: continue
		var local := branch_roof_center + Vector2((g._roll(akey + "x") - 0.5) * (branch_size.x - 2.0 * radius - 0.6), (g._roll(akey + "z") - 0.5) * (branch_size.y - 2.0 * radius - 0.6))
		var blocked := false
		for other in branch_occupied:
			if local.distance_to(other.point) < radius + other.radius: blocked = true; break
		if blocked: continue
		branch_occupied.append({"point": local, "radius": radius})
		var yaw := floorf(g._roll(akey + "r") * 4.0) * PI * 0.5
		g._push(batches, kind, xform * Transform3D(Basis(Vector3.UP, yaw), Vector3(local.x, branch_roof_y, local.y)))
		placed += 1
		if kind in ROOF_EXITS: roof_exit_placed = true
	item.roof_exit_placed = roof_exit_placed
	if slab_index == 0: item.main_occupied = branch_occupied


## Último item do prédio: outdoor e a vida da fachada/telhado (BuildingLife), que cria nós.
static func _rooftop_building_finish(chunk: Node3D, item: Dictionary, cursor: Dictionary, batches: Dictionary) -> void:
	var building: UrbanBuildingBase = item.building
	var key: String = item.key
	var main_roof: AABB = (item.slabs as Array)[0]
	var roof_y := main_roof.end.y + 0.012
	var roof_center := Vector2(main_roof.get_center().x, main_roof.get_center().z)
	var size := Vector2(main_roof.size.x, main_roof.size.z)
	var occupied: Array = item.main_occupied
	var has_billboard := false
	# These accessible storefronts identify themselves by their proper names;
	# a random fuel-brand slogan above Union misidentifies the clothing shop.
	if key not in ["NorthFrontage3", "NorthFrontage4"] and int(cursor.billboards) < 2 and size.x >= 7.5 and roof_y >= 4.4 and g._roll(key + "billboard") < 0.34:
		has_billboard = _place_billboard(chunk, building, roof_y, roof_center, size, occupied, batches)
		if has_billboard: cursor.billboards = int(cursor.billboards) + 1
	# Fachada e telhado "vivos" (escada de incêndio, ar-condicionado, varal...).
	LIFE.decorate(chunk, building, roof_y, roof_center, size, occupied, batches, has_billboard)


## Lajes do prédio: a laje única do arquétipo ou, nas casas geminadas (cada
## unidade é um volume próprio, nenhum cobre 60% da planta), o topo de cada
## unidade. Sem isto os telhados dessas fileiras ficavam de cor chapada.
static func _roof_slabs(building: UrbanBuildingBase) -> Array:
	# Pitched roofs own their finish; a generic slab cut through Cobra houses.
	if building.building_kind == "cobra_house": return []
	var single := _roof_box(building)
	if single.size != Vector3.ZERO: return [single]
	var result := []
	var inverse := building.global_transform.affine_inverse()
	# Uma varredura só: antes cada unidade da fileira refazia find_children no prédio
	# inteiro (unidades × malhas). A árvore não muda dentro desta função; mesma lista.
	var meshes := building.find_children("*", "MeshInstance3D", true, false)
	for node in meshes:
		var mesh := node as MeshInstance3D
		if not mesh.mesh is BoxMesh and not mesh.get_meta("harbor_source_box", false): continue
		var box := inverse * (mesh.global_transform * mesh.get_aabb())
		if box.size.x < 2.8 or box.size.z < 2.8 or box.size.y < 2.5 or box.position.y > 0.5: continue
		result.append(box)
	# A laje visível é a caixa mais alta sobre cada unidade (a fábrica põe uma
	# placa de cor por cima do volume); o acabamento vai acima dela.
	for index in result.size():
		var unit: AABB = result[index]
		for node in meshes:
			var mesh := node as MeshInstance3D
			var box := inverse * (mesh.global_transform * mesh.get_aabb())
			if box.size.x < unit.size.x * 0.5 or box.size.z < unit.size.z * 0.5: continue
			if not unit.grow(0.3).has_point(box.get_center()) and not Rect2(unit.position.x - 0.3, unit.position.z - 0.3, unit.size.x + 0.6, unit.size.z + 0.6).has_point(Vector2(box.get_center().x, box.get_center().z)): continue
			if box.end.y > unit.end.y and box.end.y < unit.end.y + 0.6:
				unit.size.y = box.end.y - unit.position.y
		result[index] = unit
	result.sort_custom(func(a, b): return a.size.x * a.size.z > b.size.x * b.size.z)
	return result


## Maior caixa horizontal (>=60% da planta nos dois eixos) mais alta, em
## coordenadas locais do prédio. AABB vazio se o arquétipo não tem laje plana.
static func _roof_box(building: UrbanBuildingBase) -> AABB:
	var best := AABB()
	var inverse := building.global_transform.affine_inverse()
	var footprint: Vector2 = building.building_size
	for node in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := inverse * (mesh.global_transform * mesh.get_aabb())
		if box.size.x < footprint.x * 0.6 or box.size.z < footprint.y * 0.6: continue
		if box.size.x > footprint.x * 1.3 or box.size.z > footprint.y * 1.3: continue
		if best.size == Vector3.ZERO or box.end.y > best.end.y: best = box
	return best


## Tudo que já está em cima da laje (caixa d'água, claraboia, chaminé) vira
## obstáculo em coordenadas locais do prédio, para o adereço novo não
## atravessar o existente.
static func _roof_obstacles(building: UrbanBuildingBase, roof_y: float) -> Array:
	var result := []
	var inverse := building.global_transform.affine_inverse()
	for node in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := inverse * (mesh.global_transform * mesh.get_aabb())
		if box.end.y < roof_y + 0.08 or box.position.y > roof_y + 6.0: continue
		if box.size.x > building.building_size.x * 0.8 and box.size.z > building.building_size.y * 0.8: continue
		if box.size.x > building.building_size.x * 0.9 or box.size.z > building.building_size.y * 0.9: continue
		var center := box.get_center()
		result.append({"point": Vector2(center.x, center.z), "radius": maxf(box.size.x, box.size.z) * 0.5 + 0.2})
	return result


## Outdoor no telhado encostado na borda sul, virado para a câmera (+Z
## global). É a única face que a câmera fixa vê de frente.
static func _place_billboard(chunk: Node3D, building: UrbanBuildingBase, roof_y: float, roof_center: Vector2, size: Vector2, occupied: Array, batches: Dictionary) -> bool:
	var inverse_basis := building.global_transform.basis.inverse()
	var south_local := inverse_basis * Vector3(0, 0, 1)
	var facing := Vector2(south_local.x, south_local.z).normalized()
	# Só eixos: prédios da V1 são alinhados à grade.
	var along_z := absf(facing.y) > absf(facing.x)
	var half_depth := (size.y if along_z else size.x) * 0.5
	var edge := roof_center + facing * (half_depth - 1.2)
	for other in occupied:
		if edge.distance_to(other.point) < other.radius + 3.0: return false
	var yaw := atan2(facing.x, facing.y)
	var local := Transform3D(Basis(Vector3.UP, yaw), Vector3(edge.x, roof_y, edge.y))
	var world := building.global_transform * local
	g._push(batches, "billboard_frame", world)
	var brand: Dictionary = BRANDS.pick(building.building_id)
	chunk.add_child(BRANDS.billboard_panel(brand, chunk.global_transform.affine_inverse() * world))
	return true



## Prédios montados fora dos arquétipos (hospital, residências, fachadas
## autorais): só o acabamento da laje, sem adereços (não sabemos o que há lá).
static func _other_roofs(chunk: Node3D, _batches: Dictionary) -> void:
	for child in chunk.get_children(): _other_roof(child)


## Um filho do chunk por item (o passo 12 fatiado chama isto pelo cursor).
static func _other_roof(child: Node) -> void:
	# A carga com entrada a pé tem um teto retrátil; uma laje do chunk inteiro ficaria
	# opaca sobre o jogador depois que o teto real tivesse sumido.
	if child.get_meta("native_dynamic_roof",false): return
	if not child is Node3D or child is UrbanBuildingBase or child is MultiMeshInstance3D: return
	if child.find_children("*", "MeshInstance3D", true, false).size() < 3: return
	var roof := ROOFS.find_roof(child)
	if roof.size == Vector3.ZERO or roof.end.y < 2.5: return
	ROOFS.replace_existing(child, "", String(child.name))
