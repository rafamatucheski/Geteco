extends SceneTree
## Production Main, actual mixer output and finite optional on/off measurement.
## Recording and PCM inspection are excluded from all performance windows.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const L := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const CANYON := preload("res://runtime/desert/canyon/CanyonState.gd")
var world: Node3D
var ambience: Node3D
var output := ""
var failures: Array[String]=[]
var checks := 0
var phases: Array[Dictionary]=[]
var recordings: Array[Dictionary]=[]
var measurements: Array[Dictionary]=[]
var source_probe_bus := -1
var ambient_bus := -1
var original_buses: Array[Dictionary]=[]

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): failures.append("240s audio fixture watchdog"); finish(3))
	run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks+=1
	print("CANYON_AUDIO ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	if not check(DisplayServer.get_name()!="headless" and "--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"rendered isolated native .NET required"): finish(2); return
	output=FIXTURE.output_dir("smuggler-canyon-audio")
	var point: Vector3 = L.BRIDGE_START.lerp(L.BRIDGE_END,.5)+Vector3.UP*.2
	var data := FIXTURE.full_snapshot(point,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[point.x,point.y,point.z]}
	data.world[CANYON.KEY]={"version":1,"defeated_mask":255,"cache_mask":0}
	var path := FIXTURE.write_fixture(output,"audio-checkpoint.json",data)
	if not check(not path.is_empty(),"isolated checkpoint validates"): finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.get("session")!=null and world.session.ready_for_play and world.production.store.path==path and world.session.controller.no_save,"actual Main loads only isolated checkpoint"): finish(1); return
	if world.session.modal: world.session.close_menu()
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"native C# backend active")
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	ambience=world.session.desert.canyon.ambience
	if not check(is_instance_valid(ambience),"production encounter installs canyon mixer"): finish(1); return
	ambient_bus=AudioServer.get_bus_index("Ambient")
	if not check(ambient_bus>=0 and ambience.wind.bus==&"Ambient" and ambience.detail.bus==&"Ambient" and ambience.shelter.bus==&"Ambient","all three voices obey existing Ambient settings"): finish(1); return
	await place(point)
	await wait_seconds(2)
	check(ambience.snapshot().wind_playing and ambience.snapshot().wind_gain>.9,"bridge admits deep wind at authored gain")
	check(not ambience.snapshot().shelter_playing,"hideout texture remains inaudible at distant bridge")
	await photo("bridge-bones-and-canyon-sound")
	await capture_bridge()
	await check_ambient_mute()
	world.session._menu("Teste de pausa sonora")
	await wait_seconds(.3)
	check(not ambience.wind.playing and not ambience.detail.playing and not ambience.shelter.playing,"modal stops every canyon voice")
	world.session.close_menu()
	await wait_seconds(1.6)
	check(ambience.wind.playing,"close menu restores spatial ambience")
	paused=true
	await process_frame
	check(not ambience.wind.playing and not ambience.detail.playing,"scene-tree pause stops canyon voices")
	paused=false
	await wait_seconds(1.6)
	world.session.show_dialogue([{"speaker":"Dante","message":"A ponte range com o vento."}])
	await wait_seconds(1)
	check(ambience.wind.playing and ambience.snapshot().wind_gain<.5 and not ambience.detail.playing,"dialogue ducks the wind smoothly instead of removing the soundscape")
	world.session.interrupt_dialogue()
	world.session.close_menu()
	await wait_seconds(1.6)
	var previous_gain: float=ambience.snapshot().wind_gain
	check(world.session.state.grant_weapon("pistol") and world.session.state.equip_weapon("pistol"),"production pistol prepares acoustic combat check")
	world.gameplay.aim_point=world.player.global_position+Vector3(5,1,0)
	check(world.gameplay.fire_at(world.gameplay.aim_point),"real player gunfire reaches mixer")
	await wait_seconds(.8)
	check(ambience.snapshot().wind_gain<previous_gain*.6 and not ambience.detail.playing,"gunfire ducks wind and suppresses decorative cues")
	await wait_seconds(4.3)
	check(ambience.snapshot().wind_gain>.8,"calm ambience recovers after shooting")
	await place(L.CENTER+Vector3(0,.2,0))
	await wait_seconds(2)
	check(ambience.shelter.playing and ambience.snapshot().shelter_gain>.9,"open hideout admits quiet canvas and cargo texture")
	await photo("hideout-sound-context")
	await capture_hideout()
	await place(Vector3(-1100,.15,-900))
	await wait_seconds(5)
	check(not ambience.wind.playing and not ambience.detail.playing and not ambience.shelter.playing,"leaving canyon releases every active voice")
	await place(point)
	await wait_seconds(2)
	check(ambience.wind.playing and ambience.get_child_count()==3,"return reuses bounded three-voice mixer")
	if "--audio-perf" in OS.get_cmdline_user_args(): await measure_audio()
	var voice_ids: Array[int]=[]
	for voice in [ambience.wind,ambience.detail,ambience.shelter]: voice_ids.append(voice.get_instance_id())
	world.queue_free(); world=null
	for frame in 3: await process_frame
	var freed := true
	for id in voice_ids: freed=freed and not is_instance_id_valid(id)
	check(freed,"session teardown frees all canyon voices")
	finish(0 if failures.is_empty() else 1)

func capture_bridge() -> void:
	# Additional child bus captures only the real canyon sources, while a second
	# recorder on Master preserves the unmodified full game mix for review.
	AudioServer.add_bus()
	source_probe_bus=AudioServer.bus_count-1
	AudioServer.set_bus_name(source_probe_bus,"CanyonCaptureProbe")
	AudioServer.set_bus_send(source_probe_bus,"Ambient")
	for voice in [ambience.wind,ambience.detail,ambience.shelter]: voice.bus=&"CanyonCaptureProbe"
	var source_record := AudioEffectRecord.new()
	var mixed_record := AudioEffectRecord.new()
	source_record.format=AudioStreamWAV.FORMAT_16_BITS
	mixed_record.format=AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(source_probe_bus,source_record)
	AudioServer.add_bus_effect(0,mixed_record)
	source_record.set_recording_active(true)
	mixed_record.set_recording_active(true)
	await wait_seconds(26)
	source_record.set_recording_active(false)
	mixed_record.set_recording_active(false)
	await process_frame
	store_recording(source_record,"bridge-canyon-only.wav",25.0)
	store_recording(mixed_record,"bridge-full-game-mix.wav",25.0)
	remove_effect(source_probe_bus,source_record)
	remove_effect(0,mixed_record)
	for voice in [ambience.wind,ambience.detail,ambience.shelter]: voice.bus=&"Ambient"
	AudioServer.remove_bus(source_probe_bus); source_probe_bus=-1
	check(int(ambience.snapshot().played.metal)>0 and int(ambience.snapshot().played.vulture)>0,"finite real-time sample contains bridge metal and scavenger calls")
	phases.append({"phase":"recorded_bridge","mixer":ambience.snapshot()})

func capture_hideout() -> void:
	var record := AudioEffectRecord.new()
	record.format=AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0,record)
	record.set_recording_active(true)
	await wait_seconds(8.5)
	record.set_recording_active(false)
	await process_frame
	store_recording(record,"hideout-full-game-mix.wav",8)
	remove_effect(0,record)
	phases.append({"phase":"recorded_hideout","mixer":ambience.snapshot()})

func store_recording(record: AudioEffectRecord, filename: String, minimum_seconds: float) -> void:
	var stream := record.get_recording()
	if not check(stream!=null and stream.get_length()>=minimum_seconds,"actual mixed audio captured: "+filename): return
	var peak := sampled_peak(stream)
	check(peak>.00001,"recording has non-silent PCM: "+filename)
	check(stream.save_to_wav(output.path_join(filename))==OK,"recording saved: "+filename)
	recordings.append({"file":filename,"seconds":stream.get_length(),"sampled_peak":peak,"rate":stream.mix_rate,"stereo":stream.stereo})

func check_ambient_mute() -> void:
	# Isolate the Ambient branch in the actual Master mix for this diagnostic.
	# Bus settings are restored before any performance or presentation sample.
	for index in AudioServer.bus_count:
		original_buses.append({"index":index,"mute":AudioServer.is_bus_mute(index)})
		AudioServer.set_bus_mute(index,index!=0 and index!=ambient_bus)
	var capture := AudioEffectCapture.new()
	capture.buffer_length=1
	AudioServer.add_bus_effect(0,capture)
	await wait_seconds(.4)
	capture.clear_buffer()
	await wait_seconds(.3)
	var audible := capture_peak(capture)
	AudioServer.set_bus_mute(ambient_bus,true)
	await wait_seconds(.4)
	capture.clear_buffer()
	await wait_seconds(.3)
	var muted := capture_peak(capture)
	check(audible>.00001 and muted<.000001,"Ambient mute removes actual output downstream at Master")
	phases.append({"phase":"ambient_mute","audible_peak":audible,"muted_peak":muted})
	remove_effect(0,capture)
	for setting in original_buses: AudioServer.set_bus_mute(setting.index,setting.mute)
	original_buses.clear()

func capture_peak(capture: AudioEffectCapture) -> float:
	var peak := 0.0
	for sample in capture.get_buffer(capture.get_frames_available()): peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	return peak

func sampled_peak(stream: AudioStreamWAV) -> float:
	var peak := 0.0
	var bytes := stream.data
	for index in range(0,bytes.size()-1,64): peak=maxf(peak,absf(float(bytes.decode_s16(index))/32768.0))
	return peak

func remove_effect(bus: int, effect: AudioEffect) -> void:
	for index in range(AudioServer.get_bus_effect_count(bus)-1,-1,-1):
		if AudioServer.get_bus_effect(bus,index)==effect: AudioServer.remove_bus_effect(bus,index)

func place(point: Vector3) -> void:
	world.session.controller.region.set_focus(point)
	world.session.controller.region.prepare_collision_at(point)
	for frame in 3: await physics_frame
	world.player.teleport(point)
	world.camera.target_size=40; world.camera.size=40; world.camera.heading=0
	world.camera.initialized=false
	world.camera._process(1)
	await wait_seconds(.5)
	check(world.player.is_on_floor(),"audio context has real physical support "+str(point))

func photo(id: String) -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))

func measure_audio() -> void:
	var prior_vsync := DisplayServer.window_get_vsync_mode()
	var prior_limit := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	for value in [false,true]:
		ambience.set_enabled(value)
		await wait_seconds(5)
		var times: Array[float]=[]
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec()-start<30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append(float(now-previous)/1000.0)
			previous=now
		var row := stats(times)
		row["canyon_audio_enabled"]=value
		row["vsync"]=DisplayServer.window_get_vsync_mode()
		row["fps_limit"]=Engine.max_fps
		row["mixer"]=ambience.snapshot()
		measurements.append(row)
		print("CANYON_AUDIO_PERF ",JSON.stringify(row))
	ambience.set_enabled(true)
	Engine.max_fps=prior_limit
	DisplayServer.window_set_vsync_mode(prior_vsync)

func stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate(); sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total+=value
		if value>33.3: slow+=1
		if value>66.7: very_slow+=1
	return {"frames":values.size(),"seconds":total/1000,"fps":values.size()*1000/total,"p50_ms":sorted[int((sorted.size()-1)*.5)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over_33_3_ms":slow,"over_66_7_ms":very_slow}

func wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<until: await process_frame

func finish(code: int) -> void:
	paused=false
	for setting in original_buses: AudioServer.set_bus_mute(setting.index,setting.mute)
	if not output.is_empty():
		var report := {"checks":checks,"failures":failures,"recordings":recordings,"phases":phases,"measurements":measurements,"audio_subjective_review":"not performed; recordings provided for listening","performance_scope":"same rendered Main, same bridge, 5s settle + 30s each audio disabled/enabled; no recorder or capture effect during measurement","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"fps_limit":Engine.max_fps}
		var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report,"\t"))
	print("CANYON_AUDIO_DONE ",output," code=",code)
	quit(code)
