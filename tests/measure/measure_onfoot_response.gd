extends "res://tests/measure/measure_pursuit_drive_roundtrip.gd"
## Caso complementar finito: spawn normal de Main, resposta natural, sem mover poses.
func run() -> void:
	var isolated := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): output_dir=arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--isolated-save-root="): isolated=arg.trim_prefix("--isolated-save-root=")
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or isolated.is_empty() or output_dir.is_empty(): push_error("Caso exige rendered/no-save/roots isolados");quit(2);return
	seed(20260930)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",isolated.path_join("onfoot-progress.json"))
	world.set_meta("skip_arrival",true)
	world.set_meta("benchmark_trace",true)
	root.add_child(world)
	current_scene=world
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.people.size()>=world.production.requested_population: break
	car=world.driving.car
	check(world.session != null and world.session.ready_for_play and world.people.size()>=world.production.requested_population,"Main pronto com densidade solicitada")
	check(is_instance_valid(car) and not world.driving.occupied and world.gameplay.attack_allowed(),"spawn normal permite combate a pé sem boarding/teleporte")
	if not is_instance_valid(car) or world.driving.occupied or not world.gameplay.attack_allowed(): _finish();return
	world.gameplay.npc_gunfire.connect(func(_origin,_direction,_actor):npc_shots+=1)
	world.dispatch.dispatch_event.connect(_dispatch_event)
	world.session.state.grant_weapon("pistol")
	world.session.state.add_ammo("pistol",60)
	world.session.state.equip_weapon("pistol")
	world.gameplay.register_crime(45,world.player.global_position)
	_begin("natural_response_admission")
	deadline=Time.get_ticks_msec()+45000
	var admitted:=false
	while Time.get_ticks_msec()<deadline and _alive():
		for unit in world.dispatch.units:
			for officer in unit.officers:
				if is_instance_valid(officer) and officer.is_inside_tree() and not officer.dead:admitted=true
		if admitted:break
		await physics_frame
	_end()
	check(admitted,"agente a pé admitido naturalmente antes da janela de combate")
	if not admitted or not _alive():_finish();return
	var start: Vector3=world.player.global_position
	var next_shot:=Time.get_ticks_msec()
	var began:=Time.get_ticks_msec()
	_begin("normal_spawn_onfoot_combat_30s")
	while Time.get_ticks_msec()-began<30000 and _alive():
		_release_input()
		Input.action_press("move_left" if world.player.global_position.x>start.x else "move_right")
		if Time.get_ticks_msec()>=next_shot:
			next_shot=Time.get_ticks_msec()+2000
			var target: Vector3=world.player.global_position+Vector3(0,0,-10)
			for unit in world.dispatch.units:
				for officer in unit.officers:
					if is_instance_valid(officer) and not officer.dead: target=officer.global_position
			if world.gameplay.fire_at(target):player_shots+=1
		await physics_frame
	_release_input()
	_end()
	check(player_shots>=10,"disparos produtivos efetivos >=10: %d"%player_shots)
	check(npc_shots>0,"resposta produtiva disparou: %d"%npc_shots)
	check(_alive(),"sobreviveu sem repor saúde/dano/procura")
	_begin("normal_spawn_recovery_15s")
	deadline=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:await physics_frame
	_end()
	_finish()

func _finish() -> void:
	super._finish()
	var path:=output_dir.path_join("pilot.json")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	report["limits"]="Perfil atual complementar no spawn normal de Main; nenhum teleporte/boarding/movimento imposto. Input move a pé; fire_at, crime e loadout usam APIs produtivas. Sem reposição de saúde/dano nem sistemas desligados. Recuperação observada 15s; não prova volta dirigida nem baseline/FPS aprovado. Qualidade subjetiva não certificada."
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
