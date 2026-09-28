extends SceneTree
## Túnel do canal no grafo de rotas: trânsito e polícia enxergam o túnel, o
## cruzamento com a quay_boulevard fica em níveis diferentes, e um carro do
## trânsito (motorista do jogo, não piloto de teste) desce, atravessa e sai.
## Rodar com --no-save.
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var production = world.production
	var graph = production.traffic_routes
	# 1. Grafo: nós do túnel no fundo, nenhum nó a −6 m ligado a rua de superfície.
	var deep := 0
	var tunnel_edges := 0
	for from in graph.edges:
		for edge in graph.edges[from]:
			if edge.id == TUNNEL.TRAFFIC_ID: tunnel_edges += 1
			var a: Vector3 = graph.vertices[edge.from]
			var b: Vector3 = graph.vertices[edge.to]
			if edge.id != TUNNEL.TRAFFIC_ID and (a.y < -1.0 or b.y < -1.0): check(false, "Rua %s ligada a nó do fundo do túnel" % edge.id)
			if edge.id == TUNNEL.TRAFFIC_ID and minf(a.y, b.y) < -5.5: deep += 1
	print("TUNNEL_TRAFFIC arestas=%d fundo=%d" % [tunnel_edges, deep])
	if "--debug" in OS.get_cmdline_user_args():
		for index in graph.vertices.size():
			var v: Vector3 = graph.vertices[index]
			if absf(v.z - TUNNEL.CENTER_Z) < 1.5 and (absf(v.x - 137.3) < 5 or absf(v.x - 347) < 5):
				var ids := []
				for edge in graph.edges[index]: ids.append("%s->%s" % [edge.id, str(graph.vertices[edge.to].snapped(Vector3.ONE*.1))])
				var incoming := 0
				for from in graph.edges:
					for edge in graph.edges[from]:
						if edge.to == index: incoming += 1
				print("NODE ", v.snapped(Vector3.ONE*.01), " in=", incoming, " out=", ids)
	check(tunnel_edges >= 4, "Túnel entrou no grafo nos dois sentidos")
	check(deep >= 2, "Grafo desce até o fundo do túnel")
	# 2. Rota pedida entre as margens escolhe o túnel.
	var start := Vector3(137.0, 0, 70.0)
	var finish := Vector3(347.0, 0, 56.0)
	var route: Curve3D = graph.route_between(start, finish)
	var lowest := 0.0
	if route != null:
		for i in route.point_count: lowest = minf(lowest, route.get_point_position(i).y)
	if route != null and "--debug" in OS.get_cmdline_user_args():
		var pts := []
		for i in route.point_count: pts.append(str(route.get_point_position(i).snapped(Vector3.ONE)))
		print("ROTA ", " ".join(pts))
	print("TUNNEL_TRAFFIC rota comprimento=%.0f fundo=%.2f" % [route.get_baked_length() if route else -1.0, lowest])
	check(route != null and lowest < -5.5, "Rota entre as margens passa pelo túnel")
	# 3. Carro do trânsito com essa rota atravessa sozinho.
	if route != null:
		world.player.teleport(Vector3(240, 0.2, 90))
		production.region.set_focus(Vector3(240, 0, 63))
		for i in 900:
			await process_frame
			if production.region.is_streaming_idle(): break
		var first: Vector3 = route.get_point_position(0)
		var ahead: Vector3 = (route.get_point_position(1) - first).normalized()
		var car = production.spawn_vehicle("sedan_classic", first + Vector3.UP * .12, atan2(-ahead.x, -ahead.z))
		car.vehicle_id = "tunnel_test_car"
		if "--trace" in OS.get_cmdline_user_args(): car.set_meta("debug_trace", true)
		car.route = route
		car.route_distance = 0.0
		car.traffic = true
		var reached_bottom := false
		var exited := false
		var max_x := -INF
		var start_ms := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start_ms < 70000:
			await physics_frame
			if not is_instance_valid(car): break
			world.player.global_position = Vector3(car.global_position.x, 0.2, 90)
			production.region.set_focus(car.global_position)
			max_x = maxf(max_x, car.global_position.x)
			if "--debug" in OS.get_cmdline_user_args() and Engine.get_physics_frames() % 60 == 0:
				var b = car.get("blocker")
				print("CAR x=%.1f y=%.2f speed=%.2f floor=%s blocker=%s route_d=%.1f throttle=%s jgap=%s held=%s exitb=%s yield=%s" % [car.global_position.x, car.global_position.y, float(car.get("speed")), car.is_on_floor(), (str(b.name)+" "+str(b.global_position.snapped(Vector3.ONE*.1))+" "+str(b.get_script().resource_path.get_file() if b.get_script() else "")+" meta="+str(b.get_meta_list()) if is_instance_valid(b) else "-"), float(car.get("route_distance")), str(car.get("throttle_input")), str(car.get("junction_gap")), str(car.get("_held_junction")), str(car.get("_exit_blocked")), str(car.get_meta("traffic_yield_state",""))])
			if car.global_position.y < -5.3: reached_bottom = true
			if reached_bottom and car.global_position.x > TUNNEL.E_TOP and car.global_position.y > -.5:
				exited = true
				break
		print("TUNNEL_TRAFFIC carro x_max=%.1f y=%.2f fundo=%s saiu=%s" % [max_x, car.global_position.y if is_instance_valid(car) else 0.0, reached_bottom, exited])
		check(reached_bottom, "Carro do trânsito desce até o fundo")
		check(exited, "Carro do trânsito sai pela boca leste no nível da rua")
	if "--debug" in OS.get_cmdline_user_args():
		var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		for v in production.vehicles:
			if not is_instance_valid(v) or not v.has_meta("awaiting_ground"): continue
			if not TUNNEL.in_roadway(v.global_position): continue
			var basis := Basis(Vector3.UP, v.rotation.y)
			var rays := []
			for x in [-v.half_width*.8, v.half_width*.8]:
				for z in [-v.half_length*.8, v.half_length*.8]:
					var support: Vector3 = v.position + basis*Vector3(x,0,z)
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(support+Vector3.UP*.6, support-Vector3.UP*.5, 1))
					rays.append("%.2f" % (hit.position.y - support.y) if not hit.is_empty() else "MISS")
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = v.shape.shape
			query.transform = Transform3D(basis, v.position + basis*v.shape.position)
			query.collision_mask = 7
			query.exclude = [v.get_rid()]
			var names := []
			for hit in space.intersect_shape(query, 6): names.append(str(hit.collider.name) + ("(rampa)" if hit.collider.has_meta("vehicle_ramp_structure") else ""))
			print("SUSP pos=%s floor=%.2f raios=%s formas=%s cold=%s" % [v.position.snapped(Vector3.ONE*.01), TUNNEL.floor_y(v.position.x), rays, names, str(production.session.cold.prepare_collision_at(v.position)) if production.session and production.session.cold else "-"])
	if "--debug" in OS.get_cmdline_user_args():
		for v in production.vehicles:
			if is_instance_valid(v) and TUNNEL.in_roadway(v.global_position) and absf(float(v.get("speed"))) < .3:
				var b = v.get("blocker")
				var contacts := []
				for ci in v.get_slide_collision_count():
					var c: KinematicCollision3D = v.get_slide_collision(ci)
					contacts.append("%s n=%s p=%s" % [str(c.get_collider().name), str(c.get_normal().snapped(Vector3.ONE*.01)), str(c.get_position().snapped(Vector3.ONE*.01))])
				var r: Curve3D = v.route
				print("DECISAO blocked=%s jwait=%s unjam=%s bypass=%s backoff=%s route_len=%.1f route_d=%.1f open=%s stuck=%s" % [str(v.get("blocked")), str(v.get("junction_wait")), str(v.get("unjam_time")), str(v.get("bypass_side")), str(v.get("backoff_time")), r.get_baked_length() if r else -1.0, float(v.route_distance), str(r.get_meta("traffic_open",false)) if r else "-", str(v.get("stuck_time"))])
				print("CONTATOS ", contacts, " vel=", v.velocity.snapped(Vector3.ONE*.01), " hvel=", v.get("horizontal_velocity"), " speed=", v.get("speed"))
				print("PARADO x=%.1f z=%.1f y=%.2f jgap=%s held=%s exitb=%s yield=%s blocker=%s" % [v.global_position.x, v.global_position.z, v.global_position.y, str(v.get("junction_gap")), str(v.get("_held_junction")), str(v.get("_exit_blocked")), str(v.get_meta("traffic_yield_state","")), (str(b.global_position.snapped(Vector3.ONE*.1)) if is_instance_valid(b) else "-")])
	print("TUNNEL_TRAFFIC failures=", failures)
	quit(0 if failures.is_empty() else 1)
