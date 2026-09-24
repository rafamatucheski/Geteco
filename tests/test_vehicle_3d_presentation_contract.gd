extends SceneTree

## Contract: a deferred catalog vehicle may wait for its 3D presentation, but
## it must never expose the legacy 2D atlas/silhouette in the playable view.

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	var budget := root.get_node("PresentationBudget")
	budget.set_process(false)
	var vehicle := (load("res://cars/traffic/TrafficVehicle.tscn") as PackedScene).instantiate()
	vehicle.defer_presentation = true
	vehicle.position = Vector2(100000, 100000)
	root.add_child(vehicle)
	vehicle.apply_archetype("union_sedan", Color("34495e"))

	_check(vehicle.get("_pending_spec") is Dictionary and not vehicle.get("_pending_spec").is_empty(), "deferred vehicle keeps a 3D build request")
	_check(not vehicle.visual.visible, "deferred vehicle does not expose a 2D fallback")
	_check(vehicle.body_viewport == null, "deferred vehicle has no fake 2D-backed presentation")
	var activity := preload("res://systems/PopulationActivity.gd").new()
	activity.set_active(vehicle, false)
	budget._process(0.11)
	_check(not budget.pending.has(vehicle), "sleeping deferred vehicle leaves the presentation queue")
	activity.set_active(vehicle, true)
	_check(budget.pending.has(vehicle), "waking deferred vehicle re-enters the presentation queue")

	vehicle.position = Vector2(100, 100)
	vehicle.ensure_presentation()
	_check(vehicle.is_3d_vehicle, "presentation resolves to a 3D vehicle")
	_check(is_instance_valid(vehicle.body_viewport), "resolved vehicle owns a 3D viewport")
	_check(is_instance_valid(vehicle.body_model), "resolved vehicle owns a 3D model")
	_check(vehicle.visual.visible, "resolved 3D vehicle becomes visible")
	_check(vehicle.visual.texture == vehicle.body_viewport.get_texture(), "visible vehicle uses the 3D viewport texture")
	var full_size: Vector2i = vehicle.body_viewport.size
	vehicle.compact_presentation_for_sleep()
	_check(vehicle.body_viewport.size == Vector2i(64, 64), "sleeping vehicle shrinks its 3D render target")
	vehicle.restore_presentation_after_sleep()
	_check(vehicle.body_viewport.size == Vector2i(64, 64), "waking vehicle defers its 3D target restore")
	vehicle.call("_update_3d_orientation", 0.0)
	_check(vehicle.body_viewport.size == full_size, "visible vehicle restores its 3D render target")

	# The driven car owns the active camera. A collision can leave the smoothed
	# canvas transform one frame behind the physics body; that stale transform
	# must never disable or hide the player's vehicle presentation.
	vehicle.compact_presentation_for_sleep()
	vehicle.restore_presentation_after_sleep()
	vehicle.visual.hide()
	vehicle.is_driven_by_player = true
	vehicle.position = Vector2(100000, 100000)
	vehicle.call("_update_3d_orientation", 0.0)
	_check(vehicle.visual.visible, "driven vehicle repairs a hidden presentation")
	_check(vehicle.body_viewport.size == full_size, "driven vehicle cannot keep a compacted presentation")
	_check(vehicle.body_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED, "stale camera transform cannot cull the driven vehicle")

	# Reproduce the reported frontage: drive east into the EARLY SHIFT solid and
	# verify that collision recovery leaves both motion and presentation valid.
	var early_shift := preload("res://world/harbor/HarborBuilding.gd").new()
	early_shift.name = "ServiceCafe"
	early_shift.position = Vector2(6200, -1370)
	early_shift.footprint = Vector2(200, 220)
	early_shift.building_kind = "corner_shop"
	root.add_child(early_shift)
	vehicle.position = Vector2(6040, -1370)
	vehicle.rotation = 0.0
	vehicle.velocity = Vector2(500, 0)
	for frame in 30:
		await physics_frame
	_check(vehicle.global_position.x < 6100, "driven vehicle stops at the EARLY SHIFT frontage")
	_check(vehicle.global_position.is_finite() and vehicle.velocity.is_finite(), "EARLY SHIFT impact keeps vehicle physics finite")
	_check(vehicle.visual.visible and vehicle.body_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED, "EARLY SHIFT impact keeps the driven vehicle rendered")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var impact_image: Image = vehicle.body_viewport.get_texture().get_image()
		_check(impact_image.get_used_rect().has_area(), "EARLY SHIFT impact leaves visible pixels in the vehicle viewport")
	vehicle.is_driven_by_player = false

	var sport_coupe := (load("res://cars/traffic/TrafficVehicle.tscn") as PackedScene).instantiate()
	sport_coupe.defer_presentation = false
	root.add_child(sport_coupe)
	sport_coupe.apply_archetype("sport_coupe", Color("f1f2f6"))
	_check(sport_coupe.is_3d_vehicle, "sport coupe resolves to its authored 3D body")
	_check(sport_coupe.get_node_or_null("RoofProp") == null, "3D sport coupe does not receive a detached legacy spoiler")

	print("VEHICLE_3D_PRESENTATION failures=", failures)
	activity.restore_all()
	early_shift.queue_free()
	vehicle.queue_free()
	sport_coupe.queue_free()
	budget.set_process(true)
	await process_frame
	quit(0 if failures.is_empty() else 1)
