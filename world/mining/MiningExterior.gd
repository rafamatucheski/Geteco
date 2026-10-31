extends RefCounted
## Sítio industrial remoto a céu aberto, pertencente ao ciclo de vida de chunks existente do deserto.
## Acesso/piso e bancadas são admitidos antes dos atores; os props não têm laços por quadro.
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const BATCH := preload("res://world/mining/MiningBatch.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const GROUND_SHADER := preload("res://world/mining/mining_ground.gdshader")
const DESERT_GEOMETRY := preload("res://world/desert/DesertGeometry.gd")
const GRID := 3.0
const OWNED_GROUND := Rect2(-326,-1230,300,365)
static var _ground_material: ShaderMaterial
static var _wall_material: ShaderMaterial
static var _road_material: ShaderMaterial
static var _outline := PackedVector2Array()
static var _surface_scenes: Dictionary={}
static var _height_tiles: Dictionary={}
static var _access_corridors: Array[PackedVector2Array]=[]
static var _local_corridors: Array[PackedVector2Array]=[]
static var _road_triangles: Array[Dictionary]=[]
static var _road_buckets: Dictionary={}

static func ground_remainders(rect: Rect2) -> Array[Rect2]:
	if not LAYOUT.enabled() or not rect.intersects(OWNED_GROUND): return [rect]
	var cut := rect.intersection(OWNED_GROUND)
	var result: Array[Rect2]=[]
	for piece in [Rect2(rect.position,Vector2(rect.size.x,cut.position.y-rect.position.y)),Rect2(Vector2(rect.position.x,cut.end.y),Vector2(rect.size.x,rect.end.y-cut.end.y)),Rect2(Vector2(rect.position.x,cut.position.y),Vector2(cut.position.x-rect.position.x,cut.size.y)),Rect2(Vector2(cut.end.x,cut.position.y),Vector2(rect.end.x-cut.end.x,cut.size.y))]:
		if piece.has_area(): result.append(piece)
	return result

static func build_surfaces(parent: Node3D, rect: Rect2) -> void:
	if not LAYOUT.enabled(): return
	if not rect.intersects(OWNED_GROUND): return
	if not _surface_scenes.has(rect):
		var prototype := Node3D.new()
		prototype.name="MiningGround"
		_build_surfaces_uncached(prototype,rect)
		_own_children(prototype,prototype)
		var scene := PackedScene.new()
		if scene.pack(prototype)!=OK:
			prototype.free()
			push_error("Could not cache quarry ground at "+str(rect))
			return
		_surface_scenes[rect]=scene
		prototype.free()
	var ground: Node3D=(_surface_scenes[rect] as PackedScene).instantiate()
	parent.add_child(ground)
	# Anexa o provedor de altura vivo depois de instanciar a cena em cache; o apoio de
	# veículos precisa usar exatamente estas faces de terreno/estrada, sem guardar um callable
	# no PackedScene reutilizável nem dar apoio aos props decorativos da mina.
	for body in ground.find_children("QuarryBenchCollision","StaticBody3D",true,false):
		body.set_meta("desert_continuous_ground",true)
		body.set_meta("desert_ground_height",surface_height)

static func _own_children(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner=owner_root
		_own_children(child,owner_root)

static func _build_surfaces_uncached(parent: Node3D, rect: Rect2) -> void:
	var patch := rect.intersection(LAYOUT.BOUNDS)
	if patch.has_area():
		var floor_faces := PackedVector3Array()
		var wall_faces := PackedVector3Array()
		var solid_faces := PackedVector3Array()
		for z in range(floori(patch.position.y/GRID),ceili(patch.end.y/GRID)):
			for x in range(floori(patch.position.x/GRID),ceili(patch.end.x/GRID)):
				var a := Vector2(maxf(float(x)*GRID,patch.position.x),maxf(float(z)*GRID,patch.position.y))
				var b := Vector2(minf(float(x+1)*GRID,patch.end.x),minf(float(z+1)*GRID,patch.end.y))
				var local := (a+b)*.5-Vector2(LAYOUT.CENTER.x,LAYOUT.CENTER.z)
				var offset := Vector2(LAYOUT.CENTER.x,LAYOUT.CENTER.z)
				var corners := PackedVector2Array([a-offset,Vector2(b.x,a.y)-offset,b-offset,Vector2(a.x,b.y)-offset])
				var pieces: Array[PackedVector2Array]=[]
				var distance := (local-LAYOUT.PIT_CENTER).length()
				if distance<110:
					pieces.append(corners)
				elif distance<158:
					pieces=Geometry2D.intersect_polygons(corners,_ground_outline())
				pieces=_carve_roads(pieces,local)
				for polygon in pieces:
					var vertices := PackedVector3Array()
					var raised := false
					for index in Geometry2D.triangulate_polygon(polygon):
						var p: Vector2=polygon[index]
						var h := bench_height(p)
						raised=raised or absf(h)>.008
						vertices.append(Vector3(p.x+offset.x,h,p.y+offset.y))
					if raised:
						wall_faces.append_array(vertices)
						solid_faces.append_array(vertices)
					else: floor_faces.append_array(vertices)
		_emit(parent,"QuarryDisturbedEarth",floor_faces,_surface(false),floor_faces)
		_emit(parent,"ExcavatedOreBenches",wall_faces,_surface(true),solid_faces)
	var owned := rect.intersection(OWNED_GROUND)
	_build_basefill(parent,owned)
	_build_access(parent,owned)

static func _subtract(parts: Array[PackedVector2Array],mask: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array]=[]
	for part in parts: result.append_array(Geometry2D.clip_polygons(part,mask))
	return result

static func _access_polygons(local := false) -> Array[PackedVector2Array]:
	if _access_corridors.is_empty():
		_prepare_roads()
	if not local: return _access_corridors
	return _local_corridors

static func _carve_roads(pieces: Array[PackedVector2Array],local: Vector2) -> Array[PackedVector2Array]:
	if LAYOUT.haul_sample(local).x<15.0 or (local.y>118 and local.x>-17 and local.x<30):
		for corridor in _access_polygons(true): pieces=_subtract(pieces,corridor)
	return pieces

static func _build_basefill(parent: Node3D,rect: Rect2) -> void:
	if not rect.has_area(): return
	var pieces: Array[PackedVector2Array]=[PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])]
	var outline := PackedVector2Array()
	for point in _ground_outline(): outline.append(point+Vector2(LAYOUT.CENTER.x,LAYOUT.CENTER.z))
	pieces=_subtract(pieces,outline)
	for corridor in _access_polygons(): pieces=_subtract(pieces,corridor)
	var faces := PackedVector3Array()
	for part in pieces:
		for index in Geometry2D.triangulate_polygon(part): faces.append(Vector3(part[index].x,0,part[index].y))
	_emit(parent,"MineSurroundingDesert",faces,DESERT_GEOMETRY.material(Color("b9a079"),true),faces)

static func _ground_outline() -> PackedVector2Array:
	if not _outline.is_empty(): return _outline
	# Contorno recortado exato, independente da grade de 3 m do terreno e das bordas de chunk.
	for i in 72:
		var angle := float(i)*TAU/72.0
		var south := maxf(sin(angle),0)
		var sectors := [0.0,9.0,-5.0,4.0,12.0,-7.0,5.0,-9.0,8.0,-4.0,11.0,-3.0]
		var sector := float(i) / 6.0
		var cut := lerpf(sectors[int(sector)%12],sectors[(int(sector)+1)%12],fposmod(sector,1.0))
		# Contorno de escavação quebrado mais forte ao norte; mantém o pátio
		# sul autorado, o acesso e a folga do estacionamento.
		var roughness := (sin(angle*5)*1.7+sin(angle*9)*1.2) + cut*(1.0-south)
		var radius := Vector2(136-36*south+roughness,136+17*south+roughness)
		_outline.append(LAYOUT.PIT_CENTER+Vector2(cos(angle),sin(angle))*radius)
	return _outline

static func bench_height(point: Vector2) -> float:
	return LAYOUT.terrain_height(point)

static func surface_height(point: Vector2) -> float:
	## Altura física dos mesmos triângulos emitidos acima, incluindo as transições
	## de bancada que cruzam a grade. Isto fica disponível a consultas de câmera/restauração.
	if not LAYOUT.enabled() or not OWNED_GROUND.has_point(point): return 0.0
	var road := _road_height(point)
	if is_finite(road): return road
	if not LAYOUT.BOUNDS.has_point(point): return 0.0
	var key := Vector2i(floori(point.x/GRID),floori(point.y/GRID))
	if not _height_tiles.has(key):
		var offset := Vector2(LAYOUT.CENTER.x,LAYOUT.CENTER.z)
		var a := Vector2(key)*GRID
		var c := a+Vector2.ONE*GRID
		a=a.max(LAYOUT.BOUNDS.position)
		c=c.min(LAYOUT.BOUNDS.end)
		var polygon := PackedVector2Array([a-offset,Vector2(c.x,a.y)-offset,c-offset,Vector2(a.x,c.y)-offset])
		var parts: Array[PackedVector2Array]=[]
		if ((a+c)*.5-offset-LAYOUT.PIT_CENTER).length()<110: parts.append(polygon)
		else: parts=Geometry2D.intersect_polygons(polygon,_ground_outline())
		parts=_carve_roads(parts,(a+c)*.5-offset)
		var tile_triangles := PackedVector3Array()
		for part in parts:
			for index in Geometry2D.triangulate_polygon(part):
				var p: Vector2=part[index]
				tile_triangles.append(Vector3(p.x+offset.x,bench_height(p),p.y+offset.y))
		_height_tiles[key]=tile_triangles
	var triangles: PackedVector3Array=_height_tiles[key]
	for i in range(0,triangles.size(),3):
		var a := Vector2(triangles[i].x,triangles[i].z)
		var b := Vector2(triangles[i+1].x,triangles[i+1].z)
		var c := Vector2(triangles[i+2].x,triangles[i+2].z)
		var divisor := (b-a).cross(c-a)
		if absf(divisor)<.00001: continue
		var u := (point-a).cross(c-a)/divisor
		var v := (b-a).cross(point-a)/divisor
		if u>=-.00001 and v>=-.00001 and u+v<=1.00001:
			var height := triangles[i].y*(1-u-v)+triangles[i+1].y*u+triangles[i+2].y*v
			return height
	return 0.0

static func _surface(wall: bool) -> ShaderMaterial:
	if _ground_material==null:
		_ground_material=ShaderMaterial.new()
		_ground_material.shader=GROUND_SHADER
		_ground_material.set_shader_parameter("ground_color",Color("615d55"))
		_ground_material.set_shader_parameter("world_origin",LAYOUT.CENTER)
		_wall_material=ShaderMaterial.new()
		_wall_material.shader=GROUND_SHADER
		_wall_material.set_shader_parameter("ground_color",Color("615d55"))
		_wall_material.set_shader_parameter("world_origin",LAYOUT.CENTER)
		_wall_material.set_shader_parameter("quarry_wall",true)
	return _wall_material if wall else _ground_material

static func _emit(parent: Node3D,label: String,faces: PackedVector3Array,mat: Material,solids: PackedVector3Array) -> void:
	if faces.is_empty(): return
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in faces: builder.add_vertex(p)
	builder.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name=label
	visual.mesh=builder.commit()
	visual.material_override=mat
	visual.set_meta("vehicle_surface","dirt")
	parent.add_child(visual)
	if not solids.is_empty():
		var body := StaticBody3D.new()
		body.name="QuarryBenchCollision"
		body.collision_layer=1
		body.collision_mask=0
		body.set_meta("vehicle_surface","dirt")
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(solids)
		var collider := CollisionShape3D.new()
		collider.shape=shape
		body.add_child(collider)
		visual.add_child(body)

static func _build_access(parent: Node3D,rect: Rect2) -> void:
	var chunk_polygon := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var faces := PackedVector3Array()
	_prepare_roads()
	for row in _road_triangles:
		if not rect.intersects(row.bounds,true): continue
		for part in Geometry2D.intersect_polygons(row.polygon,chunk_polygon):
			for index in Geometry2D.triangulate_polygon(part):
				var point: Vector2=part[index]
				faces.append(Vector3(point.x,_triangle_height(point,row.faces),point.y))
	# Cascalho claro compactado separa a espiral usável das bancadas brutas.
	# A cor pertence à mesma malha física: sem sobreposição flutuante nem z-fighting.
	if _road_material == null:
		_road_material = _surface(false).duplicate() as ShaderMaterial
		_road_material.set_shader_parameter("ground_color", Color("77766f"))
	_emit(parent,"MineGravelAccess",faces,_road_material,faces)

static func _prepare_roads() -> void:
	if not _road_triangles.is_empty(): return
	for record in LAYOUT.roads():
		var points: PackedVector3Array=record.points
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		for i in points.size():
			var before := points[i]-points[maxi(i-1,0)]
			var after := points[mini(i+1,points.size()-1)]-points[i]
			before.y=0; after.y=0
			if before.length_squared()<.001: before=after
			if after.length_squared()<.001: after=before
			before=before.normalized(); after=after.normalized()
			var tangent := (before+after).normalized()
			var side := Vector3(-tangent.z,0,tangent.x)
			var old_side := Vector3(-before.z,0,before.x)
			var width := float(record.width)*.5/maxf(absf(side.dot(old_side)),.65)
			left.append(points[i]-side*width+Vector3.UP*.018)
			right.append(points[i]+side*width+Vector3.UP*.018)
		var corridor := PackedVector2Array()
		for p in left: corridor.append(Vector2(p.x,p.z))
		for i in range(right.size()-1,-1,-1): corridor.append(Vector2(right[i].x,right[i].z))
		_access_corridors.append(corridor)
		var local := PackedVector2Array()
		for p in corridor: local.append(p-Vector2(LAYOUT.CENTER.x,LAYOUT.CENTER.z))
		_local_corridors.append(local)
		for i in range(1,points.size()):
			var vertices := PackedVector3Array([left[i-1],right[i-1],right[i],left[i]])
			var polygon := PackedVector2Array()
			for p in vertices: polygon.append(Vector2(p.x,p.z))
			var indices := Geometry2D.triangulate_polygon(polygon)
			for index in range(0,indices.size(),3):
				var triangle := PackedVector3Array([vertices[indices[index]],vertices[indices[index+1]],vertices[indices[index+2]]])
				var planar := PackedVector2Array()
				var bounds := Rect2(Vector2(triangle[0].x,triangle[0].z),Vector2.ZERO)
				for vertex in triangle:
					var p := Vector2(vertex.x,vertex.z)
					planar.append(p); bounds=bounds.expand(p)
				var row := {"polygon":planar,"faces":triangle,"bounds":bounds}
				_road_triangles.append(row)
				for x in range(floori(bounds.position.x/24),floori(bounds.end.x/24)+1):
					for z in range(floori(bounds.position.y/24),floori(bounds.end.y/24)+1):
						var key := Vector2i(x,z)
						if not _road_buckets.has(key): _road_buckets[key]=[]
						_road_buckets[key].append(row)

static func _triangle_height(point: Vector2,faces: PackedVector3Array) -> float:
	var a := Vector2(faces[0].x,faces[0].z)
	var b := Vector2(faces[1].x,faces[1].z)
	var c := Vector2(faces[2].x,faces[2].z)
	var divisor := (b-a).cross(c-a)
	if absf(divisor)<.000001: return faces[0].y
	var u := (point-a).cross(c-a)/divisor
	var v := (b-a).cross(point-a)/divisor
	return faces[0].y*(1-u-v)+faces[1].y*u+faces[2].y*v

static func _road_height(point: Vector2) -> float:
	_prepare_roads()
	var key := Vector2i(floori(point.x/24),floori(point.y/24))
	for row in _road_buckets.get(key,[]):
		if Geometry2D.is_point_in_polygon(point,row.polygon): return _triangle_height(point,row.faces)
	return INF

static func build_chunk(parent: Node3D, rect: Rect2) -> Array[OmniLight3D]:
	var lights: Array[OmniLight3D]=[]
	if not LAYOUT.enabled(): return lights
	var local_rect := Rect2(rect.position-Vector2(LAYOUT.CENTER.x,LAYOUT.CENTER.z),rect.size)
	if not rect.intersects(LAYOUT.BOUNDS):
		_build_access_markers(parent,rect)
		return lights
	# Spans (22/10): a etapa da mina custou 22–25 ms num quadro no deserto sem dizer onde.
	var span := STALL_WORK.begin()
	var batch := BATCH.new(parent,"MiningIndustrialExterior",LAYOUT.CENTER)
	if local_rect.has_point(Vector2(12,126)): _guardhouse(batch)
	STALL_WORK.finish_slow("mining.exterior.guardhouse", span, 2000)
	span = STALL_WORK.begin()
	if local_rect.has_point(Vector2(-45,100)): _parking(batch)
	if local_rect.has_point(Vector2(13,0)): _crusher(batch)
	if local_rect.has_point(Vector2(63,89)): _service_corner(batch)
	if local_rect.has_point(Vector2(LAYOUT.SECRET_EXTERIOR.x-LAYOUT.CENTER.x,LAYOUT.SECRET_EXTERIOR.z-LAYOUT.CENTER.z)): _hidden_adit(batch)
	STALL_WORK.finish_slow("mining.exterior.sites", span, 2000)
	span = STALL_WORK.begin()
	_dress_ore(batch,local_rect)
	STALL_WORK.finish_slow("mining.exterior.ore", span, 2000)
	span = STALL_WORK.begin()
	_fence(batch,local_rect)
	STALL_WORK.finish_slow("mining.exterior.fence", span, 2000)
	span = STALL_WORK.begin()
	for record in LAYOUT.light_stations():
		var p: Vector3=record.point
		if local_rect.has_point(Vector2(p.x,p.z)):
			_tower(batch,p,float(record.height))
			var light := OmniLight3D.new()
			light.name="MiningFloodlight_"+str(record.id)
			light.position=LAYOUT.CENTER+p+Vector3(0,float(record.height)-.35,0)
			light.light_color=Color("ffdab0")
			light.light_energy=0.0
			light.omni_range=float(record.range)
			light.omni_attenuation=1.5
			light.shadow_enabled=false
			light.set_meta("mining_light_energy",float(record.energy))
			parent.add_child(light)
			lights.append(light)
	STALL_WORK.finish_slow("mining.exterior.towers", span, 2000)
	span = STALL_WORK.begin()
	batch.finish()
	STALL_WORK.finish_slow("mining.exterior.finish", span, 2000)
	span = STALL_WORK.begin()
	preload("res://world/mining/MiningRouteDressing.gd").build(parent, local_rect, surface_height)
	STALL_WORK.finish_slow("mining.exterior.route", span, 2000)
	if local_rect.has_point(Vector2(13, 0)):
		var ambience := preload("res://audio/mining/MiningAmbience.gd").new()
		ambience.position = LAYOUT.CENTER + Vector3(13, -26, 0)
		parent.add_child(ambience)
	_build_access_markers(parent,rect)
	return lights

## Escritório da mina pintado (PaintedFacadeKit, estilo escritorio-mina) no lugar
## da guarita de caixas: 10 m ao longo da estrada (z 121..131), 5 m de fundo
## (x 9,5..14,5), de frente para a pista; o portão em z=134 fica livre.
static func _painted_office(b: RefCounted, at: Vector3) -> bool:
	const STYLE := "escritorio-mina"
	if not PaintedFacadeKit.enabled() or not FileAccess.file_exists(PaintedFacadeKit.ROOT+STYLE+"/style.json"): return false
	const OFFICE := preload("res://world/mining/MiningOffice.gd")
	if OFFICE.available():
		# Escritório acessível (29/10): porta de empurrar e sala `mining_office`.
		var office := preload("res://world/mining/MiningOfficeFacade.gd").new()
		office.position=OFFICE.AT
		office.rotation.y=OFFICE.YAW
		b.root.add_child(office)
		return true
	var holder := Node3D.new()
	holder.name="MiningOffice"
	holder.position=at
	holder.rotation.y=-PI*.5
	b.root.add_child(holder)
	var natural := PaintedFacadeKit.natural_size(STYLE)
	PaintedFacadeKit.build(holder,STYLE,Vector3(natural.x,natural.y,5.0),holder,NAN,{"snow":false})
	return true

static func _guardhouse(b: RefCounted) -> void:
	var at := Vector3(12,0,126)
	if _painted_office(b,at): _gate(b); return
	b.box("GuardhouseFoundation",at+Vector3(0,.13,0),Vector3(5,.26,4.8),"concrete",true)
	b.box("GuardhouseClosedBody",at+Vector3(0,1.55,0),Vector3(4.4,2.85,4.2),"cream",true)
	b.box("GuardhouseRustRoof",at+Vector3(0,3.07,0),Vector3(5.05,.24,4.85),"rust",true)
	for side in [-1.0,1.0]:
		b.box("GuardhouseWindow",at+Vector3(side*2.213,1.88,-.2),Vector3(.032,1.1,2.3),"glass")
		b.box("WindowFrame",at+Vector3(side*2.24,1.87,-.2),Vector3(.04,.07,2.4),"steel")
	b.box("GuardhouseFrontWindow",at+Vector3(.45,1.9,2.113),Vector3(2.25,1.04,.035),"glass")
	b.box("GuardhouseDoor",at+Vector3(-1.3,1.25,2.13),Vector3(.85,2.2,.08),"steel")
	b.box("GuardhouseLowerDirt",at+Vector3(0,.38,2.143),Vector3(4.35,.27,.045),"trail")
	for x in [-.6,.5,1.6]: b.box("WindowMullion",at+Vector3(x,1.9,2.144),Vector3(.055,1.06,.055),"white")
	b.box("AirConditioner",at+Vector3(2.43,.8,1.0),Vector3(.5,.65,1.1),"steel",true)
	for i in 5: b.box("AirConditionerSlat",at+Vector3(2.70,.59+float(i)*.1,1),Vector3(.025,.035,.91),"rubber")
	_gate(b)

static func _gate(b: RefCounted) -> void:
	# A cancela levantada parece uma obra em funcionamento e nunca bloqueia o acesso.
	for x in [-8.9,8.9]:
		b.box("GateBollard",Vector3(x,.75,134),Vector3(.4,1.5,.4),"yellow",true)
		b.box("GateBollardBand",Vector3(x,.87,134),Vector3(.42,.26,.42),"rubber")
	b.box("RaisedBarrier",Vector3(8.95,3.28,134),Vector3(.16,5.1,.18),"white",true,Vector3(0,0,-.18))
	for y in [1.45,2.3,3.15,4.0,4.85]: b.box("BarrierStripe",Vector3(8.95+(y-3.28)*.18,y,134.105),Vector3(.18,.32,.025),"red",false,Vector3(0,0,-.18))
	b.box("GateNamePanel",Vector3(-10,2.5,132),Vector3(6.4,1.4,.15),"steel",true)
	for x in [-12.7,-7.3]: b.box("NamePanelLeg",Vector3(x,1.3,132),Vector3(.14,2.6,.14),"steel",true)
	var name_label := Label3D.new()
	name_label.name="MineProperName"
	name_label.text="SERRA BRUTA"
	name_label.position=Vector3(-10,2.52,132.10)
	name_label.font_size=58
	name_label.pixel_size=.011
	name_label.modulate=Color("ddcba2")
	name_label.outline_size=0
	b.root.add_child(name_label)

static func _parking(b: RefCounted) -> void:
	# Os veículos dos funcionários são instâncias reais de frota pertencentes a MiningOperation.
	for i in 7: b.box("WornParkingStripe",Vector3(-61+float(i)*4.7,.030,100),Vector3(.12,.018,7.2),"white")
	for i in 6:
		b.box("WheelStop",Vector3(-58.65+float(i)*4.7,.13,96.4),Vector3(2.2,.26,.3),"concrete",true)
	b.box("ParkingFarEdge",Vector3(-46,.18,93.9),Vector3(34,.36,.35),"concrete",true)
	# Banco e armários ficam atrás dos batentes do estacionamento, fora das manobras dos carros.
	b.box("BreakBenchSeat",Vector3(-64,.48,88),Vector3(3,.13,.65),"timber",true)
	b.box("BreakBenchBack",Vector3(-64,.92,87.71),Vector3(3,.7,.08),"timber",true)
	for x in [-65,-63]: b.box("BreakBenchLeg",Vector3(x,.23,88),Vector3(.16,.46,.5),"steel",true)
	for i in 3: b.box("WorkerLocker",Vector3(-63+float(i)*.8,1.08,82),Vector3(.75,2.16,.7),"blue",true)

static func _crusher(b: RefCounted) -> void:
	var at := Vector3(13,-28,0)
	for x in [-3.6,3.6]:
		for z in [-3.5,3.5]:
			b.box("CrusherFoot",at+Vector3(x,.2,z),Vector3(1.4,.4,1.4),"concrete",true)
			b.box("CrusherSteelLeg",at+Vector3(x,3.2,z),Vector3(.36,6.4,.36),"steel",true)
		b.beam("CrusherDiagonal",at+Vector3(x,.4,-3.5),at+Vector3(x,5.8,3.5),.2,"rust")
	b.box("CrusherJaw",at+Vector3(0,3.15,0),Vector3(5.7,3.8,5.6),"yellow",true)
	b.box("CrusherMouth",at+Vector3(0,5.15,0),Vector3(7.2,.32,6.7),"rust",true)
	b.box("HopperDarkOpening",at+Vector3(0,5.32,0),Vector3(6.2,.06,5.7),"ore_dark")
	for side in [-1.0,1.0]:
		b.box("HopperRim",at+Vector3(side*3.45,5.75,0),Vector3(.28,1.2,6.7),"yellow",true,Vector3(0,0,side*.24))
		b.box("HopperEnd",at+Vector3(0,5.75,side*3.15),Vector3(7,1.2,.28),"yellow",true,Vector3(-side*.24,0,0))
	b.cylinder("CrusherDriveMotor",at+Vector3(-3.32,2.45,0),1.1,1.2,"steel",true,Vector3(0,0,PI*.5))
	# Caixa de engrenagens, nervuras da mandíbula e placas de inspeção aparafusadas deixam o maquinário
	# legível em escala humana. Todo ornamento abraça o envelope sólido existente.
	for x in [-2.45,-1.75,-1.05,-.35,.35,1.05,1.75,2.45]:
		b.box("CrusherJawRib",at+Vector3(x,3.15,2.83),Vector3(.12,3.1,.06),"rust")
	for side in [-1.0,1.0]:
		b.box("CrusherInspectionPlate",at+Vector3(side*2.87,2.7,.3),Vector3(.055,1.15,1.7),"steel")
		for y in [2.22,3.18]:
			for z in [-.43,1.03]: b.box("CrusherPlateBolt",at+Vector3(side*2.91,y,z),Vector3(.08,.11,.11),"cream")
		for y in [1.6,1.95,2.3,2.65,3.0,3.35,3.7]:
			b.box("MotorCoolingRib",at+Vector3(-3.32,y,side*.77),Vector3(1.14,.055,.10),"rubber")
	# A escada de manutenção com guarda fica fisicamente no britador, longe do
	# corredor do piso; os degraus estreitos encostam na face frontal já sólida.
	for x in [-.63,.63]: b.box("CrusherLadderRail",at+Vector3(x,2.75,2.9),Vector3(.075,4.5,.075),"steel")
	for index in 13: b.box("CrusherLadderRung",at+Vector3(0,.65+float(index)*.33,2.93),Vector3(1.26,.075,.075),"steel")
	# A diagonal ore belt ties the crusher to a stockpile, leaving the floor
	# underneath visually and physically readable (no invisible tall box).
	var start := at+Vector3(0,1.7,-3)
	var end := at+Vector3(-27,7.5,-23)
	var direction := end-start
	var basis := Basis.looking_at(direction.normalized(),Vector3.UP)
	b.box("ConveyorBelt",(start+end)*.5,Vector3(2.15,.2,direction.length()),"rubber",true,basis.get_euler())
	for side in [-1.0,1.0]:
		var lateral: Vector3=basis.x*float(side)*1.18
		b.beam("BeltSideTruss",start+lateral+Vector3(0,.35,0),end+lateral+Vector3(0,.35,0),.18,"rust")
		for i in 7:
			var p: Vector3=start.lerp(end,float(i)/6.0)+lateral
			b.box("BeltSupport",Vector3(p.x,at.y+(p.y-at.y)*.5,p.z),Vector3(.19,p.y-at.y,.19),"steel",true)
	for i in 8:
		var p := start.lerp(end,float(i)/8.0)
		b.rock("ConveyorOre",p+Vector3(0,.30,0),Vector3(.65,.40,.70),"ore_dark",false,float(i))
	for index in 19:
		var p := start.lerp(end, float(index)/18.0)
		b.box("ConveyorBeltJoint",p+Vector3.UP*.108,Vector3(2.04,.016,.05),"steel",false,basis.get_euler())
		for side in [-1.0,1.0]:
			var edge: Vector3 = basis.x * side * 1.19
			b.box("ConveyorFrameBracket",p+edge,Vector3(.23,.28,.14),"steel",false,basis.get_euler())
	b.rock("StockpileCore",Vector3(end.x,at.y+1.75,end.z),Vector3(11.5,4.2,10),"ore_dark",true,.2)
	for i in 10:
		var angle := float(i)*2.399
		b.rock("ConveyorStockpile",end+Vector3(cos(angle)*3.7,-6.2+float(i%3)*.65,sin(angle)*2.7),Vector3(4.4,3.1,3.8),"ore",true,angle)
	# As mesas de triagem ficam de propósito fora do quadrado de manobra das máquinas principais.
	b.box("OreSampleBench",at+Vector3(-9.4,.84,11),Vector3(2.2,.14,1.2),"steel",true)
	for x in [-10.2,-8.6]: b.box("SampleBenchLeg",at+Vector3(x,.41,11),Vector3(.15,.82,1),"steel",true)
	for i in 5: b.rock("SortedOre",at+Vector3(-10.2+float(i)*.36,1.01,11),Vector3(.28,.24,.35),"ore_light",false)

static func _service_corner(b: RefCounted) -> void:
	var at := Vector3(63,0,89)
	b.box("ServiceContainer",at+Vector3(0,1.45,0),Vector3(12,2.9,4.2),"blue",true)
	b.box("ContainerRoof",at+Vector3(0,2.95,0),Vector3(12.25,.12,4.4),"rust")
	for i in 27: b.box("ContainerCorrugation",at+Vector3(-5.8+float(i)*.44,1.5,2.15),Vector3(.09,2.75,.12),"steel")
	for x in [-4.0,4.0]:
		b.box("ContainerDoor",at+Vector3(x,1.47,-2.13),Vector3(2.3,2.55,.065),"blue")
		b.box("DoorLockBar",at+Vector3(x+.65,1.47,-2.18),Vector3(.045,2.42,.045),"steel")
	for i in 4:
		var p := at+Vector3(9+float(i%2)*1.2,0,-1.5+floori(float(i)/2.0)*1.2)
		b.cylinder("OilDrum",p+Vector3(0,.56,0),.46,1.12,"rust",true)
		for y in [.23,.88]: b.cylinder("DrumBand",p+Vector3(0,y,0),.48,.07,"steel")
	b.cylinder("DieselTank",Vector3(74,1.45,70),1.35,6.0,"cream",true,Vector3(0,0,PI*.5))
	for x in [72,76]: b.box("TankCradle",Vector3(x,.45,70),Vector3(.45,.9,2.3),"rust",true)
	b.box("DieselPump",Vector3(70,.92,72.3),Vector3(.65,1.84,.62),"yellow",true)
	for i in 5: b.cylinder("SpareHaulerTyre",Vector3(66.8+float(i%2)*2.1,.29+floori(float(i)/2.0)*.57,78),1.06,.57,"rubber",true)
	for i in 5: b.box("TimberPile",Vector3(73,.18+float(i)*.21,96),Vector3(7,.18,.36),"timber",true,Vector3(0,float(i%2)*.05,0))

static func _hidden_adit(b: RefCounted) -> void:
	var at := LAYOUT.SECRET_EXTERIOR-LAYOUT.CENTER
	# Abertura livre real de 2.8 m com lados e verga sólidos. O fundo escuro fica
	# além do ponto de transição do NativePlace; nenhum sólido se esconde sob a entrada.
	for side in [-1.0,1.0]:
		b.box("OldAditTimber",at+Vector3(side*1.64,1.58,0),Vector3(.37,3.16,.48),"timber",true)
		b.rock("AditRockShoulder",at+Vector3(side*3.7,1.45,-1.1),Vector3(4,3.4,4.6),"ore_dark",true,side*.4)
	b.box("OldAditLintel",at+Vector3(0,3.14,0),Vector3(3.85,.38,.54),"timber",true)
	b.box("AditRoof",at+Vector3(0,3.26,-1.7),Vector3(3.7,.4,3.4),"ore_dark",true)
	b.box("AditRecess",at+Vector3(0,1.48,-3.15),Vector3(3.05,2.96,.15),"recess",true)
	for side in [-1.0,1.0]: b.box("AditInnerSide",at+Vector3(side*1.49,1.48,-1.6),Vector3(.15,2.96,3.2),"recess",true)
	b.rock("AditOverburden",at+Vector3(0,4.1,-1.6),Vector3(6.6,2.1,5.5),"ore_dark",true,.17)
	for i in 14:
		var spread := sin(float(i)*2.399)*(.35+float(i%3)*.3)
		b.rock("EscapedCoal",at+Vector3(spread,.045,-1.2+float(i)*.49),Vector3(.25,.12,.28),"coal",false,float(i))
	for z in [-2.7,-1.4,.1]:
		b.box("BuriedMineSleeper",at+Vector3(0,.039,z),Vector3(2.0,.07,.18),"timber")
	for side in [-1.0,1.0]: b.box("OldMineRail",at+Vector3(side*.58,.07,-.6),Vector3(.08,.1,5.1),"rust")
	# Um carrinho meio enterrado e uma pilha irregular encobrem a abertura na diagonal;
	# toda a aproximação sul e o ponto de retorno continuam desobstruídos.
	b.box("AbandonedOreCart",at+Vector3(-4.8,.74,3.0),Vector3(1.7,1.3,2.3),"rust",true,Vector3(0,.32,.12))
	b.box("CartCoal",at+Vector3(-4.8,1.37,3),Vector3(1.42,.10,2.04),"coal")
	for side in [-1.0,1.0]:
		for z in [2.4,3.55]:
			b.cylinder("AbandonedCartWheel",at+Vector3(-4.8+side*.85,.3,z),.29,.12,"steel",false,Vector3(0,0,PI*.5))
		b.box("CartSideBrace",at+Vector3(-4.8+side*.84,.8,3),Vector3(.06,.10,2.12),"steel",false,Vector3(0,.32,.12))
	# Rebites, madeira lascada e cintas de reparo ficam na moldura do portal;
	# o marcador de retorno e a abertura inteira mantêm o espaço livre existente.
	for side in [-1.0,1.0]:
		for y in [.45,1.7,2.7]:
			b.box("AditTimberRepairStrap",at+Vector3(side*1.64,y,.25),Vector3(.39,.13,.025),"steel")
			for dx in [-.12,.12]: b.box("AditStrapBolt",at+Vector3(side*1.64+dx,y,.272),Vector3(.06,.06,.02),"rust")
		for y in [.75,1.3,2.2]:
			b.box("AditTimberSplit",at+Vector3(side*1.67,y,.248),Vector3(.022,.37,.018),"recess",false,Vector3(0,0,side*.13))
	for i in 6: b.rock("HiddenAditSpoil",at+Vector3(6.5+float(i%2)*1.4,.4+float(i%3)*.33,2+float(i)*1.3),Vector3(2.6,1.8,2.3),"ore_dark",true,float(i))

static func _tower(b: RefCounted, at: Vector3, height: float) -> void:
	b.box("FloodlightFoot",at+Vector3(0,.2,0),Vector3(1.05,.4,1.05),"concrete",true)
	b.box("FloodlightPole",at+Vector3(0,height*.5,0),Vector3(.19,height,.19),"steel",true)
	b.box("FloodlightCrossarm",at+Vector3(0,height,0),Vector3(2.0,.13,.16),"steel")
	for side in [-1.0,1.0]:
		b.box("FloodlightHousing",at+Vector3(side*.67,height-.10,0),Vector3(.67,.36,.48),"steel")
		b.box("FloodlightLens",at+Vector3(side*.67,height-.29,.05),Vector3(.55,.032,.38),"lamp")

static func _dress_ore(b: RefCounted, rect: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=610202607
	for i in 68:
		var angle := rng.randf_range(deg_to_rad(145),deg_to_rad(395))
		var radius := rng.randf_range(43,116)
		var p := LAYOUT.PIT_CENTER+Vector2(cos(angle),sin(angle))*radius
		if not rect.has_point(p) or LAYOUT.SECRET_RESERVE.grow(3).has_point(p): continue
		if LAYOUT.haul_sample(p).x<13.0: continue
		# Mantém o piso do caminhão aberto, incluindo o quadrado de teste de carga compartilhado.
		if p.length()<43: continue
		var size := Vector3(rng.randf_range(1.6,4.8),rng.randf_range(1,3),rng.randf_range(1.7,4.2))
		b.rock("BlastedOreBoulder",Vector3(p.x,bench_height(p)+size.y*.42,p.y),size,["ore","ore_dark","ore_light"][i%3],true,angle)
	# Manchas de terra compactada, madeira espalhada e pedrinhas deixam o pátio gasto;
	# nenhuma obstrução física minúscula é espalhada no corredor dirigível.
	for i in 32:
		var p := Vector2(rng.randf_range(-74,77),rng.randf_range(52,126))
		if not rect.has_point(p): continue
		if LAYOUT.haul_sample(p).x<9.0: continue
		b.rock("ApronGravel",Vector3(p.x,bench_height(p)+.055,p.y),Vector3(.42,.13,.36),"ore_dark",false,rng.randf()*TAU)
	for p in [Vector2(-22,73),Vector2(67,64),Vector2(-67,113)]:
		if rect.has_point(p) and absf(bench_height(p))<.01: b.cylinder("OilStain",Vector3(p.x,.028,p.y),2.1,.008,"trail",false)

static func _fence(b: RefCounted, rect: Rect2) -> void:
	for endpoints in [[Vector2(-135,134),Vector2(-15,134)],[Vector2(8,134),Vector2(74,124)],[Vector2(-135,134),Vector2(-142,-25)],[Vector2(74,124),Vector2(132,49)]]:
		var a: Vector2=endpoints[0]
		var c: Vector2=endpoints[1]
		var pieces := ceili(a.distance_to(c)/5.0)
		for i in pieces:
			var p := a.lerp(c,float(i)/float(pieces))
			var q := a.lerp(c,float(i+1)/float(pieces))
			if not rect.has_point((p+q)*.5): continue
			b.box("PerimeterPost",Vector3(p.x,1.25,p.y),Vector3(.12,2.5,.12),"steel",true)
			# Os fios de arame deixam o sítio legível de fora; duas vigas dão um limite
			# físico explícito em vez de uma parede de colisão transparente.
			for y in [.56,1.28,2.02]: b.beam("PerimeterCable",Vector3(p.x,y,p.y),Vector3(q.x,y,q.y),.04,"cable",y<1.3)
			for j in 5:
				var v := p.lerp(q,float(j)/5.0)
				b.beam("FenceWire",Vector3(v.x,.3,v.y),Vector3(v.x,2.15,v.y),.018,"steel")

static func _build_access_markers(parent: Node3D,rect: Rect2) -> void:
	var b: RefCounted = null
	for i in range(1,LAYOUT.ACCESS.size()-1):
		var p: Vector2=LAYOUT.ACCESS[i]
		if not rect.has_point(p): continue
		if b==null: b=BATCH.new(parent,"QuarryAccessMarkers")
		for side in [-1.0,1.0]:
			b.box("RoadEdgeStake",Vector3(p.x+side*7,.48,p.y),Vector3(.12,.96,.12),"timber",true)
			b.box("StakeReflector",Vector3(p.x+side*7,.8,p.y+.071),Vector3(.15,.19,.027),"white")
	if b!=null: b.finish()
