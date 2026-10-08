extends "res://tests/measure/measure_desert.gd"
## A staged 18 m fall followed by real Actor physics and recovery on the pit floor.
## Temporal camera evidence; this short route is not a frame-rate benchmark.
const GROUND := preload("res://world/mining/MiningExterior.gd")

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("mining-fall-review")
	var point:=Vector3(-198,0,-1788)
	var floor_height:=GROUND.surface_height(Vector2(point.x,point.z))
	point.y=floor_height+18.0
	# Restore on the supported portal landing; a save on a steep bench face
	# correctly invokes safe-location recovery instead of admitting that pose.
	var admission:=preload("res://world/mining/MiningLayout.gd").SECRET_ENTRY+Vector3.UP*.08
	var snapshot:=FIXTURE.full_snapshot(admission,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[admission.x,admission.y,admission.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for frame in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path: quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: quit(1); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	await create_timer(3).timeout
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point)
	world.camera.heading=PI
	world.camera.initialized=false
	world.player.speed=6.0
	world.player.automatic_direction=Vector3.ZERO
	var trace:=[]
	var start:=Time.get_ticks_msec()
	var next_photo:=0
	var peak_vertical_speed:=0.0
	var last_pitch:=0.0
	var previous_falling:=false
	var reversals_in_fall:=0
	var falling_frames:=0
	while Time.get_ticks_msec()-start<8000:
		await physics_frame
		var position_now: Vector3=world.player.global_position
		var camera_pose: Dictionary=world.camera._desert_terrain_camera.diagnostics()
		var falling: bool=world.player.velocity.y < -1.0 and not world.player.is_on_floor()
		if falling: falling_frames+=1
		peak_vertical_speed=maxf(peak_vertical_speed,-world.player.velocity.y)
		if falling and previous_falling and float(camera_pose.pitch_degrees)<last_pitch-.1: reversals_in_fall+=1
		last_pitch=float(camera_pose.pitch_degrees)
		previous_falling=falling
		trace.append({"ms":Time.get_ticks_msec()-start,"point":str(position_now),"vertical_speed":world.player.velocity.y,"floor":world.player.is_on_floor(),"camera":str(world.camera.global_position),"pitch":last_pitch,"projection":world.camera.projection,"clearance":camera_pose.near_plane_conservative_clearance})
		if Time.get_ticks_msec()-start>=next_photo:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("fall-%02d.png" % (next_photo/1000)))
			next_photo+=2000
	world.player.automatic_direction=Vector3.BACK
	await create_timer(2).timeout
	world.player.automatic_direction=Vector3.ZERO
	var drop: float=point.y-world.player.global_position.y
	var walk_distance: float=Vector2(point.x,point.z).distance_to(Vector2(world.player.global_position.x,world.player.global_position.z))
	var valid: bool=falling_frames>30 and drop>15.0 and walk_distance>3.0 and peak_vertical_speed>10.0 and reversals_in_fall==0 and world.player.is_on_floor() and world.gameplay.health>0 and not world.player.input_locked
	var data:={"valid":valid,"drop_metres":drop,"recovery_walk_metres":walk_distance,"falling_frames":falling_frames,"peak_vertical_speed":peak_vertical_speed,"camera_reversals_while_falling":reversals_in_fall,"start":str(point),"end":str(world.player.global_position),"trace":trace,"note":"Real gravity in Main .NET from a staged 18m elevation, landing and 2s physical walking recovery. Captures included in trace, not FPS evidence or traversal from the rim."}
	data["max_fps"] = Engine.max_fps
	data["vsync"] = DisplayServer.window_get_vsync_mode()
	data["benchmark_argument"] = "--benchmark" in OS.get_cmdline_user_args()
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	print("MINING_FALL_REVIEW ",output," valid=",valid," peak_vy=",peak_vertical_speed," reversals=",reversals_in_fall)
	quit(0 if valid else 1)
