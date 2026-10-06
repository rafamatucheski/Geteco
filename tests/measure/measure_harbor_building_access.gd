extends "res://tests/measure/measure.gd"
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var folder := ""
var place := ""
func fingerprints() -> Dictionary:
	var result:={}
	for path in ["runtime/FullSession.gd","runtime/ProductionWorld.gd","runtime/Settings.gd","world/regions/NativeRegion.gd","world/regions/MountainTerrain3D.gd","world/regions/MountainBridgeShore.gd","world/regions/OriginalWorldData.json","world/editing/world_edits.json","world/places/PlaceCatalog.gd","world/places/harbor_buildings/HarborBuildingCatalog.gd"]:
		result[path]=FileAccess.get_sha256("res://"+path)
	return result
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	seed(60726)
	Engine.set_meta("harbor_buildings_measure_baseline","--batch-baseline" in OS.get_cmdline_user_args())
	var source_before:=fingerprints()
	create_timer(240).timeout.connect(func(): quit(3))
	label = "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=")
		if arg.begins_with("--place="): place=arg.trim_prefix("--place=")
	folder=FIXTURE.output_dir("harbor-access-"+label)
	var point:=Vector3(173.75,.08,17)
	var checkpoint:=FIXTURE.full_snapshot(point,true)
	checkpoint.campaign.aftermath={"call_complete":true}
	var path:=FIXTURE.write_fixture(folder,"save.json",checkpoint)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	if not place.is_empty():
		if not await world.session.enter_place(place,false): quit(4); return
	await create_timer(5).timeout
	root.get_texture().get_image().save_png(folder.path_join("scene.png"))
	var values: Array[float]=[]
	var begin:=Time.get_ticks_usec()
	var last:=begin
	while Time.get_ticks_usec()-begin<30000000:
		await process_frame
		var now:=Time.get_ticks_usec()
		values.append(float(now-last)/1000.0)
		last=now
	var report:={"summary":stats(values),"samples_ms":values,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"people":world.people.size(),"cars":world.production.vehicles.size(),"place":place}
	report.source_before=source_before
	report.source_after=fingerprints()
	report.batch_baseline=Engine.get_meta("harbor_buildings_measure_baseline",false)
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("HARBOR_ACCESS_BENCHMARK ",folder," ",JSON.stringify(report.summary))
	quit()
