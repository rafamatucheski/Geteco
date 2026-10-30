extends RefCounted
## One composed ground: planted infield, paved circulation and a supported verge.
## The old pavement is removed wherever another finish owns the same surface.
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const CLIP := preload("res://world/editing/WorldGroundFactory.gd")
const SURFACES := preload("res://world/places/ShopInteriorMaterials.gd")
const LANDSCAPE := preload("res://activities/motocross/MotocrossGroundDetail.gd")
const PAVING := preload("res://world/urban_detail/HarborPaving.gd")
const TOP := .025
const MEADOW_TOP := .001
## Meio-fio de pedra entre a faixa mineral e o gramado: 16 cm de largura, 5 cm acima do piso.
const CURB_WIDTH := .16
const CURB_TOP := TOP+.05
## Acabamentos PNG (BC7 com mipmaps) da HarborPaving. limestone/brick são cinza quase branco
## (média 231/255): a tinta define a cor. O concrete já vem colorido, por isso a tinta clara.
const PAINTED := {"paving":["brick","a39a88"],"walk":["limestone","bdb6a2"],"mineral":["concrete","b9b6aa"],"curb":["limestone","9d9a8e"]}
const STANDIN_GROUP := &"park_lume_ground_standin"
const STANDIN_NAME := "ParkLumeMeadowStandIn"
## Pegada do parque e do acesso (x local até 49) mais a faixa (até ~2 m nos cantos em esquadro):
## chunks fora nem calculam a cobertura.
const SITE_BOUNDS := Rect2(-219,39,96,78)
## GETECO_PLACE_GROUND_CUT=0 volta ao chão antigo por cima do mato (borda a 1 mm, sem meio-fio
## e sem recorte do Land). Interruptor de A/B, não opção do jogador.
static var cut_enabled := OS.get_environment("GETECO_PLACE_GROUND_CUT") != "0"
## O parque só existe a menos de 170 m (AmusementParkRuntime). Enquanto ele não está na árvore, o
## mato recortado do Land volta como substituto do chunk (NativeRegion._place_ground_cut).
static var site_shown := false
static var _materials := {}
static var _cover: Array[PackedVector2Array] = []

static func _painted() -> bool: return CLIP.painted_enabled

static func _meadow_top() -> float:
	# Com o Land recortado no contorno externo da faixa, a borda encosta no mato na mesma cota.
	return 0.0 if cut_enabled else MEADOW_TOP

static func prewarm_materials() -> Array[Material]:
	var result: Array[Material] = []
	if _painted():
		for kind in PAINTED: result.append(_material(kind))
	return result

static func _rect(x: float,z: float,width: float,depth: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x,z),Vector2(x+width,z),Vector2(x+width,z+depth),Vector2(x,z+depth)])

static func _gardens() -> Array[PackedVector2Array]:
	return [
		_rect(-40,-36,35.2,59.3),
		PackedVector2Array([Vector2(-3.8,-35.7),Vector2(22,-35.7),Vector2(24,-32.3),Vector2(12,-30.8),Vector2(-3.8,-31.8)]),
		PackedVector2Array([Vector2(36,23.5),Vector2(40,23.5),Vector2(40,36),Vector2(25,36)])]

static func _material(kind: String) -> Material:
	if _materials.has(kind): return _materials[kind]
	if kind == "grass":
		_materials[kind] = LANDSCAPE.ground_material()
	elif kind == "verge":
		var verge := ShaderMaterial.new()
		verge.shader = preload("res://world/places/amusement_park/ParkGroundVerge.gdshader")
		LANDSCAPE.bind_textures(verge)
		_materials[kind] = verge
	elif _painted() and PAINTED.has(kind):
		# Material compartilhado da HarborPaving (triplanar em espaço de mundo): ignora os UVs do lote.
		_materials[kind] = PAVING.material(Color(PAINTED[kind][1]),PAINTED[kind][0])
	elif kind == "curb":
		_materials[kind] = _material("mineral")
	else:
		var material := StandardMaterial3D.new()
		material.albedo_texture = SURFACES.texture("stone")
		material.albedo_color = Color({"paving":"a3a08c","walk":"c0baa5","mineral":"797c70"}[kind])
		material.roughness = .94
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_materials[kind] = material
	return _materials[kind]

static func _stream(streams: Dictionary,kind: String) -> SurfaceTool:
	if not streams.has(kind):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		streams[kind] = surface
	return streams[kind]

static func _triangle(surface: SurfaceTool,points: PackedVector3Array,weights := PackedFloat32Array()) -> void:
	var order := [0,1,2]
	if (points[1]-points[0]).cross(points[2]-points[0]).y>0: order = [0,2,1]
	for index: int in order:
		var point := points[index]
		surface.set_normal(Vector3.UP)
		# A 1 m tile contains four rows of 50 x 25 cm pavers.
		surface.set_uv(Vector2(point.x,point.z))
		# Só a faixa usa a cor (desgaste no alfa). Pisos sem cor ficam no formato de vértice
		# dos pisos do Harbor (posição, normal, UV), o mesmo do pré-aquecimento.
		if not weights.is_empty(): surface.set_color(Color(1,1,1,weights[index]))
		surface.add_vertex(point)

static func _faces(polygon: PackedVector2Array,height := TOP) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var indices := Geometry2D.triangulate_polygon(polygon)
	for index in indices: faces.append(Vector3(polygon[index].x,height,polygon[index].y))
	return faces

static func _polygon(streams: Dictionary,kind: String,polygon: PackedVector2Array) -> void:
	var faces := _faces(polygon)
	if faces.is_empty(): return
	var surface := _stream(streams,kind)
	for index in range(0,faces.size(),3):
		_triangle(surface,PackedVector3Array([faces[index],faces[index+1],faces[index+2]]))

static func _finish_parts(streams: Dictionary,kind: String,polygon: PackedVector2Array,masks: Array) -> void:
	for part in CLIP.uncovered(polygon,masks): _polygon(streams,kind,part)

static func build(park: Node3D) -> void:
	# The fairground owns its foundation independently of editable city ground.
	# A removed underlying tile must not leave the rides over water or empty space.
	var foundation := MeshInstance3D.new()
	foundation.name = "ParkFoundation"
	var foundation_faces := _faces(LAYOUT.outline(),-.035)
	if cut_enabled:
		# Com o mato recortado até o contorno externo da faixa, a fundação vai até lá:
		# uma fresta de emenda mostra pedra a 3,5 cm, nunca o vazio debaixo do Land.
		var under_verge := _faces(_contour().outside,-.035)
		if not under_verge.is_empty(): foundation_faces = under_verge
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,foundation_faces.size(),3):
		_triangle(surface,PackedVector3Array([foundation_faces[i],foundation_faces[i+1],foundation_faces[i+2]]))
	foundation.mesh = surface.commit()
	foundation.material_override = _material("mineral")
	park.add_child(foundation)
	foundation.create_trimesh_collision()
	var streams := {}
	var outline := LAYOUT.outline()
	var inner: PackedVector2Array = Geometry2D.offset_polygon(outline,-.34,Geometry2D.JOIN_MITER)[0]
	var approach := _rect(40,13.1,11,5.8)
	var walks: Array[PackedVector2Array] = [_rect(-14,12,54,6),_rect(17.4,-5,5.2,18)]
	var trims: Array[PackedVector2Array] = [_rect(-14,11.785,54,.13),_rect(-14,18.085,54,.13)]
	var gardens: Array[PackedVector2Array] = []
	var planted_borders: Array[PackedVector2Array] = []
	for source in _gardens():
		for garden in Geometry2D.intersect_polygons(source,inner):
			gardens.append(garden)
			for expanded in Geometry2D.offset_polygon(garden,.18,Geometry2D.JOIN_MITER):
				planted_borders.append_array(Geometry2D.intersect_polygons(expanded,inner))
	var circulation_masks: Array = walks+trims
	_finish_parts(streams,"paving",inner,planted_borders+circulation_masks)
	for garden in gardens: _finish_parts(streams,"grass",garden,circulation_masks)
	for border in planted_borders: _finish_parts(streams,"mineral",border,gardens+circulation_masks)
	_finish_parts(streams,"mineral",outline,[inner]+circulation_masks)
	var previous_walks: Array = []
	for walk in walks:
		for clipped in Geometry2D.intersect_polygons(walk,outline):
			_finish_parts(streams,"walk",clipped,previous_walks)
		previous_walks.append(walk)
	for trim in trims:
		for clipped in Geometry2D.intersect_polygons(trim,outline):
			_finish_parts(streams,"mineral",clipped,walks)
	var faces := _faces(outline)
	_approach(streams,faces)
	_perimeter_verge(streams,park,approach,faces)
	for kind: String in streams:
		var display := MeshInstance3D.new()
		display.name = "ParkGround_"+kind
		display.mesh = streams[kind].commit()
		display.material_override = _material(kind)
		display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		park.add_child(display)
	var body := StaticBody3D.new()
	body.name = "ParkGround"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	park.add_child(body)
	park.set_meta("integrated_ground",true)
	if cut_enabled: _track_site(park)

## Substituto do mato no chunk: escondido enquanto o parque está montado e visível.
static func _track_site(park: Node3D) -> void:
	var sync := func() -> void: _set_site_shown(park,park.is_inside_tree() and park.is_visible_in_tree())
	park.tree_entered.connect(sync)
	park.visibility_changed.connect(sync)
	park.tree_exiting.connect(func() -> void: _set_site_shown(park,false))
	if park.is_inside_tree(): sync.call()

static func _set_site_shown(park: Node3D,shown: bool) -> void:
	if shown == site_shown: return
	site_shown = shown
	if park.is_inside_tree(): park.get_tree().call_group(STANDIN_GROUP,"set_visible",not shown)

## Contorno parque + acesso com os dois cantos reentrantes do portão. Os dois últimos metros
## do acesso já encostam na calçada da cidade.
static func _edge() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-40,-36),Vector2(22,-36),Vector2(40,-10),
		Vector2(40,13.1),Vector2(49,13.1),Vector2(49,18.9),Vector2(40,18.9),Vector2(40,36),Vector2(-40,36)])

## Pontos do contorno a cada ~2 m: borda interna, direção de afastamento (esquadro nos cantos),
## largura da faixa e se o trecho que começa ali leva meio-fio. Os três lados do acesso não
## levam: o carro sobe por ali e a faixa afina até zero no fim da rampa.
static func _contour() -> Dictionary:
	var edge := _edge()
	var inside := PackedVector2Array()
	var outside := PackedVector2Array()
	var offsets := PackedVector2Array()
	var widths := PackedFloat32Array()
	var curbed: Array[bool] = []
	for index in edge.size():
		var a := edge[index]
		var b := edge[(index+1)%edge.size()]
		var direction := (b-a).normalized()
		var normal := Vector2(direction.y,-direction.x)
		var prior := (a-edge[posmod(index-1,edge.size())]).normalized()
		var corner := (normal+Vector2(prior.y,-prior.x)).normalized()
		var segments := maxi(1,ceili(a.distance_to(b)/2.0))
		var gate := a.x>=40.0 and b.x>=40.0 and minf(a.y,b.y)>=13.1 and maxf(a.y,b.y)<=18.9
		for step in segments:
			var point := a.lerp(b,float(step)/segments)
			inside.append(point)
			var offset := corner/maxf(.2,corner.dot(normal)) if step==0 else normal
			offsets.append(offset)
			widths.append(_width(point))
			outside.append(point+offset*_width(point))
			curbed.append(cut_enabled and not gate)
	return {"inside":inside,"outside":outside,"offsets":offsets,"widths":widths,"curbed":curbed}

## Área que o chão do parque (piso, faixa e acesso até a rampa) cobre, em coordenadas do Harbor.
## O Land não desenha o mato ali; a rampa final do acesso (x local 49..51) fica sobre o Land.
static func world_cover() -> Array[PackedVector2Array]:
	if not cut_enabled or not LAYOUT.enabled(): return []
	if _cover.is_empty():
		var polygon := PackedVector2Array()
		for point in _contour().outside: polygon.append(point+Vector2(LAYOUT.ORIGIN.x,LAYOUT.ORIGIN.z))
		_cover.append(polygon)
	return _cover

static func _approach(streams: Dictionary,faces: PackedVector3Array) -> void:
	# The vehicle hull rests at street level: even the former 2.5 cm exposed
	# triangle edge stopped its front bumper. Ease the last 2 m down to zero,
	# using the same vertices for visible paving and physical support.
	var stations := PackedFloat32Array([40,49,49.25,49.5,49.75,50,50.25,50.5,50.75,51])
	for index in range(stations.size()-1):
		var x0 := stations[index]
		var x1 := stations[index+1]
		var y0 := TOP*(1.0-smoothstep(49.0,51.0,x0))
		var y1 := TOP*(1.0-smoothstep(49.0,51.0,x1))
		var a := Vector3(x0,y0,13.1)
		var b := Vector3(x1,y1,13.1)
		var c := Vector3(x1,y1,18.9)
		var d := Vector3(x0,y0,18.9)
		for triangle in [PackedVector3Array([a,b,c]),PackedVector3Array([a,c,d])]:
			_triangle(_stream(streams,"walk"),triangle)
			faces.append_array(triangle)

static func _wear(point: Vector2) -> float:
	return clampf(.55+sin(point.x*.17+point.y*.19)*.23+sin(point.y*.51)*.17,.15,.95)

static func _width(point: Vector2) -> float:
	var width := clampf(.90+sin(point.x*.17+point.y*.22)*.30+cos(point.x*.40-point.y*.13)*.22,.55,1.42)
	return width*clampf((49.0-point.x)/3.0,0,1) if point.x>46.0 else width

static func _perimeter_verge(streams: Dictionary,park: Node3D,approach: PackedVector2Array,faces: PackedVector3Array) -> void:
	var contour := _contour()
	var inside: PackedVector2Array = contour.inside
	var outside: PackedVector2Array = contour.outside
	var offsets: PackedVector2Array = contour.offsets
	var widths: PackedFloat32Array = contour.widths
	var curbed: Array[bool] = contour.curbed
	var meadow := _meadow_top()
	var curb := SurfaceTool.new()
	curb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curb_faces := 0
	for index in inside.size():
		var next := (index+1)%inside.size()
		# A faixa é o mesmo plano de antes (TOP na borda do piso, mato no fim); com meio-fio ela
		# só começa depois da pedra, na cota desse plano ali.
		var cut := CURB_WIDTH if curbed[index] else 0.0
		var t0 := cut/maxf(widths[index],.001)
		var t1 := cut/maxf(widths[next],.001)
		var start0 := inside[index]+offsets[index]*cut
		var start1 := inside[next]+offsets[next]*cut
		var a := Vector3(start0.x,lerpf(TOP,meadow,t0),start0.y)
		var b := Vector3(start1.x,lerpf(TOP,meadow,t1),start1.y)
		var c := Vector3(outside[next].x,meadow,outside[next].y)
		var d := Vector3(outside[index].x,meadow,outside[index].y)
		var wear0 := _wear(inside[index])*(1.0-t0)
		var wear1 := _wear(inside[next])*(1.0-t1)
		_verge_triangle(streams,PackedVector3Array([a,b,c]),PackedFloat32Array([wear0,wear1,0]),[approach],faces)
		_verge_triangle(streams,PackedVector3Array([a,c,d]),PackedFloat32Array([wear0,0,0]),[approach],faces)
		if cut > 0.0:
			_curb_piece(curb,faces,inside[index],inside[next],start0,start1,a.y,b.y)
			curb_faces += 1
			# Ponta do meio-fio onde o trecho seguinte (acesso) não tem pedra.
			if not curbed[next]: _curb_cap(curb,faces,inside[next],start1,b.y,inside[next]-inside[index])
			if not curbed[posmod(index-1,inside.size())]: _curb_cap(curb,faces,inside[index],start0,a.y,inside[index]-inside[next])
	if curb_faces == 0: return
	var display := MeshInstance3D.new()
	# Fora do prefixo ParkGround_: o meio-fio não é piso horizontal nem parte da conta de área.
	display.name = "ParkEdgeCurb"
	display.mesh = curb.commit()
	display.material_override = _material("curb")
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	park.add_child(display)

## Um bloco do meio-fio: topo, face interna (do piso, TOP até o topo) e face externa (topo até a
## faixa). As faces entram também na colisão do chão; a pedra tem 5 cm, o pneu sobe.
static func _curb_piece(surface: SurfaceTool,faces: PackedVector3Array,p0: Vector2,p1: Vector2,q0: Vector2,q1: Vector2,low0: float,low1: float) -> void:
	var along := (p1-p0).normalized()
	var outward := Vector3(along.y,0,-along.x)
	_curb_quad(surface,faces,[Vector3(p0.x,CURB_TOP,p0.y),Vector3(p1.x,CURB_TOP,p1.y),Vector3(q1.x,CURB_TOP,q1.y),Vector3(q0.x,CURB_TOP,q0.y)],Vector3.UP)
	_curb_quad(surface,faces,[Vector3(p0.x,TOP,p0.y),Vector3(p1.x,TOP,p1.y),Vector3(p1.x,CURB_TOP,p1.y),Vector3(p0.x,CURB_TOP,p0.y)],-outward)
	_curb_quad(surface,faces,[Vector3(q0.x,low0,q0.y),Vector3(q1.x,low1,q1.y),Vector3(q1.x,CURB_TOP,q1.y),Vector3(q0.x,CURB_TOP,q0.y)],outward)

static func _curb_cap(surface: SurfaceTool,faces: PackedVector3Array,p: Vector2,q: Vector2,low: float,facing: Vector2) -> void:
	# Nos cantos do portão a ponta é diagonal (esquadro): a normal é a do plano da ponta.
	var across := Vector2(-(q-p).y,(q-p).x).normalized()
	if across.dot(facing) < 0.0: across = -across
	var normal := Vector3(across.x,0,across.y)
	_curb_quad(surface,faces,[Vector3(p.x,TOP,p.y),Vector3(q.x,low,q.y),Vector3(q.x,CURB_TOP,q.y),Vector3(p.x,CURB_TOP,p.y)],normal)

static func _curb_quad(surface: SurfaceTool,faces: PackedVector3Array,corners: Array,normal: Vector3) -> void:
	for triangle in [[0,1,2],[0,2,3]]:
		var points := PackedVector3Array([corners[triangle[0]],corners[triangle[1]],corners[triangle[2]]])
		if (points[1]-points[0]).cross(points[2]-points[0]).length_squared() < 1e-12: continue
		# Face da frente no sentido horário do Godot, como _triangle faz no piso.
		if (points[1]-points[0]).cross(points[2]-points[0]).dot(normal) > 0: points = PackedVector3Array([points[0],points[2],points[1]])
		for point in points:
			surface.set_normal(normal)
			surface.set_uv(Vector2(point.x+point.y,point.z+point.y))
			surface.add_vertex(point)
		faces.append_array(points)

static func _verge_triangle(streams: Dictionary,points: PackedVector3Array,weights: PackedFloat32Array,masks: Array,faces: PackedVector3Array) -> void:
	var source := PackedVector2Array()
	for point in points: source.append(Vector2(point.x,point.z))
	var denominator := (source[1]-source[0]).cross(source[2]-source[0])
	if absf(denominator)<.000001: return
	for clipped in CLIP.uncovered(source,masks):
		var indices := Geometry2D.triangulate_polygon(clipped)
		for i in range(0,indices.size(),3):
			var triangle := PackedVector3Array()
			var alphas := PackedFloat32Array()
			for index in [indices[i],indices[i+1],indices[i+2]]:
				var point: Vector2 = clipped[index]
				var w1 := (point-source[0]).cross(source[2]-source[0])/denominator
				var w2 := (source[1]-source[0]).cross(point-source[0])/denominator
				var w0 := 1-w1-w2
				triangle.append(Vector3(point.x,points[0].y*w0+points[1].y*w1+points[2].y*w2,point.y))
				alphas.append(clampf(weights[0]*w0+weights[1]*w1+weights[2]*w2,0,1))
			_triangle(_stream(streams,"verge"),triangle,alphas)
			faces.append_array(triangle)
