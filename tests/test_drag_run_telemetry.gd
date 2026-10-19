extends SceneTree
const TELEMETRY:=preload("res://activities/desert_drag/DragRunTelemetry.gd")
var failures:Array[String]=[]
var checks:=0
class Drive extends RefCounted:
	var launch_quality:="BOA LARGADA"
	var launch_score:=.9
	var shift_serial:=0
	var last_shift:=""
	var gear:=1
	var limiter:=false
	var wheelspin:=0.0
	var nitro_active:=false
	var speed_mps:=10.0
func check(ok:bool,label:String)->void:
	checks+=1
	print("DRAG_TELEMETRY ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func _initialize()->void:
	var observed:=TELEMETRY.new()
	var drive:=Drive.new()
	drive.shift_serial=1
	drive.last_shift="BOA TROCA"
	observed.observe(drive,55,65,2,.1,201)
	check(is_equal_approx(float(observed.splits["60"]),2.05),"partial time interpolates actual physical crossing")
	observed.observe(drive,65,75,2.1,.1,201)
	check(observed.good_shifts==1,"one shift is not counted every frame")
	drive.shift_serial=2
	drive.last_shift="ATRASOU"
	drive.limiter=true
	drive.nitro_active=true
	drive.wheelspin=.5
	observed.observe(drive,200,204,6,.1,201)
	check(is_equal_approx(float(observed.splits["201"]),6.025),"finish time uses only distance to finish")
	check(is_equal_approx(observed.nitro_seconds,.025) and is_equal_approx(observed.limiter_seconds,.025),"durations stop at the physical finish")
	var before:=observed.snapshot()
	observed.observe(drive,204,220,6.1,.1,201)
	check(observed.snapshot()==before,"braking cannot contaminate the pass")
	check(observed.bad_shifts==1 and observed.shifts.size()==2,"bad and good shifts are distinguished")
	check(not observed.splits.has("402"),"short course cannot invent a longer partial")
	var snapshot:=observed.snapshot()
	snapshot.shifts.clear()
	snapshot.splits.clear()
	check(observed.shifts.size()==2 and observed.splits.size()==2,"result is a detached immutable observation")
	check(str(observed.snapshot().advice).contains("faixa"),"feedback addresses the observed bad shift")
	var retry:=TELEMETRY.new()
	check(retry.shifts.is_empty() and retry.splits.is_empty(),"new attempt carries no previous pass")
	print("DRAG_TELEMETRY_DONE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
