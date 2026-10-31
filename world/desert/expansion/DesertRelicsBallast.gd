extends RefCounted
## Apoio ferroviário raso e contínuo. As pontas externas/finais começam abaixo do
## chão existente, então veículos nunca encontram a borda vertical de uma laje fina elevada.
const G := preload("res://world/desert/DesertGeometry.gd")
const GRID := 4.0
const TOE_HEIGHT := -.025
const RAIL_TOP := .142
const PROFILE := [Vector2(0,.032),Vector2(.36,.055),Vector2(.55,.107),Vector2(.62,RAIL_TOP),Vector2(.82,RAIL_TOP),Vector2(1.05,.132),Vector2(1.35,.10),Vector2(2.0,.04),Vector2(2.8,.005),Vector2(3.4,TOE_HEIGHT)]

static func cross_height(across: float) -> float:
	var distance := absf(across)
	for i in range(1,PROFILE.size()):
		var a: Vector2 = PROFILE[i-1]
		var b: Vector2 = PROFILE[i]
		if distance<=b.x: return lerpf(a.y,b.y,inverse_lerp(a.x,b.x,distance))
	return TOE_HEIGHT

static func support_height(x: float, across: float, start_x: float, end_x: float) -> float:
	var taper := smoothstep(start_x-8.0,start_x,x)*(1.0-smoothstep(end_x,end_x+8.0,x))
	return lerpf(TOE_HEIGHT,cross_height(across),taper)

static func build_chunk(parent: Node3D, rect: Rect2, height: Callable, centerline: Callable, start_x: float, end_x: float) -> int:
	var start := maxi(-2,floori((rect.position.x-start_x)/GRID)-1)
	var end := mini(ceili((end_x-start_x)/GRID)+2,ceili((rect.end.x-start_x)/GRID)+1)
	var across: Array[float] = []
	for i in range(PROFILE.size()-1,0,-1): across.append(-PROFILE[i].x)
	for sample: Vector2 in PROFILE: across.append(sample.x)
	var faces := PackedVector3Array()
	var visual_faces := PackedVector3Array()
	var normals := PackedVector3Array()
	var count := 0
	for i in range(start,end):
		var x := start_x+(float(i)+.5)*GRID
		var anchor: Vector2 = centerline.call(x)
		if not rect.has_point(anchor): continue
		var left: Vector2 = centerline.call(x-GRID*.5)
		var right: Vector2 = centerline.call(x+GRID*.5)
		for j in range(1,across.size()):
			var a := _vertex(left,across[j-1],height,start_x,end_x)
			var b := _vertex(right,across[j-1],height,start_x,end_x)
			var c := _vertex(right,across[j],height,start_x,end_x)
			var d := _vertex(left,across[j],height,start_x,end_x)
			for triangle in [[a,b,c],[a,c,d]]:
				var normal: Vector3 = (Vector3(triangle[2])-Vector3(triangle[0])).cross(Vector3(triangle[1])-Vector3(triangle[0])).normalized()
				for vertex: Vector3 in triangle:
					faces.append(vertex)
					# A 2 mm granular finish offset keeps iron heads readable without
					# coplanar flicker; the continuous support still meets their tops.
					visual_faces.append(vertex-Vector3.UP*.002)
					normals.append(normal)
		count+=1
	if count==0: return 0
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=visual_faces
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name="ContinuousRailBallast"
	node.mesh=mesh
	node.material_override=G.material(Color("9d907b"),true)
	node.set_meta("desert_rail_ballast",true)
	parent.add_child(node)
	var body := StaticBody3D.new()
	body.name="RailBallastSupport"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface","dirt")
	body.set_meta("desert_rail_ballast",true)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape=shape
	body.add_child(collider)
	node.add_child(body)
	return count

static func _vertex(center: Vector2, across: float, height: Callable, start_x: float, end_x: float) -> Vector3:
	var point := center+Vector2(0,across)
	return Vector3(point.x,float(height.call(point))+support_height(point.x,across,start_x,end_x),point.y)
