extends "res://tests/test_fragile_debris_physics.gd"
const PROPS = preload("res://gameplay/street_physics/FragileProps3D.gd")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rendered backend required for MultiMesh transforms")
		quit(2); return
	var director := Director.new()
	root.add_child(director)
	var chunk := Node3D.new()
	root.add_child(chunk)
	for kind in ["lamp", "signal_pole"]:
		for speed in [12.0, 30.0, 80.0]:
			var pole := MeshInstance3D.new()
			pole.mesh = CylinderMesh.new()
			chunk.add_child(pole)
			pole.position = Vector3(3, 0, 5)
			var body := StaticBody3D.new()
			pole.add_child(body)
			PROPS.register_node(kind, pole, chunk)
			var item: Dictionary = PROPS.query(pole.position, 1)[0]
			verify(not PROPS.hit(item, 3.0, Vector3.RIGHT, director), kind + ": low impact resists")
			verify(body.collision_layer == 1 and item.state == "standing", kind + ": low impact keeps collision")
			await physics_frame
			verify(PROPS.hit(item, speed, Vector3.RIGHT, director), kind + ": strong impact topples")
			verify(body.collision_layer == 0, kind + ": fallen collision releases car")
			verify(director.find_children("*", "RigidBody3D", true, false).is_empty(), kind + ": never launches debris")
			for frame in 65:
				await physics_frame
				verify(pole.position.is_equal_approx(Vector3(3, 0, 5)), kind + ": base stays anchored throughout fall")
			verify(absf(pole.basis.y.y) < 0.1, kind + ": settles horizontal without wobble interference")
			verify(not PROPS.hit(item, speed, Vector3.RIGHT, director), kind + ": repeat hit does not restart fall")
			if kind == "lamp":
				preload("res://gameplay/street_physics/LampRecovery3D.gd").restore(item)
				verify(item.state == "standing" and body.collision_layer == 1 and pole.basis.is_equal_approx(Basis.IDENTITY), "lamp recovery restores pose and collision")
			pole.free()
			PROPS.cells.clear()
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = CylinderMesh.new()
	batch.instance_count = 2
	var base := Transform3D(Basis.IDENTITY, Vector3(5, 0, 2))
	batch.set_instance_transform(0, base)
	batch.set_instance_transform(1, Transform3D.IDENTITY)
	var lens := MultiMesh.new()
	lens.transform_format = MultiMesh.TRANSFORM_3D
	lens.mesh = BoxMesh.new()
	lens.instance_count = 1
	var offset := Transform3D(Basis.IDENTITY, Vector3.UP * 3)
	lens.set_instance_transform(0, base * offset)
	PROPS.register_instance("signal_pole", batch, 0, chunk, [{"multimesh":lens, "index":0, "offset":offset}])
	var signal_item: Dictionary = PROPS.query(base.origin, 1)[0]
	verify(PROPS.hit(signal_item, 80, Vector3.RIGHT, director), "batched signal topples at highway speed")
	for frame in 65:
		await physics_frame
		var pose := batch.get_instance_transform(0)
		verify(pose.origin.is_equal_approx(base.origin), "batched signal base remains fixed")
		verify(lens.get_instance_transform(0).is_equal_approx(pose * offset), "signal lens follows pole")
	verify(batch.get_instance_transform(1).is_equal_approx(Transform3D.IDENTITY), "neighbor signal stays intact")
	PROPS.cells.clear()
	# City trash cans use instancing; exercise that production representation.
	var loose := MultiMesh.new()
	loose.transform_format = MultiMesh.TRANSFORM_3D
	loose.mesh = CylinderMesh.new()
	loose.instance_count = 1
	loose.set_instance_transform(0, Transform3D.IDENTITY)
	PROPS.register_instance("trash_can", loose, 0, chunk)
	verify(PROPS.hit(PROPS.query(Vector3.ZERO, 1)[0], 30.0, Vector3.RIGHT, director), "loose trash can yields")
	var debris := director.find_children("*", "RigidBody3D", true, false)
	verify(debris.size() == 2 and debris[0].linear_velocity.length() > 10, "light objects still fly with separate lid")
	PROPS.cells.clear()
	director.queue_free()
	chunk.queue_free()
	await process_frame
	await process_frame
	print("ANCHORED_POST_IMPACTS failures=", failures)
	quit(0 if failures.is_empty() else 1)
