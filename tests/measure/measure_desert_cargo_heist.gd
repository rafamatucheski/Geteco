extends "res://tests/measure/measure_desert.gd"
## Diagnóstico renderizado de integração. FPS final exige export release/ReleaseBenchmark.
var heist: Node
var failures: Array[String] = []
var gunshots := 0
var cargo_frames: Array[Dictionary] = []
var observation_id := ""
var observation_due := 0

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Exige .NET renderizado e --no-save")
		quit(2)
		return
	seed(16102026)
	root.size = Vector2i(1280,720)
	var label := "review"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	output = FIXTURE.output_dir("desert-cargo-" + label)
	var point := Vector3(-700,.08,-1530)
	var snapshot := FIXTURE.full_snapshot(point,true)
	snapshot.campaign.aftermath.call_complete = true
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region":"desert","position":[point.x,point.y,point.z]}
	snapshot.world.time = 1.0/24.0
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	fingerprint = source_fingerprint()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.dispatch.router.nearest_edge(point)
	if world.dispatch.router._native == null or world.production.store.path != path:
		push_error("Sessão nativa isolada não carregou")
		quit(1)
		return
	heist = world.session.desert.heist
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.god_mode = true
	world.gameplay.npc_gunfire.connect(func(_origin: Vector3,_direction: Vector3,shooter: Node3D):
		if heist.guards.has(shooter): gunshots += 1)
	world.session.weather.time_of_day = 1.0/24.0
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather._update()
	await create_timer(10).timeout
	await observe("madrugada-trafego")
	var disabled := OS.get_environment("GETECO_DESERT_CARGO_HEIST") == "0"
	if not disabled:
		if not is_instance_valid(heist.truck):
			failures.append("Nenhuma carga real apareceu na estrada do sal")
		else:
			# Posicionamento diagnóstico explícito; não comprova perseguição/acesso rodoviário.
			var truck_point: Vector3 = heist.truck.global_position
			world.player.teleport(truck_point + Vector3(0,.08,12))
			world.gameplay.weapon_fired.emit("pistol",world.player.global_position)
	await create_timer(2).timeout
	await observe("interceptacao-combate")
	if not disabled:
		if heist.guards.filter(func(guard): return is_instance_valid(guard) and not guard.dead).size() != 2: failures.append("Interceptação não produziu exatamente dois guardas")
		if gunshots == 0: failures.append("Nenhum disparo real dos guardas foi observado")
	# Afastamento permite observar a política de retenção/limpeza sem aprovar deslocamento.
	world.player.teleport(Vector3(-700,.08,-1320))
	await create_timer(10).timeout
	await observe("afastamento-recuperacao")
	var stable := fingerprint == source_fingerprint(fingerprint)
	if not stable: failures.append("Fontes mudaram durante a captura")
	var result := {"valid":failures.is_empty(),"failures":failures,"build":"editor_diagnostic" if OS.has_feature("editor") else "export",
		"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),
		"max_fps":Engine.max_fps,"toggle":OS.get_environment("GETECO_DESERT_CARGO_HEIST"),"scenarios":reports,"cargo_frames":cargo_frames,
		"guard_shots":gunshots,"source_stable":stable,"source_sha256":fingerprint,
		"scope":"Main real, câmera comum, tráfego e despacho ativos, três janelas de 30s. Interceptação via sinal real com posicionamento diagnóstico e invencibilidade. Não certifica condução, entrega, abertura, áudio nem performance release."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DESERT_CARGO_REVIEW ",output," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func observe(id: String) -> void:
	observation_id = id
	observation_due = 0
	process_frame.connect(record_cargo)
	await measure(id)
	process_frame.disconnect(record_cargo)

func record_cargo() -> void:
	var now := Time.get_ticks_msec()
	if now < observation_due: return
	observation_due = now + 1000
	cargo_frames.append({"scenario":observation_id,"ms":now,"truck":str(heist.truck.global_position) if is_instance_valid(heist.truck) else "none",
		"guards":heist.guards.filter(func(guard): return is_instance_valid(guard)).size(),"shots":gunshots,"data":heist.data.duplicate(true)})

func source_fingerprint(reference: Dictionary = {}) -> Dictionary:
	var result := super.source_fingerprint(reference)
	if not reference.is_empty(): return result
	for filename in DirAccess.get_files_at("res://gameplay/desert_heist"):
		if filename.ends_with(".gd") or filename.ends_with(".gdshader"):
			var path := "res://gameplay/desert_heist/" + filename
			result[path] = FileAccess.get_sha256(path)
	result[get_script().resource_path] = FileAccess.get_sha256(get_script().resource_path)
	return result
