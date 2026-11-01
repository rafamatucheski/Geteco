extends RefCounted
## Chão base do porto (Land e o recorte da ponte unificada), tronco físico das árvores e a caixa `_box`,
## separados do NativeRegion em 01/11 só para ele caber na leitura. O estado (region_id, materiais)
## continua no NativeRegion, que mantém cada função antiga como delegação de uma linha com a mesma
## assinatura, então EditableRegion (`_tree_collision`) e testes (`native._land_piece`) não mudam.
## `g` fica como Node3D, e não como o script do NativeRegion, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.` (`g._box`, `g._land_outside_bridge`,
## `g._material`): se uma subclasse sobrescrever alguma delas, o despacho continua igual ao de antes.
## Roda só na thread principal (estágio de build do chunk), como antes.

const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _tree_collision(tree: Node3D, chunk: Node3D) -> void:
	var trunk: MeshInstance3D = g._box(tree,"TrunkSolid",Vector3(0,1.4,0),Vector3(.4,2.8,.4),Color("00000000"),true)
	trunk.visible = false
	if g.region_id in ["mountain","harbor"]:
		# Mantém só o tronco físico: o proxy escondido não pode virar um estilhaço visível.
		trunk.get_child(0).reparent(tree)
		trunk.free()
		var radius := .4 * maxf(tree.global_basis.x.length(),tree.global_basis.z.length())
		# Pinheiro da serra (29/10): era "desert_tree", que vira destroço rígido e some por
		# transparência, levando o material do pinheiro ao passe alfa sem pré-aquecimento.
		# "woodland_tree" tomba na base e fica caído; o trecho reconstruído o traz de pé.
		preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("harbor_tree" if g.region_id == "harbor" else "woodland_tree",tree,chunk,{},[],radius)

## Chão base do porto: colisão em caixa de 0,3 m como antes; o visual é o topo só onde nenhum piso de cima
## (`cover`) cobre, mais as quatro laterais (a margem com o mar continua igual).
func _land_piece(chunk: Node3D, piece: Rect2, cover: Array[PackedVector2Array]) -> void:
	# A ponte é dona também do chão físico. Recortar só o visual deixava a
	# caixa integral em y=0 atravessando o tronco e a boca do ramal norte.
	var bridge_kit = preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
	if g.region_id == "harbor" and bridge_kit.enabled():
		var cuts: Array[PackedVector2Array] = []
		var outline := GROUND_CUT.rect_polygon(piece)
		if piece.intersects(bridge_kit.east_bounds(),true):
			if not Geometry2D.intersect_polygons(outline,bridge_kit.east_footprint()).is_empty(): cuts.append(bridge_kit.east_footprint())
		if piece.intersects(Rect2(328.75,-374.25,36.55,126.0),true):
			if not Geometry2D.intersect_polygons(outline,bridge_kit.north_footprint()).is_empty(): cuts.append(bridge_kit.north_footprint())
		if not cuts.is_empty():
			g._land_outside_bridge(chunk,piece,cover,cuts)
			return
	var mesh := GROUND_CUT.flat_mesh(GROUND_CUT.subtract([GROUND_CUT.rect_polygon(piece)],cover),0.0,1.0)
	if mesh == null: mesh = ArrayMesh.new()
	var corners := [Vector2(piece.position.x,piece.position.y),Vector2(piece.end.x,piece.position.y),Vector2(piece.end.x,piece.end.y),Vector2(piece.position.x,piece.end.y)]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side+1)%4]
		var edge := b-a
		var normal := Vector3(edge.y,0,-edge.x).normalized()
		for point in [Vector3(a.x,0,a.y),Vector3(b.x,0,b.y),Vector3(b.x,-.3,b.y),Vector3(a.x,0,a.y),Vector3(b.x,-.3,b.y),Vector3(a.x,-.3,a.y)]:
			vertices.append(point)
			normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var land := MeshInstance3D.new()
	land.name = "Land"
	land.mesh = mesh
	# O topo nativo recortado substitui a antiga sobreposição em y=.001 da FreightOutskirts.
	# O terreno de bosque autorado bate com este retângulo, já dividido por chunk.
	var woodland := Rect2(-430,-160,350,318).encloses(piece)
	land.material_override = preload("res://activities/motocross/MotocrossGroundDetail.gd").ground_material() if woodland else g._material(Color("737b69"))
	if woodland: land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(land)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(piece.get_center().x,-.15,piece.get_center().y)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(piece.size.x,.3,piece.size.y)
	collider.shape = shape
	body.add_child(collider)
	land.add_child(body)

func _land_outside_bridge(chunk: Node3D, piece: Rect2, cover: Array[PackedVector2Array], cuts: Array[PackedVector2Array]) -> void:
	# Ownership é obrigatório inclusive no diagnóstico de pisos empilhados.
	# A mesma borda recortada gera paredes visíveis e colisão sem ler a GPU.
	var polygons := GROUND_CUT.subtract_exact([GROUND_CUT.rect_polygon(piece)],cuts)
	if polygons.is_empty(): return
	var mesh := GROUND_CUT.flat_mesh(GROUND_CUT.subtract(polygons,cover),0.0,1.0)
	if mesh == null: mesh = ArrayMesh.new()
	var walls := PackedVector3Array()
	var normals := PackedVector3Array()
	var faces := PackedVector3Array()
	for polygon in polygons:
		var indices := Geometry2D.triangulate_polygon(polygon)
		if indices.is_empty():
			push_error("Poligono de chao da ponte sem triangulacao: %s"%piece)
			return
		# O contorno anti-horário XZ dá faces superiores horárias vistas de cima.
		for index in range(0,indices.size(),3):
			var a: Vector2 = polygon[indices[index]]
			var b: Vector2 = polygon[indices[index+1]]
			var c: Vector2 = polygon[indices[index+2]]
			if (b-a).cross(c-a) == 0.0: continue
			faces.append_array(PackedVector3Array([Vector3(a.x,0,a.y),Vector3(b.x,0,b.y),Vector3(c.x,0,c.y),
				Vector3(c.x,-.3,c.y),Vector3(b.x,-.3,b.y),Vector3(a.x,-.3,a.y)]))
		for side in polygon.size():
			var a: Vector2 = polygon[side]
			var b: Vector2 = polygon[(side+1)%polygon.size()]
			var edge := b-a
			if edge.length_squared() == 0.0: continue
			var normal := Vector3(edge.y,0,-edge.x).normalized()
			var wall := PackedVector3Array([Vector3(a.x,0,a.y),Vector3(b.x,-.3,b.y),Vector3(b.x,0,b.y),
				Vector3(a.x,0,a.y),Vector3(a.x,-.3,a.y),Vector3(b.x,-.3,b.y)])
			walls.append_array(wall)
			faces.append_array(wall)
			for _point in wall: normals.append(normal)
	if faces.is_empty():
		push_error("Chão da ponte sem triangulação válida: %s"%piece)
		return
	if not walls.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = walls
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var land := MeshInstance3D.new()
	land.name = "LandOutsideUnifiedBridge"
	land.mesh = mesh
	land.material_override = g._material(Color("737b69"))
	chunk.add_child(land)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collider.shape = shape
	body.add_child(collider)
	land.add_child(body)

func _box(parent: Node3D,label: String,point: Vector3,size: Vector3,color: Color,solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	mesh.material_override = g._material(color)
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		mesh.add_child(body)
	return mesh
