extends SceneTree
## The baked pilot must disappear when theft transfers a bike to Dante.
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
		check(bike._motorcycle_rider_parts.size() == 1, id + " has a separate batched pilot")
		if bike._motorcycle_rider_parts.is_empty(): continue
		var pilot: MeshInstance3D = bike._motorcycle_rider_parts[0]
		check(pilot.visible and pilot.get_aabb().size.y > .7, id + " has a complete traffic pilot")
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
	world.queue_free()
	await process_frame
	print("MOTORCYCLE_RIDER_VISIBILITY ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
