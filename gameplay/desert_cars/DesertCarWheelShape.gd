extends RefCounted
## Profiled, open wheel hardware. Shares the car's existing material batches.

static func rim(root: Node3D, radius: float, width: float, center: Vector3, material: Material) -> void:
	# No end caps: the spokes connect a real rim instead of hiding a solid disc.
	var section := [Vector2(-width*.5,radius),Vector2(width*.5,radius),Vector2(width*.5,radius*.91),Vector2(-width*.5,radius*.91),Vector2(-width*.5,radius)]
	_profile(root,"RimBarrel",section,24,center,material)

static func hub(root: Node3D, radius: float, side: float, center: Vector3, material: Material) -> void:
	# A chamfered six-sided cap reads as machined hardware at close range.
	var section := [Vector2(-.012,0),Vector2(-.012,radius),Vector2(.009,radius),Vector2(.017,radius*.72),Vector2(.017,0)]
	if side<0:
		for i in section.size(): section[i].x=-section[i].x
		section.reverse()
	_profile(root,"WheelHub",section,6,center,material)

static func exhaust(root: Node3D, center: Vector3, material: Material) -> void:
	var section := [Vector2(-.095,.055),Vector2(.095,.055),Vector2(.095,.044),Vector2(-.095,.044)]
	var node := _profile(root,"ExhaustTip",section,16,Vector3.ZERO,material)
	# Local profile axis is X; the exhaust outlet points towards the rear (+Z).
	node.rotation.y=-PI*.5
	node.position=center

static func _profile(root: Node3D, label: String, section: Array, segments: int, center: Vector3, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a := TAU*float(i)/float(segments)
		var b := TAU*float(i+1)/float(segments)
		for j in range(section.size()-1):
			var p: Vector2 = section[j]
			var q: Vector2 = section[j+1]
			var outward := Vector3(-(q.y-p.y),sin((a+b)*.5)*(q.x-p.x),cos((a+b)*.5)*(q.x-p.x)).normalized()
			var v0 := center+Vector3(p.x,sin(a)*p.y,cos(a)*p.y)
			var v1 := center+Vector3(p.x,sin(b)*p.y,cos(b)*p.y)
			var v2 := center+Vector3(q.x,sin(b)*q.y,cos(b)*q.y)
			var v3 := center+Vector3(q.x,sin(a)*q.y,cos(a)*q.y)
			_triangle(st,v0,v1,v2,outward)
			_triangle(st,v0,v2,v3,outward)
	var node := MeshInstance3D.new()
	node.name=label
	node.mesh=st.commit()
	node.material_override=material
	root.add_child(node)
	return node

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	if normal.length_squared()<.5: return
	var vertices := [a,b,c]
	if normal.dot(outward)<0:
		vertices=[a,c,b]
		normal=-normal
	for point: Vector3 in vertices:
		st.set_normal(normal)
		st.set_uv(Vector2(point.z,point.y))
		st.add_vertex(point)
