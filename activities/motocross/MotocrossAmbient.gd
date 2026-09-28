extends RefCounted
## Nearby practice riders only: no entry fee, awards, race gates or save state.
## The controller calls update(delta), appends rows to surface effects and calls
## clear() before a paid race, rental or mounted-player sequence is created.
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const MAX_RIDERS := 3
const ENTER_DISTANCE := 150.0
const EXIT_DISTANCE := 180.0
const CHECK_INTERVAL := 0.5
const STEER_INTERVAL := 0.08
var rows: Array = []
var _controller: WeakRef
var _course: WeakRef
var _clock := CHECK_INTERVAL
var _next_rider := 0
var _steer_clock := STEER_INTERVAL

func configure(controller: Node) -> void:
	clear()
	_controller = weakref(controller) if is_instance_valid(controller) else null
	_clock = CHECK_INTERVAL

func update(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	var controller: Node = _controller.get_ref() if _controller != null else null
	if not is_instance_valid(controller) or not controller.is_inside_tree():
		clear()
		return
	var session: Variant = controller.session
	if session == null or not session.ready_for_play or controller.active or controller.mounted:
		clear()
		return
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty() or session.is_transition_blocked():
		clear()
		return
	var world: Node3D = session.world
	if not is_instance_valid(world) or not is_instance_valid(world.player):
		clear()
		return
	# A streamed-out course must not leave bikes simulating over missing terrain.
	var loaded_course: Node3D = _course.get_ref() if _course != null else null
	if not rows.is_empty() and (not is_instance_valid(loaded_course) or loaded_course.is_queued_for_deletion() or not loaded_course.is_inside_tree()):
		clear()
	for row in rows:
		if not is_instance_valid(row.bike): continue
		row.bike.race_enabled = not session.modal
		row.bike.set_physics_process(not session.modal)
	if session.modal: return
	_clock += delta
	if _clock >= CHECK_INTERVAL:
		var elapsed := minf(_clock, 1.0)
		_clock = 0.0
		loaded_course = _find_course(controller, world)
		if not is_instance_valid(loaded_course):
			clear()
			return
		var center := Vector3(loaded_course.BOUNDS.get_center().x, 0.0, loaded_course.BOUNDS.get_center().y)
		var player_position: Vector3 = world.player.global_position
		var distance := Vector2(player_position.x - center.x, player_position.z - center.z).length()
		var radius := ENTER_DISTANCE if rows.is_empty() else EXIT_DISTANCE
		if distance > radius:
			clear()
			return
		rows = rows.filter(func(row: Dictionary): return is_instance_valid(row.bike) and not row.bike.is_queued_for_deletion())
		for row in rows: _recover_if_needed(controller, row, elapsed)
		# Spread procedural-model setup over three checks instead of constructing
		# all three riders in a single first-visit frame.
		if rows.size() < MAX_RIDERS and distance <= ENTER_DISTANCE:
			_spawn_one(controller, world)
	_steer_clock += delta
	if _steer_clock < STEER_INTERVAL: return
	_steer_clock = fmod(_steer_clock,STEER_INTERVAL)
	# Physics stays at the engine rate. Background riders only need a fresh
	# look-ahead steering decision at 12.5 Hz; their last input is held between.
	for row in rows:
		if not is_instance_valid(row.bike): continue
		row.bike.wetness = controller.wetness
		controller._drive_ai(row,STEER_INTERVAL)

func clear() -> void:
	for row in rows:
		var bike: Variant = row.get("bike")
		if not is_instance_valid(bike): continue
		bike.set_physics_process(false)
		bike.collision_layer = 0
		bike.collision_mask = 0
		if is_instance_valid(bike.rider):
			bike.rider.collision_layer = 0
			bike.rider.collision_mask = 0
		bike.hide()
		if not bike.is_queued_for_deletion(): bike.queue_free()
	rows.clear()
	_course = null
	_next_rider = 0

func _find_course(controller: Node, world: Node3D) -> Node3D:
	var previous: Node3D = _course.get_ref() if _course != null else null
	if is_instance_valid(previous) and previous.is_inside_tree() and not previous.is_queued_for_deletion(): return previous
	for candidate in controller.get_tree().get_nodes_in_group("motocross_course"):
		if candidate is Node3D and world.is_ancestor_of(candidate) and not candidate.is_queued_for_deletion():
			_course = weakref(candidate)
			return candidate
	return null

func _spawn_one(controller: Node, world: Node3D) -> void:
	var index := _next_rider % MAX_RIDERS
	_next_rider += 1
	var bike := BIKE.new()
	bike.name = "AmbientMotocross%d" % index
	bike.rider_name = ["Faísca", "Nina", "Lobo"][index]
	bike.paint_color = [Color("c8542b"), Color("428aaa"), Color("d1b545")][index]
	bike.rider_color = bike.paint_color.lightened(0.23)
	bike.max_speed = [14.0, 15.5, 14.7][index]
	bike.wetness = controller.wetness
	bike.race_enabled = true
	bike.set_meta("motocross_ambient", true)
	world.add_child(bike)
	var distance: float = controller.track.length * [0.10, 0.43, 0.72][index]
	var lane: float = [-0.75, 0.75, 0.0][index]
	bike.reset_to(controller.track.pose(distance, lane))
	rows.append({"bike": bike, "lane": lane, "pace": [13.0, 14.6, 13.8][index], "safe_distance": distance, "outside": 0.0, "stalled": 0.0, "recovering": 0.0, "respawns": 0})

func _recover_if_needed(controller: Node, row: Dictionary, delta: float) -> void:
	var bike: CharacterBody3D = row.bike
	var nearest: Dictionary = controller.track.nearest(bike.global_position)
	var outside := float(nearest.lateral) > float(controller.track.HALF_WIDTH) + 2.0 or bike.global_position.y < float(nearest.point.y) - 3.0
	row.outside = float(row.outside) + delta if outside else 0.0
	row.stalled = float(row.stalled) + delta if absf(bike.speed) < 0.35 and bike.crash_state == "riding" else 0.0
	row.recovering = float(row.recovering) + delta if bike.crash_state != "riding" else 0.0
	if not outside and bike.is_on_floor() and bike.crash_state == "riding" and absf(bike.speed) > 0.8:
		row.safe_distance = float(nearest.distance)
	if float(row.outside) <= 1.0 and float(row.stalled) <= 6.0 and float(row.recovering) <= 18.0: return
	var distance := float(row.safe_distance)
	if float(row.stalled) > 6.0: distance += 3.0
	bike.reset_to(controller.track.pose(distance, float(row.lane)))
	row.outside = 0.0
	row.stalled = 0.0
	row.recovering = 0.0
	row.respawns += 1
	# Keep the same visible fall/stand/remount lifecycle as racing opponents.
	bike.crash(0.2)
