extends SceneTree

const ACTIVITY := preload("res://systems/PopulationActivity.gd")
var failures: Array[String] = []

class OutdoorPresentation extends Node:
	var active_updates := true
	func allows_population_sleep() -> bool: return true
	func set_population_active(active: bool) -> void: active_updates = active

class InteriorPresentation extends Node:
	pass

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var activity = ACTIVITY.new()
	var outdoor_actor := CharacterBody2D.new()
	outdoor_actor.position = Vector2(5000.0, 5000.0)
	world.add_child(outdoor_actor)
	var outdoor_view := OutdoorPresentation.new()
	world.add_child(outdoor_view)
	outdoor_actor.set_meta("interior_actor_presentation", outdoor_view)
	_check(not activity._pinned(outdoor_actor, Rect2(-100.0, -100.0, 200.0, 200.0)), "Outdoor station presentation remains eligible for zone sleep")
	activity.set_active(outdoor_actor, false)
	_check(outdoor_actor.process_mode == Node.PROCESS_MODE_DISABLED and not outdoor_view.active_updates, "Sleeping passenger also suspends its external presentation adapter")
	activity.set_active(outdoor_actor, true)
	_check(outdoor_actor.process_mode != Node.PROCESS_MODE_DISABLED and outdoor_view.active_updates, "Waking passenger restores actor and presentation adapter")
	var interior_actor := CharacterBody2D.new()
	interior_actor.position = Vector2(5000.0, 5000.0)
	world.add_child(interior_actor)
	var interior_view := InteriorPresentation.new()
	world.add_child(interior_view)
	interior_actor.set_meta("interior_actor_presentation", interior_view)
	_check(activity._pinned(interior_actor, Rect2(-100.0, -100.0, 200.0, 200.0)), "True interior presentation remains pinned")
	print("EXTERNAL_PRESENTATION_POPULATION_SLEEP failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
