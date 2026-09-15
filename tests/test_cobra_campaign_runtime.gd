extends SceneTree
## Controller integration and finite encounter actors.
## Full bank/tow progression lives in test_first_favors; real driving in test_cobra_race_player_car.
## Subject is a collision fixture, NOT a claim of manual PlayerCar playtesting.
const CONTROLLER = preload("res://world/harbor/campaign/CobraCampaignController.gd")
const STATE = preload("res://world/harbor/campaign/CobraCampaignState.gd")
class Subject extends CharacterBody2D:
	var is_dead := false
	var is_in_dialogue := false
	var is_control_disabled := false
	var money := 0
	func take_damage(_amount: int, _attacker := false) -> void:
		pass
class Car extends CharacterBody2D:
	var is_driven_by_player := true
	func take_damage(_amount: int, _attacker := false) -> void:
		pass
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var packed: Node = load("res://world/harbor/HarborPreview.tscn").instantiate()
	for id in ["RoadLayout", "CobraNeighborhood", "RoadNetwork"]:
		var node: Node = packed.get_node(id)
		packed.remove_child(node)
		node.owner = null
		world.add_child(node)
	packed.free()
	var traffic = load("res://world/harbor/HarborLife.gd").HarborController.new()
	traffic.graph_source = world.get_node("RoadNetwork")
	world.add_child(traffic)
	await physics_frame
	await physics_frame
	var player := Subject.new()
	player.add_to_group("player")
	world.add_child(player)
	var state = STATE.new()
	state.bind(null)
	state.data.completed["primeiro_giro"] = true
	var controller = CONTROLLER.new()
	world.add_child(controller)
	var territory = load("res://world/harbor/cobras/CobraTerritory.gd").new()
	territory.configure(Rect2(6510,960,2010,1450),PackedVector2Array([Vector2(7220,1580),Vector2(7330,1350),Vector2(8150,1760)]))
	world.add_child(territory)
	controller.configure(player, state, territory)
	check(controller.start_mission("cobra_contact"), "contact starts")
	check(controller._contact == territory.guards[2], "contact is the existing physical workshop guard")
	controller._contact.take_damage(10000, false)
	await physics_frame
	await physics_frame
	check(controller.active_id.is_empty(), "dead contact cannot receive ghost dialogue")
	check(controller.start_mission("cobra_contact"), "explicit retry replaces dead contact")
	await physics_frame
	check(territory.guards.size() == 3 and controller._contact == territory.guards[2] and not controller._contact.is_dead, "retry preserves finite three-guard roster")
	check(not controller.interact(), "remote E cannot complete delivery")
	player.position = controller.WORKSHOP
	check(controller.interact() and controller.stage == 0, "contact requires available physical recovery service")
	check(controller.interact() and not controller.active_id.is_empty(), "repeated E cannot bypass the new tow objective")
	# This minimal combat world intentionally has no salvage yard. Its full
	# physical mission is exercised in test_first_favors; stage prerequisites
	# here so unrelated encounter regressions retain their isolated coverage.
	controller.fail_mission("fixture stages completed tow prerequisite")
	state.data.completed["cobra_contact"] = true
	state.data.cobra_access = 1
	player.money = 120
	controller._set_access(true)
	territory.report_aggression()
	check(int(state.data.cobra_access) == 0, "assault revokes persistent access, not just runtime permission")
	check(controller.get_status().target == Vector2.ZERO, "completed job removes old objective marker")
	check(state.get_status("cobra_race").available, "race is available immediately after prerequisite")
	check(controller.start_mission("cobra_race"), "race starts without waiting another day")
	player.position = controller.RACE_START
	controller.interact()
	check(not controller._race_started, "race requires actual driven vehicle")
	var car := Car.new()
	car.position = controller.RACE_START
	car.rotation = -PI/2.0
	car.add_to_group("vehicle")
	world.add_child(car)
	controller.interact()
	check(controller._race_started and controller.get_status().route.size() > 20, "time trial follows production lane geometry")
	for i in 20:
		await physics_frame
	check(controller._countdown > 0.0 and controller._race_elapsed == 0.0, "timer waits for the visible countdown")
	car.position += Vector2(120, 0)
	await physics_frame
	await physics_frame
	check(controller.active_id.is_empty(), "false start fails without completing ledger")
	# Retry uses real physics motion around the ordered circuit, not direct
	# checkpoint completion. This tests scoring, not production player handling.
	car.position = controller.RACE_START
	check(controller.start_mission("cobra_race"), "failed race can retry")
	controller.interact()
	var race_angle := PI
	var player_travel := 0.0
	var previous_car_position: Vector2 = car.position
	for frame in 1400:
		await physics_frame
		if controller.active_id.is_empty():
			break
		if controller._countdown > 0.0:
			continue
		race_angle += 200.0 / 300.0 / 60.0
		var next_point: Vector2 = controller.CENTER + Vector2(cos(race_angle), sin(race_angle)) * 300.0
		car.velocity = (next_point - car.position) * 60.0
		car.move_and_slide()
		player_travel += car.position.distance_to(previous_car_position)
		previous_car_position = car.position
	check(bool(state.data.completed.get("cobra_race", false)), "ordered physical lap wins the race")
	check(player_travel > 1800.0, "whole lap physically advances through ordered gates")
	check(int(traffic.get_telemetry_snapshot().get("invalid_lane_contracts", 0)) == 0, "time trial preserves canonical lane contracts")
	check(player.money == 320, "race pays once")
	car.queue_free()
	await process_frame
	state.rest_until_next_day()
	check(controller.start_mission("cobra_collection"), "collection starts")
	player.position = controller.RESIDENT
	controller.interact()
	check(controller._encounter.actors.size() == 2, "two real combat actors spawned")
	controller.interact()
	check(controller.active_id == "cobra_collection", "cannot bypass living opponents by E")
	for actor in controller._encounter.actors:
		actor.take_damage(10000, true)
	await physics_frame
	await physics_frame
	check(controller._encounter_complete, "actual actor deaths unlock resident debrief")
	controller.interact()
	check(controller.active_id.is_empty() and player.money == 570, "debrief completes once")
	state.rest_until_next_day()
	check(controller.start_mission("cobra_supply"), "supply unlocks next day")
	player.position = controller.SUPPLY
	controller.interact()
	player.is_dead = true
	await physics_frame
	await physics_frame
	check(controller.active_id.is_empty() and state.data.active_id == "", "death resets runtime and ledger")
	check(not bool(state.data.completed.get("cobra_supply", false)), "death never grants completion")
	player.is_dead = false
	check(controller.start_mission("cobra_supply"), "supply retries after hospital")
	controller.interact()
	for actor in controller._encounter.actors:
		actor.take_damage(10000, true)
	await physics_frame
	await physics_frame
	controller.interact()
	check(bool(state.data.completed.get("cobra_supply", false)), "supply requires clearing and recovering evidence")
	player.position = controller.RESIDENT
	check(controller.interact(), "optional resident conversation grants back-route advantage")
	check(not controller.interact(), "optional favor cannot be repeatedly claimed")
	state.rest_until_next_day()
	check(controller.start_mission("cobra_finale"), "finale starts only after prior mission/day")
	player.position = controller.WORKSHOP
	controller.interact()
	check(controller._encounter.actors.size() == 2, "neighbor assistance removes one final reinforcement")
	check(controller._encounter.actors[0].combat_role == "leader", "finale includes actual leader")
	for actor in controller._encounter.actors:
		actor.take_damage(10000, true)
	await physics_frame
	await physics_frame
	controller.interact()
	check(bool(state.data.defeated) and player.money == 1520, "finale closes arc and rewards exactly once")
	check(not controller.start_mission("cobra_finale"), "completed finale cannot repeat rewards")
	world.queue_free()
	await process_frame
	print("COBRA CAMPAIGN RUNTIME: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
