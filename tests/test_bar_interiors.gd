extends SceneTree
## Native room physics; rendered presentation and Main transitions are separate gates.
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
const ACTOR = preload("res://scripts/Actor.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("BAR_INTERIORS " + label)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var receipts := {}
	for id in ["harbor_bar", "desert_bar"]:
		var definition: Dictionary = CATALOG.get_definition(id)
		check(not definition.is_empty(), id + " catalog registration")
		if definition.is_empty(): continue
		var room = CATALOG.create_place(id)
		stage.add_child(room)
		await physics_frame
		await physics_frame
		check(room.solid_bounds.size() >= 8, id + " physical furniture and walls")
		var points: Array[Vector3] = [definition.spawn, definition.exit]
		for resident in definition.get("npcs", []): points.append(resident.local_position)
		for reward in definition.get("rewards", []):
			check(not receipts.has(reward.id), id + " unique persistent reward receipt")
			receipts[reward.id] = true
			points.append(reward.local_position)
		for station in room.interaction_points:
			if str(station).begins_with("bar_"): points.append(room.to_local(room.interaction_points[station]))
		for player in [true, false]:
			var actor = ACTOR.new()
			actor.is_player = player
			actor.controlled_automatically = true
			stage.add_child(actor)
			actor.set_physics_process(false)
			await physics_frame
			var who := "Dante" if player else "NPC"
			for point in points:
				actor.position = point + Vector3.UP * .04
				check(not actor.test_move(actor.global_transform, Vector3.UP * .002), id + " " + who + " capsule clear " + str(point))
				var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .2, point - Vector3.UP * .35, 1)
				var hit := stage.get_world_3d().direct_space_state.intersect_ray(ray)
				check(not hit.is_empty() and absf(hit.position.y) < .1, id + " " + who + " floor support " + str(point))
			actor.position = definition.spawn + Vector3.UP * .04
			check(not actor.test_move(actor.global_transform, definition.exit - definition.spawn), id + " " + who + " spawn to exit unobstructed")
			var swept := 0
			for bounds in room.solid_bounds:
				var center: Vector3 = bounds.get_center()
				for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
					var half: float = bounds.size.x * .5 if absf(side.x) > .5 else bounds.size.z * .5
					var start: Vector3 = Vector3(center.x, .04, center.z) + side * (half + .6)
					if absf(start.x) > definition.size.x * .5 - .4 or absf(start.z) > definition.size.y * .5 - .4: continue
					if not room.is_floor_clear(start, .32): continue
					actor.position = start
					check(actor.test_move(actor.global_transform, -side * (half + 1.2)), id + " " + who + " swept body blocked by " + str(bounds))
					swept += 1
					break
			check(swept >= 8, id + " " + who + " reachable furniture/wall coverage")
			actor.free()
		room.set_active(false)
		check(not room.visible and room.process_mode == Node.PROCESS_MODE_DISABLED, id + " inactive lifecycle")
		room.free()
		await physics_frame
	check(receipts.size() == 2, "two independent persistent rewards")
	stage.free()
	print("BAR_INTERIORS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
