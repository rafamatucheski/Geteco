extends SceneTree
const COURSE := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
const RUN := preload("res://activities/mountain_jeep/MountainJeepRun.gd")
const PROGRESS := preload("res://systems/campaign/MountainJeepProgress.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var progress := PROGRESS.new()
	var economy := ECONOMY.new()
	check(PROGRESS.validate_snapshot(progress.snapshot()),"older saves receive empty valid progress")
	check(PROGRESS.validate_wallet(progress.snapshot(),economy.snapshot()),"no historical prize is invented")
	var run := RUN.new()
	check(not run.begin(42,"sport_coupe",COURSE.start()),"a sports car cannot enter the jeep event")
	check(not run.begin(42,COURSE.VEHICLE,COURSE.start()+Vector3.RIGHT*8),"admission requires physical staging")
	check(run.begin(42,COURSE.VEHICLE,COURSE.start()),"jeep can stage at the start")
	run.tick(.1,COURSE.start()+Vector3.LEFT*1.2,42,true)
	check(not run.active and run.failure=="false_start","moving before countdown ends cancels")
	run=_ready_run()
	run.tick(.1,run.previous,43,true)
	check(not run.active and run.failure=="driver_left","switching to another jeep cancels by body identity")
	run=_ready_run()
	run.tick(.1,run.previous,42,false)
	check(not run.active,"leaving the jeep or dying cancels the attempt")
	run=_ready_run()
	run.tick(.1,COURSE.sample(45).position,42,true)
	check(not run.active and run.failure=="teleport","teleport across gates cannot score")
	run=_ready_run()
	# Controlled scorer fixtures: prove forward direction and physical gate width.
	var first: Dictionary=run.gates[0]
	run.previous=first.position+first.forward*.5
	run.tick(.1,first.position-first.forward*.5,42,true)
	check(run.gate==0,"reverse crossing does not count")
	var side := Vector3(first.forward.z,0,-first.forward.x)
	run.previous=first.position-first.forward*.5+side*3.2
	run.tick(.1,first.position+first.forward*.5+side*3.2,42,true)
	check(run.gate==0,"driving beside the physical gate does not count")
	var second: Dictionary=run.gates[1]
	run.previous=second.position-second.forward*.5
	run.tick(.1,second.position+second.forward*.5,42,true)
	check(run.gate==0 and not run.finished,"skipping the first gate cannot advance to the second")
	run=_drive_course(8.0)
	check(run.finished and not run.active and run.gate==COURSE.checkpoints().size(),"continuous ordered course ends at authored finish without an extra return lap")
	var paid := progress.settle(run,economy)
	check(not paid.is_empty() and paid.paid==700 and economy.balance==700,"first genuine finish pays exactly R$ 700")
	check(progress.settle(run,economy).is_empty() and economy.balance==700,"duplicate completion callback cannot pay or increment twice")
	var restored := PROGRESS.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(progress.snapshot()))),"results survive JSON save/load")
	check(PROGRESS.validate_wallet(restored.snapshot(),economy.snapshot()),"restored progress agrees with receipt")
	var second_run := _drive_course(9.0)
	var second_result := restored.settle(second_run,economy)
	check(not second_result.is_empty() and second_result.record and second_result.paid==0,"faster replay updates record without paying first prize again")
	check(economy.balance==700 and restored.data.finishes==2,"legitimate replay preserves balance and counts finishes")
	var invalid := restored.snapshot()
	invalid.rewarded=false
	check(not PROGRESS.validate_snapshot(invalid),"completion cannot omit first-prize state")
	invalid=restored.snapshot()
	invalid.best=NAN
	check(not PROGRESS.validate_snapshot(invalid),"non-finite record rejected")
	invalid=restored.snapshot()
	invalid.finishes=1.5
	check(not PROGRESS.validate_snapshot(invalid),"fractional finish count rejected")
	check(not PROGRESS.validate_wallet(restored.snapshot(),ECONOMY.new().snapshot()),"progress with missing reward receipt is rejected")
	var wallet := economy.snapshot()
	wallet.transactions["reward:"+PROGRESS.RECEIPT].amount=701
	check(not PROGRESS.validate_wallet(restored.snapshot(),wallet),"wrong prize amount rejected")
	run=_ready_run()
	run.elapsed=COURSE.TIME_LIMIT
	run.tick(.1,run.previous,42,true)
	check(not run.active and run.failure=="timeout" and progress.settle(run,economy).is_empty(),"timeout cannot award completion")
	for illegal in [null,true,"1",INF,1.5]:
		invalid=progress.snapshot()
		invalid.version=illegal
		check(not PROGRESS.validate_snapshot(invalid),"invalid schema rejected: "+str(illegal))
	for malformed in [null,[],"",42,true]:
		check(not PROGRESS.validate_snapshot(malformed) and not PROGRESS.validate_wallet(malformed,economy.snapshot()),"malformed root does not crash validator")
	check(not PROGRESS.validate_wallet(progress.snapshot(),{"transactions":[]}),"malformed receipt table rejected")
	var vehicle_progress := PROGRESS.new()
	var stale_vehicle := {"archetype":COURSE.VEHICLE,"vehicle_id":COURSE.LOAN_ID,"position":[640.0,.12,-438.0],"yaw":0.0,"health":80.0,"region":"mountain"}
	check(vehicle_progress.vehicle_for_restore(stale_vehicle)==stale_vehicle,"legacy selected jeep is accepted only when dedicated snapshot is absent")
	var latest_vehicle := stale_vehicle.duplicate(true)
	latest_vehicle.position=[635.0,.12,-440.0]
	latest_vehicle.health=40.0
	vehicle_progress.data.vehicle=latest_vehicle
	check(vehicle_progress.vehicle_for_restore(stale_vehicle)==latest_vehicle,"newer unload snapshot keeps parking and damage instead of old selected-car save")
	stale_vehicle.vehicle_id="player_personal_car"
	check(PROGRESS.new().vehicle_for_restore(stale_vehicle).is_empty(),"personal selected car cannot become the supplied jeep")
	print("MOUNTAIN_JEEP_PROGRESS_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _ready_run() -> RefCounted:
	var run := RUN.new()
	run.begin(42,COURSE.VEHICLE,COURSE.start())
	for i in 61: run.tick(.05,COURSE.start(),42,true)
	return run

func _drive_course(speed: float) -> RefCounted:
	var run := _ready_run()
	var distance := 0.0
	while run.active and distance<COURSE.length():
		distance+=speed*.02
		run.tick(.02,COURSE.sample(distance).position,42,true)
	return run

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)
