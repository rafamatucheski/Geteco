extends SceneTree
## Só inspeção renderizada de componente. Integração/desempenho no Main ficam com o runner da sessão.
const REGION := preload("res://world/desert/DesertRegion.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
var output := "D:/geteco/artifacts/desert-20261006/world"
var region: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var env: WorldEnvironment
var failures: Array[String]=[]
var photos: Array[Dictionary]=[]
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output=ProjectSettings.globalize_path(argument.trim_prefix("--out="))
	_run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	var stage := Node3D.new()
	root.add_child(stage)
	env=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("a6afb0")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("e2d2b3")
	env.environment.ambient_light_energy=.75
	stage.add_child(env)
	sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-32,0)
	sun.light_color=Color("fff0cd")
	sun.light_energy=1.5
	sun.shadow_enabled=true
	stage.add_child(sun)
	region=REGION.new()
	region.initial_focus=LAYOUT.TRUCK_STOP
	stage.add_child(region)
	camera=Camera3D.new()
	# São teleportes de inspeção; nunca interpola a primeira vista a partir da origem.
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=1400
	stage.add_child(camera)
	camera.current=true
	for setup in [
		{"id":"truckstop-day","point":Vector3(260,0,-755),"size":80.0,"offset":Vector3(24,60,50)},
		{"id":"town-day","point":LAYOUT.TOWN+Vector3(0,0,-30),"size":120.0,"offset":Vector3(0,100,85)},
		{"id":"bank-day","point":LAYOUT.BANK,"size":31.0,"offset":Vector3(0,18,15)},
		{"id":"digo-day","point":LAYOUT.WORKSHOP,"size":39.0,"offset":Vector3(0,25,23)},
		{"id":"highway-day","point":Vector3(342.5,0,-1100),"size":65.0,"offset":Vector3(25,32,70)},
		{"id":"drag-day","point":LAYOUT.drag_start_point(),"size":35.0,"offset":Vector3(-8,14,22)},
	]:
		await _place_camera(setup.point,setup.offset,setup.size)
		await _capture(setup.id)
	env.environment.background_color=Color("151e2b")
	env.environment.ambient_light_color=Color("8996b3")
	env.environment.ambient_light_energy=.2
	sun.light_energy=.08
	region.set_night_lights(1.0)
	await _place_camera(LAYOUT.drag_start_point(),Vector3(-8,14,22),35)
	await _capture("drag-night")
	# Finite 30s continuous camera sweep across streamed strip lighting, at 30fps capture target.
	var began := Time.get_ticks_usec()
	var frames := 0
	var timestamps: Array[Dictionary]=[]
	var next_capture := 0.0
	var previous_capture := 0.0
	var largest_capture_gap := 0.0
	var gaps_over_67ms := 0
	while float(Time.get_ticks_usec()-began)/1000000.0<30.0:
		var elapsed := float(Time.get_ticks_usec()-began)/1000000.0
		var target := LAYOUT.drag_start_point()+Vector3.RIGHT*elapsed*12
		region.set_focus(target)
		camera.position=target+Vector3(-8,14,22)
		camera.look_at(target+Vector3.UP)
		await process_frame
		if elapsed>=next_capture:
			await RenderingServer.frame_post_draw
			var captured_at := float(Time.get_ticks_usec()-began)/1000000.0
			var gap := captured_at-previous_capture
			if frames>0:
				largest_capture_gap=maxf(largest_capture_gap,gap)
				if gap>0.0667: gaps_over_67ms+=1
			var file := "night-%05d.png"%frames
			if root.get_texture().get_image().save_png(output.path_join(file))!=OK: failures.append("Could not save "+file)
			timestamps.append({"frame":frames,"elapsed":captured_at,"pose_time":elapsed,"point":[target.x,target.y,target.z],"file":file})
			frames+=1
			previous_capture=captured_at
			next_capture=captured_at+1.0/30.0
	var duration := float(Time.get_ticks_usec()-began)/1000000.0
	FileAccess.open(output.path_join("sequence.json"),FileAccess.WRITE).store_string(JSON.stringify({"scope":"component fixture: geometry and fixed strip lights only; no actors, traffic, headlights or Main performance approval","renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"capture_frames":frames,"duration":duration,"capture_fps":float(frames)/maxf(duration,.001),"largest_capture_gap_seconds":largest_capture_gap,"capture_gaps_over_67ms":gaps_over_67ms,"failures":failures,"timestamps":timestamps},"\t"))
	print("DESERT_WORLD_VISUAL frames=",frames," path=",output)
	FileAccess.open(output.path_join("photos.json"),FileAccess.WRITE).store_string(JSON.stringify(photos,"\t"))
	stage.free()
	quit(0 if failures.is_empty() else 1)
func _place_camera(at: Vector3, offset: Vector3, size: float) -> void:
	region.set_focus(at)
	region.set_environment_activity(true,at)
	for i in 240:
		if region.is_streaming_idle(): break
		await process_frame
	if not region.is_streaming_idle(): failures.append("Streaming did not settle at "+str(at))
	camera.size=size
	camera.position=at+offset
	camera.look_at(at+Vector3.UP)
	camera.reset_physics_interpolation()
	await physics_frame
	for i in 3: await process_frame
func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	var trucks: Array[Dictionary]=[]
	for node in region.find_children("*","Node3D",true,false):
		if node.get_meta("vehicle_kind","")=="bitrem":
			var point: Vector3=node.global_position+Vector3.UP*2
			var screen := camera.unproject_position(point)
			trucks.append({"position":str(node.global_position),"screen":str(screen),"inside_view":not camera.is_position_behind(point) and Rect2(Vector2.ZERO,Vector2(root.size)).has_point(screen)})
	if id=="truckstop-day":
		if trucks.size()!=4: failures.append("Truck stop photo requires four instantiated bitrems")
		for truck in trucks:
			if not truck.inside_view: failures.append("Truck stop photo missed parked bitrem at "+str(truck.position))
	photos.append({"id":id,"focus":str(region.focus),"camera":str(camera.global_transform),"stream_idle":region.is_streaming_idle(),"trucks":trucks})
	if root.get_texture().get_image().save_png(output.path_join(id+".png"))!=OK: failures.append("Could not save "+id)
