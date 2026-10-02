extends SceneTree
const DATA=preload("res://world/editing/WorldEditData.gd")
const REGION=preload("res://world/editing/EditableRegion.gd")
const SIGNALS=preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
var world
var folder: String
func _initialize():run.call_deferred()
func run():
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args():quit(2);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):folder=arg.trim_prefix("--out-dir=")
	if folder.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	seed(29092026);root.size=Vector2i(1280,720)
	var map_hash=DATA.disk_hash()
	var sites=[]
	for id in ["harbor","mountain"]:
		var region=REGION.build_region(id);region.prepare_data()
		for road in region.roads:
			var curve=Curve3D.new()
			for p in road.points:curve.add_point(p)
			sites.append({"id":str(road.id),"region":id,"point":curve.sample_baked(curve.get_baked_length()*.5),"width":road.width})
		region.free()
	world=load("res://Main.tscn").instantiate();world.set_meta("skip_arrival",true)
	root.add_child(world);current_scene=world
	var start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<60000:
		await process_frame
		if world.session!=null and world.session.ready_for_play:break
	if world.session==null or not world.session.ready_for_play:quit(3);return
	world.player.controlled_automatically=true;world.player.automatic_direction=Vector3.ZERO
	# An observer parked outdoors must not die of cold while the traffic is audited.
	world.session.cold.set_process(false)
	world.camera.set_process_unhandled_input(false);world.camera.heading=0;world.camera.target_size=105
	world.session.weather.time_of_day=.35;world.session.weather.weather_state=0
	world.session.weather._update();world.session.weather.set_process(false)
	var captured=[]
	var index=0
	for site in sites:
		if "--signals-only" in OS.get_cmdline_user_args():break
		var point:Vector3=site.point
		world.player.teleport(point+Vector3(0,.2,5));world.production._update_physical_residency(point)
		world.camera.initialized=false
		start=Time.get_ticks_msec()
		while Time.get_ticks_msec()-start<2200:await process_frame
		await RenderingServer.frame_post_draw
		var name="%02d_%s.png"%[index,str(site.id).replace("/","_")]
		var result=root.get_texture().get_image().save_png(folder+"/"+name)
		captured.append({"id":site.id,"region":site.region,"position":str(point),"image":name,"error":result})
		print("ROAD_VIEW ",site.id," ",name)
		index+=1
	FileAccess.open(folder+"/views.json",FileAccess.WRITE).store_string(JSON.stringify(captured,"\t"))
	# One X-junction under normal ambient traffic, three full cycles (31.2 s each).
	var focus=Vector3(182,.15,83)
	world.player.teleport(focus+Vector3(-12,0,-12));world.production._update_physical_residency(focus)
	world.camera.target_size=72;world.camera.initialized=false
	start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<6000:await process_frame
	var frames=[]
	var seen={}
	var completed=[]
	var mismatch_count=0
	var mismatches=[]
	var sampled_junctions={}
	var lens_samples=0
	var last_sample=0
	var last_shot=0
	var phase_frames=[]
	var phase_center:Vector3=SIGNALS._signal_near(Vector3(188,0,78)).get("center",Vector3(188,0,78))
	start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<95000:
		await RenderingServer.frame_post_draw
		var elapsed=Time.get_ticks_msec()-start
		# Consecutive native frames around each transition, including both sides.
		# Keep the expensive image readback out of performance measurements.
		if "--phase-frames" in OS.get_cmdline_user_args():
			var half_cycle=SIGNALS.CYCLE*.5
			var phase=fposmod(Time.get_ticks_msec()/1000.0+SIGNALS._offset(phase_center),half_cycle)
			var boundary=minf(minf(phase,half_cycle-phase),minf(absf(phase-SIGNALS.GREEN_SECONDS),absf(phase-SIGNALS.GREEN_SECONDS-SIGNALS.AMBER_SECONDS)))
			if boundary<.08:
				var name="phase_%06d.jpg"%elapsed
				root.get_texture().get_image().save_jpg(folder+"/"+name,.85)
				phase_frames.append({"ms":elapsed,"image":name,"center":str(phase_center)})
		if elapsed-last_sample<250:continue
		var sample_ms=elapsed-last_sample
		last_sample=elapsed
		var vehicles=[]
		var alive={}
		for car in world.production.vehicles:
			if not is_instance_valid(car) or not car.traffic:continue
			var id=car.get_instance_id();alive[id]=true
			var near=Vector2(car.position.x-focus.x,car.position.z-focus.z).length()<35
			if not seen.has(id):seen[id]={"first_ms":elapsed,"stopped_ms":0,"max_stopped_ms":0,"near":near}
			if near and absf(car.speed)<.2:seen[id].stopped_ms+=sample_ms
			else:seen[id].stopped_ms=0
			seen[id].max_stopped_ms=maxi(seen[id].max_stopped_ms,seen[id].stopped_ms)
			seen[id].near=seen[id].near or near
			seen[id].currently_near=near
			if near:vehicles.append({"id":id,"position":str(car.position),"speed":car.speed,"waiting_signal":car.junction_wait,"stopped_ms":seen[id].stopped_ms,"physics":car.is_physics_processing(),"blocker":str(car.blocker.get_path()) if is_instance_valid(car.blocker) else "","progress":car.route_distance,"laps":car.route_laps})
		for id in seen.keys():
			if not alive.has(id):
				var record=seen[id].duplicate();record.id=id;record.end_ms=elapsed;record.reason="left_vehicle_list";completed.append(record);seen.erase(id)
		# Compare the actual lens color and driver's decision in the same rendered frame.
		for lens in SIGNALS._lenses:
			var mesh=lens.mesh.get_ref()
			if mesh==null or int(lens.index)>=mesh.instance_count:continue
			if lens.center.distance_to(focus)>70:continue
			var key=SIGNALS._nearest_junction(lens.center)
			if not SIGNALS.junctions.has(key):continue
			var state=SIGNALS.signal_state(key,lens.heading)
			if state=="stop":continue
			var actual=mesh.get_instance_color(lens.index)
			var visible_state="green" if actual.g>.85 else ("amber" if actual.g>.3 else "red")
			lens_samples+=1
			sampled_junctions[str(key)]=true
			if visible_state!=state:
				mismatch_count+=1
				if mismatches.size()<30:mismatches.append({"ms":elapsed,"key":str(key),"center":str(lens.center),"heading":str(lens.heading),"actual":str(actual),"expected":state})
		frames.append({"ms":elapsed,"cars":vehicles})
		if elapsed-last_shot>=5000:
			last_shot=elapsed;root.get_texture().get_image().save_png(folder+"/signals_%03d.png"%int(elapsed/1000))
	var report={"map_hash":map_hash,"map_unchanged":map_hash==DATA.disk_hash(),"seed":29092026,"duration_ms":Time.get_ticks_msec()-start,"focus":str(focus),"lens_samples":lens_samples,"lens_mismatches":mismatch_count,"mismatch_examples":mismatches,"sampled_junctions":sampled_junctions.keys(),"frames":frames,"departed_or_despawned":completed,"still_present":seen.values()}
	FileAccess.open(folder+"/signals.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	FileAccess.open(folder+"/phase_frames.json",FileAccess.WRITE).store_string(JSON.stringify(phase_frames,"\t"))
	print("ROAD_VISUAL_DONE roads=",captured.size()," lens_samples=",lens_samples," mismatches=",mismatch_count)
	world.queue_free();await process_frame;quit()
