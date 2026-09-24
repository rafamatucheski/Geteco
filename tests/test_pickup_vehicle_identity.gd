extends SceneTree

const ENGINE_SOUND := preload("res://audio/VehicleEngineSound.gd")
const PICKUPS := [&"atlas_crew_pickup", &"sertao_trail_pickup"]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var sedan := VehicleCatalog.get_vehicle_spec("sedan_classic")
	var signatures: Array[String] = []
	for pickup_id in PICKUPS:
		var spec := VehicleCatalog.get_vehicle_spec(pickup_id)
		_check(String(spec.get("id", "")) == pickup_id, "%s exists in the catalog" % pickup_id)
		_check(String(spec.get("drivetrain", "")) == "4x4", "%s uses a 4x4 drivetrain" % pickup_id)
		_check(float(spec.get("mass", 0.0)) >= 1.80, "%s has pickup-class mass" % pickup_id)
		_check(float(spec.get("durability", 0.0)) >= 190.0, "%s has pickup-class durability" % pickup_id)
		_check(float(spec.get("turn_speed", 99.0)) < float(sedan.turn_speed), "%s turns more deliberately than a sedan" % pickup_id)
		_check(float(spec.get("drift_factor", 99.0)) < float(sedan.drift_factor), "%s has planted utility handling" % pickup_id)
		_check(float(spec.get("acceleration", 9999.0)) <= float(sedan.acceleration), "%s accelerates with utility weight" % pickup_id)
		_check(ENGINE_SOUND.family_for_vehicle(pickup_id) == String(spec.engine_family), "%s uses its authored engine voice" % pickup_id)

		var model_script := load(String(spec.get("model_class", ""))) as Script
		_check(model_script != null, "%s model loads" % pickup_id)
		if model_script == null:
			continue
		var model := model_script.new() as Node3D
		root.add_child(model)
		var signature := String(model.get_meta("silhouette_signature", ""))
		_check(not signature.is_empty() and not signatures.has(signature), "%s has a unique pickup silhouette" % pickup_id)
		signatures.append(signature)
		_check(String(model.get_meta("cabin_kind", "")).contains("open_bed"), "%s has an open pickup bed" % pickup_id)
		var centers := {}
		for child in model.get_children():
			if child.has_meta("wheel_center"):
				centers[child.get_meta("wheel_center")] = true
		_check(centers.size() == 4, "%s has four authored wheel centers" % pickup_id)
		model.queue_free()

	await process_frame
	print("PICKUP_VEHICLE_IDENTITY failures=%d pickups=%d" % [failures.size(), PICKUPS.size()])
	quit(0 if failures.is_empty() else 1)
