extends "res://tests/measure/measure_desert.gd"
## Antes/depois na mesma cena do Main, trabalhadores, frota, clima e chão. A única
## chave de diagnóstico é o trabalho opcional. Rode cada variante em sequência.
const JOB := preload("res://gameplay/mining/jobs/MiningYardJob.gd")

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--benchmark" not in OS.get_cmdline_user_args() or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		quit(2); return
	var disabled: bool="--without-job" in OS.get_cmdline_user_args()
	Engine.set_meta("mining_yard_job_disabled",disabled)
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("mining-job-baseline" if disabled else "mining-job-after")
	fingerprint=source_fingerprint()
	for filename in DirAccess.get_files_at("res://gameplay/mining/jobs"):
		if filename.ends_with(".gd"): fingerprint["res://gameplay/mining/jobs/"+filename]=FileAccess.get_sha256("res://gameplay/mining/jobs/"+filename)
	var point:=JOB.CONTACT+Vector3.UP*.08
	var snapshot:=FIXTURE.full_snapshot(point,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[point.x,point.y,point.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for frame in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path or world.production.save_invalid:
		quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: quit(1); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	# Equivalent active state also exercises the three-body delivery polling.
	JOB.STATE.begin(world.session.state.world_state)
	for hour in [.45,.9]:
		world.session.weather.time_of_day=hour
		world.session.weather._update()
		await create_timer(10).timeout
		await measure("quarry-day" if hour<.5 else "quarry-night")
	var valid:=fingerprint==source_fingerprint(fingerprint)
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"valid":valid,"job_disabled":disabled,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"scenarios":reports,"note":"Rendered Main .NET, real quarry and workers; 10s warmup + 30s samples per day/night. Compare both variants; does not certify loader route."},"\t"))
	print("MINING_JOB_MEASURE ",output," valid=",valid)
	quit(0 if valid else 1)
