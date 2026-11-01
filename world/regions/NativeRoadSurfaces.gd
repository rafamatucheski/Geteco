extends RefCounted
## Superfícies de rua do chunk (asfalto/terra, acostamento macio da serra), recorte de retângulos e o
## estágio fatiado das superfícies do Harbor (`_harbor_surfaces_step`/`_harbor_surface_substep`),
## separados do NativeRegion em 01/11 só para ele caber na leitura. O estado (harbor_road_geometry,
## source_data, extra_land, o `state` do job...) continua no NativeRegion, que mantém cada função
## antiga como delegação de uma linha com a mesma assinatura; testes que sobrescrevem `_build_surfaces`
## numa subclasse não passam por aqui e continuam iguais.
## `g` fica como Node3D, e não como o script do NativeRegion, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.` (`g._harbor_surface_substep`,
## `g._rect_outside`, `g._land_piece`...): se uma subclasse sobrescrever alguma, o despacho não muda.
## Os spans `stream.harbor.surfaces.<passo>` e a ordem dos passos são os mesmos. Roda só na thread
## principal (o WorkerThreadPool do terreno da serra fica no NativeRegion e não toca nisto).
## HARBOR_SURFACE_STEPS/HARBOR_SURFACE_STEP_NAMES e SCALE continuam constantes do NativeRegion (lidas por `g.`).

const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const HARBOR_ROAD_GEOMETRY := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const NATURAL_GROUND := preload("res://world/regions/natural_ground_edge.gdshader")
const ROUTE_GEOMETRY := preload("res://world/mountain_detail/MountainRouteGeometry.gd")
const SOUTH_PORT_LAYOUT := preload("res://world/regions/OriginalSouthPortLayout.gd")
const CEMETERY := preload("res://world/regions/OriginalCemetery3D.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const HARBOR_COAST := preload("res://world/shape/HarborCoast.gd")
const HARBOR_COAST_WOODLAND := preload("res://world/shape/HarborCoastWoodland.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _build_road_surfaces(chunk: Node3D, rect: Rect2) -> void:
	var rows: Array = chunk.get_meta("road_surface_rows",[])
	if rows.is_empty(): return
	var by_color: Dictionary = {}
	for row in rows:
		var color: Color = row.color
		if not by_color.has(color): by_color[color] = PackedVector3Array()
		var vertices: PackedVector3Array = by_color[color]
		var y: float = row.top
		var polygon: PackedVector2Array = row.polygon
		for index in Geometry2D.triangulate_polygon(polygon):
			var point := polygon[index]
			vertices.append(Vector3(point.x,y,point.y))
		by_color[color] = vertices
	for color in by_color:
		if by_color[color].is_empty(): continue
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for vertex in by_color[color]:
			surface.set_uv(Vector2(vertex.x, vertex.z) / 4.0)
			surface.add_vertex(vertex)
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "RoadSurface"
		mesh.set_meta("vehicle_surface", "hard" if color == HARBOR_ROAD_GEOMETRY.ROAD_COLOR else "dirt")
		mesh.mesh = surface.commit()
		if color == HARBOR_ROAD_GEOMETRY.ROAD_COLOR:
			if g.harbor_road_geometry == null: g.harbor_road_geometry = HARBOR_ROAD_GEOMETRY.new()
			var unified_bridge := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
			mesh.material_override = unified_bridge.material("asphalt") if unified_bridge.enabled() else g.harbor_road_geometry._material(color)
		else:
			# Estrada de terra ganha o mesmo chão procedural das peças do editor.
			var dirt := ShaderMaterial.new()
			dirt.shader = NATURAL_GROUND
			dirt.set_shader_parameter("base_color",color)
			dirt.set_shader_parameter("uv_meters",4.0)
			dirt.set_shader_parameter("base_color",Color("5d4e3d"))
			dirt.set_shader_parameter("surface_softness",.6)
			mesh.material_override = dirt
			mesh.set_instance_shader_parameter("uv_origin",(Vector2(by_color[color][0].x,by_color[color][0].z)/256.0).floor()*64.0)
			# Preserva exatamente o apoio autorado; troca só o recorte duro
			# por um acostamento visual mais largo que se dissolve no chão real.
			mesh.hide()
			if g.terrain == null: g._build_soft_road_surface(chunk,rect,dirt)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(mesh)
		# O apoio usa o mesmo contorno da superfície, na altura do terreno.
		mesh.create_trimesh_collision()
		mesh.get_child(0).position.y = -.026
	chunk.remove_meta("road_surface_rows")

func _build_soft_road_surface(chunk: Node3D, rect: Rect2, material: ShaderMaterial) -> void:
	const SHOULDER := 1.4
	var boundary := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var paved: Dictionary = {}
	for road in g.roads+g.walkways:
		if road.get("surface","asphalt") == "asphalt": paved[road.id] = true
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	var first := Vector2.ZERO
	for road in g.roads+g.walkways:
		if road.get("surface","asphalt") == "asphalt": continue
		var points: PackedVector3Array = road.points
		var reach: float = float(road.width)*.5+SHOULDER
		var edges := ROUTE_GEOMETRY.edges(points,float(road.width)+SHOULDER*2.0)
		for index in range(edges.size()-1):
			var shape := ROUTE_GEOMETRY.polygon(edges[index].left,edges[index+1].left,edges[index+1].right,edges[index].right)
			if not ROUTE_GEOMETRY.bounds(shape).intersects(rect): continue
			var pieces: Array[PackedVector2Array] = []
			for part in Geometry2D.intersect_polygons(shape,boundary): pieces.append(part)
			# Nunca pinta solo solto sobre uma faixa de asfalto nem sobre a borda intencional dela.
			for footprint in g.route_geometry.footprints:
				if not paved.has(footprint.id) or not footprint.bounds.intersects(rect): continue
				var remaining: Array[PackedVector2Array] = []
				for piece in pieces:
					for part in Geometry2D.clip_polygons(piece,footprint.polygon):
						if part.size()>=3: remaining.append(part)
				pieces = remaining
			for piece in pieces:
				if Geometry2D.is_polygon_clockwise(piece): piece.reverse()
				# Triangulate first: clipping a winding asphalt edge can leave a
				# concave piece. Mid-edge samples retain the opaque path axis.
				var triangles := Geometry2D.triangulate_polygon(piece)
				var samples := PackedVector2Array()
				for triangle in range(0,triangles.size(),3):
					var a := piece[triangles[triangle]]
					var b := piece[triangles[triangle+1]]
					var c := piece[triangles[triangle+2]]
					var ab := (a+b)*.5
					var bc := (b+c)*.5
					var ca := (c+a)*.5
					samples.append_array(PackedVector2Array([a,ab,ca,ab,b,bc,ca,bc,c,ab,bc,ca]))
				for point in samples:
					var distance := INF
					for segment in range(points.size()-1):
						var a := Vector2(points[segment].x,points[segment].z)
						var b := Vector2(points[segment+1].x,points[segment+1].z)
						distance = minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)))
					var alpha := clampf(1.0-distance/reach,0.0,1.0)
					surface.set_normal(Vector3.UP)
					surface.set_uv(point/4.0)
					surface.set_color(Color(1,1,1,alpha))
					surface.add_vertex(Vector3(point.x,.026,point.y))
					if count == 0: first = point
					count += 1
	if count == 0: return
	var soft := MeshInstance3D.new()
	soft.name = "SoftMountainTrail"
	soft.mesh = surface.commit()
	material.set_shader_parameter("edge_alpha",true)
	soft.material_override = material
	soft.set_instance_shader_parameter("uv_origin",(first/256.0).floor()*64.0)
	soft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(soft)

## O cemitério fornece o próprio piso e colisão em y=0. O terreno do Harbor tem
## a mesma face de cima ali; desenhar os dois causa briga de profundidade e luz piscando.
## `_rect_outside` contra vários recortes (os bueiros), peça a peça.
func _rects_outside_all(rect: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var pieces: Array[Rect2] = [rect]
	for hole in holes:
		var next: Array[Rect2] = []
		for piece in pieces: next.append_array(g._rect_outside(piece, hole))
		pieces = next
	return pieces

func _rect_outside(surface: Rect2, hole: Rect2) -> Array[Rect2]:
	if not surface.has_area(): return []
	var overlap := surface.intersection(hole)
	if not overlap.has_area(): return [surface]
	var pieces: Array[Rect2] = []
	if overlap.position.y > surface.position.y:
		pieces.append(Rect2(surface.position, Vector2(surface.size.x, overlap.position.y - surface.position.y)))
	if overlap.end.y < surface.end.y:
		pieces.append(Rect2(Vector2(surface.position.x, overlap.end.y), Vector2(surface.size.x, surface.end.y - overlap.end.y)))
	if overlap.position.x > surface.position.x:
		pieces.append(Rect2(Vector2(surface.position.x, overlap.position.y), Vector2(overlap.position.x - surface.position.x, overlap.size.y)))
	if overlap.end.x < surface.end.x:
		pieces.append(Rect2(Vector2(overlap.end.x, overlap.position.y), Vector2(surface.end.x - overlap.end.x, overlap.size.y)))
	return pieces

## Um passo por vez até o orçamento (pelo menos um por chamada). Devolve true ao terminar o estágio.
## Cada passo tem span próprio (`stream.harbor.surfaces.<passo>`): se um passo sozinho passar de ~2 ms,
## o próximo log diz qual.
func _harbor_surfaces_step(state: Dictionary, budget_usec: float, began: int) -> bool:
	var unbounded := budget_usec <= 0.0 or is_inf(budget_usec)
	while int(state.step) < g.HARBOR_SURFACE_STEPS:
		var step := int(state.step)
		var step_began := STALL_WORK.begin()
		var advanced: bool = g._harbor_surface_substep(state)
		STALL_WORK.finish_slow("stream.harbor.surfaces.%s"%g.HARBOR_SURFACE_STEP_NAMES[step],step_began,2000)
		if advanced: state.step = step+1
		if not unbounded and Time.get_ticks_usec()-began >= budget_usec: break
	return int(state.step) >= g.HARBOR_SURFACE_STEPS

## Corpo do antigo _build_surfaces do Harbor, cortado nos mesmos pontos. Devolve true quando o passo
## atual acabou; "land" e "extra_land" devolvem false enquanto ainda há pedaço/polígono na fila.
func _harbor_surface_substep(state: Dictionary) -> bool:
	var chunk: Node3D = state.chunk
	var rect: Rect2 = state.rect
	match int(state.step):
		0:
			# Uma camada de chão só (2026-10-13): quem está por cima é montado primeiro e quem fica por baixo
			# perde a área coberta. Ruas > lotes e concreto do porto > chão base (Land).
			var ground_cover: Array[PackedVector2Array] = []
			if g.harbor_road_geometry != null:
				g.harbor_road_geometry.build_chunk(chunk,rect)
				ground_cover.append_array(g.harbor_road_geometry.chunk_cover)
				# A faixa opaca de terra para grama já fornece o próprio acabamento.
				# Reserva só os triângulos recortados reais, nunca a caixa envolvente deles.
				var chunk_outline := GROUND_CUT.rect_polygon(rect)
				for triangle in g.harbor_road_geometry._earth_verge_triangles:
					if not GROUND_CUT.bounds(triangle.points).intersects(rect): continue
					ground_cover.append_array(Geometry2D.intersect_polygons(triangle.points,chunk_outline))
			state.ground_cover = ground_cover
		1:
			var ground_cover: Array[PackedVector2Array] = state.ground_cover
			for footprint in g.harbor_facade_ground:
				if GROUND_CUT.bounds(footprint).intersects(rect): ground_cover.append(footprint)
			for footprint in g.harbor_dressing_ground:
				if GROUND_CUT.bounds(footprint).intersects(rect): ground_cover.append(footprint)
			# O Santa Mare é dono do convés visível. O terreno e as superfícies autoradas mantêm os
			# colisores, mas não podem renderizar um segundo piso embaixo do navio.
			var santa_deck := PackedVector2Array()
			for point in SOUTH_PORT_LAYOUT.ship_hull(): santa_deck.append(point*g.SCALE)
			if GROUND_CUT.bounds(santa_deck).intersects(rect): ground_cover.append(santa_deck)
			for footprint in CEMETERY.path_footprints(CEMETERY.SOURCE_CENTER*g.SCALE):
				if GROUND_CUT.bounds(footprint).intersects(rect): ground_cover.append(footprint)
			if g.harbor_urban_surface != null:
				for lot in g.harbor_urban_surface.build_chunk(chunk,rect,ground_cover): ground_cover.append(GROUND_CUT.rect_polygon(lot))
			var port_land := Rect2(SOUTH_PORT_LAYOUT.LAND.position*g.SCALE,SOUTH_PORT_LAYOUT.LAND.size*g.SCALE)
			var port_surface := rect.intersection(port_land)
			state.port_surface = port_surface
			state.port_cover = ground_cover.duplicate()
			if port_surface.has_area(): ground_cover.append(GROUND_CUT.rect_polygon(port_surface))
			g._place_ground_cut(chunk,rect,ground_cover)
			var cemetery_half: Vector2 = CEMETERY.LOT_SIZE * g.SCALE * 0.5
			state.cemetery_floor = Rect2(CEMETERY.SOURCE_CENTER * g.SCALE - cemetery_half, cemetery_half * 2.0)
			var sewer_openings: Array[Rect2] = []
			for opening in CATALOG.sewer_openings(): sewer_openings.append(Rect2(opening.position * g.SCALE, opening.size * g.SCALE))
			state.sewer_openings = sewer_openings
			var owned_land: Array[Rect2] = []
			state.owned_land = owned_land
			state.land_index = 0
			var land_queue: Array[Rect2] = []
			state.land_queue = land_queue
		2:
			# Um pedaço de Land por vez (trimesh + recorte visual em _land_piece). Os pedaços de cada
			# retângulo saem da mesma conta de antes; owned_land só cresce depois de enfileirá-los.
			var ground_cover: Array[PackedVector2Array] = state.ground_cover
			var land_queue: Array[Rect2] = state.land_queue
			if not land_queue.is_empty():
				g._land_piece(chunk,land_queue.pop_front(),ground_cover)
				return false
			var land_index := int(state.land_index)
			if land_index >= g.source_data.harbor_land.size(): return true
			state.land_index = land_index+1
			var owned_land: Array[Rect2] = state.owned_land
			var sewer_openings: Array[Rect2] = state.sewer_openings
			var secret_cellar_opening := Rect2(-413.25,85.35,6.10,3.30)
			var land = g.source_data.harbor_land[land_index]
			var surface := rect.intersection(Rect2(land[0]*g.SCALE,land[1]*g.SCALE,land[2]*g.SCALE,land[3]*g.SCALE))
			var land_holes: Array[Rect2] = owned_land.duplicate()
			land_holes.append(state.cemetery_floor)
			for piece in g._rects_outside_all(surface,land_holes):
				for sewer_piece in g._rects_outside_all(piece, sewer_openings):
					for cellar_piece in g._rect_outside(sewer_piece, secret_cellar_opening):
						# Rampas e trechos cobertos do Túnel do canal têm piso e laje próprios.
						for land_piece in CANAL_TUNNEL.outside_land(cellar_piece):
							for skate_piece in preload("res://activities/skate/SkateParkLayout.gd").outside(land_piece):
								land_queue.append(skate_piece)
			if surface.has_area(): owned_land.append(surface)
			return false
		3:
			g.harbor_ocean.build_chunk(chunk,rect)
		4:
			CANAL_TUNNEL.build_chunk(chunk,rect)
			var skate_center := preload("res://activities/skate/SkateParkLayout.gd").CENTER
			if preload("res://activities/skate/SkateParkLayout.gd").enabled() and rect.has_point(Vector2(skate_center.x, skate_center.z)):
				chunk.add_child(preload("res://activities/skate/SkatePark.gd").new())
		5:
			g.coastal_protection.build_chunk(chunk,rect)
		6:
			# Um polígono de extra_land por vez; extra_support cresce na mesma ordem de antes.
			if not state.has("extra_support"):
				var extra_support: Array[PackedVector2Array] = []
				for land_rect in state.owned_land: extra_support.append(GROUND_CUT.rect_polygon(land_rect))
				state.extra_support = extra_support
				state.extra_index = 0
			var extra_index := int(state.extra_index)
			if extra_index >= g.extra_land.size(): return true
			state.extra_index = extra_index+1
			var support: Array[PackedVector2Array] = state.extra_support
			var ground_cover: Array[PackedVector2Array] = state.ground_cover
			var clip := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
			var polygon: PackedVector2Array = g.extra_land[extra_index]
			var woodland: bool = polygon==preload("res://world/places/fishing/FishingRuralLayout.gd").outline() or HARBOR_COAST.is_natural(polygon)
			var pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(polygon,clip)
			for piece in GROUND_CUT.subtract_exact(pieces,support): g._authored_surface(chunk,piece,woodland,ground_cover)
			support.append(polygon)
			return extra_index+1 >= g.extra_land.size()
		7:
			preload("res://world/places/fishing/FishingWoodland.gd").build_chunk(chunk,rect)
		8:
			HARBOR_COAST_WOODLAND.build_chunk(chunk,rect)
		9:
			var port_surface: Rect2 = state.port_surface
			if port_surface.has_area():
				# Só acabamento visual: OriginalSouthPort/terreno já são donos do apoio físico.
				# Mantém o pátio abaixo de todo acabamento de rua. O antigo topo de .014 era
				# exatamente coplanar com CURB_COLOR, causando cintilação ao longo das ruas.
				# Sem a área das ruas: antes o concreto inteiro ficava por baixo delas.
				var apron_mesh := GROUND_CUT.flat_mesh(GROUND_CUT.subtract([GROUND_CUT.rect_polygon(port_surface)],state.port_cover),.004,1.0)
				if apron_mesh != null:
					var apron := MeshInstance3D.new()
					apron.name = "SouthPortConcrete"
					apron.mesh = apron_mesh
					apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					apron.material_override = preload("res://world/regions/PortYardMaterials3D.gd").concrete()
					chunk.add_child(apron)
	return true
