extends RefCounted
## Uma superfície física para a reta autorada. Triângulos coplanares de chunks
## separados podem dar contato de borda horizontal nas emendas de 96 m a um carro rápido.
## Asfalto renderizado, acostamentos, obstáculos e a estrada de volta mantêm a geometria.
const CUT := preload("res://world/urban_detail/GroundCut.gd")
const BOUNDS := Rect2(-796,-805,1026,10)

static func install(region: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "DragTrackSupport"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("vehicle_surface","hard")
	var center := BOUNDS.get_center()
	body.position = Vector3(center.x,0,center.y)
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array()
	# Faces conectadas num corpo só têm bordas internas, ao contrário de colisores
	# de chunks separados. Triângulos curtos e centrados também evitam perda de precisão perto
	# da ponta aguda de um único triângulo de um quilômetro durante o encaixe no piso.
	for segment in ceili(BOUNDS.size.x/32.0):
		var left := BOUNDS.position.x+float(segment)*32.0-center.x
		var right := minf(left+32.0,BOUNDS.end.x-center.x)
		var a := Vector3(left,0,-BOUNDS.size.y*.5)
		var b := Vector3(right,0,-BOUNDS.size.y*.5)
		var c := Vector3(right,0,BOUNDS.size.y*.5)
		var d := Vector3(left,0,BOUNDS.size.y*.5)
		faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
	shape.set_faces(faces)
	collider.shape = shape
	body.add_child(collider)
	region.add_child(body)
	return body

static func replace_chunk_collision(region: Node3D, chunk: Node3D) -> void:
	for surface in chunk.get_children():
		if not surface is MeshInstance3D: continue
		if not str(surface.name).begins_with("DesertGround") and not str(surface.name).begins_with("WeatheredAsphalt"): continue
		for body in surface.get_children():
			if not body is StaticBody3D: continue
			for collider in body.get_children():
				if not collider is CollisionShape3D or not collider.shape is ConcavePolygonShape3D: continue
				var to_region: Transform3D = region.global_transform.affine_inverse()*collider.global_transform
				var faces := outside_faces(collider.shape.get_faces(),to_region)
				if faces.is_empty():
					collider.disabled = true
				else:
					var replacement := ConcavePolygonShape3D.new()
					replacement.backface_collision = collider.shape.backface_collision
					replacement.set_faces(faces)
					collider.shape = replacement

static func outside_faces(faces: PackedVector3Array, to_region := Transform3D.IDENTITY) -> PackedVector3Array:
	var output := PackedVector3Array()
	var from_region := to_region.affine_inverse()
	var cover: Array[PackedVector2Array] = [CUT.rect_polygon(BOUNDS)]
	for index in range(0,faces.size(),3):
		var a := to_region*faces[index]
		var b := to_region*faces[index+1]
		var c := to_region*faces[index+2]
		var polygon := PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
		var normal := (b-a).cross(c-a)
		# A reta fica na referência zero comum. Deixa rampas, paredes e
		# geometria fora da área completamente intocadas.
		if absf(a.y)>.001 or absf(b.y)>.001 or absf(c.y)>.001 or absf(normal.y)<.000001 or not CUT.bounds(polygon).intersects(BOUNDS):
			output.append_array(faces.slice(index,index+3))
			continue
		var subjects: Array[PackedVector2Array] = [polygon]
		for remainder in CUT.subtract_exact(subjects,cover):
			var triangles := Geometry2D.triangulate_polygon(remainder)
			for offset in range(0,triangles.size(),3):
				var points := PackedVector3Array()
				for corner in 3:
					var p := remainder[triangles[offset+corner]]
					var height := a.y-(normal.x*(p.x-a.x)+normal.z*(p.y-a.z))/normal.y
					points.append(Vector3(p.x,height,p.y))
				if (points[1]-points[0]).cross(points[2]-points[0]).dot(normal)<0:
					var swap := points[1]
					points[1]=points[2]
					points[2]=swap
				for p in points: output.append(from_region*p)
	return output
