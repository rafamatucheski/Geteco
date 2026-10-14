extends "res://tests/test_vehicle_doors.gd"
const CARJACKING := preload("res://gameplay/VehicleCarjacking.gd")
class TheftWorld extends Node3D:
	var player: CharacterBody3D
	var production: Node
	var people: Array = []

func run() -> void:
	stage = TheftWorld.new()
	root.add_child(stage)
	actor = ACTOR.new()
	actor.is_player = true
	stage.add_child(actor)
	stage.player = actor
	actor.set_physics_process(false)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80,.2,80)
	floor_shape.shape = box
	floor_body.position.y = -.1
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	await physics_frame
	for id in ["sedan_classic", "bike_sport", "bike_urban", "cargo_flatbed_truck", "route_city", "beach_buggy", "port_forklift"]:
		var car := spawn(id, PI if id == "sedan_classic" else PI * .5)
		car.finish_doors()
		var side := CARJACKING.driver_side(car)
		var point := CARJACKING.landing_point(stage,car,side)
		check(point.is_finite(), id + ": finds a supported, unobstructed landing")
		if not point.is_finite(): car.queue_free(); continue
		var victim := ACTOR.new()
		stage.add_child(victim)
		var theft := CARJACKING.new()
		theft.prepare(stage,car,victim,side,point,id.begins_with("bike_"))
		check(not victim.is_physics_processing() and victim.collision_layer == 0, id + ": holds driver AI until extraction")
		check(victim.global_position.distance_to(car.driver_seat_anchor()) < .01, id + ": driver starts in the seat")
		actor.teleport(car.driver_door_anchor(side))
		var body := BOARDING.new()
		stage.add_child(body)
		body.begin_entry(stage,car,actor,side,false,theft)
		body._motion.kill()
		body.set_process(false)
		check(not body._extracting and not theft.released, id + ": approach precedes forced removal")
		body.progress = body._approach if not body._layout.is_empty() else .22
		body._apply()
		body._begin_extraction()
		body._extraction_progress = .15
		body._apply()
		check(not theft.hit and victim.global_position.distance_to(car.driver_seat_anchor()) < .01, id + ": occupant stays seated before contact")
		body._extraction_progress = .55
		body._apply()
		check(theft.hit and not theft.released and not actor.seated, id + ": contact and pull happen before Dante occupies the seat")
		if CARJACKING.throw_enabled:
			# Arrastada pela porta na altura do banco: a raiz não sobe, então a cabeça não atravessa o teto.
			check(victim.global_position.y <= car.driver_seat_anchor().y + .02, id + ": dragged out low, without rising inside the cabin")
		body._finish_extraction()
		if CARJACKING.throw_enabled:
			check(theft.released and theft.thrown and victim.has_meta("street_flying"), id + ": thrown out and flying after the pull")
			for frame in 360:
				await physics_frame
				if not victim.has_meta("street_down"): break
			var flat := Vector3(victim.global_position.x - point.x, 0, victim.global_position.z - point.z)
			check(not victim.has_meta("street_down") and flat.length() < 3.0, id + ": falls near the checked landing and gets up (%.2f m)" % flat.length())
		else:
			check(theft.released and victim.global_position.distance_to(point) < .01, id + ": lands outside before boarding resumes")
		check(victim.collision_layer == 2 and victim.is_physics_processing(), id + ": restores collision and AI")
		victim.controlled_automatically = true
		victim.automatic_direction = Vector3.RIGHT
		for frame in 45: await physics_frame
		var model: Node3D = victim.visual.get_child(0)
		check(model.global_basis.z.normalized().dot(Vector3.RIGHT) > .95, id + ": displaced driver faces the direction of escape after a rotated vehicle")
		body.abort("test_cleanup")
		check(actor.visible and not actor.seated, id + ": cancellation restores Dante on foot")
		victim.queue_free()
		car.queue_free()
		await process_frame
	# Cancellation before contact must also release ownership of the held victim.
	var car := spawn("sedan_classic",.0)
	var victim := ACTOR.new()
	stage.add_child(victim)
	var theft := CARJACKING.new()
	var point := CARJACKING.landing_point(stage,car,-1)
	theft.prepare(stage,car,victim,-1,point)
	actor.teleport(car.driver_door_anchor(-1))
	var body := BOARDING.new()
	stage.add_child(body)
	body.begin_entry(stage,car,actor,-1,false,theft)
	check(body.reverse_entry_to_exit(), "occupied entry can be cancelled during approach")
	check(theft.released and victim.is_physics_processing() and actor.visible, "cancellation releases both bodies without dangling timers")
	# Removed vehicles must not strand their driver or leave disabled collision.
	car.free()
	theft.release()
	check(victim.collision_layer == 2, "release remains idempotent after vehicle removal")
	stage.free()
	print("VEHICLE_CARJACKING checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
