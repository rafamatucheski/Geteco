extends SceneTree
## New imported pilots wear helmets and disappear when Dante takes the bike.
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	for id in ["bike_urban", "bike_sport", "bike_cruiser"]:
		var bike = preload("res://scripts/Vehicle.gd").new()
		bike.archetype = id
		bike.traffic = true
		world.add_child(bike)
		bike.set_physics_process(false)
		check(bike._motorcycle_rider_parts.size() == 1, id + " has one separate pilot")
		if bike._motorcycle_rider_parts.is_empty(): continue
		var pilot: Node3D = bike._motorcycle_rider_parts[0]
		check(pilot.visible and pilot.skeleton != null and not pilot.body_source.is_empty(), id + " has an imported traffic pilot")
		check(pilot.find_child("Acc_motorcycle_helmet",true,false) != null, id + " has a helmet attached to the head")
		for steering in [-.45,0.0,.45]:
			for pivot in bike.steer_pivots.values(): pivot.rotation.y = steering
			pilot._pose(0.0)
			var holds: Dictionary = bike.motorcycle_handholds()
			for i in 2:
				var hand: Vector3 = pilot.forearms[i].to_global(Vector3(0,-pilot._arm_measure(i).y,0))
				var gap := hand.distance_to(holds["Right" if i == 0 else "Left"].origin)
				check(gap < .12,id + " new pilot reaches turned handlebars gap=" + str(gap))
		bike.traffic = false
		bike.controlled = true
		check(not pilot.visible, id + " hides the original pilot on theft")
		bike.controlled = false
		check(not pilot.visible, id + " stays empty after dismount")
		for part in bike.visual.get_children():
			if part is MeshInstance3D and part != pilot:
				check(part.visible, id + " preserves chassis and wheels")
		bike.queue_free()
		await process_frame
		var parked = preload("res://scripts/Vehicle.gd").new()
		parked.archetype = id
		world.add_child(parked)
		parked.set_physics_process(false)
		check(parked._motorcycle_rider_parts.all(func(part): return not part.visible), id + " spawns parked without a fixed body")
		parked.queue_free()
		await process_frame
	var bodies := {}
	var helmets := {}
	for identity in 16:
		var rider := preload("res://assets/civilians/TrafficMotorcyclist.gd").create(world,identity)
		var repeat := preload("res://assets/civilians/TrafficMotorcyclist.gd").create(world,identity)
		check(rider.body_source == repeat.body_source and rider.body_accessories == repeat.body_accessories,"identity keeps the same body and accessories")
		bodies[rider.body_source] = true
		helmets[rider.body_accessories[0].color] = true
		rider.free()
		repeat.free()
	check(bodies.size() >= 4,"motorcyclists use varied imported bodies")
	check(helmets.size() >= 3,"motorcyclists use varied helmets")
	world.queue_free()
	await process_frame
	print("MOTORCYCLE_RIDER_VISIBILITY ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
