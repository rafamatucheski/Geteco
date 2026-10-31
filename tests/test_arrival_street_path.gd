extends SceneTree
## Rota física integrada da saída do terminal até o M8 e o pátio da oficina
## dele. Testa o apoio no chão e o movimento real do jogador, sem certificar FPS.
var failures: Array[String] = []
var checks := 0
var world

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func focus(point: Vector3) -> void:
	# O streaming de produção segue o jogador a cada tick de física; mantém o dono dele
	# no local amostrado em vez de brigar com ele usando um foco sintético.
	world.player.teleport(point+Vector3.UP*.08)
	world.production.region.set_focus(point)
	var deadline := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.production.region.is_streaming_idle(): break
	for i in 3: await physics_frame
	check(world.production.region.is_streaming_idle(), "route collision finished streaming at %s" % point)

func supported(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.5,point-Vector3.UP*.8,1)
	return not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func run() -> void:
	root.get_node("V2Launch").selected_path = "user://arrival-street-path-isolated.json"
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Arrival street path: startup unavailable"); world.free(); quit(1); return
	var session = world.session
	var arrival = session.arrival
	arrival.active = false
	world.player.input_locked = true
	world.player.set_physics_process(false)
	await focus(arrival.PARK)
	arrival._spawn_encounter()
	arrival.car.set_physics_process(false)
	var terminal_exit := Vector3(223,.08,153)
	check(session.position_clear(terminal_exit), "terminal street exit admits the whole player capsule")
	for point in [Vector3(223,0,153),Vector3(220,0,153),Vector3(217,0,153),Vector3(214,0,153),Vector3(211,0,155)]:
		check(supported(point), "terminal-to-road apron has real ground at %s" % point)
	world.player.teleport(terminal_exit)
	check(await arrival._walk(world.player,Vector3(214,.08,155),true), "real player crosses the dry public apron without going through a coastal rail")
	check(await arrival._walk(world.player,arrival.car.door_point(1)), "real player reaches the M8 passenger door with normal collisions")
	var route: Curve3D = arrival._build_route()
	check(route != null and route.get_baked_length() > 40, "tour uses a connected Harbor road route")
	if route != null:
		var distance := 0.0
		var last_cell := Vector2i(999999,999999)
		while distance <= route.get_baked_length():
			var point := route.sample_baked(distance)
			var cell := Vector2i(floori(point.x/32.0),floori(point.z/32.0))
			if cell != last_cell:
				await focus(point)
				last_cell = cell
			check(supported(point), "authored M8 route stays on a supported surface at %.1f m %s" % [distance,point])
			distance += 2.0
		var yard: Vector3 = world.maciota_place.tour_parking
		await focus(yard)
		var hull_query := PhysicsShapeQueryParameters3D.new()
		var hull := BoxShape3D.new()
		hull.size = Vector3(2.2,1.5,5.3)
		hull_query.shape = hull
		hull_query.collision_mask = 1
		for x in [178.0,174.0,170.0,166.0,162.0,158.0]:
			hull_query.transform = Transform3D(Basis(Vector3.UP,PI*.5),Vector3(x,1.0,111.0))
			check(world.get_world_3d().direct_space_state.intersect_shape(hull_query,1).is_empty(),"full M8 hull fits between the workshop frontage and FreightDepot at x=%.1f" % x)
		# Uma linha central livre ou um sensor da frente não prova que o canto traseiro na curva
		# passa livre do Depot. Varre o casco superior completo ao longo da curva autoral real.
		var bend_start := route.get_closest_offset(route.get_meta("court_access_start"))
		var turn_clear := true
		var sample := bend_start
		while sample <= route.get_baked_length():
			var point := route.sample_baked(sample,true)
			var tangent := route.sample_baked(minf(sample+.02,route.get_baked_length()),true)-route.sample_baked(maxf(bend_start,sample-.02),true)
			var yaw := atan2(-tangent.x,-tangent.z)
			hull_query.transform = Transform3D(Basis(Vector3.UP,yaw),point+Vector3.UP)
			var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(hull_query,8)
			if not hits.is_empty():
				turn_clear = false
				var paths: Array[String] = []
				for hit in hits: paths.append(str(hit.collider.get_path()))
				print("ARRIVAL_COURT_HULL_REJECT sample=",sample," position=",point," yaw=",yaw," solids=",paths)
				break
			sample += .2
		check(turn_clear,"full M8 turning hull clears frontage, fences and Depot throughout the approach")
		# O candidato anterior consumia quatro vagas de táxi vivas e o círculo de drift.
		# Os contratos originais deles agora continuam intactos ao lado da oficina realocada.
		await focus(preload("res://runtime/TaxiRank.gd").CENTER)
		for slot: Vector3 in preload("res://runtime/TaxiRank.gd").SLOTS:
			hull_query.transform = Transform3D(Basis(Vector3.UP,PI*.5),slot+Vector3.UP*.9)
			check(world.get_world_3d().direct_space_state.intersect_shape(hull_query,1).is_empty(),"original taxi bay remains outside all workshop solids at %s" % slot)
		var drift: Dictionary = preload("res://activities/ActivityDefinitions.gd").drifts("harbor").harbor_cold_storage
		var drift_query := PhysicsShapeQueryParameters3D.new()
		var circle := CylinderShape3D.new()
		circle.radius = float(drift.radius)/16.0
		circle.height = 2.0
		drift_query.shape = circle
		drift_query.collision_mask = 1
		drift_query.transform = Transform3D(Basis.IDENTITY,Vector3(drift.pos.x/16.0,1.4,drift.pos.y/16.0))
		var drift_hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(drift_query,64)
		var workshop_drift_hits: Array[Dictionary] = []
		for hit in drift_hits:
			var collider: Node = hit.collider
			var belongs_workshop: bool = world.maciota_place.is_ancestor_of(collider)
			print("ARRIVAL_DRIFT_SOLID path=",collider.get_path()," name=",collider.name," class=",collider.get_class()," position=",collider.global_position if collider is Node3D else null," shape=",hit.shape," belongs_workshop=",belongs_workshop," parent_class=",collider.get_parent().get_class())
			if belongs_workshop: workshop_drift_hits.append(hit)
		# O CanalTunnel existente se sobrepõe a este cilindro largo de atividade. Preserva
		# a geometria dele; esta realocação não pode acrescentar nenhum sólido de oficina ao drift.
		check(workshop_drift_hits.is_empty(),"relocated workshop adds no solid to the original warehouse drift circle")
		await focus(yard)
		check(route.sample_baked(route.get_baked_length()).distance_to(yard) < .02, "trip ends inside the service court instead of a traffic lane")
		check(session.position_clear(yard+Vector3(2,.08,0)) and session.position_clear(yard+Vector3(-2,.08,0)), "both M8 occupants have supported, full-capsule exits in the court")
		var entrance: Vector3 = world.maciota_place.entry_position
		check(session.position_clear(entrance+Vector3.UP*.08), "workshop entrance admits the whole player capsule")
		world.player.teleport(entrance+Vector3(0,.08,5))
		arrival.maciota.global_position = yard+Vector3(-2,.08,0)
		check(await arrival._walk(arrival.maciota,entrance+Vector3(0,0,2)), "real Maciota walks out of the court to the entrance without crossing walls or fences")
		var old_police := Vector3(1080.0/16,0,1950.0/16)
		check(world.maciota_place.entry_position.distance_to(old_police) > 80, "workshop is separated from the police district")
	world.free()
	await process_frame
	print("ARRIVAL_STREET_PATH checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
