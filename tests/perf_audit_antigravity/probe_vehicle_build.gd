extends SceneTree
## GETECO-PERF-01-ANTIGRAVITY: Decomposição do Custo de Construção de Veículos (CLAUDE-PERF-002)
## Mede individualmente com Time.get_ticks_usec():
## 1. load(model_path) - carregamento de script/recurso
## 2. model_res.new() - instanciação da árvore 3D (nós, materiais, malhas)
## 3. wheel_rig.mount() - montagem de rodas/pivôs
## 4. VehicleMeshBatcher.batch_model() - unificação de superfícies
## 5. SubViewport setup - criação de câmera, DirectionalLight3D, WorldEnvironment
## 6. add_child() - entrada na árvore de nós
## 7. Primeiro frame de renderização (Vulkan) - CPU render prep e GPU execution

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requer renderização real")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)

	for i in 10:
		await process_frame

	print("=== DECOMPOSIÇÃO DE CUSTO: CONSTRUÇÃO DE VEHICLE3DRENDER ===")
	
	var catalog = preload("res://cars/VehicleCatalog.gd")
	var archetypes := ["sedan", "coupe", "muscle", "pickup", "delivery_truck", "port_forklift", "motorcycle", "police_cruiser"]

	var results := []

	for arch_id in archetypes:
		var spec := catalog.get_vehicle_spec(arch_id)
		var model_path : String = String(spec.get("model_class", ""))
		if model_path.is_empty():
			continue

		print("\n--- Testando Arquétipo: %s (path: %s) ---" % [arch_id, model_path.get_file()])

		# 1. Carregamento do script/recurso
		var t0 := Time.get_ticks_usec()
		var model_res = load(model_path)
		var t_load := Time.get_ticks_usec() - t0

		# 2. Instanciação do modelo 3D
		t0 = Time.get_ticks_usec()
		var body_model: Node3D = model_res.new() as Node3D
		var t_instantiate := Time.get_ticks_usec() - t0

		var node_count := _count_nodes(body_model)
		var mesh_count := _count_meshes(body_model)

		# 3. Montagem do wheel_rig
		t0 = Time.get_ticks_usec()
		var wheel_rig = preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
		wheel_rig.mount(body_model)
		var t_rig := Time.get_ticks_usec() - t0

		# 4. Batching de malhas
		t0 = Time.get_ticks_usec()
		preload("res://cars/VehicleMeshBatcher.gd").batch_model(body_model)
		var t_batch := Time.get_ticks_usec() - t0

		# 5. Configuração do SubViewport e iluminação
		t0 = Time.get_ticks_usec()
		var body_viewport := SubViewport.new()
		body_viewport.size = Vector2i(192, 192)
		body_viewport.transparent_bg = true
		body_viewport.own_world_3d = true
		body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		
		var view := Camera3D.new()
		view.position = Vector3(0, 8, 4)
		view.look_at(Vector3(0, 0.45, 0))
		view.projection = Camera3D.PROJECTION_ORTHOGONAL
		view.size = 6.0
		body_viewport.add_child(view)

		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = 0.7
		body_viewport.add_child(env)

		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55, -30, 0)
		sun.light_energy = 1.0
		body_viewport.add_child(sun)

		body_viewport.add_child(body_model)
		var t_viewport_setup := Time.get_ticks_usec() - t0

		# 6. Adição à árvore de cena
		t0 = Time.get_ticks_usec()
		root.add_child(body_viewport)
		var t_add_tree := Time.get_ticks_usec() - t0

		RenderingServer.viewport_set_measure_render_time(body_viewport.get_viewport_rid(), true)

		# 7. Primeiro frame de renderização (GPU pipeline / shaders / raster)
		t0 = Time.get_ticks_usec()
		await process_frame
		var t_first_render_frame := Time.get_ticks_usec() - t0
		var vp_render_cpu := RenderingServer.viewport_get_measured_render_time_cpu(body_viewport.get_viewport_rid())
		var vp_render_gpu := RenderingServer.viewport_get_measured_render_time_gpu(body_viewport.get_viewport_rid())

		print("  [1] load(model_path):            %.3f ms" % (t_load / 1000.0))
		print("  [2] model.new() (%d nós, %d meshes): %.3f ms" % [node_count, mesh_count, t_instantiate / 1000.0])
		print("  [3] wheel_rig.mount():          %.3f ms" % (t_rig / 1000.0))
		print("  [4] batch_model():               %.3f ms" % (t_batch / 1000.0))
		print("  [5] SubViewport setup:           %.3f ms" % (t_viewport_setup / 1000.0))
		print("  [6] add_child(body_viewport):    %.3f ms" % (t_add_tree / 1000.0))
		print("  -- SOMA CPU SÍNCRONA CONSTRUÇÃO:  %.3f ms" % ((t_load + t_instantiate + t_rig + t_batch + t_viewport_setup + t_add_tree) / 1000.0))
		print("  [7] 1º frame total:              %.3f ms (Render CPU: %.3f ms | Render GPU: %.3f ms)" % [
			t_first_render_frame / 1000.0, vp_render_cpu, vp_render_gpu
		])

		results.append({
			"archetype": arch_id,
			"load_ms": t_load / 1000.0,
			"instantiate_ms": t_instantiate / 1000.0,
			"nodes": node_count,
			"meshes": mesh_count,
			"rig_ms": t_rig / 1000.0,
			"batch_ms": t_batch / 1000.0,
			"setup_ms": t_viewport_setup / 1000.0,
			"tree_ms": t_add_tree / 1000.0,
			"sync_cpu_ms": (t_load + t_instantiate + t_rig + t_batch + t_viewport_setup + t_add_tree) / 1000.0,
			"first_frame_ms": t_first_render_frame / 1000.0,
			"render_cpu_ms": vp_render_cpu,
			"render_gpu_ms": vp_render_gpu
		})

		body_viewport.queue_free()
		await process_frame

	print("\n=== RESUMO GERAL DE CONSTRUÇÃO ===")
	print("%-16s | %-8s | %-8s | %-8s | %-10s | %-12s | %-10s" % [
		"Arquétipo", "Nós/Mesh", "Instan.", "Batch", "Soma CPU", "1º Frame Tot", "GPU ms"
	])
	for r in results:
		print("%-16s | %3d/%-4d | %6.2f ms | %6.2f ms | %8.2f ms | %10.2f ms | %8.2f ms" % [
			r.archetype, r.nodes, r.meshes, r.instantiate_ms, r.batch_ms, r.sync_cpu_ms, r.first_frame_ms, r.render_gpu_ms
		])

	print("\n=== FIM DO DIAGNÓSTICO DE CONSTRUÇÃO ===")
	quit(0)

func _count_nodes(n: Node) -> int:
	var count := 1
	for c in n.get_children():
		count += _count_nodes(c)
	return count

func _count_meshes(n: Node) -> int:
	var count := 1 if n is MeshInstance3D else 0
	for c in n.get_children():
		count += _count_meshes(c)
	return count
