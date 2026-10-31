extends SceneTree
## Main real, população normal da cidade e um cupê do jogador estacionado. Sem acesso a save.
## Godot .NET --path . --script res://tests/measure/measure_sport_coupe_redesign.gd
## -- --no-save --skip-arrival --population=24 --label=before [--uncapped]
## --paired executa um bloco ABBA finito por dia/noite no mesmo Main.
## O rótulo só nomeia a evidência: quem chama seleciona a versão real do recurso.
var world
var car: CharacterBody3D
var label := "before"
var folder := ""
var uncapped := false
var fixture: Dictionary = {}
var car_origin := Vector3.ZERO
const BASELINE_MODEL := "res://evidence/sport-coupe-redesign/baseline/sport_coupe.scn"
var paired := false
var paired_baseline: Node3D
var paired_final: Node3D
var active_model: Node3D
var active_model_source := ""
var active_variant := "installed"
var paired_contract: Dictionary = {}
var paired_reports: Array[Dictionary] = []
var paired_valid := true
var render_timing_enabled := false
var background_run := false
var paired_focus_condition := ""
## Optional fixed focus contract for subclasses using a normal window.
var expected_focus_mode := ""
## Opcional: só antes da primeira janela pareada completa, uma única mudança de foco
## do SO pode selecionar a condição duradoura. Todos os quadros anteriores são descartados.
var allow_initial_focus_reselection := false
var initial_focus_reselected := false

func _initialize() -> void:
	if "--background" in OS.get_cmdline_user_args(): apply_background_policy()
	run.call_deferred()

func apply_background_policy() -> void:
	# Aplica antes do Main, e antes/depois que o início dos autoloads pode definir o modo de janela.
	var review_size := DisplayServer.window_get_size()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(review_size)
	OS.low_processor_usage_mode=false

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--paired-preflight" in args:
		paired_preflight()
		return
	paired = "--paired" in args
	background_run = "--background" in args
	if DisplayServer.get_name() == "headless" or "--no-save" not in args:
		push_error("Requires rendered Godot .NET and --no-save"); quit(2); return
	if paired and "--baseline" in args:
		push_error("--paired requires the installed final asset and its separate baseline, not --baseline"); quit(2); return
	if background_run:
		# Política de janela local ao processo: nunca traz esta revisão por cima do app do usuário.
		apply_background_policy()
	for arg in args:
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
	var normal_cap := Engine.max_fps
	var normal_vsync := DisplayServer.window_get_vsync_mode()
	uncapped = "--uncapped" in args
	# Só comparação isolada: mantém intocado o recurso de produção instalado.
	if "--baseline" in args:
		preload("res://runtime/FleetCatalog.gd").all()["sport_coupe"].scene = BASELINE_MODEL
	if uncapped:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	seed(11102026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	folder = "res://evidence/sport-coupe-redesign/" + label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save:
		push_error("Main did not reach isolated ready state"); quit(3); return
	car = world.driving.car
	if car.archetype != "sport_coupe":
		push_error("Fixture needs the unsaved starter sport_coupe"); quit(4); return
	world.production.set_population(24)
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	car.paint_color = Color("ba3f35")
	car.vehicle_id = "sport_coupe_redesign_reference"
	car.external_input = true
	car.throttle_input = 0.0
	car.brake_input = true
	car.ensure_equipment(world)
	world.player.teleport(car.to_global(Vector3(-3.0, .05, 3.5)))
	world.production.region.set_focus(car.global_position)
	world.camera.locked = true
	world.camera.target = car
	world.camera.heading = 0.0
	world.camera.offset = Vector3(0, 25.3, 25.3)
	world.camera.target_size = 26.0
	world.camera.size = 26.0
	var focus := car.global_position + Vector3(0, .65, 0)
	world.camera.global_position = focus + Vector3(0, 25.3, 25.3)
	world.camera.look_at(focus)
	world.session.weather.set_process(false)
	# Deixa o streaming de produção, os cidadãos do ambiente e o trânsito assentarem primeiro.
	# Rodadas anteriores cresciam de 32 até o limite de 40 carros de trânsito ao longo das janelas. Um
	# assentamento pareado mais longo reduz essa rampa não linear do início sem congelar a IA.
	var settle_seconds := 60 if paired else 12
	var settle_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle_start < settle_seconds*1000:
		await process_frame
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if not background_run: DisplayServer.window_move_to_foreground()
	car_origin = car.global_position
	active_model = car.visual
	active_model_source = preload("res://runtime/FleetCatalog.gd").spec("sport_coupe").scene
	fixture = {"archetype":car.archetype,"car_position":str(car_origin),
		"car_yaw":car.rotation.y,"camera_position":str(world.camera.global_position),
		"camera_rotation":str(world.camera.global_rotation),"camera_size":world.camera.size,
		"player_position":str(world.player.global_position),"model":mesh_metrics(car.visual),
		"requested_population":24,"seed":11102026,"settle_seconds":settle_seconds,
		"scenario":"parked starter coupe in freight yard, active city"}
	if paired:
		if not prepare_paired_models():
			push_error("Could not prepare the two visual-only paired variants"); world.free(); quit(5); return
		if background_run and not await wait_background_ready():
			paired_valid=false
			write_paired_summary()
			world.free(); quit(5); return
		# Conferido contra o GodotSharp.xml desta instalação. Os valores são ms;
		# descrevem o viewport principal, não scripts nem cada subviewport.
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		render_timing_enabled=true
		for night in [false,true]:
			for index in range(4):
				var variant: String = ["baseline","final","final","baseline"][index]
				select_paired_model(variant)
				var name := ("night" if night else "day")+"-%02d-" % (index+1)+variant
				var report: Dictionary = await scenario(night,name)
				paired_reports.append(report)
				var focus_condition := "unfocused" if report.focused_frames==0 else ("focused" if report.focused_frames==report.summary.frames else "mixed")
				if paired_focus_condition.is_empty(): paired_focus_condition=focus_condition
				paired_valid = paired_valid and report.sample_complete and report.paired_invariants.valid and focus_condition!="mixed" and focus_condition==paired_focus_condition and (not background_run or focus_condition=="unfocused") and report.minimized_frames==0 and report.car_displacement_m<.01
				if not paired_valid: break
			if not paired_valid: break
		write_paired_summary()
		select_paired_model("final")
	else:
		for night in [false, true]: await scenario(night)
	if "--check-normal" in args:
		Engine.max_fps = normal_cap
		DisplayServer.window_set_vsync_mode(normal_vsync)
		uncapped = false
		await scenario(false,"normal-day")
	world.free()
	await process_frame
	quit(0 if paired_valid else 5)

func wait_background_ready() -> bool:
	var began := Time.get_ticks_msec()
	var stable_start := 0
	var prior_state := ""
	var transitions: Array[Dictionary] = []
	var ready := false
	while Time.get_ticks_msec()-began<120000:
		await process_frame
		var now := Time.get_ticks_msec()
		var state := "focused" if DisplayServer.window_is_focused() else ("minimized" if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED else "background")
		if state!=prior_state:
			transitions.append({"seconds":float(now-began)/1000.0,"state":state})
			prior_state=state
		if state!="background": stable_start=0; continue
		if stable_start==0: stable_start=now
		if now-stable_start>=5000: ready=true; break
	var report := {"ready":ready,"seconds":float(Time.get_ticks_msec()-began)/1000.0,"required_continuous_unfocused_seconds":5,"deadline_seconds":120,"transitions":transitions}
	FileAccess.open(folder+"/background-ready.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SPORT_COUPE_BACKGROUND_READY ",JSON.stringify(report))
	return ready

func scenario(night: bool, name_override := "") -> Dictionary:
	var name := name_override if not name_override.is_empty() else ("night" if night else "day")
	world.session.weather.time_of_day = .93 if night else .4
	world.session.weather.weather_state = 0
	world.production.state.world_state.time = .93 if night else .4
	world.production.state.world_state.weather = 0
	world.session.weather._update()
	car.equipment.headlights_on = night
	var warm: Array[float] = []
	var frames: Array[float] = []
	var cpu: Array[float] = []
	var physics: Array[float] = []
	var draws: Array[float] = []
	var primitives: Array[float] = []
	var render_cpu: Array[float] = []
	var render_gpu: Array[float] = []
	var render_setup_cpu: Array[float] = []
	var gpu_nonzero_samples := 0
	var focused_frames := 0
	var minimized_frames := 0
	var population_start: int = world.people.size()
	var load_samples: Array[Dictionary] = []
	var next_load_sample := 0.0
	var began := Time.get_ticks_usec()
	var previous := began
	var accepted_began := began
	var duration := 0.0
	var focus_interrupted := false
	var discarded_segments: Array[Dictionary] = []
	var discarded_focus_intervals: Array[Dictionary] = []
	var focus_reselections: Array[Dictionary] = []
	var guard_focus := paired and (background_run or not expected_focus_mode.is_empty())
	while duration < 30000.0 and (not guard_focus or Time.get_ticks_usec()-began<120000000):
		await process_frame
		var now := Time.get_ticks_usec()
		var interval := float(now - previous) / 1000.0
		previous = now
		var expected_focused := expected_focus_mode=="focused"
		if guard_focus and (DisplayServer.window_is_focused()!=expected_focused or DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED):
			if not focus_interrupted:
				discarded_segments.append({"at_seconds":float(now-began)/1000000.0,"reason":"focus_or_minimization_changed",
					"frames_ms":frames.duplicate(),"warmup_ms":warm.duplicate(),"cpu_process_ms":cpu.duplicate(),"physics_ms":physics.duplicate(),
					"draw_calls":draws.duplicate(),"primitives":primitives.duplicate(),"viewport_cpu_ms":render_cpu.duplicate(),
					"viewport_gpu_ms":render_gpu.duplicate(),"frame_setup_cpu_ms":render_setup_cpu.duplicate(),"load_samples":load_samples.duplicate(true)})
				frames.clear(); warm.clear(); cpu.clear(); physics.clear(); draws.clear(); primitives.clear()
				render_cpu.clear(); render_gpu.clear(); render_setup_cpu.clear(); load_samples.clear()
				duration=0.0; focused_frames=0; minimized_frames=0; gpu_nonzero_samples=0; next_load_sample=0.0
				focus_interrupted=true
			discarded_focus_intervals.append({"seconds":float(now-began)/1000000.0,"interval_ms":interval,"focused":DisplayServer.window_is_focused(),"minimized":DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED})
			if allow_initial_focus_reselection and not initial_focus_reselected and paired_reports.is_empty() and DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_MINIMIZED:
				var selected := "focused" if DisplayServer.window_is_focused() else "unfocused"
				focus_reselections.append({"at_seconds":float(now-began)/1000000.0,"from":expected_focus_mode,"to":selected,"reason":"one OS focus reselection before any completed paired window; all prior samples discarded"})
				expected_focus_mode=selected
				initial_focus_reselected=true
			continue
		if focus_interrupted:
			accepted_began=now
			population_start=world.people.size()
			focus_interrupted=false
		if now - accepted_began < 10000000:
			warm.append(interval)
			continue
		frames.append(interval)
		duration += interval
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if render_timing_enabled:
			var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			render_gpu.append(gpu_ms)
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			render_setup_cpu.append(RenderingServer.get_frame_setup_time_cpu())
			if gpu_ms>0.0: gpu_nonzero_samples+=1
		if DisplayServer.window_is_focused(): focused_frames += 1
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED: minimized_frames += 1
		if paired and duration>=next_load_sample:
			var sample := load_snapshot()
			sample.seconds=duration/1000.0
			load_samples.append(sample)
			next_load_sample+=1000.0
	var report := {"label":label,"scenario":name,"fixture":fixture,
		"sample_complete":duration>=30000.0,"sampling_wall_seconds":float(Time.get_ticks_usec()-began)/1000000.0,
		"discarded_focus_segments":discarded_segments,"discarded_focus_frames":discarded_focus_intervals.size(),
		"discarded_focus_intervals":discarded_focus_intervals,"focus_sampling_deadline_seconds":120 if guard_focus else 0,
		"focus_reselections":focus_reselections,
		"expected_focus_mode":expected_focus_mode if not expected_focus_mode.is_empty() else ("unfocused" if background_run else "unrestricted"),
		"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),
		"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"resolution":str(root.size),"msaa":root.msaa_3d,"vsync":DisplayServer.window_get_vsync_mode(),
		"max_fps":Engine.max_fps,"uncapped_diagnostic":uncapped,"pid":OS.get_process_id(),
		"background_requested":background_run,"low_processor_usage_mode":OS.low_processor_usage_mode,
		"window_mode":DisplayServer.window_get_mode(),"window_no_focus":DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS),
		"model_source":active_model_source,"model_sha256":FileAccess.get_sha256(active_model_source),
		"dotnet_autoload":str(root.get_node("SessionDiagnostics").get_script().resource_path),
		"summary":stats(frames),"warmup":stats(warm),"cpu_process":stats(cpu),"physics":stats(physics),
		"frames_ms":frames,"warmup_ms":warm,"cpu_process_ms":cpu,"physics_ms":physics,
		"draw_calls":distribution(draws),"primitives":distribution(primitives),
		"draw_calls_per_frame":draws,"primitives_per_frame":primitives,
		"population_start":population_start,"population_end":world.people.size(),
		"traffic_end":world.production._ambient_traffic_count(),"vehicles_end":world.production.vehicles.size(),
		"focused_frames":focused_frames,"minimized_frames":minimized_frames,
		"car_displacement_m":car.global_position.distance_to(car_origin),
		"paired":paired,"variant":active_variant,"night":night,"load_samples":load_samples,
		"paired_invariants":check_paired_contract() if paired else {},
		"render_timing":{"enabled":render_timing_enabled,"gpu_nonzero_samples":gpu_nonzero_samples,
			"viewport_cpu_ms":distribution(render_cpu),"viewport_gpu_ms":distribution(render_gpu),
			"frame_setup_cpu_ms":distribution(render_setup_cpu),
			"scope":"Main window viewport rendering only. CPU excludes scripts/physics and other subsystems; setup CPU is separate/global. Other subviewports are not included. Readings are last completed render, may lag the wall-frame interval; no force_sync or readback."},
		"viewport_cpu_ms":render_cpu,"viewport_gpu_ms":render_gpu,"frame_setup_cpu_ms":render_setup_cpu,
		"notes":"10 continuous seconds warmup then >=30 continuous seconds real frame intervals, no readbacks during sampling; active city and normal physics. Paired background windows reset warmup only on focus/minimization changes, with 120 s absolute deadline and every discarded interval preserved; no reset depends on FPS. CPU monitors do not isolate GPU time. External process inventory required for concurrency."}
	FileAccess.open(folder + "/" + name + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder + "/" + name + "-gameplay.png"))
	print("SPORT_COUPE_BENCH ", label, " ", name, " ", JSON.stringify(report.summary), " model=", fixture.model)
	return report

func prepare_paired_models() -> bool:
	var installed: String = preload("res://runtime/FleetCatalog.gd").spec("sport_coupe").scene
	paired_baseline=create_paired_baseline()
	if paired_baseline==null: return false
	paired_final=car.visual
	paired_baseline.name="PairedBaselineVisual"
	paired_baseline.visible=false
	car.add_child(paired_baseline)
	var paint := preload("res://runtime/VehiclePaint.gd").new()
	paint.bind(paired_baseline,"sport_coupe")
	paint.apply(car.paint_color)
	preload("res://runtime/VehicleUsage.gd").apply(paired_baseline,"sport_coupe",car.vehicle_id,paint.materials)
	# Reaproveita a ligação real de material do equipamento, mas não cria projetores,
	# áudio, física, efeitos nem segundo veículo. As duas variantes ficam estacionadas/apagadas.
	var materials := {}
	var mounts: Array[Vector3] = []
	var bars: Array[Vector3] = []
	for part: MeshInstance3D in paired_baseline.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null or part.has_meta("wheel_center"): continue
		for surface in (1 if part.material_override!=null else part.mesh.get_surface_count()):
			car.equipment._bind_lens(part,surface,materials,mounts,bars)
	car.equipment._lens_state=-1
	car.equipment._tail_state=-1
	car.equipment._refresh()
	paired_contract={"body_id":car.get_instance_id(),"equipment_id":car.equipment.get_instance_id(),
		"collision_rid":str(car.get_rid()),"collision_shape_id":car.shape.shape.get_instance_id(),
		"collision_size":str(car.shape.shape.size),"body_transform":str(car.global_transform),
		"camera_transform":str(world.camera.global_transform),"camera_size":world.camera.size,
		"player_position":str(world.player.global_position),
		"health":car.health,"wheel_pivots":car.wheels.size(),"real_projectors":car.equipment.lamps.size(),
		"baseline_model":mesh_metrics(paired_baseline),"final_model":mesh_metrics(paired_final),
		"final_source":installed,"baseline_source":BASELINE_MODEL}
	FileAccess.open(folder+"/paired-preparation.json",FileAccess.WRITE).store_string(JSON.stringify(paired_contract,"\t"))
	print("SPORT_COUPE_PAIRED_PREPARE ",JSON.stringify(paired_contract))
	return paired_contract.baseline_model=={"meshes":39,"surfaces":39,"triangles":61087} and paired_contract.final_model.meshes<39 and paired_contract.final_model.triangles<61087

func create_paired_baseline() -> Node3D:
	# As passadas da fábrica fazem cache por arquétipo, não por caminho de origem. Isola só as entradas
	# deste id enquanto monta a origem alternativa e depois as restaura de forma atômica.
	# Nenhum await, spawn ou tick de produção consegue observar o estado temporário.
	if not ResourceLoader.exists(BASELINE_MODEL): return null
	var definition: Dictionary = preload("res://runtime/FleetCatalog.gd").all()["sport_coupe"]
	var installed: String = definition.scene
	var caches: Array[Dictionary] = [preload("res://runtime/FleetSpeedPass.gd")._hulls,preload("res://runtime/FleetSpeedPass.gd")._doors,preload("res://runtime/FleetSpeedPass.gd")._plans]
	var saved: Array[Dictionary] = []
	for cache in caches:
		saved.append({"present":cache.has("sport_coupe"),"value":cache.get("sport_coupe")})
		cache.erase("sport_coupe")
	definition.scene=BASELINE_MODEL
	var model := preload("res://runtime/FleetCatalog.gd").create("sport_coupe")
	definition.scene=installed
	for index in caches.size():
		if saved[index].present: caches[index]["sport_coupe"]=saved[index].value
		else: caches[index].erase("sport_coupe")
	return model

func paired_preflight() -> void:
	var final := preload("res://runtime/FleetCatalog.gd").create("sport_coupe")
	var original := create_paired_baseline()
	var final_again := preload("res://runtime/FleetCatalog.gd").create("sport_coupe")
	var report := {"final_first":mesh_metrics(final),"baseline_second":mesh_metrics(original),"final_restored":mesh_metrics(final_again)}
	report.ok=report.baseline_second=={"meshes":39,"surfaces":39,"triangles":61087} and report.final_first=={"meshes":11,"surfaces":17,"triangles":4908} and report.final_restored==report.final_first
	report.notes="Headless fixture-only preflight: final factory first, original factory with isolated/restored caches second, final factory again. This does not measure FPS or visual quality."
	FileAccess.open("res://evidence/sport-coupe-redesign/paired-fixture-preflight.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SPORT_COUPE_PAIRED_PREFLIGHT ",JSON.stringify(report))
	for model in [final,original,final_again]:
		if is_instance_valid(model): model.free()
	quit(0 if report.ok else 5)

func select_paired_model(variant: String) -> void:
	active_variant=variant
	paired_baseline.visible=variant=="baseline"
	paired_final.visible=variant=="final"
	active_model=paired_baseline if variant=="baseline" else paired_final
	active_model_source=BASELINE_MODEL if variant=="baseline" else paired_contract.final_source
	# O duplicate impede que uma seleção posterior altere relatórios guardados em memória.
	fixture=fixture.duplicate(true)
	fixture.model=mesh_metrics(active_model)
	fixture.paired_variant=variant
	fixture.scenario="same loaded Main, same parked vehicle, only its visual variant changes"

func check_paired_contract() -> Dictionary:
	var visible_variants := int(paired_baseline.visible)+int(paired_final.visible)
	var valid: bool = car.get_instance_id()==paired_contract.body_id and car.equipment.get_instance_id()==paired_contract.equipment_id and str(car.get_rid())==paired_contract.collision_rid and car.shape.shape.get_instance_id()==paired_contract.collision_shape_id and str(car.shape.shape.size)==paired_contract.collision_size and car.health==paired_contract.health and car.wheels.size()==paired_contract.wheel_pivots and car.equipment.lamps.size()==paired_contract.real_projectors and visible_variants==1 and car.visual==paired_final and not car.controlled and not car.traffic
	valid=valid and active_model.is_visible_in_tree() and str(world.camera.global_transform)==paired_contract.camera_transform and world.camera.size==paired_contract.camera_size and str(world.player.global_position)==paired_contract.player_position
	for item in car.equipment.lamps: valid=valid and not item.lamp.visible
	return {"valid":valid,"visible_variants":visible_variants,"active_model":mesh_metrics(active_model),
		"body_id":car.get_instance_id(),"equipment_id":car.equipment.get_instance_id(),
		"resident_model_meshes":paired_contract.baseline_model.meshes+paired_contract.final_model.meshes,
		"contracts":paired_contract}

func load_snapshot() -> Dictionary:
	var in_frustum := 0
	var coupes := 0
	for vehicle in world.production.vehicles:
		if not is_instance_valid(vehicle): continue
		if world.camera.is_position_in_frustum(vehicle.global_position+Vector3.UP*.7): in_frustum+=1
		if vehicle.archetype=="sport_coupe": coupes+=1
	return {"pedestrians":world.people.size(),"vehicles":world.production.vehicles.size(),
		"traffic":world.production._ambient_traffic_count(),"vehicle_centres_in_frustum":in_frustum,
		"sport_coupes_registered":coupes,"target_visible":active_model.is_visible_in_tree(),
		"focused":DisplayServer.window_is_focused()}

func write_paired_summary() -> void:
	var cases := {}
	for night in [false,true]:
		var values := {"baseline":[],"final":[]}
		var gpu_values := {"baseline":[],"final":[]}
		var cpu_values := {"baseline":[],"final":[]}
		var windows := {"baseline":[],"final":[]}
		for report in paired_reports:
			if report.night!=night: continue
			values[report.variant].append_array(report.frames_ms)
			gpu_values[report.variant].append_array(report.viewport_gpu_ms)
			cpu_values[report.variant].append_array(report.viewport_cpu_ms)
			windows[report.variant].append({"scenario":report.scenario,"summary":report.summary,"load":report.load_samples,"draws":report.draw_calls,"primitives":report.primitives,"render_timing":report.render_timing})
		var before_values: Array[float] = []
		var after_values: Array[float] = []
		before_values.assign(values.baseline)
		after_values.assign(values.final)
		var before := stats(before_values)
		var after := stats(after_values)
		if before.is_empty() or after.is_empty(): continue
		var before_gpu: Array[float] = []
		var after_gpu: Array[float] = []
		var before_cpu: Array[float] = []
		var after_cpu: Array[float] = []
		before_gpu.assign(gpu_values.baseline)
		after_gpu.assign(gpu_values.final)
		before_cpu.assign(cpu_values.baseline)
		after_cpu.assign(cpu_values.final)
		cases["night" if night else "day"]={"baseline":before,"final":after,"windows":windows,
			"baseline_viewport_gpu_ms":distribution(before_gpu),"final_viewport_gpu_ms":distribution(after_gpu),
			"baseline_viewport_cpu_ms":distribution(before_cpu),"final_viewport_cpu_ms":distribution(after_cpu),
			"p95_change_percent":(after.p95_ms/before.p95_ms-1.0)*100.0,
			"p99_change_percent":(after.p99_ms/before.p99_ms-1.0)*100.0,
			"fps_change_percent":(after.fps/before.fps-1.0)*100.0}
	var report := {"measurement_valid":paired_valid and paired_reports.size()==8,"completed_samples":paired_reports.size(),
		"pid":OS.get_process_id(),"order":["baseline","final","final","baseline"],"cases":cases,"contracts":paired_contract,
		"background_requested":background_run,"focus_condition":paired_focus_condition,
		"notes":"Finite ABBA per daytime/night in one loaded Main: eight samples total, each 10 s warmup + >=30 s measurement. Only one parked target visual changes. Both resources remain resident throughout; inactive visual is hidden. Same physical body, collision, player, camera, equipment, lights and active city; other sport coupes retain the final model. Focus must be uniform within and equivalent across all samples; --background uses a non-minimized no-focus window and disables low-processor mode only in this process. Background measurements are not a foreground gameplay FPS promise. Per-second vehicle centres in camera frustum do not prove occlusion visibility. Linear time drift is balanced, live traffic variation is not eliminated. This isolates target presentation cost, not full fleet migration or universal FPS. No automatic reruns until passing."}
	FileAccess.open(folder+"/paired-summary.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SPORT_COUPE_PAIRED ",JSON.stringify({"valid":report.measurement_valid,"completed_samples":paired_reports.size(),"cases":cases.keys()}))

func distribution(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += value
	return {"mean":total / sorted.size(),"p50":sorted[int((sorted.size()-1)*.5)],"p95":sorted[int((sorted.size()-1)*.95)],"p99":sorted[int((sorted.size()-1)*.99)],"max":sorted[-1]}

func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	return {"frames":values.size(),"seconds":total/1000.0,"fps":values.size()*1000.0/total,
		"p50_ms":sorted[int((sorted.size()-1)*.50)],"p95_ms":sorted[int((sorted.size()-1)*.95)],
		"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over_33_3_ms":slow,"over_66_7_ms":very_slow}

func mesh_metrics(model: Node3D) -> Dictionary:
	var result := {"meshes":0,"surfaces":0,"triangles":0}
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		result.meshes += 1
		result.surfaces += part.mesh.get_surface_count()
		for index in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(index)
			var count: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
			result.triangles += int(count / 3)
	return result
