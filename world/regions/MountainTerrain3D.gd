extends RefCounted
## Metric XZ coordinates; NativeRegion owns the returned mesh and collision.
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
const LAKE_BASINS := preload("res://world/regions/LakeBasins.gd")
const TRAIL_BLEND := preload("res://world/regions/MountainTrailBlend.gd")
const STEP := 4.0
const CELL := 64.0
const BLEND := 28.0
const GRID_MARGIN := 6.0 # More than a grid diagonal: flat corridors survive triangulation.
const HEIGHT_SAMPLE_LIMIT := 32768
var _segments: Dictionary = {}
var _clearings: Array[Rect2] = []
## Clareiras por célula de CELL m, como _segments. _clearance varria as ~150 clareiras (6 da V1 + entradas ×
## 4 campos) para cada amostra de altura; um trecho pede ~1.450 amostras (vértices e as 4 vizinhas da
## normal), e o estágio de superfícies da serra custava 20-80 ms por trecho em jogo (travessia de 15/10).
## Clareira mais longe que BLEND não muda o resultado (a distância parte de BLEND), então basta a da célula.
var _clearing_cells: Dictionary = {}
var _material: ShaderMaterial
var _trail_blend := TRAIL_BLEND.new()
var _height_samples: Dictionary = {}
var _height_sample_order: Array[Vector2] = []
var _height_sample_next := 0
## Cópia da margem do lago (LakeBasins.snapshot) tirada no configure: o cálculo de alturas roda também num
## trabalhador (chunk_data) e não pode ler as estáticas que outro configure() reatribuiria no meio.
var _lake_shore := PackedVector2Array()
var _lake_bounds := Rect2()

func configure(roads: Array, entries: Array, clearings: Array) -> void:
	_trail_blend.configure(roads)
	_segments.clear()
	_clearings.clear()
	_clearing_cells.clear()
	_height_samples.clear()
	_height_sample_order.clear()
	_height_sample_next = 0
	# Authored V1 scenery footprints, deliberately flat until their gameplay adopts height.
	for original in [Rect2(6680,-320,800,700), Rect2(5080,-1500,740,680),
		Rect2(7310,-2010,690,720), Rect2(6100,350,510,430),
		Rect2(6100,-5050,2050,2350), Rect2(6200,-2930,380,300)]:
		_clearings.append(Rect2((original.position+CATALOG.MOUNTAIN_OFFSET)/16.0,original.size/16.0).grow(GRID_MARGIN))
	for clearing in clearings:
		if clearing is Rect2: _clearings.append(clearing.grow(GRID_MARGIN))
	# Keep the remote secret exit and its approach supported by the terrain itself.
	# The existing blend joins this small clearing smoothly to the snowy hillside.
	var secret_exit: Vector3 = preload("res://gameplay/urban_v1/fort/MountainFortExit3D.gd").WORLD_POSITION
	_clearings.append(Rect2(Vector2(secret_exit.x-4.0,secret_exit.z-4.0),Vector2(8.0,9.0)).grow(GRID_MARGIN))
	for entry in entries:
		if entry.get("region","mountain") != "mountain": continue
		for field in ["position","exterior_position","entry_position","return_position"]:
			if entry.get(field) is Vector3:
				var p: Vector3 = entry[field]
				var center := Vector2(p.x,p.z)
				_clearings.append(Rect2(center-Vector2.ONE*22.0,Vector2.ONE*44.0))
	for rect in _clearings:
		var reach := rect.grow(BLEND)
		var first := _cell(reach.position)
		var last := _cell(reach.end)
		for x in range(first.x,last.x+1):
			for z in range(first.y,last.y+1):
				var key := Vector2i(x,z)
				if not _clearing_cells.has(key): _clearing_cells[key] = []
				_clearing_cells[key].append(rect)
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
					_segments[key].append({"a":a,"b":b,"radius":radius})
	LAKE_BASINS.configure(roads)
	var lake: Array = LAKE_BASINS.snapshot()
	_lake_shore = lake[0]
	_lake_bounds = lake[1]
	_material = ShaderMaterial.new()
	_material.shader = preload("res://world/regions/mountain_terrain.gdshader")
	preload("res://world/regions/WorldConnection3D.gd").configure_ground_material(_material)
	preload("res://world/regions/MountainGroundFinish.gd").apply_ground(_material)

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/CELL),floori(point.y/CELL))

func _clearance(point: Vector2) -> float:
	var distance := BLEND
	for rect in _clearing_cells.get(_cell(point),[]):
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
	# Terrain, normals and ground dressing repeatedly sample the same points.
	# Keep the exact result; FIFO eviction bounds memory during long journeys.
	if _height_samples.has(point): return _height_samples[point]
	var height := _calculate_height(point)
	_remember_height(point, height)
	return height

func _remember_height(point: Vector2, height: float) -> void:
	if _height_samples.has(point): return
	if _height_sample_order.size() < HEIGHT_SAMPLE_LIMIT:
		_height_sample_order.append(point)
	else:
		_height_samples.erase(_height_sample_order[_height_sample_next])
		_height_sample_order[_height_sample_next] = point
		_height_sample_next = (_height_sample_next + 1) % HEIGHT_SAMPLE_LIMIT
	_height_samples[point] = height

func _calculate_height(point: Vector2) -> float:
	var weight := smoothstep(0.0,BLEND,_clearance(point))
	# Fixed world-space waves: deterministic, continuous across loading boundaries.
	var broad := 0.5+0.5*sin(point.x*0.025+sin(point.y*0.019))*cos(point.y*0.023)
	var detail := 0.5+0.5*sin(point.x*0.075+0.7)*sin(point.y*0.068)
	# The flat road reservation meets the physical road top at y=0. Lowering
	# this terrain made a one-way curb at every narrow track edge.
	return weight*(broad*6.0+detail*1.5)-LAKE_BASINS.depth_in(_lake_shore,_lake_bounds,point)

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

## Cálculo puro do trecho (alturas, normais, cores, índices e máscara das trilhas), sem nó, sem recurso de
## servidor e sem escrever em estado compartilhado: roda num WorkerThreadPool. O estágio de superfícies da
## serra fazia isto no thread principal e custava 30-62 ms por trecho, 13-16 quadros acima de 33 ms por
## travessia (release, fase 2 de 16/10): ~1.450 alturas, cada uma varrendo as estradas e clareiras da célula,
## mais a máscara 129×129 em GDScript. Sem o cache de alturas (escrito pelo thread principal): o valor é o
## mesmo de height_at, que só guarda _calculate_height.
func chunk_data(rect: Rect2) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var heights := PackedFloat64Array()
	var steps := int(CELL/STEP)
	for z in range(steps+1):
		for x in range(steps+1):
			var point := rect.position+Vector2(x,z)*STEP
			var h := _calculate_height(point)
			heights.append(h)
			vertices.append(Vector3(point.x,h,point.y))
			var normal := Vector3(_calculate_height(point-Vector2.RIGHT)-_calculate_height(point+Vector2.RIGHT),2.0,_calculate_height(point-Vector2.DOWN)-_calculate_height(point+Vector2.DOWN)).normalized()
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
	# Triângulos da colisão já no trabalhador: create_trimesh_shape lia a malha de volta da GPU no thread
	# principal (mesmo custo do surface_get_arrays proibido, auditoria de 19/10).
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size(): faces[i] = vertices[indices[i]]
	return {"rect":rect,"vertices":vertices,"normals":normals,"colors":colors,"indices":indices,"faces":faces,"heights":heights,"trail":_trail_blend.mask_for(rect)}

## Entrada do trabalhador: o terreno vai como argumento (referência forte), então não some com a tarefa no ar.
## O resultado é escrito no dicionário de saída e só é lido depois de wait_for_task_completion.
static func prepare_task(terrain: RefCounted, rect: Rect2, out: Dictionary) -> void:
	out.merge(terrain.chunk_data(rect))

## Monta o trecho. `data` vem de chunk_data (pronto num trabalhador); vazio, calcula aqui mesmo (testes,
## ferramentas e quem precisa do chão já). No thread principal ficam só a malha, a forma de colisão e os nós.
func build_chunk(parent: Node3D, rect: Rect2, shore_edges: Array[Dictionary] = [], data: Dictionary = {}) -> MeshInstance3D:
	# Only aligned 64m NativeRegion chunks: no partial edge cells or mismatched seams.
	if rect.size != Vector2.ONE*CELL or rect.position != Vector2(_cell(rect.position))*CELL:
		push_error("MountainTerrain3D requires aligned 64m chunks")
		return null
	if data.is_empty() or data.get("rect") != rect: data = chunk_data(rect)
	# Árvores, pedras, grama e o piloto leem surface_height_at nos mesmos pontos da grade: ficam no cache como
	# quando build_chunk calculava aqui.
	var steps := int(CELL/STEP)
	var heights: PackedFloat64Array = data.heights
	for z in range(steps+1):
		for x in range(steps+1):
			_remember_height(rect.position+Vector2(x,z)*STEP,heights[z*(steps+1)+x])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_COLOR] = data.colors
	arrays[Mesh.ARRAY_INDEX] = data.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var result := MeshInstance3D.new()
	result.name = "MountainTerrain"
	result.mesh = mesh
	var chunk_material := _material.duplicate() as ShaderMaterial
	chunk_material.set_shader_parameter("trail_mask",ImageTexture.create_from_image(Image.create_from_data(TRAIL_BLEND.SIZE,TRAIL_BLEND.SIZE,false,Image.FORMAT_R8,data.trail)))
	result.material_override = chunk_material
	result.set_instance_shader_parameter("origin",rect.position)
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	var body := StaticBody3D.new()
	body.set_meta("mountain_terrain", true)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	# Mesmos triângulos da malha, na mesma ordem (o que create_trimesh_shape faria, sem ler a GPU).
	var collision_shape := ConcavePolygonShape3D.new()
	# Dado de fora sem "faces" (montado por um teste ou versão antiga do trabalhador): a mesma expansão aqui.
	var faces: PackedVector3Array = data.get("faces", PackedVector3Array())
	if faces.is_empty():
		var indices: PackedInt32Array = data.indices
		var vertices: PackedVector3Array = data.vertices
		faces.resize(indices.size())
		for i in indices.size(): faces[i] = vertices[indices[i]]
	collision_shape.set_faces(faces)
	shape.shape = collision_shape
	body.add_child(shape)
	result.add_child(body)
	# Only the explicit bridge water spans have permanent exposed banks.
	preload("res://world/regions/MountainBridgeShore.gd").build_chunk(parent,rect,self,shore_edges)
	preload("res://world/regions/MountainTerrain3DPilot.gd").attach(self,result,rect,chunk_material.get_shader_parameter("trail_mask"))
	return result
