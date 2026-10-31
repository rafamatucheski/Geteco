extends "res://tests/measure/measure_mining.gd"
## A continuous rendered sequence, deliberately separate from performance measurements.
func _initialize() -> void:
	create_timer(400).timeout.connect(func(): push_error("MINING_TEMPORAL timeout"); quit(3))
	run.call_deferred()

func measure(id: String) -> void:
	var measured: Dictionary={}
	if "--measure" in OS.get_cmdline_user_args():
		# Mede por 30s sem leituras/codificação antes de gravar qualquer quadro.
		Engine.max_fps=0
		await super.measure(id)
		measured=reports.pop_back()
	Engine.max_fps=30
	var folder:=output.path_join(id+"-frames")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var timestamps: Array[Dictionary]=[]
	var previous_frame:=-1
	var missed:=0
	var started:=Time.get_ticks_usec()
	var index:=0
	var revealed:=false
	if id=="coal-gallery":
		world.session.room.restore_secret(false)
		world.player.teleport(world.session.room.to_global(Vector3(-9.65,.04,-4.05)))
	while Time.get_ticks_usec()-started<30000000 and index<1100:
		var elapsed:=float(Time.get_ticks_usec()-started)/1000000.0
		if id!="coal-gallery":
			world.camera.heading=0.0 if elapsed<10 else (elapsed-10.0)*TAU/20.0
		else:
			if elapsed>5 and not revealed:
				world.session.room.perform_mine_action()
				revealed=true
		await RenderingServer.frame_post_draw
		var render_frame:=Engine.get_frames_drawn()
		if previous_frame>=0: missed+=maxi(0,render_frame-previous_frame-1)
		previous_frame=render_frame
		var frame:=root.get_texture().get_image()
		frame.save_jpg(folder.path_join("%05d.jpg"%index),.85)
		if index==0: frame.save_png(output.path_join(id+"-temporal.png"))
		timestamps.append({"index":index,"usec":Time.get_ticks_usec(),"render_frame":render_frame,"heading":world.camera.heading,"camera":str(world.camera.global_position)})
		index+=1
	world.camera.heading=0
	var record:={"id":id,"frames":index,"seconds":float(Time.get_ticks_usec()-started)/1000000.0,"missed_render_frames":missed,"timestamps":timestamps,"summary":measured.get("summary",{}),"performance":measured,"purpose":"Every rendered frame captured at a temporary 30 FPS cap. Capture overhead included: NOT performance evidence. Optional performance record is a separate preceding 30s uncapped window with no image readbacks. First10s static, then full exterior orbit; gallery lever animation after5s."}
	reports.append(record)
	FileAccess.open(folder.path_join("timestamps.json"),FileAccess.WRITE).store_string(JSON.stringify(record,"\t"))
	print("MINING_TEMPORAL ",id," frames=",index," missed=",missed," output=",folder)
	Engine.max_fps=0
