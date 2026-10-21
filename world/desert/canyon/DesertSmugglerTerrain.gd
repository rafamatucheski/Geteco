extends RefCounted
const LIFETIME := preload("res://world/desert/DesertPreparationLifetime.gd")
## One shared triangulation for visible geology, physical floor and height queries.
const L := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const SANDSTONE := preload("res://world/desert/canyon/smuggler_sandstone.gdshader")
const CELL := 96.0
static var _meshes: Dictionary={}
static var _faces: Dictionary={}
static var _samples: Dictionary={}
static var _tiles: Dictionary={}
static var _refined: Dictionary={}
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material==null:
		_material=ShaderMaterial.new()
		_material.shader=SANDSTONE
		_material.set_shader_parameter("base_color",Color("b9a079"))
	return _material

static func _sample(p: Vector2) -> Dictionary:
	if not _samples.has(p):
		var radius := .25
		var dx := L.analytic_height(p+Vector2(radius,0))-L.analytic_height(p-Vector2(radius,0))
		var dz := L.analytic_height(p+Vector2(0,radius))-L.analytic_height(p-Vector2(0,radius))
		_samples[p]={"height":L.analytic_height(p),"normal":Vector3(-dx,2*radius,-dz).normalized()}
	return _samples[p]

static func _vertex(p: Vector2) -> Vector3:
	return Vector3(p.x,float(_sample(p).height),p.y)

static func surface_height(p: Vector2) -> float:
	if not L.BOUNDS.has_point(p): return 0.0
	var faces := _tile_faces(Vector2i((p/L.STEP).floor()))
	for i in range(0,faces.size(),3):
		var a := Vector2(faces[i].x,faces[i].z)
		var b := Vector2(faces[i+1].x,faces[i+1].z)
		var c := Vector2(faces[i+2].x,faces[i+2].z)
		var denominator := (b-a).cross(c-a)
		var u := (p-a).cross(c-a)/denominator
		var v := (b-a).cross(p-a)/denominator
		if u>=-.00001 and v>=-.00001 and u+v<=1.00001:
			return faces[i].y*(1-u-v)+faces[i+1].y*u+faces[i+2].y*v
	push_error("Canyon terrain tile does not cover "+str(p))
	return NAN

static func _tile_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key)*L.STEP,Vector2.ONE*L.STEP).intersection(L.BOUNDS)

static func _is_refined(key: Vector2i) -> bool:
	if _refined.has(key): return _refined[key]
	var rect := _tile_rect(key)
	if not rect.has_area(): return false
	var low := INF
	var high := -INF
	for p: Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.get_center()]:
		var h := float(_sample(p).height)
		low=minf(low,h)
		high=maxf(high,h)
	_refined[key]=high-low>1.25
	return _refined[key]

static func _triangle(faces: PackedVector3Array,a: Vector2,b: Vector2,c: Vector2) -> void:
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
		var step := rect.size/3.0
		for z in 3:
			for x in 3:
				var p := a+Vector2(x,z)*step
				var q := p+Vector2(step.x,0)
				var r := p+step
				var s := p+Vector2(0,step.y)
				_triangle(faces,p,q,r)
				_triangle(faces,p,r,s)
	else:
		var top := _is_refined(key+Vector2i(0,-1))
		var right := _is_refined(key+Vector2i(1,0))
		var bottom := _is_refined(key+Vector2i(0,1))
		var left := _is_refined(key+Vector2i(-1,0))
		if top or right or bottom or left:
			# Match every refined edge vertex. A plain coarse quad would leave
			# cracks where a shelf turns into the half-metre rock mesh.
			var ring: Array[Vector2]=[a]
			if top: ring.append_array([a.lerp(b,1.0/3),a.lerp(b,2.0/3)])
			ring.append(b)
			if right: ring.append_array([b.lerp(c,1.0/3),b.lerp(c,2.0/3)])
			ring.append(c)
			if bottom: ring.append_array([c.lerp(d,1.0/3),c.lerp(d,2.0/3)])
			ring.append(d)
			if left: ring.append_array([d.lerp(a,1.0/3),d.lerp(a,2.0/3)])
			for i in ring.size(): _triangle(faces,rect.get_center(),ring[i],ring[(i+1)%ring.size()])
		else:
			_triangle(faces,a,b,c)
			_triangle(faces,a,c,d)
	_tiles[key]=faces
	return faces

static func mesh_for(key: Vector2i) -> ArrayMesh:
	if _meshes.has(key): return _meshes[key]
	var rect := Rect2(Vector2(key)*CELL,Vector2.ONE*CELL).intersection(L.BOUNDS)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for z in range(floori(rect.position.y/L.STEP),ceili(rect.end.y/L.STEP)):
		for x in range(floori(rect.position.x/L.STEP),ceili(rect.end.x/L.STEP)):
			vertices.append_array(_tile_faces(Vector2i(x,z)))
	for i in range(0,vertices.size(),3):
		for j in 3:
			var v := vertices[i+j]
			# Half-metre escarpment samples resolve the continuous profile.
			# Sharing its normal avoids triangle bands at each shelf lip.
			normals.append(_sample(Vector2(v.x,v.z)).normal)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_meshes[key]=mesh
	_faces[key]=vertices
	return mesh

static func build_visuals() -> Node3D:
	var root := Node3D.new()
	root.name="SmugglerGorgeGeology"
	for z in range(floori(L.BOUNDS.position.y/CELL),ceili(L.BOUNDS.end.y/CELL)):
		for x in range(floori(L.BOUNDS.position.x/CELL),ceili(L.BOUNDS.end.x/CELL)):
			var node := MeshInstance3D.new()
			node.name="GorgeRock_%d_%d"%[x,z]
			node.mesh=mesh_for(Vector2i(x,z))
			node.material_override=material()
			root.add_child(node)
	# Render resources now cover every cell; collision reuses these exact faces.
	# Height queries need no generation dictionaries after the first build.
	_samples.clear()
	_refined.clear()
	return root

## Igual a build_visuals, cedendo o quadro quando a fatia passa do orçamento: montada de uma vez
## dentro do mirante costeiro, a geologia do cânion segurava ~2 s num quadro só no carregamento (16/10).
static func build_visuals_sliced(tree: SceneTree,budget_usec := 12000, token: Dictionary = {}) -> Node3D:
	if LIFETIME.cancelled(token): return null
	var root := Node3D.new()
	LIFETIME.track(token,root)
	root.name="SmugglerGorgeGeology"
	var slice := Time.get_ticks_usec()
	for z in range(floori(L.BOUNDS.position.y/CELL),ceili(L.BOUNDS.end.y/CELL)):
		for x in range(floori(L.BOUNDS.position.x/CELL),ceili(L.BOUNDS.end.x/CELL)):
			var node := MeshInstance3D.new()
			node.name="GorgeRock_%d_%d"%[x,z]
			node.mesh=mesh_for(Vector2i(x,z))
			node.material_override=material()
			root.add_child(node)
			if Time.get_ticks_usec()-slice > budget_usec:
				await tree.process_frame
				if LIFETIME.cancelled(token): return null
				slice=Time.get_ticks_usec()
	_samples.clear()
	_refined.clear()
	LIFETIME.release(token,root)
	return root

static func build_collision(parent: Node3D,rect: Rect2) -> void:
	if not rect.intersects(L.BOUNDS): return
	var key := Vector2i((rect.get_center()/CELL).floor())
	mesh_for(key)
	var body := StaticBody3D.new()
	body.name="SmugglerGorgeGround"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface","dirt")
	body.set_meta("desert_continuous_ground",true)
	body.set_meta("desert_ground_height",surface_height)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces[key])
	var collider := CollisionShape3D.new()
	collider.shape=shape
	body.add_child(collider)
	parent.add_child(body)
