extends SceneTree
## Regression: presentation receives resolved motion even when move_and_slide stopped the attacker.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")

class QuietStreet extends "res://gameplay/street_physics/StreetPhysics.gd":
	func _ready() -> void:
		instance = self
		set_physics_process(false)
	func spawn_glass(_point: Vector3, _direction: Vector3) -> void:
		pass

class EventCar extends CharacterBody3D:
	var health := 100.0
	var max_health := 100.0
	var half_width := 1.0
	var half_length := 2.0
	var handling: Node
	var horizontal_velocity := Vector3.ZERO
	var speed := 0.0
	var traffic := false
	var presented := Vector3.INF
	var own_at_event := Vector3.INF
	var other_at_event := Vector3.INF
	func receive_impact(amount: float, _point: Vector3, source: Node = null, _closing := -1.0, _normal := Vector3.ZERO, presentation_velocity := Vector3.INF) -> void:
		presented = presentation_velocity
		own_at_event = horizontal_velocity
		other_at_event = source.horizontal_velocity
		health -= amount

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(35).timeout.connect(func(): push_error("PANEL_MOMENTUM timeout"); quit(3))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var street := QuietStreet.new()
	world.add_child(street)
	for width in [1.0, 1.6]:
		var attacker := EventCar.new()
		var target := EventCar.new()
		target.half_width = width
		world.add_child(attacker)
		world.add_child(target)
		target.position.z = -5.0
		# The sweep already stopped the attacker. Its incoming velocity remains separate.
		var incoming := Vector3(0, 0, -32)
		var target_before := Vector3(0, 0, -4)
		target.horizontal_velocity = target_before
		var mine := STREET._vehicle_mass(attacker)
		var theirs := STREET._vehicle_mass(target)
		street._stall_crash(attacker, target, Vector3.BACK, 28.0, Vector3(0, .6, -2), incoming)
		check(attacker.own_at_event == Vector3.ZERO and attacker.other_at_event == target_before, "attacker presentation precedes gameplay velocity " + str(width))
		check(target.own_at_event == target_before and target.other_at_event == Vector3.ZERO, "target presentation precedes gameplay velocity " + str(width))
		check(attacker.presented.is_equal_approx(attacker.horizontal_velocity), "attacker receives resolved motion " + str(width))
		check(target.presented.is_equal_approx(target.horizontal_velocity), "target receives resolved motion " + str(width))
		var before := incoming * mine + target_before * theirs
		var after := attacker.horizontal_velocity * mine + target.horizontal_velocity * theirs
		check(before.is_equal_approx(after), "planar momentum remains conserved " + str(width))
		check(attacker.health > 70 and target.health > 70, "presentation leaves capped gameplay damage " + str(width))
		attacker.free()
		target.free()
	for id in ["sport_coupe", "monaliza"]:
		var car := VEHICLE.new()
		car.archetype = id
		car.vehicle_id = "momentum-" + id
		world.add_child(car)
		car.set_physics_process(false)
		var resolved := Vector3(0, 0, -15)
		var front := Vector3(.15, .7, -car.half_length)
		car.receive_impact(10, front, null, 35.0, Vector3.BACK, resolved)
		car.receive_impact(10, front, null, 35.0, Vector3.BACK, resolved)
		var hood: RigidBody3D
		var bumper: RigidBody3D
		for fragment in get_nodes_in_group("vehicle_panel_debris"):
			if fragment.source_vehicle_id != car.vehicle_id: continue
			if fragment.panel_id == "hood": hood = fragment
			if fragment.panel_id == "bumper_front": bumper = fragment
		check(hood != null and bumper != null, id + " detaches front components")
		if hood != null:
			check(hood.linear_velocity.z < 0 and hood.linear_velocity.z > resolved.z, id + " hood inherits forward motion with relative rearward release")
			check(hood.linear_velocity.y > 0 and hood.linear_velocity.x > 0, id + " hood clears upward and toward contact side")
			check(hood.angular_velocity.x < 0, id + " hood rear edge turns upward")
		if bumper != null:
			check(bumper.linear_velocity.z < resolved.z and bumper.linear_velocity.y < 0, id + " front bumper falls out of owner")
		car.receive_impact(10, Vector3(.15,.7,car.half_length), null, 35.0, Vector3.FORWARD, resolved)
		var rear_found := false
		for fragment in get_nodes_in_group("vehicle_panel_debris"):
			if fragment.source_vehicle_id == car.vehicle_id and fragment.panel_id == "bumper_rear":
				rear_found = true
				check(fragment.linear_velocity.z > resolved.z and fragment.linear_velocity.y < 0, id + " rear bumper falls behind owner")
		check(rear_found, id + " detaches rear bumper")
		car.repair()
		car.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	print("VEHICLE_PANEL_MOMENTUM checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
