extends Node2D
## The berth owns one coach; shopping continues after it returns to the harbor.
const Layout = preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd")
const Traveler = preload("res://world/mountain_pass/transit/MountainArrivalTraveler.gd")
const NAMES := ["ANA", "CAIO", "LIA", "RAUL", "MILA", "IVO", "NORA", "DAVI", "HELENA", "LUCAS"]
const COLORS := [Color("487c91"), Color("c97c45"), Color("794d83"), Color("47765e"), Color("c1ad83")]
var active_bus: Node2D
var travelers: Array[Node] = []
var pending: Array[Node] = []
var history: Array[Dictionary] = []
var trip_count := 0
var exchange_complete := true
var release_delay := 0.0
var arrival_clock := 0.0
var purchases := 0
var completed_rests := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("mountain_transit_passengers")

func mountain_point(point: Vector2) -> Vector2:
	return get_parent().get_parent().to_global(point)

func global_route(points: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points: result.append(mountain_point(point))
	return result

func receive_coach(coach: Node2D) -> bool:
	if is_instance_valid(active_bus): return active_bus == coach
	active_bus = coach
	trip_count += 1
	exchange_complete = false
	arrival_clock = 0.6
	release_delay = 0.0
	# Recycle people inside a chalet and corpses outside the player's view.
	# Dead travelers must not occupy the ten live passenger slots forever.
	var live_count := 0
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for traveler in travelers.duplicate():
		if not is_instance_valid(traveler):
			travelers.erase(traveler)
		elif traveler.routine == "inside_chalet" or (traveler.is_dead and _corpse_out_of_view(traveler, player)):
			travelers.erase(traveler)
			traveler.queue_free()
		elif not traveler.is_dead:
			live_count += 1
	var count := mini([5, 2, 4, 3][(trip_count - 1) % 4], maxi(0, 10 - live_count))
	var manifest := {"trip": trip_count, "expected": count, "alighted": 0, "winter_ready": 0, "shopping": 0}
	for index in count:
		var traveler := Traveler.new()
		traveler.name = "Trip%dTraveler%d" % [trip_count, index]
		traveler.resident_name = NAMES[(trip_count * 3 + index) % NAMES.size()]
		traveler.appearance_variant = trip_count * 7 + index
		traveler.coat_color = COLORS[(trip_count + index) % COLORS.size()]
		traveler.role = "visitor"
		traveler.winter_outfit = index % 2 == 0
		traveler.cabin_index = (trip_count + index) % 4
		traveler.trip_id = trip_count
		traveler.walk_speed = randf_range(29.0, 42.0)
		add_child(traveler)
		traveler.global_position = mountain_point(Layout.BUS_DOOR)
		traveler.go_inside("onboard")
		traveler.reached_destination.connect(_destination_reached)
		traveler.bench_rest_finished.connect(_rest_finished)
		travelers.append(traveler)
		pending.append(traveler)
		manifest["winter_ready" if traveler.winter_outfit else "shopping"] += 1
	history.append(manifest)
	if history.size() > 12: history.pop_front()
	return true

func _corpse_out_of_view(traveler: Node2D, player: Node2D) -> bool:
	if player != null and traveler.global_position.distance_to(player.global_position) <= 1100.0:
		return false
	if traveler.is_visible_in_tree():
		var screen_point := traveler.get_global_transform_with_canvas().origin
		if get_viewport().get_visible_rect().grow(100.0).has_point(screen_point):
			return false
	return true

func is_exchange_complete() -> bool:
	return exchange_complete

func release_coach(coach: Node2D) -> void:
	if coach == active_bus and exchange_complete:
		active_bus = null

func cancel_exchange(coach: Node2D) -> void:
	if active_bus != coach: return
	for traveler in pending:
		if is_instance_valid(traveler): traveler.walk_route(global_route(Layout.BUS_TO_PLAZA),"leaving_platform")
	pending.clear()
	exchange_complete = true
	active_bus = null

func _physics_process(delta: float) -> void:
	if is_instance_valid(active_bus) and not exchange_complete:
		arrival_clock -= delta
		if not pending.is_empty() and arrival_clock <= 0.0:
			var traveler: Node = pending.pop_front()
			traveler.walk_route(global_route(Layout.BUS_TO_PLAZA), "leaving_platform")
			history.back()["alighted"] += 1
			arrival_clock = randf_range(1.6, 2.7)
			release_delay = 2.0
		elif pending.is_empty():
			release_delay -= delta
			if release_delay <= 0.0: exchange_complete = true
	for traveler in travelers:
		if traveler.routine != "shopping" or traveler.is_dead: continue
		traveler.pause_left -= delta
		if traveler.pause_left <= 0.0:
			traveler.buy_winter_clothes()
			purchases += 1
			var route := global_route([Layout.SHOP_DOOR, Vector2(7790, -1590), Layout.PLAZA])
			traveler.walk_route(route, "returning_from_shop")

func _destination_reached(traveler: Node) -> void:
	match traveler.routine:
		"leaving_platform":
			if traveler.winter_outfit:
				_rest_before_chalet(traveler)
			else:
				traveler.walk_route(global_route(Layout.PLAZA_TO_SHOP), "walking_to_shop")
		"walking_to_shop":
			traveler.go_inside("shopping")
			traveler.pause_left = randf_range(3.0, 7.0)
		"returning_from_shop":
			_rest_before_chalet(traveler)
		"walking_to_chalet": traveler.go_inside("inside_chalet")

func _rest_before_chalet(traveler:Node) -> void:
	if traveler.request_bench_rest(240.0,"village"):
		traveler.routine="resting_before_chalet"
	else:
		traveler.walk_route(global_route(Layout.cabin_route(traveler.cabin_index)),"walking_to_chalet")

func _rest_finished(traveler:Node,completed:bool) -> void:
	if traveler.routine!="resting_before_chalet" or traveler.is_dead:return
	if completed:completed_rests+=1
	# Return to the plaza path after leaving the bench, then continue to the chalet.
	traveler.walk_route(global_route(Layout.cabin_route(traveler.cabin_index)),"walking_to_chalet")
