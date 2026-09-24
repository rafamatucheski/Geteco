class_name VehicleRegionalPrewarmCoordinator
extends Node

## Starts region-owned vehicle presentation work from the actor's continuous
## physical approach. This node never changes actor transforms or velocities.

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const SCHEDULER := preload("res://systems/RuntimeWorkScheduler.gd")

const DEFAULT_SEAM_POSITION := Vector2(7300.0, -4560.0)
const SAMPLE_INTERVAL_SECONDS := 0.1
const DIRECT_TRIGGER_DISTANCE := 3600.0
const LOOKAHEAD_SECONDS := 8.0
const MIN_APPROACH_SPEED := 35.0
const CANCEL_DISTANCE := 4600.0
const MIN_AWAY_SPEED := 20.0
const NEAR_PRIORITY_DISTANCE := 1400.0
const VISIBLE_PRIORITY_DISTANCE := 3000.0
const RETRY_BACKOFF_BASE_MSEC := 1000
const RETRY_BACKOFF_MAX_MSEC := 8000

var seam_position := DEFAULT_SEAM_POSITION
var target_region: StringName = &"mountain"
var motion_source_override: Node2D

var _sample_elapsed := 0.0
var _run_active := false
var _cancel_requested := false
var _cancel_reason := ""
var _session_error := ""
var _session: Dictionary = {}
var _last_position := Vector2.ZERO
var _last_velocity := Vector2.ZERO
var _last_distance := INF
var _last_approach_speed := 0.0
var _last_effective_distance := INF
var _state := "idle"
var _failure_signature := ""
var _failure_repeat_count := 0
var _retry_not_before_msec := 0
var _scheduler_wait_started_frame := -1
var _telemetry := {
	"samples": 0,
	"trigger_count": 0,
	"cancel_count": 0,
	"completed_count": 0,
	"jobs_executed": 0,
	"resource_requests": 0,
	"resource_ready": 0,
	"resource_wait_frames": 0,
	"resource_failures": 0,
	"heavy_reservations": 0,
	"stage_steps_executed": 0,
	"over_budget_stages": 0,
	"max_jobs_in_frame": 0,
	"last_job_frame": -1,
	"jobs_in_last_frame": 0,
	"crossed_before_ready": 0,
	"last_trigger": {},
	"last_cancel": {},
	"last_error": {},
	"last_stage": {},
	"failure_signature": "",
	"failure_repeat_count": 0,
	"retry_backoff_msec": 0,
	"retry_not_before_msec": 0,
	"cancelled_pending_scheduler": false,
	"cancel_scheduler_wait_frames": 0,
	"last_report": {},
}

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_sample_elapsed += delta
	if _sample_elapsed < SAMPLE_INTERVAL_SECONDS:
		return
	_sample_elapsed = fmod(_sample_elapsed, SAMPLE_INTERVAL_SECONDS)
	var actor := _motion_actor()
	if actor == null:
		return
	observe_motion(actor.global_position, _actor_velocity(actor))

## Public for deterministic route tests and future world-stream coordinators.
## Supplying observations does not move any actor; production samples the live
## player-controlled body through `_process`.
func observe_motion(position: Vector2, velocity: Vector2) -> void:
	if not position.is_finite() or not velocity.is_finite():
		return
	_last_position = position
	_last_velocity = velocity
	_last_distance = position.distance_to(seam_position)
	var toward := seam_position - position
	_last_approach_speed = velocity.dot(toward.normalized()) if toward.length_squared() > 0.001 else velocity.length()
	_last_effective_distance = _last_distance - maxf(0.0, _last_approach_speed) * LOOKAHEAD_SECONDS
	_telemetry.samples = int(_telemetry.samples) + 1

	if _has_crossed(position) and not is_region_ready():
		_telemetry.crossed_before_ready = int(_telemetry.crossed_before_ready) + 1
	if _run_active:
		if _last_distance > CANCEL_DISTANCE and _last_approach_speed < -MIN_AWAY_SPEED:
			request_cancel("physical_return")
		return
	if is_region_ready():
		_state = "completed"
		return
	if _should_trigger():
		_start_region_prewarm()

func request_cancel(reason := "requested") -> void:
	if not _run_active or _cancel_requested:
		return
	_cancel_requested = true
	_cancel_reason = reason
	_state = "cancelling"
	if _scheduler_wait_started_frame >= 0:
		# RuntimeWorkScheduler owns the pending request; cancellation removes it and
		# wakes reserve() with an empty ticket on the following frame.
		_telemetry.cancelled_pending_scheduler = bool(SCHEDULER.cancel_pending(self, _producer_name()))
	_telemetry.cancel_count = int(_telemetry.cancel_count) + 1
	_telemetry.last_cancel = {
		"reason": reason,
		"position": _last_position,
		"distance": _last_distance,
		"approach_speed": _last_approach_speed,
		"frame": Engine.get_process_frames(),
	}

func is_region_ready() -> bool:
	if get_tree() == null:
		return false
	return bool(CACHE.region_cache_readiness(target_region, get_tree()).get("ready", false))

func telemetry_snapshot() -> Dictionary:
	var result := _telemetry.duplicate(true)
	result["state"] = _state
	result["region"] = String(target_region)
	result["seam_position"] = seam_position
	result["position"] = _last_position
	result["velocity"] = _last_velocity
	result["distance"] = _last_distance
	result["approach_speed"] = _last_approach_speed
	result["effective_distance"] = _last_effective_distance
	result["trigger_distance"] = DIRECT_TRIGGER_DISTANCE
	result["lookahead_seconds"] = LOOKAHEAD_SECONDS
	result["cancel_distance"] = CANCEL_DISTANCE
	result["running"] = _run_active
	result["cancel_requested"] = _cancel_requested
	result["retry_remaining_msec"] = maxi(0, _retry_not_before_msec - Time.get_ticks_msec())
	result["readiness"] = CACHE.region_cache_readiness(target_region, get_tree()) if get_tree() != null else {}
	return result

func _should_trigger() -> bool:
	if Time.get_ticks_msec() < _retry_not_before_msec:
		return false
	if _last_distance <= DIRECT_TRIGGER_DISTANCE:
		return true
	return _last_approach_speed >= MIN_APPROACH_SPEED and _last_effective_distance <= DIRECT_TRIGGER_DISTANCE

func _start_region_prewarm() -> void:
	if _run_active:
		return
	_run_active = true
	_cancel_requested = false
	_cancel_reason = ""
	_session_error = ""
	_scheduler_wait_started_frame = -1
	_telemetry.cancelled_pending_scheduler = false
	_state = "starting"
	_telemetry.trigger_count = int(_telemetry.trigger_count) + 1
	_telemetry.last_trigger = {
		"position": _last_position,
		"velocity": _last_velocity,
		"distance": _last_distance,
		"approach_speed": _last_approach_speed,
		"effective_distance": _last_effective_distance,
		"frame": Engine.get_process_frames(),
	}
	_run_region_session.call_deferred()

func _run_region_session() -> void:
	if not _run_active or get_tree() == null:
		_run_active = false
		return
	_session = CACHE.begin_region_session(get_tree(), target_region)
	if not bool(_session.get("valid", false)):
		_state = "failed"
		_telemetry.last_report = _session.get("report", {}).duplicate(true)
		_run_active = false
		return
	_state = "loading_resources"
	var resource_ready_paths: Dictionary = {}
	if not _cancel_requested:
		for pending_job in CACHE.region_session_jobs(_session):
			var request := CACHE.request_region_job_resource(_session, pending_job)
			_telemetry.resource_requests = int(_telemetry.resource_requests) + 1
			if request.has("error"):
				_fail_session_resource(
					String(pending_job.get("path", "")),
					String(request.get("error", "thread_request_failed"))
				)
				break
	while not _cancel_requested:
		var jobs := CACHE.region_session_jobs(_session)
		if jobs.is_empty():
			break
		var job: Dictionary = jobs[0]
		var resource_state := CACHE.poll_region_job_resource(_session, job)
		if String(resource_state.get("state", "")) == "not_requested":
			resource_state = CACHE.request_region_job_resource(_session, job)
			_telemetry.resource_requests = int(_telemetry.resource_requests) + 1
		if resource_state.has("error"):
			_fail_session_resource(
				String(job.get("path", "")),
				String(resource_state.get("error", "thread_load_failed"))
			)
			break
		if String(resource_state.get("state", "")) != "loaded":
			_state = "loading_resources"
			_telemetry.resource_wait_frames = int(_telemetry.resource_wait_frames) + 1
			await get_tree().process_frame
			continue
		var job_path := String(job.get("path", ""))
		if not resource_ready_paths.has(job_path):
			resource_ready_paths[job_path] = true
			_telemetry.resource_ready = int(_telemetry.resource_ready) + 1
		_state = "waiting_scheduler"
		var priority := _scheduler_priority()
		_scheduler_wait_started_frame = Engine.get_process_frames()
		var ticket: Dictionary = await SCHEDULER.reserve(
			self,
			StringName(job.get("producer", &"vehicle_prewarm:mountain")),
			priority,
			int(job.get("estimated_usec", SCHEDULER.FRAME_BUDGET_USEC))
		)
		var scheduler_wait_frames := maxi(0, Engine.get_process_frames() - _scheduler_wait_started_frame)
		_scheduler_wait_started_frame = -1
		if ticket.is_empty():
			if _cancel_requested:
				_telemetry.cancel_scheduler_wait_frames = scheduler_wait_frames
			else:
				_cancel_requested = true
				_cancel_reason = "scheduler_owner_invalid"
			break
		if _cancel_requested:
			SCHEDULER.complete(ticket, 0)
			_telemetry.cancel_scheduler_wait_frames = scheduler_wait_frames
			break
		_telemetry.heavy_reservations = int(_telemetry.heavy_reservations) + 1
		_state = "running"
		var result := CACHE.advance_region_job(
			_session,
			job,
			resource_state.get("resource") as Resource,
			ticket
		)
		var actual_usec := int(result.get("actual_usec", 0))
		SCHEDULER.complete(ticket, actual_usec)
		_record_stage_frame(
			int(ticket.get("frame", Engine.get_process_frames())),
			job_path,
			String(result.get("stage", "")),
			actual_usec,
			bool(result.get("over_budget", false))
		)
		if result.has("error"):
			_fail_session_resource(String(job.get("path", "")), String(result.error))
			break
		if bool(result.get("executed", false)):
			_telemetry.jobs_executed = int(_telemetry.jobs_executed) + 1
	var report := CACHE.finish_region_session(_session, _cancel_requested)
	_telemetry.last_report = report.duplicate(true)
	_session = {}
	_run_active = false
	if not _session_error.is_empty():
		_state = "failed"
	elif _cancel_requested:
		_state = "cancelled"
	else:
		var readiness := CACHE.region_cache_readiness(target_region, get_tree())
		if bool(readiness.get("ready", false)):
			_state = "completed"
			_failure_signature = ""
			_failure_repeat_count = 0
			_retry_not_before_msec = 0
			_telemetry.completed_count = int(_telemetry.completed_count) + 1
		else:
			_state = "failed"

func _fail_session_resource(path: String, reason: String) -> void:
	_session_error = reason
	_cancel_requested = true
	_cancel_reason = reason
	_telemetry.resource_failures = int(_telemetry.resource_failures) + 1
	var signature := "%s|%s" % [path, reason]
	if signature == _failure_signature:
		_failure_repeat_count += 1
	else:
		_failure_signature = signature
		_failure_repeat_count = 1
	var exponent := mini(3, maxi(0, _failure_repeat_count - 1))
	var retry_delay_msec := mini(RETRY_BACKOFF_MAX_MSEC, RETRY_BACKOFF_BASE_MSEC * (1 << exponent))
	_retry_not_before_msec = Time.get_ticks_msec() + retry_delay_msec
	_telemetry.failure_signature = _failure_signature
	_telemetry.failure_repeat_count = _failure_repeat_count
	_telemetry.retry_backoff_msec = retry_delay_msec
	_telemetry.retry_not_before_msec = _retry_not_before_msec
	_telemetry.last_error = {
		"path": path,
		"reason": reason,
		"retryable": true,
		"frame": Engine.get_process_frames(),
		"retry_backoff_msec": retry_delay_msec,
	}

func _producer_name() -> StringName:
	return StringName("vehicle_prewarm:%s" % String(target_region))

func _record_stage_frame(frame: int, path: String, stage: String, actual_usec: int, over_budget: bool) -> void:
	_telemetry.stage_steps_executed = int(_telemetry.stage_steps_executed) + 1
	if over_budget:
		_telemetry.over_budget_stages = int(_telemetry.over_budget_stages) + 1
	_telemetry.last_stage = {
		"path": path,
		"stage": stage,
		"actual_usec": actual_usec,
		"over_budget": over_budget,
		"frame": frame,
	}
	if int(_telemetry.last_job_frame) == frame:
		_telemetry.jobs_in_last_frame = int(_telemetry.jobs_in_last_frame) + 1
	else:
		_telemetry.last_job_frame = frame
		_telemetry.jobs_in_last_frame = 1
	_telemetry.max_jobs_in_frame = maxi(int(_telemetry.max_jobs_in_frame), int(_telemetry.jobs_in_last_frame))

func _scheduler_priority() -> int:
	if _last_distance <= NEAR_PRIORITY_DISTANCE:
		return SCHEDULER.PRIORITY_NEAR_COLLISION
	if _last_distance <= VISIBLE_PRIORITY_DISTANCE:
		return SCHEDULER.PRIORITY_VISIBLE
	return SCHEDULER.PRIORITY_BACKGROUND

func _motion_actor() -> Node2D:
	if is_instance_valid(motion_source_override):
		return motion_source_override
	var travel := get_node_or_null("/root/RegionTravel")
	if travel != null and travel.has_method("controlled_car"):
		var car = travel.controlled_car()
		if is_instance_valid(car) and car is Node2D:
			return car
	return get_tree().get_first_node_in_group("player") as Node2D if get_tree() != null else null

func _actor_velocity(actor: Node2D) -> Vector2:
	if actor is CharacterBody2D:
		return (actor as CharacterBody2D).velocity
	if actor is RigidBody2D:
		return (actor as RigidBody2D).linear_velocity
	return Vector2.ZERO

func _has_crossed(position: Vector2) -> bool:
	return position.x >= seam_position.x and position.y < -2000.0

func _exit_tree() -> void:
	_cancel_requested = true
	SCHEDULER.cancel_pending(self, _producer_name())
	if not _session.is_empty() and bool(_session.get("active", false)):
		CACHE.finish_region_session(_session, true)
	_session = {}
	_run_active = false
