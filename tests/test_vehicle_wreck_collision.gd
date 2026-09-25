extends SceneTree
## A carcaça precisa respeitar o piso durante todo o salto, inclusive inclinada.
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func local_bounds(car: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var box: AABB = (car.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	for slope in [0.0, 0.12]:
		var ground := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var plane := WorldBoundaryShape3D.new()
		var normal := Vector3(0, 1, slope).normalized()
		plane.plane = Plane(normal, 0)
		collider.shape = plane
		ground.add_child(collider)
		world.add_child(ground)
		for archetype in ["sport_coupe", "american_dump_truck"]:
			var car := VEHICLE.new()
			car.archetype = archetype
			car.position.y = 0.7 if slope > 0 else 0.04
			world.add_child(car)
			for frame in 30: await physics_frame
			var bounds := local_bounds(car)
			car.damage_look._rng.seed = 127
			car.receive_damage(car.max_health * 2)
			var lowest := INF
			var highest := -INF
			var initial_y: float = car.visual.global_position.y
			for frame in 360:
				await physics_frame
				for corner in 8:
					var point: Vector3 = car.visual.global_transform * bounds.get_endpoint(corner)
					lowest = minf(lowest, normal.dot(point))
				highest = maxf(highest, car.visual.global_position.y - initial_y)
			var label := "%s inclinação=%.2f" % [archetype, slope]
			check(lowest >= -0.025, label + ": nenhuma extremidade atravessa o piso (mínimo %.3f m)" % lowest)
			check(highest > 0.05, label + ": explosão ainda levanta o carro")
			var settled: Transform3D = car.visual.global_transform
			for frame in 30: await physics_frame
			check(car.visual.global_position.distance_to(settled.origin) < 0.025,
				label + ": carcaça repousa sem afundar e voltar")
			var wreck: RigidBody3D = car.damage_look._wreck_body
			check(wreck.sleeping, label + ": carcaça em repouso dorme na física")
			var query := PhysicsRayQueryParameters3D.create(
				car.to_global(bounds.get_center() + Vector3(bounds.size.x + 2, 0, 0)),
				car.to_global(bounds.get_center()), 4)
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			check(not hit.is_empty() and hit.collider == wreck, label + ": colisão acompanha a carcaça")
			print("WRECK_COLLISION ", label, " lowest=", lowest, " lift=", highest)
			car.repair()
			check(car.collision_layer == 4 and car.collision_mask == 7 and car.is_physics_processing(),
				label + ": reparo restaura física de condução")
			check(car.visual.position == Vector3.ZERO and not car.damage_look.wrecked,
				label + ": reparo restaura apresentação")
			await process_frame
			check(not is_instance_valid(wreck), label + ": reparo remove o corpo físico antigo")
			car.receive_damage(car.max_health * 2)
			for frame in 4: await physics_frame
			car.repair()
			check(car.collision_layer == 4 and car.is_physics_processing()
				and car.damage_look._wreck_body == null, label + ": reparo durante o salto encerra a carcaça")
			car.queue_free()
			await process_frame
		ground.queue_free()
		await physics_frame
	world.queue_free()
	await process_frame
	print("VEHICLE_WRECK_COLLISION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
