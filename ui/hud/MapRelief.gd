extends RefCounted
## Relevo cartográfico retido: só malhas 2D, polígonos e lotes de linha.
## Alturas/pegadas vêm dos dados de produção. Nenhuma região é montada, nenhuma
## física é criada e nenhuma coordenada de navegação é movida para a apresentação.
const DESERT := preload("res://world/desert/DesertLayout.gd")
const HORIZON := preload("res://world/desert/DesertHorizonRelief.gd")
const CANYON := preload("res://world/desert/DesertTerrainRelief.gd")
const GORGE := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const MINING := preload("res://world/mining/MiningLayout.gd")
const LANDFORMS := preload("res://world/desert/expansion/DesertLandforms.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const PALETTE := {"city":Color("414641"),"forest":Color("36433b"),"mountain":Color("515957"),"desert":Color("82765e"),"water":Color("16262a")}
const LIGHT := Vector3(-.55,.72,-.42)
# Estes são os perfis de horizonte escritos em DesertHorizonRelief.build(). O
# mesmo amostrador de produção abaixo fornece a pegada erodida e as normais deles.
const RANGES := [
	{"side":"north","from":DESERT.BOUNDS.position.x-220.0,"to":DESERT.BOUNDS.end.x+240.0,"width":360.0,"seed":73,"profile":[Vector2(0,.05),Vector2(.055,.30),Vector2(.10,.86),Vector2(.20,.89),Vector2(.24,.38),Vector2(.32,.31),Vector2(.36,.73),Vector2(.46,.77),Vector2(.50,.36),Vector2(.58,.40),Vector2(.62,.94),Vector2(.75,.91),Vector2(.80,.51),Vector2(.88,.56),Vector2(.94,.22),Vector2(1,.06)]},
	{"side":"west","from":DESERT.BOUNDS.position.y-250.0,"to":DESERT.BOUNDS.end.y+68.5,"width":310.0,"seed":29,"profile":[Vector2(0,.06),Vector2(.10,.44),Vector2(.21,.92),Vector2(.28,.72),Vector2(.42,.33),Vector2(.53,.67),Vector2(.65,.91),Vector2(.78,.36),Vector2(.90,.68),Vector2(1,.04)]},
	{"side":"south","from":DESERT.BOUNDS.position.x-190.0,"to":90.0,"width":210.0,"seed":97,"profile":[Vector2(0,.03),Vector2(.10,.66),Vector2(.21,.38),Vector2(.35,.89),Vector2(.41,.76),Vector2(.55,.29),Vector2(.69,.68),Vector2(.82,.42),Vector2(.92,.30),Vector2(1,.02)]},
]
var visual_bounds := Rect2()
var region_visual_bounds := {}
var _commands: Array[Dictionary]=[]
var _line_batches: Array[Dictionary]=[]
var _water: Array[PackedVector2Array]=[]
var _desert_visual_bounds := Rect2()
var triangle_count := 0
var preparation_usec := 0

func prepare(lands: Array, regions: Dictionary, navigation_bounds: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	_commands.clear(); _line_batches.clear(); _water.clear()
	triangle_count=0; region_visual_bounds=navigation_bounds.duplicate(); visual_bounds=Rect2()
	_desert_visual_bounds=DESERT.BOUNDS
	for land in lands:
		if land.biome=="water" and land.polygon.size()>2: _water.append(land.polygon)
	var first := true
	var land_extents := {}
	for land in lands:
		var polygon: PackedVector2Array=land.polygon
		if polygon.size()<3: continue
		var extent := _bounds(polygon)
		var region_id: String={"city":"harbor","forest":"harbor","mountain":"mountain","desert":"desert"}.get(land.biome,"")
		if not region_id.is_empty():
			land_extents[region_id]=land_extents[region_id].merge(extent) if land_extents.has(region_id) else extent
			region_visual_bounds[region_id]=land_extents[region_id]
		visual_bounds=extent if first else visual_bounds.merge(extent); first=false
	if regions.has("desert") and regions.desert is Node:
		_desert_relief(lands)
	# As cristas exteriores contextuais ficam atrás das pegadas jogáveis escritas do
	# Harbor e da montanha. A silhueta delas não pode cobrir outra região.
	for land in _presentation_lands(lands):
		var polygon: PackedVector2Array=land.polygon
		if polygon.size()<3 or land.biome in ["water","desert"]: continue
		var extent := _bounds(polygon)
		# A ilha da forma do mundo já é costa de verdade: sem o envoltório que disfarçava o corte das células.
		if not land.get("shape",false): _context_envelope(polygon,str(land.biome))
		if land.biome=="mountain" and regions.has("mountain") and regions.mountain is Node:
			var terrain: Variant=regions.mountain.get("terrain")
			if terrain!=null:
				# _calculate_height é o amostrador de produção só de leitura; ao contrário de
				# height_at, não mexe no cache de alturas do streaming do jogo.
				_height_patch(extent,8.0,terrain._calculate_height,"mountain",polygon,1.5)
		elif land.biome in ["city","forest"]:
			_height_patch(extent,12.0,_flat_height,str(land.biome),polygon,0.0)
		else:
			_polygon(polygon,PALETTE.get(land.biome,PALETTE.city))
	for id in ["harbor","mountain"]:
		if regions.has(id) and regions[id] is Node: _tree_canopies(regions[id],id)
	# Lagos cobrem facetas e curvas do terreno mas não mudam nenhum registro de terra.
	for polygon in _water:
		_polygon(polygon,PALETTE.water)
		_closed_line(polygon,Color("6a7874"),.8)
	preparation_usec=Time.get_ticks_usec()-started

func draw_terrain(target: CanvasItem) -> void:
	for command in _commands:
		if command.has("mesh"): target.draw_mesh(command.mesh,null,Transform2D.IDENTITY)
		else: target.draw_colored_polygon(command.polygon,command.color)


func draw_lines(target: CanvasItem, scale_value: float) -> void:
	var factor := maxf(scale_value,.001)
	for batch in _line_batches:
		if factor<float(batch.get("min_scale",0.0)): continue
		target.draw_multiline(batch.points,batch.color,float(batch.width)/factor,true)


func _desert_relief(lands: Array = []) -> void:
	# Mundo orgânico (etapa 5): com a ilha da forma do mundo, a terra é ela, com borda curta de costa.
	for land in lands:
		if land.biome == "desert" and land.get("shape", false):
			_soft_polygon(land.polygon, PALETTE.desert, 6.0)
			_desert_visual_bounds = _bounds(land.polygon).grow(36.0)
			visual_bounds = visual_bounds.merge(_desert_visual_bounds)
			_desert_detail()
			return
	# Uma base geológica contínua inclui a bacia jogável inteira e as
	# cordilheiras exteriores escritas. Só o LADO DE FORA dessa união se dissolve em tinta.
	# Não há fronteira de transparência na extensão retangular do runtime.
	var outline := _rectangle(DESERT.BOUNDS)
	for definition in RANGES:
		var footprint := _range_footprint(definition,definition.side in ["north","west"])
		var merged: Array[PackedVector2Array]=Geometry2D.merge_polygons(outline,footprint)
		if merged.size()==1: outline=merged[0]
	_soft_polygon(outline,PALETTE.desert,105.0)
	_desert_visual_bounds=_bounds(outline).grow(105.0)
	visual_bounds=visual_bounds.merge(_desert_visual_bounds)
	_desert_detail()

## Cordilheiras, cânion, cava e formações: o mesmo com o retângulo antigo ou com a ilha.
func _desert_detail() -> void:
	for distant in [true,false]:
		for definition in RANGES:
			if distant and definition.side not in ["north","west"]: continue
			_horizon_mesh(definition,distant)
	_height_patch(CANYON.BOUNDS,12.0,CANYON.height_at,"sand",PackedVector2Array(),8.0)
	if MINING.enabled():
		_height_patch(MINING.BOUNDS,6.0,_mining_height,"quarry",PackedVector2Array(),7.0)
	if GORGE.enabled():
		_height_patch(GORGE.BOUNDS,6.0,GORGE.analytic_height,"gorge",PackedVector2Array(),12.0)
	_landforms()
	# As pegadas mostradas aqui pertencem a formas de relevo visíveis, não a ruas inventadas.
	for location in LANDFORMS.locations():
		if location.kind in ["dunes","dry_wash","salt_flat"]: continue
		var at := Vector2(location.position.x,location.position.z)
		var radius := Vector2(14,8) if location.kind=="natural_arch" else Vector2(5,4)
		_polygon(LANDFORMS._oval(at+Vector2(3,3),radius*1.2,.2,true),Color("4b493c"))
		_polygon(LANDFORMS._oval(at,radius,.2,true),Color("a38d69"))

func _mining_height(point: Vector2) -> float:
	return MINING.terrain_height(point-Vector2(MINING.CENTER.x,MINING.CENTER.z))

func _horizon_mesh(definition: Dictionary, distant: bool) -> void:
	var buffer := HORIZON._buffer()
	HORIZON._ridge(buffer,definition,distant)
	var vertices: PackedVector3Array=buffer.vertices
	var normals: PackedVector3Array=buffer.normals
	var flat := PackedVector3Array()
	var colors := PackedColorArray()
	for i in vertices.size():
		var p := vertices[i]
		flat.append(Vector3(p.x,p.z,0))
		var crest := smoothstep(1.0,65.0,p.y)
		var base: Color=PALETTE.desert.lerp(Color("57584d"),crest)
		var shade := clampf(.62+normals[i].dot(LIGHT)*.42,.40,1.04)
		var strata := .97+.03*sin(p.y*.40)
		var color := base*shade*strata
		if distant: color=color.lerp(Color("1b2424"),.43)
		color.a=smoothstep(-.6,22.0,p.y)*(.75 if distant else .94)
		colors.append(color)
		visual_bounds=visual_bounds.expand(Vector2(p.x,p.z))
		_desert_visual_bounds=_desert_visual_bounds.expand(Vector2(p.x,p.z))
	_mesh(flat,colors)
	region_visual_bounds.desert=_desert_visual_bounds

func _flat_height(_point: Vector2) -> float: return 0.0

func _rectangle(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

func _range_footprint(definition: Dictionary, distant: bool) -> PackedVector2Array:
	# A linha externa do horizonte de produção usa section.x=1 / section.y=0.
	# Reaproveitar exatamente esse cálculo de frente/profundidade dá uma borda externa irregular;
	# as pontas escritas afinam até o datum e se juntam à bacia comum.
	var points := PackedVector2Array()
	var inner := PackedVector2Array()
	var count := ceili((float(definition.to)-float(definition.from))/24.0)
	for i in range(count+1):
		var t := float(i)/count
		var along := lerpf(float(definition.from),float(definition.to),t)
		var phase := float(definition.seed)*.071
		var gullies := 0.0
		for g in 7:
			var center := .075+float(g)*.137+sin(phase+float(g)*2.7)*.027
			var width := .009+float(g%3)*.004
			gullies=maxf(gullies,exp(-pow((t-center)/width,2)))
		var front := maxf(HORIZON.MARGIN,HORIZON.MARGIN+17.0+11.0*sin(t*15+phase)+8.0*sin(t*33+phase*.4)+gullies*29.0)
		var depth := float(definition.width)*(1.0+.13*sin(t*8+phase))
		if distant: front+=175.0; depth*=.92
		var taper := smoothstep(0.0,.065,t)*smoothstep(0.0,.065,1.0-t)
		var outside: Vector3=HORIZON._position(definition.side,along,(front+depth)*taper,0)
		var inside: Vector3=HORIZON._position(definition.side,along,-3.0,0)
		points.append(Vector2(outside.x,outside.z)); inner.append(Vector2(inside.x,inside.z))
	inner.reverse(); points.append_array(inner)
	return points

func _soft_polygon(polygon: PackedVector2Array, color: Color, feather: float) -> void:
	# Uma malha regular não pode se sobrepor nos vértices côncavos do perímetro.
	# A opacidade vem da distância real ao perímetro, nunca de uma normal extrudada.
	# O polígono mantém a opacidade de entrada; só o exterior tem borda suave.
	var step := maxf(4.0,feather/5.0)
	var rect := _bounds(polygon).grow(feather+step)
	var columns := ceili(rect.size.x/step)
	var rows := ceili(rect.size.y/step)
	var stride := columns+1
	var positions := PackedVector2Array()
	var distances := PackedFloat32Array()
	distances.resize(stride*(rows+1)); distances.fill(feather*feather)
	for y in range(rows+1):
		for x in range(columns+1):
			positions.append(rect.position+Vector2(minf(float(x)*step,rect.size.x),minf(float(y)*step,rect.size.y)))
	# Restringe a amostragem de distância à vizinhança finita de esfumado de cada segmento.
	# A maioria dos vértices internos precisa só da consulta nativa de ponto no polígono.
	for i in polygon.size():
		var a := polygon[i]; var b := polygon[(i+1)%polygon.size()]
		var vicinity := Rect2(a,b-a).abs().grow(feather)
		var first_x := maxi(0,floori((vicinity.position.x-rect.position.x)/step))
		var first_y := maxi(0,floori((vicinity.position.y-rect.position.y)/step))
		var last_x := mini(columns,ceili((vicinity.end.x-rect.position.x)/step))
		var last_y := mini(rows,ceili((vicinity.end.y-rect.position.y)/step))
		for y in range(first_y,last_y+1):
			for x in range(first_x,last_x+1):
				var index := y*stride+x
				var point := positions[index]
				var closest := Geometry2D.get_closest_point_to_segment(point,a,b)
				distances[index]=minf(distances[index],point.distance_squared_to(closest))
	var tints := PackedColorArray()
	for i in positions.size():
		var tint := color
		if not Geometry2D.is_point_in_polygon(positions[i],polygon):
			tint.a*=1.0-smoothstep(0.0,feather,sqrt(distances[i]))
		tints.append(tint)
	var vertices := PackedVector3Array(); var colors := PackedColorArray()
	for y in rows:
		for x in columns:
			var a := y*stride+x; var b := a+1; var c := a+stride; var d := c+1
			if maxf(maxf(tints[a].a,tints[b].a),maxf(tints[c].a,tints[d].a))<=0.0: continue
			for index in [a,b,d,a,d,c]:
				vertices.append(Vector3(positions[index].x,positions[index].y,0)); colors.append(tints[index])
	_mesh(vertices,colors)

func _presentation_lands(lands: Array) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for land in lands:
		var row := {"polygon":land.polygon,"biome":land.biome}
		if land.biome in ["city","forest"]:
			var merged := true
			while merged:
				merged=false
				for i in range(result.size()-1,-1,-1):
					if result[i].biome!=row.biome: continue
					var union: Array[PackedVector2Array]=Geometry2D.merge_polygons(row.polygon,result[i].polygon)
					if union.size()!=1: continue
					row.polygon=union[0]; result.remove_at(i); merged=true
		result.append(row)
	return result

func _context_envelope(polygon: PackedVector2Array, biome: String) -> void:
	# Contexto de terreno translúcido e sem contorno, explicitamente separado da pegada
	# jogável exata. Esconde um corte de célula-fonte/casco sem inventar costa.
	var spread := 76.0 if biome=="mountain" else 32.0 if biome=="forest" else 12.0
	var tint := Color("47524b") if biome!="mountain" else Color("56605b")
	tint.a=.17 if biome=="mountain" else .11
	_soft_polygon(polygon,tint,spread)

func _landforms() -> void:
	# Reaproveita os polígonos escritos exatos, incluindo as quatro dunas. _prepare
	# preenche um cache de dados finito; não monta geometria 3D em streaming.
	LANDFORMS._prepare()
	for feature in LANDFORMS._features:
		var polygon: PackedVector2Array=feature.polygon
		match int(feature.kind):
			0:
				_polygon(polygon,Color("a28b63"))
				var crest := PackedVector2Array()
				for i in range(3,22):
					var t := float(i)/24.0
					var offset := Vector2(lerpf(-.8,.8,t),sin(t*PI)*.10)*Vector2(feature.radius)
					crest.append(Vector2(feature.center)+offset.rotated(float(feature.yaw)))
				_open_line(crest,Color("d0b98c"),1.15,.35)
				var lee := polygon.duplicate()
				for i in lee.size(): lee[i]=Vector2(feature.center)+(lee[i]-Vector2(feature.center))*.65+Vector2(2.0,1.5)
				_polygon(lee,Color("b9a075"))
			1:
				_polygon(polygon,Color("b4a383"))
				_closed_line(polygon,Color("d0bc94"),.65,.18)
				var stream := PackedVector2Array()
				for i in 45: stream.append(LANDFORMS.wash_point(float(i)/44.0))
				_open_line(stream,Color("786f5c"),1.0,.18)
			2:
				_polygon(polygon,Color("c8bda4"))
				var interior := polygon.duplicate()
				for i in interior.size(): interior[i]=LANDFORMS.SALT+(interior[i]-LANDFORMS.SALT)*.82
				_polygon(interior,Color("d7ceb9"))
				_closed_line(polygon,Color("e0d6bb"),.65,.18)

func _height_patch(rect: Rect2, step: float, sampler: Callable, kind: String, clipping: PackedVector2Array, contour_interval: float) -> void:
	var columns := ceili(rect.size.x/step)
	var rows := ceili(rect.size.y/step)
	var heights := PackedFloat32Array()
	var positions := PackedVector2Array()
	for y in range(rows+1):
		for x in range(columns+1):
			var p := rect.position+Vector2(minf(float(x)*step,rect.size.x),minf(float(y)*step,rect.size.y))
			positions.append(p); heights.append(float(sampler.call(p)))
	var tints := PackedColorArray()
	for y in range(rows+1):
		for x in range(columns+1):
			var i := y*(columns+1)+x
			var dx := heights[y*(columns+1)+maxi(0,x-1)]-heights[y*(columns+1)+mini(columns,x+1)]
			var dz := heights[maxi(0,y-1)*(columns+1)+x]-heights[mini(rows,y+1)*(columns+1)+x]
			# Vertical exaggeration changes shading only, never survey positions.
			var exaggeration := 3.0 if kind=="mountain" else 1.6
			var normal := Vector3(dx*exaggeration,step*2.0,dz*exaggeration).normalized()
			var tint := _height_color(positions[i],heights[i],normal,kind)
			if not clipping.is_empty():
				var fade := 44.0 if kind=="mountain" else 26.0 if kind=="forest" else 9.0
				tint.a*=smoothstep(0.0,fade,_edge_distance(positions[i],clipping))
			tints.append(tint)
	var vertices := PackedVector3Array(); var colors := PackedColorArray(); var contours := PackedVector2Array()
	for y in rows:
		for x in columns:
			var a := y*(columns+1)+x; var b := a+1; var c := a+columns+1; var d := c+1
			var corners := PackedVector2Array([positions[a],positions[b],positions[d],positions[c]])
			var parts: Array[PackedVector2Array]=[corners]
			var clipped := false
			if not clipping.is_empty():
				var all_inside := true
				for p in corners:
					if not Geometry2D.is_point_in_polygon(p,clipping): all_inside=false; break
				if not all_inside:
					parts=Geometry2D.intersect_polygons(corners,clipping); clipped=true
			if not clipped:
				# Células internas reaproveitam as quatro amostras sombreadas. Só fragmentos
				# da fronteira precisam de recorte/triangulação ou cores interpoladas.
				for index in [a,b,d,a,d,c]:
					vertices.append(Vector3(positions[index].x,positions[index].y,0)); colors.append(tints[index])
			else:
				for part in parts:
					var part_colors := PackedColorArray()
					for p in part:
						var blend := (p-corners[0])/Vector2(maxf(.001,corners[2].x-corners[0].x),maxf(.001,corners[2].y-corners[0].y))
						var tint := tints[a].lerp(tints[b],blend.x).lerp(tints[c].lerp(tints[d],blend.x),blend.y)
						if _edge_distance(p,clipping)<.01: tint.a=0.0
						part_colors.append(tint)
					for index in Geometry2D.triangulate_polygon(part):
						var p := part[index]; vertices.append(Vector3(p.x,p.y,0)); colors.append(part_colors[index])
			if not parts.is_empty() and contour_interval>0.0:
				_contour_cell(corners,PackedFloat32Array([heights[a],heights[b],heights[d],heights[c]]),contour_interval,contours,clipping)
	_mesh(vertices,colors)
	if not contours.is_empty():
		_line_batches.append({"points":contours,"color":Color(.78,.74,.62,.11) if kind!="mountain" else Color(.77,.82,.81,.10),"width":.55,"min_scale":.38})

func _height_color(point: Vector2, height: float, normal: Vector3, kind: String) -> Color:
	var base: Color=PALETTE.desert
	match kind:
		"mountain":
			var original_y := point.y*16.0-CATALOG.MOUNTAIN_OFFSET.y
			var snow := 1.0-smoothstep(-1500.0,-1200.0,original_y)
			base=Color("4b574b").lerp(Color("777b70"),clampf(height/7.5,0,1)).lerp(Color("a6b4b1"),snow*.84)
		"city": base=PALETTE.city
		"forest": base=PALETTE.forest
		"quarry": base=base.lerp(Color("514e42"),clampf(-height/40.0,0,1))
		"gorge": base=base.lerp(Color("363e3c"),clampf(-height/65.0,0,1))
		"sand": base=base.lerp(Color("797460"),clampf(height/65.0,0,1))
	var shade := clampf(.48+normal.dot(LIGHT)*.66,.25,1.10)
	var result := base*shade; result.a=1.0
	return result

func _contour_cell(corners: PackedVector2Array, heights: PackedFloat32Array, interval: float, output: PackedVector2Array, clipping: PackedVector2Array) -> void:
	var low := minf(minf(heights[0],heights[1]),minf(heights[2],heights[3]))
	var high := maxf(maxf(heights[0],heights[1]),maxf(heights[2],heights[3]))
	for level in range(ceili(low/interval),floori(high/interval)+1):
		var altitude := float(level)*interval
		if is_zero_approx(altitude): continue
		var cuts := PackedVector2Array()
		for i in 4:
			var j := (i+1)%4
			if (heights[i]<altitude)==(heights[j]<altitude): continue
			cuts.append(corners[i].lerp(corners[j],inverse_lerp(heights[i],heights[j],altitude)))
		for i in range(0,cuts.size()-1,2):
			var mid := (cuts[i]+cuts[i+1])*.5
			if not clipping.is_empty() and (not Geometry2D.is_point_in_polygon(mid,clipping) or _edge_distance(mid,clipping)<16.0): continue
			if _water.any(func(polygon): return Geometry2D.is_point_in_polygon(mid,polygon)): continue
			output.append(cuts[i]); output.append(cuts[i+1])

func _edge_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var distance := INF
	for i in polygon.size():
		distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])))
	return distance

func _tree_canopies(region: Node, id: String) -> void:
	var vertices := PackedVector3Array(); var colors := PackedColorArray()
	var count := 0
	var records: Variant=region.get("records")
	if not records is Dictionary: return
	for cell in records.values():
		for record in cell:
			if record.get("kind","")!="tree" or count>=1600: continue
			var at := Vector2(record.position.x,record.position.z)
			var radius := 2.5 if id=="harbor" else 2.8
			var snow := bool(record.get("snow",false))
			var center_color := Color("526453") if not snow else Color("a6b4ae")
			var edge_color := Color("263c34") if not snow else Color("697c77")
			for i in 6:
				var a := at+Vector2.from_angle(float(i)*TAU/6)*radius
				var b := at+Vector2.from_angle(float(i+1)*TAU/6)*radius
				vertices.append_array(PackedVector3Array([Vector3(at.x,at.y,0),Vector3(a.x,a.y,0),Vector3(b.x,b.y,0)]))
				colors.append_array(PackedColorArray([center_color,edge_color,edge_color]))
			count+=1
	_mesh(vertices,colors)

func _polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size()>2: _commands.append({"polygon":points,"color":color})

func _mesh(vertices: PackedVector3Array, colors: PackedColorArray) -> void:
	if vertices.is_empty(): return
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_commands.append({"mesh":mesh}); triangle_count+=int(vertices.size()/3)

func _closed_line(points: PackedVector2Array, color: Color, width: float, min_scale := 0.0) -> void:
	var line := points.duplicate(); line.append(points[0]); _open_line(line,color,width,min_scale)

func _open_line(points: PackedVector2Array, color: Color, width: float, min_scale := 0.0) -> void:
	var pairs := PackedVector2Array()
	for i in range(1,points.size()): pairs.append(points[i-1]); pairs.append(points[i])
	_line_batches.append({"points":pairs,"color":color,"width":width,"min_scale":min_scale})

func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0],Vector2.ZERO)
	for p in polygon: result=result.expand(p)
	return result
