extends RefCounted
## Opaque, streamed ocean. Shore distance is baked on creation, never per frame.
const WATER_Y := -0.94 # Preserve the top of the previous water box.
const STEP := 4.0
const DEPTH_RANGE := 24.0
## Período das ondas em metros. O shader recebe coordenada local 0..PERIOD em UV:
## no renderizador Mobile a coordenada de mundo (~500 m) perdia precisão no
## fragmento e a fase das ondas virava blocos quadrados (captura de 2026-09-24).
const PERIOD := 256.0
## Vão da ponte Harbor–Mountain: o tabuleiro ficava a 17 cm do mar e a ponte não
## tinha altura nenhuma. Só a água desce (até BRIDGE_DROP), longe de qualquer
## margem e com transição suave; tabuleiro, colisão e trânsito não mudam.
const BRIDGE_DROP := 3.0
const BRIDGE_START_X := 6300.0/16.0
const BRIDGE_END_X := (4300.0+4650.0)/16.0
const BRIDGE_CENTER_Z := -4560.0/16.0

static func surface_y(point: Vector2, shore: float = DEPTH_RANGE) -> float:
	var along := smoothstep(BRIDGE_START_X+10.0,BRIDGE_START_X+35.0,point.x)*(1.0-smoothstep(BRIDGE_END_X-35.0,BRIDGE_END_X-10.0,point.x))
	var across := 1.0-smoothstep(25.0,70.0,absf(point.y-BRIDGE_CENTER_Z))
	return WATER_Y-BRIDGE_DROP*along*across*smoothstep(8.0,22.0,shore)
const SHADER := preload("res://world/regions/harbor_ocean.gdshader")
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
var shores: Array[PackedVector2Array] = []
var material: ShaderMaterial
var shore_wash := preload("res://world/regions/HarborShoreWash.gd").new()

func configure(land: Array, extra: Array[PackedVector2Array]) -> void:
	shores.clear()
	for row in land:
		var rect := Rect2(float(row[0])/16.0,float(row[1])/16.0,float(row[2])/16.0,float(row[3])/16.0)
		shores.append(PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]))
	shores.append_array(extra)
	material = ShaderMaterial.new()
	material.shader = SHADER
	shore_wash.configure(shores)

func shore_distance(point: Vector2) -> float:
	var nearest := DEPTH_RANGE
	for polygon in shores:
		for i in polygon.size():
			var closest := Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])
			nearest = minf(nearest,point.distance_to(closest))
	return nearest

## Broad phase computed once per chunk. Every retained edge keeps its original
## order; exact closest-point distances still determine each vertex's shore color.
## The margin includes boundary/rounding cases, and also accepts zero-width AABBs.
func _nearby_shore_edges(rect: Rect2) -> PackedVector2Array:
	var area := rect.abs().grow(DEPTH_RANGE + 0.001)
	var edges := PackedVector2Array()
	for polygon in shores:
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var bounds := Rect2(a, Vector2.ZERO).expand(b)
			if area.intersects(bounds, true):
				edges.append(a)
				edges.append(b)
	return edges

func _shore_distance_from_edges(point: Vector2, edges: PackedVector2Array) -> float:
	var nearest := DEPTH_RANGE
	for i in range(0, edges.size(), 2):
		var closest := Geometry2D.get_closest_point_to_segment(point, edges[i], edges[i + 1])
		nearest = minf(nearest, point.distance_to(closest))
	return nearest

func build_chunk(parent: Node3D, rect: Rect2) -> MeshInstance3D:
	# Exclude actual land geometry, not cell centres: even an island smaller
	# than STEP must stay dry, without a square gap in the surrounding sea.
	var dry: Array[PackedVector2Array] = []
	for polygon in shores:
		if polygon.size() >= 3 and GROUND_CUT.bounds(polygon).intersects(rect): dry.append(polygon)
	dry.append(GROUND_CUT.rect_polygon(CANAL_TUNNEL.WATER_CUT))
	if preload("res://activities/skate/SkateParkLayout.gd").enabled():
		dry.append(GROUND_CUT.rect_polygon(preload("res://activities/skate/SkateParkLayout.gd").FOOTPRINT))
	if GROUND_CUT.subtract_exact([GROUND_CUT.rect_polygon(rect)],dry).is_empty(): return null
	var edges := _nearby_shore_edges(rect)
	var count := maxi(1,ceili(rect.size.x/STEP))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	# Chunks de 64 m alinhados cabem inteiros num bloco de PERIOD: sem costura dentro do chunk.
	var base := (rect.position/PERIOD).floor()*PERIOD
	var indices := PackedInt32Array()
	for z in range(count+1):
		for x in range(count+1):
			var point := rect.position+rect.size*Vector2(float(x)/count,float(z)/count)
			var shore := _shore_distance_from_edges(point, edges)
			vertices.append(Vector3(point.x,surface_y(point,shore),point.y))
			normals.append(Vector3.UP)
			colors.append(Color(shore/DEPTH_RANGE,0,0,1))
			uvs.append(point-base)
	for z in count:
		for x in count:
			var a := z*(count+1)+x
			var tile := Rect2(rect.position + rect.size * Vector2(float(x)/count, float(z)/count), rect.size / count)
			var tile_cuts: Array[PackedVector2Array] = []
			for polygon in dry:
				if GROUND_CUT.bounds(polygon).intersects(tile): tile_cuts.append(polygon)
			if tile_cuts.is_empty():
				indices.append_array(PackedInt32Array([a,a+1,a+count+1,a+1,a+count+2,a+count+1]))
				continue
			for piece in GROUND_CUT.subtract_exact([GROUND_CUT.rect_polygon(tile)],tile_cuts):
				var triangles := Geometry2D.triangulate_polygon(piece)
				if triangles.is_empty(): continue
				var offset := vertices.size()
				for point in piece:
					var shore := _shore_distance_from_edges(point,edges)
					vertices.append(Vector3(point.x,surface_y(point,shore),point.y))
					normals.append(Vector3.UP)
					colors.append(Color(shore/DEPTH_RANGE,0,0,1))
					uvs.append(point-base)
				for index in triangles: indices.append(offset+index)
	if indices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var surface := MeshInstance3D.new()
	surface.name = "Water"
	surface.mesh = mesh
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(surface)
	shore_wash.build_chunk(surface,rect)
	return surface
