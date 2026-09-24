extends SceneTree

const SCHEDULER := preload("res://systems/RuntimeWorkScheduler.gd")
const CARGO_PLANE := preload("res://world/mountain_pass/MountainCargoPlane.gd")
const FOREST_STREAMER := preload("res://world/mountain_pass/MountainForestStreamer.gd")
const PINE := preload("res://world/mountain_pass/MountainPine3D.gd")
const WINTER_DRESSING := preload("res://world/mountain_pass/transit/MountainWinterDressing.gd")
const MAX_FRAMES := 420
const SETTLE_MAX_FRAMES := 120

class FocusProbe extends Node2D:
	var velocity := Vector2.ZERO

class RoadFixture extends Node2D:
	var curve := Curve2D.new()
	var road_width := 96.0
	func _init() -> void:
		curve.bake_interval = 8.0
		curve.add_point(Vector2(6030,-1510))
		curve.add_point(Vector2(6260,-1840))
		curve.add_point(Vector2(6510,-2260))
		curve.add_point(Vector2(6460,-2580))
		curve.add_point(Vector2(7000,-2910))
	func is_point_on_road(point: Vector2, clearance: float) -> bool:
		return point.distance_to(curve.get_closest_point(point)) <= clearance

class StreamedWorld extends Node2D:
	var streamed_region := true
	var road: Node2D

class StreamedSettlement extends Node2D:
	var _streamed := true

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func _start_winter(settlement: Node2D) -> void:
	await WINTER_DRESSING.install_pockets(settlement)

func _request_then_cancel(owner: Node) -> void:
	await SCHEDULER.reserve(owner,&"cancelled_probe",SCHEDULER.PRIORITY_BACKGROUND,1200)

func _request_and_capture(owner: Node, producer: StringName, result: Dictionary) -> void:
	var ticket: Dictionary = await SCHEDULER.reserve(owner,producer,SCHEDULER.PRIORITY_BACKGROUND,1200)
	result["returned"] = true
	result["ticket"] = ticket.duplicate(true)
	if not ticket.is_empty():
		SCHEDULER.complete(ticket,0)

func _cancel_all_pending(owner: Node, result: Dictionary) -> void:
	result["count"] = SCHEDULER.cancel_pending(owner)
	result["returned"] = true

func _cancel_pending_producer(owner: Node, producer: StringName, result: Dictionary) -> void:
	result["count"] = SCHEDULER.cancel_pending(owner,producer)
	result["returned"] = true

func _forest_plan() -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	# Multiples of 64 keep every pine on variant 0. The real pine path, collider,
	# fallback and global atlas cache are still exercised without creating 16
	# unrelated atlas jobs in this scheduler integration fixture.
	for index in 8:
		plan.append({
			"plan_id": index,
			"position": Vector2(float(index - 4) * 64.0, float(index % 2) * 64.0),
			"scale": 0.9 + float(index % 3) * 0.05,
			"rock": index >= 6,
			"snow_region": false,
			"grove": index < 3,
			"placed_index": index,
		})
	return plan

func _atlas_ready(key: String) -> bool:
	for child in root.get_children():
		if child is SubViewport and String(child.get_meta("pine_atlas_key", "")) == key:
			return bool(child.get_meta("pine_atlas_ready", false))
	return false

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	Engine.max_fps = 0
	SCHEDULER.reset_for_tests()

	var world := Node2D.new()
	world.name = "RuntimeSchedulerIntegration"
	root.add_child(world)
	current_scene = world
	var focus := FocusProbe.new()
	focus.add_to_group("player")
	world.add_child(focus)

	var forest := FOREST_STREAMER.new()
	forest.name = "ConcurrentForest"
	world.add_child(forest)
	forest.configure(_forest_plan())

	var cargo := CARGO_PLANE.new()
	cargo.name = "ConcurrentCargoPlane"
	world.add_child(cargo)

	var pine := PINE.new()
	pine.name = "ConcurrentPine"
	pine.variant_seed = 8
	pine.is_snowy = false
	pine.position = Vector2(240,80)
	world.add_child(pine)

	var winter_world := StreamedWorld.new()
	winter_world.name = "ConcurrentWinterWorld"
	var road := RoadFixture.new()
	winter_world.road = road
	winter_world.add_child(road)
	var settlement := StreamedSettlement.new()
	winter_world.add_child(settlement)
	world.add_child(winter_world)
	_start_winter.call_deferred(settlement)

	var cancelled_owner := Node.new()
	cancelled_owner.name = "CancelledSchedulerOwner"
	world.add_child(cancelled_owner)
	_request_then_cancel.call_deferred(cancelled_owner)
	cancelled_owner.queue_free()

	# Queue cancellation after reserve() reaches its first await. This exercises
	# a genuinely pending request rather than an unsubmitted fixture.
	var explicit_owner := Node.new()
	explicit_owner.name = "ExplicitCancelledSchedulerOwner"
	world.add_child(explicit_owner)
	var explicit_reservation := {"returned": false, "ticket": {}}
	var explicit_cancel := {"returned": false, "count": -1}
	_request_and_capture.call_deferred(explicit_owner,&"explicit_cancel_probe",explicit_reservation)
	_cancel_all_pending.call_deferred(explicit_owner,explicit_cancel)

	# Filtering by producer must leave a sibling request from the same owner
	# eligible for its normal grant and completion.
	var filtered_owner := Node.new()
	filtered_owner.name = "FilteredCancelledSchedulerOwner"
	world.add_child(filtered_owner)
	var filtered_cancelled := {"returned": false, "ticket": {}}
	var filtered_kept := {"returned": false, "ticket": {}}
	var filtered_cancel := {"returned": false, "count": -1}
	_request_and_capture.call_deferred(filtered_owner,&"filtered_cancel_probe",filtered_cancelled)
	_request_and_capture.call_deferred(filtered_owner,&"filtered_keep_probe",filtered_kept)
	_cancel_pending_producer.call_deferred(filtered_owner,&"filtered_cancel_probe",filtered_cancel)

	var frames := 0
	while frames < MAX_FRAMES:
		await process_frame
		frames += 1
		var all_complete := (
			cargo.is_presentation_staging_complete()
			and int(forest.get_meta("stream_resident_count", 0)) == 8
			and _atlas_ready("0_0")
			and bool(settlement.get_meta("winter_dressing_complete", false)))
		if all_complete:
			break

	# Real producers may still hold the single global slot after their visible
	# staging contract completes. Wait for both the queue and the cancellation
	# coroutines, but keep a strict finite bound so starvation remains a failure.
	var settle_frames := 0
	var settle_complete := false
	while settle_frames < SETTLE_MAX_FRAMES:
		var settle_telemetry: Dictionary = SCHEDULER.telemetry_snapshot()
		settle_complete = (
			int(settle_telemetry.pending) == 0
			and bool(explicit_cancel.returned)
			and bool(explicit_reservation.returned)
			and bool(filtered_cancel.returned)
			and bool(filtered_cancelled.returned)
			and bool(filtered_kept.returned))
		if settle_complete:
			break
		settle_frames += 1
		await process_frame
	var telemetry: Dictionary = SCHEDULER.telemetry_snapshot()
	settle_complete = (
		int(telemetry.pending) == 0
		and bool(explicit_cancel.returned)
		and bool(explicit_reservation.returned)
		and bool(filtered_cancel.returned)
		and bool(filtered_cancelled.returned)
		and bool(filtered_kept.returned))
	var records: Array = telemetry.records
	var grants_by_frame := {}
	var completed_by_producer := {}
	var cancelled_by_producer := {}
	var maximum_wait_frames := 0
	var conflicting_frames: Array[int] = []
	var over_budget_records: Array[Dictionary] = []
	for record_variant in records:
		var record: Dictionary = record_variant
		if String(record.get("status", "")) == "cancelled":
			var cancelled_producer := String(record.get("producer", ""))
			cancelled_by_producer[cancelled_producer] = int(cancelled_by_producer.get(cancelled_producer,0)) + 1
		if String(record.get("status", "")) != "completed":
			continue
		var frame := int(record.frame)
		grants_by_frame[frame] = int(grants_by_frame.get(frame,0)) + 1
		completed_by_producer[String(record.producer)] = int(completed_by_producer.get(String(record.producer),0)) + 1
		maximum_wait_frames = maxi(maximum_wait_frames,int(record.waited_frames))
		if bool(record.get("over_budget",false)):
			over_budget_records.append({"producer":String(record.producer),"frame":frame,
				"expected_usec":int(record.expected_usec),"actual_usec":int(record.actual_usec)})
	for frame_variant in grants_by_frame:
		if int(grants_by_frame[frame_variant]) > 1:
			conflicting_frames.append(int(frame_variant))

	_check(cargo.is_presentation_staging_complete(),"avião real conclui staging sob contenção global")
	_check(int(forest.get_meta("stream_resident_count",0)) == 8,"floresta real materializa todos os itens próximos")
	_check(int(forest.get_meta("stream_peak_instances_per_frame",99)) <= forest.MAX_INSTANCES_PER_FRAME,"floresta preserva limite local de duas instâncias")
	_check(_atlas_ready("0_0"),"atlas real do pinheiro conclui mantendo fallback/cache global")
	_check(bool(settlement.get_meta("winter_dressing_complete",false)),"winter real conclui visual e colisões")
	_check(conflicting_frames.is_empty(),"nenhum frame recebe duas reservas pesadas conflitantes")
	for producer in ["mountain_cargo_plane","mountain_forest","mountain_pine_atlas","mountain_winter"]:
		_check(int(completed_by_producer.get(producer,0)) > 0,"telemetria registra produtor %s" % producer)
	_check(settle_complete,"fila global e resultados assíncronos terminam dentro do settle limitado")
	_check(int(telemetry.pending) == 0,"fila global termina vazia")
	_check(int(telemetry.cancelled_total) >= 3,"telemetria contabiliza owner inválido e dois cancelamentos explícitos")
	_check(bool(explicit_cancel.returned) and int(explicit_cancel.count) == 1,"cancelamento explícito remove uma reserva pendente do owner")
	_check(bool(explicit_reservation.returned) and (explicit_reservation.ticket as Dictionary).is_empty(),"reserve cancelado explicitamente acorda com ticket vazio")
	_check(int(cancelled_by_producer.get("explicit_cancel_probe",0)) == 1,"telemetria registra cancelamento explícito")
	_check(bool(filtered_cancel.returned) and int(filtered_cancel.count) == 1,"filtro de producer cancela somente a reserva correspondente")
	_check(bool(filtered_cancelled.returned) and (filtered_cancelled.ticket as Dictionary).is_empty(),"reserva filtrada acorda com ticket vazio")
	_check(bool(filtered_kept.returned) and not (filtered_kept.ticket as Dictionary).is_empty(),"filtro de producer preserva a reserva irmã do mesmo owner")
	_check(int(cancelled_by_producer.get("filtered_cancel_probe",0)) == 1 and int(cancelled_by_producer.get("filtered_keep_probe",0)) == 0,"telemetria respeita o filtro de producer")
	_check(maximum_wait_frames < MAX_FRAMES,"aging impede starvation de produtores de menor prioridade")
	_check(frames < MAX_FRAMES,"quatro produtores concluem dentro do prazo finito")

	print("RUNTIME_WORK_SCHEDULER frames=",frames,
		" completed=",telemetry.completed_total,
		" cancelled=",telemetry.cancelled_total,
		" over_budget=",telemetry.over_budget_total,
		" max_wait_frames=",maximum_wait_frames,
		" settle_frames=",settle_frames,
		" producer_counts=",completed_by_producer,
		" over_budget_records=",over_budget_records,
		" conflicting_frames=",conflicting_frames,
		" failures=",failures)
	world.queue_free()
	for index in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)
