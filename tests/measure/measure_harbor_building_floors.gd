extends "res://tests/measure/measure.gd"
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
var folder:=""

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	create_timer(420).timeout.connect(func(): quit(3))
	folder=FIXTURE.output_dir("harbor-floor-performance")
	var checkpoint:=FIXTURE.full_snapshot(Vector3(173.75,.08,17),true)
	checkpoint.campaign.aftermath={"call_complete":true}
	var path:=FIXTURE.write_fixture(folder,"save.json",checkpoint)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	var reports:=[]
	for definition in CATALOG.definitions():
		if not await world.session.enter_place(definition.id,false): quit(4); return
		var room=world.session.room
		# Rejected destination must preserve the previous room and release controls.
		world.player.teleport(room.to_global(room.stair_point()+Vector3.UP*.04))
		var blocker:=StaticBody3D.new()
		var collision:=CollisionShape3D.new()
		var box:=BoxShape3D.new()
		box.size=Vector3(2,3,2)
		collision.shape=box
		blocker.add_child(collision)
		blocker.position=room.to_global(room.stair_point()+Vector3(1.35,1,-80))
		world.add_child(blocker)
		await physics_frame
		await physics_frame
		var rejected: bool=not await world.session.interact()
		blocker.free()
		await physics_frame
		if not rejected or room.floor_index!=0 or world.player.input_locked or world.session.is_transition_blocked():
			push_error("Blocked floor failed to preserve room/control"); quit(5); return
		print("BUILDING_RECOVERY PASS ",definition.id)
		for index in definition.floor_count:
			if index>0:
				world.player.teleport(room.to_global(room.stair_point()+Vector3.UP*.04))
				if not await room.change_floor(index): quit(6); return
			if "--additional-floors" in OS.get_cmdline_user_args() and index<2: continue
			world.player.teleport(room.to_global(Vector3(0,.04,2.4)))
			await create_timer(5).timeout
			var values: Array[float]=[]
			var begin:=Time.get_ticks_usec()
			var last:=begin
			while Time.get_ticks_usec()-begin<30000000:
				await process_frame
				var now:=Time.get_ticks_usec()
				values.append(float(now-last)/1000.0)
				last=now
			var report:={"place":definition.id,"floor":index,"summary":stats(values),"samples_ms":values,"people":world.people.size(),"cars":world.production.vehicles.size(),"floor_nodes":room.get_child_count()}
			reports.append(report)
			root.get_texture().get_image().save_png(folder.path_join(definition.id+"-"+str(index)+".png"))
			print("BUILDING_FLOOR_BENCHMARK ",definition.id," ",index," ",JSON.stringify(report.summary))
		if not await world.session.leave_place(): quit(7); return
	var data:={"reports":reports,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps}
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	print("BUILDING_FLOOR_PERFORMANCE ",folder)
	quit()
