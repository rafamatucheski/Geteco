extends SceneTree
const STATE := preload("res://runtime/upside_world/UpsideWorldState.gd")
const RETURNS := preload("res://runtime/upside_world/UpsideReturnPoints.gd")
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	check(not STATE.eligible(STATE.PLACE,89.999),"subthreshold intoxication never enters the illusion")
	check(STATE.eligible(STATE.PLACE,90.0) and STATE.eligible(STATE.PLACE,100.0),"extreme threshold includes90 and caps100")
	for bad in [-1.0,NAN,INF,100.001]: check(not STATE.eligible(STATE.PLACE,bad),"invalid alcohol rejected")
	check(not STATE.eligible("harbor_curitiba_cellar",100.0),"drinking at the wine store does not trigger Umbra")
	check(not STATE.eligible(STATE.PLACE,100.0,true),"loading a saved Umbra position never starts or restarts an illusion")
	var model=STATE.new()
	check(not model.start(1,12.0) and not model.tick(20.0),"time or consumption alone cannot begin without a fresh entry")
	check(model.arm_entry(101,STATE.PLACE,90.0),"extreme fresh entry arms one attempt")
	check(not model.arm_entry(101,STATE.PLACE,100.0),"duplicate admission callback does not queue a second illusion")
	check(not model.start(101,9.999) and not model.start(101,15.001),"productive duration cannot escape10–15seconds")
	check(model.start(101,12.5),"one armed entry begins with bounded authored duration")
	var before: Dictionary=model.snapshot()
	check(not model.tick(200.0,true) and model.snapshot()==before,"pause freezes the whole remaining duration")
	check(not model.tick(NAN) and not model.tick(-1.0) and model.snapshot()==before,"invalid deltas cannot consume or extend the timer")
	check(not model.tick(12.49) and model.tick(.02) and model.elapsed==12.5,"return requested exactly after playable duration")
	model.cancel()
	check(not model.arm_entry(101,STATE.PLACE,100.0),"drinking again inside the same room cannot retrigger")
	check(model.arm_entry(202,STATE.PLACE,100.0) and model.start(202,10.0),"leaving and entering a new room instance permits a later independent event")
	model.cancel()
	check(not model.active and model.pending_entry==0,"interruption clears active and pending state")
	var points:=RETURNS.candidates()
	check(points.size()>=4,"several curated accessible Harbor pavement returns are available")
	for point in points:
		check(point.is_finite() and point.y>=0.0 and point.y<1.0 and point.z>-200.0 and point.z<300.0,"return remains at ground-level Harbor, never map2 or the remote illusion arena")
	print("UPSIDE_WORLD_STATE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
