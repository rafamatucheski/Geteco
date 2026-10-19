extends SceneTree
## Directed queue-boundary validation, separate from physical racing coverage.
const CHALLENGE := preload("res://activities/desert_drag/DragRivalChallengeProgress.gd")
const CONTROLLER := preload("res://activities/desert_drag/DragRivalChallengeController.gd")
const NIGHT := preload("res://activities/desert_drag/DragNightProgress.gd")
const NIGHT_CONTROLLER := preload("res://activities/desert_drag/DragNightController.gd")
var checks := 0
var failures: Array[String] = []

class SessionDouble extends Node:
	var state := {"world_state":{}}

class RaceDouble extends Node3D:
	var session: Node
	func powertrain_profile_for_vehicle(car: Node) -> String: return car.profile

class CarDouble extends Node:
	var vehicle_id := "queue_car"
	var archetype := "desert_faisca"
	var profile := "desert_faisca"

func check(ok: bool, label: String) -> void:
	checks+=1
	print("RIVAL_DISPATCH ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var session := SessionDouble.new()
	var race := RaceDouble.new()
	var car := CarDouble.new()
	root.add_child(session)
	root.add_child(race)
	root.add_child(car)
	race.session=session
	var controller := CONTROLLER.new()
	race.add_child(controller)
	controller.configure(race)
	var begun := CHALLENGE.begin(session.state.world_state,"digo",0,car.vehicle_id,car.archetype,car.profile,{})
	controller._armed=begun.entry
	check(controller.can_start("digo") and not controller.can_start("livia"),"armed workshop context authorizes only its own rival")
	check(controller.validate_dispatch(car).is_empty(),"unchanged registered car can dispatch")
	car.set_meta("desert_parts",{"ecu":"ecu_1"})
	check(not controller.validate_dispatch(car).is_empty(),"mechanical change while waiting blocks dispatch")
	car.set_meta("desert_parts",{"paint":"paint_pearl"})
	check(controller.validate_dispatch(car).is_empty(),"cosmetic change does not invalidate a workshop proof")
	car.vehicle_id="other_car"
	check(not controller.validate_dispatch(car).is_empty(),"changing cars while waiting blocks dispatch")
	car.vehicle_id="queue_car"
	car.profile="desert_mirage"
	check(not controller.validate_dispatch(car).is_empty(),"changing mechanical profile blocks dispatch")
	car.profile="desert_faisca"
	controller.cancel_attempt("queue_cancelled")
	check(not controller.can_start("digo") and CHALLENGE.data(session.state.world_state).current.is_empty(),"cancel disarms both context and durable registration")
	check(CHALLENGE.status(session.state.world_state,"digo").stamps==0,"queue cancellation grants no proof")
	session.state.world_state={}
	var night := NIGHT_CONTROLLER.new()
	race.add_child(night)
	night.configure(race)
	NIGHT.begin(session.state.world_state,"digo",car.vehicle_id,car.archetype,car.profile,"street")
	night._armed=NIGHT.next_pass(session.state.world_state)
	car.set_meta("desert_parts",{})
	check(night.validate_dispatch(car).is_empty(),"night permits unchanged under-budget registration")
	car.set_meta("desert_parts",{"turbo":"turbo_large"})
	check(not night.validate_dispatch(car).is_empty(),"night rejects an over-budget change before spawning the opponent")
	car.set_meta("desert_parts",{"gearbox":"gear_short"})
	check(night.validate_dispatch(car).is_empty(),"within-budget adjustment before first pass remains allowed")
	NIGHT.record_finish(session.state.world_state,1,0,car.vehicle_id,car.profile,{},10,11,201)
	NIGHT.record_finish(session.state.world_state,1,1,car.vehicle_id,car.profile,{"gearbox":"gear_short"},16,17,402)
	night._armed=NIGHT.next_pass(session.state.world_state)
	check(night.validate_dispatch(car).is_empty(),"second 402 m dispatch accepts the identical preparation")
	car.set_meta("desert_parts",{})
	check(not night.validate_dispatch(car).is_empty(),"second 402 m dispatch rejects another build even under the cap")
	race.queue_free()
	session.queue_free()
	car.queue_free()
	await process_frame
	print("RIVAL_DISPATCH_DONE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
