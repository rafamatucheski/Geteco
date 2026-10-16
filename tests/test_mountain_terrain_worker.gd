extends SceneTree
## Terreno da serra calculado num WorkerThreadPool (MountainTerrain3D.chunk_data + NativeRegion estágio 0):
## alturas, normais, cores, índices e máscara das trilhas têm de ser exatamente os do cálculo antigo no
## thread principal (height_at com cache), e o trecho montado pelo streaming fatiado tem a mesma malha e a
## mesma colisão do trecho montado de uma vez. Não mede tempo.
const REGION := preload("res://world/regions/NativeRegion.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

## O build_chunk de antes de 16/10, linha a linha: alturas e normais pelo height_at com cache.
func legacy_data(terrain: RefCounted, rect: Rect2) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var steps := int(TERRAIN.CELL/TERRAIN.STEP)
	for z in range(steps+1):
		for x in range(steps+1):
			var point := rect.position+Vector2(x,z)*TERRAIN.STEP
			var h: float = terrain.height_at(point)
			vertices.append(Vector3(point.x,h,point.y))
			normals.append(Vector3(terrain.height_at(point-Vector2.RIGHT)-terrain.height_at(point+Vector2.RIGHT),2.0,terrain.height_at(point-Vector2.DOWN)-terrain.height_at(point+Vector2.DOWN)).normalized())
			var original_y: float = point.y*16.0-preload("res://world/places/PlaceCatalog.gd").MOUNTAIN_OFFSET.y
			var snow := 1.0-smoothstep(-1500.0,-1200.0,original_y)
			var earth := Color("52634a").lerp(Color("72766b"),clampf(h/7.5,0.0,1.0))
			colors.append(earth.lerp(Color("d2d9d9"),snow))
	return {"vertices":vertices,"normals":normals,"colors":colors,"trail":terrain._trail_blend.image_for(rect).get_data()}

func terrain_mesh(chunk: Node) -> MeshInstance3D:
	for node in chunk.find_children("MountainTerrain*","MeshInstance3D",true,false): return node
	return null

func collision_faces(mesh: MeshInstance3D) -> PackedVector3Array:
	for shape in mesh.find_children("*","CollisionShape3D",true,false):
		if shape.shape is ConcavePolygonShape3D: return (shape.shape as ConcavePolygonShape3D).get_faces()
	return PackedVector3Array()

func run() -> void:
	var region = REGION.build_region("mountain", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	var terrain = region.terrain
	var keys: Array[Vector2i] = []
	for x in range(8, 20):
		for z in range(-12, 0):
			var key := Vector2i(x,z)
			if region._mountain_owns_terrain(key) and not region.chunks.has(key): keys.append(key)
			if keys.size() >= 5: break
		if keys.size() >= 5: break
	check(keys.size() >= 5, "Há trechos de terreno da serra para comparar (%d)" % keys.size())
	# 1) Dados: thread principal, trabalhador e o cálculo antigo dão exatamente o mesmo.
	for key in keys:
		var rect := Rect2(Vector2(key)*TERRAIN.CELL, Vector2.ONE*TERRAIN.CELL)
		var main: Dictionary = terrain.chunk_data(rect)
		var worker := {}
		var task := WorkerThreadPool.add_task(Callable(TERRAIN,"prepare_task").bind(terrain,rect,worker))
		WorkerThreadPool.wait_for_task_completion(task)
		var legacy := legacy_data(terrain, rect)
		for field in ["vertices","normals","colors","indices","heights","trail"]:
			check(worker.get(field) == main.get(field), "%s %s igual no trabalhador e no thread principal" % [key, field])
		for field in ["vertices","normals","colors","trail"]:
			check(main.get(field) == legacy.get(field), "%s %s igual ao cálculo antigo (height_at com cache)" % [key, field])
	# 2) Streaming fatiado (trabalhador) contra montagem imediata: mesma malha, mesma colisão, mesmo chão.
	var streamed_key: Vector2i = keys[0]
	var used_worker := false
	region._build_chunk(streamed_key, false)
	for frame in 600:
		if not region._terrain_tasks.is_empty() or region.build_jobs.any(func(job): return job.has("terrain_task") or job.has("waiting_worker")): used_worker = true
		if region.is_streaming_idle(): break
		await process_frame
	check(used_worker, "Streaming da serra calculou o terreno num trabalhador")
	check(region.is_streaming_idle(), "Streaming terminou")
	var streamed := terrain_mesh(region.chunks[streamed_key])
	var holder := Node3D.new()
	root.add_child(holder)
	var reference: MeshInstance3D = terrain.build_chunk(holder, Rect2(Vector2(streamed_key)*TERRAIN.CELL, Vector2.ONE*TERRAIN.CELL))
	check(streamed != null and reference != null, "Trecho fatiado tem MountainTerrain")
	if streamed != null and reference != null:
		var a: Array = streamed.mesh.surface_get_arrays(0)
		var b: Array = reference.mesh.surface_get_arrays(0)
		for index in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
			check(a[index] == b[index], "Malha fatiada igual à imediata (array %d)" % index)
		check(collision_faces(streamed) == collision_faces(reference) and not collision_faces(streamed).is_empty(), "Colisão fatiada igual à imediata")
		check(streamed.material_override.get_shader_parameter("trail_mask").get_image().get_data() == reference.material_override.get_shader_parameter("trail_mask").get_image().get_data(), "Máscara das trilhas igual")
	# Chão pedido já (veículo): estágio 0 síncrono, com ou sem tarefa começada.
	var urgent_key: Vector2i = keys[1]
	region._build_chunk(urgent_key, false)
	region._prefetch_terrain_tasks()
	region._ensure_chunk_surfaces(urgent_key)
	check(terrain_mesh(region.chunks[urgent_key]) != null, "Chão urgente sai no mesmo quadro mesmo com a tarefa no trabalhador")
	var cold_key: Vector2i = keys[2]
	region._ensure_chunk_surfaces(cold_key)
	check(terrain_mesh(region.chunks[cold_key]) != null, "Chão urgente sem tarefa sai no mesmo quadro")
	for frame in 600:
		if region.is_streaming_idle(): break
		await process_frame
	await process_frame
	check(region._terrain_tasks.is_empty(), "Nenhuma tarefa do terreno fica pendurada")
	# 3) Região liberada com tarefa no ar: espera a tarefa (sem vazamento nem acesso a terreno liberado).
	region._build_chunk(keys[3], false)
	region._build_chunk(keys[4], false)
	region._prefetch_terrain_tasks()
	check(not region._terrain_tasks.is_empty(), "Tarefas começam à frente da vez")
	holder.free()
	region.free()
	await process_frame
	check(true, "Região liberada com tarefas no ar sem erro")
	print("MOUNTAIN_TERRAIN_WORKER checks=%d falhas=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
