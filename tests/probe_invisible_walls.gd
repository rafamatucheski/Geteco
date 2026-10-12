extends SceneTree
## Sonda: varre a região do paddock do Digo com raios e lista sólidos sem malha visível.
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
func _initialize() -> void: run.call_deferred()
func _has_visible_mesh(n: Node) -> bool:
	for c in n.get_children():
		if (c is MeshInstance3D and c.is_visible_in_tree()) or (c is MultiMeshInstance3D and c.is_visible_in_tree()): return true
		if c is CollisionObject3D: continue
		if _has_visible_mesh(c): return true
	return false
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	world.session.state.intro.stage = "complete"
	world.player.teleport(COURSE.ENTRY+Vector3.UP*.1)
	world.production.region.set_focus(COURSE.ENTRY)
	for i in 240: await physics_frame
	var area := Rect2(COURSE.BOUNDS).grow(40)
	var meshes: Array[AABB] = []
	var bodies: Array = []
	var stack: Array = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is MultiMeshInstance3D and n.is_visible_in_tree() and n.multimesh != null and n.multimesh.mesh != null:
			var mm: MultiMesh = n.multimesh
			var ma: AABB = mm.mesh.get_aabb()
			var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			for i in count:
				var ia: AABB = (n.global_transform * mm.get_instance_transform(i)) * ma
				if area.intersects(Rect2(ia.position.x,ia.position.z,ia.size.x,ia.size.z)): meshes.append(ia.grow(.6))
		elif n is MeshInstance3D and n.is_visible_in_tree() and n.mesh != null:
			var a: AABB = n.global_transform * n.get_aabb()
			if a.size.x < 35 and a.size.z < 35 and area.intersects(Rect2(a.position.x,a.position.z,a.size.x,a.size.z)): meshes.append(a.grow(.6))
		elif n is StaticBody3D and n.collision_layer != 0:
			bodies.append(n)
	var flagged := 0
	for b in bodies:
		for sh in b.get_children():
			if not (sh is CollisionShape3D) or sh.shape == null or sh.disabled: continue
			var dm: Mesh = sh.shape.get_debug_mesh()
			if dm == null: continue
			var box: AABB = sh.global_transform * dm.get_aabb()
			if not area.has_point(Vector2(box.get_center().x,box.get_center().z)): continue
			if box.size.x > 4.0 or box.size.z > 4.0:
				print("GRANDE ", b.get_path(), " ", sh.name, " centro=", box.get_center(), " tam=", box.size, " ", sh.shape.get_class())
			var covered := false
			for m in meshes:
				if m.intersects(box): covered = true; break
			if not covered:
				flagged += 1
				print("SEM_VISUAL ", b.get_path(), " ", sh.name, " centro=", box.get_center(), " tam=", box.size, " layer=", b.collision_layer)
	var seen := {}
	for b in bodies:
		for sh in b.get_children():
			if not (sh is CollisionShape3D) or sh.shape == null: continue
			var dm: Mesh = sh.shape.get_debug_mesh()
			if dm == null: continue
			var box: AABB = sh.global_transform * dm.get_aabb()
			var c := box.get_center()
			if Vector2(c.x,c.z).distance_to(Vector2(-224,-20)) > 70: continue
			if box.size.y < .3: continue
			var key := str(b.get_path()).get_slice("World3D/",1).rstrip("0123456789@")
			if key.contains("QuarryRock") or key.contains("CourseStakes") or key.contains("Woodland"): continue
			print("COL ",b.get_path()," ",sh.shape.get_class()," c=",c.snapped(Vector3.ONE*.1)," s=",box.size.snapped(Vector3.ONE*.1)," L=",b.collision_layer)
	print("PROBE_DONE ", flagged, " corpos=", bodies.size(), " malhas=", meshes.size())
	quit(0)
