extends RefCounted
## Conforming local refinement. Render, height queries and streamed collision share faces.
const FIELD := preload("res://world/desert/DesertTerrainRelief.gd")
const SHADER := preload("res://world/desert/desert_relief.gdshader")
const LIFETIME := preload("res://world/desert/DesertPreparationLifetime.gd")
const CELL := 96.0
const STEP := 2.0
const CAMERA_SAMPLE_STEP := 1.0
const CURVATURE_ERROR := .04
const MIN_NORMAL_Y := .90
static var _meshes: Dictionary = {}
static var _faces: Dictionary = {}
static var _samples: Dictionary = {}
static var _refinement: Dictionary = {}
static var _tiles: Dictionary = {}
static var _tile_kinds: Dictionary = {} # 0 coarse, 1 transition, 2 refined.
static var _scratch_released := false
static var _released_sample_count := 0
static var _kinds: Dictionary = {"coarse":0,"transition":0,"refined":0}
static var _material: ShaderMaterial

static func cell_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key)*CELL,Vector2.ONE*CELL).intersection(FIELD.BOUNDS)

static func build_visuals() -> Node3D:
	var root := Node3D.new()
	root.name="DesertCanyonTerrain"
	for z in range(floori(FIELD.BOUNDS.position.y/CELL),ceili(FIELD.BOUNDS.end.y/CELL)):
		for x in range(floori(FIELD.BOUNDS.position.x/CELL),ceili(FIELD.BOUNDS.end.x/CELL)):
			var key := Vector2i(x,z)
			var node := MeshInstance3D.new()
			node.name="Canyon_%d_%d"%[x,z]
			node.mesh=mesh_for(key)
			node.material_override=material()
			root.add_child(node)
	release_generation_scratch()
	return root

## Mesma montagem de build_visuals, cedendo o quadro quando passa do orçamento: o horizonte
## do mirante costeiro montava o terreno inteiro do deserto num quadro só (~9 s congelando
## a janela no carregamento, auditoria de 16/10). Resultado idêntico.
static func build_visuals_sliced(tree: SceneTree, budget_usec := 12000, token: Dictionary = {}) -> Node3D:
	if LIFETIME.cancelled(token): return null
	var root := Node3D.new()
	LIFETIME.track(token,root)
	root.name="DesertCanyonTerrain"
	var slice := Time.get_ticks_usec()
	for z in range(floori(FIELD.BOUNDS.position.y/CELL),ceili(FIELD.BOUNDS.end.y/CELL)):
		for x in range(floori(FIELD.BOUNDS.position.x/CELL),ceili(FIELD.BOUNDS.end.x/CELL)):
			var key := Vector2i(x,z)
			var prepared_mesh: ArrayMesh=await mesh_for_sliced(key,tree,budget_usec,token)
			if LIFETIME.cancelled(token): return null
			var node := MeshInstance3D.new()
			node.name="Canyon_%d_%d"%[x,z]
			node.mesh=prepared_mesh
			node.material_override=material()
			root.add_child(node)
			if Time.get_ticks_usec() - slice > budget_usec:
				await tree.process_frame
				if LIFETIME.cancelled(token): return null
				slice = Time.get_ticks_usec()
	release_generation_scratch()
	LIFETIME.release(token,root)
	return root

## A cold cell can itself take hundreds of milliseconds. Yield inside its
## tile generation; vertex order, normals and physical faces stay identical.
static func mesh_for_sliced(key: Vector2i, tree: SceneTree, budget_usec: int, token: Dictionary = {}) -> ArrayMesh:
	if LIFETIME.cancelled(token): return null
	if _meshes.has(key): return _meshes[key]
	var rect := cell_rect(key)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var slice := Time.get_ticks_usec()
	for z in range(floori(rect.position.y/STEP),ceili(rect.end.y/STEP)):
		for x in range(floori(rect.position.x/STEP),ceili(rect.end.x/STEP)):
			var faces := _tile_faces(Vector2i(x,z))
			vertices.append_array(faces)
			for vertex in faces: normals.append(_sample(Vector2(vertex.x,vertex.z)).normal)
			if Time.get_ticks_usec()-slice>budget_usec:
				await tree.process_frame
				if LIFETIME.cancelled(token): return null
				slice=Time.get_ticks_usec()
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	# Célula fora do campo de relevo (mapa compacto de 21/10) não tem faces: superfície vazia dava erro
	# do RenderingServer (array_len == 0); a malha sem superfície continua valendo como "pronta".
	if not vertices.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_meshes[key]=mesh
	_faces[key]=vertices
	return mesh

static func release_generation_scratch() -> bool:
	# Only after EVERY visual cell and tile is cached: no later height/collision
	# query needs the classification or analytic height/normal dictionaries.
	for z in range(floori(FIELD.BOUNDS.position.y/CELL),ceili(FIELD.BOUNDS.end.y/CELL)):
		for x in range(floori(FIELD.BOUNDS.position.x/CELL),ceili(FIELD.BOUNDS.end.x/CELL)):
			if not _meshes.has(Vector2i(x,z)): return false
	var columns := ceili(FIELD.BOUNDS.end.x/STEP)-floori(FIELD.BOUNDS.position.x/STEP)
	var rows := ceili(FIELD.BOUNDS.end.y/STEP)-floori(FIELD.BOUNDS.position.y/STEP)
	if _tiles.size()!=columns*rows or _tile_kinds.size()!=_tiles.size(): return false
	_released_sample_count=maxi(_released_sample_count,_samples.size())
	_samples.clear()
	_refinement.clear()
	_scratch_released=true
	return true

static func material() -> ShaderMaterial:
	if _material==null:
		_material=ShaderMaterial.new()
		_material.shader=SHADER
		_material.set_shader_parameter("base_color",Color("b9a079"))
	return _material

static func _sample(p: Vector2) -> Dictionary:
	if not _samples.has(p):
		# Keep the ORIGINAL radius2 normal, including at new subdivision vertices.
		_samples[p]={"height":FIELD.height_at(p),"normal":FIELD.normal_at(p,2.0)}
	return _samples[p]

static func _vertex(p: Vector2) -> Vector3:
	return Vector3(p.x,float(_sample(p).height),p.y)

static func _tile_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key)*STEP,Vector2.ONE*STEP).intersection(FIELD.BOUNDS)

static func _is_refined(key: Vector2i) -> bool:
	if _refinement.has(key): return bool(_refinement[key])
	var rect := _tile_rect(key)
	if not rect.has_area():
		_refinement[key]=false
		return false
	var a := rect.position
	var b := Vector2(rect.end.x,rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x,rect.end.y)
	var points: Array[Vector2]=[a,b,c,d,(a+c)*.5]
	var steep := false
	for p in points:
		var normal: Vector3=_sample(p).normal
		steep=steep or normal.y<MIN_NORMAL_Y
	var ha := float(_sample(a).height)
	var hb := float(_sample(b).height)
	var hc := float(_sample(c).height)
	var hd := float(_sample(d).height)
	var error := absf(float(_sample((a+c)*.5).height)-(ha+hc)*.5)
	var mids: Array[Vector2]=[(a+b)*.5,(b+c)*.5,(c+d)*.5,(d+a)*.5]
	var linear: Array[float]=[(ha+hb)*.5,(hb+hc)*.5,(hc+hd)*.5,(hd+ha)*.5]
	for i in range(4): error=maxf(error,absf(float(_sample(mids[i]).height)-linear[i]))
	var result := steep or error>CURVATURE_ERROR
	_refinement[key]=result
	return result

static func _append_triangle(faces: PackedVector3Array,a: Vector2,b: Vector2,c: Vector2) -> void:
	faces.append(_vertex(a))
	faces.append(_vertex(b))
	faces.append(_vertex(c))

static func _tile_faces(key: Vector2i) -> PackedVector3Array:
	if _tiles.has(key): return _tiles[key]
	var rect := _tile_rect(key)
	var faces := PackedVector3Array()
	if not rect.has_area(): return faces
	var a := rect.position
	var b := Vector2(rect.end.x,rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x,rect.end.y)
	if _is_refined(key):
		_tile_kinds[key]=2
		_kinds.refined=int(_kinds.refined)+1
		var half := rect.size*.5
		for z in range(2):
			for x in range(2):
				var p := a+Vector2(float(x)*half.x,float(z)*half.y)
				var q := p+Vector2(half.x,0)
				var r := p+half
				var s := p+Vector2(0,half.y)
				_append_triangle(faces,p,q,r)
				_append_triangle(faces,p,r,s)
	else:
		var top := _is_refined(key+Vector2i(0,-1))
		var right := _is_refined(key+Vector2i(1,0))
		var bottom := _is_refined(key+Vector2i(0,1))
		var left := _is_refined(key+Vector2i(-1,0))
		if top or right or bottom or left:
			_tile_kinds[key]=1
			_kinds.transition=int(_kinds.transition)+1
			var ring: Array[Vector2]=[a]
			if top: ring.append((a+b)*.5)
			ring.append(b)
			if right: ring.append((b+c)*.5)
			ring.append(c)
			if bottom: ring.append((c+d)*.5)
			ring.append(d)
			if left: ring.append((d+a)*.5)
			var center := (a+c)*.5
			for i in range(ring.size()):
				_append_triangle(faces,center,ring[i],ring[(i+1)%ring.size()])
		else:
			_tile_kinds[key]=0
			_kinds.coarse=int(_kinds.coarse)+1
			_append_triangle(faces,a,b,c)
			_append_triangle(faces,a,c,d)
	_tiles[key]=faces
	return faces

static func mesh_for(key: Vector2i) -> ArrayMesh:
	if _meshes.has(key): return _meshes[key]
	var rect := cell_rect(key)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for z in range(floori(rect.position.y/STEP),ceili(rect.end.y/STEP)):
		for x in range(floori(rect.position.x/STEP),ceili(rect.end.x/STEP)):
			var faces := _tile_faces(Vector2i(x,z))
			vertices.append_array(faces)
	for v in vertices:
		normals.append(_sample(Vector2(v.x,v.z)).normal)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	# Célula fora do campo de relevo (mapa compacto de 21/10) não tem faces: superfície vazia dava erro
	# do RenderingServer (array_len == 0); a malha sem superfície continua valendo como "pronta".
	if not vertices.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_meshes[key]=mesh
	_faces[key]=vertices
	return mesh

static func install_collision(parent: Node3D,key: Vector2i) -> void:
	if not cell_rect(key).has_area(): return
	mesh_for(key)
	var body := StaticBody3D.new()
	body.name="CanyonGroundCollider"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface","dirt")
	body.set_meta("desert_continuous_ground",true)
	body.set_meta("desert_ground_height",surface_height)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces[key])
	var node := CollisionShape3D.new()
	node.shape=shape
	body.add_child(node)
	parent.add_child(body)

static func surface_height(p: Vector2) -> float:
	if not FIELD.BOUNDS.has_point(p): return 0.0
	var key := Vector2i(floori(p.x/STEP),floori(p.y/STEP))
	var faces := _tile_faces(key)
	var kind := int(_tile_kinds[key])
	if kind==0:
		var t := (p-Vector2(key)*STEP)/STEP
		return _quad_height(faces,0,t)
	if kind==2:
		var t := (p-Vector2(key)*STEP)/(STEP*.5)
		var column := mini(floori(t.x),1)
		var row := mini(floori(t.y),1)
		return _quad_height(faces,(row*2+column)*6,t-Vector2(column,row))
	# Transition fans only: the exact cached triangles, at most8.
	for i in range(0,faces.size(),3):
		var a := Vector2(faces[i].x,faces[i].z)
		var b := Vector2(faces[i+1].x,faces[i+1].z)
		var c := Vector2(faces[i+2].x,faces[i+2].z)
		var denominator := (b-a).cross(c-a)
		var u := (p-a).cross(c-a)/denominator
		var v := (b-a).cross(p-a)/denominator
		if u>=-.00001 and v>=-.00001 and u+v<=1.00001:
			return faces[i].y*(1.0-u-v)+faces[i+1].y*u+faces[i+2].y*v
	push_error("Refined terrain tile did not cover point %s"%p)
	return NAN

static func _quad_height(faces: PackedVector3Array,at: int,t: Vector2) -> float:
	# Stored order a,b,c,a,c,d; direct barycentric evaluation of ONE triangle.
	var a := faces[at].y
	var c := faces[at+2].y
	if t.x>=t.y: return a*(1.0-t.x)+faces[at+1].y*(t.x-t.y)+c*t.y
	return a*(1.0-t.y)+c*t.x+faces[at+5].y*(t.y-t.x)

static func diagnostics() -> Dictionary:
	var vertex_count := 0
	for values in _faces.values():
		var faces: PackedVector3Array=values
		vertex_count+=faces.size()
	var tile_vertices := 0
	for values in _tiles.values():
		var faces: PackedVector3Array=values
		tile_vertices+=faces.size()
	return {"cells":_meshes.size(),"tiles":_tiles.size(),"tile_kinds":_kinds.duplicate(),"triangles":int(float(vertex_count)/3.0),"render_vertex_normal_payload_bytes":vertex_count*24,"cpu_cell_face_payload_bytes":vertex_count*12,"cpu_tile_face_payload_bytes":tile_vertices*12,"scratch_released":_scratch_released,"released_sample_count":_released_sample_count,"refinement_cache_count":_refinement.size(),"sample_count":_samples.size(),"sample_numeric_payload_bytes_lower_bound":_samples.size()*24,"memory_note":"Numeric payload counts only. Dictionary/Variant/allocator overhead, GPU packing, mesh storage and physics acceleration structure excluded. Not measured total memory.","normal_sample_radius":2.0,"base_step":STEP,"refined_step":STEP*.5}

static func flat_remainders(rect: Rect2) -> Array[Rect2]:
	var overlap := rect.intersection(FIELD.BOUNDS)
	if not overlap.has_area(): return [rect]
	var result: Array[Rect2]=[]
	for part in [
		Rect2(rect.position.x,rect.position.y,rect.size.x,overlap.position.y-rect.position.y),
		Rect2(rect.position.x,overlap.end.y,rect.size.x,rect.end.y-overlap.end.y),
		Rect2(rect.position.x,overlap.position.y,overlap.position.x-rect.position.x,overlap.size.y),
		Rect2(overlap.end.x,overlap.position.y,rect.end.x-overlap.end.x,overlap.size.y),
	]:
		if part.has_area(): result.append(part)
	return result
