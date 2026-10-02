extends SceneTree
## Diagnostic only: paired workload windows with processing callbacks of one
## existing group gated at a time. All nodes, collision shapes and visual assets
## remain. The gate disables inherited processing of the subtree, not native
## physics bodies; differences are NOT pure engine-physics or exclusive CPU cost.
## Lifecycle set_physics_process/set_process writes remain authoritative.
## Frame intervals and callback intervals of every physics tick are retained.
## Sentinels bracket scene callbacks only; they exclude native solver work that
## runs outside those callbacks. First tick -> process_frame is separately named
## a batch wall-time estimate and must not be called pure physics CPU time.
## Rendered only; --no-save --skip-arrival, isolated user directory by executor.

const WARM_LIMIT_SECONDS := 60.0
const MIN_UNITS := 6
const SETTLE_SECONDS := 1.0

class Sentinel extends Node:
	var first_usec := 0
	var tick_start := 0
	var ticks := 0
	var completed_tick_us: Array[int] = []
	func _init() -> void:
		name = "PhysicsStartSentinel"
		process_physics_priority = -100000
	func _physics_process(_delta: float) -> void:
		tick_start = Time.get_ticks_usec()
		if ticks == 0: first_usec = tick_start
		ticks += 1
	func clear() -> void:
		ticks = 0
		first_usec = 0
		completed_tick_us.clear()

class EndSentinel extends Node:
	var first: Sentinel
	func _init() -> void:
		name = "PhysicsEndSentinel"
		process_physics_priority = 100000
	func _physics_process(_delta: float) -> void:
		if first.tick_start > 0:
			first.completed_tick_us.append(Time.get_ticks_usec()-first.tick_start)
			first.tick_start = 0

var label := "chaos-attribution"
var window_seconds := 4.0
var world: Node
var sentinel: Sentinel
var end_sentinel: EndSentinel
var gate_self_check: Dictionary = {}
var shots_admitted := 0
var blasts_admitted := 0
var next_shot := 0
var next_blast := 0

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if "--self-check-restoration" in OS.get_cmdline_user_args():
		var checked := await _check_gate_contract()
		print("ATTRIBUTION_RESTORATION ",JSON.stringify(checked))
		quit(0 if checked.passed else 1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Medição exige renderização real; headless não mede nada.")
		quit(2)
		return
	var arguments := OS.get_cmdline_user_args()
	for needed in ["--no-save", "--skip-arrival"]:
		if needed not in arguments:
			push_error("Medição recusada: falta %s." % needed)
			quit(2)
			return
	for arg in arguments:
		if arg.begins_with("--label="): label = arg.split("=")[1]
		if arg.begins_with("--seconds="): window_seconds = arg.split("=")[1].to_float()
		if arg.begins_with("--seed="): seed(arg.split("=")[1].to_int())
	gate_self_check = await _check_gate_contract()
	if not gate_self_check.passed:
		push_error("Processing gate contract failed: " + str(gate_self_check))
		quit(1)
		return
	world = load("res://Main.tscn").instantiate()
	# Liga o DispatchTrace: trechos lentos e resumos por segundo vão para perf_costs.
	world.set_meta("benchmark_trace", true)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for index in 900:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Mundo nativo não iniciou")
		quit(1)
		return
	world.player.controlled_automatically = true
	var controller: Node3D = world.dispatch
	if not is_instance_valid(controller):
		push_error("Controlador produtivo de despacho ausente")
		quit(1)
		return
	sentinel = Sentinel.new()
	root.add_child(sentinel)
	end_sentinel = EndSentinel.new()
	end_sentinel.first = sentinel
	root.add_child(end_sentinel)
	# Carga do guardião: arma, crime inicial de 150 pontos, vida reposta, explosão a cada 8 s.
	world.session.state.grant_weapon("ak47")
	world.session.state.add_ammo("ak47", 600)
	world.session.state.equip_weapon("ak47")
	await _settle(8.0)
	world.gameplay.register_crime(150, world.player.position)
	var waited := 0.0
	while controller.units.size() < MIN_UNITS and waited < WARM_LIMIT_SECONDS:
		waited += await _settle(1.0)
	var report := {"label": label, "window_seconds": window_seconds, "warm_seconds": waited, "reached_units": controller.units.size(),
		"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(), "population": world.people.size(),
		"ambient_cars": world.production.vehicles.size(), "variants": {}, "gate_self_check": gate_self_check,
		"scope": "Diagnostic processing-subtree ablation; native colliders stay active; newly created nodes are not automatically gated",
		"time_definitions": {"callback_tick_ms":"wall time between first/last physics callback sentinel; excludes native solver outside callbacks",
		"batch_wall_per_tick_ms":"first physics callback to process_frame divided by tick count; includes intervening engine work, not exclusive CPU attribution"}}
	if controller.units.size() < MIN_UNITS:
		report["warning"] = "carga não alcançou %d unidades: atribuição fraca" % MIN_UNITS
	report["baseline_before"] = await _sample(window_seconds)
	for id in ["dispatch_controller", "dispatch_vehicles", "police_on_foot", "emergency_crews_and_fires", "air_and_k9", "ambient_traffic", "pedestrians"]:
		var nodes: Array = _groups()[id]
		var changed := _suspend(nodes)
		var result := await _sample(window_seconds)
		result["nodes_gated"] = changed.size()
		var newcomers := 0
		for node in _groups()[id]:
			if is_instance_valid(node) and not nodes.has(node): newcomers += 1
		result["new_group_nodes_not_gated"] = newcomers
		result["restoration"] = _resume(changed)
		report["variants"][id] = result
		await _settle(SETTLE_SECONDS)
	report["baseline_after"] = await _sample(window_seconds)
	report["dispatch_costs"] = world.get_meta("perf_costs", [])
	var valid := true
	for variant in report.variants.values():
		if not variant.restoration.errors.is_empty() or variant.tick_count_mismatches>0: valid = false
	if report.baseline_before.tick_count_mismatches>0 or report.baseline_after.tick_count_mismatches>0: valid = false
	report["instrumentation_valid"] = valid
	var folder := ProjectSettings.globalize_path("res://tests/dispatch/results")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "/" + label + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("DISPATCH_ATTRIBUTION " + path)
	quit(0 if valid else 1)

## Mantém a carga viva por `seconds` sem medir. Devolve o tempo decorrido.
func _settle(seconds: float) -> float:
	var elapsed := 0.0
	var previous := Time.get_ticks_usec()
	while elapsed < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		elapsed += float(now - previous) / 1000000.0
		previous = now
		_drive_load()
	sentinel.clear()
	return elapsed

func _drive_load() -> void:
	if world.gameplay.health <= 0 or world.session.modal: return
	var now := Time.get_ticks_usec()
	world.gameplay.health = 100.0
	if now >= next_shot:
		next_shot = now + 200000
		if world.gameplay.fire_at(world.player.position + Vector3(8, 0, -2)): shots_admitted += 1
		if world.session.state.get_ammo("ak47").magazine == 0: world.gameplay.reload_weapon()
	if next_blast == 0: next_blast = now + 8000000
	if now >= next_blast:
		next_blast = now + 8000000
		world.gameplay.explode(world.player.position + Vector3(8, .1, -2), 4.0, 80.0, world.player, false)
		blasts_admitted += 1

func _sample(seconds: float) -> Dictionary:
	var frames := PackedFloat64Array()
	var per_tick := PackedFloat64Array()
	var callback_ticks := PackedFloat64Array()
	var raw_frames: Array = []
	var ticks_total := 0
	var mismatches := 0
	var elapsed := 0.0
	var previous := Time.get_ticks_usec()
	var previous_physics := Engine.get_physics_frames()
	var shots_before := shots_admitted
	var blasts_before := blasts_admitted
	var start_status: Dictionary = world.dispatch.status()
	sentinel.clear()
	while elapsed < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		var step := float(now - previous) / 1000.0
		previous = now
		frames.append(step)
		elapsed += step / 1000.0
		var engine_ticks := Engine.get_physics_frames()-previous_physics
		previous_physics = Engine.get_physics_frames()
		if sentinel.ticks != engine_ticks or sentinel.ticks != sentinel.completed_tick_us.size(): mismatches += 1
		var estimate := 0.0
		if sentinel.ticks > 0:
			estimate = float(now - sentinel.first_usec) / 1000.0 / float(sentinel.ticks)
			per_tick.append(estimate)
			ticks_total += sentinel.ticks
		var callback_us: Array = sentinel.completed_tick_us.duplicate()
		for us in callback_us: callback_ticks.append(float(us)/1000.0)
		raw_frames.append({"usec":now,"frame_ms":step,"engine_physics_ticks":engine_ticks,
			"sentinel_ticks":sentinel.ticks,"callback_tick_us":callback_us,"batch_wall_per_tick_ms":estimate})
		sentinel.clear()
		_drive_load()
	return {"frame_ms": _stats(frames), "batch_wall_per_tick_ms": _stats(per_tick),
		"callback_tick_ms": _stats(callback_ticks), "raw_frames":raw_frames,"tick_count_mismatches":mismatches,
		"ticks_per_frame": float(ticks_total) / maxf(1.0, float(frames.size())),
		"shots_admitted":shots_admitted-shots_before,"blasts_admitted":blasts_admitted-blasts_before,
		"health_end":world.gameplay.health,"stars_end":world.gameplay.stars,
		"dispatch_start":start_status,"dispatch":world.dispatch.status()}

func _stats(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty(): return {"n": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over_33 := 0
	var over_66 := 0
	for value in values:
		total += value
		if value > 33.3: over_33 += 1
		if value > 66.7: over_66 += 1
	var count := sorted.size()
	return {"n": count, "mean": total / count, "p50": sorted[int(count * 0.5)], "p95": sorted[int(count * 0.95)],
		"p99": sorted[mini(count - 1, int(count * 0.99))], "max": sorted[count - 1], "over_33_3": over_33, "over_66_7":over_66,"total_ms":total}

func _groups() -> Dictionary:
	var dispatch: Node3D = world.dispatch
	var gameplay: Node3D = world.gameplay
	var vehicles: Array = []
	var foot: Array = []
	var crews: Array = []
	# Unidades suspensas (longe) já têm a física desligada pelo próprio despacho.
	for unit in dispatch.units:
		if unit.finished or unit.suspended: continue
		vehicles.append(unit.vehicle)
		foot.append_array(unit.officers)
		if is_instance_valid(unit.crew): crews.append(unit.crew)
	foot.append_array(gameplay.police)
	crews.append_array(gameplay.emergency.fires)
	crews.append_array(gameplay.emergency.crews)
	var air: Array = []
	var director: Node3D = gameplay.police_air
	if is_instance_valid(director):
		air.append(director)
		if is_instance_valid(director.helicopter): air.append(director.helicopter)
		air.append_array(director.dogs)
	var ambient: Array = []
	ambient.append_array(world.production.vehicles)
	var people: Array = []
	people.append_array(world.people)
	return {"dispatch_controller": [dispatch], "dispatch_vehicles": vehicles, "police_on_foot": foot,
		"emergency_crews_and_fires": crews, "air_and_k9": air, "ambient_traffic": ambient, "pedestrians": people}

## process_mode is an independent gate: process flags can still change underneath.
## Respect an explicit lifecycle change of mode during the diagnostic as well.
func _suspend(nodes: Array) -> Array:
	var changed: Array = []
	var seen := {}
	for node in nodes:
		if not is_instance_valid(node) or node.is_queued_for_deletion(): continue
		var id: int = node.get_instance_id()
		if seen.has(id) or node.process_mode == Node.PROCESS_MODE_DISABLED: continue
		seen[id] = true
		changed.append({"ref":weakref(node),"path":str(node.get_path()),"mode":node.process_mode})
		node.process_mode = Node.PROCESS_MODE_DISABLED
	return changed

func _resume(changed: Array) -> Dictionary:
	var report := {"restored":0,"freed":0,"lifecycle_mode_preserved":0,"flag_changes":0,"errors":[]}
	for row in changed:
		var node: Node = row.ref.get_ref()
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			report.freed += 1
			continue
		var physics_flag := node.is_physics_processing()
		var process_flag := node.is_processing()
		if node.process_mode == Node.PROCESS_MODE_DISABLED:
			node.process_mode = row.mode
			report.restored += 1
			if node.process_mode != row.mode: report.errors.append(row.path+": mode restoration failed")
		else:
			report.lifecycle_mode_preserved += 1
		if physics_flag != node.is_physics_processing() or process_flag != node.is_processing():
			report.flag_changes += 1
			report.errors.append(row.path+": restoration changed authoritative process flags")
	return report

## Meaningful engine-node check: the old unconditional physics=true restoration
## fails the first case. No gameplay mock or permissive assertion is involved.
func _check_gate_contract() -> Dictionary:
	var results := {"passed":false,"flags_preserved":false,"mode_override_preserved":false,"freed_skipped":false,
		"disabled_excluded":false,"inherited_child_preserved":false,"explicit_child_excluded":false}
	var probe := Node.new()
	root.add_child(probe)
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	probe.set_physics_process(true)
	probe.set_process(true)
	var inherited_child := Node.new()
	probe.add_child(inherited_child)
	inherited_child.set_physics_process(true)
	var explicit_child := Node.new()
	probe.add_child(explicit_child)
	explicit_child.process_mode = Node.PROCESS_MODE_ALWAYS
	var rows := _suspend([probe,probe])
	var inherited_was_gated := not inherited_child.can_process()
	results.explicit_child_excluded = explicit_child.can_process()
	inherited_child.set_physics_process(false)
	probe.set_physics_process(false)
	probe.set_process(false)
	var restored := _resume(rows)
	results.inherited_child_preserved = inherited_was_gated and inherited_child.can_process() and not inherited_child.is_physics_processing()
	results.flags_preserved = rows.size()==1 and probe.process_mode==Node.PROCESS_MODE_ALWAYS and not probe.is_physics_processing() and not probe.is_processing() and restored.errors.is_empty()
	rows = _suspend([probe])
	probe.process_mode = Node.PROCESS_MODE_PAUSABLE
	restored = _resume(rows)
	results.mode_override_preserved = probe.process_mode==Node.PROCESS_MODE_PAUSABLE and restored.lifecycle_mode_preserved==1
	probe.process_mode = Node.PROCESS_MODE_DISABLED
	results.disabled_excluded = _suspend([probe]).is_empty()
	probe.process_mode = Node.PROCESS_MODE_PAUSABLE
	rows = _suspend([probe])
	probe.queue_free()
	await process_frame
	restored = _resume(rows)
	results.freed_skipped = restored.freed==1 and restored.errors.is_empty()
	results.passed = results.flags_preserved and results.mode_override_preserved and results.freed_skipped and results.disabled_excluded and results.inherited_child_preserved and results.explicit_child_excluded
	return results
