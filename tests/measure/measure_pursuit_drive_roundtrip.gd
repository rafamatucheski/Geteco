extends "res://tests/test_pursuit_region_seam.gd"
## Perfil atual: setup inicial R3 declarado, depois somente Input/V1Handling.
## Retorno de ré, combate a pé e recuperação observada sem repor saúde/procura.
var output_dir := ""
var phase_name := ""
var phase_began := 0
var previous_draw := 0
var frame_samples: Array[float] = []
var physics_samples: Array[float] = []
var phases: Array[Dictionary] = []
var side_contacts: Array[Dictionary] = []
var total_side_contacts := 0
var regions_crossed: Array[Dictionary] = []
var npc_shots := 0
var player_shots := 0
var phase_distance := 0.0
var peak_units := 0
var min_population := 1000000
var max_step := 0.0
var sampled_handling := 0
var finishing := false

func _release_input() -> void:
	super._release_input()
	for action in ["accelerate", "brake", "fire"]: Input.action_release(action)

func _process(_delta: float) -> bool:
	if phase_name.is_empty(): return false
	var now := Time.get_ticks_usec()
	if previous_draw > 0: frame_samples.append(float(now-previous_draw)/1000.0)
	previous_draw = now
	physics_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	if is_instance_valid(world):
		peak_units = maxi(peak_units, world.dispatch.units.size())
		min_population = mini(min_population, world.people.size())
	return false

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"frames": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += value
	return {"frames": sorted.size(), "seconds": total/1000.0, "fps": sorted.size()*1000.0/total, "p50_ms": sorted[int((sorted.size()-1)*.50)], "p95_ms": sorted[int((sorted.size()-1)*.95)], "p99_ms": sorted[int((sorted.size()-1)*.99)], "max_ms": sorted[-1], "over_33_3_ms": sorted.filter(func(v): return v>33.3).size(), "over_66_7_ms": sorted.filter(func(v): return v>66.7).size()}

func _begin(name: String) -> void:
	phase_name = name
	phase_began = Time.get_ticks_usec()
	previous_draw = 0
	frame_samples.clear()
	physics_samples.clear()
	phase_distance = 0.0
	peak_units = 0
	min_population = world.people.size()
	print("PILOT_PHASE ", name, " position=",car.global_position," health=",world.gameplay.health)

func _end() -> void:
	if phase_name.is_empty(): return
	var observation := {"phase": phase_name, "seconds": float(Time.get_ticks_usec()-phase_began)/1000000.0, "frames": _stats(frame_samples), "physics": _stats(physics_samples), "frame_ms": frame_samples.duplicate(), "distance_m": phase_distance, "peak_dispatch_units": peak_units, "min_population": min_population, "cars": world.production.vehicles.size(), "stars":world.gameplay.stars, "health": world.gameplay.health, "car_health":car.health,"position":str(car.global_position)}
	phases.append(observation)
	print("PILOT_PHASE_END ", JSON.stringify(observation.duplicate().merged({"frame_ms": []}, true)))
	phase_name = ""

func _alive() -> bool:
	return world.gameplay.health > 0 and car.health > 0 and not world.session.modal

func _step_observation(previous: Vector3) -> void:
	var step := car.global_position.distance_to(previous)
	phase_distance += step
	max_step = maxf(max_step,step)
	sampled_handling += int(car._handling_frame)
	for index in car.get_slide_collision_count():
		var contact := car.get_slide_collision(index)
		if absf(contact.get_normal().y) > .65: continue
		total_side_contacts += 1
		if side_contacts.size() >= 30: continue
		var collider := contact.get_collider()
		side_contacts.append({"phase":phase_name,"speed":car.speed,"position":str(contact.get_position()),"normal":str(contact.get_normal()),"collider":str(collider.get_path()) if collider is Node and collider.is_inside_tree() else str(collider)})

func _steer(target: Vector3, reverse: bool, limit: float) -> void:
	_release_input()
	var direction := target-car.global_position
	direction.y = 0
	if reverse: direction = -direction
	var desired := atan2(-direction.x,-direction.z)
	var diff := angle_difference(car.rotation.y,desired)
	var turn := clampf(-diff*2.5*( -1.0 if reverse else 1.0),-1.0,1.0)
	if absf(turn)>.015: Input.action_press("move_right" if turn>0 else "move_left",absf(turn))
	if reverse:
		if car.speed > -limit: Input.action_press("brake")
	else:
		if car.speed < limit: Input.action_press("accelerate")

func _drive_leg(name: String, goal_x: float, reverse: bool) -> bool:
	_begin(name)
	var deadline := Time.get_ticks_msec()+60000
	var target_z := CONNECTION.CENTER_Z+1.9375
	var moved := 0.0
	while Time.get_ticks_msec()<deadline:
		var previous := car.global_position
		var reached := previous.x <= goal_x if reverse else previous.x >= goal_x
		if reached: break
		_steer(Vector3(previous.x+(-18.0 if reverse else 18.0),previous.y,target_z),reverse,5.0 if reverse else 6.0)
		await physics_frame
		_step_observation(previous)
		moved = phase_distance
		if not _alive() or not world.driving.occupied: break
	_release_input()
	_end()
	var region_id := "harbor" if reverse else "mountain"
	var reached := car.global_position.x <= goal_x if reverse else car.global_position.x >= goal_x
	check(reached and world.session.state.region_id==region_id,"piloto "+name+" chegou dirigindo: %.2f m"%moved)
	return reached and _alive() and world.driving.occupied

func _stop() -> bool:
	_release_input()
	Input.action_press("handbrake")
	var deadline := Time.get_ticks_msec()+5000
	while absf(car.speed)>.2 and Time.get_ticks_msec()<deadline: await physics_frame
	_release_input()
	return absf(car.speed)<=.2

func _contact() -> void:
	check(await _stop(),"parada por freio real antes de contato")
	_begin("authored_wall_contact")
	var old_contacts := total_side_contacts
	var goal := Vector3(car.global_position.x+4.0,car.global_position.y,CONNECTION.CENTER_Z+8.0)
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline and total_side_contacts==old_contacts and _alive():
		var previous := car.global_position
		_steer(goal,false,3.0)
		await physics_frame
		_step_observation(previous)
	_release_input()
	_end()
	check(total_side_contacts>old_contacts,"contato lateral real com colisão autoral, sem injetar evento")
	check(await _stop(),"freio recupera após contato autoral")

func _combat() -> void:
	check(await _stop(),"parada para desembarque físico")
	check(world.driving.leave(),"desembarque admitido por API real")
	var deadline := Time.get_ticks_msec()+6000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	check(not world.driving.occupied and world.gameplay.attack_allowed(),"combate começa a pé, com gate produtivo aberto")
	if world.driving.occupied or not world.gameplay.attack_allowed(): return
	world.session.state.grant_weapon("pistol")
	world.session.state.add_ammo("pistol",60)
	world.session.state.equip_weapon("pistol")
	var start: Vector3 = world.player.global_position
	var next_shot := Time.get_ticks_msec()
	var began := Time.get_ticks_msec()
	_begin("on_foot_combat_30s")
	while Time.get_ticks_msec()-began<30000 and _alive():
		_release_input()
		Input.action_press("move_left" if world.player.global_position.x>start.x else "move_right")
		if Time.get_ticks_msec()>=next_shot:
			next_shot = Time.get_ticks_msec()+2000
			var target: Vector3 = world.player.global_position+Vector3(0,0,-10)
			for unit in world.dispatch.units:
				for officer in unit.officers:
					if is_instance_valid(officer) and not officer.dead: target = officer.global_position
			if world.gameplay.fire_at(target): player_shots += 1
		await physics_frame
	_release_input()
	_end()
	check(player_shots>=10,"disparos produtivos efetivos >=10: %d"%player_shots)
	check(npc_shots>0,"resposta atirou por sinal npc_gunfire: %d"%npc_shots)
	check(_alive(),"sobreviveu sem repor saúde nem alterar dano")

func run() -> void:
	var isolated := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): output_dir=arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--isolated-save-root="): isolated=arg.trim_prefix("--isolated-save-root=")
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or isolated.is_empty() or output_dir.is_empty(): push_error("Piloto exige rendered/no-save/roots isolados");quit(2);return
	seed(20260930)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",isolated.path_join("pilot-progress.json"))
	world.set_meta("skip_arrival",true)
	world.set_meta("benchmark_trace",true)
	root.add_child(world)
	current_scene=world
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.people.size()>=world.production.requested_population: break
	check(world.session != null and world.session.ready_for_play and world.people.size()>=world.production.requested_population,"sessão real e densidade solicitada prontas")
	if world.session==null or not world.session.ready_for_play: _finish();return
	if not await _prepare_car(): _finish();return
	world.production.logical_region_changed.connect(func(previous,next): regions_crossed.append({"previous":previous,"next":next,"position":str(car.global_position),"phase":phase_name}))
	world.gameplay.npc_gunfire.connect(func(_origin,_direction,_actor):npc_shots+=1)
	world.dispatch.dispatch_event.connect(_dispatch_event)
	_begin("warmup_5s")
	deadline=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline: await physics_frame
	_end()
	# Estímulo explícito, admitido pelo sistema real. Nenhum diretor é desligado.
	world.gameplay.register_crime(45,car.global_position)
	if await _drive_leg("outbound_drive",CONNECTION.SEAM.x+160.0,false):
		await _contact()
		if _alive() and await _drive_leg("return_reverse_drive",CONNECTION.SEAM.x-35.0,true): await _combat()
	_begin("recovery_observation_15s")
	_release_input()
	deadline=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline: await physics_frame
	_end()
	check(sampled_handling>0 and not car.external_input,"direção usou V1Handling real")
	check(max_step<2.0,"nenhum salto de pose durante percurso: %.3f m"%max_step)
	check(regions_crossed.size()>=2,"mudanças lógicas ida e volta observadas")
	_finish()

func _finish() -> void:
	if finishing:return
	finishing=true
	_release_input()
	_end()
	var report := {"config":{"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d},"phases":phases,"contacts":side_contacts,"total_side_contacts":total_side_contacts,"regions":regions_crossed,"player_shots":player_shots,"npc_shots":npc_shots,"handling_frames":sampled_handling,"max_step_m":max_step,"routing_events":routing_events,"checks":checks,"failures":failures,"runtime_costs":world.get_meta("perf_costs",[]),"limits":"Perfil atual sem baseline equivalente. Setup inicial R3 excluído; percurso usa Input/V1Handling, volta de ré. Estímulo de procura e loadout explícitos; nenhum teleporte pós-setup/saúde reposta/sistema desligado. Recuperação observa sistemas vivos, sem forçar desaparecimento de procura. Cenas reais de Main; qualidade subjetiva não certificada."}
	var file:=FileAccess.open(output_dir.path_join("pilot.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PILOT_FINISHED failures=",failures.size())
	if is_instance_valid(world):world.free()
	quit(0 if failures.is_empty() else 1)
