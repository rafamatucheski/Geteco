extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func run() -> void:
	create_timer(120, true, false, true).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	while not current_scene.gameplay_ready: await process_frame
	var system: Node2D = current_scene.get_node("UrbanTransit")
	while not system.ready_for_service: await process_frame
	var bus: Node2D = system.buses[0]
	check(bus.sections.size() == 1, "production bus creates one trailer")
	bus.set_headlights(true)
	check(bus.sections[0].is_night_or_storm, "headlights propagate to living sections")
	var removed: Node = bus.sections[0]
	removed.queue_free()
	bus.set_headlights(false)
	await process_frame
	await process_frame
	check(not is_instance_valid(removed), "section was actually freed")
	check(bus.sections.is_empty(), "freed section removed from bus references")
	check(bus.is_broken and bus.velocity == Vector2.ZERO, "incomplete bus stops")
	for dark in [true, false, true]:
		system.clock._notify_headlights(dark)
		bus.set_headlights(dark)
		check(bus.is_night_or_storm == dark, "lighting remains safe without a trailer: %s" % dark)
		await process_frame
	bus._joints.queue_redraw()
	var other_bus: Node2D = system.buses[1]
	var follow: Node = other_bus.get_parent()
	var lane: Node = follow.get_parent()
	lane.remove_child(follow)
	lane.add_child(follow)
	await process_frame
	check(other_bus.sections.size() == 1 and is_instance_valid(other_bus.sections[0]), "temporary lane handoff preserves sections")
	current_scene.queue_free()
	await process_frame
	await process_frame
	print("SECTION LIFETIME FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
