extends SceneTree
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	check(SCHEDULE.departure(0,.5).is_empty(),"No convoy on unscheduled days")
	check(SCHEDULE.departure(1,8.99/24.0).is_empty(),"No departure before bank loading window")
	check(SCHEDULE.departure(1,10.0/24.0).is_empty(),"Missed departures do not restart outside their window")
	var first := SCHEDULE.departure(1,9.0/24.0)
	check(first.origin == "harbor_bank" and first.destination == "desert_bank","First route connects the existing city bank to desert bank")
	var reverse := SCHEDULE.departure(3,14.0/24.0)
	check(reverse.origin == "desert_bank" and reverse.destination == "harbor_bank","Convoy can originate from desert bank")
	check(SCHEDULE.departure(8,9.0/24.0).origin != first.origin,"Following week rotates origin")
	check(SCHEDULE.CASH_PER_TRUCK == preload("res://data/catalogs/EconomyBalance.gd").ARMORED_CASH_PER_TRUCK and SCHEDULE.CASH_PER_TRUCK > 0,"Reward per truck comes from the economy table")
	var previous := SCHEDULE.security(0)
	for level in range(1,7):
		var next := SCHEDULE.security(level)
		check(next.guard_count >= previous.guard_count and next.guard_health >= previous.guard_health,"Preparation never reduces escort strength")
		check(next.city_report_delay <= previous.city_report_delay and next.road_report_delay <= previous.road_report_delay,"Repeated robbery accelerates dispatch")
		check(next.city_report_delay <= next.road_report_delay,"Urban response is never slower than rural response")
		previous = next
	check(previous.road_report_delay == 0 and previous.lock_stages == 3 and previous.blast_hits == 3,"Maximum preparation calls immediately and reinforces both entry methods")
	check(SCHEDULE.security(999) == previous,"Escalation has bounded physical workload")
	var row := SCHEDULE.initial(first,2)
	var saved := {"version":1,"last_event":first.id,"security_level":2,"event":row}
	check(SCHEDULE.valid_saved(saved),"Fresh event can round-trip through save validation")
	var restored := SCHEDULE.restore(JSON.parse_string(JSON.stringify(row)))
	check(not restored.is_empty() and restored.security_level == 2,"JSON storage preserves preparation")
	var pose_record := row.duplicate(true)
	pose_record.vehicles = []
	for index in 4: pose_record.vehicles.append({"point":[0,2,0],"yaw":0,"health":100})
	check(SCHEDULE.restore(JSON.parse_string(JSON.stringify(pose_record))).virtual_poses,"Off-screen poses retain their terrain admission marker through JSON")
	pose_record.virtual_poses = false
	check(not SCHEDULE.restore(pose_record).virtual_poses,"Physical saved poses retain exact-placement policy")
	pose_record.erase("virtual_poses")
	check(not SCHEDULE.restore(pose_record).virtual_poses,"Legacy four-body saves remain physical, without implicit repositioning")
	pose_record.vehicles = []
	check(SCHEDULE.restore(pose_record).virtual_poses,"Legacy event without bodies uses virtual admission")
	pose_record.virtual_poses = "true"
	check(SCHEDULE.restore(pose_record).is_empty(),"Invalid admission marker rejected before restore")
	row.opened[0] = true
	row.taken[0] = true
	row.pending = SCHEDULE.CASH_PER_TRUCK
	check(SCHEDULE.valid_saved(saved),"One opened truck records exactly one truck carried")
	row.pending = SCHEDULE.CASH_PER_TRUCK * 2
	check(not SCHEDULE.valid_saved(saved),"Cannot claim both rewards after opening only one truck")
	row.pending = 0
	row.secured[0] = true
	check(SCHEDULE.valid_saved(saved),"Secured first truck stays consumed")
	row.opened[1] = true
	row.taken[1] = true
	row.pending = SCHEDULE.CASH_PER_TRUCK
	check(SCHEDULE.valid_saved(saved),"Returning for second truck preserves only its unpaid truck")
	row.phase = "finished"
	row.pending = 0
	check(SCHEDULE.valid_saved(saved),"Failed event consumes stolen cargo without granting it")
	row.elapsed = NAN
	check(not SCHEDULE.valid_saved(saved),"Nonfinite clocks rejected")
	row.elapsed = 0
	row.vehicles = [{"point":[0,0,0],"yaw":0,"health":100}]
	check(not SCHEDULE.valid_saved(saved),"Partial admission cannot be saved as full convoy")
	row.vehicles = []
	row.guards = [{"point":[0,0,0],"health":100,"seat":0,"phase":"bank"}]
	check(SCHEDULE.valid_saved(saved),"Finite crew snapshot accepted")
	row.guards[0].point = [0,INF,0]
	check(not SCHEDULE.valid_saved(saved),"Invalid crew coordinates rejected before live state mutation")
	row.guards = []
	row.delivered[0] = true
	check(not SCHEDULE.valid_saved(saved),"Money deposited at bank cannot also be stolen from the same truck")
	print("ARMORED_SCHEDULE: %d checks; failures=%d" % [checks,failures])
	quit(1 if failures else 0)
