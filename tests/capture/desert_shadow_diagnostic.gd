extends SceneTree
## Pose fixa isolada. Posicionamentos explícitos e física de corpo desligada são só diagnóstico.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const CAPTURE := preload("res://tests/capture/DesertCanyonShadowDiagnostic.gd")
var world: Node3D
var output := ""

func _initialize() -> void:
	create_timer(95).timeout.connect(func(): _finish(3,{"error":"95s diagnostic watchdog"}))
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not "--no-save" in OS.get_cmdline_user_args() or not "--no-traffic" in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		_finish(2,{"error":"Requires rendered isolated no-save/no-traffic .NET"}); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-shadow-diagnostic")
	var arrival := Vector3(-835,.1,-1540)
	var snapshot := FIXTURE.full_snapshot(arrival,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[arrival.x,arrival.y,arrival.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): _finish(1,{"error":"Invalid isolated fixture"}); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.get("session")==null or not world.session.ready_for_play or world.production.store.path!=path:
		_finish(1,{"error":"Main did not load isolated checkpoint"}); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: _finish(1,{"error":"Native backend unavailable"}); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather._update()
	var road := Vector3(-860,.16,-1540)
	world.production.region.prepare_collision_at(road)
	var car: CharacterBody3D=world.production.spawn_vehicle("desert_bison",road,1.35)
	if car==null: _finish(1,{"error":"Bison public spawn not admitted"}); return
	var point := Vector3(-1055,HM.surface_height(Vector2(-1055,-1801))+.32,-1801)
	car.set_physics_process(false)
	car.global_position=point
	car.velocity=Vector3.ZERO
	car.set("speed",0.0)
	world.player.teleport(point+Vector3(3,0,0))
	world.player.set_physics_process(false)
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.camera.target=car
	world.camera.initialized=false
	await create_timer(2.0).timeout
	var ray_report := preload("res://tests/capture/DesertRayMeshDiagnostic.gd").capture_existing(world,output)
	var report: Dictionary
	if "--mesh-refinement-diagnostic" in OS.get_cmdline_user_args():
		report=await preload("res://tests/capture/DesertTerrainMeshComparison.gd").capture_existing(self,world,output)
	elif "--normal-bias-diagnostic" in OS.get_cmdline_user_args():
		report=await preload("res://tests/capture/DesertCanyonNormalBiasDiagnostic.gd").capture_existing(self,world,output)
	elif "--frustum-diagnostic" in OS.get_cmdline_user_args():
		report=await preload("res://tests/capture/DesertCanyonFrustumDiagnostic.gd").capture_existing(self,world,output)
	else:
		report=await CAPTURE.capture_existing(self,world,output)
	if "--bird-mesh-diagnostic" in OS.get_cmdline_user_args():
		var birds: Dictionary=await preload("res://tests/capture/DesertBirdMeshComparison.gd").capture_existing(self,world,output)
		report["bird_mesh_comparison"]=birds
		if birds.has("error"): report["error"]=birds.error
	report["ray_mesh_identification"]=ray_report
	report["fixed_diagnostic_pose"]=[point.x,point.y,point.z]
	report["body_physics_deliberately_disabled"]=true
	report["boarding_not_attempted"]=true
	_finish(1 if report.has("error") else 0,report)

func _finish(code: int,report: Dictionary) -> void:
	if not output.is_empty(): FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DESERT_SHADOW_DIAGNOSTIC_DONE ",output," code=",code)
	quit(code)
