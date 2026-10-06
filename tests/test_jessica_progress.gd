extends SceneTree
const PROGRESS := preload("res://systems/campaign/JessicaProgress.gd")
const BANK := preload("res://runtime/Robberies.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var world := {}
	check(PROGRESS.validate_snapshot(PROGRESS.data(world)),"old save without Jessica has valid untouched defaults")
	check(PROGRESS.mark_met(world) and not PROGRESS.mark_met(world),"first meeting is recorded once without a relationship score")
	var bank := BANK.defaults()
	check(PROGRESS.begin_bank_job(world,bank),"clean bank can be accepted")
	check(not PROGRESS.begin_bank_job(world,bank),"active bank attempt cannot be accepted twice")
	var proof := {"cycle":0,"mask":1,"receipt":"bank_haul:0:1","receipt_paid":false,"alive":true,"outside_bank":true,"bank_failed":false}
	check(not PROGRESS.report_world_event(world,"bank_escaped",proof),"cash pickup without economy receipt cannot count as escaped haul")
	proof.receipt_paid = true
	proof.cycle = 1
	check(not PROGRESS.report_world_event(world,"bank_escaped",proof),"another robbery cycle cannot complete this job")
	proof.cycle = 0
	proof.outside_bank = false
	check(not PROGRESS.report_world_event(world,"bank_escaped",proof),"loot still inside bank cannot complete escape")
	proof.outside_bank = true
	check(PROGRESS.report_world_event(world,"bank_escaped",proof),"new secured pile plus correct receipt advances the real escape")
	check(not PROGRESS.report_world_event(world,"bank_escaped",proof),"duplicate robbery departure does not advance twice")
	var boarding := {"vehicle_id":"union_sedan","alive":true,"passenger":true,"door_clear":true}
	check(not PROGRESS.report_world_event(world,"getaway_boarded",boarding),"ordinary sedan cannot substitute Jessica's Jetta")
	boarding.vehicle_id = PROGRESS.CAR_ID
	boarding.door_clear = false
	check(not PROGRESS.report_world_event(world,"getaway_boarded",boarding),"blocked passenger side prevents boarding")
	boarding.door_clear = true
	check(PROGRESS.report_world_event(world,"getaway_boarded",boarding),"verified passenger boarding advances")
	var finish := {"vehicle_id":PROGRESS.CAR_ID,"alive":true,"route_finished":true,"safe_exit":true,"exterior":true,"inside_courtyard":true,"wanted":2,"travelled":100.0,"safe_distance":3.0}
	check(not PROGRESS.report_world_event(world,"safe_return",finish),"arriving with police pursuit is not a safe return")
	finish.wanted = 0
	finish.travelled = 0.0
	check(not PROGRESS.report_world_event(world,"safe_return",finish),"teleport to safe point cannot replace physical getaway")
	finish.travelled = 100.0
	finish.safe_exit = false
	check(not PROGRESS.report_world_event(world,"safe_return",finish),"blocked exit cannot complete return")
	finish.safe_exit = true
	finish.inside_courtyard = false
	check(not PROGRESS.report_world_event(world,"safe_return",finish),"street proximity alone cannot replace entering the actual workshop court")
	finish.inside_courtyard = true
	check(PROGRESS.report_world_event(world,"safe_return",finish),"physical return and collision-safe exit complete getaway")
	check(not PROGRESS.data(world).bank_complete,"relationship debrief remains pending until its conversation finishes")
	check(PROGRESS.report_world_event(world,"bank_debrief",{"at_jessica":true,"alive":true,"wanted":0}),"finished conversation records shared bank job")
	check(PROGRESS.validate_snapshot(JSON.parse_string(JSON.stringify(PROGRESS.data(world)))),"completed chapter event survives JSON numbers")
	check(not PROGRESS.cancel_attempt(world,"player_death"),"later death never erases completed meeting")
	var malformed := PROGRESS.data(world)
	malformed.haul_receipt = "bank_haul:99:7"
	check(not PROGRESS.validate_snapshot(malformed),"mismatching receipt cannot restore")
	malformed = PROGRESS.data(world)
	malformed.bank_complete = false
	check(not PROGRESS.validate_snapshot(malformed),"completion and encounter record must agree")
	malformed = PROGRESS.data(world)
	malformed.conversations.append("bank_debrief")
	check(not PROGRESS.validate_snapshot(malformed),"duplicate encounters rejected")
	var retry := {}
	bank = BANK.defaults()
	bank.bank_cash0 = true
	check(PROGRESS.begin_bank_job(retry,bank),"partially used bank can start without stealing earlier haul")
	check(not PROGRESS.report_world_event(retry,"bank_escaped",proof),"pile paid before acceptance is not new progress")
	check(PROGRESS.cancel_attempt(retry,"player_arrest"),"arrest cancels active attempt without editing robbery or economy")
	check(PROGRESS.data(retry).met and PROGRESS.validate_snapshot(PROGRESS.data(retry)),"cancel preserves acquaintance and valid restart state")
	var exhausted := BANK.defaults()
	exhausted.bank_cash0 = true
	exhausted.bank_cash1 = true
	exhausted.bank_cash2 = true
	check(not PROGRESS.begin_bank_job(retry,exhausted),"exhausted bank needs genuine new robbery cycle")
	for invalid in [null, "1", NAN, 1.5, true]:
		malformed = PROGRESS.data(world)
		malformed.version = invalid
		check(not PROGRESS.validate_snapshot(malformed),"malformed schema rejected: "+str(invalid))
	print("JESSICA_PROGRESS_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
