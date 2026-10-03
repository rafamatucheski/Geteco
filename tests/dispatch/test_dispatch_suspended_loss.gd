extends "res://tests/dispatch/test_dispatch_lifecycle.gd"
## Real dispatch, distance suspension and child burn callbacks. The fixture
## moves only the observing player; it never resumes or ticks the unit by hand.
const BURN := preload("res://gameplay/BurningActor.gd")

func _suspended_loss(remove_body: bool) -> void:
	var label := "removed" if remove_body else "burned"
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var unit: RefCounted = await _wait_unit(bundle)
	check(unit != null, label + ": real dispatch created a unit")
	if unit == null:
		KIT.teardown(bundle)
		return
	var working: bool = await _wait_state(unit, "working", 2400)
	check(working and is_instance_valid(unit.crew), label + ": crew disembarked normally")
	if not working or not is_instance_valid(unit.crew):
		KIT.teardown(bundle)
		return
	var responder: CharacterBody3D = unit.crew
	check(controller.router._native != null, label + ": compiled C# router is active")
	var lost := {"count": 0}
	controller.dispatch_event.connect(func(event_name: String, data: Dictionary):
		if event_name == "crew_lost" and data.get("unit") == unit: lost.count += 1)
	bundle.player.global_position = Vector3(30, 0, 220)
	await _frames(5)
	check(unit.suspended and not responder.visible and responder.collision_layer == 0 and not responder.is_physics_processing(), label + ": distance suspends real crew")
	var body_position := responder.global_position
	if remove_body:
		responder.queue_free()
		await _frames(3)
		check(not is_instance_valid(responder), label + ": body was actually freed while suspended")
	else:
		var burn := BURN.new()
		burn.configure(responder, bundle.gameplay, null)
		responder.add_child(burn)
		for i in 180:
			await physics_frame
			if responder.dead: break
		check(responder.dead and responder.health <= 0.0, label + ": live burn child killed suspended crew")
		check(unit.suspended, label + ": unit remained suspended through death")
		check(responder.collision_layer == 0 and responder.collision_mask == 0, label + ": death disabled collision before resume")
	# An old corpse/freed position must not block resuming the surviving vehicle.
	# This small wall is separate from the parked vehicle's footprint.
	var wall := KIT.add_wall(bundle.scene, body_position + Vector3.UP * .85, Vector3(.65, 1.7, .65))
	await _frames(3)
	bundle.player.global_position = Vector3(30, 0, 10)
	await _frames(35)
	check(not unit.suspended, label + ": obsolete crew capsule does not block resume")
	wall.queue_free()
	await _frames(25)
	check(not unit.suspended, label + ": unit is resumed after removing the wall")
	check(lost.count == 1, label + ": crew loss handled exactly once after resume")
	check(not is_instance_valid(unit.crew), label + ": dead/freed crew ownership released")
	if not remove_body:
		check(is_instance_valid(responder) and responder.dead and responder.visible, label + ": corpse remains available and visible to mortician")
		check(responder.collision_layer == 0 and responder.collision_mask == 0, label + ": no living collision is restored on corpse")
		check(not responder.is_physics_processing(), label + ": dead crew physics remains disabled")
	KIT.teardown(bundle)
	await _frames(3)
	done(label)

func run() -> void:
	await _suspended_loss(false)
	await _suspended_loss(true)
	await _suspension_of_people()
	report("DISPATCH_SUSPENDED_LOSS", ["burned", "removed", "suspension_of_people"], 30)
