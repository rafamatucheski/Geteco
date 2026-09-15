extends SceneTree
## GETECO-PERF-02B — custo de construção da apresentação 3D de veículos.
## Uso (renderizado; APPDATA isolado):
##   --script res://tests/perf_audit_claude/probe_vehicle_build_02b.gd -- run=<nome> mode=cold|loaded variant=real|decomp
## mode=cold   processo novo, sem mundo e sem prepare_common_models.
## mode=loaded GameLoading real antes (caches aquecidos como no jogo).
## variant=real   ensure_presentation() do ator real (timer externo único) + 1º desenho.
## variant=decomp réplica da ordem de TrafficVehicle._setup_3d_model com timers
##                sequenciais; subcustos "contido_em_*" são réplicas somente leitura,
##                medidas à parte e NUNCA somadas ao total.

const HARBOR := "res://world/harbor/HarborGame.tscn"
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const DEFAULT_TRAFFIC := ["union_sedan", "courier_van", "route_city", "american_tanker_truck", "police_suv"]
## archetypes=a,b,c substitui a lista padrão (ex.: motos e modelos sem cache).
var TRAFFIC: Array = DEFAULT_TRAFFIC.duplicate()
const EXEMPLARS := 3

var out := {}
var stage: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _us(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().replace("\\", "/").contains("perf_audit_claude"):
		push_error("PROBE requer renderização e user data isolado")
		quit(1)
		return
	var run_name := "probe_02b"
	var mode := "cold"
	var variant := "real"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("run="): run_name = arg.trim_prefix("run=")
		if arg.begins_with("mode="): mode = arg.trim_prefix("mode=")
		if arg.begins_with("variant="): variant = arg.trim_prefix("variant=")
		if arg.begins_with("archetypes="): TRAFFIC = Array(arg.trim_prefix("archetypes=").split(","))
	var dir := ProjectSettings.globalize_path("res://tests/perf_audit_claude/results/%s" % run_name)
	DirAccess.make_dir_recursive_absolute(dir.path_join("saves"))
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", dir.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	root.size = Vector2i(1280, 720)
	seed(15092026)
	out["mode"] = mode
	out["variant"] = variant
	out["archetypes"] = TRAFFIC
	out["engine"] = Engine.get_version_info().string
	out["debug_build"] = OS.is_debug_build()
	out["renderer"] = RenderingServer.get_current_rendering_method()
	out["adapter"] = RenderingServer.get_video_adapter_name()
	var budget := root.get_node("PresentationBudget")
	if mode == "loaded":
		var campaign := root.get_node("CampaignState")
		campaign.reset_campaign()
		for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
			campaign.set_campaign_flag(StringName(flag), true)
		var loader := root.get_node("GameLoading")
		loader.begin(HARBOR)
		await loader.finished
		for i in 30: await process_frame
		stage = Node2D.new()
		stage.name = "Probe02BStage"
		current_scene.add_child(stage)
		# Área visível do jogador: o sprite do veículo precisa de fato ser desenhado.
		var camera := root.get_viewport().get_camera_2d()
		stage.global_position = camera.get_screen_center_position() if camera else Vector2.ZERO
	else:
		var world := Node2D.new()
		root.add_child(world)
		current_scene = world
		var camera := Camera2D.new()
		world.add_child(camera)
		camera.make_current()
		stage = Node2D.new()
		world.add_child(stage)
		for i in 10: await process_frame
	# O orçamento de produção não pode construir nada durante o probe.
	budget.set_process(false)
	out["pending_ignored"] = budget.pending.size()
	out["caches_before"] = _cache_sizes()
	if variant == "real":
		out["traffic"] = await _real_traffic(budget)
		out["emergency"] = await _real_emergency()
	else:
		out["traffic"] = await _decomposition()
	out["caches_after"] = _cache_sizes()
	var file := FileAccess.open(dir.path_join("probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	print("PROBE_02B ", JSON.stringify(out))
	budget.set_process(true)
	quit(0)

# Os contadores abaixo só existem no patch 02B; na árvore "antes" eles faltam.
# Ler por Script.get() mantém o mesmo probe válido nos dois lados do A/B.
func _counter(script: Script, name: String) -> Variant:
	var value = script.get(name)
	return value if value != null else "indisponível"

func _entries(script: Script, name: String) -> Variant:
	var value = script.get(name)
	return (value as Dictionary).size() if value is Dictionary else "indisponível"

func _cache_sizes() -> Dictionary:
	var batcher: Script = BATCHER
	var clearance: Script = CLEARANCE
	return {"geometry_models": CACHE._models.size(), "geometry_prepared": CACHE._prepared.size(), "geometry_hits": CACHE.hits,
		"clearance_meshes": CLEARANCE._cache.size(), "batcher_meshes": BATCHER._mesh_cache.size(), "batcher_hits": BATCHER.cache_hits,
		"static_memory_mib": OS.get_static_memory_usage() / 1048576.0,
		"batcher_format_hits": _counter(batcher, "format_cache_hits"), "batcher_format_entries": _entries(batcher, "_format_cache"),
		"batcher_primitive_format_hits": _counter(batcher, "primitive_format_hits"),
		"batcher_mesh_evictions": _counter(batcher, "mesh_cache_evictions"), "batcher_mesh_misses": _counter(batcher, "mesh_cache_misses"),
		"batcher_invalidations": _counter(batcher, "cache_invalidations"), "clearance_key_invalidations": _counter(clearance, "content_key_invalidations"),
		"clearance_key_hits": _counter(clearance, "content_key_hits"), "clearance_key_entries": _entries(clearance, "_content_keys")}

func _draw_cost(view: SubViewport) -> Dictionary:
	if view == null: return {}
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	var t0 := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var first := _us(t0)
	await process_frame
	await RenderingServer.frame_post_draw
	return {"first_frame_ms": first, "viewport_render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()),
		"viewport_render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()), "update_mode_after": view.render_target_update_mode}

func _real_traffic(budget: Node) -> Array:
	var rows: Array = []
	var serial := 0
	for archetype in TRAFFIC:
		for exemplar in EXEMPLARS:
			serial += 1
			var before := _cache_sizes()
			var t0 := Time.get_ticks_usec()
			var car = FACTORY.spawn_parked_vehicle(stage, "Probe%d" % serial, stage.global_position + Vector2(serial % 3 * 60 - 60, 0), 0.0, archetype, 0, Color(0.2, 0.4, 0.8))
			var spawn_ms := _us(t0)
			budget.pending.erase(car)
			var pending_spec_before: bool = not car._pending_spec.is_empty()
			t0 = Time.get_ticks_usec()
			car.ensure_presentation()
			var ensure_ms := _us(t0)
			var after := _cache_sizes()
			var row := {"archetype": archetype, "exemplar": exemplar + 1, "model": String(car.body_model.get_script().resource_path).get_file() if is_instance_valid(car.body_model) else "",
				"spawn_parked_ms": spawn_ms, "was_deferred": pending_spec_before, "ensure_presentation_ms": ensure_ms,
				"nodes_in_viewport": _count(car.body_viewport), "geometry_cache_hit": after.geometry_hits > before.geometry_hits,
				"clearance_meshes_added": after.clearance_meshes - before.clearance_meshes, "batcher_hits_delta": after.batcher_hits - before.batcher_hits,
				"static_memory_delta_mib": after.static_memory_mib - before.static_memory_mib}
			row["draw"] = await _draw_cost(car.body_viewport)
			rows.append(row)
			car.queue_free()
			await process_frame
	return rows

func _real_emergency() -> Array:
	var rows: Array = []
	var scene := load("res://emergency/EmergencyVehicle.tscn") as PackedScene
	for spec in [[0, "police_suv"], [1, ""], [0, "police_suv"], [1, ""]]:
		var unit = scene.instantiate()
		unit.type = spec[0]
		if spec[0] == 0: unit.police_archetype = spec[1]
		unit.visible = false # _ready só constrói o modelo quando visível.
		stage.add_child(unit)
		unit.global_position = stage.global_position + Vector2(0, 80)
		var before := _cache_sizes()
		var t0 := Time.get_ticks_usec()
		unit.ensure_presentation()
		var ms := _us(t0)
		unit.visible = true
		var after := _cache_sizes()
		var row := {"service": ["police", "ambulance"][spec[0]], "ensure_presentation_ms": ms, "nodes_in_viewport": _count(unit.body_viewport),
			"geometry_cache_hit": after.geometry_hits > before.geometry_hits, "static_memory_delta_mib": after.static_memory_mib - before.static_memory_mib}
		row["draw"] = await _draw_cost(unit.body_viewport)
		rows.append(row)
		unit.queue_free()
		await process_frame
	return rows

func _decomposition() -> Array:
	var rows: Array = []
	for archetype in TRAFFIC:
		var spec: Dictionary = preload("res://cars/VehicleCatalog.gd").get_vehicle_spec(archetype)
		for exemplar in EXEMPLARS:
			var row := {"archetype": archetype, "exemplar": exemplar + 1}
			var t0 := Time.get_ticks_usec()
			var model_res = load(String(spec.model_class))
			row["load_ms"] = _us(t0)
			t0 = Time.get_ticks_usec()
			var view := SubViewport.new()
			view.size = Vector2i(192, 192)
			view.transparent_bg = true
			view.own_world_3d = true
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			stage.add_child(view)
			row["viewport_create_add_ms"] = _us(t0)
			var hits := CACHE.hits
			t0 = Time.get_ticks_usec()
			var model: Node3D = model_res.new()
			row["model_new_ms"] = _us(t0)
			row["geometry_cache_hit"] = CACHE.hits > hits
			t0 = Time.get_ticks_usec()
			view.add_child(model)
			row["model_enter_tree_ready_ms"] = _us(t0)
			row["nodes_before_mount"] = _count(model)
			# Réplica somente leitura da chave de VehicleWheelClearance.carve.
			t0 = Time.get_ticks_usec()
			row["carve_parts_keyed"] = _replica_carve_keys(model)
			row["contido_em_mount__carve_key_replica_ms"] = _us(t0)
			t0 = Time.get_ticks_usec()
			var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
			rig.mount(model)
			row["wheel_rig_mount_ms"] = _us(t0)
			# Réplica somente leitura de _surface_format do batcher.
			t0 = Time.get_ticks_usec()
			var formatted := 0
			for node in _meshes(model):
				if node.mesh != null and node.mesh.get_surface_count() == 1:
					BATCHER._surface_format(node.mesh)
					formatted += 1
			row["contido_em_batch__surface_format_replica_ms"] = _us(t0)
			row["surface_format_calls"] = formatted
			t0 = Time.get_ticks_usec()
			var removed: int = BATCHER.batch_model(model)
			row["batch_model_ms"] = _us(t0)
			row["batched_removed"] = removed
			t0 = Time.get_ticks_usec()
			model.rotation.y = -PI * 0.5
			var camera := Camera3D.new()
			view.add_child(camera)
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			var environment := WorldEnvironment.new()
			environment.environment = Environment.new()
			view.add_child(environment)
			view.add_child(DirectionalLight3D.new())
			row["camera_environment_light_ms"] = _us(t0)
			row["total_sequential_ms"] = row.load_ms + row.viewport_create_add_ms + row.model_new_ms + row.model_enter_tree_ready_ms + row.wheel_rig_mount_ms + row.batch_model_ms + row.camera_environment_light_ms
			row["nodes_after"] = _count(model)
			rows.append(row)
			view.queue_free()
			await process_frame
	return rows

func _replica_carve_keys(model: Node3D) -> int:
	# Mesmos centros/poços calculados por VehicleWheelRig.mount (cópia).
	var centers: Array[Vector3] = []
	for node in model.get_children():
		if node.has_meta("wheel_center") and not centers.has(node.get_meta("wheel_center")): centers.append(node.get_meta("wheel_center"))
	if centers.is_empty() or model.get_meta("vehicle_kind", "car") == "motorcycle": return 0
	var min_z := INF
	var max_z := -INF
	for center in centers:
		min_z = minf(min_z, center.z)
		max_z = maxf(max_z, center.z)
	var front_limit := (min_z + max_z) * 0.5
	var rear := bool(model.get_meta("rear_steering", false))
	var wells: Array[Dictionary] = []
	for center in centers:
		var radius := 0.355
		var half_width := 0.0
		for part in model.get_children():
			if part is MeshInstance3D and part.get_meta("wheel_center", Vector3.INF) == center:
				radius = float(part.get_meta("wheel_radius", radius))
				var bounds: AABB = part.transform * part.mesh.get_aabb()
				half_width = maxf(half_width, maxf(absf(bounds.position.x - center.x), absf(bounds.end.x - center.x)))
		var angle := 0.58 if (center.z < front_limit) != rear else 0.0
		var reach := radius * sin(angle) + half_width * cos(angle)
		wells.append({"center": center, "radius": sqrt(radius * radius + half_width * half_width) + 0.035, "inner": maxf(0.05, absf(center.x) - reach - 0.035)})
	var keyed := 0
	for part in model.get_children():
		if not part is MeshInstance3D or part.has_meta("wheel_center") or part.mesh == null: continue
		var relevant: Array[Dictionary] = []
		var bounds: AABB = part.transform * part.mesh.get_aabb()
		for well in wells:
			var center: Vector3 = well.center
			var radius: float = well.radius / cos(PI / 16)
			if bounds.end.y < center.y - radius or bounds.position.y > center.y + radius: continue
			if bounds.end.z < center.z - radius or bounds.position.z > center.z + radius: continue
			if center.x > 0 and bounds.end.x < well.inner: continue
			if center.x < 0 and bounds.position.x > -well.inner: continue
			relevant.append(well)
		if relevant.is_empty(): continue
		var key := str(part.transform, relevant)
		for surface in part.mesh.get_surface_count():
			key += str(hash(part.mesh.surface_get_arrays(surface)))
		keyed += 1
	return keyed

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D: result.append(child)
		result.append_array(_meshes(child))
	return result

func _count(node: Node) -> int:
	if node == null: return 0
	var total := 1
	for child in node.get_children(): total += _count(child)
	return total
