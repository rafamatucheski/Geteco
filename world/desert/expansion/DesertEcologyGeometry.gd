extends RefCounted
## Small shared vertex-colour builders. All static ecology is one opaque surface per chunk.
static var _material: StandardMaterial3D

static func buffer() -> Dictionary:
	return {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}

static func material() -> StandardMaterial3D:
	if _material==null:
		_material=StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo=true
		_material.vertex_color_is_srgb=true
		_material.roughness=1.0
		_material.metallic_specular=0.0
	return _material

static func mesh(data: Dictionary) -> ArrayMesh:
	var result := ArrayMesh.new()
	if data.vertices.is_empty(): return result
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.vertices
	arrays[Mesh.ARRAY_NORMAL]=data.normals
	arrays[Mesh.ARRAY_COLOR]=data.colors
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

static func triangle(data: Dictionary,a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
	var normal := (c-a).cross(b-a).normalized()
	data.vertices.append_array(PackedVector3Array([a,b,c]))
	data.normals.append_array(PackedVector3Array([normal,normal,normal]))
	data.colors.append_array(PackedColorArray([color,color,color]))

static func leaf(data: Dictionary,a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
	triangle(data,a,b,c,color)
	triangle(data,c,b,a,color.darkened(.08))

static func branch(data: Dictionary,a: Vector3,b: Vector3,radius: float,tip_radius: float,color: Color,sides := 6) -> PackedVector3Array:
	var up := (b-a).normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length_squared()<.1: right=Vector3.RIGHT
	var forward := right.cross(up)
	var points := PackedVector3Array()
	for i in sides:
		var angle := float(i)*TAU/float(sides)
		var next := float(i+1)*TAU/float(sides)
		var ray := right*cos(angle)+forward*sin(angle)
		var ray_next := right*cos(next)+forward*sin(next)
		var a0 := a+ray*radius
		var a1 := a+ray_next*radius
		var b0 := b+ray*tip_radius
		var b1 := b+ray_next*tip_radius
		var shade := color.lightened(.035) if i%3==0 else color
		triangle(data,a0,a1,b1,shade)
		triangle(data,a0,b1,b0,shade)
		triangle(data,b0,b1,b,shade)
		triangle(data,a1,a0,a,shade)
		points.append(a0)
		points.append(b0)
	return points

static func ellipsoid(data: Dictionary,pose: Transform3D,size: Vector3,color: Color,sides := 10,rings := 5,ribbed := false) -> void:
	for row in rings:
		var v0 := PI*float(row)/float(rings)
		var v1 := PI*float(row+1)/float(rings)
		for side in sides:
			var a0 := TAU*float(side)/float(sides)
			var a1 := TAU*float(side+1)/float(sides)
			var c0 := 1.0 if not ribbed or side%2==0 else .87
			var c1 := 1.0 if not ribbed or (side+1)%2==0 else .87
			var p0 := pose*(Vector3(cos(a0)*sin(v0)*c0,cos(v0),sin(a0)*sin(v0)*c0)*size)
			var p1 := pose*(Vector3(cos(a1)*sin(v0)*c1,cos(v0),sin(a1)*sin(v0)*c1)*size)
			var p2 := pose*(Vector3(cos(a1)*sin(v1)*c1,cos(v1),sin(a1)*sin(v1)*c1)*size)
			var p3 := pose*(Vector3(cos(a0)*sin(v1)*c0,cos(v1),sin(a0)*sin(v1)*c0)*size)
			var shade := color.lightened(.07) if ribbed and side%2==0 else color
			if row>0: triangle(data,p0,p2,p1,shade)
			if row<rings-1: triangle(data,p0,p3,p2,shade)

static func solid(body: StaticBody3D,points: PackedVector3Array) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points=points
	var collision := CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision)
