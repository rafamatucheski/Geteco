extends SceneTree
## Real Main, isolated save, 30-second rendered windows. No user save writes.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const FROZEN_BASELINE := "res://tests/fixtures/world_map_baseline/MapUI.gd"
const REGIONS := ["world","harbor","mountain","desert"]
var world
var output := ""
var samples: Array[float] = []
var recording := false
var stamp := 0
var results := {}
var comparison_views := {}
var performance_eligible := true
var atlas_compare := false
var capture_only := false

func _initialize() -> void:
	atlas_compare="--atlas-compare" in OS.get_cmdline_user_args()
	capture_only="--capture-only" in OS.get_cmdline_user_args()
	# 18 x 30 s de amostras + 104 s de início frio observado + ~84 s de custo de vista/captura
	# + consultas de processo limitadas. Guarda toda amostra; limita a rodada inteira.
	create_timer(900 if atlas_compare else 300).timeout.connect(func(): fail("WORLD_MAP timeout",3))
	run.call_deferred()

func fail(message: String, code := 1) -> void:
	recording=false
	results.status="failed"; results.failure=message
	save_results()
	push_error(message); quit(code)

func save_results() -> void:
	if output.is_empty(): return
	var file := FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE)
	if file==null: push_error("WORLD_MAP cannot write metrics"); return
	file.store_string(JSON.stringify(results,"\t")); file.close()

func record_concurrency(label: String) -> bool:
	# Fora das janelas de medição: a própria consulta de processo não pode inflar um quadro.
	# Depois de contaminada, continua capturando evidência sem disparar mais consultas de processo.
	if not performance_eligible: return false
	var entry := {"phase":label,"at_ms":Time.get_ticks_msec(),"checked":false,"processes":[]}
	if OS.get_name()=="Windows":
		var listing: Array=[]
		var command := "$ErrorActionPreference='Stop'; $mapSelf=Get-CimInstance Win32_Process -Filter 'ProcessId = %d'; $mapOthers=@(Get-CimInstance Win32_Process | Where-Object { ($_.Name -like 'Godot*.exe' -or $_.Name -like 'Geteco*.exe' -or $_.Name -like 'Harbor*.exe') -and $_.ProcessId -ne $mapSelf.ProcessId -and $_.ProcessId -ne $mapSelf.ParentProcessId -and $_.CommandLine -notmatch '(^|\\s)--editor(\\s|$)' } | Select-Object ProcessId,ParentProcessId,Name,CommandLine); ConvertTo-Json -InputObject $mapOthers -Compress"%OS.get_process_id()
		var code := OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),listing,true,false)
		entry.exit_code=code
		var parsed = JSON.parse_string("\n".join(listing)) if code==0 else null
		if parsed is Array:
			entry.checked=true; entry.processes=parsed
		else: entry.diagnostic="\n".join(listing)
	if not results.has("concurrency"): results.concurrency=[]
	results.concurrency.append(entry)
	if not entry.checked or not entry.processes.is_empty():
		performance_eligible=false
		results.performance_status="inconclusive_process_check" if not entry.checked else "inconclusive_concurrent_processes"
		print("WORLD_MAP_MEASUREMENT_STOP ",label," ",results.performance_status," ",entry.processes)
	save_results()
	return performance_eligible

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0: samples.append(float(now-stamp)/1000.0)
	stamp=now
	return false

func sample(label: String, map, moving := false) -> bool:
	if not performance_eligible: return false
	if not record_concurrency(label+"_before"): return false
	# Deixa o quadro que contém a consulta síncrona de processo terminar antes de cronometrar.
	await create_timer(.5).timeout
	var population_before: int=world.people.size()
	var origin: Vector2=map.target_center
	var scale_value: float=map._base_zoom*map.zoom
	results.phase=label; save_results()
	samples.clear(); stamp=Time.get_ticks_usec(); recording=true
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-start < 30000:
		if moving:
			var t := float(Time.get_ticks_msec()-start)/1000.0
			map.target_center=origin+Vector2(sin(t*.5)*80,(cos(t*.5)-1)*40)
		await process_frame
	recording=false
	if samples.is_empty(): fail("WORLD_MAP no frame samples"); return false
	var sorted := samples.duplicate(); sorted.sort()
	var total := 0.0; var over33 := 0; var over66 := 0
	for value in samples:
		total+=value
		if value>33.3: over33+=1
		if value>66.7: over66+=1
	results[label]={"frames":samples.size(),"seconds":total/1000,"fps":samples.size()*1000/total,"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":over33,"over66":over66,"raw_ms":samples.duplicate(),"center":[origin.x,origin.y],"pixels_per_metre":scale_value,"map_area":[map._area.size.x,map._area.size.y],"moving":moving,"population_before":population_before,"population_after":world.people.size(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()}
	save_results()
	print("WORLD_MAP ",label," fps=",results[label].fps," p95=",results[label].p95," p99=",results[label].p99)
	return record_concurrency(label+"_after")

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(label+".png"))
	if error!=OK: fail("WORLD_MAP cannot save capture "+label); return
	if not results.has("captures"): results.captures=[]
	results.captures.append(label+".png"); save_results()

func apply_comparison_view(map, region: String) -> void:
	map.focus_region(region)
	var view: Dictionary=comparison_views[region]
	map.center=Vector2(view.center[0],view.center[1]); map.target_center=map.center
	map.zoom=float(view.pixels_per_metre)/map._base_zoom; map.target_zoom=map.zoom
	map._redraw()

func measure_atlas(map, label: String, establish_views := false) -> void:
	Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for region: String in REGIONS:
		if establish_views:
			map.focus_region(region)
			comparison_views[region]={"center":[map.target_center.x,map.target_center.y],"pixels_per_metre":map._base_zoom*map.target_zoom}
			results.comparison_views=comparison_views.duplicate(true); save_results()
		apply_comparison_view(map,region)
		await create_timer(3).timeout
		await capture(label+"-"+region)
		if capture_only: continue
		if not await sample(label+"_"+region+"_stationary",map): return
		apply_comparison_view(map,region); await create_timer(2).timeout
		if not await sample(label+"_"+region+"_pan",map,true): return
	results.comparison_views=comparison_views.duplicate(true); save_results()
	if capture_only: return
	# Valida o limite/VSync normal depois do diagnóstico sem limite, nas duas versões.
	Engine.max_fps=60; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	apply_comparison_view(map,"desert"); await create_timer(3).timeout
	await sample(label+"_normal_60fps",map,true)

func find_marker(map, region: String, preferred := "") -> int:
	var fallback := -1
	for i in map._markers.size():
		if map._markers[i].region!=region or map._markers[i].kind=="lock": continue
		if map._markers[i].title==preferred: return i
		if fallback<0: fallback=i
	return fallback

func record_relief(map, key: String) -> void:
	var relief = map.atlas.get("relief")
	if relief==null: return
	results[key]={"preparation_usec":int(relief.preparation_usec),"triangle_count":int(relief.triangle_count),"cache_hit":bool(map.atlas.relief_cache_hit)}
	save_results()

func capture_current_states(map) -> void:
	# Layout atual de produção nos dois tamanhos de revisão aceitos, independente do encaixe A/B.
	for viewport_size: Vector2i in [Vector2i(1280,720),Vector2i(800,600)]:
		root.content_scale_size=viewport_size; root.size=viewport_size
		await create_timer(.7).timeout
		var suffix := "" if viewport_size.x==1280 else "-compact"
		for region: String in REGIONS:
			map.select_marker(-1); map.focus_region(region)
			await create_timer(.7).timeout
			await capture(("city" if region=="harbor" else region)+suffix)
			if region=="world": continue
			var preferred: String={"harbor":"Union","mountain":"Forja da Serra","desert":"Digo"}[region]
			var index := find_marker(map,region,preferred)
			assert(index>=0,"authored regional marker available")
			map.select_marker(index)
			if region=="desert":
				assert(map._markers[index].title=="Digo","reference selects the actual Digo marker")
				await create_timer(.7).timeout
				await capture("desert-digo-region"+suffix)
			map._locate_selected(); await create_timer(.7).timeout
			assert(map.sidebar.visible and map.marker_title.text==map._markers[index].title)
			await capture(region+"-selected"+suffix)
			var kind: String={"harbor":"hospital","mountain":"cave","desert":"workshop"}[region]
			map._set_filter(kind); map.focus_region(region); await create_timer(.7).timeout
			assert(map._drawn_markers.all(func(i): return map._markers[i].kind==kind or map._markers[i].objective))
			await capture(region+"-filtered"+suffix)
			if map.has_method("_toggle_filters"):
				if not map._legend.visible: map._toggle_filters()
				await create_timer(.7).timeout
				assert(map._legend.visible,"filter menu is open in its review capture")
				await capture(region+"-filters-open"+suffix)
				map._toggle_filters()
			map._set_filter(kind)
	root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720)
	await create_timer(.7).timeout

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	output=FIXTURE.output_dir("world-map")
	if output.is_empty(): fail("WORLD_MAP cannot create output directory"); return
	results={"status":"running","performance_status":"not_measured" if capture_only else "pending_review","phase":"startup","atlas_compare":atlas_compare,"capture_only":capture_only,"process_id":OS.get_process_id(),"budget":{"target_fps":60,"frame_budget_ms":1000.0/60.0,"p95_p99_regression_review_percent":5,"window_seconds":30},"measurement_notes":"Main scene remains simulated with the production modal map. Same fixed weather, actor position, coordinates and map scale; population counts recorded per window. Process checks bracket each window, not continuous monitoring. No automatic performance approval."}
	save_results()
	var at := Vector3(80,.12,80)
	var data := FIXTURE.full_snapshot(at,true)
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: fail("WORLD_MAP startup did not settle"); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: fail("C# path unavailable"); return
	world.gameplay.god_mode=true
	root.mode=Window.MODE_WINDOWED; root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720)
	world.session.weather.set_process(false); world.session.weather.time_of_day=.45; world.session.weather._update()
	Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	results.environment={"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"scene":"Main.tscn","native":true,"population":world.people.size(),"time_of_day":.45,"fixture":path,"actor":[at.x,at.y,at.z],"region":str(world.session.controller.state.region_id)}
	save_results()
	var baseline_path := FROZEN_BASELINE if atlas_compare else ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-map="): baseline_path=argument.trim_prefix("--baseline-map=")
	if not baseline_path.is_empty():
		var baseline := GDScript.new()
		baseline.source_code=FileAccess.get_file_as_string(baseline_path)
		if baseline.reload()!=OK: fail("WORLD_MAP baseline could not load: "+baseline_path); return
		results.baseline_path=baseline_path; results.phase="baseline_open"; save_results()
		var baseline_began := Time.get_ticks_usec()
		world.session._menu("Mapa")
		var old_map=baseline.new(); old_map.controller=world.session.controller
		world.hud.add_child(old_map); world.session.panel.hide(); world.session.menu_closed=old_map.queue_free
		results.baseline_open_ms=float(Time.get_ticks_usec()-baseline_began)/1000.0; save_results()
		if atlas_compare:
			await measure_atlas(old_map,"baseline",true)
		else:
			old_map.center=Vector2(80,80); old_map.target_center=old_map.center
			old_map.zoom=.8/old_map._base_zoom; old_map.target_zoom=old_map.zoom; old_map._redraw()
			await create_timer(3).timeout; await capture("baseline")
			if not capture_only:
				await sample("baseline_stationary",old_map)
				await sample("baseline_pan",old_map,true)
		world.session.close_menu(); await process_frame
	# Os dois mapas usam a mesma cena montada; só o Control modal é substituído.
	Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	results.phase="current_open"; save_results()
	var began := Time.get_ticks_usec()
	world.session.show_map()
	results.open_ms=float(Time.get_ticks_usec()-began)/1000.0
	var map=world.hud.get_node("MapUI")
	record_relief(map,"relief"); save_results()
	if not atlas_compare and "--compare" in OS.get_cmdline_user_args():
		map.focus_region("harbor"); map.center=Vector2(80,80); map.target_center=map.center
		map.zoom=.8/map._base_zoom; map.target_zoom=map.zoom
	await create_timer(3).timeout
	await capture("map-open")
	print("WORLD_MAP_READY ",output)
	if atlas_compare and (capture_only or performance_eligible):
		await measure_atlas(map,"current")
	elif not atlas_compare and not capture_only and performance_eligible:
		await sample("stationary",map)
		await sample("pan",map,true)
	if map.has_method("focus_region"):
		if not atlas_compare and not capture_only and performance_eligible:
			map.focus_region("desert"); await create_timer(1).timeout
			await sample("desert_pan",map,true)
			Engine.max_fps=60; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			await create_timer(2).timeout
			await sample("normal_60fps",map)
		await capture_current_states(map)
		map.focus_region("harbor"); await create_timer(1).timeout; await capture("city")
		var marker := -1
		for i in map._markers.size():
			if map._markers[i].title=="Digo": marker=i; break
		assert(marker>=0,"actual desert mechanic is discoverable from city")
		map.select_marker(marker); map._locate_selected(); await create_timer(1).timeout
		assert(map.sidebar.visible and map.marker_title.text=="Digo")
		map._mark_selected()
		assert(map._waypoint==map._markers[marker].point,"destination uses actual entry position")
		await capture("selected-digo")
		map._set_filter("hospital"); map.focus_region("harbor"); await create_timer(.7).timeout
		assert(map._drawn_markers.all(func(i): return map._markers[i].kind=="hospital" or map._markers[i].objective))
		map._set_filter("hospital"); map.focus_region("mountain"); await create_timer(.7).timeout
		var old_zoom: float=map.target_zoom
		var wheel := InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true
		map.map_input(wheel); assert(map.target_zoom>old_zoom)
		var wanted: Vector2=map.project(map._actor_point())
		assert(map.unproject(wanted).distance_to(map._actor_point())<.001,"projection and picking agree")
		root.content_scale_size=Vector2i(800,600); root.size=Vector2i(800,600)
		await create_timer(.7).timeout; await capture("compact")
		root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720)
	world.session.close_menu(); await process_frame
	assert(not world.session.modal and not world.player.input_locked)
	var reopen_began := Time.get_ticks_usec()
	world.session.show_map()
	results.reopen_ms=float(Time.get_ticks_usec()-reopen_began)/1000.0
	var reopened=world.hud.get_node("MapUI")
	record_relief(reopened,"reopen_relief"); save_results()
	await create_timer(.5).timeout
	if reopened.has_method("focus_region"):
		assert(reopened._waypoint.is_finite(),"destination survives closing and reopening map")
		reopened._clear_waypoint(); assert(not world.has_meta("map_waypoint"))
	world.session.close_menu(); await process_frame
	results.phase="complete"; results.status="complete"
	results.performance_eligible=performance_eligible and not capture_only
	save_results()
	print("WORLD_MAP_DONE ",output)
	world.free(); quit(0 if performance_eligible or capture_only else 4)
