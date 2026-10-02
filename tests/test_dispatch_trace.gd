extends SceneTree
## Instrumentation contract only, not a gameplay or performance test.
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")
const WORK := preload("res://runtime/StallWorkTrace.gd")
class Controller extends Node:
	var units: Array = []
	var wrecks: Array = []
	func foot_officer_count() -> int: return 0
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:
		failures.append(label)
		push_error(label)
func sample_tick(controller: Node, label: String) -> void:
	var began := TRACE.begin()
	TRACE.end(label,began)
	TRACE.flush(controller)
func summaries(world: Node) -> Array:
	var result: Array = []
	for row in world.get_meta("perf_costs",[]):
		if row.get("label","")=="dispatch.summary": result.append(row)
	return result
func run() -> void:
	var first := Node.new()
	var second := Node.new()
	var controller := Controller.new()
	root.add_child(first)
	root.add_child(second)
	root.add_child(controller)
	first.set_meta("benchmark_trace",true)
	second.set_meta("benchmark_trace",true)
	TRACE.refresh(first)
	check(TRACE.on and TRACE.begin()>0,"trace explicitly enabled")
	var engine_start := Engine.get_physics_frames()
	sample_tick(controller,"controller.tick")
	sample_tick(controller,"controller.tick")
	TRACE._window_start = Time.get_ticks_usec()-TRACE.SUMMARY_USEC-1
	sample_tick(controller,"controller.tick")
	var reports := summaries(first)
	check(reports.size()==1,"one summary at finite window boundary")
	if reports.size()==1:
		var report: Dictionary = reports[0]
		check(report.controller_ticks==3 and report.physics_ticks==3,"first flush counts: three controller ticks, no off-by-one")
		check(report.spans["controller.tick"].n==3,"span count and controller count agree")
		check(report.engine_physics_ticks==Engine.get_physics_frames()-engine_start,"engine ticks distinct from controller callbacks")
	check(TRACE._controller_ticks==0 and TRACE._spans.is_empty(),"published window releases counters/spans")
	sample_tick(controller,"old_window")
	first.set_meta("benchmark_trace",false)
	TRACE.refresh(first)
	check(not TRACE.on and TRACE.begin()==0,"disabled trace returns zero timestamp")
	check(TRACE._controller_ticks==0 and TRACE._window_start==0 and TRACE._spans.is_empty(),"disable discards partial window")
	TRACE.end("ignored",0)
	TRACE.flush(controller)
	check(TRACE._controller_ticks==0 and TRACE._spans.is_empty(),"disabled calls do not accumulate")
	first.set_meta("benchmark_trace",true)
	TRACE.refresh(first)
	check(TRACE._controller_ticks==0 and TRACE._spans.is_empty(),"reenable starts fresh")
	sample_tick(controller,"old_world")
	TRACE.refresh(second)
	check(TRACE._controller_ticks==0 and TRACE._window_start==0 and TRACE._spans.is_empty(),"world switch discards previous world's window")
	sample_tick(controller,"second_world")
	TRACE._window_start = Time.get_ticks_usec()-TRACE.SUMMARY_USEC-1
	sample_tick(controller,"second_world")
	var second_reports := summaries(second)
	check(second_reports.size()==1,"new world gets its own summary")
	if second_reports.size()==1:
		var report: Dictionary = second_reports[0]
		check(report.controller_ticks==2 and report.spans["second_world"].n==2,"new world count isolated")
		check(not report.spans.has("old_world") and not report.spans.has("old_window"),"old labels absent from new world")
	check(summaries(first).size()==1,"world switch does not write into old world")
	var saturated: Array = []
	for i in TRACE.SLOW_RECORD_LIMIT: saturated.append({"label":"fixture.fast"})
	second.set_meta("perf_costs",saturated)
	WORK.enabled = true
	WORK.take()
	TRACE.end("fixture.critical",Time.get_ticks_usec()-25000)
	var forwarded := WORK.take()
	check(forwarded.size()==1 and forwarded[0].label=="dispatch.fixture.critical","slow dispatch span survives saturation of the older buffer")
	check(second.get_meta("perf_costs").size()==TRACE.SLOW_RECORD_LIMIT,"forwarding keeps the older buffer bounded")
	WORK.enabled = false
	TRACE.refresh(null)
	check(not TRACE.on and TRACE._controller_ticks==0 and TRACE._spans.is_empty(),"null world closes diagnostic state")
	first.free()
	second.free()
	controller.free()
	print("DISPATCH_TRACE checks=",checks," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
