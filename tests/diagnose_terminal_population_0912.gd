extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1772, 666)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	campaign.set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("SaveManager").clear_pending_save()
	var world: Node2D = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while not world.gameplay_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	for _frame in 12:
		await physics_frame
	var player: Node2D = world.get_node("Player")
	var camera: Camera2D = root.get_camera_2d()
	var terminal: Node2D = world.get_node("ArrivalStop")
	var stream: Node = world.get_node("ContinuousWorld")
	print("STALL_START paused=", paused, " phase=", world.campaign_controller.phase,
		" player=", player.global_position, " focus=", stream.exterior_position(),
		" camera=", camera.get_screen_center_position() if camera else Vector2.INF,
		" area=", preload("res://world/shared/traffic/CameraSimulationArea.gd").visible_area(world, stream.exterior_position(), 80.0),
		" terminal=", terminal.get_service_status())
	var probes: Array[Node2D] = []
	for actor in get_nodes_in_group("authored_sidewalk_pedestrian"):
		if actor is Node2D and (String(actor.name).begins_with("HarborResident_0_") or String(actor.name).begins_with("HarborResident_1_") or String(actor.name).begins_with("MarketStroller_")):
			probes.append(actor)
	var previous := {}
	for actor in probes:
		previous[actor] = actor.global_position
	print_probe(0, probes, previous)
	for frame in 180:
		await physics_frame
		if frame % 60 == 59:
			print("STALL_TICK sim_seconds=", (frame + 1) / 60.0, " terminal=", terminal.get_service_status())
			print_probe((frame + 1) / 60, probes, previous)
	for actor in probes:
		if actor.velocity.is_zero_approx() and actor.global_position.distance_to(actor.walk_target) > 20.0:
			print_blocker(actor)
	print("STALL_END terminal=", terminal.get_service_status(), " population=", stream.population_activity.stats)
	world.queue_free()
	for _frame in 4:
		await process_frame
	quit()

func print_probe(second: int, probes: Array[Node2D], previous: Dictionary) -> void:
	for actor in probes:
		if not is_instance_valid(actor):
			continue
		var navigation = actor.movement_navigation
		print("STALL_ACTOR t=", second, " name=", actor.name, " pos=", actor.global_position,
			" step=", actor.global_position.distance_to(previous[actor]), " velocity=", actor.velocity,
			" target=", actor.walk_target, " distance=", actor.global_position.distance_to(actor.walk_target),
			" locomotion=", actor.locomotion_state, " stuck=", actor.stuck_timer,
			" recovery=", actor.recovery_count, " pause=", actor._destination_pause,
			" companion_wait=", actor._companion_wait, " direct=", navigation.direct_clear,
			" path=", navigation.path.size(), " search=", navigation._search_pending,
			" retry=", navigation.retry, " process=", actor.can_process(),
			" sleeping=", actor.get_meta("proximity_sleeping", false),
			" slides=", actor.get_slide_collision_count())
		previous[actor] = actor.global_position

func print_blocker(actor: Node2D) -> void:
	actor._configure_navigation_corridor()
	var start: Vector2 = actor.global_position
	var goal: Vector2 = actor.walk_target
	print("STALL_BLOCK name=", actor.name,
		" allowed_start=", actor._navigation_point_allowed(start),
		" allowed_mid=", actor._navigation_point_allowed(start.lerp(goal, 0.5)),
		" allowed_goal=", actor._navigation_point_allowed(goal))
	for child in actor.get_children():
		if not child is CollisionShape2D or child.disabled or child.shape == null:
			continue
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.motion = goal - start
		query.collision_mask = actor.collision_mask & 3
		query.exclude = [actor.get_rid()]
		query.margin = actor.safe_margin
		var cast := actor.get_world_2d().direct_space_state.cast_motion(query)
		var hit := actor.get_world_2d().direct_space_state.get_rest_info(query)
		print("STALL_BLOCK shape=", child.name, " cast=", cast,
			" collider=", hit.get("collider"),
			" path=", hit.get("collider").get_path() if is_instance_valid(hit.get("collider")) else NodePath(""),
			" point=", hit.get("point"))
