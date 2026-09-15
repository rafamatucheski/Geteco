extends SceneTree

## Regression for the quay/dock junction shown in the ambulance report. The
## production bi-articulated line must finish its turn instead of remaining
## across the only drivable entrance to the south-port incident road.

class TestClock extends Node:
	var time_of_day := 8.0 / 24.0
	var is_dark := false
	var weather_state := 0


class TestWorld extends Node2D:
	var weather: Node


class TestLife extends "res://world/harbor/HarborLife.gd":
	func _spawn_traffic(_network: Node2D) -> void:
		pass
	func _spawn_walkers() -> void:
		pass


var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures.append(label)


func _run() -> void:
	seed(510)
	var world := TestWorld.new()
	root.add_child(world)
	current_scene = world
	var clock := TestClock.new()
	clock.name = "TestClock"
	world.add_child(clock)
	world.weather = clock

	var layout := preload("res://world/harbor/HarborRoadLayout.gd").new()
	layout.name = "RoadLayout"
	world.add_child(layout)
	var district := preload("res://world/harbor/HarborDistrict.gd").new()
	district.name = "District"
	world.add_child(district)
	var network := preload("res://world/harbor/HarborRoadNetwork.gd").new()
	network.name = "RoadNetwork"
	network.provider_paths.assign([NodePath("../RoadLayout")])
	world.add_child(network)
	var rail := Node2D.new()
	rail.name = "FreightRail"
	world.add_child(rail)
	var life := TestLife.new()
	life.name = "Life"
	world.add_child(life)
	life.setup(network)
	life.set_process(false)
	var transit := preload("res://world/harbor/urban_transit/UrbanTransit.gd").new()
	transit.name = "UrbanTransit"
	world.add_child(transit)

	for frame in 240:
		if transit.ready_for_service:
			break
		await process_frame
	_check(transit.ready_for_service and transit.buses.size() == 2, "Production urban fleet starts on the Harbor road graph")
	if not transit.ready_for_service or transit.buses.is_empty():
		await _finish(world)
		return

	var bus: CharacterBody2D = transit.buses[0]
	var controller: Node = null
	for frame in 240:
		controller = bus._get_junction_traffic_controller()
		if controller != null and not controller._junctions.is_empty():
			break
		await process_frame
	_check(controller != null and not controller._junctions.is_empty(), "Junction controller is ready before the turn fixture starts")
	if controller == null or controller._junctions.is_empty():
		await _finish(world)
		return
	transit.set_physics_process(false)
	transit._exchanges.erase(bus)
	for stop in transit.stops:
		if stop.service_bus == bus:
			stop.service_bus = null
	for other in transit.buses:
		if other == bus:
			continue
		other.suspended = true
		other.collision_layer = 0
		for section in other.sections:
			section.collision_layer = 0

	var quay_stop: Node2D = transit.stops[5]
	var quay_lane: Path2D = quay_stop.lane
	var follow := bus.get_parent() as PathFollow2D
	follow.reparent(quay_lane, false)
	follow.loop = false
	follow.progress = quay_lane.curve.get_closest_offset(quay_lane.to_local(Vector2(3000, 1960)))
	follow.remove_meta("traffic_planned_connection_id")
	follow.remove_meta("traffic_planned_junction_index")
	bus.position = Vector2.ZERO
	bus.rotation = 0.0
	bus.current_stop = 5
	bus.next_stop = 0
	bus.dwelling = false
	bus.doors = 0.0
	bus.suspended = false
	bus.is_broken = false
	bus._lane_motion_speed = 70.0
	bus._last_lane_motion_contract = {}
	bus.block_wait_timer = 0.0
	controller.release_vehicle(bus.get_instance_id())
	bus._history_head = 0
	bus._history_count = 240
	for index in bus._history_count:
		bus.history[index] = bus.global_position - bus.global_transform.x * float(index) * 2.0
	bus._update_sections(0.0)
	await physics_frame
	await physics_frame

	var corner_lamp: Node2D = null
	for lamp in get_nodes_in_group("street_lamp"):
		if lamp is Node2D and lamp.global_position.distance_to(Vector2(2800, 2285)) < 2.0:
			corner_lamp = lamp
			break
	_check(corner_lamp != null, "Quay/dock corner lamp remains in the production fixture")

	var entered_dock := false
	var cleared_access := false
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 26000:
		await process_frame
		var active_follow := bus.get_parent() as PathFollow2D
		var active_lane := active_follow.get_parent() as Path2D if active_follow else null
		var road := String(active_lane.get_meta("traffic_road_id", "")).get_file() if active_lane else ""
		entered_dock = entered_dock or road == "dock_street"
		# The lead reaching Dock is not enough: at x=2860 both trailers can
		# still span the quay and the south-port mouth. Require the whole
		# production-length convoy to continue well beyond the turn.
		if entered_dock and bus.global_position.x < 2520.0:
			cleared_access = true
			break

	var final_follow := bus.get_parent() as PathFollow2D
	var final_lane := final_follow.get_parent() as Path2D if final_follow else null
	print("URBAN_BUS_EMERGENCY_ACCESS position=", bus.global_position,
		" lane=", String(final_lane.get_meta("traffic_road_id", "")) if final_lane else "none",
		" wait=", bus.block_wait_timer, " contract=", bus._last_lane_motion_contract)
	_check(entered_dock, "Bi-articulated bus completes the quay-to-dock turn")
	_check(cleared_access, "Bi-articulated bus clears the south-port emergency road mouth")
	await _finish(world)


func _finish(world: Node) -> void:
	world.queue_free()
	await process_frame
	print("URBAN_BUS_EMERGENCY_ACCESS failures=", failures)
	quit(0 if failures.is_empty() else 1)
