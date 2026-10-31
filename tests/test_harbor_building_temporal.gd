extends "res://tests/test_harbor_building_walkthrough.gd"
## A evidência em vídeo é separada da medição de tempo de quadro: o custo do gravador
## fica de propósito fora de qualquer conclusão de desempenho.
var recorder := -1
var epochs: Array[Dictionary] = []
var origin := 0
var capture_active := false
var captured: Array[Dictionary] = []

func capture_native_frames() -> void:
	while capture_active:
		await RenderingServer.frame_post_draw
		if not capture_active: break
		var stamp := Time.get_ticks_usec()
		var filename := "frame-%06d.jpg"%captured.size()
		root.get_texture().get_image().save_jpg(folder.path_join(filename),.90)
		var sample := {"file":filename,"usec":stamp}
		if is_instance_valid(world.session.railway) and is_instance_valid(world.session.railway.train):
			var train_position: Vector3 = world.session.railway.train.global_position
			sample.train_position = [train_position.x,train_position.y,train_position.z]
		captured.append(sample)

func encode_native_frames(ffmpeg: String, output: String) -> bool:
	var manifest := FileAccess.open(folder.path_join("frames.txt"),FileAccess.WRITE)
	for index in captured.size():
		manifest.store_line("file '"+str(captured[index].file)+"'")
		manifest.store_line("option framerate 1000")
		var duration := float(captured[index+1].usec-captured[index].usec)/1000000.0 if index+1<captured.size() else 1.0/60.0
		manifest.store_line("duration %.6f"%duration)
	manifest.close()
	var encoder_log: Array = []
	var status := OS.execute(ffmpeg,["-hide_banner","-loglevel","warning","-y","-f","concat","-safe","0","-i",ProjectSettings.globalize_path(folder.path_join("frames.txt")),"-fps_mode","vfr","-c:v","libx264","-preset","fast","-crf","21","-pix_fmt","yuv420p",output],encoder_log,true,false)
	FileAccess.open(folder.path_join("encoder.log"),FileAccess.WRITE).store_string(str(encoder_log))
	return status==0 and FileAccess.file_exists(output)

func mark_phase(label: String) -> void:
	epochs.append({"phase":label,"seconds":float(Time.get_ticks_msec()-origin)/1000.0,"sightline":world.session.building_entrance.sightline.debug_snapshot()})
	print("BUILDING_TEMPORAL_PHASE ",epochs[-1])

func run() -> void:
	create_timer(180).timeout.connect(func(): finish(3))
	if DisplayServer.get_name()=="headless": quit(2); return
	rendered = true
	folder = FIXTURE.output_dir("harbor-building-temporal")
	var ffmpeg := ""
	var building := "harbor_customs_house"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ffmpeg="): ffmpeg=arg.trim_prefix("--ffmpeg=")
		if arg.begins_with("--building="): building=arg.trim_prefix("--building=")
	if not FileAccess.file_exists(ffmpeg): push_error("Pass --ffmpeg=<local executable> for video evidence"); quit(4); return
	var definition := CATALOG.find(building)
	var snapshot := FIXTURE.full_snapshot(definition.return_position+Vector3.UP*.08,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.world.time = .9
	snapshot.world.weather = 0
	save_path = FIXTURE.write_fixture(folder,"save.json",snapshot)
	await boot()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	DisplayServer.window_set_title("Geteco Building Temporal")
	DisplayServer.window_move_to_foreground()
	world.session.weather.time_of_day = .9
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	await create_timer(3).timeout
	var output := ProjectSettings.globalize_path(folder.path_join("night-entry-interior-roof.mp4"))
	origin = Time.get_ticks_msec()
	capture_active = true
	capture_native_frames()
	mark_phase("street")
	await create_timer(2).timeout
	var runtime = world.session.building_entrance
	var deadline := Time.get_ticks_msec()+15000
	while (runtime.preparing or not is_instance_valid(runtime.staged)) and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(is_instance_valid(runtime.staged),"street room prepared"): finish(); return
	if not check(await walk(runtime.staged.spawn_position+Vector3.UP*.04),"night continuous entry"): finish(); return
	var room = world.session.room
	if not check(is_instance_valid(room),"night admission completed"): finish(); return
	await walk(room.to_global(Vector3(0,.04,1.45)))
	if is_instance_valid(world.session.railway) and is_instance_valid(world.session.railway.train):
		check(int(runtime.sightline.debug_snapshot().moving.geometry)>0,"live train receives interior camera clipping")
	mark_phase("interior-stable-30s")
	await photo("night-ground-start")
	await create_timer(30).timeout
	await photo("night-ground-end")
	mark_phase("stairs")
	for level in range(1,int(definition.floor_count)+1):
		world.player.teleport(room.to_global(room.stair_point())+Vector3.UP*.04)
		if not check(await stairs_to(level),"night stair "+str(level)): finish(); return
	var look = world.get_node("CityLook")
	check(look._night_factor()>.9,"city night lights retained on roof")
	check(not look._uses_interior_depth(),"roof uses exterior occlusion")
	check(int(runtime.sightline.debug_snapshot().moving.geometry)==0,"roof restores original moving train materials")
	mark_phase("roof-stable-30s")
	await photo("night-roof-start")
	await create_timer(30).timeout
	await photo("night-roof-end")
	capture_active = false
	await process_frame
	check(captured.size()>900,"every rendered frame captured across both 30 second phases")
	check(encode_native_frames(ffmpeg,output),"native frame video encoded")
	FileAccess.open(folder.path_join("phases.json"),FileAccess.WRITE).store_string(JSON.stringify({"phases":epochs,"output":output,"frames":captured,"building":building,"scope":"clear night, ground and roof; native frame readback and encoding are not performance measurements"},"\t"))
	finish()
