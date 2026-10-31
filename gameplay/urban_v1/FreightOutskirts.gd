extends Node3D
## Extensão rural nas coordenadas de mundo do Harbor. OriginalWorldData é dono do
## chão físico e da via em streaming; este nó acrescenta mata estática, agrupada
## espacialmente, sem outro colisor de piso sobreposto nem loop por quadro.
const LAND := Rect2(-430, -160, 350, 318)
const SECRET_CELLAR_OPENING := Rect2(-413.25,85.35,6.10,3.30)
const SITE_CLEARANCE := Rect2(-394, -118, 111, 125)
const ROAD := [Vector2(-55,137.5), Vector2(-65,144), Vector2(-105,144),
	Vector2(-120,118),Vector2(-120,70),Vector2(-145,34),
	Vector2(-200,34), Vector2(-250,10), Vector2(-290,10), Vector2(-320,18),
	Vector2(-340,18), Vector2(-340,-2)]
const CELL := 64.0
const VILLAGE_ROAD := [Vector2(-290,10),Vector2(-290,32),Vector2(-285,48),
	Vector2(-286,66),Vector2(-290,82),Vector2(-304,95)]
var tree_positions: Array[Vector3] = []
var _batches: Dictionary = {}
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _trunks: StaticBody3D

func _ready() -> void:
	name = "FreightOutskirts"
	_build_resources()
	_trunks = StaticBody3D.new()
	_trunks.name = "WoodlandTrunks"
	add_child(_trunks)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9282026
	# Uma grade solta e irregular impede troncos se cruzando e mantém todas as
	# malhas de copa longe do corredor dos caminhões e da cerca da empresa.
	for x in range(-422, -99, 12):
		for z in range(-150, 151, 12):
			var point := Vector2(float(x)+rng.randf_range(-3.5,3.5),float(z)+rng.randf_range(-3.5,3.5))
			if not _available(point,11.0) or rng.randf()<0.12: continue
			_tree(point,rng)
	for index in 580:
		var point := Vector2(rng.randf_range(-422,-101),rng.randf_range(-153,150))
		if not _available(point,8.1): continue
		var scale_value := rng.randf_range(0.5,1.25)
		var tint := Color(.86,.95,.82).lerp(Color(.99,.96,.80),rng.randf())
		_put("shrub",Vector3(point.x,0.36*scale_value,point.y),Vector3(1.2,0.65,1.0)*scale_value,rng.randf()*TAU,tint)
	for index in 72:
		var point := Vector2(rng.randf_range(-422,-101),rng.randf_range(-153,150))
		if not _available(point,8.6): continue
		# Pedras baixas ficam abaixo de um passo normal de caminhada, não pedregulhos sólidos falsos.
		_put("stone",Vector3(point.x,0.055,point.y),Vector3(rng.randf_range(.25,.65),.11,rng.randf_range(.3,.8)),rng.randf()*TAU,Color.WHITE)
	for index in 12000:
		var point := Vector2(rng.randf_range(-422,-101),rng.randf_range(-153,150))
		if not _available(point,5.0): continue
		var size_value := rng.randf_range(.85,1.75)
		_put("grass",Vector3(point.x,-.02,point.y),Vector3.ONE*size_value,rng.randf()*TAU,Color(.9,1,.85))
	_flush()

static func _available(point: Vector2, road_clearance: float) -> bool:
	# Reserva o parque de motocross marcado e o acesso dele; troncos não podem furar rampas.
	if preload("res://activities/motocross/MotocrossCourse.gd").BOUNDS.grow(4).has_point(point): return false
	if Rect2(-229,-40,9,75).has_point(point): return false
	# Mantém livres a varanda de aluguel, os bancos de piquenique e as vagas de moto.
	if Rect2(-240,-41,30,18).grow(2).has_point(point): return false
	if SITE_CLEARANCE.grow(5.0).has_point(point): return false
	# Mantém a vila, os caminhos dos quintais e a aproximação dos caminhões sem troncos.
	if Rect2(-418,62,176,88).grow(5.0).has_point(point): return false
	for index in VILLAGE_ROAD.size()-1:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,VILLAGE_ROAD[index],VILLAGE_ROAD[index+1])) < 10.0: return false
	for index in ROAD.size()-1:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,ROAD[index],ROAD[index+1]))<road_clearance: return false
	return true

func _build_resources() -> void:
	# Uma malha de madeira compartilhada inclui o tronco afunilado e quatro galhos bifurcados.
	# As faces escuras/claras parecem sulcos longos de casca sem amostrar textura.
	_meshes["trunk"] = _wood_mesh()
	for variant in 3: _meshes["crown_%d"%variant] = _canopy_mesh(variant)
	var crown := SphereMesh.new()
	crown.radius = 0.5
	crown.height = 1.0
	crown.radial_segments = 9
	crown.rings = 5
	_meshes["shrub"] = _shrub_mesh()
	_meshes["stone"] = crown
	_meshes["grass"] = preload("res://world/urban_detail/HarborGrassTufts.gd")._tuft_mesh()
	_materials["grass"] = preload("res://activities/motocross/MotocrossGroundDetail.gd").grass_material()
	for entry in [["trunk",Color("514232")],["crown_0",Color("364a32")],["crown_1",Color("53613b")],
		["crown_2",Color("435637")],["shrub",Color("4b6039")],["stone",Color("777c6c")]]:
		var material := StandardMaterial3D.new()
		material.albedo_color = entry[1]
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.94
		_materials[entry[0]] = material

static func _face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b-a).cross(c-a).normalized()
	# No Godot as faces frontais são horárias. Mantém as normais para fora e expõe a casca.
	for point in [a,c,b]:
		surface.set_normal(normal)
		surface.set_color(tint)
		surface.add_vertex(point)

static func _limb(surface: SurfaceTool, start: Vector3, finish: Vector3, radius: float, taper: float, sides: int) -> void:
	var axis := finish-start
	var local_basis := Basis(Quaternion(Vector3.UP,axis.normalized()))
	for side in sides:
		var a := TAU*float(side)/float(sides)
		var b := TAU*float(side+1)/float(sides)
		var bottom_a := start+local_basis*Vector3(cos(a)*radius,0,sin(a)*radius)
		var bottom_b := start+local_basis*Vector3(cos(b)*radius,0,sin(b)*radius)
		var top_a := finish+local_basis*Vector3(cos(a)*radius*taper,0,sin(a)*radius*taper)
		var top_b := finish+local_basis*Vector3(cos(b)*radius*taper,0,sin(b)*radius*taper)
		var shade := .68 + .11*float(side%4)
		var tint := Color(shade,shade*.98,shade*.93)
		_face(surface,bottom_a,top_a,top_b,tint)
		_face(surface,bottom_a,top_b,bottom_b,tint)
		_face(surface,finish,top_b,top_a,tint)

static func _shrub_mesh() -> ArrayMesh:
	# Substitui o arbusto esférico antigo por 12 folhas largas dobradas (48 triângulos).
	# Mesma área, posições e lotes de MultiMesh; sem instâncias/física acrescentadas.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for leaf in 12:
		var angle := float(leaf)*2.39996
		var outer := leaf < 7
		var direction := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))
		var base := Vector3(0,-.50,0)+direction*.035
		var tip := direction*(.48 if outer else .31)+Vector3.UP*(.02+sin(angle)*.10 if outer else .43)
		var middle := base.lerp(tip,.57)
		var width := .115 if outer else .092
		var left := middle+side*width
		var right := middle-side*width
		var crest := middle+Vector3.UP*.065
		var tint := Color.WHITE.darkened(.10+float(leaf%3)*.055)
		_face(surface,base,left,crest,tint.darkened(.10))
		_face(surface,left,tip,crest,tint)
		_face(surface,tip,right,crest,tint.lightened(.035))
		_face(surface,right,base,crest,tint.darkened(.06))
	return surface.commit()

static func _wood_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_limb(surface,Vector3(0,-.008,0),Vector3(0,.67,0),.04,.72,8)
	for root_index in 5:
		var angle := root_index*TAU/5
		_limb(surface,Vector3(0,.02,0),Vector3(cos(angle)*.11,-.003,sin(angle)*.11),.012,.15,5)
	# Mantém as seções dos galhos em unidades normalizadas de altura da árvore e então escala
	# X/Z por raio/.04 e Y pela altura total (evita galhos gigantes achatados).
	for index in 4:
		var angle := float(index)*2.39+.3
		var start := Vector3(0,.35+float(index)*.045,0)
		var finish := Vector3(cos(angle)*(.16+index*.014),.60+index*.038,sin(angle)*(.16+index*.014))
		_limb(surface,start,finish,.0172,.14,6)
	return surface.commit()

static func _canopy_mesh(variant: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centers := [Vector3(-.05,.03,0),Vector3(.28,-.12,.12),Vector3(-.27,-.05,-.10),Vector3(.08,.29,-.07),Vector3(-.05,-.07,.31)]
	var sizes := [Vector3(.38,.40,.34),Vector3(.28,.29,.25),Vector3(.29,.33,.26),Vector3(.27,.29,.26),Vector3(.29,.26,.25)]
	for mass in centers.size():
		var center: Vector3 = centers[mass]
		center.x *= 1.0 + float(variant)*.08
		center.z += sin(float(mass+variant)*1.7)*.065
		var size: Vector3 = sizes[mass]
		size.y *= 1.0 + sin(float(variant*3+mass))*.16
		var tint := Color.WHITE.darkened(.055*float((mass+variant)%3))
		for ring in 4:
			for side in 7:
				var points: Array[Vector3] = []
				for corner in [Vector2i(side,ring),Vector2i(side+1,ring),Vector2i(side+1,ring+1),Vector2i(side,ring+1)]:
					var angle := TAU*float(corner.x)/7.0
					var latitude := PI*float(corner.y)/4.0
					var wobble := 1.0 + sin(angle*3.0+float(mass+variant)*1.7+latitude)*.11
					points.append(center+Vector3(cos(angle)*sin(latitude)*wobble,cos(latitude),sin(angle)*sin(latitude)*wobble)*size)
				if ring > 0: _face(surface,points[0],points[1],points[2],tint)
				if ring < 3: _face(surface,points[0],points[2],points[3],tint)
	return surface.commit()

func _tree(point: Vector2, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(7.0,12.0)
	var radius := rng.randf_range(0.24,0.39)
	var trunk_height := height*0.67
	var trunk_center := Vector3(point.x,trunk_height*0.5,point.y)
	_put("trunk",Vector3(point.x,0,point.y),Vector3(radius/.04,height,radius/.04),rng.randf()*TAU,Color.WHITE)
	var crown_size := rng.randf_range(4.3,6.4)
	_put("crown_%d"%rng.randi_range(0,2),Vector3(point.x,height*0.70,point.y),Vector3(crown_size,height*.54,crown_size*.94),rng.randf()*TAU,Color.WHITE)
	if preload("res://runtime/FishingLocation.gd").reserved(point,2.5): return
	if preload("res://world/places/amusement_park/AmusementParkLayout.gd").reserved(point,3.5): return
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = trunk_height
	collider.shape = shape
	collider.position = trunk_center
	_trunks.add_child(collider)
	tree_positions.append(Vector3(point.x,0,point.y))

func _put(kind: String, point: Vector3, scale_value: Vector3, yaw: float, tint: Color) -> void:
	if preload("res://runtime/FishingLocation.gd").reserved(Vector2(point.x,point.z),2.5 if kind == "trunk" or kind.begins_with("crown_") else .7): return
	if preload("res://world/places/amusement_park/AmusementParkLayout.gd").reserved(Vector2(point.x,point.z),3.5 if kind == "trunk" or kind.begins_with("crown_") else .7): return
	var cell := Vector2i(floori(point.x/CELL),floori(point.z/CELL))
	var key := "%s_%d_%d" % [kind,cell.x,cell.y]
	if not _batches.has(key): _batches[key] = {"kind":kind,"cell":cell,"transforms":[],"colors":[]}
	var local := point-Vector3(cell.x*CELL,0,cell.y*CELL)
	_batches[key].transforms.append(Transform3D(Basis(Vector3.UP,yaw).scaled(scale_value),local))
	_batches[key].colors.append(tint)

func _flush() -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _meshes[batch.kind]
		multimesh.instance_count = batch.transforms.size()
		for index in batch.transforms.size():
			multimesh.set_instance_transform(index,batch.transforms[index])
			multimesh.set_instance_color(index,batch.colors[index])
		var display := MultiMeshInstance3D.new()
		display.name = key
		display.position = Vector3(batch.cell.x*CELL,0,batch.cell.y*CELL)
		display.multimesh = multimesh
		display.material_override = _materials[batch.kind]
		if batch.kind in ["shrub","stone","grass"]: display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if batch.kind=="grass":
			display.visibility_range_end = 100
			display.visibility_range_end_margin = 15
		add_child(display)
	_batches.clear()
