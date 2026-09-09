extends Node
## One world, one Player, one camera. Regions are prepared ahead of travel;
## their simulation/rendering sleeps outside the active neighbourhood.
const MOUNTAIN_SCENE := "res://district/mountain_pass/MountainPass.tscn"
const MOUNTAIN_OFFSET := Vector2(4300, -4960)
const SEAM_X := 7300.0
var mountain: Node2D
var building := false
var ready_for_crossing := false
var current_region := "harbor"
var _elapsed := 0.0
var _sleeping_traffic: Dictionary = {}
var _mountain_layers: Array[CanvasLayer] = []
var handoff_max_displacement := 0.0

func _ready() -> void:
	add_to_group("continuous_world")
	ResourceLoader.load_threaded_request(MOUNTAIN_SCENE)

func ensure_mountain() -> void:
	if building or ready_for_crossing: return
	building = true
	while ResourceLoader.load_threaded_get_status(MOUNTAIN_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var resource := ResourceLoader.load_threaded_get(MOUNTAIN_SCENE) as PackedScene
	if resource == null:
		building = false
		push_error("Could not prepare Mountain Pass")
		return
	mountain = resource.instantiate()
	mountain.name = "MountainRegion"
	mountain.position = MOUNTAIN_OFFSET
	mountain.streamed_region = true
	mountain.region_selected = false
	mountain.connect_to_harbor = false
	mountain.spawn_player_on_ready = false
	mountain.spawn_suv_on_ready = false
	mountain.player_instance = get_tree().get_first_node_in_group("player")
	get_parent().add_child(mountain)
	while not mountain.region_ready:
		await get_tree().process_frame
	for node in mountain.find_children("*", "CanvasLayer", true, false):
		_mountain_layers.append(node)
	ready_for_crossing = true
	for lane in get_tree().get_nodes_in_group("unified_traffic_lane"):
		var road_id := String(lane.get_meta("traffic_road_id", ""))
		if road_id.ends_with("mountain_bridge_outbound"): lane.set_meta("continuous_border_end", true)
		if road_id.ends_with("mountain_bridge_inbound"): lane.set_meta("continuous_border_start", true)
	building = false
	_update_region()
	get_node("/root/RegionTravel").finish_arrival(get_parent())

func exterior_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null: return Vector2.ZERO
	var car: Node2D = get_node("/root/RegionTravel").controlled_car()
	if car != null and not player.has_meta("police_exterior_position"): return car.global_position
	return player.get_meta("police_exterior_position", player.global_position)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.2: return
	_elapsed = 0.0
	var point := exterior_position()
	var pending: Dictionary = get_node("/root/RegionTravel").pending_world
	if not ready_for_crossing and not building and (point.y < -1000 or pending.get("region", "") == "mountain"):
		ensure_mountain()
	if not ready_for_crossing: return
	_update_region()
	_budget_traffic(point)
	_transfer_bridge_traffic()

func _update_region() -> void:
	var point := exterior_position()
	var player: Node2D = mountain.player_instance
	var selected: bool = point.x >= SEAM_X and point.y < -2000 or bool(player.get_meta("mountain_interior", false))
	current_region = "mountain" if selected else "harbor"
	var nearby: bool = selected or point.distance_to(Vector2(SEAM_X, -4560)) < 3200
	mountain.visible = nearby
	mountain.process_mode = Node.PROCESS_MODE_INHERIT if nearby else Node.PROCESS_MODE_DISABLED
	mountain.region_selected = selected
	mountain.cold_controller.set_process(selected)
	mountain.cold_hud.visible = selected
	if not selected: mountain.storm_manager.set_sheltered(true)
	mountain.parallax.visible = selected
	for layer in _mountain_layers: layer.visible = selected
	var expedition := mountain.get_node("MountainExpedition")
	expedition.set_process(selected)
	expedition.set_process_unhandled_key_input(selected)
	get_parent().weather.set_interior_mode(selected or bool(player.get_meta("harbor_interior", false)))
	if not selected:
		var camera := get_viewport().get_camera_2d()
		if camera and camera.has_meta("mountain_zoom"): camera.remove_meta("mountain_zoom")

func _budget_traffic(point: Vector2) -> void:
	# Keep parked/driven cars and live pursuit state. Distant ambient followers
	# stop simulation, retaining their instances and damage rather than respawning.
	for car in get_tree().get_nodes_in_group("modern_traffic"):
		if not is_instance_valid(car): continue
		var distant: bool = car.global_position.distance_to(point) > 3400 and car.get("is_driven_by_player") != true
		if distant and not _sleeping_traffic.has(car) and (car.is_processing() or car.is_physics_processing()):
			_sleeping_traffic[car] = {"physics":car.is_physics_processing(),"idle":car.is_processing()}
			car.set_physics_process(false)
			car.set_process(false)
		elif not distant and _sleeping_traffic.has(car):
			car.set_physics_process(_sleeping_traffic[car].physics)
			car.set_process(_sleeping_traffic[car].idle)
			_sleeping_traffic.erase(car)
	for car in _sleeping_traffic.keys():
		if not is_instance_valid(car): _sleeping_traffic.erase(car)

func _transfer_bridge_traffic() -> void:
	var traffic := mountain.get_node("MountainTraffic")
	for car in get_tree().get_nodes_in_group("modern_traffic"):
		if car.get("is_driven_by_player") == true: continue
		var follower := car.get_parent() as PathFollow2D
		if follower == null: continue
		var lane := follower.get_parent() as Path2D
		if lane == null: continue
		var road_id := String(lane.get_meta("traffic_road_id", ""))
		if road_id.ends_with("mountain_bridge_outbound") and follower.progress > lane.curve.get_baked_length() - 8:
			_handoff(follower, traffic.lane)
		elif lane == traffic.lane and car.global_position.x < SEAM_X + 10 and car.global_position.y < -4560:
			for target in get_tree().get_nodes_in_group("unified_traffic_lane"):
				if String(target.get_meta("traffic_road_id", "")).ends_with("mountain_bridge_inbound"):
					_handoff(follower, target)
					break

func _handoff(follower: PathFollow2D, target: Path2D) -> void:
	var point := follower.global_position
	follower.reparent(target, false)
	follower.loop = bool(target.get_meta("traffic_lane_loop", false))
	follower.progress = target.curve.get_closest_offset(target.to_local(point))
	handoff_max_displacement = maxf(handoff_max_displacement,point.distance_to(follower.global_position))
	for car in follower.get_children():
		if car is Node2D:
			car.position = Vector2.ZERO
			car.rotation = 0.0
			car.set_meta("traffic_lane_id", target.get_meta("traffic_lane_id", target.name))
			car.set_meta("traffic_road_id", target.get_meta("traffic_road_id", ""))

func get_streaming_stats() -> Dictionary:
	return {"ready": ready_for_crossing, "region": current_region, "resident_regions": 2 if ready_for_crossing else 1,
		"sleeping_traffic": _sleeping_traffic.size(), "memory_bytes": OS.get_static_memory_usage()}

func _exit_tree() -> void:
	_sleeping_traffic.clear()
