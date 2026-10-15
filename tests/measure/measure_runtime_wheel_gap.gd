extends SceneTree
# Em jogo: distância entre o fundo de cada pneu e a colisão do chão logo abaixo dele,
# para o carro inicial e para uma moto colocada ao lado.
func _initialize() -> void: run.call_deferred()

func _gap(world: Node, car: CharacterBody3D) -> void:
	var space := car.get_world_3d().direct_space_state
	for pivot in car.wheels:
		var low := INF
		for m in pivot.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = (m as MeshInstance3D).get_aabb()
			for i in 8:
				low = minf(low, ((m as Node3D).global_transform * box.get_endpoint(i)).y)
		var p: Vector3 = pivot.global_position
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0, 0xFFFFFFFF)
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		var ground: float = hit.position.y if not hit.is_empty() else NAN
		print("GAP %s roda@%s fundo=%.3f chao=%.3f folga=%.3f car.y=%.3f floor=%s" % [car.archetype, p.snappedf(.01), low, ground, low - ground, car.global_position.y, car.is_on_floor()])

func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var car: CharacterBody3D = world.driving.car
	var route: Curve3D = world.production.traffic_routes.route_near(car.position)
	var d := route.get_closest_offset(car.position)
	var pt := route.sample_baked(d, true)
	var dir := route.sample_baked(d + 1, true) - pt
	car.place(world.player.global_position + Vector3(4, .3, 0), 0.0)
	car.set_physics_process(true)
	for i in 240: await physics_frame
	var sp := car.get_world_3d().direct_space_state
	for off in [Vector3.ZERO, Vector3(8,0,0), Vector3(0,0,8)]:
		var o: Vector3 = car.global_position + off
		var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(o + Vector3.UP * 20.0, o + Vector3.DOWN * 20.0, 0xFFFFFFFF))
		print("GAP raio ", o.snappedf(.01), " -> ", r.get("position", "nada"), " ", r.get("collider", null))
	print("GAP physics_process=", car.is_physics_processing(), " proc_mode=", car.process_mode, " player=", world.player.global_position)
	_gap(world, car)
	var seen := {}
	for m in world.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree(): continue
		var bb: AABB = mi.global_transform * mi.get_aabb()
		if absf(bb.get_center().x - 170.0) > 12 or absf(bb.get_center().z - 110.8) > 12: continue
		if bb.size.x < 3 or bb.size.z < 3 or bb.size.y > 1.0: continue
		print("GAP malha ", mi.get_path().get_name(mi.get_path().get_name_count() - 1), " topo=%.3f base=%.3f tam=%s" % [bb.end.y, bb.position.y, bb.size.snappedf(.1)])
	world.free()
	await process_frame
	quit(0)
