extends "res://tests/measure/measure_intermittent_stalls.gd"
## Mesma rota produtiva e observadores; agrega só o retorno de 30–60 segundos.
const RETURN_START_USEC := 30000000
const RETURN_END_USEC := 60000000
var _return_start_usec := 0
var _return_end_usec := 0
var _return_cpu_start := PackedInt64Array()
var _return_cpu_end := PackedInt64Array()
var _return_totals: Dictionary = {}
var _return_expected_rows := 0
var _return_edges: Array[Dictionary] = []
var _return_invalid: Array[String] = []

func run() -> void:
	if CAPTURE_WORK.aggregate_enabled:
		push_error("RETURN_STAGE_REQUIRES_UNCLAIMED_AGGREGATE_SINK")
		quit(7)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--observer=") and argument != "--observer=on":
			push_error("RETURN_STAGE_REQUIRES_NATIVE_BOUNDARY_OBSERVER")
			quit(7)
			return
		if argument == "--profile":
			push_error("RETURN_STAGE_REQUIRES_SCRIPT_PROFILER_DISABLED")
			quit(7)
			return
	await super.run()
	if _return_start_usec != 0 and _return_end_usec == 0:
		_return_invalid.append("route_ended_before_return_window_closed")
		_stop_return_stage()
	_export_return_stage()

func capture_interval(now: int, previous: int) -> void:
	# Fecha antes de o pai coletar o último intervalo concluído. Ele inclui
	# o trabalho desde o sinal de process-frame anterior, antes deste callback.
	if capture_start > 0 and _return_start_usec != 0 and _return_end_usec == 0 and now-capture_start >= RETURN_END_USEC:
		_stop_return_stage()
	super.capture_interval(now,previous)
	if _return_start_usec != 0 and not capture_last_row.is_empty():
		var row := capture_last_row
		var finish := _return_end_usec if _return_end_usec != 0 else now
		if int(row.start_usec) >= _return_start_usec and int(row.end_usec) <= finish:
			_return_expected_rows += 1
			# Guarda também os intervalos rápidos. A deduplicação do pai e o DETAIL_LIMIT continuam
			# valendo; qualquer perda invalida o pai e este relatório.
			capture_keep(row)
		elif int(row.end_usec) > _return_start_usec and int(row.start_usec) < finish and _return_edges.size() < 2:
			_return_edges.append(row)
	# Começa depois de coletar o intervalo que cruza o limite de 30 segundos;
	# os callbacks anteriores dele não podem ser contados retroativamente como trabalho agregado.
	if capture_start > 0 and _return_start_usec == 0 and now-capture_start >= RETURN_START_USEC and now-capture_start < RETURN_END_USEC:
		_return_start_usec = Time.get_ticks_usec()
		_return_cpu_start = _boundary_sample()
		CAPTURE_WORK.start_aggregate()
		capture_event("return_stage_start",{"requested_start_usec":capture_start+RETURN_START_USEC,"actual_start_usec":_return_start_usec})

func _stop_return_stage() -> void:
	_return_end_usec = Time.get_ticks_usec()
	_return_totals = CAPTURE_WORK.stop_aggregate()
	_return_cpu_end = _boundary_sample()
	capture_event("return_stage_end",{"requested_end_usec":capture_start+RETURN_END_USEC,"actual_end_usec":_return_end_usec})

func _cpu_difference(first: Variant, last: Variant) -> int:
	if first.size() != 7 or last.size() != 7: return -1
	if int(first[5]) != 1 or int(last[5]) != 1 or int(first[1]) != boundary_thread_id or int(last[1]) != boundary_thread_id: return -1
	if int(last[0]) < int(first[0]) or int(last[2]) < int(first[2]) or int(last[3]) < int(first[3]): return -1
	return int(last[2])+int(last[3])-int(first[2])-int(first[3])

func _boundary_totals(rows: Array[Dictionary]) -> Dictionary:
	var result := {"intervals":rows.size(),"interval_wall_usec":0,"interval_cpu_usec":0,
		"physics_ticks":0,"physics_callbacks_wall_usec":0,"physics_callbacks_cpu_usec":0,
		"through_process_end_wall_usec":0,"through_process_end_cpu_usec":0,
		"draw_wall_usec":0,"draw_cpu_usec":0,"invalid_cpu_pairs":0,"invalid_boundary_rows":0,
		"observer_wall_usec":0,"capture_wall_usec":0,"context_observer_wall_usec":0}
	for row in rows:
		var start := int(row.start_usec)
		var finish := int(row.end_usec)
		result.interval_wall_usec += finish-start
		result.observer_wall_usec += int(row.get("observer_wall_usec",0))
		result.capture_wall_usec += int(row.get("capture_usec",0))
		result.context_observer_wall_usec += int(row.get("signal_observer_usec",0))
		var cpu := _cpu_difference(row.thread_start,row.thread_end)
		if cpu < 0: result.invalid_cpu_pairs += 1
		else: result.interval_cpu_usec += cpu
		var process_end := int(row.process_callbacks_end_usec)
		var draw_pre := int(row.draw_pre_usec)
		var draw_post := int(row.draw_post_usec)
		var ordered := process_end >= start and draw_pre >= process_end and draw_post >= draw_pre and draw_post <= finish and bool(row.draw_pair_valid)
		if not ordered:
			result.invalid_boundary_rows += 1
			continue
		result.through_process_end_wall_usec += process_end-start
		cpu = _cpu_difference(row.thread_start,row.thread_process_end)
		if cpu < 0: result.invalid_cpu_pairs += 1
		else: result.through_process_end_cpu_usec += cpu
		result.draw_wall_usec += draw_post-draw_pre
		cpu = _cpu_difference(row.thread_draw_pre,row.thread_draw_post)
		if cpu < 0: result.invalid_cpu_pairs += 1
		else: result.draw_cpu_usec += cpu
		for tick in row.physics_ticks:
			# Entre sinais consecutivos de process-frame, a física pertence ao período depois
			# do desenho anterior. Rejeita sobreposição em vez de contá-la duas vezes.
			if int(tick.start_usec) < draw_post or int(tick.end_usec) > finish or int(tick.end_usec) < int(tick.start_usec):
				result.invalid_boundary_rows += 1
				continue
			result.physics_ticks += 1
			result.physics_callbacks_wall_usec += int(tick.end_usec)-int(tick.start_usec)
			cpu = _cpu_difference(tick.thread_start,tick.thread_end)
			if cpu < 0: result.invalid_cpu_pairs += 1
			else: result.physics_callbacks_cpu_usec += cpu
	result["unbracketed_cpu_usec"] = result.interval_cpu_usec-result.through_process_end_cpu_usec-result.draw_cpu_usec-result.physics_callbacks_cpu_usec
	result["unbracketed_wall_usec"] = result.interval_wall_usec-result.through_process_end_wall_usec-result.draw_wall_usec-result.physics_callbacks_wall_usec
	return result

func _export_return_stage() -> void:
	if output.is_empty(): return
	if _return_start_usec == 0: _return_invalid.append("return_window_not_started")
	if not capture_valid.is_empty(): _return_invalid.append("parent_capture_invalid: "+capture_valid)
	if not boundary_error.is_empty(): _return_invalid.append(boundary_error)
	if boundary_dropped_intervals > 0 or boundary_dropped_ticks > 0 or boundary_tick_mismatches > 0 or boundary_invalid_cpu > 0 or capture_dropped > 0 or capture_ring_dropped > 0 or capture_cause_dropped > 0:
		_return_invalid.append("observer_data_loss")
	var rows: Array[Dictionary] = []
	for row in capture_kept:
		if _return_start_usec != 0 and int(row.start_usec) >= _return_start_usec and int(row.end_usec) <= _return_end_usec: rows.append(row)
	if rows.is_empty() or rows.size() != _return_expected_rows: _return_invalid.append("complete_interval_retention_mismatch")
	var stages: Array[Dictionary] = []
	for stage_label: String in _return_totals.get("labels",{}):
		var stage: Dictionary = _return_totals.labels[stage_label].duplicate()
		stage["label"] = stage_label
		stage["mean_usec"] = float(stage.total_usec)/maxi(1,int(stage.calls))
		stages.append(stage)
	stages.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.total_usec)>int(b.total_usec))
	if int(_return_totals.get("dropped_calls",0)) > 0: _return_invalid.append("aggregate_label_overflow")
	var cpu := _cpu_difference(_return_cpu_start,_return_cpu_end)
	if cpu < 0: _return_invalid.append("invalid_aggregate_thread_cpu")
	var boundaries := _boundary_totals(rows)
	if int(boundaries.invalid_cpu_pairs) > 0 or int(boundaries.invalid_boundary_rows) > 0: _return_invalid.append("incomplete_or_overlapping_boundaries")
	var report := {"label":label,"invalid":_return_invalid,"parent_validity":capture_valid,
		"requested_start_usec":capture_start+RETURN_START_USEC,"requested_end_usec":capture_start+RETURN_END_USEC,
		"aggregate_start_usec":_return_start_usec,"aggregate_end_usec":_return_end_usec,
		"thread_cpu_start":Array(_return_cpu_start),"thread_cpu_end":Array(_return_cpu_end),"thread_cpu_usec":cpu,
		"thread_columns":["wall_usec","native_thread_id","kernel_usec","user_usec","cycles","valid","processor"],
		"stages":stages,"aggregate_dropped_calls":int(_return_totals.get("dropped_calls",0)),
		"expected_complete_intervals":_return_expected_rows,"intervals":rows,"edge_intervals":_return_edges,
		"boundaries":boundaries,"priority_audit":boundary_priority_rows,
		"parent_limits":{"detail_limit":DETAIL_LIMIT,"ring_limit":RING_LIMIT,"max_ticks_per_interval":MAX_BOUNDARY_TICKS},
		"scope":"Same parent route, native C# path, input, observers, validity and bounds. Aggregate opens at the first capture callback at/after READY+30s, after collecting the preceding interval; closes at the first callback at/after READY+60s, before collecting its completed interval. Exact times reveal frame-boundary overshoot. Every complete interval inside the actual aggregate window is retained, including fast frames. Edge intervals remain separate: aggregate totals/CPU include that partial-frame work, so do not subtract complete-row sums from whole-window stages as if their boundaries matched. through_process_end includes the observer/input work before ordinary process callbacks. Parent/child stages are inclusive and MUST NOT be summed; native work inside them is already included. Unbracketed gaps are not exclusive solver, GPU or scheduler attribution. Observer overhead is included, never subtracted. CPU accounting is coarse; cycles are not time."}
	if not rows.is_empty():
		report["complete_start_usec"] = rows.front().start_usec
		report["complete_end_usec"] = rows.back().end_usec
		report["start_fringe_wall_usec"] = int(rows.front().start_usec)-_return_start_usec
		report["end_fringe_wall_usec"] = _return_end_usec-int(rows.back().end_usec)
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join(label+"-return-stage-cost.json"),FileAccess.WRITE)
	if file == null:
		push_error("RETURN_STAGE_EXPORT_FAILED")
		quit(7)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("RETURN_STAGE_COST ",JSON.stringify({"invalid":_return_invalid,"stages":stages.size(),"complete_intervals":rows.size(),"cpu_usec":cpu}))
	if not _return_invalid.is_empty(): quit(7)
