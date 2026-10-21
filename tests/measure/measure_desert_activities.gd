extends "res://tests/measure/measure_desert.gd"
## Five production locations follow their authored anchors after relocation.
const VILLAGE_LAYOUT := preload("res://world/desert/DesertMoonVillage.gd")
const MINING_LAYOUT := preload("res://world/mining/MiningLayout.gd")
const NORTH_LAYOUT := preload("res://world/desert/north_pass/DesertNorthPassLayout.gd")
const WASH_COURSE := preload("res://activities/desert_wash/DesertWashCourse.gd")
const RELAY := preload("res://runtime/secret_travel/SecretTravel.gd")
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	seed(7102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-activities-measure")
	var arrival: Vector3=VILLAGE_LAYOUT.CENTER+Vector3(-12,.08,-56)
	var snapshot:=FIXTURE.full_snapshot(arrival,true)
	snapshot.region_id="desert"
	snapshot.campaign.aftermath={"call_complete":true}
	snapshot.world.pedestrian={"region":"desert","position":[arrival.x,arrival.y,arrival.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(2); return
	fingerprint=source_fingerprint()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.save_invalid: quit(2); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: quit(2); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	var cap: bool="--normal-cap" in OS.get_cmdline_user_args()
	Engine.max_fps=60 if cap else 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if cap else DisplayServer.VSYNC_DISABLED)
	for setup in [
		{"id":"santa-lua","point":VILLAGE_LAYOUT.CENTER+Vector3(-13,0,44)},
		{"id":"wash","point":WASH_COURSE.gate(0)},
		{"id":"mining-job","point":MINING_LAYOUT.CENTER+Vector3(-20,-28,0)},
		{"id":"north-rockfall","point":NORTH_LAYOUT.GATE+Vector3(0,0,20)},
		{"id":"secret-relay","point":RELAY.SITES.desert.point+Vector3(0,0,3)},
	]:
		world.production.region.set_focus(setup.point)
		world.production.region.prepare_collision_at(setup.point)
		for i in 3: await physics_frame
		var ray:=PhysicsRayQueryParameters3D.create(setup.point+Vector3.UP*100,setup.point-Vector3.UP*100,1)
		var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): push_error("No baseline ground "+setup.id); quit(2); return
		world.player.teleport(hit.position+Vector3.UP*.08)
		world.camera.initialized=false
		await create_timer(7).timeout
		await measure(setup.id)
	var end:=source_fingerprint(fingerprint)
	var report:={"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"resolution":str(root.size),"msaa":root.msaa_3d,"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"source_start":fingerprint,"source_end":end,"source_stable":end==fingerprint,"scenarios":reports,"baseline":not preload("res://runtime/desert/DesertActivitiesPolicy.gd").enabled(),"note":"Main .NET; live population; five fixed locations, 7s settling + 30s samples each. Fixture relocations do not validate travel. Baseline disables this content batch through the debug-only policy; no personal save."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DESERT_ACTIVITIES_MEASURE ",output," stable=",end==fingerprint)
	quit(0 if end==fingerprint else 1)

func source_fingerprint(reference: Dictionary = {}) -> Dictionary:
	var result:=super.source_fingerprint(reference)
	if not reference.is_empty(): return result
	result[get_script().resource_path]=FileAccess.get_sha256(get_script().resource_path)
	for directory in ["res://world/desert","res://runtime/desert","res://runtime/secret_travel","res://activities/desert_wash","res://gameplay/mining/jobs"]: _hash_tree(directory,result)
	return result
func _hash_tree(directory: String,result: Dictionary) -> void:
	for filename in DirAccess.get_files_at(directory):
		if filename.ends_with(".gd") or filename.ends_with(".gdshader"):
			var path:=directory.path_join(filename)
			result[path]=FileAccess.get_sha256(path)
	for child in DirAccess.get_directories_at(directory): _hash_tree(directory.path_join(child),result)
