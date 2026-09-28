extends SceneTree
## Vértice: empilhadeiras dirigíveis presas ao pátio, operadores andando de
## frente, funcionários no escritório e bagunça sem bloquear os caminhos.
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("OK   " if ok else "FAIL ")+label)
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	var depot = world.session.urban_operations.cargo_handling.depot
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = 9.0/24
	world.player.teleport(depot.ORIGIN+Vector3(0,.1,60))
	world.production.region.set_focus(world.player.position)
	for i in 600:
		await physics_frame
		var ready := true
		for vehicle in depot.forklifts.vehicles: ready = ready and is_instance_valid(vehicle)
		if ready: break
	var yard := Rect2(-50,-30,100,108)
	for vehicle in depot.forklifts.vehicles:
		check(is_instance_valid(vehicle) and vehicle.archetype=="port_forklift","Empilhadeira dirigível estacionada no pátio")
		if not is_instance_valid(vehicle): continue
		var local: Vector3 = vehicle.global_position-depot.ORIGIN
		check(yard.has_point(Vector2(local.x,local.z)) and local.y>-.3 and local.y<1.0,"Empilhadeira nasce no chão, dentro da cerca")
		check(vehicle.get_meta("port_work_vehicle",false),"Empilhadeira não é recolhida pelo trânsito ambiente")
	# Operadores: contagem e frente do modelo acompanhando o deslocamento.
	var operators := 0
	for entry in depot.staff:
		if not entry.guard and not entry.office: operators += 1
	check(operators>=6,"Pelo menos seis operadores no pátio e galpão (%d)"%operators)
	check(depot.desk_staff.size()==2,"Dois funcionários sentados às mesas do escritório")
	var start_points := {}
	var backwards := {}
	var forwards := {}
	for entry in depot.staff:
		start_points[entry.actor] = entry.waypoint
		backwards[entry.actor] = 0
		forwards[entry.actor] = 0
	var previous := {}
	var changes := {}
	var travel := {}
	for frame in 1800:
		await physics_frame
		for entry in depot.staff:
			if entry.waypoint!=start_points[entry.actor]:
				changes[entry.actor] = changes.get(entry.actor,0)+1
				start_points[entry.actor] = entry.waypoint
		if frame%10: continue
		for entry in depot.staff:
			var npc = entry.actor
			var at: Vector3 = npc.global_position
			if previous.has(npc):
				var step: Vector3 = at-previous[npc]
				step.y = 0
				travel[npc] = travel.get(npc,0.0)+step.length()
				if step.length()>.08:
					var front: Vector3 = entry.model.global_basis.z
					front.y = 0
					if front.normalized().dot(step.normalized())>.5: forwards[npc] += 1
					elif front.normalized().dot(step.normalized())<-.5: backwards[npc] += 1
			previous[npc] = at
	for entry in depot.staff:
		var npc = entry.actor
		check(forwards[npc]>0 and backwards[npc]==0,"%s anda de frente (frente %d, ré %d)"%[npc.name,forwards[npc],backwards[npc]])
		check(changes.get(npc,0)>0 or travel.get(npc,0.0)>25.0,"%s percorre a rota sem travar"%npc.name)
		check(npc.global_position.y>-.1 and npc.global_position.y<.5,"%s continua no chão"%npc.name)
	# Portão: dirigida para fora, a empilhadeira para na linha do portão.
	var forklift = depot.forklifts.vehicles[1]
	if is_instance_valid(forklift):
		world.player.teleport(depot.ORIGIN+Vector3(20,.1,60))
		forklift.global_position = depot.ORIGIN+Vector3(0,.2,66)
		forklift.global_rotation = Vector3(0,0,0)
		forklift.rotation.y = PI
		forklift.controlled = true
		forklift.external_input = true
		forklift.brake_input = false
		forklift.set_physics_process(true)
		var furthest := -INF
		for frame in 600:
			forklift.throttle_input = 1.0
			forklift.steer_input = 0.0
			forklift.brake_input = false
			await physics_frame
			furthest = maxf(furthest,forklift.global_position.z-depot.ORIGIN.z)
		check(furthest>70,"Empilhadeira anda de verdade até o portão (z máx %.1f)"%furthest)
		check(furthest<depot.forklifts.GATE_STOP_Z+.6,"Empilhadeira não passa do portão (z máx %.1f)"%furthest)
		forklift.controlled = false
		forklift.external_input = false
	print("FALHAS: %d"%failures.size())
	quit(0 if failures.is_empty() else 1)
