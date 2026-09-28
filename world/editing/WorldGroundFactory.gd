@tool
extends RefCounted
## Opaque ground, shared textures, one static mesh/body per intersected chunk.
const STEP := 4.0 # Same grid and triangle diagonal as MountainTerrain3D.
const SURFACES := ["grass","earth","sand","gravel","concrete","asphalt","pavers"]
const LABELS := ["Grama","Terra","Areia","Cascalho","Concreto","Asfalto","Piso de blocos"]
const COLORS := ["5e7945","897053","c4b383","8a8b80","92958c","484e50","a09079"]
static var materials: Dictionary = {}
static func color(surface: String) -> Color:
	return Color(COLORS[maxi(0,SURFACES.find(surface))])
static func texture(surface: String) -> Image:
	var result := Image.create(64,64,false,Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9017 + SURFACES.find(surface)
	var base := color(surface)
	for y in 64:
		for x in 64:
			var value := base * rng.randf_range(.85,1.12)
			if surface == "grass" and x%3 == 0: value = value.lightened(.06)
			if surface == "gravel" and (x/3+y/3)%2 == 0: value = value.darkened(.14)
			if surface == "pavers" and (y%16 < 2 or (x+(16 if (y/16)%2 == 0 else 0))%32 < 2): value = base.darkened(.35)
			if surface == "concrete" and (x == 0 or y == 0): value = base.darkened(.2)
			result.set_pixel(x,y,value)
	result.generate_mipmaps()
	return result
const NATURAL := ["earth","gravel","grass","sand"]
const NATURAL_SHADER := preload("res://world/regions/natural_ground.gdshader")
static func material(surface: String) -> Material:
	if not materials.has(surface) and surface in NATURAL:
		# Chão natural com detalhe procedural; a textura 64x64 lia como papel liso.
		var natural := ShaderMaterial.new()
		natural.shader = NATURAL_SHADER
		natural.set_shader_parameter("kind",NATURAL.find(surface) if surface != "sand" else 3)
		natural.set_shader_parameter("base_color",color(surface))
		natural.set_shader_parameter("uv_meters",2.0)
		materials[surface] = natural
	if not materials.has(surface):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(texture(surface))
		mat.roughness = .95
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		materials[surface] = mat
	return materials[surface]
static func footprint(row: Dictionary) -> PackedVector2Array:
	var center := Vector2(row.position[0],row.position[1])
	var half := Vector2(row.size[0],row.size[1])*.5
	var result := PackedVector2Array()
	var outline: Array = row.get("outline",[[-half.x,-half.y],[half.x,-half.y],[half.x,half.y],[-half.x,half.y]])
	for point in outline:
		var offset := Vector2(point[0],point[1])
		result.append(center+offset.rotated(-deg_to_rad(float(row.rotation))))
	return result
static func bounds(row: Dictionary) -> Rect2:
	var polygon := footprint(row)
	var result := Rect2(polygon[0],Vector2.ZERO)
	for point in polygon: result = result.expand(point)
	return result
static func half_plane(polygon: PackedVector2Array, a: Vector2, b: Vector2, inside: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	if polygon.is_empty(): return result
	var previous := polygon[-1]
	var previous_distance := (b-a).cross(previous-a)
	for point in polygon:
		var distance := (b-a).cross(point-a)
		var keep := distance >= 0 if inside else distance <= 0
		var previous_keep := previous_distance >= 0 if inside else previous_distance <= 0
		if keep != previous_keep:
			result.append(previous.lerp(point,previous_distance/(previous_distance-distance)))
		if keep: result.append(point)
		previous = point
		previous_distance = distance
	return result
static func uncovered(polygon: PackedVector2Array, masks: Array) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [polygon]
	for mask in masks:
		var next: Array[PackedVector2Array] = []
		for part in parts:
			var remaining := part
			for edge in mask.size():
				var a: Vector2 = mask[edge]
				var b: Vector2 = mask[(edge+1)%mask.size()]
				var outside := half_plane(remaining,a,b,false)
				if outside.size() >= 3: next.append(outside)
				remaining = half_plane(remaining,a,b,true)
				if remaining.size() < 3: break
		parts = next
	return parts
static func create(row: Dictionary, clip: Rect2, height: Callable = Callable(), masks: Array = []) -> MeshInstance3D:
	var polygon := footprint(row)
	var rect := bounds(row).intersection(clip)
	if not rect.has_area(): return null
	var boundary := PackedVector2Array([clip.position,Vector2(clip.end.x,clip.position.y),clip.end,Vector2(clip.position.x,clip.end.y)])
	var clipped := Geometry2D.intersect_polygons(polygon,boundary)
	if clipped.is_empty(): return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	# Clip to the base terrain triangles, preserving its exact piecewise height.
	for z in range(floori(rect.position.y/STEP),ceili(rect.end.y/STEP)):
		for x in range(floori(rect.position.x/STEP),ceili(rect.end.x/STEP)):
			var a := Vector2(x,z)*STEP
			var b := a+Vector2(STEP,0)
			var c := a+Vector2(0,STEP)
			var d := a+Vector2(STEP,STEP)
			for triangle in [PackedVector2Array([a,b,c]),PackedVector2Array([b,d,c])]:
				var visible: Array[PackedVector2Array] = []
				for section in clipped:
					for part in Geometry2D.intersect_polygons(section,triangle):
						if not row.has("outline"):
							visible.append_array(uncovered(part,masks))
							continue
						var indices := Geometry2D.triangulate_polygon(part)
						for i in range(0,indices.size(),3):
							visible.append_array(uncovered(PackedVector2Array([part[indices[i]],part[indices[i+1]],part[indices[i+2]]]),masks))
				for part in visible:
					if Geometry2D.is_polygon_clockwise(part): part.reverse()
					for i in range(1,part.size()-1):
						var points := PackedVector3Array()
						for p in [part[0],part[i],part[i+1]]:
							points.append(Vector3(p.x,(float(height.call(p)) if height.is_valid() else 0.0)+.08,p.y))
						var normal := (points[2]-points[0]).cross(points[1]-points[0])
						if normal.length_squared() < .00000001: continue
						for point in points:
							vertices.append(point)
							normals.append(normal.normalized())
							uvs.append(Vector2(point.x,point.z)*.5)
	if vertices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var result := MeshInstance3D.new()
	result.name = "WorldGround_"+str(row.surface)
	result.set_meta("editor_id",row.id)
	result.set_meta("editor_ground",true)
	result.mesh = mesh
	result.material_override = material(row.surface)
	if str(row.surface) in NATURAL: result.set_instance_shader_parameter("uv_origin",(uvs[0]/32.0).floor()*32.0)
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("editor_id",row.id)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	result.add_child(body)
	return result
