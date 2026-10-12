extends SceneTree
const WORK := preload("res://runtime/StallWorkTrace.gd")
var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)

func _initialize() -> void:
	WORK.enabled = false
	check(WORK.begin() == 0,"Default trace and aggregation must be disabled")
	WORK.start_aggregate()
	var began := WORK.begin()
	check(began > 0,"Aggregate-only timing must arm existing call sites")
	WORK.finish_slow("fast_stage",began,1000000000)
	check(WORK.aggregate_totals.fast_stage.calls == 1,"Fast calls must contribute below detailed-log threshold")
	check(WORK.events.is_empty(),"Aggregate-only timing must not allocate detailed events")
	WORK.take()
	check(WORK.aggregate_totals.fast_stage.calls == 1,"Logger take must not consume aggregate totals")
	WORK.enabled = true
	WORK.finish("both_sinks",WORK.begin())
	var events := WORK.take()
	check(events.size() == 1 and events[0].label == "both_sinks","Detailed sink remains usable with aggregation")
	check(WORK.aggregate_totals.both_sinks.calls == 1,"Both sinks receive an enabled call")
	WORK.enabled = false
	var captured := WORK.stop_aggregate()
	check(WORK.begin() == 0,"Stopping aggregation restores default disabled timing")
	WORK.start_aggregate()
	check(WORK.aggregate_totals.is_empty(),"A new capture clears previous totals")
	check(captured.labels.fast_stage.calls == 1,"Exported snapshot survives the next capture")
	WORK.stop_aggregate()
	print("STALL_WORK_AGGREGATE failures=",failures)
	quit(1 if failures else 0)
