extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const MANIFEST := preload("res://cars/VehiclePrewarmManifest.gd")
const CATALOG := preload("res://cars/VehicleCatalog.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const MEDIC_BOX_PATH := "res://prototypes/living_cast/models/MedicBoxModel.gd"

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_reset_isolated_cache()
	var future_path := String(CATALOG.get_vehicle_spec("snow_plow_truck").model_class)
	var harbor_paths := MANIFEST.model_paths(&"harbor")
	var initial_jobs := CACHE.region_jobs(&"harbor", self)
	_check(initial_jobs.size() == harbor_paths.size(), "fresh Harbor exposes one job per model")
	for job in initial_jobs:
		_check(String(job.get("producer", "")) == "vehicle_prewarm:harbor", "job producer identifies its region")
		_check(int(job.get("estimated_usec", 0)) > 0, "job exposes an estimated cost")

	var cancelled: Dictionary = await CACHE.prepare_region(self, &"mountain", func() -> bool: return true)
	_check(bool(cancelled.cancelled) and not bool(cancelled.completed), "region prewarm can cancel before doing work")
	_check(not CACHE._prepared.has(future_path), "cancelled mountain request retains no future preparation")

	var started := Time.get_ticks_usec()
	await CACHE.prepare_common_models(self)
	# Compatibility wrapper intentionally returns void; retrieve the regional report.
	var harbor: Dictionary = CACHE.region_telemetry(&"harbor")
	var harbor_usec := Time.get_ticks_usec() - started
	await process_frame
	_check(bool(harbor.get("completed", false)), "Harbor regional prewarm completes")
	_check(int(harbor.get("requested_models", 0)) == harbor_paths.size(), "Harbor report covers its real manifest")
	_check(CACHE.region_jobs(&"harbor", self).is_empty(), "completed Harbor prewarm is idempotent")
	_check(not CACHE._prepared.has(future_path), "future mountain model stays cold until requested")
	_check(not CACHE._models.has(future_path), "future mountain template is not retained by Harbor")
	_check(int(harbor.get("memory_after_bytes", -1)) >= 0, "report exposes process memory after prewarm")
	_check(harbor.has("memory_delta_bytes") and harbor.has("retained_models"), "report exposes approximate retention")

	var hits_before := CACHE.hits
	var misses_before := CACHE.misses
	var cold_before := CACHE.cold_builds
	var instantiated := 0
	var fixture := Node3D.new()
	root.add_child(fixture)
	for path in harbor_paths:
		if not CACHE._models.has(path):
			continue
		var script := load(path) as Script
		if script == null:
			continue
		var model := script.new() as Node3D
		if model == null:
			continue
		fixture.add_child(model)
		instantiated += 1
		model.free()
	_check(CACHE.misses == misses_before, "cacheable Harbor models have zero post-prewarm misses")
	_check(CACHE.cold_builds == cold_before, "cacheable Harbor models have zero post-prewarm cold builds")
	_check(CACHE.hits - hits_before == instantiated, "every cacheable Harbor model restores its prepared template")
	fixture.free()
	_validate_cached_medic_box()

	var models_before_second := CACHE._models.size()
	var captures_before_second := CACHE.captures
	var misses_before_second := CACHE.misses
	var cold_before_second := CACHE.cold_builds
	var second_started := Time.get_ticks_usec()
	await CACHE.prepare_region(self, &"harbor")
	var second_usec := Time.get_ticks_usec() - second_started
	var second := CACHE.region_telemetry(&"harbor")
	if not bool(harbor.get("completed", false)) or not bool(second.get("completed", false)):
		print("VEHICLE_REGIONAL_PREWARM_DEBUG harbor_failed=%s harbor_uncached=%s harbor_operational=%s second_failed=%s second_uncached=%s second_hits=%d/%d" % [
			JSON.stringify(harbor.get("failed_models", [])),
			JSON.stringify(harbor.get("uncached_models", [])),
			JSON.stringify(harbor.get("operational_models_warmed", [])),
			JSON.stringify(second.get("failed_models", [])),
			JSON.stringify(second.get("uncached_models", [])),
			int(second.get("cache_hits", 0)),
			int(second.get("operational_warm_hits", 0)),
		])
	_check(int(second.models_prepared) == 0, "second Harbor call performs no model work")
	_check(int(second.get("cache_misses", -1)) == 0, "second Harbor call opens no cold model job")
	_check((second.get("operational_models_warmed", []) as Array).is_empty(), "second Harbor call repeats no operational presentation warmup")
	_check(
		int(second.cache_hits) + int(second.operational_warm_hits) == harbor_paths.size(),
		"second Harbor call reports cacheable and operational-only paths as distinct warm hits"
	)
	_check(CACHE.region_jobs(&"harbor", self).is_empty(), "second Harbor call leaves no pending regional jobs")
	_check(CACHE._models.size() == models_before_second and CACHE.captures == captures_before_second, "second Harbor call publishes no duplicate cache entry")
	_check(CACHE.misses == misses_before_second and CACHE.cold_builds == cold_before_second, "second Harbor call adds no cold-build telemetry")
	var second_readiness := CACHE.region_cache_readiness(&"harbor", self)
	_check(bool(second_readiness.get("ready", false)), "Harbor remains ready after its idempotent second call")
	_check((second_readiness.get("operational_ready_paths", []) as Array).has("res://prototypes/living_cast/models/RescuePumperModel.gd"), "Harbor readiness retains RescuePumper as operationally warm")

	var mountain: Dictionary = await CACHE.prepare_region(self, &"mountain")
	await process_frame
	_check(bool(mountain.completed), "mountain region can be requested later")
	_check(CACHE._prepared.has(future_path), "mountain request prepares its snow plow")
	_check(CACHE._models.has(future_path), "mountain request retains the prepared snow-plow template")
	var global_telemetry := CACHE.region_telemetry()
	_check(not bool(global_telemetry.eviction_supported), "unsafe eviction remains explicitly disabled")
	_check(global_telemetry.retained_regions.has(&"harbor") and global_telemetry.retained_regions.has(&"mountain"), "retention is attributed by region")
	await process_frame
	await process_frame
	_check(not _has_warmup_view_prefix("VehicleWarmupViewport_harbor_"), "Harbor warmup viewport is released")
	_check(not _has_warmup_view_prefix("VehicleWarmupViewport_mountain_"), "mountain warmup viewport is released")

	print("VEHICLE_REGIONAL_PREWARM harbor_models=%d harbor_ms=%.3f second_ms=%.3f cacheable=%d mountain_new=%d retained=%d memory_delta=%d max_model_ms=%.3f max_model=%s failures=%s" % [
		harbor_paths.size(), harbor_usec / 1000.0, second_usec / 1000.0, instantiated,
		int(mountain.models_prepared), CACHE._models.size(), int(harbor.memory_delta_bytes),
		int(harbor.max_model_usec) / 1000.0, String(harbor.max_model_path), failures,
	])
	quit(0 if failures.is_empty() else 1)

func _reset_isolated_cache() -> void:
	CACHE._models.clear()
	CACHE._prepared.clear()
	CACHE._operationally_warmed_paths.clear()
	CACHE._region_reports.clear()
	CACHE._retained_regions.clear()
	CACHE._deferred_constructor_paths.clear()
	CACHE._regional_capture_suppressed_paths.clear()
	CACHE._prewarm_complete = false
	CACHE._last_prewarm_report.clear()
	CACHE.hits = 0
	CACHE.misses = 0
	CACHE.captures = 0
	CACHE.cold_builds = 0
	CACHE.cold_build_usec = 0
	CACHE.regional_misses = 0
	CACHE.regional_cold_builds = 0
	CACHE.regional_cold_build_usec = 0

func _validate_cached_medic_box() -> void:
	_check(CACHE._models.has(MEDIC_BOX_PATH) and CACHE._prepared.has(MEDIC_BOX_PATH), "MedicBox publishes a complete Harbor cache template")
	var script := load(MEDIC_BOX_PATH) as Script
	var first := script.new() as Node3D
	var second := script.new() as Node3D
	root.add_child(first)
	root.add_child(second)
	var first_left := first.get_node_or_null("RearDoorLeft") as Node3D
	var first_right := first.get_node_or_null("RearDoorRight") as Node3D
	_check(first_left != null and first_right != null, "cached MedicBox restores both rear-door hinges")
	var left_door_meshes: Array[Node] = first_left.find_children("*", "MeshInstance3D", true, false) if first_left != null else []
	var right_door_meshes: Array[Node] = first_right.find_children("*", "MeshInstance3D", true, false) if first_right != null else []
	_check(left_door_meshes.size() >= 3 and right_door_meshes.size() >= 3, "cached MedicBox preserves panel, window and handle geometry on both doors")
	first.call("set_rear_doors", true, true)
	_check(first_left != null and first_left.rotation.y > 1.8, "cached MedicBox opens its left rear door")
	_check(first_right != null and first_right.rotation.y < -1.8, "cached MedicBox opens its right rear door")
	first.call("set_rear_doors", false, true)
	_check(first_left != null and first_right != null and is_zero_approx(first_left.rotation.y) and is_zero_approx(first_right.rotation.y), "cached MedicBox closes both rear doors")
	var first_paint := first.get("paint") as StandardMaterial3D
	var second_paint := second.get("paint") as StandardMaterial3D
	_check(first_paint != null and second_paint != null and first_paint != second_paint, "cached MedicBox keeps independent paint materials")
	var door_uses_instance_paint := false
	for node in left_door_meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and mesh_instance.material_override == first_paint:
			door_uses_instance_paint = true
	_check(door_uses_instance_paint, "cached MedicBox rebinds rear-door paint to the live instance")
	if first_paint != null and second_paint != null:
		var second_color := second_paint.albedo_color
		first_paint.albedo_color = Color.MAGENTA
		_check(second_paint.albedo_color == second_color, "repainting one cached MedicBox cannot recolor another")
	var wheel_rig := WHEEL_RIG.new()
	_check(wheel_rig.mount(first) and wheel_rig.pivots.size() == 4, "cached MedicBox remounts all four wheels")
	first.call("apply_impact", Vector3(0.7, 0.8, -2.2), Vector3(-1.0, 0.0, 0.0), 9.0)
	_check(int(first.get("impact_count")) == 1, "cached MedicBox retains damage behavior")
	first.call("repair")
	_check(int(first.get("impact_count")) == 0, "cached MedicBox retains repair behavior")
	var unsafe_references := CACHE._unsafe_operational_node_reference_properties(first)
	_check(unsafe_references.is_empty(), "MedicBox restored state contains no unsafe operational Node references")
	first.free()
	second.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _has_warmup_view_prefix(prefix: String) -> bool:
	for child in root.get_children():
		if String(child.name).begins_with(prefix):
			return true
	return false
