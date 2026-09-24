extends SceneTree

const DRESSING := preload("res://world/mountain_pass/transit/MountainWinterDressing.gd")
const MAX_FRAMES := 240
const SIXTY_FPS_BUDGET_USEC := 16667

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
	if condition: return
	failures.append(message)
	push_error(message)

func _start_install(settlement: Node2D) -> void:
	await DRESSING.install_pockets(settlement)

func _run() -> void:
	var world := StreamedWorld.new()
	var road := RoadFixture.new()
	world.road = road
	world.add_child(road)
	var settlement := StreamedSettlement.new()
	world.add_child(settlement)
	root.add_child(world)

	# Exclude the engine/test harness first-frame initialization from the
	# dressing slice attribution. No dressing node exists during this warm-up.
	for frame in 5: await process_frame
	_start_install.call_deferred(settlement)
	var frame_count := 0
	var peak_interval_usec := 0
	var previous := Time.get_ticks_usec()
	while not settlement.get_meta("winter_dressing_complete",false) and frame_count < MAX_FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		peak_interval_usec = maxi(peak_interval_usec,now-previous)
		previous = now
		frame_count += 1

	var props := get_nodes_in_group("mountain_dressing").size()
	var peak_model_feature_usec := 0
	var peak_batch_allocation_usec := 0
	var peak_filter_usec := 0
	for group in settlement.find_children("*","Node3D",true,false):
		peak_model_feature_usec = maxi(peak_model_feature_usec,int(group.get_meta("stream_build_peak_feature_usec",0)))
		peak_batch_allocation_usec = maxi(peak_batch_allocation_usec,int(group.get_meta("stream_build_batch_allocation_usec",0)))
	for view in settlement.find_children("*","Node2D",true,false):
		peak_filter_usec = maxi(peak_filter_usec,int(view.get_meta("winter_dressing_peak_filter_usec",0)))
	_check(settlement.get_meta("winter_dressing_complete",false),"streamed winter dressing completes")
	_check(frame_count > 6,"streamed winter dressing is distributed across multiple frames")
	_check(frame_count < MAX_FRAMES,"streamed winter dressing has a finite completion bound")
	_check(props > 0,"streamed cadence preserves physical winter dressing")
	_check(int(settlement.get_meta("winter_dressing_build_view_peak_usec",0)) < SIXTY_FPS_BUDGET_USEC,
		"each streamed static-view setup stays within the structural frame budget")
	_check(peak_model_feature_usec < SIXTY_FPS_BUDGET_USEC,
		"each streamed model feature stays within the structural frame budget")
	_check(peak_batch_allocation_usec < SIXTY_FPS_BUDGET_USEC,
		"each streamed batch allocation stays within the structural frame budget")
	_check(peak_filter_usec < SIXTY_FPS_BUDGET_USEC,
		"each streamed hull/filter feature stays within the structural frame budget")
	print("WINTER_DRESSING_STREAM_CADENCE frames=",frame_count,
		" peak_interval_usec=",peak_interval_usec,
		" build_view_peak_usec=",settlement.get_meta("winter_dressing_build_view_peak_usec",0),
		" model_feature_peak_usec=",peak_model_feature_usec,
		" batch_allocation_peak_usec=",peak_batch_allocation_usec,
		" filter_peak_usec=",peak_filter_usec,
		" props=",props," failures=",failures)
	world.queue_free()
	for frame in 3: await process_frame
	quit(0 if failures.is_empty() else 1)
