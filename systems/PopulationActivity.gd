extends RefCounted
## One owner controls ambient simulation. Sleeping retains identity, route and damage.
const AREA := preload("res://cars/traffic/CameraSimulationArea.gd")
const CONFLICTS := preload("res://cars/traffic/TrafficSimulationBudget.gd")
const BLOOD_TRANSFER := preload("res://guns/combat/BloodTransferSystem.gd")
const HYSTERESIS := 240.0
const MAX_TRANSITIONS_PER_UPDATE := 64
const MAX_TRANSITION_USEC := 1500
var sleeping: Dictionary = {}
var _pending_transitions: Dictionary = {}
var stats: Dictionary = {}

func update(reference: CanvasItem, focus: Vector2, cars: Array, walkers: Array) -> void:
	var tree := reference.get_tree()
	var drive_area := AREA.visible_area(reference, focus)
	# Wake ambient walkers shortly before they enter the viewport. Active actors
	# retain the additional hysteresis below, while combat and mission actors are
	# still pinned immediately. Using the shared pedestrian margin avoids
	# simulating a large offscreen ring with no visible population benefit.
	var walk_area := AREA.visible_area(reference, focus, AREA.PEDESTRIAN_MARGIN)
	var conflict_started := Time.get_ticks_usec()
	var conflict_stats := {}
	var conflicts := CONFLICTS.active_conflict_actors(tree, drive_area.grow(HYSTERESIS), conflict_stats)
	var conflict_usec := Time.get_ticks_usec() - conflict_started
	# Timetabled intercity services remain simulation anchors; ordinary urban buses do not.
	var anchors := tree.get_nodes_in_group("regional_coach")
	anchors.append_array(tree.get_nodes_in_group("harbor_terminal_coach"))
	stats = {"active_traffic": 0, "sleeping_traffic": 0, "active_pedestrians": 0, "sleeping_pedestrians": 0}
	stats["conflict_usec"] = conflict_usec
	stats["conflict_index"] = conflict_stats
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
			var in_area := area.has_point(actor.global_position)
			var pinned := _pinned(actor, area)
			var committed := conflicts.has(actor.get_instance_id())
			var active := in_area or pinned or committed
			for anchor in anchors:
				if not is_instance_valid(anchor) or not anchor.can_process(): continue
				var radius: float = AREA.REGIONAL_PEDESTRIAN_RADIUS if pedestrian else AREA.REGIONAL_ACTIVITY_RADIUS
				if actor.global_position.distance_squared_to(anchor.global_position) < radius * radius:
					active = true
			# Actors near the player, committed to a conflict, or explicitly
			# pinned must react in this update. Distant ambient transitions are
			# drained through a finite queue so a population burst cannot spend an
			# unbounded amount of work in one 200 ms budget tick.
			_request_transition(actor, active, in_area or pinned or committed)
			var key := ("active_" if active else "sleeping_") + ("pedestrians" if pedestrian else "traffic")
			stats[key] += 1
	for actor in sleeping.keys():
		if not is_instance_valid(actor): sleeping.erase(actor)
	for actor in _pending_transitions.keys():
		if not is_instance_valid(actor): _pending_transitions.erase(actor)
	_drain_transition_budget()
	stats["pending_transitions"] = _pending_transitions.size()


func _request_transition(actor: Node2D, active: bool, immediate: bool) -> void:
	var currently_active := not sleeping.has(actor)
	if currently_active == active:
		_pending_transitions.erase(actor)
		return
	if immediate:
		_pending_transitions.erase(actor)
		set_active(actor, active)
		return
	_pending_transitions[actor] = active


func _drain_transition_budget() -> void:
	var started_usec := Time.get_ticks_usec()
	var processed := 0
	var pending_keys: Array = _pending_transitions.keys()
	for actor_value in pending_keys:
		if processed >= MAX_TRANSITIONS_PER_UPDATE or (processed > 0 and Time.get_ticks_usec() - started_usec >= MAX_TRANSITION_USEC):
			break
		var actor := actor_value as Node2D
		var desired := bool(_pending_transitions.get(actor, false))
		_pending_transitions.erase(actor)
		if not is_instance_valid(actor):
			continue
		var currently_active := not sleeping.has(actor)
		if currently_active != desired:
			set_active(actor, desired)
		processed += 1
	stats["transitions_applied"] = processed
	stats["transition_usec"] = Time.get_ticks_usec() - started_usec

func _pinned(actor: Node2D, area: Rect2) -> bool:
	# Interior simulation stays around the exterior door; the player travels
	# to a distant room and must never sleep with the ambient pedestrians.
	if actor.is_in_group("player"): return true
	if actor.has_meta("interior_actor_presentation"):
		var presentation: Node = actor.get_meta("interior_actor_presentation")
		# Outdoor shared-depth adapters (for example transit platforms) look like
		# interior adapters but remain part of the streamed city. True interiors
		# keep the conservative pinned behavior by default.
		if not is_instance_valid(presentation) or not presentation.has_method("allows_population_sleep") or not bool(presentation.call("allows_population_sleep")):
			return true
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
		# RenderQuality leaves long-lived dormant caches at their resident AA to
		# avoid allocating every city at once. Consume its event hook before any
		# owner method or saved update mode can submit this actor's SubViewports.
		for view in previous.views:
			_prepare_viewport_residency(view)
		if actor.has_method("restore_presentation_after_sleep"):
			actor.call("restore_presentation_after_sleep")
		for view in previous.views:
			if is_instance_valid(view) and actor.is_visible_in_tree(): view.render_target_update_mode = previous.views[view]
		actor.remove_meta("proximity_sleeping")
		sleeping.erase(actor)
		_notify_external_presentation(actor, true)
		if actor.has_method("queue_presentation"):
			actor.call("queue_presentation")
		actor.reset_physics_interpolation()
		BLOOD_TRANSFER.actor_activity_changed(actor, true)
		return
	if sleeping.has(actor): return
	sleeping[actor] = {"mode": actor.process_mode, "views": {}}

	if actor is CollisionObject2D:
		sleeping[actor].disable_mode = actor.disable_mode
		# Actors outside the simulation area must leave the physics broadphase.
		# Keeping every sleeping body active preserved an obstacle that no active
		# vehicle could reach, while still contributing pairs during catch-up steps.
		# Conflicts and actors near the player never reach this branch; wake restores
		# the authored disable mode before gameplay resumes.
		actor.disable_mode = CollisionObject2D.DISABLE_MODE_REMOVE
	actor.set_meta("proximity_sleeping", true)
	_notify_external_presentation(actor, false)
	BLOOD_TRANSFER.actor_activity_changed(actor, false)
	# Do not overwrite individual callback flags: boarding, death and mission
	# transitions may change them while this subtree is asleep.
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	# SubViewport updates are rendering work, independent of script processing.
	for child in actor.find_children("*", "SubViewport", true, false):
		sleeping[actor].views[child] = child.render_target_update_mode
		child.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if actor.has_method("compact_presentation_for_sleep"):
		actor.call("compact_presentation_for_sleep")


func _prepare_viewport_residency(view: Variant) -> void:
	if not is_instance_valid(view) or not view is SubViewport:
		return
	var hook: Callable = view.get_meta("quality_residency_hook", Callable())
	if hook.is_valid():
		hook.call()

func _notify_external_presentation(actor: Node2D, active: bool) -> void:
	if not actor.has_meta("interior_actor_presentation"): return
	var presentation: Node = actor.get_meta("interior_actor_presentation")
	if is_instance_valid(presentation) and presentation.has_method("set_population_active"):
		presentation.call("set_population_active", active)

func restore_all() -> void:
	_pending_transitions.clear()
	for actor in sleeping.keys():
		if is_instance_valid(actor): set_active(actor, true)
	sleeping.clear()
