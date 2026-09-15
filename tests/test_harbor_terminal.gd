extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 12:
		await process_frame
	var terminal = world.get_node("ArrivalStop")
	var player = world.get_node("Player")
	var mission = world.campaign_controller
	check(terminal.bus != null, "Bus is instantiated on canonical lane")
	if terminal.bus == null:
		quit(1)
		return
	check(terminal.bus.is_3d_vehicle and terminal.bus.visual.visible, "Terminal bus uses the native 3D renderer")
	check(not preload("res://emergency/ModernTrafficFactory.gd")._position_is_clear(self, terminal.bus.global_position), "Terminal berth must be reserved during traffic spawning")
	var initial_hull := PhysicsShapeQueryParameters2D.new()
	initial_hull.shape = terminal.bus.collision.shape
	initial_hull.transform = terminal.bus.collision.global_transform
	initial_hull.collision_mask = 2
	initial_hull.exclude = [terminal.bus.get_rid()]
	check(world.get_world_2d().direct_space_state.intersect_shape(initial_hull).is_empty(), "Traffic must not spawn inside the service bus")
	if OS.get_cmdline_user_args().has("--initial-only"):
		print("HARBOR_TERMINAL_INITIAL failures=%d" % failures.size())
		world.queue_free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	check(not player.visible, "Dante remains inside the bus during CGI")
	mission.skip_cinematic()
	var started := Time.get_ticks_msec()
	while mission.phase != "phone" and Time.get_ticks_msec() - started < 20000:
		await process_frame
	check(mission.phase == "phone", "Physical disembark completes before phone")
	print("TERMINAL_DANTE position=%s phase=%s" % [player.global_position, mission.phase])
	if mission.phase != "phone":
		world.queue_free()
		await process_frame
		quit(1)
		return
	check(player.visible and player.global_position.distance_to(world.get_node("ArrivalSpawn").global_position) < 4, "Dante reaches platform on foot")
	mission.answer_phone()
	for i in 4:
		mission.advance_dialogue()
	var last_road := ""
	var seen: Dictionary = {}
	var previous_bus_position: Vector2 = terminal.bus.global_position
	var overlap_reported := false
	var jump_reported := false
	started = Time.get_ticks_msec()
	while (terminal.visits < 2 or terminal.departures < 2) and Time.get_ticks_msec() - started < 180000:
		await physics_frame
		var bus = terminal.bus
		if bus.global_position.distance_to(previous_bus_position) > 16.1 and not jump_reported:
			check(false, "Bus must not teleport at a lane handoff")
			jump_reported = true
		previous_bus_position = bus.global_position
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = bus.get_node("Collision").shape
		query.transform = bus.get_node("Collision").global_transform
		query.collision_mask = 1
		if not world.get_world_2d().direct_space_state.intersect_shape(query).is_empty() and not overlap_reported:
			check(false, "Bus body overlaps a building/wall during its actual circuit")
			overlap_reported = true
		var lane = bus.get_parent().get_parent()
		var road := String(lane.get_meta("traffic_road_id", "")).get_file()
		if road != last_road:
			last_road = road
			seen[road] = true
			print("TERMINAL_ROUTE road=%s pos=%s state=%s" % [road, bus.global_position, terminal.get_service_status()])
	check(terminal.boarded >= 2, "Two actual passengers board through the stopped door")
	check(terminal.alighted >= 2, "Two passengers alight and walk onto platform")
	check(terminal.departures >= 1, "Bus departs with its passengers")
	check(terminal.visits >= 2, "Bus completes street circuit and returns without teleporting")
	check(terminal.departures >= 2 and terminal.boarded >= 4 and terminal.alighted >= 4, "Returning bus performs a second real passenger exchange")
	for person in terminal.passengers:
		if person.transit_state == "onboard":
			check(person.collision_layer == 0 and not person.visible, "Onboard passengers leave no invisible obstacles on the platform")
	check(seen.has("union_avenue") and seen.has("foundry_avenue") and seen.has("warehouse_way"), "Bus uses the authored four-road circuit")
	check(terminal.passengers.size() == 4, "Repeated service has bounded population")
	print("HARBOR_TERMINAL failures=%d status=%s" % [failures.size(), terminal.get_service_status()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
