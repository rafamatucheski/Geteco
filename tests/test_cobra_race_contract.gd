extends SceneTree
## Rules-only cases use a lightweight subject on the production road graph.
## Continuous input-driven driving is covered separately by test_cobra_race_player_car.
const CONTROLLER = preload("res://world/harbor/campaign/CobraCampaignController.gd")
const STATE = preload("res://world/harbor/campaign/CobraCampaignState.gd")
class Subject extends Node2D:
	var is_dead := false
	var is_arrested := false
	var is_in_dialogue := false
	var is_control_disabled := false
	var money := 0
class Car extends Node2D:
	var is_driven_by_player := true
	var health := 100
	var velocity := Vector2.ZERO
var errors: Array[String] = []
var checks := 0
var c: Node2D
var state: RefCounted
var player: Subject
var car: Car
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)
func start() -> void:
	if not c.active_id.is_empty():
		c.fail_mission("fixture resets attempt")
	car.health = 100
	car.velocity = Vector2.ZERO
	car.is_driven_by_player = true
	player.is_dead = false
	player.is_arrested = false
	player.is_control_disabled = false
	player.is_in_dialogue = false
	car.position = c.RACE_START
	car.rotation = -PI / 2.0
	check(c.start_mission("cobra_race"), "available attempt starts")
	check(c.interact() and c._race_started, "R prepares race with a working existing vehicle")
func release_start() -> void:
	c._tick_race(3.0)
	check(c._countdown == 0.0 and c.get_status().race_phase == "racing", "countdown releases race")
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var packed: Node = load("res://world/harbor/HarborPreview.tscn").instantiate()
	for id in ["RoadLayout", "CobraNeighborhood", "RoadNetwork"]:
		var child: Node = packed.get_node(id)
		packed.remove_child(child)
		child.owner = null
		world.add_child(child)
	packed.free()
	await physics_frame
	await physics_frame
	player = Subject.new()
	world.add_child(player)
	car = Car.new()
	world.add_child(car)
	car.add_to_group("vehicle")
	state = STATE.new()
	state.bind(null)
	state.data.completed["cobra_contact"] = true
	c = CONTROLLER.new()
	world.add_child(c)
	c.configure(player, state, null)
	c.set_physics_process(false)
	car.position = c.RACE_START
	check(c.start_mission("cobra_race"), "race may be accepted before preparing car")
	car.rotation = PI / 2.0
	c.interact()
	check(not c._race_started and c._last_message.contains("norte"), "wrong heading receives alignment instruction before timer starts")
	car.rotation = -PI / 2.0
	car.health = 0
	c.interact()
	check(not c._race_started, "broken vehicle cannot start the trial")
	car.health = 100
	car.velocity = Vector2(0,-60)
	c.interact()
	check(not c._race_started, "moving vehicle must stop before countdown")
	start()
	check(c.get_status().route.size() > 20, "route exposes the real road geometry")
	check(c._race_traffic._plans.size() == 8, "event routes both directions of all four quarters to the exit")
	check(c._race_traffic.global_position.distance_to(Vector2(7400,1700)) > 440.0, "incoming stop gate stays outside the junction reservation window so outbound cars can reserve")
	var arriving := Car.new()
	var incoming_lane := Path2D.new()
	world.add_child(incoming_lane)
	var incoming_follow := PathFollow2D.new()
	incoming_lane.add_child(incoming_follow)
	incoming_follow.add_child(arriving)
	arriving.is_driven_by_player = false
	incoming_lane.set_meta("traffic_direction", 1)
	arriving.set_meta("traffic_direction", -1) # stale spawn metadata must not decide
	check(c._race_traffic.should_stop_vehicle(arriving), "closure stops incoming ambient traffic")
	incoming_lane.set_meta("traffic_direction", -1)
	arriving.set_meta("traffic_direction", 1)
	check(not c._race_traffic.should_stop_vehicle(arriving), "closure keeps the current exit lane open despite stale spawn direction")
	incoming_lane.queue_free()
	check(c.get_status().route[0].distance_to(c.RACE_START) < 2.0, "route begins at the starting line")
	check(c.get_objective().contains("3"), "three-second countdown is visible")
	player.is_in_dialogue = true
	var countdown: float = c._countdown
	c._physics_process(2.0)
	check(c._countdown == countdown , "reading dialogue freezes countdown")
	player.is_in_dialogue = false
	car.position += Vector2(120,0)
	c._tick_race(0.1)
	check(c.active_id.is_empty() and not state.data.completed.get("cobra_race",false), "false start fails without completion")
	start()
	car.health = 0
	c._tick_race(0.1)
	check(c.active_id.is_empty(), "destroyed player car fails during countdown")
	start()
	car.is_driven_by_player = false
	c._tick_race(0.1)
	check(c.active_id.is_empty(), "leaving the registered car cancels the race")
	start()
	c.fail_mission("fixture tests preparation cleanup")
	car.is_driven_by_player = true
	check(c.start_mission("cobra_race"), "fresh preparation starts")
	var blocker := Car.new()
	world.add_child(blocker)
	blocker.is_driven_by_player = false
	blocker.add_to_group("vehicle")
	blocker.position = c.CENTER + Vector2(0, c.RACE_RADIUS)
	c._race_traffic._update_routes()
	c.interact()
	check(not c._race_started and c._race_traffic.remaining == 1, "occupied course cannot start a timer over physical blockers")
	var closure: Node = c._race_traffic
	closure._physics_process(91.0)
	check(c.active_id.is_empty() and not closure.active and not closure.is_in_group("traffic_control_zone"), "bounded preparation failure releases road closure")
	blocker.queue_free()
	await process_frame
	start()
	player.is_arrested = true
	player.is_control_disabled = true
	c._physics_process(0.1)
	check(c.active_id.is_empty(), "arrest fails before disabled-control guard can suspend recovery")
	start()
	player.is_dead = true
	c._physics_process(0.1)
	check(c.active_id.is_empty(), "death leaves the mission retryable")
	start()
	release_start()
	car.position += Vector2(400,0)
	c._tick_race(1.0/60.0)
	check(c.active_id.is_empty(), "teleport/region transition cannot skip the route")
	start()
	release_start()
	# A small excursion can be recovered; there is no instant invisible failure.
	car.position = c.CENTER + Vector2(-365,0)
	c._tick_race(0.05)
	check(not c.active_id.is_empty() and c.get_status().race_return_seconds > 0.0, "off-road excursion shows recovery countdown")
	car.position = c.RACE_START
	c._tick_race(0.05)
	check(not c.active_id.is_empty() and c.get_status().race_return_seconds == 0.0, "rejoining through same place clears warning")
	car.position = c.CENTER + Vector2(-365,0)
	c._tick_race(0.05)
	c._tick_race(4.0)
	check(c.active_id.is_empty(), "remaining outside route exhausts explicit grace time")
	start()
	release_start()
	for index in 100:
		var angle := PI - float(index+1)*0.018
		car.position = c.CENTER + Vector2(cos(angle),sin(angle))*c.RACE_RADIUS
		c._tick_race(1.0/60.0)
	check(c._checkpoint == 0, "reverse-direction quarter never counts as a checkpoint")
	start()
	release_start()
	c._tick_race(100.0)
	check(c.active_id.is_empty(), "displayed 100-second deadline expires without reward")
	start()
	release_start()
	for index in 380:
		if c.active_id.is_empty():
			break
		var angle := PI + float(index+1)*0.017
		car.position = c.CENTER + Vector2(cos(angle),sin(angle))*c.RACE_RADIUS
		c._tick_race(1.0/60.0)
	check(state.data.completed.get("cobra_race",false), "four ordered gates and full continuous lap complete race")
	check(player.money == 200, "successful race pays exactly once")
	check(not c.start_mission("cobra_race") and player.money == 200, "completed race cannot duplicate reward")
	check(c.get_status().route.is_empty() and c.get_status().target == Vector2.ZERO, "completion clears route and objective")
	print("COBRA RACE CONTRACT checks=%d failures=%d" % [checks, errors.size()])
	for sound in c.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	world.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
