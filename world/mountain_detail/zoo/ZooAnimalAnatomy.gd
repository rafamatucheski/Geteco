extends RefCounted
## Elliptical cross-section lofts, batched per articulated bone and shared by species.
static var meshes: Dictionary = {}
static var materials: Dictionary = {}
var key: String
var surfaces: Dictionary = {}
func _init(cache_key: String) -> void: key = cache_key
func loft(points: Array, radii: Array, color: String, rest := Vector3.ZERO, sides := 10) -> void:
	if meshes.has(key): return
	var patterned := color in ["d8b56a", "e4dfcf"]
	var group := color if patterned else "plain"
	if not surfaces.has(group):
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[group] = surface
	var st: SurfaceTool = surfaces[group]
	var rings: Array = []
	for j in points.size():
		var tangent: Vector3 = points[mini(j+1,points.size()-1)]-points[maxi(j-1,0)]
		tangent = tangent.normalized()
		var across := Vector3.RIGHT
		if absf(tangent.dot(across)) > .95: across = Vector3.FORWARD
		across = (across-tangent*across.dot(tangent)).normalized()
		var up := tangent.cross(across).normalized()
		var ring: Array = []
		for i in sides:
			var a := TAU*float(i)/sides
			ring.append(points[j]+across*cos(a)*radii[j].x+up*sin(a)*radii[j].y)
		rings.append(ring)
	for j in range(points.size()-1):
		for i in sides:
			var next := (i+1)%sides
			for triangle in [[rings[j][i],rings[j+1][next],rings[j+1][i]],[rings[j][i],rings[j][next],rings[j+1][next]]]:
				var normal: Vector3 = (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
				# Godot renders clockwise fronts; retain the outward geometric normal.
				for vertex: Vector3 in [triangle[0],triangle[2],triangle[1]]:
					st.set_normal(normal)
					st.set_color(Color.WHITE if patterned else Color(color))
					var coat := vertex+rest
					st.set_uv(Vector2(coat.z,coat.y)); st.set_uv2(Vector2(coat.x,0))
					st.add_vertex(vertex)
	# Closed ends retain muzzle planes and prevent hollow knees/shoulders.
	for end in [0, points.size()-1]:
		var normal: Vector3 = (points[0]-points[1]).normalized() if end == 0 else (points[-1]-points[-2]).normalized()
		for i in sides:
			var next := (i+1)%sides
			var triangle: Array = [points[end],rings[end][next],rings[end][i]] if end == 0 else [points[end],rings[end][i],rings[end][next]]
			for vertex: Vector3 in [triangle[0],triangle[2],triangle[1]]:
				st.set_normal(normal); st.set_color(Color.WHITE if patterned else Color(color))
				var coat := vertex+rest
				st.set_uv(Vector2(coat.z,coat.y)); st.set_uv2(Vector2(coat.x,0)); st.add_vertex(vertex)
func form(at: Vector3, size: Vector3, color: String, rest := Vector3.ZERO) -> void:
	# Designed fusiform profile; angular cheek/chest planes rather than spheres.
	loft([at+Vector3(0,0,-size.z*.5),at+Vector3(0,0,-size.z*.32),at,at+Vector3(0,0,size.z*.32),at+Vector3(0,0,size.z*.5)],
		[Vector2(.001,.001),Vector2(size.x*.38,size.y*.38),Vector2(size.x*.5,size.y*.5),Vector2(size.x*.35,size.y*.36),Vector2(.001,.001)],color,rest)
func flush(parent: Node3D) -> void:
	if not meshes.has(key):
		var built: Dictionary = {}
		for group in surfaces: built[group] = surfaces[group].commit()
		meshes[key] = built
	for group in meshes[key]:
		if not materials.has(group):
			if group == "plain":
				var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true
				mat.vertex_color_is_srgb = true; mat.roughness = .92
				materials[group] = mat
			else:
				var mat := ShaderMaterial.new(); mat.shader = preload("res://world/mountain_detail/zoo/animal_coat.gdshader")
				mat.set_shader_parameter("base_color", Color(group))
				mat.set_shader_parameter("marking", Color("80502b") if group == "d8b56a" else Color("242324"))
				mat.set_shader_parameter("pattern", 1 if group == "d8b56a" else 2)
				mat.set_shader_parameter("anatomical_coordinates", true)
				materials[group] = mat
		var mesh := MeshInstance3D.new(); mesh.mesh = meshes[key][group]
		mesh.material_override = materials[group]; parent.add_child(mesh)
