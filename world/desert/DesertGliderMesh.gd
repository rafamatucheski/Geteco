extends RefCounted
## Static glider mesh. One surface, 38 triangles, original 1.70 m wingspan.
## Local +Z is forward: the existing circular-flight basis points +Z tangentially.

static func build() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	# Connected broad inner wing, elbow and three separated primary-feather tips.
	# A shallow dihedral preserves the original tip height instead of enlarging it.
	var wing := PackedVector3Array([
		Vector3(.075,.025,-.10), Vector3(.32,.045,-.14),
		Vector3(.62,.085,-.08), Vector3(.85,.12,.055),
		Vector3(.70,.09,.105), Vector3(.81,.11,.18),
		Vector3(.63,.075,.17), Vector3(.69,.085,.285),
		Vector3(.34,.04,.23), Vector3(.075,.015,.16),
	])
	for side in [-1.0,1.0]:
		for i in range(1,wing.size()-1):
			var a := Vector3(wing[0].x*side,wing[0].y,-wing[0].z)
			var b := Vector3(wing[i].x*side,wing[i].y,-wing[i].z)
			var c := Vector3(wing[i+1].x*side,wing[i+1].y,-wing[i+1].z)
			_face(vertices,normals,a,b,c,Vector3.UP)
	# Small closed volumes give the silhouette a thorax, neck and head in oblique
	# views. No eye, feather material, animation, extra surface or instance needed.
	_octahedron(vertices,normals,Vector3(0,.035,.03),Vector3(.095,.105,.28))
	_octahedron(vertices,normals,Vector3(0,.072,.28),Vector3(.065,.065,.10))
	var beak := PackedVector3Array([
		Vector3(0,.065,.43), Vector3(-.037,.06,.34),
		Vector3(.037,.06,.34), Vector3(0,.10,.335),
	])
	var beak_center := (beak[0]+beak[1]+beak[2]+beak[3])*.25
	for indices in [[0,1,2],[0,3,1],[0,2,3],[1,3,2]]:
		var a: Vector3=beak[indices[0]]
		var b: Vector3=beak[indices[1]]
		var c: Vector3=beak[indices[2]]
		_face(vertices,normals,a,b,c,(a+b+c)/3.0-beak_center)
	# Fan tail attaches to the body, rather than a detached floating triangle.
	var tail := PackedVector3Array([Vector3(-.035,.018,-.20),Vector3(.035,.018,-.20),Vector3(.14,0,-.44),Vector3(-.14,0,-.44)])
	_face(vertices,normals,tail[0],tail[1],tail[2],Vector3.UP)
	_face(vertices,normals,tail[0],tail[2],tail[3],Vector3.UP)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func _octahedron(vertices: PackedVector3Array, normals: PackedVector3Array, center: Vector3, radius: Vector3) -> void:
	var top := center+Vector3(0,radius.y,0)
	var bottom := center-Vector3(0,radius.y*.55,0)
	var ring := PackedVector3Array([center+Vector3(radius.x,0,0),center+Vector3(0,0,radius.z),center-Vector3(radius.x,0,0),center-Vector3(0,0,radius.z)])
	for i in 4:
		var a: Vector3=ring[i]
		var b: Vector3=ring[(i+1)%4]
		_face(vertices,normals,top,a,b,(top+a+b)/3.0-center)
		_face(vertices,normals,bottom,b,a,(bottom+b+a)/3.0-center)

static func _face(vertices: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	if normal.dot(outward)<0:
		var previous_b := b
		b=c
		c=previous_b
		normal=-normal
	vertices.append_array(PackedVector3Array([a,b,c]))
	normals.append_array(PackedVector3Array([normal,normal,normal]))
