extends RefCounted
## All geometry belongs to the streamed chunk. No timers, physics, or scene-wide scans.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const SURFACE := preload("res://world/desert/desert_surface.gdshader")
const GRASS := preload("res://world/desert/desert_dry_grass.gdshader")
static var _shoulder_material: ShaderMaterial
static var _pebble_material: StandardMaterial3D
static var _grass_material: ShaderMaterial
static var _pebble_mesh: SphereMesh
static var _grass_mesh: ArrayMesh

static func build_chunk(chunk: Node3D, rect: Rect2, roads: Array, clear: Callable, height_at := Callable()) -> void:
	_prepare_resources()
	var rng := RandomNumberGenerator.new()
	rng.seed=absi(int(rect.position.x)*73856093^int(rect.position.y)*19349663)+771
	var pebbles: Array[Transform3D]=[]
	var grasses: Array[Transform3D]=[]
	for cluster in 14:
		var p := Vector2(rng.randf_range(rect.position.x+3,rect.end.x-3),rng.randf_range(rect.position.y+3,rect.end.y-3))
		if not bool(clear.call(p,2.0)): continue
		for rock in 7:
			var at := p+Vector2(rng.randf_range(-1.7,1.7),rng.randf_range(-1.7,1.7))
			var scale := Vector3(rng.randf_range(.07,.26),rng.randf_range(.035,.11),rng.randf_range(.07,.21))
			var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(scale)
			var ground: float=height_at.call(at) if height_at.is_valid() else LAYOUT.surface_height(at)
			pebbles.append(Transform3D(basis,Vector3(at.x,ground+scale.y*.33,at.y)))
		if cluster%2==0:
			var scale := rng.randf_range(.65,1.3)
			var ground: float=height_at.call(p) if height_at.is_valid() else LAYOUT.surface_height(p)
			grasses.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),Vector3(p.x,ground,p.y)))
	_batch(chunk,"MineralPebbles",_pebble_mesh,_pebble_material,pebbles)
	_batch(chunk,"WindDriedGrass",_grass_mesh,_grass_material,grasses)

static func _prepare_resources() -> void:
	if _shoulder_material!=null: return
	_init_shoulder()
	_pebble_material=StandardMaterial3D.new()
	_pebble_material.albedo_color=Color("a6977f")
	_pebble_material.vertex_color_use_as_albedo=true
	_pebble_material.roughness=1.0
	_pebble_mesh=SphereMesh.new()
	_pebble_mesh.radius=1.0
	_pebble_mesh.height=2.0
	_pebble_mesh.radial_segments=7
	_pebble_mesh.rings=3
	_grass_material=ShaderMaterial.new()
	_grass_material.shader=GRASS
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for blade in 9:
		var angle := float(blade)*2.39996
		var side := Vector3(cos(angle),0,sin(angle))*.022
		var foot := Vector3(cos(angle)*.08,0,sin(angle)*.08)
		var tip := foot+Vector3(cos(angle)*.2,.24+float(blade%4)*.075,sin(angle)*.2)
		vertices.append_array(PackedVector3Array([foot-side,tip,foot+side]))
		for n in 3: normals.append(Vector3.UP)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	_grass_mesh=ArrayMesh.new()
	_grass_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

static func _init_shoulder() -> void:
	_shoulder_material=ShaderMaterial.new()
	_shoulder_material.shader=SURFACE
	_shoulder_material.set_shader_parameter("base_color",Color("b9a079"))
	_shoulder_material.set_shader_parameter("shoulder",true)

static func shoulder_material() -> Material:
	_prepare_resources()
	return _shoulder_material

static func prepare_shoulder_segments(rect: Rect2, roads: Array) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for road: Dictionary in roads:
		var points: PackedVector3Array=road.points
		for i in range(1,points.size()):
			var a := Vector2(points[i-1].x,points[i-1].z)
			var b := Vector2(points[i].x,points[i].z)
			var half := float(road.width)*.5
			var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(half+2.5)
			if bounds.intersects(rect,true): result.append({"a":a,"b":b,"half":half})
	return result

static func shoulder_weight(point: Vector2, segments: Array) -> float:
	var edge_distance := INF
	for segment: Dictionary in segments:
		edge_distance=minf(edge_distance,Geometry2D.get_closest_point_to_segment(point,segment.a,segment.b).distance_to(point)-float(segment.half))
	var width := 1.65+sin(point.x*.37+point.y*.21)*.31+sin(point.x*.11-point.y*.29)*.29
	return 1.0-smoothstep(.05,width,edge_distance)

static func build_sites_ground(chunk: Node3D, rect: Rect2) -> void:
	_prepare_resources()
	var truck := PackedVector2Array([Vector2(215,-780),Vector2(224,-790),Vector2(314,-788),Vector2(329,-780),Vector2(330,-724),Vector2(320,-712),Vector2(226,-714),Vector2(214,-724)])
	var workshop := PackedVector2Array([Vector2(-158,-943),Vector2(-153,-947),Vector2(-121,-947),Vector2(-116,-941),Vector2(-117,-900),Vector2(-124,-893),Vector2(-153,-896),Vector2(-158,-903)])
	_soft_ground(chunk,"TruckApron",truck,rect,.014)
	_soft_ground(chunk,"DigoApron",workshop,rect,.012)

static func _soft_ground(chunk: Node3D, label: String, polygon: PackedVector2Array, rect: Rect2, offset: float) -> void:
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for p in polygon: bounds=bounds.expand(p)
	var area := bounds.intersection(rect)
	if not area.has_area(): return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	# World-anchored tessellation supplies interior weights and matches adjacent chunks.
	for z in range(floori(area.position.y/4.0),ceili(area.end.y/4.0)):
		for x in range(floori(area.position.x/4.0),ceili(area.end.x/4.0)):
			var tile := Rect2(float(x)*4,float(z)*4,4,4).intersection(area)
			var clip := PackedVector2Array([tile.position,Vector2(tile.end.x,tile.position.y),tile.end,Vector2(tile.position.x,tile.end.y)])
			for part: PackedVector2Array in Geometry2D.intersect_polygons(polygon,clip):
				if Geometry2D.is_polygon_clockwise(part): part.reverse()
				for index in Geometry2D.triangulate_polygon(part):
					var p := part[index]
					var distance := INF
					for i in polygon.size(): distance=minf(distance,Geometry2D.get_closest_point_to_segment(p,polygon[i],polygon[(i+1)%polygon.size()]).distance_to(p))
					var blend := smoothstep(0,3.4+sin(p.x*.36+p.y*.18)*.9,distance)
					vertices.append(Vector3(p.x,_floor_height(p)+offset,p.y))
					normals.append(Vector3.UP)
					colors.append(Color(blend,blend,blend,1))
	if vertices.is_empty(): return
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name=label
	node.mesh=mesh
	node.material_override=_shoulder_material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(node)

static func _batch(parent: Node3D, label: String, mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty(): return
	var batch := MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.use_colors=true
	batch.mesh=mesh
	batch.instance_count=transforms.size()
	for i in transforms.size():
		batch.set_instance_transform(i,transforms[i])
		var shade := .82+float(posmod(i*17,19))*.016
		batch.set_instance_color(i,Color(shade,shade,shade,1))
	var node := MultiMeshInstance3D.new()
	node.name=label
	node.multimesh=batch
	if Engine.get_meta("geteco_live_preview_build",false):
		node.set_meta("preview_instance_transforms",transforms)
		var colors: Array = []
		for i in transforms.size():
			var shade := .82+float(posmod(i*17,19))*.016
			colors.append(Color(shade,shade,shade,1))
		node.set_meta("preview_instance_colors",colors)
	node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end=100.0
	parent.add_child(node)

static func _floor_height(point: Vector2) -> float:
	# Same 8m piecewise bridge ramp used by the region's collision mesh.
	if point.y<=-448: return 0.0
	var low := floorf(point.y/8.0)*8.0
	var high := minf(low+8,LAYOUT.BOUNDS.end.y)
	if high<=low: return LAYOUT.surface_height(point)
	return lerpf(LAYOUT.surface_height(Vector2(point.x,low)),LAYOUT.surface_height(Vector2(point.x,high)),(point.y-low)/(high-low))
