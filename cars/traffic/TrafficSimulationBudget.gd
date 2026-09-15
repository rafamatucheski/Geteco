extends RefCounted
## Keep a committed crossing and its immediate blockers alive off camera.

static func active_conflict_actors(tree: SceneTree, activity_area := Rect2()) -> Dictionary:
	var active := {}
	var pending: Array[Node2D] = []
	var emergency := preload("res://cars/traffic/TrafficEmergencyYield.gd")
	var units := emergency.responders(tree)
	if not units.is_empty():
		for group in ["vehicle", "authored_sidewalk_pedestrian"]:
			for actor in tree.get_nodes_in_group(group):
				if not actor is Node2D: continue
				for unit in units:
					if actor.global_position.distance_squared_to(unit.global_position) < emergency.ACTIVE_RADIUS * emergency.ACTIVE_RADIUS:
						pending.append(actor)
						break
	for controller in tree.get_nodes_in_group("junction_traffic_controller"):
		if controller.has_method("get_reserved_vehicles"):
			pending.append_array(controller.get_reserved_vehicles())
		if controller.has_method("get_waiting_traffic_actors"):
			for actor in controller.get_waiting_traffic_actors():
				# A distant waiting queue is not a committed crossing. Otherwise
				# reservations renew forever and wake traffic across the whole map.
				if activity_area == Rect2() or activity_area.has_point(actor.global_position):
					pending.append(actor)
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
			if blocker is Node2D and (blocker.is_in_group("vehicle") or blocker.is_in_group("authored_sidewalk_pedestrian")):
				pending.append(blocker)
	return active
