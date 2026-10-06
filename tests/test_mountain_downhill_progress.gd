extends SceneTree
const COURSE := preload("res://activities/mountain_downhill/MountainDownhillCourse.gd")
const RUN := preload("res://activities/mountain_downhill/MountainDownhillRun.gd")
const PROGRESS := preload("res://systems/campaign/MountainDownhillProgress.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var course := COURSE.new()
	check(course.length>500 and course.gate_offsets.size()>10,"long pass has ordered gates through its hairpins")
	check(is_equal_approx(course.length-course.gate_offsets.back(),75.0),"finish retains 75 metres of physical braking run-off")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	var main := preload("res://world/mountain_detail/MountainRouteLayout.gd").main_route(source.mountain_control_points)
	check(course.point(0).distance_to(main[-1])<.01 and course.point(course.length).distance_to(main[0])<.01,"course follows production pass summit to base")
	for i in 7:
		var grid := course.grid(i)
		check(grid.origin.distance_to(course.point(course.nearest_offset(grid.origin)))<2.0,"grid slot remains on actual road: %d"%i)
		for j in range(i+1,7):
			check(grid.origin.distance_to(course.grid(j).origin)>3.4,"seven distinct non-overlapping grid centers %d/%d"%[i,j])
	var run := RUN.start("car",course.grid(6).origin,course)
	RUN.tick(run,.1,course.grid(6).origin+Vector3(4,0,0),"car",true,true,course)
	check(run.failure=="race_false_start","moving before countdown cannot start early")
	run = RUN.start("car",course.grid(6).origin,course)
	RUN.tick(run,.1,course.gate(course.gate_offsets.size()-1),"car",true,false,course)
	check(run.failure=="race_interrupted" and run.checkpoint==0,"teleport cannot skip to finish")
	run = RUN.start("car",course.grid(6).origin,course)
	RUN.tick(run,.1,course.grid(6).origin,"different",true,false,course)
	check(run.failure=="race_vehicle_left","switching car invalidates attempt")
	run = RUN.start("car",course.grid(6).origin,course)
	RUN.tick(run,.1,course.grid(6).origin,"car",false,false,course)
	check(run.failure=="race_vehicle_broken","destroyed car cannot finish")
	var center := course.gate(0)
	var forward := course.forward(0)
	run = RUN.start("car",center+forward*2.0,course)
	RUN.tick(run,.1,center-forward*2.0,"car",true,false,course)
	check(run.checkpoint==0,"reverse crossing never counts")
	RUN.tick(run,.1,center+forward*2.0,"car",true,false,course)
	check(run.checkpoint==1,"swept forward crossing counts at speed")
	RUN.tick(run,.1,center-forward*2.0,"car",true,false,course)
	RUN.tick(run,.1,center+forward*2.0,"car",true,false,course)
	check(run.checkpoint==1,"same gate cannot count twice")
	run = RUN.start("car",course.gate(1)-course.forward(1)*2,course)
	RUN.tick(run,.1,course.gate(1)+course.forward(1)*2,"car",true,false,course)
	check(run.checkpoint==0,"later gate cannot substitute missing first gate")
	var right := forward.cross(Vector3.UP).normalized()
	run = RUN.start("car",center-forward*2+right*6,course)
	RUN.tick(run,.1,center+forward*2+right*6,"car",true,false,course)
	check(run.checkpoint==0,"passing outside gate width is rejected")
	run = RUN.start("car",center-forward*2+Vector3.UP*4,course)
	RUN.tick(run,.1,center+forward*2+Vector3.UP*4,"car",true,false,course)
	check(run.checkpoint==0,"different elevation cannot pass the road gate")
	run = RUN.start("car",course.point(10),course)
	var offset := 10.0
	while offset<course.length-60.0 and str(run.failure).is_empty():
		offset += 1.5
		RUN.tick(run,.1,course.point(offset),"car",true,false,course)
	check(run.failure.is_empty() and is_finite(float(run.finish)) and int(run.checkpoint)==course.gate_offsets.size(),"continuous complete ordered route finishes")
	var finished_time: float = run.finish
	RUN.tick(run,.1,course.point(offset),"car",true,false,course)
	check(run.finish==finished_time,"finished timing is immutable")
	var a := {"index":0,"run":run.duplicate()}
	var b := {"index":6,"run":run.duplicate()}
	a.run.finish = 30.08
	b.run.finish = 30.02
	check(RUN.ahead(b,a) and not RUN.ahead(a,b),"same-frame finish classification uses swept crossing time")
	var state := {}
	var economy := ECONOMY.new()
	check(PROGRESS.validate_wallet(PROGRESS.data(state),economy.snapshot()),"old save defaults are valid and untouched")
	check(not PROGRESS.claim_reward(state,economy),"participation alone grants no prize")
	check(PROGRESS.record_finish(state,7,65.5),"last place records a completed race")
	check(not PROGRESS.claim_reward(state,economy),"loss cannot claim winner prize")
	check(PROGRESS.record_finish(state,1,58.2),"first actual victory records result")
	var balance: int = economy.balance
	check(PROGRESS.claim_reward(state,economy) and economy.balance==balance+2400,"first victory grants documented reward")
	check(not PROGRESS.claim_reward(state,economy) and economy.balance==balance+2400,"repeated callback cannot duplicate prize")
	check(PROGRESS.record_finish(state,1,55.2) and not PROGRESS.claim_reward(state,economy),"repeat victory improves record without farming first-win receipt")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(PROGRESS.data(state)))
	check(PROGRESS.validate_wallet(saved,economy.snapshot()),"results and receipt survive JSON serialization")
	check(not PROGRESS.validate_wallet(saved,ECONOMY.new().snapshot()),"claimed prize without wallet receipt is rejected")
	saved.reward_paid = false
	check(not PROGRESS.validate_wallet(saved,economy.snapshot()),"wallet prize without matching result flag is rejected")
	for invalid in [NAN,true,"1",1.5,-1]:
		var bad := PROGRESS.defaults()
		bad.finishes = invalid
		check(not PROGRESS.validate_snapshot(bad),"malformed result counter rejected: "+str(invalid))
	print("MOUNTAIN_DOWNHILL_PROGRESS checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
