extends SceneTree
## Native room and actual player/visitor CharacterBody3D capsules. This runner
## verifies physical inventory, swept movement and usable floor separately
## from the rendered occlusion runner and the Main session walkthrough.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var checks := 0
var failures: Array[String] = []
var checked_solids: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("CELLAR_PHYSICS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("CELLAR_PHYSICS timeout"); quit(3))
	var definition := PLACES.get_definition("harbor_curitiba_cellar")
	if not check(not definition.is_empty(), "dedicated Harbor place exists"): finish(); return
	var stage := Node3D.new()
	root.add_child(stage)
	var room = PLACES.create_place("harbor_curitiba_cellar")
	stage.add_child(room)
	for frame in 3: await physics_frame
	check(room.model != null and room.model.get_child_count() > 0, "authored room instantiated")
	check(room.solid_bodies.size() >= 8, "full furniture and wall inventory has physics")
	var grouped := {}
	for mesh in room.model.find_children("*", "MeshInstance3D", true, false):
		var id := str(mesh.get_meta("interior_solid_id", ""))
		if id.is_empty(): continue
		var bounds: AABB = (room.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		if bounds.position.y > 2.1 or bounds.end.y < .06: continue
		grouped[id] = grouped[id].merge(bounds) if grouped.has(id) else bounds
	check(grouped.size() >= 7, "multiple independently classified furniture and wall volumes")
	for id: String in grouped:
		var visible: AABB = grouped[id]
		var covered := false
		for body in room.solid_bodies:
			if str(body.get_meta("interior_solid_id", "")) != id: continue
			var physical: AABB = body.get_meta("bounds")
			covered = physical.grow(.005).encloses(visible)
		check(covered, "visible solid covered by full blocking volume: " + id)
	for is_player in [true, false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.collision_mask = 1
		for frame in 3: await physics_frame
		var who := "Dante" if is_player else "visitor NPC"
		for point_name in ["spawn", "exit"]:
			var point: Vector3 = definition[point_name] + Vector3.UP * .04
			check(_clear(actor, room.to_global(point)), who + " full capsule clear at " + point_name)
			check(_supported(stage, room.to_global(point)), who + " supported floor at " + point_name)
		for station in room.interaction_points:
			var point: Vector3 = room.interaction_points[station] + Vector3.UP * .04
			check(_clear(actor, point), who + " interaction capsule clear: " + str(station))
			check(_supported(stage, point), who + " interaction floor supported: " + str(station))
		for reward in room.reward_points:
			check(_clear(actor, reward.position + Vector3.UP * .04), who + " reward does not spawn in furniture")
		var tested := 0
		for body in room.solid_bodies:
			var id := str(body.get_meta("interior_solid_id", ""))
			if id == "Floor": continue
			var bounds: AABB = body.get_meta("bounds")
			if bounds.end.y < .15: continue
			var center := bounds.get_center()
			var tested_sides := 0
			for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
				var extent := bounds.size.x * .5 if absf(direction.x) > .5 else bounds.size.z * .5
				var start := Vector3(center.x, .04, center.z) + direction * (extent + .85)
				if absf(start.x) > definition.size.x * .5 - .35 or absf(start.z) > definition.size.y * .5 - .35: continue
				if not _clear(actor, room.to_global(start)): continue
				var from := actor.global_transform
				from.origin = room.to_global(start)
				check(actor.test_move(from, -direction * (extent * 2 + 1.7)), who + " long sweep blocks " + id + " side " + str(direction))
				tested_sides += 1
			if tested_sides > 0:
				tested += 1
				if is_player: checked_solids.append(id)
		check(tested >= 7, who + " verifies at least seven accessible solid boundaries")
		actor.free()
	stage.free()
	await process_frame
	finish()

func _clear(actor: CharacterBody3D, point: Vector3) -> bool:
	var from := actor.global_transform
	from.origin = point
	return not actor.test_move(from, Vector3.UP * .001)

func _supported(stage: Node3D, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .10, point - Vector3.UP * .35, 1)
	var hit := stage.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and absf(float(hit.position.y) - point.y) < .3 and hit.normal.y > .8

func finish() -> void:
	print("CELLAR_PHYSICS_RESULT ", JSON.stringify({"checks":checks, "failures":failures, "swept_solids":checked_solids}))
	quit(0 if failures.is_empty() else 1)
