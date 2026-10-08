extends "res://tests/measure/measure_cargo_lake.gd"
## MovieWriter captura todo quadro; 30 s de dia e 30 s de noite fora do benchmark.
var recording:=false
var sim_time:=0.0
var night:=false
var timeline: Array=[]
var frame_begin:=0
func run() -> void:
	await super.run()
	started=0
	if not is_instance_valid(plane): return
	world.player.automatic_direction=Vector3.ZERO
	world.camera.heading=.35
	world.session.weather.set_process(false)
	world.session.weather.time_of_day=.45; world.session.weather._update()
	world.player.speed=2.4
	frame_begin=Engine.get_frames_drawn()
	recording=true
	print("CARGO_LAKE_TEMPORAL_START ",folder," frame=",frame_begin)
func _process(delta: float) -> bool:
	if not recording: return false
	sim_time+=delta
	if sim_time>=30 and not night:
		night=true; waypoint=0
		world.player.teleport(plane.to_global(Vector3(9,.14,18.5)))
		world.camera.initialized=false
		world.session.weather.time_of_day=.82; world.session.weather._update()
	var phase_time:=sim_time-30.0 if night else sim_time
	if phase_time<10:
		world.player.automatic_direction=Vector3.ZERO
	else:
		var direction: Vector3=route[waypoint]-world.player.global_position
		direction.y=0
		if direction.length()<.4: waypoint=(waypoint+1)%route.size()
		world.player.automatic_direction=direction.normalized()
	timeline.append({"frame":Engine.get_frames_drawn(),"sim_seconds":sim_time,"usec":Time.get_ticks_usec(),"night":night,"position":str(world.player.global_position),"camera":str(world.camera.global_position),"on_floor":world.player.is_on_floor()})
	if sim_time>=60:
		recording=false; complete.call_deferred()
	return false
func complete() -> void:
	world.player.automatic_direction=Vector3.ZERO
	FileAccess.open(folder.path_join("temporal.json"),FileAccess.WRITE).store_string(JSON.stringify({"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"fps_fixed":60,"window_size":str(root.size),"framebuffer":str(root.get_texture().get_size()),"first_movie_frame":frame_begin,"last_movie_frame":Engine.get_frames_drawn(),"timeline":timeline,"notes":"Invoke with --write-movie and --fixed-fps60; verify MovieWriter output and frame count separately. MovieWriter contains setup frames before first_movie_frame. GPU readback/movie output excluded from FPS certification. 30 s clear day + 30 s clear night, each 10 s static and 20 s walking. Day/night cut at30s is intentional."}))
	print("CARGO_LAKE_TEMPORAL_END ",folder," frames=",timeline.size())
	world.queue_free(); await process_frame; quit()
