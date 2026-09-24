extends SceneTree
class NavigationProbe extends "res://emergency/ResponderNavigation.gd":
	var sweeps := 0
	func movement(_body: CharacterBody2D, _goal: Vector2, _speed: float, _delta: float) -> Vector2:
		return Vector2(40, 0)
	func clear_segment(_body: CharacterBody2D, _start: Vector2, _end: Vector2) -> bool:
		sweeps += 1
		return true

var failures := 0
func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var actor := AuthoredSidewalkPedestrian.new()
	actor.defer_presentation = true
	actor.configure_authored_route(PackedVector2Array([Vector2.ZERO, Vector2(300, 0)]), "budget")
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.position = Vector2.ZERO
	actor._ambient_physics_elapsed = 0.0
	actor._life_clock = 0.0
	actor._physics_process(1.0 / 60.0)
	check(is_zero_approx(actor._life_clock), "Authored ambient work must skip the first 60 Hz tick.")
	actor._physics_process(1.0 / 60.0)
	check(is_equal_approx(actor._life_clock, 1.0 / 30.0), "Authored ambient work must consume the accumulated 30 Hz step.")
	actor.is_scared = true
	var priority_clock := actor._life_clock
	actor._physics_process(1.0 / 60.0)
	check(is_equal_approx(actor._life_clock - priority_clock, 1.0 / 60.0), "Scared authored actors must remain at full physics cadence.")
	actor.is_scared = false
	var probe := NavigationProbe.new()
	actor.movement_navigation = probe
	# Measure social steering after the route's local waypoint is established.
	# Waypoint occupancy is checked once on selection, not on each steering tick.
	actor._local_route_goal = Vector2(300, 0)
	actor._local_target = Vector2(300, 0)
	var velocity := actor._navigate_towards(Vector2(300, 0), 48.0, 1.0 / 60.0)
	check(velocity == Vector2(40, 0), "Sem vizinho, preservar movimento validado pela navegação.")
	check(probe.sweeps == 0, "Sem desvio, não repetir três raycasts por pedestre/tick.")
	var neighbor := Node2D.new()
	neighbor.position = Vector2(12, 3)
	root.add_child(neighbor)
	actor._cached_neighbors = [neighbor]
	velocity = actor._navigate_towards(Vector2(300, 0), 48.0, 1.0 / 60.0)
	check(absf(velocity.y) > 0.0, "Vizinho próximo deve continuar causando desvio.")
	check(probe.sweeps == 1, "Direção alterada deve continuar verificando obstáculos.")
	var commuter := preload("res://world/harbor/urban_transit/UrbanPassenger.gd").new()
	commuter.defer_presentation = true
	root.add_child(commuter)
	commuter.position = Vector2.ZERO
	commuter.walk_route(PackedVector2Array([Vector2.ZERO, Vector2(100, 0)]), "arriving")
	commuter.set_physics_process(false)
	commuter._ambient_physics_elapsed = 0.0
	commuter._physics_process(1.0 / 60.0)
	check(commuter.waypoints.size() == 2, "Urban commuter waypoint work must skip the first ambient 60 Hz tick.")
	commuter._physics_process(1.0 / 60.0)
	check(commuter.waypoints.size() == 1, "Urban commuter waypoint work must consume the accumulated 30 Hz step.")
	commuter.is_scared = true
	commuter.position = Vector2(100, 0)
	commuter._physics_process(1.0 / 60.0)
	check(commuter.waypoints.is_empty(), "Scared urban commuters must resume full-rate waypoint work immediately.")
	actor.queue_free()
	commuter.queue_free()
	neighbor.queue_free()
	await process_frame
	print("PEDESTRIAN_AVOIDANCE_BUDGET_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)
