extends RefCounted
## Keep a committed crossing and its immediate blockers alive off camera.
const INDEX := preload("res://cars/traffic/TrafficConflictIndex.gd")
## Ordinary traffic only retains the immediate local dependency chain. Three
## leaders cover a compact queue without turning a camera-edge car into a pin
## for an entire authored lane.
const MAX_ORDINARY_LEADER_CHAIN := 3

static func active_conflict_actors(tree: SceneTree, activity_area := Rect2(), diagnostics: Dictionary = {}) -> Dictionary:
	var active := {}
	var pending: Array[Node2D] = []
	var emergency := preload("res://cars/traffic/TrafficEmergencyYield.gd")
	var units := emergency.responders(tree)
	for controller in tree.get_nodes_in_group("junction_traffic_controller"):
		if controller.has_method("get_reserved_vehicles"):
			pending.append_array(controller.get_reserved_vehicles())
		if controller.has_method("get_waiting_traffic_actors"):
			for actor in controller.get_waiting_traffic_actors():
				# A distant waiting queue is not a committed crossing. Otherwise
				# reservations renew forever and wake traffic across the whole map.
				if activity_area == Rect2() or activity_area.has_point(actor.global_position):
					pending.append(actor)
	if pending.is_empty() and units.is_empty() and not activity_area.has_area(): return active
	# One linear snapshot, then local queries. The cost of distant residents is
	# no longer multiplied by the number of reservations/responders.
	var index := INDEX.new()
	index.build(tree, activity_area)
	for unit in units:
		pending.append_array(index.near(unit.global_position, emergency.ACTIVE_RADIUS))
	while not pending.is_empty():
		var actor: Node2D = pending.pop_back()
		if not is_instance_valid(actor) or active.has(actor.get_instance_id()):
			continue
		active[actor.get_instance_id()] = true
		# A sleeping queue ahead of the owner must also be allowed to drain.
		# The visited set terminates cycles without waking unrelated traffic.
		for sensor_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
			var sensor := actor.get_node_or_null(sensor_name) as RayCast2D
			if sensor == null:
				continue
			sensor.force_raycast_update()
			var blocker = sensor.get_collider()
			if blocker is Node2D and (blocker.is_in_group("vehicle") or blocker.is_in_group("authored_sidewalk_pedestrian") or blocker.is_in_group("pedestrian")):
				pending.append(blocker)
			pending.append_array(index.sleeping_blockers(sensor, actor))
	# A normal active car can have its exact PathFollow leader removed from the
	# physics broadphase by population sleep. Follow only that authored lane
	# relationship, with a hard local cap; nearby parallel traffic is unrelated.
	for root in index.active_vehicles(activity_area):
		active[root.get_instance_id()] = true
		var follower: Node2D = root
		for depth in MAX_ORDINARY_LEADER_CHAIN:
			var leader := index.sleeping_lane_leader(follower)
			if leader == null: break
			active[leader.get_instance_id()] = true
			index.stats.ordinary_leaders_woken += 1
			follower = leader
		if index.sleeping_lane_leader(follower) != null:
			index.stats.ordinary_chains_truncated += 1
	diagnostics.merge(index.stats, true)
	return active
