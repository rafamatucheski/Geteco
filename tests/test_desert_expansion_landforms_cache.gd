extends SceneTree
## Resource reuse is a functional contract, not a frame-time benchmark.
const LAND := preload("res://world/desert/expansion/DesertLandforms.gd")
var failures: Array[String]=[]
var checks := 0

class HeightProvider:
	extends Node3D
	var elevation := 0.0
	func height(_point: Vector2) -> float: return elevation

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func _base_height(_point: Vector2) -> float:
	return 0.0

func _run() -> void:
	var cells: Array[Vector2i]=LAND.resource_cells()
	_check(cells.size()==28,"Warm-up covers the finite 28 authored candidate cells")
	var baseline: Dictionary={}
	Engine.set_meta("desert_landform_cache_benchmark_disabled",true)
	var disabled: Dictionary=LAND.prewarm(_base_height)
	_check(not disabled.enabled and not disabled.ready,"Debug comparison skips resource prewarm")
	for cell in cells:
		var original := Node3D.new()
		var count: int=LAND.build_chunk(original,Rect2(Vector2(cell)*96.0,Vector2.ONE*96.0),6102026,_base_height)
		baseline[cell]={"count":count,"signature":_signature(original)}
		original.free()
	Engine.set_meta("desert_landform_cache_benchmark_disabled",false)
	var prepared: Dictionary=LAND.prewarm(_base_height)
	_check(prepared.ready and int(prepared.cached_cells)==cells.size(),"All resources exist before the first gameplay visit")
	_check(int(prepared.geometry_builds)==cells.size(),"Each candidate is generated once during prewarm")
	var mismatches := 0
	var unshared := 0
	var populated := 0
	for cell in cells:
		var first := Node3D.new()
		var second := Node3D.new()
		var rect := Rect2(Vector2(cell)*96.0,Vector2.ONE*96.0)
		var first_count: int=LAND.build_chunk(first,rect,6102026,_base_height)
		var first_signature := _signature(first)
		var held_resources := _resources(first)
		first.free() # Um chunk liberado não pode invalidar os recursos imutáveis.
		var second_count: int=LAND.build_chunk(second,rect,6102026,_base_height)
		var second_resources := _resources(second)
		if first_count>0: populated+=1
		if first_count!=int(baseline[cell].count) or second_count!=first_count or first_signature!=baseline[cell].signature or _signature(second)!=first_signature: mismatches+=1
		if held_resources.size()!=second_resources.size(): unshared+=1
		else:
			for i in held_resources.size():
				if held_resources[i]!=second_resources[i]: unshared+=1
		second.free()
	_check(populated>0 and mismatches==0,"Prewarmed/recreated chunks exactly preserve meshes, transforms, metadata and collision geometry")
	_check(unshared==0,"Mesh and Shape3D resources survive release and are shared on return")
	var reused: Dictionary=LAND.cache_diagnostics(_base_height)
	_check(int(reused.geometry_builds)==int(prepared.geometry_builds),"First visit and return do not regenerate vertex arrays or shapes")
	_check(int(reused.cached_cells)<=LAND.MAX_CACHED_CELLS and int(reused.provider_count)<=2,"Resource residency stays bounded")
	var provider_a := HeightProvider.new()
	provider_a.elevation=3.0
	var provider_b := HeightProvider.new()
	provider_b.elevation=7.0
	var a := Node3D.new()
	var b := Node3D.new()
	var test_rect := Rect2(-96,-672,96,96)
	LAND.build_chunk(a,test_rect,6102026,provider_a.height)
	LAND.build_chunk(b,test_rect,6102026,provider_b.height)
	_check(is_finite(_minimum_ground_y(a)) and is_finite(_minimum_ground_y(b)) and _minimum_ground_y(a)>=2.999 and _minimum_ground_y(b)>=6.999,"Different height providers never receive another provider's terrain")
	var bounded: Dictionary=LAND.cache_diagnostics(provider_b.height)
	_check(int(bounded.provider_count)<=2,"A third provider evicts an old resource cache")
	a.free(); b.free(); provider_a.free(); provider_b.free()
	var released: Dictionary=LAND.cache_diagnostics(_base_height)
	_check(int(released.provider_count)==0,"Freed providers are removed through weak references")
	var custom := Node3D.new()
	var callback := func(_point: Vector2) -> float: return 5.0
	LAND.build_chunk(custom,test_rect,6102026,callback)
	_check(is_finite(_minimum_ground_y(custom)) and _minimum_ground_y(custom)>=4.999,"Custom callbacks retain their exact uncached generation path")
	custom.free()
	Engine.remove_meta("desert_landform_cache_benchmark_disabled")
	for failure in failures: push_error(failure)
	print("DESERT_LANDFORM_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"candidate_cells":cells.size(),"populated_cells":populated,"prepared":prepared,"reused":reused}))
	quit(0 if failures.is_empty() else 1)

func _signature(parent: Node3D) -> String:
	var lines := PackedStringArray()
	_signature_node(parent,Transform3D.IDENTITY,lines)
	lines.sort()
	return "\n".join(lines)

func _signature_node(node: Node,parent_transform: Transform3D,lines: PackedStringArray) -> void:
	var transform := parent_transform
	if node is Node3D: transform=parent_transform*node.transform
	if node is MeshInstance3D:
		var arrays: Array=node.mesh.surface_get_arrays(0)
		lines.append("mesh:%s:%s:%s:%s:%s:%s:%s"%[node.name,transform,hash(arrays[Mesh.ARRAY_VERTEX]),hash(arrays[Mesh.ARRAY_NORMAL]),hash(arrays[Mesh.ARRAY_COLOR]),node.cast_shadow,node.get_meta("desert_expansion_ground",false)])
	elif node is CollisionObject3D:
		lines.append("body:%s:%s:%s:%s:%s"%[node.name,transform,node.collision_layer,node.collision_mask,node.get_meta("vehicle_surface","")])
	elif node is CollisionShape3D:
		var shape: Shape3D=node.shape
		if shape is ConcavePolygonShape3D: lines.append("concave:%s:%s"%[transform,hash(shape.get_faces())])
		elif shape is ConvexPolygonShape3D: lines.append("convex:%s:%s"%[transform,hash(shape.points)])
	if node.has_meta("desert_landform_id"): lines.append("landmark:%s:%s:%s"%[node.get_meta("desert_landform_id"),transform,node.get_meta("footprint_radius")])
	for child in node.get_children(): _signature_node(child,transform,lines)

func _resources(parent: Node3D) -> Array[Resource]:
	var result: Array[Resource]=[]
	for node in parent.find_children("*","Node",true,false):
		if node is MeshInstance3D: result.append(node.mesh)
		elif node is CollisionShape3D: result.append(node.shape)
	return result

func _minimum_ground_y(parent: Node3D) -> float:
	var minimum := INF
	for node in parent.find_children("*","MeshInstance3D",true,false):
		if not node.get_meta("desert_expansion_ground",false): continue
		var arrays: Array=node.mesh.surface_get_arrays(0)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]: minimum=minf(minimum,vertex.y)
	return minimum
