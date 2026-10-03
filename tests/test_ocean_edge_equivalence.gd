extends SceneTree
## Exact geometry signatures across before/after, plus shore, seam and lifecycle contracts.
## Construction timings are isolated CPU cost, never gameplay FPS.
const OCEAN := preload("res://world/regions/HarborOcean.gd")
const PORT := preload("res://world/regions/OriginalSouthPort.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok: failures.append(what); push_error("OCEAN_EDGES " + what)

func signature(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		var surfaces: Array = []
		for index in mesh.get_surface_count():
			var digest := HashingContext.new()
			digest.start(HashingContext.HASH_SHA256)
			digest.update(var_to_bytes(mesh.surface_get_arrays(index)))
			surfaces.append(digest.finish().hex_encode())
		var shader_path := ""
		if node.material_override is ShaderMaterial:
			shader_path = node.material_override.shader.resource_path
		result.append({"name":str(node.name),"transform":str(node.transform),"surfaces":surfaces,"shadow":node.cast_shadow,"shader":shader_path})
	for child in node.get_children(): result.append_array(signature(child))
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists(&"CSharpScript"):
		push_error("Requires rendered Godot .NET")
		quit(2)
		return
	await process_frame
	await process_frame
	var ocean := OCEAN.new()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	var extra: Array[PackedVector2Array] = []
	for polygon in PORT.extra_surfaces():
		var metric := PackedVector2Array()
		for point in polygon: metric.append(point / 16.0)
		extra.append(metric)
	var cases: Array[Rect2] = []
	for cell in [Vector2i(3,3),Vector2i(4,3),Vector2i(0,0),Vector2i(-1,0),Vector2i(1,-1),Vector2i(6,-5),Vector2i(7,-5),Vector2i(8,-5),Vector2i(3,0),Vector2i(3,1),Vector2i(-2,-2),Vector2i(10,10)]:
		cases.append(Rect2(Vector2(cell)*64.0,Vector2(64,64)))
	# Boundary/degenerate edges and reconfiguration must not retain stale candidates.
	var synthetic: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-24,0),Vector2(-24,64)]),PackedVector2Array([Vector2(88,0),Vector2(88,64)]),PackedVector2Array([Vector2(0,88),Vector2(64,88)]),PackedVector2Array([Vector2(20,20),Vector2(20,20)]),PackedVector2Array([Vector2(1000,1000),Vector2(1001,1000),Vector2(1001,1001)])]
	for pass_index in 3:
		if pass_index == 1: ocean.configure([[0,0,160,160]],synthetic)
		else: ocean.configure(source.harbor_land,extra)
		for rect in cases:
			var holder := Node3D.new()
			root.add_child(holder)
			var began := Time.get_ticks_usec()
			var surface := ocean.build_chunk(holder,rect)
			var elapsed := Time.get_ticks_usec()-began
			await process_frame
			await RenderingServer.frame_post_draw
			var arrays: Array = surface.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			check(vertices.size()==289,"bounded vertices")
			check(surface.material_override==ocean.material,"shared configured material")
			check(surface.find_children("*","CollisionObject3D",true,false).is_empty(),"water does not add collision")
			for index in vertices.size():
				var vertex := vertices[index]
				var distance := ocean.shore_distance(Vector2(vertex.x,vertex.z))
				# Mesh colors are stored as normalized RGBA8; use one byte tolerance.
				check(absf(colors[index].r-distance/OCEAN.DEPTH_RANGE)<=1.0/255.0+0.000001,"exact shore query determines color")
				check(absf(vertex.y-OCEAN.surface_y(Vector2(vertex.x,vertex.z),distance))<0.000001,"bridge/water height preserved")
			rows.append({"pass":pass_index,"rect":str(rect),"build_usec":elapsed,"geometry":signature(holder)})
			holder.free()
			await process_frame
	# The measured production chunk workload is repeated finitely in each variant.
	var timings: Array[int] = []
	for cycle in 12:
		var holder := Node3D.new()
		root.add_child(holder)
		var began := Time.get_ticks_usec()
		ocean.build_chunk(holder,Rect2(192,192,64,64))
		timings.append(Time.get_ticks_usec()-began)
		await process_frame
		await RenderingServer.frame_post_draw
		holder.free()
		await process_frame
	var report := {"checks":checks,"failures":failures,"rows":rows,"production_chunk_usec":timings,"scope":"Rendered geometry equivalence and isolated construction CPU cost; not gameplay FPS"}
	FileAccess.open("user://ocean-edge-equivalence.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OCEAN_EDGES ",JSON.stringify({"checks":checks,"failures":failures,"production_chunk_usec":timings}))
	quit(0 if failures.is_empty() else 1)
