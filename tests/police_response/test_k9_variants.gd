extends "res://tests/police_response/test_air_k9.gd"
## Variant integration: rendering resources, physical fit and animated settling.
## Screenshots and rendered frame-time comparison remain separate validation.

const EXPECTED_SCALES := [1.0, 0.86, 1.08, 0.94]

func _body_collider(dog: Node) -> CollisionShape3D:
	for child in dog.get_children():
		if child is CollisionShape3D: return child
	return null

func _rig_ready(rig: Dictionary) -> bool:
	var legs: Array = rig.get("legs", [])
	if legs.size() != 4: return false
	for leg in legs:
		if not is_instance_valid(leg) or not leg is Node3D: return false
	for key in ["head", "jaw", "tail"]:
		if not is_instance_valid(rig.get(key)) or not rig.get(key) is Node3D: return false
	return true

func _shares_meshes(first: Node3D, second: Node3D) -> bool:
	var first_parts := first.find_children("*", "MeshInstance3D", true, false)
	var second_parts := second.find_children("*", "MeshInstance3D", true, false)
	if first_parts.is_empty() or first_parts.size() != second_parts.size(): return false
	for index in first_parts.size():
		var first_mesh := first_parts[index] as MeshInstance3D
		var second_mesh := second_parts[index] as MeshInstance3D
		if first_mesh.mesh == null or first_mesh.mesh != second_mesh.mesh: return false
	return true

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, "Ground", Vector3(0, -0.2, 0), Vector3(60, 0.4, 60))
	var wall := box(world, "VariantWall", Vector3(0, 1.0, -2.0), Vector3(32, 2.0, 0.2))
	var gameplay := Controller.new()
	world.add_child(gameplay)
	var director := DIRECTOR.new()
	director.gameplay = gameplay
	gameplay.add_child(director)
	director.set_physics_process(false)
	var handler := Handler.new()
	handler.position = Vector3(12, 0.05, 8)
	world.add_child(handler)
	await frames(2)
	var settled_reference := Vector3.ZERO
	for variant in EXPECTED_SCALES.size():
		var expected_scale: float = EXPECTED_SCALES[variant]
		var lane := -6.0 + float(variant) * 4.0
		# Mantém as posições livre/bloqueada em lados opostos da face real da parede.
		var front_offset: float = (DOG.BODY_CENTER.z - DOG.BODY_SIZE.z * 0.5) * expected_scale
		var clear_point := Vector3(lane, 0.05, -1.9 - front_offset + 0.08)
		var blocked_point := clear_point + Vector3.FORWARD * 0.16
		var spawn_fits: bool = director.dog_clear(clear_point, expected_scale) and not director.dog_clear(blocked_point, expected_scale)
		var dog := DOG.new()
		dog.appearance_variant = variant
		dog.director = director
		dog.handler = handler
		dog.position = Vector3(lane, 0.05, 1.4)
		world.add_child(dog)
		dog.set_physics_process(false)
		var duplicate := DOG.new()
		duplicate.appearance_variant = variant
		duplicate.position = Vector3(lane, 0.05, 8)
		world.add_child(duplicate)
		duplicate.set_physics_process(false)
		var collider := _body_collider(dog)
		var shape: BoxShape3D = collider.shape as BoxShape3D if collider != null else null
		var rig_and_size: bool = _rig_ready(dog._rig) and _rig_ready(duplicate._rig) and dog._rig.head != duplicate._rig.head
		rig_and_size = rig_and_size and is_equal_approx(dog.body_scale, expected_scale) and dog.scale.is_equal_approx(Vector3.ONE)
		rig_and_size = rig_and_size and dog.visual.scale.is_equal_approx(Vector3.ONE * expected_scale)
		rig_and_size = rig_and_size and shape != null and shape.size.is_equal_approx(DOG.BODY_SIZE * expected_scale)
		rig_and_size = rig_and_size and collider != null and collider.position.is_equal_approx(DOG.BODY_CENTER * expected_scale)
		check(rig_and_size and _shares_meshes(dog.visual, duplicate.visual), "variant %d has independent animation, matching physical size and reused meshes" % variant)
		duplicate.queue_free()
		await frames(2)
		var touched_wall := false
		var start_z: float = dog.position.z
		for frame in 90:
			# Move the real CharacterBody, without steering choosing a different lane.
			dog.velocity = Vector3(0, -1, -3)
			dog.move_and_slide()
			for collision_index in dog.get_slide_collision_count():
				touched_wall = touched_wall or dog.get_slide_collision(collision_index).get_collider() == wall
			await physics_frame
		var front_z: float = dog.global_position.z + front_offset
		check(spawn_fits and touched_wall and dog.position.z < start_z - 0.5 and front_z >= -1.93, "variant %d admits only fitting spawns and physically stops before the wall" % variant)
		dog.receive_damage(100.0)
		dog.set_physics_process(false)
		dog._animate_death(0.3)
		var progressive: bool = dog.visual.rotation.z > 0.0 and dog.visual.rotation.z < PI * 0.5
		dog._animate_death(0.6)
		var settled: Transform3D = dog.visual.transform
		# Encerrar a perseguição não pode reposicionar um cadáver assentado para dentro do chão.
		dog.begin_withdrawal()
		var normalized_settle: Vector3 = dog.visual.position / expected_scale
		if variant == 0: settled_reference = normalized_settle
		await frames(2)
		check(progressive and normalized_settle.is_equal_approx(settled_reference) and is_equal_approx(dog.visual.rotation.z, PI * 0.5) and dog.visual.transform.is_equal_approx(settled) and not dog.is_physics_processing(), "variant %d falls gradually, settles proportionally and stays still" % variant)
		dog.queue_free()
		await frames(2)
	world.queue_free()
	await process_frame
	print("K9_VARIANTS failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
