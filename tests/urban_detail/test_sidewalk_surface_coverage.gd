extends SceneTree
## Rebuilt Harbor paving covers the authored lots exactly once, including
## borders/chunk seams; roads also own a single face at corridor intersections.
const SURFACE = preload("res://world/urban_detail/HarborUrbanSurface3D.gd")
var failed := 0

func _initialize() -> void:
	var factory = SURFACE.new()
	factory.configure()
	for bounds in [Rect2(-10,-290,440,455),Rect2(90,85,40,45),Rect2(130,85,40,45)]:
		var parent := Node3D.new()
		factory.build_chunk(parent,bounds)
		# Triângulos reais de cada acabamento (a malha é recortada e indexada desde 2026-10-13: uma camada de
		# chão só; não dá mais para ler retângulos de 6 em 6 vértices).
		var pieces: Array[Dictionary] = []
		for node in parent.get_children():
			var faces: PackedVector3Array = node.mesh.get_faces()
			var material = node.mesh.surface_get_material(0)
			for i in range(0,faces.size(),3):
				pieces.append({"a":Vector2(faces[i].x,faces[i].z),"b":Vector2(faces[i+1].x,faces[i+1].z),"c":Vector2(faces[i+2].x,faces[i+2].z),"color":material.albedo_color,"node":node})
		# As amostras internas evitam arestas compartilhadas ambíguas. Compara a ordem de
		# pintura original, independente do agrupamento ou da tesselação do renderizador.
		for x in range(int(bounds.position.x),int(bounds.end.x),2):
			for y in range(int(bounds.position.y),int(bounds.end.y),2):
				var point := Vector2(x+.371,y+.613)
				if not bounds.has_point(point): continue
				var expected = null
				for source in factory._surfaces:
					if not source.rect.has_point(point): continue
					if source.kind == "grass": expected = Color("687c65") if (source.rect as Rect2).grow(-.18).has_point(point) else Color("878d88")
					else: expected = Color("aaa9a1")
				var actual = null
				var owners := 0
				for piece in pieces:
					if Geometry2D.point_is_inside_triangle(point,piece.a,piece.b,piece.c):
						actual=piece.color
						owners += 1
				# Sem sobreposição coplanar de área positiva entre acabamentos diferentes.
				if owners > 1: failed+=1
				if actual!=expected: failed+=1
		parent.free()
	_check_road_ownership()
	_check_enclosed_hole()
	_check_route_floor()
	_check_transformed_spike()
	print("SIDEWALK_COVERAGE failures=",failed)
	quit(1 if failed else 0)


func _check_road_ownership() -> void:
	var roads := preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()
	var records: Array[Dictionary] = [
		{"id":"horizontal","points":PackedVector3Array([Vector3(-20,0,0),Vector3(20,0,0)]),"width":8.0},
		{"id":"vertical","points":PackedVector3Array([Vector3(0,0,-20),Vector3(0,0,20)]),"width":8.0}]
	roads.configure(records)
	var parent := Node3D.new()
	roads.build_chunk(parent,Rect2(-24,-24,48,48))
	var faces := PackedVector3Array()
	for node in parent.get_children():
		if node is MeshInstance3D and String(node.name).begins_with("HarborRoad_"): faces.append_array(node.mesh.get_faces())
	for x in range(-19,20):
		for z in range(-19,20):
			var point := Vector2(x+.371,z+.613)
			var count := 0
			for i in range(0,faces.size(),3):
				if Geometry2D.point_is_inside_triangle(point,Vector2(faces[i].x,faces[i].z),Vector2(faces[i+1].x,faces[i+1].z),Vector2(faces[i+2].x,faces[i+2].z)): count += 1
			if count > 1: failed += 1
			if (absf(point.x) < 4.0 or absf(point.y) < 4.0) and count != 1: failed += 1
	parent.free()


func _check_enclosed_hole() -> void:
	var cut := preload("res://world/urban_detail/GroundCut.gd")
	# Uma abertura minúscula totalmente fechada passa de propósito do antigo orçamento
	# de subdivisão binária. Ela nunca pode ser preenchida de volta em silêncio.
	var polygon := cut.rect_polygon(Rect2(-500,-500,1000,1000))
	var hole := cut.rect_polygon(Rect2(11.13,17.29,.2,.2))
	var pieces := cut.subtract_exact([polygon],[hole])
	for point in [Vector2(11.21,17.37),Vector2(11.26,17.44)]:
		for piece in pieces:
			if Geometry2D.is_point_in_polygon(point,piece): failed += 1
	for point in [Vector2(-490,-490),Vector2(11,17),Vector2(12,18),Vector2(490,490)]:
		var covered := false
		for piece in pieces:
			if Geometry2D.is_point_in_polygon(point,piece): covered = true
		if not covered: failed += 1


func _check_route_floor() -> void:
	var factory := preload("res://world/harbor_route_detail/HarborRouteDetail3D.gd")
	for zone_id in factory.ALL_ZONES:
		var zone := factory.build_zone(zone_id)
		for child in zone.get_children():
			if child.get_meta("district_ground_owned",false):
				if child.get_child_count() != 0: failed += 1
		if not zone.find_children("SlabMesh","MeshInstance3D",true,false).is_empty(): failed += 1
		if not zone.find_children("RampCollision","StaticBody3D",true,false).is_empty(): failed += 1
		if not zone.find_children("CurbCollision","StaticBody3D",true,false).is_empty(): failed += 1
		# Index-based saved edits must still address the same route furniture.
		if zone_id == "rodoviaria":
			if zone.get_child(0).name != "SidewalkSlab" or not String(zone.get_child(9).name).begins_with("TrashBin"): failed += 1
		zone.free()


func _check_transformed_spike() -> void:
	var cut := preload("res://world/urban_detail/GroundCut.gd")
	# Capturado do acabamento totalmente integrado do Harbor: recorte do mundo mais
	# transformação inversa deixou um retrocesso de oito micrômetros na borda inferior.
	var outline := PackedVector2Array([Vector2(-1.125,4.169273),Vector2(-1.125031,-4.169258),Vector2(0,-4.169266),Vector2(-.90625,-4.169266),Vector2(-.906281,4.162453),Vector2(-.906403,4.169281)])
	var failures_before := cut.failed_triangulations
	var mesh := cut.flat_mesh([outline],.0065,1.0)
	if mesh == null or cut.failed_triangulations != failures_before:
		failed += 1
		return
	var area := 0.0
	var faces := mesh.get_faces()
	for index in range(0,faces.size(),3):
		area += (faces[index+1]-faces[index]).cross(faces[index+2]-faces[index]).length()*.5
	# Preserva a faixa estreita, não seu retângulo envolvente de 9.38 m² nem o casco com pico.
	if area < 1.80 or area > 1.84: failed += 1
