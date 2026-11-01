extends RefCounted
## Construtores de registro do NativeRegion (_build_record e o que ele chama: marca central da serra,
## prédios e fachadas do porto, lugares da serra, floresta, navio Northstar, guindastes e guarda-corpos),
## separados em 01/11 (Onda 2) só para o NativeRegion.gd caber na leitura. Sem estado próprio: registros,
## terreno, teleféricos e materiais continuam no NativeRegion, que mantém cada função antiga como
## delegação de uma linha com a mesma assinatura (_prepare continua chamando _prepare_forest lá).
## `g` fica como Node3D, e não como o script do NativeRegion, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: EditableRegion e testes sobrescrevem
## `_build_record` e `_building` (EditableRegion chama `super._building`), e o despacho tem de continuar
## o de antes. A `static var` do dono (_blade_forge_enabled) é lida por `g.get_script()`.
## Roda na thread principal (estágio de build do chunk), como antes.
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const CEMETERY := preload("res://world/regions/OriginalCemetery3D.gd")
const FORGE_HERMIT := preload("res://world/mountain_detail/forge/ForgeHermitCabin.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const HARBOR_BRIDGE := preload("res://world/urban_detail/HarborBridge3D.gd")
const HARBOR_DRESSING := preload("res://world/urban_detail/HarborAreaDressing3D.gd")
const HARBOR_PROP := preload("res://world/urban_detail/HarborProp3D.gd")
const HARBOR_PUBLIC_REALM := preload("res://world/urban_detail/HarborPublicRealm3D.gd")
const HARBOR_ROAD_GEOMETRY := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const HARBOR_ROUTE_FACTORY := preload("res://world/harbor_route_detail/HarborRouteDetailFactory.gd")
const MOUNTAIN_FACTORY := preload("res://world/mountain_detail/MountainDetailFactory.gd")
const MOUNTAIN_FORGE := preload("res://world/mountain_detail/forge/MountainForge.gd")
const MOUNTAIN_JEEP_SCENERY := preload("res://world/mountain_jeep/MountainJeepScenery.gd")
const MOUNTAIN_REFUGE := preload("res://world/mountain_detail/MountainRefuge.gd")
const MOUNTAIN_SHADOW := preload("res://world/mountain_detail/MountainShadowFinish.gd")
const NORTHSTAR_HOIST := preload("res://world/regions/NorthstarCargoHoist3D.gd")
const PAINTED_MOUNTAIN := preload("res://world/mountain_detail/PaintedMountainPlaces.gd")
const PORT_CONTAINER_BATCH := preload("res://world/regions/PortContainerBatch.gd")
const PORT_SHIP_DRESSING := preload("res://world/regions/PortShipDressing3D.gd")
const PORT_SHIP_PAINT := preload("res://world/regions/PortShipMaterials3D.gd")
const RESTAURANT_TERRACE := preload("res://world/urban_detail/HarborRestaurantTerrace3D.gd")
const ROUTE_GEOMETRY := preload("res://world/mountain_detail/MountainRouteGeometry.gd")
const SOUTH_PORT := preload("res://world/regions/OriginalSouthPort.gd")
const SOUTH_PORT_LAYOUT := preload("res://world/regions/OriginalSouthPortLayout.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")
const URBAN_FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const WALKUP_DOOR := preload("res://world/places/WalkupFacadeDoor.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _build_record(chunk: Node3D, record: Dictionary) -> void:
	match record.kind:
		"cemetery":
			var cemetery := CEMETERY.new()
			cemetery.position = record.position
			chunk.add_child(cemetery)
		"south_port_model":
			# Prédio do porto com fachada pintada (galpão, oficina, garagem: PaintedHarborHouses.LOWRISE)
			# monta pela fábrica, com a mesma pegada e altura do catálogo, no lugar do modelo antigo.
			if str(record.id).begins_with("PortBuilding") and not PaintedHarborHouses.style_for(str(record.id), str(record.model_kind)).is_empty():
				var def: Dictionary = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").for_source(str(record.id))
				var painted_port := URBAN_FACTORY.populate_chunk(chunk, {"id": str(record.id), "kind": str(record.model_kind), "position": record.position,
					"size": (record.footprint as Rect2).size / 16.0, "height_override": float(def.get("roof_height", 4.6)) - .10, "variant_seed": int(record.variant)})
				if painted_port != null:
					painted_port.add_to_group("exterior_reveal_building")
					preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd").install(painted_port,str(record.id))
				return
			var port_art: Node3D = SOUTH_PORT.mount(chunk,record)
			if str(record.id).begins_with("PortBuilding"):
				port_art.add_to_group("exterior_reveal_building")
				preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd").install(port_art,str(record.id))
		"south_port_ship_detail":
			var ship_detail := PORT_SHIP_DRESSING.new()
			chunk.add_child(ship_detail)
			ship_detail.build_santa_mare(SOUTH_PORT_LAYOUT.ship_hull())
		"south_port_rail":
			var delta: Vector3 = record.b-record.a
			var rail: MeshInstance3D = g._box(chunk,"SantaMareRail",(record.a+record.b)*.5+Vector3.UP*.45,Vector3(.25,.9,delta.length()),Color("a0a49a"),true)
			rail.rotation.y = atan2(delta.x,delta.z)
		"salvage":
			var yard = preload("res://world/places/SalvageYardNative.gd").new()
			yard.position = record.position
			chunk.add_child(yard)
		"harbor_dressing":
			var dressing := HARBOR_DRESSING.new()
			dressing.configure(record.zone_id)
			dressing.position = record.position
			chunk.add_child(dressing)
		"harbor_bridge":
			var bridge:=HARBOR_BRIDGE.new()
			bridge.position=record.position
			chunk.add_child(bridge)
		"harbor_prop":
			# Banco/árvore/poste do pátio da ilha caía dentro da rampa aberta do túnel.
			if g.region_id == "harbor" and CANAL_TUNNEL.reserves(Vector2(record.position.x,record.position.z),0.8): return
			var skate_layout := preload("res://activities/skate/SkateParkLayout.gd")
			if g.region_id == "harbor" and skate_layout.enabled() and skate_layout.FOOTPRINT.grow(.3).has_point(Vector2(record.position.x, record.position.z)): return
			var prop:=HARBOR_PROP.new()
			prop.configure(record.data)
			prop.position=record.position
			chunk.add_child(prop)
		"harbor_restaurant":
			var terrace := RESTAURANT_TERRACE.new()
			terrace.configure(record.venue_id,record.table_index,record.fabric)
			terrace.position = record.position
			chunk.add_child(terrace)
			terrace.add_to_group("harbor_restaurant_terrace")
		"ship": g._build_ship(chunk)
		"lake":
			var lake = preload("res://world/regions/NativeLake.gd").new()
			lake.variant = record.variant
			lake.position = record.position
			chunk.add_child(lake)
		"cargo_plane":
			var aircraft = preload("res://world/places/CargoPlaneNative.gd").new()
			aircraft.name = "SmugglerCargoPlane"
			aircraft.position = record.position
			chunk.add_child(aircraft)
		"tree":
			var variant: int = [0,1,2,6,7][int(record.variant) % 5] if g.region_id == "mountain" else int(record.variant)
			var tree = preload("res://world/regions/NativePine.gd").create(variant,record.snow)
			tree.position = record.position
			if g.terrain != null: tree.position.y = g.terrain.surface_height_at(Vector2(tree.position.x,tree.position.z))
			chunk.add_child(tree)
			g._tree_collision(tree,chunk)
		"mountain_jeep_scenery": MOUNTAIN_JEEP_SCENERY.build(chunk,record)
		"cave_approach":
			var cover := preload("res://world/mountain_detail/MountainCaveApproach.gd").new()
			cover.position = record.position
			chunk.add_child(cover)
		"mountain_road_lamp":
			var lamp = preload("res://world/mountain_detail/MountainRoadLamp3D.gd").new()
			lamp.position = record.position
			if g.terrain != null: lamp.position.y = g.terrain.surface_height_at(Vector2(lamp.position.x,lamp.position.z))
			chunk.add_child(lamp)
		"sawmill_yard":
			MOUNTAIN_FACTORY.populate_sawmill_chunk(chunk,record)
		"mountain_village": MOUNTAIN_FACTORY.populate_village_chunk(chunk,record)
		"mountain_forge":
			if not g.get_script()._blade_forge_enabled: return
			var forge := MOUNTAIN_FORGE.new()
			forge.position = record.position
			chunk.add_child(forge)
		"forge_hermit_cabin":
			if not g.get_script()._blade_forge_enabled: return
			var cabin := FORGE_HERMIT.new()
			cabin.position = record.position
			chunk.add_child(cabin)
		"mountain_refuge":
			if not MOUNTAIN_REFUGE.enabled(): return
			var refuge := MOUNTAIN_REFUGE.new()
			refuge.position = record.position
			chunk.add_child(refuge)
		"environmental_parity":
			var mechanism := MOUNTAIN_FACTORY.populate_environmental_chunk(chunk,record)
			if mechanism != null:
				mechanism.set_operating(g.chairlift_operating)
				mechanism.set_animation_active(true)
				g.chairlifts.append(mechanism)
		"harbor_route_zone": HARBOR_ROUTE_FACTORY.populate_zone_chunk(chunk, record.zone_id, record.get("prepared_route_zone"))
		"harbor_public_realm":
			var public_realm := HARBOR_PUBLIC_REALM.new()
			public_realm.zone_id = record.zone_id
			public_realm.position = record.position
			chunk.add_child(public_realm)
		"road":
			if g.region_id == "harbor": return
			var road_a: Vector3 = record.a
			var road_b: Vector3 = record.b
			var mountain_pass_road: bool = record.get("road_id","") == "mountain_pass"
			var bridge_join: bool = mountain_pass_road and road_a.distance_to(CATALOG._at(Vector2(3000,400),"mountain")) < 0.1
			# O MountainPass é autorado na altura do tabuleiro. Baixa a laje de estrada de 5 cm para
			# o topo de cada segmento ficar coplanar com a ponte e sem borda elevada na ponta.
			# O primeiro segmento também sobrepõe o tabuleiro; a curva de trânsito ainda
			# começa na emenda autorada.
			if bridge_join:
				road_a -= (road_b-road_a).normalized()*5.0
			var offset: Vector3 = road_b-road_a
			var center: Vector3 = (road_a+road_b)*.5
			var surface_kind: String = record.get("surface","asphalt")
			var road_color := HARBOR_ROAD_GEOMETRY.ROAD_COLOR if surface_kind == "asphalt" else Color("544a3b")
			var shape := ROUTE_GEOMETRY.polygon(record.left_a,record.left_b,record.right_b,record.right_a)
			var pieces: Array[PackedVector2Array] = g.route_geometry.outside_roads(shape,record.road_id,true)
			var unified_bridge := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
			if unified_bridge.enabled() and ROUTE_GEOMETRY.bounds(shape).intersects(unified_bridge.east_bounds()):
				pieces = GROUND_CUT.subtract_exact(pieces,[unified_bridge.east_footprint()])
			var rows: Array = chunk.get_meta("road_surface_rows",[])
			for piece in pieces: rows.append({"polygon":piece,"top":.026,"color":road_color})
			chunk.set_meta("road_surface_rows",rows)
			# Só o passo principal de duas faixas precisa de faixa central.
			if mountain_pass_road:
				if unified_bridge.enabled(): g._mountain_center_marking(chunk,center,offset)
				else:
					var line: MeshInstance3D = g._box(chunk,"CenterLine",center+Vector3(0,.034,0),Vector3(.09,.008,offset.length()*.64),Color("b6aa71"))
					line.rotation.y = atan2(offset.x,offset.z)
			# Os acostamentos rurais de passo/trilha são terreno. As calçadas genéricas de 2.5 m
			# cruzavam o asfalto dos cruzamentos e faziam fitas largas flutuando nas curvas.
		"building": g._building(chunk,record.data)
		"original_facade": g._original_facade(chunk,record.data)
		"container":
			var art = g._held_load("res://world/regions/LootablePortContainer.gd").new()
			chunk.add_child(art)
			art.build(record.position,record.size)
		"mountain_place": g._mountain_place(chunk,record.data)

func _mountain_center_marking(chunk: Node3D, center: Vector3, offset: Vector3) -> void:
	var bridge_kit = preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
	var direction := offset.normalized()
	var side := Vector3(-direction.z,0,direction.x)*.045
	var a := center-direction*offset.length()*.32
	var b := center+direction*offset.length()*.32
	var polygon := PackedVector2Array()
	for point in [a+side,b+side,b-side,a-side]: polygon.append(Vector2(point.x,point.z))
	var bounds := GROUND_CUT.bounds(polygon)
	if not bounds.intersects(bridge_kit.east_bounds().grow(.75),true):
		var line: MeshInstance3D = g._box(chunk,"CenterLine",center+Vector3(0,.034,0),Vector3(.09,.008,offset.length()*.64),Color("b6aa71"))
		line.rotation.y = atan2(offset.x,offset.z)
		return
	# O centro do segmento nao prova ownership da faixa inteira. Recortar o
	# desenho real e reservar 75 cm apos a cabeceira evita fundir dupla e traco.
	var terminal_gap := GROUND_CUT.rect_polygon(Rect2(bridge_kit.EAST_END-.001,bridge_kit.EAST_Z-1.0,.751,2.0))
	var pieces := GROUND_CUT.subtract_exact([polygon],[bridge_kit.east_footprint(),terminal_gap])
	var mesh := GROUND_CUT.flat_mesh(pieces,.038,1.0)
	if mesh == null: return
	var clipped_line := MeshInstance3D.new()
	clipped_line.name = "CenterLineClippedAtBridge"
	clipped_line.mesh = mesh
	clipped_line.material_override = g._material(Color("b6aa71"))
	clipped_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(clipped_line)

func _building(chunk: Node3D, data: Dictionary) -> void:
	if data.id == "LastroBar":
		var bar := preload("res://world/places/bars/HarborBarFacade.gd").new()
		bar.add_to_group("exterior_reveal_building")
		bar.position = data.position
		chunk.add_child(bar)
		return
	if data.id == "FerroVelhoGym":
		var gym := preload("res://world/places/gym/GymFacade.gd").new()
		gym.add_to_group("exterior_reveal_building")
		gym.position = data.position
		chunk.add_child(gym)
		return
	if data.id == "Fagulha":
		var arcade := preload("res://world/places/arcade/ArcadeFacade.gd").new()
		arcade.add_to_group("exterior_reveal_building")
		arcade.position = data.position
		chunk.add_child(arcade)
		return
	if data.id == "CuritibaCellar":
		var cellar := preload("res://world/places/curitiba_cellar/CuritibaCellarFacade.gd").new()
		cellar.add_to_group("exterior_reveal_building")
		cellar.position = data.position
		chunk.add_child(cellar)
		return
	if data.id == "NorthFrontage1":
		var market := preload("res://world/places/supermarket/SupermarketFacade.gd").new()
		market.add_to_group("exterior_reveal_building")
		market.position = CATALOG.get_definition("harbor_supermarket").exterior_position
		chunk.add_child(market)
		return
	# Exactly one exterior per authored building record; Maciota belongs to ProductionWorld.
	if data.id == "Garage": return
	var facade: Dictionary = data.duplicate(true)
	var place_ids := {"NorthFrontage0":"harbor_bank","NorthFrontage2":"harbor_ammunation","NorthFrontage3":"harbor_clothing","NorthFrontage4":"harbor_fuel","Police":"harbor_police","Clinic":"harbor_hospital","NorthFireStation":"harbor_fire_station","CanalHomesWest":"canal_north"}
	if place_ids.has(data.id):
		var definition: Dictionary = CATALOG.get_definition(place_ids[data.id])
		facade["place_id"] = definition.id
		facade["original_name"] = definition.original_name
		facade["name"] = definition.original_name
		facade["entry_position"] = definition.entry_position
		facade["return_position"] = definition.return_position
		facade["variant"] = definition.variant
		# O catálogo é a autoridade para fachadas originais substituídas e origens de transição.
		facade.position = definition.exterior_position
	var art := URBAN_FACTORY.populate_chunk(chunk,facade)
	if art != null:
		art.add_to_group("exterior_reveal_building")
		preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd").install(art,str(data.id))
		art.set_meta("source_id",data.get("source",""))
		art.set_meta("place_id",facade.get("place_id",""))
		if facade.get("place_id", "") in ["harbor_ammunation", "harbor_police", "harbor_bank", "harbor_clothing", "harbor_fuel", "harbor_hospital", "harbor_fire_station"]:
			art.add_to_group("v2_walkin_facade")
			if facade.place_id in ["harbor_bank", "harbor_clothing", "harbor_fuel", "harbor_hospital", "harbor_fire_station"]: art.set_open_amount(0.0)
		if facade.has("entry_position"):
			art.set_meta("entry_position",facade.entry_position)
			art.set_meta("return_position",facade.return_position)
		if facade.get("place_id", "") == "canal_north": WALKUP_DOOR.install(art, CATALOG.get_definition("canal_north"))

func _mountain_place(chunk: Node3D, data: Dictionary) -> void:
	var painted_place := PAINTED_MOUNTAIN.handles(str(data.id))
	if painted_place:
		# Prédios pintados da serra; a porta de acesso continua a do WalkupFacadeDoor (a loja de
		# armas abre pela WeaponShopEntrance, que acha a frente pelo grupo e pelo place_id).
		var painted: Node3D = PAINTED_MOUNTAIN.build(chunk, data)
		painted.add_to_group("exterior_reveal_building")
		if data.id == "mountain_gunshop":
			painted.set_meta("place_id", data.id)
			painted.add_to_group("v2_weapon_shop_facade")
			painted.add_to_group("v2_walkin_facade")
		WALKUP_DOOR.install(painted, data)
		var painted_size: Vector3 = PAINTED_MOUNTAIN.size_for(str(data.id))
		MOUNTAIN_SHADOW.attach(chunk, Vector2(painted_size.x, painted_size.z), data.exterior_position + PAINTED_MOUNTAIN.building_center(str(data.id)))
	elif str(data.id).begins_with("mountain_cabin") or data.id == "lumberjack_shelter":
		var art = g._held_load("res://assets/regions/source/world/mountain_pass/art/winter_props/LumberjackCabin3D.gd").new()
		art.add_to_group("exterior_reveal_building")
		art.position = data.exterior_position
		chunk.add_child(art)
		WALKUP_DOOR.install(art, data)
	elif data.id == "mountain_bunker":
		var art = preload("res://world/places/BunkerExteriorNative.gd").new()
		art.add_to_group("exterior_reveal_building")
		art.position = data.exterior_position
		chunk.add_child(art)
		WALKUP_DOOR.install(art, data)
	elif data.id == "ski_lodge":
		var art = g._held_load("res://assets/regions/source/world/mountain_pass/SummitSkiLodge3D.gd").new()
		art.add_to_group("exterior_reveal_building")
		art.position = data.exterior_position
		chunk.add_child(art)
		WALKUP_DOOR.install(art, data)
	elif data.id in ["mountain_outfitters","mountain_boutique","mountain_village_outfitters","mountain_gunshop","mountain_mystery_cave"]:
		g._original_facade(chunk,data)
	else:
		# As fachadas restantes estão ausentes de propósito até a geometria original delas ser portada.
		var marker := Marker3D.new()
		marker.name = data.id
		marker.position = data.entry_position
		chunk.add_child(marker)
	# Pegada da construção exterior, derivada dos modelos existentes. Esses
	# planos visuais não participam da colisão nem bloqueiam as entradas.
	var contact_size := Vector2.ZERO
	if painted_place: pass
	elif str(data.id).begins_with("mountain_cabin") or data.id == "lumberjack_shelter": contact_size = Vector2(3.6, 4.2)
	elif data.id == "ski_lodge": contact_size = Vector2(13.8, 8.4)
	elif data.id == "mountain_bunker": contact_size = Vector2(18.0, 12.0)
	elif data.id in ["mountain_outfitters", "mountain_boutique", "mountain_village_outfitters"]: contact_size = Vector2(6.7, 4.0)
	elif data.id == "mountain_gunshop": contact_size = Vector2(7.0, 4.0)
	if contact_size != Vector2.ZERO: MOUNTAIN_SHADOW.attach(chunk, contact_size, data.exterior_position)

func _original_facade(chunk: Node3D,data: Dictionary) -> void:
	if data.region == "harbor":
		# Residências/cemitério só do catálogo não são duplicados em harbor_buildings.
		var branch_art := URBAN_FACTORY.populate_chunk(chunk,data)
		if branch_art != null:
			branch_art.add_to_group("exterior_reveal_building")
			WALKUP_DOOR.install(branch_art, data)
		return
	var path := ""
	match str(data.id):
		"harbor_hospital": path = "world/harbor/hospital/HarborHospitalModel3D.gd"
		"westgate_garden","quayside_house","canal_north": path = "world/harbor/residences/ResidenceExterior3D.gd"
		"cemetery_keeper": path = "world/harbor/cemetery/CemeteryHouseExterior3D.gd"
		"harbor_ammunation": path = "guns/ammunation/AmmunationFacade3D.gd"
		"mountain_gunshop": path = "world/mountain_pass/art/review_0908/MountainGunShop3D.gd"
		"mountain_outfitters","mountain_boutique","mountain_village_outfitters": path = "world/mountain_pass/ResortShop3D.gd"
		"mountain_mystery_cave": path = "world/mountain_pass/MountainWaterfallCave3D.gd"
	if path.is_empty(): return
	var art = g._held_load("res://assets/regions/source/"+path).new()
	art.add_to_group("exterior_reveal_building")
	if data.service == "residence": art.variant_index = data.variant
	art.position = data.exterior_position
	chunk.add_child(art)
	if data.id == "mountain_gunshop":
		art.set_meta("place_id", data.id)
		art.add_to_group("v2_weapon_shop_facade")
		art.add_to_group("v2_walkin_facade")
	if data.id == "harbor_hospital":
		art.set_public_door_amount(1.0)
		art.set_door_amount(1.0)
		for mesh in art.find_children("*","MeshInstance3D",true,false): mesh.layers = 1
	for label in art.find_children("*","Label3D",true,false): label.text = data.original_name
	# Native collision follows each original structural mesh, keeping open approaches.
	for mesh in art.find_children("*","MeshInstance3D",true,false):
		var bounds: AABB = mesh.mesh.get_aabb()
		var center: Vector3 = mesh.global_transform * bounds.get_center()
		if center.y > 2.4 or bounds.size.y < .4: continue
		if mesh.get_meta("interior_solid_id","") != "" or bounds.size.x > 2 and bounds.size.z > 2:
			mesh.create_trimesh_collision()
	WALKUP_DOOR.install(art, data)

func _prepare_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3913
	var places := CATALOG.definitions()
	for grove in g.source_data.forest_clusters:
		var center := Vector2(grove.center[0],grove.center[1])
		var placed := 0
		for attempt in int(grove.count)*6:
			if placed >= int(grove.count): break
			var original := center+Vector2.from_angle(rng.randf()*TAU)*sqrt(rng.randf())*float(grove.radius)
			var point := CATALOG._at(original,g.region_id)
			var blocked := false
			for place in places:
				if place.region == g.region_id and point.distance_to(place.exterior_position)<12: blocked=true
			for lake in [Rect2(6680,-320,800,700),Rect2(5080,-1500,740,680)]:
				if lake.has_point(original): blocked=true
			var key: Vector2i = g._cell(point)
			for x in range(-1,2):
				for z in range(-1,2):
					for record in g.records.get(key+Vector2i(x,z),[]):
						if record.kind == "road":
							var nearest := Geometry3D.get_closest_point_to_segment(point,record.a,record.b)
							# Mantém a exclusão de 5.625m de antes da migração para a EastVale: alargar o
							# leito visual de terra dela em 0.5m não pode sortear de novo bosques sem relação.
							var clearance: float = 5.625 if record.get("surface","")=="earth" else record.width*.5+4
							if point.distance_to(nearest)<clearance: blocked=true
						elif record.kind == "tree" and point.distance_to(record.position)<2.4: blocked=true
			if blocked: continue
			g._record(point,{"kind":"tree","position":point,"variant":placed%8,"snow":grove.snow})
			placed+=1
	# Filtra depois da geração determinística: preserva toda árvore fora da clareira autorada.
	# Rejeitar durante o posicionamento do RNG sortearia de novo bosques posteriores pela montanha inteira.
	for key in g.records:
		g.records[key] = g.records[key].filter(func(record):
			if record.kind != "tree": return true
			# Serra ilha: nada de árvore na encosta da costa nem no mar.
			# As células da ponte leste ficam fora: lá a margem é a da ponte (MountainBridgeShore), não a costa.
			if TERRAIN.island_enabled() and g._cell(record.position) not in g.MOUNTAIN_BRIDGE_VOID_CELLS and preload("res://world/shape/WorldShape.gd").field_distance("mountain", Vector2(record.position.x,record.position.z)) < 10.0: return false
			var original: Vector2 = Vector2(record.position.x,record.position.z)/g.SCALE-CATALOG.MOUNTAIN_OFFSET
			var planar := Vector2(record.position.x,record.position.z)
			if MOUNTAIN_FORGE.FOOTPRINT.grow(2.0).has_point(planar) or FORGE_HERMIT.FOOTPRINT.grow(2.0).has_point(planar) or MOUNTAIN_REFUGE.FOOTPRINT.grow(2.0).has_point(planar): return false
			return not g._helipad_reserved(original) and not g._fort_exit_reserved(Vector2(record.position.x,record.position.z)) and not preload("res://world/mountain_detail/OriginalVillageLayout.gd").is_reserved(original))

func _build_ship(chunk: Node3D) -> void:
	var outline := PackedVector2Array()
	for point in g.source_data.ship_deck: outline.append(Vector2(point[0],point[1])*g.SCALE)
	var triangles := Geometry2D.triangulate_polygon(outline)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangles:
		var point: Vector2 = outline[index]
		surface.add_vertex(Vector3(point.x,0,point.y))
	surface.generate_normals()
	var deck := MeshInstance3D.new()
	deck.name = "NorthstarDeck"
	deck.mesh = surface.commit()
	deck.material_override = PORT_SHIP_PAINT.material("deck")
	chunk.add_child(deck)
	deck.create_trimesh_collision()
	# As paredes do casco deixam a silhueta produtiva do Northstar legível da
	# câmera oblíqua do jogo em vez de deixar um convés fino como papel sobre a água.
	for index in outline.size():
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index+1)%outline.size()]
		var delta := b-a
		var wall: MeshInstance3D = g._box(chunk,"NorthstarHull",Vector3((a.x+b.x)*.5,-.65,(a.y+b.y)*.5),Vector3(.18,1.3,delta.length()),Color("35464b"),true)
		wall.rotation.y = atan2(delta.x,delta.y)
		wall.material_override = PORT_SHIP_PAINT.material("hull")
	# Termina na borda reta do casco do porto: o convés fornece acabamento e apoio
	# além de x=3372. O antigo fim em 3418 sobrepunha o convés.
	var gangway := Rect2(3130*g.SCALE,1742*g.SCALE,(3372-3130)*g.SCALE,40*g.SCALE)
	g._box(chunk,"NorthstarGangway",Vector3(gangway.get_center().x,-.03,gangway.get_center().y),Vector3(gangway.size.x,.06,gangway.size.y),Color("7c8073"),true)
	for side in [1738,1782]:
		g._box(chunk,"GangwayRail",Vector3(3251*g.SCALE,.45,side*g.SCALE),Vector3(242*g.SCALE,.9,.10),Color("a0a49a"),true)
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i+1)%outline.size()]
		if is_equal_approx(a.x,3372*g.SCALE) and is_equal_approx(b.x,3372*g.SCALE):
			g._ship_rail(chunk,Vector2(a.x,990*g.SCALE),Vector2(a.x,1738*g.SCALE))
			g._ship_rail(chunk,Vector2(a.x,1782*g.SCALE),Vector2(a.x,2070*g.SCALE))
		elif is_equal_approx(a.y,2115*g.SCALE) and is_equal_approx(b.y,2115*g.SCALE):
			# Preserva o passeio sul autorado, com guarda-corpos dos dois lados da boca.
			g._ship_rail(chunk,Vector2(3400*g.SCALE,a.y),Vector2(3534*g.SCALE,a.y))
			g._ship_rail(chunk,Vector2(3606*g.SCALE,a.y),Vector2(3740*g.SCALE,a.y))
		else: g._ship_rail(chunk,a,b)
	for cargo in g.source_data.ship_cargo:
		var center := Vector3(cargo.position[0]*g.SCALE,1.1,cargo.position[1]*g.SCALE)
		var size := Vector3(cargo.size[0]*g.SCALE,2.2,cargo.size[1]*g.SCALE)
		var cargo_seed := absi(roundi(center.x*7.0+center.z*11.0))
		# A caixa lisa continua como colisão do bloco, mas o visual agora são dois
		# contêineres lado a lado, com cor, desgaste e porta voltada alternadamente.
		var cargo_block: MeshInstance3D = g._box(chunk,"NorthstarCargo",center,size,Color.WHITE,true)
		cargo_block.mesh = null
		var container_width := (size.x-.16)*.5
		for column in 2:
			var theme := (cargo_seed+column*2)%5
			var visual := PORT_CONTAINER_BATCH.create(theme,Vector3(container_width,size.y,size.z-.1),(cargo_seed+column)%2 == 1)
			visual.position = Vector3(center.x+(column-.5)*(container_width+.08),center.y-size.y*.5,center.z)
			chunk.add_child(visual)
	var cabin := Rect2(3440*g.SCALE,1795*g.SCALE,260*g.SCALE,232*g.SCALE)
	g._box(chunk,"NorthstarAftCabin",Vector3(cabin.get_center().x,1.55,cabin.get_center().y),Vector3(cabin.size.x,3.1,cabin.size.y),Color("bec3b8"),true)
	g._box(chunk,"NorthstarWheelhouse",Vector3(cabin.get_center().x,3.55,cabin.get_center().y-.8),Vector3(cabin.size.x*.78,1.25,cabin.size.y*.58),Color("d2d4c8"),true)
	for side in [-1.0,1.0]:
		g._box(chunk,"NorthstarWindow",Vector3(cabin.get_center().x+side*cabin.size.x*.25,3.62,cabin.position.y-.02),Vector3(cabin.size.x*.20,.42,.05),Color("213942"))
	g._box(chunk,"NorthstarStack",Vector3(cabin.get_center().x,5.0,cabin.get_center().y+.9),Vector3(1.0,2.0,1.0),Color("52625e"),true)
	for source_z in [1052.0,1388.0,1612.0]: g._build_northstar_crane(chunk,Vector2(3190,source_z)*g.SCALE)
	var ship_detail := PORT_SHIP_DRESSING.new()
	chunk.add_child(ship_detail)
	ship_detail.build_northstar(outline)

func _build_northstar_crane(chunk: Node3D, point: Vector2) -> void:
	var steel := Color("c3a24c")
	for z in [-1.15,1.15]: g._box(chunk,"NorthstarCraneLeg",Vector3(point.x,2.6,point.y+z),Vector3(.42,5.2,.42),steel,true).material_override = PORT_SHIP_PAINT.material("crane")
	g._box(chunk,"NorthstarCraneCrossbeam",Vector3(point.x,5.15,point.y),Vector3(.48,.42,3.0),steel,true).material_override = PORT_SHIP_PAINT.material("crane")
	var boom_start := Vector3(point.x,5.15,point.y)
	var boom_end := Vector3(point.x+18.0,5.15,point.y)
	var boom: MeshInstance3D = g._box(chunk,"NorthstarCraneBoom",(boom_start+boom_end)*.5,Vector3(.38,.38,boom_start.distance_to(boom_end)),steel,true)
	boom.name = "NorthstarCraneBoom_%d" % roundi(point.y*16.0)
	boom.rotation.y = PI*.5
	boom.material_override = PORT_SHIP_PAINT.material("crane")
	var rigging := PORT_SHIP_DRESSING.new()
	chunk.add_child(rigging)
	rigging.build_northstar_crane(point)
	var hoist := NORTHSTAR_HOIST.new()
	hoist.configure(point,point.y*.01)
	chunk.add_child(hoist)

func _ship_rail(chunk: Node3D,a: Vector2,b: Vector2) -> void:
	var center := (a+b)*.5
	var delta := b-a
	var rail: MeshInstance3D = g._box(chunk,"ShipRail",Vector3(center.x,.5,center.y),Vector3(.15,1,delta.length()),Color("b7bbae"),true)
	rail.rotation.y = atan2(delta.x,delta.y)
