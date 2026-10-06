extends "res://tests/measure/measure_desert.gd"
## Comparable rendered Main baseline/result; optional per-render-frame night capture.
var capturing := false
var frames: Array[Dictionary] = []
var capture_start := 0
var last_render := -1
var skipped := 0
var sequence_dir := ""
var phase := ""
var failures: Array[String] = []
var performance_skipped := ""
var competing_before := ""
var competing_after := ""

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--benchmark" not in OS.get_cmdline_user_args() or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET --benchmark --no-save required"); quit(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-moon-village")
	print("MOON_VILLAGE_OUTPUT ",ProjectSettings.globalize_path(output))
	var point := Vector3(-528,.08,-829)
	var snapshot := FIXTURE.full_snapshot(point,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[point.x,point.y,point.z]}
	snapshot.world.time=0.0
	snapshot.world.moon_day=4
	var save_path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if save_path.is_empty(): quit(2); return
	fingerprint=source_fingerprint()
	for source in [get_script().resource_path,"res://runtime/atmosphere/DesertMoonlight.gd"]:
		fingerprint[source]=FileAccess.get_sha256(source)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled or world.production.store.path!=save_path or world.production.save_invalid:
		push_error("Startup/isolation failure"); quit(1); return
	world.dispatch.router.nearest_edge(point)
	if world.dispatch.router._native==null: push_error("Native backend required"); quit(1); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.camera.target=world.player
	world.camera.target_size=42.0
	world.camera.heading=0
	world.camera.initialized=false
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=0
	world.session.weather._update()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	await create_timer(10).timeout
	competing_before=other_games()
	if competing_before.is_empty():
		await measure("village-full-moon")
		competing_after=other_games()
		if not competing_after.is_empty(): performance_skipped="Another game appeared during measurement; result is inconclusive"
	else:
		performance_skipped="Measurement skipped while another game runs"
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("village-full-moon.png"))
	var stable := fingerprint==source_fingerprint(fingerprint)
	var settings := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"msaa":root.msaa_3d,"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"native_backend":world.dispatch.router._native!=null,"requested_population":world.production.requested_population}
	if "--temporal" in OS.get_cmdline_user_args():
		Engine.max_fps=60
		sequence_dir=output.path_join("sequence")
		DirAccess.make_dir_recursive_absolute(sequence_dir)
		capture_start=Time.get_ticks_usec()
		capturing=true
		RenderingServer.frame_post_draw.connect(capture_frame)
		phase="static-full-moon"
		await create_timer(10).timeout
		phase="walk-north"
		world.player.automatic_direction=Vector3.FORWARD
		await create_timer(5).timeout
		phase="walk-south-orbit"
		world.player.automatic_direction=Vector3.BACK
		for i in 50:
			world.camera.heading=float(i)/49.0*.7
			await create_timer(.1).timeout
		world.player.automatic_direction=Vector3.ZERO
		phase="dusk-transition"
		for i in 100:
			world.session.weather.time_of_day=lerpf(.72,.9,float(i)/99.0)
			world.session.weather._update()
			await create_timer(.1).timeout
		capturing=false
		RenderingServer.frame_post_draw.disconnect(capture_frame)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("village-night-final.png"))
		world.camera.target_size=64.0
		world.camera.heading=0
		world.session.weather.time_of_day=0
		world.session.weather._update()
		await create_timer(2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("village-overview-night.png"))
		world.session.weather.time_of_day=.45
		world.session.weather._update()
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("village-overview-day.png"))
	if world.gameplay.health<=0 or world.gameplay.god_mode or world.session.modal: failures.append("Ordinary gameplay contract failed")
	stable=stable and fingerprint==source_fingerprint(fingerprint)
	var result := {"settings":settings,"scenarios":reports,"source_stable":stable,"source_sha256_start":fingerprint,"source_sha256_end":source_fingerprint(fingerprint),"failures":failures,"save":save_path,"temporal_frames":frames,"skipped_render_frames":skipped,"capture_overhead_in_benchmark":false,"capture_overhead_in_sequence":true,"notes":"Real Main native routing/population. 10s warmup + 30s uncapped measurement at authored plaza, fixed full moon. Optional continuous per-render-frame sequence with walking/orbit/dusk. Fixture startup is not proof of bridge progression or vehicle access. Provisional target 60fps; >5% p95/p99 regression requires finite confirmation."}
	result["performance_limitation"]=performance_skipped
	result["other_game_processes_before"]=competing_before
	result["other_game_processes_after"]=competing_after
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MOON_VILLAGE_DONE ",output," ",JSON.stringify(reports[0].summary if not reports.is_empty() else {})," stable=",stable," failures=",failures," ",performance_skipped)
	quit(0 if failures.is_empty() else 1)

func other_games() -> String:
	if OS.get_name()!="Windows": return ""
	var listing: Array=[]
	var command := "Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'Godot*' -and $_.Name -notlike '*console.exe' -and $_.CommandLine -notmatch '(^|\\s)--editor(\\s|$)' -and $_.ProcessId -ne %d } | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"%OS.get_process_id()
	var status := OS.execute("powershell",PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),listing,true)
	if status!=0: return "Process inspection failed; measurement withheld: "+"\n".join(listing)
	return "\n".join(listing).strip_edges()

func capture_frame() -> void:
	if not capturing: return
	var render_frame := Engine.get_frames_drawn()
	if render_frame==last_render: return
	if last_render>=0: skipped+=maxi(0,render_frame-last_render-1)
	last_render=render_frame
	var now := Time.get_ticks_usec()
	var file := "%05d.jpg"%frames.size()
	root.get_texture().get_image().save_jpg(sequence_dir.path_join(file),.86)
	var sun=world.session.weather.controller.sun
	frames.append({"file":file,"seconds":float(now-capture_start)/1000000.0,"render_frame":render_frame,"phase":phase,"sun_energy":sun.light_energy,"sun_rotation":str(sun.rotation_degrees),"camera":str(world.camera.global_position),"player":str(world.player.global_position),"hour":world.session.weather.time_of_day})
