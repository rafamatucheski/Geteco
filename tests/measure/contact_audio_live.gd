extends SceneTree
## Same rendered production scene and finite contact workload before/after the audio patch.
var world
var label := "baseline"
var output := ""
var frames_ms: Array[float] = []
var cold_ms: Array[float] = []
var car
var street
var origin := Vector3.ZERO
var heading := 0.0
var cycle := 0.0
var peak_voices := 0
var record := AudioEffectRecord.new()
var contact_record := AudioEffectRecord.new()
var audio_bus := -1
func _initialize() -> void: run.call_deferred()
func stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	return {"frames":values.size(),"seconds":total/1000,"fps":values.size()*1000/total,"p50_ms":sorted[int((sorted.size()-1)*.5)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over_33_3_ms":slow,"over_66_7_ms":very_slow}
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty(): quit(2); return
	create_timer(160.0).timeout.connect(func(): push_error("CONTACT_LIVE timeout"); quit(2))
	seed(14711)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for tick in 3600:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if not world.session.ready_for_play: push_error("CONTACT_LIVE startup incomplete"); quit(2); return
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999
	world.session.weather.time_of_day = .45
	car = world.driving.car
	origin = car.global_position
	heading = car.rotation.y
	world.player.teleport(car.driver_door_anchor(-1) + car.global_basis.x * -.45)
	await physics_frame
	if not world.driving.interact(true): push_error("CONTACT_LIVE cannot board"); quit(2); return
	for tick in 300:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active(): break
	car.external_input = true
	street = world.get_node("StreetPhysics")
	var barrier := StaticBody3D.new()
	barrier.name = "ContactProbeConcrete"
	barrier.set_meta("impact_material","concrete")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6,2,.4)
	shape.shape = box
	shape.position.y = 1
	barrier.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	visual.mesh = mesh
	visual.position.y = 1
	barrier.add_child(visual)
	world.add_child(barrier)
	barrier.global_transform = Transform3D(Basis(Vector3.UP,heading),origin-car.global_basis.z*8)
	audio_bus = AudioServer.get_bus_index("SFX")
	AudioServer.add_bus_effect(audio_bus,record)
	if label != "baseline":
		var contact_pool = load("res://audio/VehicleCrashAudio.gd").pool(car)
		AudioServer.add_bus_effect(AudioServer.get_bus_index(contact_pool.bus_name),contact_record)
		contact_record.set_recording_active(true)
	record.set_recording_active(true)
	var previous := Time.get_ticks_usec()
	var began := previous
	var measured := 0
	var cycles := 0
	for tick in 10000:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now-previous)/1000.0
		previous = now
		if now-began < 5000000: cold_ms.append(frame_ms)
		else:
			if measured == 0: measured = now
			frames_ms.append(frame_ms)
		cycle -= frame_ms/1000.0
		if cycle <= 0:
			cycle = 4.0
			cycles += 1
			car.place(origin,heading)
			car.speed = 12
			car.horizontal_velocity = -car.global_basis.z*12
			car.throttle_input = 0
			car.brake_input = false
			# Existing street prop API: production audio stress, no gameplay mutation.
			for index in 16: street.play_prop_hit(origin+Vector3((index%4)*.55,.5,(index/4)*.55),"metal",8)
		var active := 0
		var pool = world.get_node_or_null("ContactAudio")
		if pool != null:
			for voice in pool.voices:
				if voice.playing: active += 1
		peak_voices = maxi(peak_voices,active)
		if measured != 0 and now-measured >= 30000000: break
	record.set_recording_active(false)
	var recording := record.get_recording()
	recording.save_to_wav(output.path_join(label+"-sfx.wav"))
	if label != "baseline":
		contact_record.set_recording_active(false)
		contact_record.get_recording().save_to_wav(output.path_join(label+"-contacts.wav"))
	var pool = world.get_node_or_null("ContactAudio")
	var report := {"label":label,"scene":"Main.tscn","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"audio_output":AudioServer.output_device,"population":world.people.size(),"vehicles":world.session.controller.vehicles.size(),"origin":str(origin),"heading":heading,"summary":stats(frames_ms),"cold":stats(cold_ms),"frame_intervals_ms":frames_ms,"cycles":cycles,"peak_contact_voices":peak_voices,"played":pool.played_count if pool != null else -1,"dropped":pool.dropped_count if pool != null else -1,"distance":car.distance_travelled,"health":car.health,"notes":"Rendered production world with normal systems active; controlled repeated physical wall contacts and simultaneous prop API stress. Audio captured from SFX bus. This is a local workload, not a global city audit."}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	var file := FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("CONTACT_LIVE ",JSON.stringify(report.summary)," cycles=",cycles," played=",report.played," peak=",peak_voices)
	world.free()
	await process_frame
	quit(0)
