extends RefCounted
## Preparação dos dados da região (corpo de NativeRegion._prepare, 194 linhas) em etapas, separada em 01/11
## (Onda 3) só para o NativeRegion.gd caber na leitura. Não tem estado próprio: records, roads, buildings,
## entries, extra_land, harbor_road_geometry, harbor_ocean, coastal_protection, terrain... continuam no
## NativeRegion, que mantém _prepare como delegação de uma linha: EditableRegion a sobrescreve e chama
## super._prepare(), e o despacho continua o de antes.
## `g` fica como Node3D, e não como o script do NativeRegion, para não criar preload cíclico.
## Até as chamadas a funções do dono passam por `g.` (_record, _add_road, _prepare_forest,
## _revise_mountain_routes, _mountain_site_terrain): EditableRegion e as subclasses de teste podem
## sobrescrevê-las. Roda na thread de quem chamou prepare_data, como antes: na carga, o WorkerThreadPool de
## ProductionWorld._prepare_geography, com a região ainda fora da árvore; nenhuma linha mudou de thread.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const CEMETERY := preload("res://world/regions/OriginalCemetery3D.gd")
const CITY_DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const FORGE_HERMIT := preload("res://world/mountain_detail/forge/ForgeHermitCabin.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const HARBOR_COAST := preload("res://world/shape/HarborCoast.gd")
const HARBOR_COAST_WOODLAND := preload("res://world/shape/HarborCoastWoodland.gd")
const HARBOR_DRESSING := preload("res://world/urban_detail/HarborAreaDressing3D.gd")
const HARBOR_PROP := preload("res://world/urban_detail/HarborProp3D.gd")
const HARBOR_PUBLIC_REALM := preload("res://world/urban_detail/HarborPublicRealm3D.gd")
const HARBOR_ROAD_GEOMETRY := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const HARBOR_ROUTE_FACTORY := preload("res://world/harbor_route_detail/HarborRouteDetailFactory.gd")
const HARBOR_URBAN_SURFACE := preload("res://world/urban_detail/HarborUrbanSurface3D.gd")
const MOUNTAIN_FACTORY := preload("res://world/mountain_detail/MountainDetailFactory.gd")
const MOUNTAIN_FORGE := preload("res://world/mountain_detail/forge/MountainForge.gd")
const MOUNTAIN_REFUGE := preload("res://world/mountain_detail/MountainRefuge.gd")
const SOUTH_PORT := preload("res://world/regions/OriginalSouthPort.gd")
const SOUTH_PORT_LAYOUT := preload("res://world/regions/OriginalSouthPortLayout.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Geografia da região em etapas, na ordem de antes: registros vindos dos dados (porto ou passo da serra),
## registros comuns e entradas, geometria do porto (vias, superfícies, chão, oceano, costa) e terreno da
## serra. Sem `await`; roda na thread de quem chamou prepare_data (o WorkerThreadPool na carga), como antes.
func _prepare() -> void:
	var records_started := STALL_WORK.begin()
	CITY_DRESSING.invalidate_context(g)
	_prepare_source_records()
	_prepare_shared_records(records_started)
	_prepare_harbor_geometry()
	_prepare_mountain_terrain()

## Etapa 1: registros dos dados de origem. Porto: cemitério, terra extra, porto sul, trilhos, ruas, prédios
## (e os lugares com interior), sucata, Cobra, ponte, props, navio, mesas e contêineres. Serra: o passo
## (curva pelos pontos de controle), os trilhos de serviço, os lugares do catálogo, abrigos e postes.
func _prepare_source_records() -> void:
	if g.region_id == "harbor":
		g._record(CEMETERY.world_position(),{"kind":"cemetery","position":CEMETERY.world_position()})
		g._record(CEMETERY.world_position(),{"kind":"harbor_dressing","zone_id":"cemetery","position":CEMETERY.world_position()})
		for polygon in SOUTH_PORT.extra_surfaces(g.source_data.harbor_land):
			var metric := PackedVector2Array()
			for point in polygon: metric.append(point*g.SCALE)
			g.extra_land.append(metric)
		g.extra_land.append_array(preload("res://world/places/fishing/FishingRuralLayout.gd").extra_surfaces())
		# Mundo orgânico (etapa 3): a faixa entre os retângulos e a costa curva, por último para o chão
		# subtrair a terra de antes.
		g.extra_land.append_array(HARBOR_COAST.natural_land())
		for record in SOUTH_PORT.records(): g._record(record.position,record)
		var south_ship_center: Vector2 = SOUTH_PORT_LAYOUT.SHIP.get_center()*g.SCALE
		g._record(Vector3(south_ship_center.x,0,south_ship_center.y),{"kind":"south_port_ship_detail"})
		for rail in SOUTH_PORT.rails():
			var a := CATALOG._at(rail[0],g.region_id)
			var b := CATALOG._at(rail[1],g.region_id)
			var steps := maxi(1,ceili(a.distance_to(b)/16.0))
			for i in steps:
				var start := a.lerp(b,float(i)/steps)
				var end := a.lerp(b,float(i+1)/steps)
				g._record((start+end)*.5,{"kind":"south_port_rail","a":start,"b":end})
		for row in g.source_data.harbor_roads:
			var points := PackedVector3Array()
			for point in row.points: points.append(CATALOG._at(Vector2(point[0],point[1]),g.region_id))
			g._add_road(row.id,points,float(row.width)*g.SCALE)
		if preload("res://runtime/FishingLocation.gd").enabled():
			var fishing_access := preload("res://world/places/fishing/FishingRuralLayout.gd")
			g._add_road(fishing_access.ROAD_ID,fishing_access.road_points(),preload("res://runtime/FishingLocation.gd").ROAD_WIDTH,"earth")
		for building in g.source_data.harbor_buildings:
			var point := CATALOG._at(Vector2(building.position[0],building.position[1]),g.region_id)
			var size: Vector2 = Vector2(building.size[0],building.size[1])*g.SCALE
			var entry: Dictionary = building.duplicate()
			entry["position"] = point
			entry["size"] = size
			g.buildings.append(entry)
			g._record(point,{"kind":"building","data":entry})
		if not Engine.get_meta("curitiba_cellar_baseline",false):
			var cellar := preload("res://world/places/curitiba_cellar/CuritibaCellarPlace.gd").definition_data()
			var cellar_building := {"id":"CuritibaCellar","position":cellar.exterior_position,"size":cellar.size,"height":4.1,"name":"Curitiba Cellar","kind":"shop"}
			g.buildings.append(cellar_building)
			g._record(cellar.exterior_position,{"kind":"building","data":cellar_building})
		if not Engine.get_meta("arcade_baseline",false):
			var arcade := preload("res://world/places/arcade/ArcadePlace.gd").definition_data()
			var arcade_building := {"id":"Fagulha","position":arcade.exterior_position,"size":arcade.size,"height":3.9,"name":"Fagulha","kind":"shop"}
			g.buildings.append(arcade_building)
			g._record(arcade.exterior_position,{"kind":"building","data":arcade_building})
		if not Engine.get_meta("bars_baseline",false):
			var bar := preload("res://world/places/bars/BarCatalog.gd").definition("harbor_bar")
			var bar_building := {"id":"LastroBar","position":bar.exterior_position,"size":bar.size,"height":3.9,"name":"Lastro","kind":"shop"}
			g.buildings.append(bar_building)
			g._record(bar.exterior_position,{"kind":"building","data":bar_building})
		if not Engine.get_meta("gym_baseline",false):
			var gym := preload("res://world/places/gym/GymPlace.gd").definition_data()
			var gym_building := {"id":"FerroVelhoGym","position":gym.exterior_position,"size":gym.size,"height":3.9,"name":"Ferro Velho","kind":"shop"}
			g.buildings.append(gym_building)
			g._record(gym.exterior_position,{"kind":"building","data":gym_building})
		g._record(CATALOG._at(Vector2(-750,550),g.region_id),{"kind":"salvage","position":CATALOG._at(Vector2(-750,550),g.region_id)})
		g._record(CATALOG._at(Vector2(-750,550),g.region_id),{"kind":"harbor_dressing","zone_id":"salvage","position":CATALOG._at(Vector2(-750,550),g.region_id)})
		g._record(CATALOG._at(Vector2(7700,1700),g.region_id),{"kind":"harbor_dressing","zone_id":"cobra","position":CATALOG._at(Vector2(7700,1700),g.region_id)})
		g._record(CATALOG._at(Vector2(3790,400),g.region_id),{"kind":"harbor_bridge","position":CATALOG._at(Vector2(3790,400),g.region_id)})
		for prop_data in HARBOR_PROP.records():
			var prop_position:=CATALOG._at(prop_data.point,g.region_id)
			g._record(prop_position,{"kind":"harbor_prop","position":prop_position,"data":prop_data})
		g._record(CATALOG._at(Vector2(3570,1400),g.region_id),{"kind":"ship"})
		# A 2ª mesa da Anchor (685,1132) e a da Early Shift (6255,-1238) ficavam na frente das portas da
		# Corner Diner e da Service Cafe e travavam a entrada (test_door_audit, 18/10); foram para o lado.
		for venue in [
			["anchor",Color("b96a46"),Vector2(555,1132),Vector2(615,1140)],
			["tideline",Color("477f7d"),Vector2(5735,1644),Vector2(5845,1644)],
			["early_shift",Color("68784a"),Vector2(6145,-1238),Vector2(6200,-1250)]]:
			for table_index in 2:
				var table_position := CATALOG._at(venue[2+table_index],g.region_id)
				g._record(table_position,{"kind":"harbor_restaurant","venue_id":venue[0],"fabric":venue[1],"table_index":table_index,"position":table_position})
		for container in g.source_data.port_containers:
			var point := CATALOG._at(Vector2(container.position[0],container.position[1]),g.region_id)
			g._record(point,{"kind":"container","position":point,"size":Vector2(container.size[0],container.size[1])*g.SCALE})
	else:
		var controls := PackedVector2Array()
		for point in g.source_data.mountain_control_points: controls.append(Vector2(point[0],point[1]))
		var curve := Curve2D.new()
		curve.bake_interval = 16
		for i in controls.size():
			var tangent := Vector2.ZERO
			if i > 0 and i < controls.size()-1: tangent = (controls[i+1]-controls[i-1]).normalized()*minf(controls[i-1].distance_to(controls[i]),controls[i+1].distance_to(controls[i]))*.38
			curve.add_point(controls[i],-tangent,tangent)
		var points := PackedVector3Array()
		for distance in range(0,int(curve.get_baked_length()),64): points.append(CATALOG._at(curve.sample_baked(distance,true),g.region_id))
		points.append(CATALOG._at(controls[-1],g.region_id))
		g._add_road("mountain_pass",points,140*g.SCALE)
		# Os trilhos de serviço encontram o passo na linha central autorada; o leito de terra é
		# recortado visualmente na borda do asfalto quando o primeiro segmento é montado.
		for track in [
			[Vector2(6250,340),Vector2(6850,690),Vector2(7350,620),Vector2(7850,580),Vector2(8350,480),Vector2(8700,460)],
			[Vector2(6950,-250),Vector2(7150,-350),Vector2(7450,-320),Vector2(7750,-220)],
			[Vector2(6120,320),Vector2(6040,100),Vector2(6060,-150),Vector2(6200,-320)],
			[Vector2(6850,-2450),Vector2(7020,-2500),Vector2(7140,-2545),Vector2(7140,-2700)],
			[Vector2(6901,-1566),Vector2(6840,-1740),Vector2(7010,-1870),Vector2(7240,-1760),Vector2(7500,-1760),Vector2(7700,-1760),Vector2(7790,-1850),Vector2(7700,-1940)]
		]:
			var branch := PackedVector3Array()
			for point in track: branch.append(CATALOG._at(point,g.region_id))
			g._add_road("mountain_track_%d"%g.roads.size(),branch,60*g.SCALE if g.roads.size()==1 else 3.25,"earth" if g.roads.size()==1 else "asphalt")
		for definition in CATALOG.definitions():
			if definition.region == g.region_id: g._record(definition.exterior_position,{"kind":"mountain_place","data":definition})
		# Three physical entrances share the bunkhouse interior, never their return origin.
		for index in 2:
			var shelter := CATALOG.get_definition("lumberjack_shelter")
			shelter["access_id"] = "lumberjack_shelter_%d" % (index + 2)
			shelter.exterior_position = CATALOG.shelter_access_exterior(index)
			g._record(shelter.exterior_position, {"kind":"mountain_place", "data":shelter})
		for lamp_point in [Vector2(6340,500),Vector2(6910,755),Vector2(7140,-455)]:
			var lamp_position := CATALOG._at(lamp_point,g.region_id)
			g._record(lamp_position,{"kind":"mountain_road_lamp","position":lamp_position})

## Etapa 2: fachadas originais, zonas e espaço público do porto; lagos, avião, serraria, vila, forja,
## eremita, refúgio, registros ambientais, floresta e rotas revistas da serra; entradas. Fecha o span
## dos registros aberto em _prepare.
func _prepare_shared_records(records_started: int) -> void:
	if g.region_id == "harbor":
		for definition in CATALOG.definitions():
			if definition.region == g.region_id and definition.id in ["westgate_garden","quayside_house","cemetery_keeper","port_boss_garage"] + CATALOG.SEWERS.ids(): g._record(definition.exterior_position,{"kind":"original_facade","data":definition})
		for zone_record in HARBOR_ROUTE_FACTORY.get_zone_records():
			g._record(zone_record.position, zone_record)
		for public_record in HARBOR_PUBLIC_REALM.records():
			var public_position := CATALOG._at(public_record.point, g.region_id)
			g._record(public_position, {"kind":"harbor_public_realm", "zone_id":public_record.zone_id, "position":public_position})
	if g.region_id == "mountain":
		for lake in [["secret",Vector2(5450,-1150)],["alpine",Vector2(7000,0)]]:
			g._record(CATALOG._at(lake[1],g.region_id),{"kind":"lake","variant":lake[0],"position":CATALOG._at(lake[1],g.region_id)})
		g._record(CATALOG._at(Vector2(5450,-1150),g.region_id),{"kind":"cargo_plane","position":CATALOG._at(Vector2(5450,-1150),g.region_id)})
		g._record(CATALOG._at(Vector2(6350,560),g.region_id),{"kind":"sawmill_yard"})
		g._record(CATALOG._at(Vector2(7560,-1650),g.region_id),{"kind":"mountain_village"})
		g._record(MOUNTAIN_FORGE.CENTER,{"kind":"mountain_forge","position":MOUNTAIN_FORGE.CENTER})
		g._record(FORGE_HERMIT.CENTER,{"kind":"forge_hermit_cabin","position":FORGE_HERMIT.CENTER})
		g._record(MOUNTAIN_REFUGE.CENTER,{"kind":"mountain_refuge","position":MOUNTAIN_REFUGE.CENTER})
		for record in MOUNTAIN_FACTORY.get_environmental_records():
			g._record(record.position,record)
		g._prepare_forest()
		g._revise_mountain_routes()
	for entry in CATALOG.access_points():
		if entry.region == g.region_id: g.entries.append(entry)
	STALL_WORK.finish("region.prepare.records." + g.region_id, records_started, {})

## Etapa 3 (só o porto): geometria das vias, superfícies urbanas, chão das fachadas e do dressing, oceano,
## proteção costeira e mata da costa, cada uma com o seu span.
func _prepare_harbor_geometry() -> void:
	if g.region_id == "harbor":
		g.harbor_road_geometry = HARBOR_ROAD_GEOMETRY.new()
		var geometry_started := STALL_WORK.begin()
		g.harbor_road_geometry.configure(g.roads)
		STALL_WORK.finish("region.prepare.roads", geometry_started, {})
		g.harbor_urban_surface = HARBOR_URBAN_SURFACE.new()
		geometry_started = STALL_WORK.begin()
		g.harbor_urban_surface.configure()
		STALL_WORK.finish("region.prepare.urban_surfaces", geometry_started, {})
		geometry_started = STALL_WORK.begin()
		g.harbor_facade_ground = preload("res://world/urban_detail/HarborFacadeGround.gd").footprints()
		g.harbor_dressing_ground.clear()
		for cell_records in g.records.values():
			for record in cell_records:
				if record.get("kind","") == "harbor_dressing":
					var origin: Vector3 = record.position
					g.harbor_dressing_ground.append_array(HARBOR_DRESSING.ground_footprints(record.zone_id,Vector2(origin.x,origin.z)))
		g.harbor_ocean = preload("res://world/regions/HarborOcean.gd").new()
		STALL_WORK.finish("region.prepare.footprints", geometry_started, {})
		geometry_started = STALL_WORK.begin()
		g.harbor_ocean.configure(g.source_data.harbor_land,g.extra_land)
		STALL_WORK.finish("region.prepare.ocean", geometry_started, {})
		g.coastal_protection = preload("res://world/regions/CoastalProtection.gd").new()
		geometry_started = STALL_WORK.begin()
		g.coastal_protection.configure(g.source_data,g.extra_land,g.harbor_road_geometry._layers[0].polygons)
		STALL_WORK.finish("region.prepare.coast", geometry_started, {})
		if not HARBOR_COAST.natural_land().is_empty():
			geometry_started = STALL_WORK.begin()
			var old_land: Array[PackedVector2Array] = []
			for row in g.source_data.harbor_land: old_land.append(GROUND_CUT.rect_polygon(Rect2(row[0]*g.SCALE,row[1]*g.SCALE,row[2]*g.SCALE,row[3]*g.SCALE)))
			for polygon in g.extra_land:
				if not HARBOR_COAST.is_natural(polygon): old_land.append(polygon)
			HARBOR_COAST_WOODLAND.prepare(old_land,g.harbor_road_geometry._layers[0].polygons)
			STALL_WORK.finish("region.prepare.coast_woodland", geometry_started, {})

## Etapa 4 (só a serra): terreno com reservas, clareiras e as avenidas do porto que entram na encosta.
func _prepare_mountain_terrain() -> void:
	if g.region_id == "mountain":
		g.terrain = TERRAIN.new()
		var reservations: Array = CATALOG.definitions().duplicate()
		reservations.append_array(g.entries)
		var terrain_roads: Array[Dictionary] = g.roads + g.walkways
		var site_clearings: Array = g._mountain_site_terrain(terrain_roads)
		# Estas rotas do Harbor entram no terreno residente da Mountain no portal
		# da margem norte. Reserva a pista autorada para a malha/colisor da encosta
		# não subir na aproximação enquanto as duas regiões estão carregadas.
		for avenue in g.source_data.harbor_roads:
			if avenue.id not in ["northbank_gateway_avenue","eastgate_drive","map2_highway_outbound"]: continue
			var avenue_points := PackedVector3Array()
			for point in avenue.points:
				avenue_points.append(CATALOG._at(Vector2(point[0],point[1]),"harbor"))
			terrain_roads.append({"id":avenue.id,"points":avenue_points,"width":float(avenue.width)*g.SCALE})
		g.terrain.configure(terrain_roads,reservations,site_clearings)
