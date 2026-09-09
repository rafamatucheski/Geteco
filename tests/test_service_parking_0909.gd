extends SceneTree

var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(90).timeout.connect(func(): print("PARKING TIMEOUT"); quit(2))
	change_scene_to_file("res://district/harbor_preview/HarborPreview.tscn")
	for i in 8: await physics_frame
	var director = get_first_node_in_group("emergency_depot_director")
	var audit: Dictionary = director.get_harbor_depot_audit()
	check(audit.ambulance.spawn.x > 2040, "Ambulance starts beside clinic, away from main door")
	check(audit.coroner.spawn.distance_to(audit.ambulance.spawn) > 100, "Medical bays do not overlap")
	for service in ["police", "ambulance", "coroner"]:
		check(audit[service].spawn_clear, service + " bay is physically clear")
	var target := CharacterBody2D.new()
	current_scene.add_child(target)
	target.global_position = Vector2(2200, 900)
	var unit = director.request_dispatch("ambulance", target, false)
	check(unit != null, "Ambulance dispatched from parking")
	if unit == null: quit(1); return
	var start: Vector2 = unit.global_position
	var gate: Vector2 = unit.get_meta("depot_road_gate")
	var deadline := Time.get_ticks_msec() + 20000
	var court := Rect2(1785, 1765, 205, 120)
	var crossed_court := false
	while bool(unit.get_meta("depot_departure_pending")) and Time.get_ticks_msec() < deadline:
		await physics_frame
		crossed_court = crossed_court or court.grow(50).has_point(unit.global_position)
	check(not bool(unit.get_meta("depot_departure_pending")), "Ambulance physically reaches street gate")
	check(unit.global_position.distance_to(start) > 50, "Ambulance actually drives out of bay")
	check(not crossed_court, "Departure does not cross basketball court")
	unit.is_returning_to_base = true
	deadline = Time.get_ticks_msec() + 25000
	while unit.visible and Time.get_ticks_msec() < deadline:
		await physics_frame
	check(not unit.visible, "Ambulance returns through driveway and releases pool assignment")
	target.global_position = Vector2(1800, 2200)
	var police = director.request_dispatch("police", target, false)
	check(police != null, "Police dispatched from parking bay")
	if police != null:
		start = police.global_position
		deadline = Time.get_ticks_msec() + 20000
		while bool(police.get_meta("depot_departure_pending")) and Time.get_ticks_msec() < deadline:
			await physics_frame
		check(not bool(police.get_meta("depot_departure_pending")), "Police physically reaches street from bay")
		check(police.global_position.distance_to(start) > 50, "Police drives out rather than spawning on street")
		root.get_node("EmergencyPool").return_vehicle(police)
	if DisplayServer.get_name() != "headless":
		var camera := root.get_camera_2d()
		camera.global_position = Vector2(2030, 1550)
		camera.zoom = Vector2.ONE * 1.5
		camera.reset_smoothing()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/medical-parking-0909.png")
	print("SERVICE PARKING failures=", failures)
	quit(0 if failures.is_empty() else 1)
