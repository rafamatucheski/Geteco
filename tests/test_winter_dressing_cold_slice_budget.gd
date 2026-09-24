extends SceneTree

const MODEL_PATH := "res://world/mountain_pass/transit/MountainWinterDressing3D.gd"
const SIXTY_FPS_BUDGET_USEC := 16667

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func _measure(callable: Callable) -> int:
	var started := Time.get_ticks_usec()
	callable.call()
	return Time.get_ticks_usec() - started

func _entry(kind: String, point: Vector2, angle: float = 0.0) -> Dictionary:
	return {"kind": kind, "point": point, "scale": 1.0, "angle": angle}

func _run() -> void:
	Engine.max_fps = 0
	# Keep engine/test harness initialization out of the cold model attribution.
	for index in 5:
		await process_frame

	var load_started := Time.get_ticks_usec()
	var model_script: GDScript = load(MODEL_PATH)
	var script_load_usec := Time.get_ticks_usec() - load_started
	var model: Variant = model_script.new()
	root.add_child(model as Node)
	var resources_usec := _measure(model._ensure_resources)
	var append_usec: Dictionary = {}
	var entries := [
		_entry("pine", Vector2.ZERO),
		_entry("pine", Vector2(80, 0), 0.4),
		_entry("rock", Vector2(160, 0), 0.8),
		_entry("log", Vector2(240, 0), 1.2),
		_entry("branches", Vector2(320, 0), 1.6),
	]
	for index in entries.size():
		var kind := String(entries[index].kind)
		var key := "%s_%d" % [kind, index]
		append_usec[key] = _measure(func(): model._append_feature(entries[index], index))
	var allocation_usec := _measure(model._allocate_group_batches)

	var largest_label := "script_load"
	var largest_usec := script_load_usec
	if resources_usec > largest_usec:
		largest_label = "resources"
		largest_usec = resources_usec
	for label in append_usec:
		if int(append_usec[label]) > largest_usec:
			largest_label = String(label)
			largest_usec = int(append_usec[label])
	if allocation_usec > largest_usec:
		largest_label = "batch_allocation"
		largest_usec = allocation_usec

	_check(script_load_usec < SIXTY_FPS_BUDGET_USEC,
		"cold script plus baked-resource load fits one 60 FPS frame")
	_check(resources_usec < SIXTY_FPS_BUDGET_USEC,
		"cold shared-resource preparation fits one 60 FPS frame")
	for label in append_usec:
		_check(int(append_usec[label]) < SIXTY_FPS_BUDGET_USEC,
			"feature slice %s fits one 60 FPS frame" % label)
	_check(allocation_usec < SIXTY_FPS_BUDGET_USEC,
		"cold MultiMesh batch allocation fits one 60 FPS frame")
	_check(model.features.size() == entries.size(),
		"profiling path preserves every winter feature")
	var snow: StandardMaterial3D = model._materials["snow"]
	_check(snow.albedo_texture != null and snow.normal_texture != null,
		"baked snow keeps procedural albedo and normal textures")
	_check(snow.uv1_triplanar and snow.uv1_world_triplanar,
		"baked snow keeps triplanar projection")
	print("WINTER_DRESSING_COLD_PROFILE script_load_usec=", script_load_usec,
		" resources_usec=", resources_usec,
		" append_usec=", append_usec,
		" batch_allocation_usec=", allocation_usec,
		" largest=", largest_label,
		" largest_usec=", largest_usec,
		" failures=", failures)
	model.queue_free()
	for index in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)
