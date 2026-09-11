extends SceneTree
class NavigationProbe extends "res://ResponderNavigation.gd":
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
	var probe := NavigationProbe.new()
	actor.movement_navigation = probe
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
	actor.queue_free()
	neighbor.queue_free()
	await process_frame
	print("PEDESTRIAN_AVOIDANCE_BUDGET_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)
