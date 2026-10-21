extends "res://tests/tank_control/test_heavy_impacts.gd"
## All five cover meshes, including their smallest instances, break on car contact.
const COVER := preload("res://world/desert/DesertGroundCover.gd")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("DESERT_GROUND_COVER_CONTACT requires real MultiMesh transforms")
		quit(2)
		return
	create_timer(60).timeout.connect(func(): quit(3))
	world = Node3D.new()
	root.add_child(world)
	street = Street.new()
	world.add_child(street)
	var chunk := Node3D.new()
	world.add_child(chunk)
	var rect := Rect2(-400, -800, 48, 48)
	var state := COVER.begin(rect)
	var slices := 0
	while not state.committed:
		COVER.step(chunk, rect, state, func(_p): return 0.0, func(_p, _r): return true, 1000)
		slices += 1
	var items := FRAGILE.query(Vector3(rect.get_center().x, 0, rect.get_center().y), 40)
	var total := 0
	for visual in chunk.get_children(): total += visual.multimesh.instance_count
	check(items.size() == total, "every visible cover piece has exactly one indexed contact")
	check(slices > 1, "dense contact registration resumes across budgeted slices")
	for kind in COVER.KINDS:
		var candidates := items.filter(func(item): return str(item.visual.get_ref().name).ends_with("_" + kind))
		check(not candidates.is_empty(), "%s contacts exist" % kind)
		if candidates.is_empty(): continue
		candidates.sort_custom(func(a, b): return a.base.basis.get_scale().length_squared() < b.base.basis.get_scale().length_squared())
		var item: Dictionary = candidates[0]
		var count: int = item.multimesh.instance_count
		check(item.index < count, "%s index fits its batch" % item.kind)
		var registry: Dictionary = FRAGILE.cells
		FRAGILE.cells = {FRAGILE._key(item.point):[item]}
		var vehicle := car(1.0)
		vehicle.position = item.point + Vector3(0, 0, 6)
		CRUSH.set_planar(vehicle, Vector3.FORWARD * 20)
		var before := street.get_child_count()
		check(not FRAGILE.hit(item, .1, Vector3.FORWARD, street), "%s does not break below contact threshold" % kind)
		street._hit_props(vehicle, vehicle.horizontal_velocity, Vector3.FORWARD * 10)
		check(item.state == "down", "%s reacts to a passing car" % item.kind)
		var debris: Array = street.get_children().slice(before).filter(func(node): return node is RigidBody3D)
		check(debris.size() == 3, "%s fractures into three physical pieces like the beige rocks" % kind)
		if item.kind in ["desert_stone", "desert_gravel"] and debris.size() == 3:
			check(absf(debris[0].linear_velocity.x - debris[2].linear_velocity.x) > 4.0, "%s shards fan apart instead of moving as one rock" % kind)
		check(not FRAGILE.hit(item, 20, Vector3.FORWARD, street), "%s cannot break twice" % kind)
		for frame in 2: await physics_frame
		await RenderingServer.frame_post_draw
		check(is_zero_approx(item.multimesh.get_instance_transform(item.index).basis.determinant()), "%s original disappears" % kind)
		for body in debris:
			if item.kind in ["desert_stone", "desert_gravel"]:
				check(body.linear_velocity.dot(Vector3.FORWARD) > 8.0, "%s shards fly in the impact direction" % item.kind)
				check(body.linear_velocity.y > 3.0, "%s shards visibly lift off the ground" % item.kind)
				check(body.linear_velocity.length() < 22.0, "%s launch stays bounded" % item.kind)
			else:
				check(body.linear_velocity.length() < 4.0, "%s vegetation still falls near the car" % item.kind)
			# Sem o material da instância a moita virava uma pedra branca ao ser atropelada (19/10).
			for mesh in body.find_children("*", "MeshInstance3D", true, false):
				var material: Material = mesh.material_override
				check(material is StandardMaterial3D and not (material as StandardMaterial3D).albedo_color.is_equal_approx(Color.WHITE), "%s debris keeps its colour (%s)" % [item.kind, material])
		vehicle.free()
		# Finish the collision-grace callback before freeing the test bodies.
		await create_timer(.4, false, true).timeout
		for body in debris: body.free()
		FRAGILE.cells = registry
	chunk.free()
	check(FRAGILE.query(Vector3(rect.get_center().x, 0, rect.get_center().y), 40).is_empty(), "unloaded cover releases its contacts")
	# Collision-grace timers outlive the manually removed bodies.
	await create_timer(.4, false, true).timeout
	print("registrados em 48x48 m: ", items.size())
	print("DESERT_GROUND_COVER_CONTACT checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
