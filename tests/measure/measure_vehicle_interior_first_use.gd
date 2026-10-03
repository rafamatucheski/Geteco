extends "res://tests/measure/measure_performance_plan.gd"
## Directed first-use diagnostic. Main is rendered, but its process mode is disabled
## after normal startup/settling. These frame statistics are NOT gameplay FPS.
## Run in fresh processes with interior-control, interior-trigger or interior-stages
## and HARBOR_PLAN_WARMUP_IDENTITY=1. Never clears resource caches. All directed arms
## use 120 FPS to keep the bounded 12,000-interval observer below its limit.

const FAMILY := "union_sedan"
const VEHICLE_SOURCE := preload("res://scripts/Vehicle.gd")
const VEHICLE_ID := "diagnostic_union_interior_first_use"
const VEHICLE_POINT := Vector3(117.0, .12, 26.75539)
const FIRST_DELAY_USEC := 15000000
const SECOND_DELAY_USEC := 5000000

var subject: CharacterBody3D
var fixture_phase := "loading"
var fixture_events: Array[Dictionary] = []
var fixture_error := ""
var fixture_started := 0
var first_finished := 0
var first_requested := false
var second_requested := false
var phase_pending := false

func _cache_state() -> Dictionary:
	return {"warmed":WARMUP_SOURCE._warmed.has(FAMILY),
		"warming_owner":int(WARMUP_SOURCE._warming.get(FAMILY, 0)),
		"spec_cached":WARMUP_SOURCE._specs.has(FAMILY),
		"mesh_cached":WARMUP_SOURCE._meshes.has(FAMILY)}

func _record_event(event: String) -> void:
	var row := {"event":event,"engine_usec":Time.get_ticks_usec(),
		"process_frame":Engine.get_process_frames(),"cache":_cache_state(),
		"vehicle_id":VEHICLE_ID,"scenario":scenario}
	if is_instance_valid(subject):
		row["vehicle_instance_id"] = subject.get_instance_id()
		row["vehicle_position"] = str(subject.global_position)
	fixture_events.append(row)
	# Keep event capture in memory: synchronous console/file output must not sit
	# between the trigger timestamp and the operation being diagnosed.
	row["capture_usec"] = Time.get_ticks_usec()-int(row.engine_usec)

func _fail_fixture(reason: String) -> void:
	if not fixture_error.is_empty(): return
	fixture_error = reason
	fixture_phase = "invalid"
	_record_event("invalid:"+reason)
	push_error("INTERIOR_FIRST_USE_INVALID: "+reason)
	# The runner rejects the explicit error as well as this exit code.
	quit(7)

func settle_load() -> bool:
	if not await super.settle_load(): return false
	if scenario not in ["interior-control", "interior-trigger", "interior-stages"]:
		_fail_fixture("unknown_scenario")
		return false
	if not warmup_identity_enabled:
		_fail_fixture("identity_observer_required")
		return false
	if WARMUP_SOURCE._warmed.has(FAMILY) or WARMUP_SOURCE._warming.has(FAMILY):
		_fail_fixture("family_already_warmed_or_pending")
		return false
	# Use the production Vehicle implementation, with identity and paint fixed before
	# _ready. ProductionWorld.spawn_vehicle assigns a clock-derived identity first;
	# changing it afterwards would leave VehicleUsage's original cosmetic variation.
	subject = VEHICLE_SOURCE.new()
	subject.archetype = FAMILY
	subject.vehicle_id = VEHICLE_ID
	subject.paint_color = Color("dde3e4")
	subject.position = VEHICLE_POINT
	subject.set_meta("region_id", world.session.state.region_id)
	world.add_child(subject)
	if not world.production.vehicle_position_clear(subject, VEHICLE_POINT, 0.0):
		_fail_fixture("fixed_spawn_position_not_clear")
		return false
	world.production.vehicles.append(subject)
	# No await between construction and disabling Main: Driving cannot select the
	# subject first. The fixed point is also outside its 5 m selection radius.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.max_fps = 120
	fixture_phase = "settled_frozen"
	_record_event("prepared")
	return true

func state() -> Dictionary:
	var row := super.state()
	row["interior_first_use"] = {"phase":fixture_phase,"error":fixture_error,
		"shared_materials_prepared":preload("res://gameplay/VehicleInteriorMaterialPrewarm.gd")._drawn,
		"world_process_disabled":world.process_mode == Node.PROCESS_MODE_DISABLED,
		"events":fixture_events.duplicate(true),"cache":_cache_state(),
		"scope":"Directed rendered first-use diagnostic with Main callbacks disabled and the same 120 FPS cap in all arms; not gameplay FPS. SceneTree frames and rendering remain active."}
	return row

func apply_load(now: int) -> void:
	if not fixture_error.is_empty(): return
	if identity_dropped_intervals > 0 or identity_dropped_warmups > 0:
		_fail_fixture("identity_capture_overflow")
		return
	if fixture_started == 0: fixture_started = now
	if now-fixture_started >= 29000000 and fixture_phase != "complete":
		_fail_fixture("directed_phases_incomplete")
		return
	if phase_pending: return
	if not first_requested and now-fixture_started >= FIRST_DELAY_USEC:
		first_requested = true
		_exercise_phase("first")
	elif first_finished != 0 and not second_requested and now-first_finished >= SECOND_DELAY_USEC:
		second_requested = true
		_exercise_phase("repeat")

func _exercise_phase(which: String) -> void:
	phase_pending = true
	fixture_phase = which
	if not is_instance_valid(subject) or not subject.is_inside_tree():
		_fail_fixture("subject_removed")
		return
	if which == "first" and (WARMUP_SOURCE._warmed.has(FAMILY) or WARMUP_SOURCE._warming.has(FAMILY)):
		_fail_fixture("family_changed_before_trigger")
		return
	if scenario == "interior-stages":
		if which == "first" and (WARMUP_SOURCE._specs.has(FAMILY) or WARMUP_SOURCE._meshes.has(FAMILY)):
			_fail_fixture("stage_first_spec_or_mesh_already_cached")
			return
		if which == "repeat" and (not WARMUP_SOURCE._specs.has(FAMILY) or not WARMUP_SOURCE._meshes.has(FAMILY) or WARMUP_SOURCE._warmed.has(FAMILY) or WARMUP_SOURCE._warming.has(FAMILY)):
			_fail_fixture("stage_repeat_requires_cached_geometry_and_unwarmed_family")
			return
	_record_event(which+"_begin")
	if scenario == "interior-stages" and which == "first":
		var cabin: Dictionary = WARMUP_SOURCE.spec(subject)
		if cabin.is_empty():
			_fail_fixture("stage_first_empty_spec")
			return
		var interior_mesh: ArrayMesh = WARMUP_SOURCE.mesh_for(FAMILY, cabin)
		if interior_mesh == null:
			_fail_fixture("stage_first_missing_mesh")
			return
		_record_event(which+"_sync_end")
		# No temporary glass or attached interior: observe deferred work caused by
		# the normal spec/mesh construction across the following three frames.
		for frame in 3: await process_frame
	elif scenario == "interior-trigger" or scenario == "interior-stages":
		await WARMUP_SOURCE.prewarm(subject)
	else:
		for frame in 3: await process_frame
	_record_event(which+"_end")
	var expected_warmed := scenario == "interior-trigger" or (scenario == "interior-stages" and which == "repeat")
	if WARMUP_SOURCE._warmed.has(FAMILY) != expected_warmed or WARMUP_SOURCE._warming.has(FAMILY):
		_fail_fixture("unexpected_cache_state_after_"+which)
		return
	phase_pending = false
	if which == "first":
		first_finished = Time.get_ticks_usec()
		fixture_phase = "awaiting_repeat"
	else:
		fixture_phase = "complete"
