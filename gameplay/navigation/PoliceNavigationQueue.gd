extends Node
## Provisional CPU budget, not a measured performance guarantee. Contact,
## combat and physical movement continue independently of these queued searches.
const JOB := preload("res://gameplay/navigation/PolicePathJob.gd")
const EXPANSIONS_PER_FRAME := 32
const EXPANSIONS_PER_TURN := 4
const BUDGET_USEC := 1500
const GOAL_REFRESH_DISTANCE := 3.0
const TELEPORT_DISTANCE := 40.0
var gameplay: Node3D
var _jobs: Dictionary = {}
var _order: Array[int] = []
var _last_frame := -1

func _ready() -> void:
	set_physics_process(false)

func request(actor: CharacterBody3D, goal: Vector3) -> Dictionary:
	if not _active() or not is_instance_valid(actor) or not actor.is_inside_tree() or actor.get("dead") == true:
		return {"ready": false}
	var id := actor.get_instance_id()
	var context := _context(actor)
	var entry: Dictionary = _jobs.get(id, {})
	# Ordinary movement must not continually erase completed expansions. Only a
	# context change or an actual discontinuity restarts an in-flight request.
	if not entry.is_empty() and (entry.context != context or entry.last_goal.distance_to(goal) > TELEPORT_DISTANCE or entry.last_position.distance_to(actor.global_position) > TELEPORT_DISTANCE):
		cancel(actor)
		entry = {}
	if entry.is_empty():
		var job := JOB.new()
		job.configure(gameplay, actor.global_position, goal)
		entry = {"actor": weakref(actor), "context": context, "goal": goal, "last_goal": goal, "last_position": actor.global_position, "job": job}
		_jobs[id] = entry
		if not job.done:
			_order.append(id)
			set_physics_process(true)
	entry.last_goal = goal
	entry.last_position = actor.global_position
	if entry.job.done:
		var result := {"ready": true, "path": entry.job.path, "refresh": entry.goal.distance_to(goal) > GOAL_REFRESH_DISTANCE}
		_jobs.erase(id)
		_order.erase(id)
		if _jobs.is_empty(): set_physics_process(false)
		return result
	return {"ready": false}

func cancel(actor: Node) -> void:
	if not is_instance_valid(actor): return
	var id := actor.get_instance_id()
	_jobs.erase(id)
	_order.erase(id)
	if _jobs.is_empty(): set_physics_process(false)

func _active() -> bool:
	return is_instance_valid(gameplay) and gameplay.is_inside_tree() and gameplay.get("enabled") == true and float(gameplay.get("health")) > 0.0

func _context(actor: Node) -> Array:
	var state: Variant = gameplay.get("state")
	return [gameplay.get_meta("police_navigation_epoch", 0), str(state.get("region_id")) if state != null else "", str(state.get("place_id")) if state != null else "", actor.get_meta("police_place_id", ""), actor.get("_navigation_generation")]

func _valid(entry: Dictionary) -> bool:
	var actor: Variant = entry.actor.get_ref()
	return is_instance_valid(actor) and actor.is_inside_tree() and actor.is_physics_processing() and not actor.is_queued_for_deletion() and actor.get("dead") != true and actor.get("controller") == gameplay and actor.get("_navigation_waiting") == true and entry.context == _context(actor)

func _physics_process(_delta: float) -> void:
	if not _active():
		_jobs.clear()
		_order.clear()
		set_physics_process(false)
		return
	# A slow rendered frame may contain several physics ticks. Do not multiply
	# the search budget during catch-up, which would reinforce the original stall.
	var frame := Engine.get_process_frames()
	if frame == _last_frame: return
	_last_frame = frame
	for id in _jobs.keys():
		if not _valid(_jobs[id]):
			_jobs.erase(id)
			_order.erase(id)
	var remaining := EXPANSIONS_PER_FRAME
	var deadline := Time.get_ticks_usec() + BUDGET_USEC
	while not _order.is_empty() and remaining > 0 and Time.get_ticks_usec() < deadline:
		var id: int = _order.pop_front()
		var entry: Dictionary = _jobs[id]
		var count: int = entry.job.advance(mini(EXPANSIONS_PER_TURN, remaining), deadline)
		remaining -= count
		if not entry.job.done: _order.append(id)
		if count == 0 and not entry.job.done: break
	if _jobs.is_empty(): set_physics_process(false)
