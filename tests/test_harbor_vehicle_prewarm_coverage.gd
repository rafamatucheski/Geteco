extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const MANIFEST := preload("res://cars/VehiclePrewarmManifest.gd")

# These constructors keep operational Node references or do not consult the
# cache. Fixing them safely requires a binding/rebuild contract in their own
# model/caller, which is deliberately outside this task's write scope.
const EXTERNAL_MODEL_DEPENDENCIES: Array[String] = [
	"res://geodata/transit/RegionalIntercityCoachModel.gd",
	"res://police/PoliceMotorcycleModel.gd",
	"res://prototypes/living_cast/BossMuscleModel.gd",
	"res://prototypes/living_cast/CabrioletModel.gd",
	"res://prototypes/living_cast/models/RescuePumperModel.gd",
	"res://world/harbor/HarborContainerTruckModel.gd",
	"res://world/harbor/HarborTransitBusModel.gd",
	"res://world/harbor/PortBossRoadsterModel.gd",
	"res://world/harbor/PortForkliftModel.gd",
	"res://world/harbor/monaliza/MonalizaModel.gd",
	"res://world/harbor/urban_transit/UrbanBusModel.gd",
	"res://world/harbor/urban_transit/UrbanBusTrailerModel.gd",
]

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture := Node3D.new()
	fixture.name = "VehiclePrewarmCoverageFixture"
	root.add_child(fixture)
	var requested := _expected_model_paths()
	var prewarm_started := Time.get_ticks_usec()
	await CACHE.prepare_common_models(self)
	var prewarm_usec := Time.get_ticks_usec() - prewarm_started
	await process_frame
	await process_frame

	var missing_templates: Array[String] = []
	for path in requested:
		if not CACHE._models.has(path):
			missing_templates.append(path)
	var unexpected_missing := missing_templates.duplicate()
	for path in EXTERNAL_MODEL_DEPENDENCIES:
		unexpected_missing.erase(path)
	_check(unexpected_missing.is_empty(),
		"prewarm has unexpected coverage gaps: %s" % [unexpected_missing])
	_check(not _has_warmup_view_prefix("VehicleWarmupViewport_harbor_"),
		"temporary prewarm viewport must be released")

	var after_prewarm := CACHE.telemetry()
	var hits_before := int(after_prewarm.hits)
	var misses_before := int(after_prewarm.misses)
	var cold_before := int(after_prewarm.cold_builds)
	var cold_usec_before := int(after_prewarm.cold_build_usec)
	var instantiated := 0
	for path in requested:
		if path in EXTERNAL_MODEL_DEPENDENCIES:
			continue
		var script := load(path) as Script
		_check(script != null, "runtime model must load: %s" % path)
		if script == null:
			continue
		var model := script.new() as Node3D
		_check(model != null, "runtime model must instantiate as Node3D: %s" % path)
		if model == null:
			continue
		fixture.add_child(model)
		instantiated += 1
		model.free()

	var after_live_builds := CACHE.telemetry()
	var post_misses := int(after_live_builds.misses) - misses_before
	var post_cold_builds := int(after_live_builds.cold_builds) - cold_before
	var post_cold_usec := int(after_live_builds.cold_build_usec) - cold_usec_before
	var post_hits := int(after_live_builds.hits) - hits_before
	_check(post_misses == 0, "post-prewarm model construction must have zero cache misses")
	_check(post_cold_builds == 0, "post-prewarm model construction must have zero cold builds")
	_check(post_hits == instantiated,
		"every post-prewarm model must restore from cache: hits=%d instantiated=%d" % [post_hits, instantiated])
	_check(int(after_live_builds.post_prewarm_misses) == 0,
		"telemetry must distinguish gameplay misses from prewarm misses")
	_check(int(after_live_builds.post_prewarm_cold_builds) == 0,
		"telemetry must distinguish gameplay cold builds from prewarm cold builds")

	print("HARBOR_VEHICLE_PREWARM requested=%d cached=%d prewarm_ms=%.3f post_hits=%d post_misses=%d post_cold_builds=%d post_cold_usec=%d missing=%s failures=%s" % [
		requested.size(), CACHE._models.size(), prewarm_usec / 1000.0, post_hits,
		post_misses, post_cold_builds, post_cold_usec, missing_templates, failures,
	])
	fixture.free()
	quit(0 if failures.is_empty() else 1)

func _expected_model_paths() -> Array[String]:
	return MANIFEST.model_paths(&"harbor")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _has_warmup_view_prefix(prefix: String) -> bool:
	for child in root.get_children():
		if String(child.name).begins_with(prefix):
			return true
	return false
