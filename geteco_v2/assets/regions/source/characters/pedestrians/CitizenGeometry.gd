extends RefCounted
## Build-time geometry only. Vertex colours batch all opaque detail on a joint.
static var _prewarm_mesh: ArrayMesh
static var _prewarm_material: StandardMaterial3D
var surface := SurfaceTool.new()
var count := 0

static func prewarm_vertex_color_mesh() -> void:
	if is_instance_valid(_prewarm_mesh) and is_instance_valid(_prewarm_material):
		return
	var geometry := new()
	geometry.loft([
		Vector4(-.12, .10, .08, 0.0),
		Vector4(.12, .11, .09, 0.0),
	], Color("b7896f"), 16)
	var part := geometry.finish_detached("CitizenGeometryPrewarm")
	_prewarm_mesh = part.mesh
	_prewarm_material = part.material_override
	part.mesh = null
	part.material_override = null
	part.free()

func _init() -> void:
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

func add(mesh: Mesh, color: Color, transform := Transform3D.IDENTITY) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := transform.basis.inverse().transposed()
	for i in (indices.size() if not indices.is_empty() else vertices.size()):
		var index: int = indices[i] if not indices.is_empty() else i
		surface.set_color(color.srgb_to_linear())
		surface.set_normal((normal_basis * normals[index]).normalized())
		surface.add_vertex(transform * vertices[index])
		count += 1

func oval(size: Vector3, position: Vector3, color: Color, rotation := Vector3.ZERO) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 12
	mesh.rings = 6
	add(mesh, color, Transform3D(Basis.from_euler(rotation).scaled(size), position))

func box(size: Vector3, position: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	# Vertical detail strips must follow the same curved abdomen as the shirt.
	mesh.subdivide_height=maxi(0,ceili(size.y/.025)-1)
	add(mesh, color, Transform3D(Basis.IDENTITY, position))

func panel(points: Array[Vector3], color: Color) -> void:
	for i in range(1,points.size()-1):
		var triangle: Array[Vector3] = [points[0],points[i],points[i+1]]
		var normal := (triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()
		if normal.z>0:
			triangle=[points[0],points[i+1],points[i]]
			normal=-normal
		for point in triangle:
			surface.set_color(color.srgb_to_linear())
			surface.set_normal(normal)
			surface.add_vertex(point)
			count += 1

func scalp(color: Color) -> void:
	var mesh_surface := SurfaceTool.new()
	mesh_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 9:
		for column in 25:
			var angle := column*TAU/24.0
			var boundary := 1.70-.65*sqrt(maxf(0,-cos(angle)))+.20*maxf(0,cos(angle))
			var phi := row/8.0*boundary
			mesh_surface.add_vertex(Vector3(sin(angle)*sin(phi)*.145,.020+cos(phi)*.190,.018+cos(angle)*sin(phi)*.136))
	for row in 8:
		for column in 24:
			var a := row*25+column
			for index in [a,a+1,a+26,a,a+26,a+25]: mesh_surface.add_index(index)
	mesh_surface.generate_normals()
	add(mesh_surface.commit(),color)

func loft(rings: Array, color: Color, segments := 16, start_angle := 0.0, arc := TAU, vertical_step := 0.0) -> void:
	# Each section is (height, half-width, half-depth, depth offset).
	if vertical_step>0:
		var refined: Array=[]
		for row in rings.size()-1:
			var a: Vector4=rings[row]
			var b: Vector4=rings[row+1]
			var steps:=maxi(1,ceili(absf(b.x-a.x)/vertical_step))
			for step in steps: refined.append(a.lerp(b,float(step)/steps))
		refined.append(rings[-1])
		rings=refined
	for row in rings.size() - 1:
		for column in segments:
			var points: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for corner in [Vector2i(0,0),Vector2i(1,1),Vector2i(1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(1,1)]:
				var ring: Vector4 = rings[row + corner.y]
				var angle := start_angle + float(column + corner.x) / segments * arc
				points.append(Vector3(sin(angle)*ring.y, ring.x, cos(angle)*ring.z+ring.w))
				var previous: Vector4 = rings[maxi(0,row+corner.y-1)]
				var next: Vector4 = rings[mini(rings.size()-1,row+corner.y+1)]
				var tangent := Vector3(cos(angle)*ring.y,0,-sin(angle)*ring.z)
				var along := Vector3(sin(angle)*(next.y-previous.y),next.x-previous.x,cos(angle)*(next.z-previous.z)+next.w-previous.w)
				normals.append(tangent.cross(along).normalized())
			for triangle in 2:
				for index in 3:
					surface.set_color(color.srgb_to_linear())
					surface.set_normal(normals[triangle*3+index])
					surface.add_vertex(points[triangle*3+index])
					count += 1

func lock(start: Vector3, control: Vector3, tip: Vector3, width: float, color: Color) -> void:
	var mesh_surface := SurfaceTool.new()
	mesh_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in 9:
		var t := step / 8.0
		var point := start.bezier_interpolate(control,control,tip,t)
		var tangent := (control-start).lerp(tip-control,t).normalized()
		var outward := (point-Vector3(0,.02,.01)).normalized()
		var across := tangent.cross(outward).normalized()
		if across.length_squared() < .1: across = Vector3.RIGHT
		var normal := across.cross(tangent).normalized()
		var taper := maxf(.22,sin((.15+.85*t)*PI))
		for side in 6:
			var angle := side*TAU/6.0
			mesh_surface.add_vertex(point+across*cos(angle)*width*taper+normal*sin(angle)*width*.38*taper)
	for step in 8:
		for side in 6:
			var a := step*6+side
			var b := step*6+(side+1)%6
			for vertex in [a,b+6,b,a,a+6,b+6]: mesh_surface.add_index(vertex)
	mesh_surface.generate_normals()
	add(mesh_surface.commit(),color)

func finish(parent: Node3D, label: String, roughness := .88) -> MeshInstance3D:
	var part := finish_detached(label, roughness)
	parent.add_child(part)
	return part

func finish_detached(label: String, roughness := .88) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = roughness
	material.metallic_specular = .2
	part.mesh = surface.commit()
	part.material_override = material
	return part
