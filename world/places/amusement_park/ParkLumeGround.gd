extends RefCounted
## One composed ground: planted infield, paved circulation and a supported verge.
## The old pavement is removed wherever another finish owns the same surface.
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const CLIP := preload("res://world/editing/WorldGroundFactory.gd")
const SURFACES := preload("res://world/places/ShopInteriorMaterials.gd")
const LANDSCAPE := preload("res://activities/motocross/MotocrossGroundDetail.gd")
const TOP := .025
const MEADOW_TOP := .001
static var _materials := {}

static func _rect(x: float,z: float,width: float,depth: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x,z),Vector2(x+width,z),Vector2(x+width,z+depth),Vector2(x,z+depth)])

static func _gardens() -> Array[PackedVector2Array]:
	return [
		_rect(-40,-36,35.2,59.3),
		PackedVector2Array([Vector2(-3.8,-35.7),Vector2(22,-35.7),Vector2(24,-32.3),Vector2(12,-30.8),Vector2(-3.8,-31.8)]),
		PackedVector2Array([Vector2(36,23.5),Vector2(40,23.5),Vector2(40,36),Vector2(25,36)])]

static func _material(kind: String) -> Material:
	if _materials.has(kind): return _materials[kind]
	if kind == "grass":
		_materials[kind] = LANDSCAPE.ground_material()
	elif kind == "verge":
		var verge := ShaderMaterial.new()
		verge.shader = preload("res://world/places/amusement_park/ParkGroundVerge.gdshader")
		LANDSCAPE.bind_textures(verge)
		_materials[kind] = verge
	else:
		var material := StandardMaterial3D.new()
		material.albedo_texture = SURFACES.texture("stone")
		material.albedo_color = Color({"paving":"a3a08c","walk":"c0baa5","mineral":"797c70"}[kind])
		material.roughness = .94
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_materials[kind] = material
	return _materials[kind]

static func _stream(streams: Dictionary,kind: String) -> SurfaceTool:
	if not streams.has(kind):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		streams[kind] = surface
	return streams[kind]

static func _triangle(surface: SurfaceTool,points: PackedVector3Array,weights := PackedFloat32Array([0,0,0])) -> void:
	var order := [0,1,2]
	if (points[1]-points[0]).cross(points[2]-points[0]).y>0: order = [0,2,1]
	for index: int in order:
		var point := points[index]
		surface.set_normal(Vector3.UP)
		# A 1 m tile contains four rows of 50 x 25 cm pavers.
		surface.set_uv(Vector2(point.x,point.z))
		surface.set_color(Color(1,1,1,weights[index]))
		surface.add_vertex(point)

static func _faces(polygon: PackedVector2Array,height := TOP) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var indices := Geometry2D.triangulate_polygon(polygon)
	for index in indices: faces.append(Vector3(polygon[index].x,height,polygon[index].y))
	return faces

static func _polygon(streams: Dictionary,kind: String,polygon: PackedVector2Array) -> void:
	var faces := _faces(polygon)
	if faces.is_empty(): return
	var surface := _stream(streams,kind)
	for index in range(0,faces.size(),3):
		_triangle(surface,PackedVector3Array([faces[index],faces[index+1],faces[index+2]]))

static func _finish_parts(streams: Dictionary,kind: String,polygon: PackedVector2Array,masks: Array) -> void:
	for part in CLIP.uncovered(polygon,masks): _polygon(streams,kind,part)

static func build(park: Node3D) -> void:
	var streams := {}
	var outline := LAYOUT.outline()
	var inner: PackedVector2Array = Geometry2D.offset_polygon(outline,-.34,Geometry2D.JOIN_MITER)[0]
	var approach := _rect(40,13.1,11,5.8)
	var walks: Array[PackedVector2Array] = [_rect(-14,12,54,6),_rect(17.4,-5,5.2,18)]
	var trims: Array[PackedVector2Array] = [_rect(-14,11.785,54,.13),_rect(-14,18.085,54,.13)]
	var gardens: Array[PackedVector2Array] = []
	var planted_borders: Array[PackedVector2Array] = []
	for source in _gardens():
		for garden in Geometry2D.intersect_polygons(source,inner):
			gardens.append(garden)
			for expanded in Geometry2D.offset_polygon(garden,.18,Geometry2D.JOIN_MITER):
				planted_borders.append_array(Geometry2D.intersect_polygons(expanded,inner))
	var circulation_masks: Array = walks+trims
	_finish_parts(streams,"paving",inner,planted_borders+circulation_masks)
	for garden in gardens: _finish_parts(streams,"grass",garden,circulation_masks)
	for border in planted_borders: _finish_parts(streams,"mineral",border,gardens+circulation_masks)
	_finish_parts(streams,"mineral",outline,[inner]+circulation_masks)
	var previous_walks: Array = []
	for walk in walks:
		for clipped in Geometry2D.intersect_polygons(walk,outline):
			_finish_parts(streams,"walk",clipped,previous_walks)
		previous_walks.append(walk)
	for trim in trims:
		for clipped in Geometry2D.intersect_polygons(trim,outline):
			_finish_parts(streams,"mineral",clipped,walks)
	_polygon(streams,"walk",approach)
	var faces := _faces(outline)
	faces.append_array(_faces(approach))
	# Trace the combined park/access contour, including both re-entrant gate corners.
	# The last two metres of the access already meet the city sidewalk.
	var edge := PackedVector2Array([Vector2(-40,-36),Vector2(22,-36),Vector2(40,-10),
		Vector2(40,13.1),Vector2(49,13.1),Vector2(49,18.9),Vector2(40,18.9),Vector2(40,36),Vector2(-40,36)])
	_perimeter_verge(streams,edge,approach,faces)
	for kind: String in streams:
		var display := MeshInstance3D.new()
		display.name = "ParkGround_"+kind
		display.mesh = streams[kind].commit()
		display.material_override = _material(kind)
		display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		park.add_child(display)
	var body := StaticBody3D.new()
	body.name = "ParkGround"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	park.add_child(body)
	park.set_meta("integrated_ground",true)

static func _wear(point: Vector2) -> float:
	return clampf(.55+sin(point.x*.17+point.y*.19)*.23+sin(point.y*.51)*.17,.15,.95)

static func _width(point: Vector2) -> float:
	var width := clampf(.90+sin(point.x*.17+point.y*.22)*.30+cos(point.x*.40-point.y*.13)*.22,.55,1.42)
	return width*clampf((49.0-point.x)/3.0,0,1) if point.x>46.0 else width

static func _perimeter_verge(streams: Dictionary,outline: PackedVector2Array,approach: PackedVector2Array,faces: PackedVector3Array) -> void:
	var inside := PackedVector2Array()
	var outside := PackedVector2Array()
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index+1)%outline.size()]
		var direction := (b-a).normalized()
		var normal := Vector2(direction.y,-direction.x)
		var prior := (a-outline[posmod(index-1,outline.size())]).normalized()
		var corner := (normal+Vector2(prior.y,-prior.x)).normalized()
		var segments := maxi(1,ceili(a.distance_to(b)/2.0))
		for step in segments:
			var point := a.lerp(b,float(step)/segments)
			inside.append(point)
			var offset := corner/maxf(.2,corner.dot(normal)) if step==0 else normal
			outside.append(point+offset*_width(point))
	for index in inside.size():
		var next := (index+1)%inside.size()
		var a := Vector3(inside[index].x,TOP,inside[index].y)
		var b := Vector3(inside[next].x,TOP,inside[next].y)
		var c := Vector3(outside[next].x,MEADOW_TOP,outside[next].y)
		var d := Vector3(outside[index].x,MEADOW_TOP,outside[index].y)
		_verge_triangle(streams,PackedVector3Array([a,b,c]),PackedFloat32Array([_wear(inside[index]),_wear(inside[next]),0]),[approach],faces)
		_verge_triangle(streams,PackedVector3Array([a,c,d]),PackedFloat32Array([_wear(inside[index]),0,0]),[approach],faces)

static func _verge_triangle(streams: Dictionary,points: PackedVector3Array,weights: PackedFloat32Array,masks: Array,faces: PackedVector3Array) -> void:
	var source := PackedVector2Array()
	for point in points: source.append(Vector2(point.x,point.z))
	var denominator := (source[1]-source[0]).cross(source[2]-source[0])
	if absf(denominator)<.000001: return
	for clipped in CLIP.uncovered(source,masks):
		var indices := Geometry2D.triangulate_polygon(clipped)
		for i in range(0,indices.size(),3):
			var triangle := PackedVector3Array()
			var alphas := PackedFloat32Array()
			for index in [indices[i],indices[i+1],indices[i+2]]:
				var point: Vector2 = clipped[index]
				var w1 := (point-source[0]).cross(source[2]-source[0])/denominator
				var w2 := (source[1]-source[0]).cross(point-source[0])/denominator
				var w0 := 1-w1-w2
				triangle.append(Vector3(point.x,points[0].y*w0+points[1].y*w1+points[2].y*w2,point.y))
				alphas.append(clampf(weights[0]*w0+weights[1]*w1+weights[2]*w2,0,1))
			_triangle(_stream(streams,"verge"),triangle,alphas)
			faces.append_array(triangle)
