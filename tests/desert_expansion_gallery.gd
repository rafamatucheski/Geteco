extends "res://tests/desert_expansion_session.gd"
## Capturas reais do Main em streaming. A câmera de visão geral é diagnóstico, nunca afirmação de FPS.
func run() -> void:
	if not check(DisplayServer.get_name()!="headless" and "--no-save" not in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"rendered native gallery with isolated save"):
		finish(2); return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size=Vector2i(1280,720)
	folder=FIXTURE.output_dir("desert-expansion-gallery")
	var at:=Vector3(-1092,.08,-575)
	var snapshot:=FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	path=FIXTURE.write_fixture(folder,"checkpoint.json",snapshot)
	if not check(not path.is_empty(),"valid isolated gallery checkpoint"): finish(1); return
	old_launch=root.get_node("V2Launch").selected_path
	root.get_node("V2Launch").selected_path=path
	if not await load_world(): finish(1); return
	Engine.max_fps=60
	var records:=LAND.locations()+SITES.locations()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			var names:=argument.trim_prefix("--only=").split(",")
			records=records.filter(func(record): return str(record.id) in names)
	for record in records:
		var p: Vector3=record.position
		# Revisa a relíquia da aproximação real pelo chão; nunca põe o ator da fixture
		# sobre a carga da carroça ou o teto do destroço por um raio vindo de cima do centro.
		for site in SITES.secrets():
			if str(site.id)=="desert_relic_"+str(record.id): p=site.position+Vector3(0,0,3)
		# Evita pôr o ator dentro de um pilar ao examinar rochas altas.
		if record.get("kind","") in ["hoodoo","basalt","balanced_rock"]: p+=Vector3(0,0,9)
		await place(p)
		var deadline:=Time.get_ticks_msec()+15000
		while not world.production.region.is_streaming_idle() and Time.get_ticks_msec()<deadline: await physics_frame
		check(world.production.region.is_streaming_idle(),"dressing settled "+str(record.id))
		await create_timer(.8).timeout
		await photo(str(record.id)+"-gameplay")
		world.camera.set_process(false)
		var target: Vector3=record.get("camera_target",record.position)
		world.camera.global_position=target+Vector3(24,55,50)
		world.camera.look_at(target)
		world.camera.size=float(record.camera_size)
		world.camera.reset_physics_interpolation()
		await create_timer(.25).timeout
		await photo(str(record.id)+"-overview")
		world.camera.set_process(true)
		world.camera.initialized=false
	finish(0 if failures.is_empty() else 1)
