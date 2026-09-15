extends RefCounted
## One owner controls ambient simulation. Sleeping retains identity, route and damage.
const AREA := preload("res://world/shared/traffic/CameraSimulationArea.gd")
const CONFLICTS := preload("res://world/shared/traffic/TrafficSimulationBudget.gd")
const BLOOD_TRANSFER := preload("res://guns/combat/BloodTransferSystem.gd")
const HYSTERESIS := 240.0
var sleeping: Dictionary = {}
var stats: Dictionary = {}

func update(reference: CanvasItem, focus: Vector2, cars: Array, walkers: Array) -> void:
	var tree := reference.get_tree()
	var drive_area := AREA.visible_area(reference, focus)
	# Wake ambient walkers shortly before they enter the viewport. Active actors
	# retain the additional hysteresis below, while combat and mission actors are
	# still pinned immediately. Using the shared pedestrian margin avoids
	# simulating a large offscreen ring with no visible population benefit.
	var walk_area := AREA.visible_area(reference, focus, AREA.PEDESTRIAN_MARGIN)
	var conflicts := CONFLICTS.active_conflict_actors(tree, drive_area.grow(HYSTERESIS))
	# Timetabled intercity services remain simulation anchors; ordinary urban buses do not.
	var anchors := tree.get_nodes_in_group("regional_coach")
	anchors.append_array(tree.get_nodes_in_group("harbor_terminal_coach"))
	stats = {"active_traffic": 0, "sleeping_traffic": 0, "active_pedestrians": 0, "sleeping_pedestrians": 0}
	var visited := {}
	for category in 2:
		var actors: Array = cars if category == 0 else walkers
		var pedestrian: bool = category == 1
		for value in actors:
			if not is_instance_valid(value) or not value is Node2D: continue
			var actor: Node2D = value
			if visited.has(actor.get_instance_id()): continue
			visited[actor.get_instance_id()] = true
			var area: Rect2 = walk_area if pedestrian else drive_area
			if not sleeping.has(actor): area = area.grow(HYSTERESIS)
			var active := area.has_point(actor.global_position) or _pinned(actor, area) or conflicts.has(actor.get_instance_id())
			for anchor in anchors:
				if not is_instance_valid(anchor) or not anchor.can_process(): continue
				var radius: float = AREA.REGIONAL_PEDESTRIAN_RADIUS if pedestrian else AREA.REGIONAL_ACTIVITY_RADIUS
				if actor.global_position.distance_squared_to(anchor.global_position) < radius * radius:
					active = true
			set_active(actor, active)
			var key := ("active_" if active else "sleeping_") + ("pedestrians" if pedestrian else "traffic")
			stats[key] += 1
	for actor in sleeping.keys():
		if not is_instance_valid(actor): sleeping.erase(actor)

func _pinned(actor: Node2D, area: Rect2) -> bool:
	# Interior simulation stays around the exterior door; the player travels
	# to a distant room and must never sleep with the ambient pedestrians.
	if actor.is_in_group("player"): return true
	if actor.has_meta("interior_actor_presentation"): return true
	if actor.is_in_group("regional_coach") or actor.is_in_group("harbor_terminal_coach"): return true
	if actor.is_in_group("simulation_keep_alive") or actor.get_meta("simulation_keep_alive", false): return true
	if actor.get("is_driven_by_player") == true or actor.get("is_exploding") == true or actor.get("is_flying") == true: return true
	if actor.get_meta("medical_pending", false): return true
	var target = actor.get("combat_target")
	if is_instance_valid(target) and target is Node2D:
		return target.is_in_group("player") or area.has_point(target.global_position)
	return false

func set_active(actor: Node2D, active: bool) -> void:
	if active:
		if not sleeping.has(actor): return
		var previous: Dictionary = sleeping[actor]
		actor.process_mode = previous.mode
		if actor is CollisionObject2D: actor.disable_mode = previous.disable_mode
		for view in previous.views:
			if is_instance_valid(view) and actor.is_visible_in_tree(): view.render_target_update_mode = previous.views[view]
		actor.remove_meta("proximity_sleeping")
		sleeping.erase(actor)
		actor.reset_physics_interpolation()
		BLOOD_TRANSFER.actor_activity_changed(actor, true)
		return
	if sleeping.has(actor): return
	sleeping[actor] = {"mode": actor.process_mode, "views": {}}
	if actor is CollisionObject2D:
		sleeping[actor].disable_mode = actor.disable_mode
		# Keep a stationary obstacle for approaching vehicles and reservation rays.
		actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.set_meta("proximity_sleeping", true)
	BLOOD_TRANSFER.actor_activity_changed(actor, false)
	# Do not overwrite individual callback flags: boarding, death and mission
	# transitions may change them while this subtree is asleep.
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	# SubViewport updates are rendering work, independent of script processing.
	for child in actor.find_children("*", "SubViewport", true, false):
		sleeping[actor].views[child] = child.render_target_update_mode
		child.render_target_update_mode = SubViewport.UPDATE_DISABLED

func restore_all() -> void:
	for actor in sleeping.keys():
		if is_instance_valid(actor): set_active(actor, true)
	sleeping.clear()
