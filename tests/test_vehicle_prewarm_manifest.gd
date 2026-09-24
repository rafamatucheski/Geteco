extends SceneTree

const MANIFEST := preload("res://cars/VehiclePrewarmManifest.gd")
const CATALOG := preload("res://cars/VehicleCatalog.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var harbor_ids := MANIFEST.vehicle_ids(&"harbor")
	var mountain_ids := MANIFEST.vehicle_ids(&"mountain")
	var harbor_paths := MANIFEST.model_paths(&"harbor")
	var mountain_paths := MANIFEST.model_paths(&"mountain")

	for id in _constant_array("res://world/harbor/HarborLife.gd", "CAR_TYPES"):
		_check(harbor_ids.has(String(id)), "Harbor CAR_TYPES missing from manifest: %s" % id)
	for id in _constant_array("res://world/harbor/HarborLife.gd", "MOTORCYCLE_TYPES"):
		_check(harbor_ids.has(String(id)), "Harbor MOTORCYCLE_TYPES missing from manifest: %s" % id)
	for id in MANIFEST.HARBOR_EXPLICIT_IDS + MANIFEST.EMERGENCY_IDS:
		_check(harbor_ids.has(String(id)), "authored Harbor vehicle missing from aggregate: %s" % id)
	for path in MANIFEST.HARBOR_RUNTIME_MODELS:
		_check(harbor_paths.has(path), "runtime-only Harbor model missing: %s" % path)

	for id in _constant_array("res://world/mountain_pass/MountainTraffic.gd", "FLEET"):
		_check(mountain_ids.has(String(id)), "MountainTraffic FLEET missing: %s" % id)
	for parking in _constant_array("res://world/mountain_pass/MountainVillageLayout.gd", "PARKING"):
		if parking is Array and parking.size() > 1:
			_check(mountain_ids.has(String(parking[1])), "mountain parking vehicle missing: %s" % parking[1])

	for id in harbor_ids + mountain_ids:
		_check(CATALOG.VEHICLES.has(id), "manifest references unknown catalog id: %s" % id)
	var future_path := String(CATALOG.get_vehicle_spec("snow_plow_truck").model_class)
	_check(mountain_paths.has(future_path), "mountain must own snow plow presentation")
	_check(not harbor_paths.has(future_path), "Harbor startup must not prewarm mountain-only snow plow")
	_check(harbor_paths.size() < _all_known_paths().size(), "Harbor startup must be smaller than global fleet coverage")

	print("VEHICLE_PREWARM_MANIFEST harbor_ids=%d harbor_paths=%d mountain_ids=%d mountain_paths=%d all_paths=%d failures=%s" % [
		harbor_ids.size(), harbor_paths.size(), mountain_ids.size(), mountain_paths.size(),
		_all_known_paths().size(), failures,
	])
	quit(0 if failures.is_empty() else 1)

func _all_known_paths() -> Array[String]:
	var paths: Array[String] = []
	for spec in CATALOG.get_all_specs():
		var path := String(spec.get("model_class", ""))
		if not path.is_empty() and ResourceLoader.exists(path) and not paths.has(path):
			paths.append(path)
	for path in MANIFEST.HARBOR_RUNTIME_MODELS:
		if ResourceLoader.exists(path) and not paths.has(path):
			paths.append(path)
	return paths

func _constant_array(path: String, name: String) -> Array:
	var script := load(path) as Script
	return script.get_script_constant_map().get(name, []) as Array if script != null else []

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
