extends RefCounted
## Metric XZ coordinates; NativeRegion owns the returned mesh and collision.
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
const STEP := 4.0
const CELL := 64.0
const BLEND := 28.0
const GRID_MARGIN := 6.0 # More than a grid diagonal: flat corridors survive triangulation.
var _segments: Dictionary = {}
var _clearings: Array[Rect2] = []
var _material: StandardMaterial3D

func configure(roads: Array, entries: Array, clearings: Array) -> void:
	_segments.clear()
	_clearings.clear()
	# Authored V1 scenery footprints, deliberately flat until their gameplay adopts height.
	for original in [Rect2(6680,-320,800,700), Rect2(5080,-1500,740,680),
		Rect2(7310,-2010,690,720), Rect2(6100,350,510,430),
		Rect2(6100,-5050,2050,2350), Rect2(6200,-2930,380,300)]:
		_clearings.append(Rect2((original.position+CATALOG.MOUNTAIN_OFFSET)/16.0,original.size/16.0).grow(GRID_MARGIN))
	for clearing in clearings:
		if clearing is Rect2: _clearings.append(clearing.grow(GRID_MARGIN))
	for entry in entries:
		if entry.get("region","mountain") != "mountain": continue
		for field in ["position","exterior_position","entry_position","return_position"]:
			if entry.get(field) is Vector3:
				var p: Vector3 = entry[field]
				var center := Vector2(p.x,p.z)
				_clearings.append(Rect2(center-Vector2.ONE*22.0,Vector2.ONE*44.0))
	for road in roads:
		var points: PackedVector3Array = road.points
		var radius: float = float(road.width)*0.5+3.0+GRID_MARGIN
		for i in range(points.size()-1):
			var a := Vector2(points[i].x,points[i].z)
			var b := Vector2(points[i+1].x,points[i+1].z)
			var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(radius+BLEND)
			var first := _cell(bounds.position)
			var last := _cell(bounds.end)
			for x in range(first.x,last.x+1):
				for z in range(first.y,last.y+1):
					var key := Vector2i(x,z)
					if not _segments.has(key): _segments[key] = []
					_segments[key].append({"a":a,"b":b,"radius":radius,"bed_radius":float(road.width)*0.5+4.0})
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/CELL),floori(point.y/CELL))

func _clearance(point: Vector2) -> float:
	var distance := BLEND
	for rect in _clearings:
		var nearest := point.clamp(rect.position,rect.end)
		distance = minf(distance,point.distance_to(nearest))
		if distance <= 0.0: return 0.0
	for segment in _segments.get(_cell(point),[]):
		var nearest := Geometry2D.get_closest_point_to_segment(point,segment.a,segment.b)
		distance = minf(distance,maxf(0.0,point.distance_to(nearest)-float(segment.radius)))
	return distance

func is_reserved(point: Vector2, radius: float = 0.0) -> bool:
	return _clearance(point) <= maxf(0.0,radius)

func height_at(point: Vector2) -> float:
	var weight := smoothstep(0.0,BLEND,_clearance(point))
	# Fixed world-space waves: deterministic, continuous across loading boundaries.
	var broad := 0.5+0.5*sin(point.x*0.025+sin(point.y*0.019))*cos(point.y*0.023)
	var detail := 0.5+0.5*sin(point.x*0.075+0.7)*sin(point.y*0.068)
	# The asphalt slab meets the Harbor bridge at y=0. Give it a small bed
	# below that plane, including at 4 m mesh-grid corners, so terrain triangles
	# never fight with road pixels or the road's physical top face.
	var bed := 0.0
	for segment in _segments.get(_cell(point),[]):
		var nearest := Geometry2D.get_closest_point_to_segment(point,segment.a,segment.b)
		var beyond: float = point.distance_to(nearest)-float(segment.bed_radius)
		bed = maxf(bed,1.0-smoothstep(0.0,4.0,beyond))
	return weight*(broad*6.0+detail*1.5)-bed*0.055

func surface_height_at(point: Vector2) -> float:
	# Same diagonal and interpolation as build_chunk, for trees/rocks without floating.
	var origin := Vector2(floorf(point.x/STEP),floorf(point.y/STEP))*STEP
	var f := (point-origin)/STEP
	var a := height_at(origin)
	var b := height_at(origin+Vector2(STEP,0))
	var c := height_at(origin+Vector2(0,STEP))
	var d := height_at(origin+Vector2.ONE*STEP)
	if f.x+f.y <= 1.0: return a+(b-a)*f.x+(c-a)*f.y
	return d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y)

func build_chunk(parent: Node3D, rect: Rect2) -> MeshInstance3D:
	# Only aligned 64m NativeRegion chunks: no partial edge cells or mismatched seams.
	if rect.size != Vector2.ONE*CELL or rect.position != Vector2(_cell(rect.position))*CELL:
		push_error("MountainTerrain3D requires aligned 64m chunks")
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var steps := int(CELL/STEP)
	for z in range(steps+1):
		for x in range(steps+1):
			var point := rect.position+Vector2(x,z)*STEP
			var h := height_at(point)
			vertices.append(Vector3(point.x,h,point.y))
			var normal := Vector3(height_at(point-Vector2.RIGHT)-height_at(point+Vector2.RIGHT),2.0,height_at(point-Vector2.DOWN)-height_at(point+Vector2.DOWN)).normalized()
			normals.append(normal)
			var original_y: float = point.y*16.0-CATALOG.MOUNTAIN_OFFSET.y
			var snow := 1.0-smoothstep(-1500.0,-1200.0,original_y)
			var earth := Color("52634a").lerp(Color("72766b"),clampf(h/7.5,0.0,1.0))
			colors.append(earth.lerp(Color("d2d9d9"),snow))
	for z in range(steps):
		for x in range(steps):
			var a := z*(steps+1)+x
			var b := a+1
			var c := a+steps+1
			var d := c+1
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var result := MeshInstance3D.new()
	result.name = "MountainTerrain"
	result.mesh = mesh
	result.material_override = _material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	result.add_child(body)
	return result
