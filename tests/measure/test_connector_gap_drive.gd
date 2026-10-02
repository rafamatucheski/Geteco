extends "res://tests/measure/measure_pursuit_drive_roundtrip.gd"
## Quatro setups declarados; cada percurso posterior usa só Input/V1Handling.
var case_results:Array[Dictionary]=[]
func _setup_case(point:Vector3,yaw:float)->bool:
	_release_input()
	if world.driving.occupied:
		if not await _stop() or not world.driving.leave():return false
		while world.driving.is_body_transition_active():await physics_frame
	world.player.teleport(point+Vector3(0,0,4))
	world.production._update_physical_residency(point)
	for region in world.production.regions.values():region.prepare_collision_at(point)
	await frames(4)
	if not world.production.vehicle_position_clear(car,point,yaw):return false
	car.place(point,yaw)
	car.set_meta("region_id",CONNECTION.logical_region(point));car.set_meta("garage_place","")
	var door:=Vector3.INF
	for side in [-1,1]:
		var candidate:Vector3=car.to_global(Vector3(side*(car.half_width+.65),.05,.15))
		if world.session.position_clear(candidate):door=candidate;break
	if not door.is_finite():return false
	world.player.teleport(door)
	return await world.session.restore_garage_driver(car)
func _leg(name:String,goal_x:float,reverse:bool)->bool:
	_begin(name)
	var east:=goal_x>car.global_position.x
	var deadline:=Time.get_ticks_msec()+12000
	var begin_contacts:=total_side_contacts
	while Time.get_ticks_msec()<deadline and _alive():
		if (car.global_position.x>=goal_x if east else car.global_position.x<=goal_x):break
		_release_input()
		if reverse:
			if car.speed> -3.5:Input.action_press("brake")
		else:
			if car.speed<3.5:Input.action_press("accelerate")
		var previous:=car.global_position
		await physics_frame
		_step_observation(previous)
	_release_input()
	var reached:=car.global_position.x>=goal_x if east else car.global_position.x<=goal_x
	var result:Dictionary={"case":name,"reached":reached,"position":str(car.global_position),"yaw":car.rotation.y,"speed":car.speed,"distance":phase_distance,"side_contacts":total_side_contacts-begin_contacts,"on_floor":car.is_on_floor(),"owner":world.session.state.region_id}
	case_results.append(result)
	_end()
	check(reached and result.distance>15 and result.on_floor,name+" cruza fisicamente com piso intacto")
	return reached
func _gap_floor()->void:
	var excluded:Array[RID]=[]
	var found:=false
	for attempt in 8:
		var query:=PhysicsRayQueryParameters3D.create(Vector3(450,3,CONNECTION.CENTER_Z),Vector3(450,-1,CONNECTION.CENTER_Z),1,excluded)
		var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():break
		excluded.append(hit.rid)
		if str(hit.collider.get_path()).contains("HarborConnectorGapBody"):
			found=true
			check(absf(hit.position.y)<.001,"piso do gap fica coplanar com apoio viário, sem remover collider")
	check(found,"collider do preenchimento do gap continua presente")
func run()->void:
	var isolated:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):output_dir=arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--isolated-save-root="):isolated=arg.trim_prefix("--isolated-save-root=")
	if isolated.is_empty() or output_dir.is_empty() or "--no-save" not in OS.get_cmdline_user_args():push_error("Teste requer roots isolados/no-save");quit(2);return
	seed(20260930)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",isolated.path_join("gap-progress.json"))
	world.set_meta("skip_arrival",true);root.add_child(world);current_scene=world
	var deadline:=Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.people.size()>=world.production.requested_population:break
	check(world.session!=null and world.session.ready_for_play and world.people.size()>=world.production.requested_population,"Main real pronto com densidade normal")
	if world.session==null or not world.session.ready_for_play:_finish();return
	car=world.driving.car
	for spec in [
		{"name":"reverse_gap","x":CONNECTION.SEAM.x+10,"z":.35,"yaw":-PI*.5,"reverse":true,"goal":CONNECTION.SEAM.x-10},
		{"name":"forward_gap","x":CONNECTION.SEAM.x+10,"z":.35,"yaw":PI*.5,"reverse":false,"goal":CONNECTION.SEAM.x-10},
		{"name":"outbound_lane_roundtrip","x":CONNECTION.SEAM.x-10,"z":1.9375,"yaw":-PI*.5,"reverse":false,"goal":CONNECTION.SEAM.x+10},
		{"name":"inbound_lane","x":CONNECTION.SEAM.x+10,"z":-1.9375,"yaw":PI*.5,"reverse":false,"goal":CONNECTION.SEAM.x-10}]:
		var admitted:=await _setup_case(Vector3(spec.x,.12,CONNECTION.CENTER_Z+spec.z),spec.yaw)
		check(admitted,spec.name+" setup físico e boarding admitidos")
		if not admitted:break
		if spec.name=="reverse_gap":_gap_floor()
		var reached:=await _leg(spec.name,spec.goal,spec.reverse)
		if spec.name=="outbound_lane_roundtrip" and reached:
			check(await _stop(),"freio real para inverter percurso da faixa")
			await _leg("outbound_lane_continuous_return",CONNECTION.SEAM.x-10,true)
	check(sampled_handling>0 and not car.external_input,"todos percursos usam handling produtivo")
	check(max_step<.5,"passos físicos contínuos após setups: %.3f m"%max_step)
	_finish()
func _finish()->void:
	super._finish()
	var path:=output_dir.path_join("pilot.json")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	report.cases=case_results
	report.limits="Contrato físico em Main com quatro setups separados explícitos (posicionamento/boarding). Após cada setup, só Input/V1Handling; a ida-volta da faixa é contínua, sem reposicionamento. Densidade/áudio/física/diretores normais. Não é benchmark FPS nem prova de todas as faixas, veículos ou clima."
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
