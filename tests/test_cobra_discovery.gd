extends SceneTree

const VEHICLES = preload("res://world/harbor/cobras/CobraVehicles.gd")
const LEDGER = preload("res://world/harbor/campaign/CobraCampaignState.gd")
const DISCOVERY = preload("res://world/harbor/campaign/CobraDiscovery.gd")
const GARAGE = preload("res://world/harbor/interiors/HarborGarageInterior.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var vehicles := VEHICLES.new()
	vehicles.name = "CobraVehicles"
	vehicles.parking_positions = {"secret": Vector2(7050, 2280), "workshop": Vector2(8350, 1740)}
	world.add_child(vehicles)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	var ledger := LEDGER.new()
	ledger.bind(campaign)
	var adapter := DISCOVERY.new()
	world.add_child(adapter)
	adapter.configure(world, ledger)
	adapter.set_physics_process(false)
	var car = vehicles.secret_car
	car.set_physics_process(false)
	var count := get_nodes_in_group("vehicle").size()
	adapter.capture_snapshot()
	check(ledger.data.secret_owned.is_empty(), "Unvisited secret remains undiscovered")
	# Production car, with a deterministic ownership fixture rather than fake mesh.
	car.is_driven_by_player = true
	car.global_position = Vector2(7000, 2260)
	car.global_rotation = 0.3
	car.repaint_vehicle(Color("284d8c"))
	car.health = 63
	adapter.capture_snapshot()
	check(ledger.data.secret_owned.has(DISCOVERY.SECRET_ID), "Driving claims authored secret")
	car.is_driven_by_player = false
	adapter.capture_snapshot()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	car.global_position = Vector2(1000, 1000)
	car.repaint_vehicle(Color.WHITE)
	car.health = 10
	check(campaign.restore_from_save(saved), "Secret JSON campaign restore")
	adapter._physics_process(0.016)
	check(car.global_position.distance_to(Vector2(7000, 2260)) < 0.01, "Restored authored car position")
	check(absf(car.global_rotation - 0.3) < 0.001, "Restored rotation")
	check(car.paint_color.is_equal_approx(Color("284d8c")), "Paint persists")
	check(car.health == 63, "Health persists without collision effects")
	check(get_nodes_in_group("vehicle").size() == count and vehicles.secret_car == car, "No duplicate car on reload")
	car.global_position = Vector2(20000, 20000)
	adapter.capture_snapshot()
	check(ledger.data.secret_owned[DISCOVERY.SECRET_ID].position == [7000.0, 2260.0], "Interior does not overwrite outdoor parking")
	ledger.data.secret_owned[DISCOVERY.SECRET_ID].position = [20000, 20000]
	adapter.restore_snapshot()
	check(car.global_position == Vector2(7050, 2280), "Invalid saved interior pose returns to authored parking")
	var garage := GARAGE.new()
	garage.position = Vector2(20000, 20000)
	world.add_child(garage)
	car.global_position = garage.spawn_point.global_position
	adapter.capture_snapshot()
	var interior_pose: Vector2 = car.global_position
	saved = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	car.global_position = Vector2(7000, 2260)
	campaign.restore_from_save(saved)
	adapter._physics_process(0.016)
	check(car.global_position == interior_pose, "Real garage camera bounds admit legitimate interior vehicle save")
	check(get_nodes_in_group("vehicle").size() == count, "Interior restore still never clones vehicle")
	world.queue_free()
	await process_frame
	print("COBRA DISCOVERY: %d failure(s)" % failures)
	quit(1 if failures else 0)
