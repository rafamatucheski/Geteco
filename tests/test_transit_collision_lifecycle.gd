extends SceneTree

class PassengerProbe extends "res://world/harbor/urban_transit/UrbanPassenger.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

class BusProbe extends CharacterBody2D:
	var sections: Array[CharacterBody2D] = []

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _run() -> void:
	var passenger := PassengerProbe.new()
	var bus := BusProbe.new()
	var trailer := CharacterBody2D.new()
	root.add_child(passenger)
	root.add_child(bus)
	root.add_child(trailer)
	bus.sections.append(trailer)
	passenger.allow_boarding(bus)
	passenger.allow_boarding(bus)
	check(passenger.boarding_bodies.size() == 2, "Repeated boarding keeps one exception per convoy body")
	check(bus.get_collision_exceptions().has(passenger) and trailer.get_collision_exceptions().has(passenger), "Boarding excludes passenger from both convoy bodies")
	passenger.queue_free()
	await process_frame
	check(bus.get_collision_exceptions().is_empty() and trailer.get_collision_exceptions().is_empty(), "Removed passenger leaves no stale collision exceptions in the convoy")
	passenger = PassengerProbe.new()
	root.add_child(passenger)
	passenger.allow_boarding(bus)
	trailer.queue_free()
	await process_frame
	check(passenger.get_collision_exceptions().size() == 1, "Removed trailer is detached from passenger collision exceptions")
	bus.sections.clear()
	bus.queue_free()
	await process_frame
	check(passenger.get_collision_exceptions().is_empty(), "Destroyed bus leaves no stale passenger collision exceptions")
	bus = BusProbe.new()
	root.add_child(bus)
	passenger.allow_boarding(bus)
	passenger.restore_collisions()
	check(passenger.get_collision_exceptions().is_empty() and bus.get_collision_exceptions().is_empty(), "Normal alighting restores both collision directions")
	passenger.allow_boarding(bus)
	check(bus.get_collision_exceptions().has(passenger), "Passenger can board again after restoration")
	var lane := Node2D.new()
	root.add_child(lane)
	bus.reparent(lane)
	check(bus.get_collision_exceptions().has(passenger) and passenger.get_collision_exceptions().has(bus), "Lane reparenting preserves boarding collision exceptions")
	passenger.free()
	check(bus.get_collision_exceptions().is_empty(), "Immediate removal also cleans convoy exceptions")
	bus.free()
	lane.free()
	var driver := CharacterBody2D.new()
	var motorcycle := CharacterBody2D.new()
	root.add_child(driver)
	root.add_child(motorcycle)
	preload("res://systems/CollisionExceptionLifetime.gd").add(driver, motorcycle)
	check(driver.get_collision_exceptions().has(motorcycle) and motorcycle.get_collision_exceptions().is_empty(), "One-way motorcycle fall exception preserves its original direction")
	motorcycle.free()
	check(driver.get_collision_exceptions().is_empty(), "Destroyed motorcycle cleans the surviving driver's exception")
	driver.free()
	print("TRANSIT_COLLISION_LIFECYCLE failures=", failures)
	quit(1 if failures else 0)
