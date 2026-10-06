extends "res://tests/measure/measure.gd"
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	create_timer(180).timeout.connect(func(): quit(3))
	seed(6102026)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=")
	var folder:=FIXTURE.output_dir("desert-contracts-"+label)
	var point:=Vector3(270,.08,-756.8)
	var snapshot:=FIXTURE.full_snapshot(point,true)
	snapshot.campaign.aftermath={"call_complete":true}
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[point.x,point.y,point.z]}
	var path:=FIXTURE.write_fixture(folder,"save.json",snapshot)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.dispatch.router.nearest_edge(point)
	if world.dispatch.router._native==null: quit(4); return
	await create_timer(5).timeout
	var values: Array[float]=[]
	var begin:=Time.get_ticks_usec()
	var last:=begin
	while Time.get_ticks_usec()-begin<30000000:
		await process_frame
		var now:=Time.get_ticks_usec()
		values.append(float(now-last)/1000.0)
		last=now
	var report:={"summary":stats(values),"samples_ms":values,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"people":world.people.size(),"cars":world.production.vehicles.size()}
	root.get_texture().get_image().save_png(folder.path_join("scene.png"))
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DESERT_CONTRACTS_BENCHMARK ",folder," ",JSON.stringify(report.summary))
	quit()
