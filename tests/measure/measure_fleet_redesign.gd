extends "res://tests/measure/measure_sport_coupe_redesign.gd"
## ABBA visual finito: dez veículos reais estacionados no Main ativo, mesmos corpos e
## cidade. Só os modelos visíveis mudam. Não afirma o custo de uma corrida com dez carros.
const IDS := ["aurora_executive","monaliza","muscle_classic","sedan_classic","station_wagon","porto_rosso","arctic_jeep","courier_van","police_cruiser","medic_box"]
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PAINT := preload("res://runtime/VehiclePaint.gd")
var targets: Array[Dictionary] = []
var manifest: Dictionary = {}
var initial_load: Dictionary = {}
var normal_cap := 60
var normal_vsync := 1
var began_setup := 0
var confirm_case := ""
var expected_samples := 8

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless" or "--no-save" not in args:
		push_error("Rendered .NET Main and --no-save required"); quit(2); return
	background_run="--background" in args
	if background_run: apply_background_policy()
	paired=true
	allow_initial_focus_reselection=not background_run
	label="ten-cars-abba"
	for arg in args:
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=").validate_filename()
		if arg.begins_with("--confirm="): confirm_case=arg.trim_prefix("--confirm=")
	if not confirm_case.is_empty() and confirm_case not in ["day","night"]:
		push_error("--confirm must be day or night"); quit(2); return
	expected_samples=8 if confirm_case.is_empty() else 4
	folder="res://evidence/fleet-redesign-20261011/validation/performance/"+label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/fleet-redesign-20261011/manifest.json"))
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	seed(11102026)
	normal_cap=Engine.max_fps
	normal_vsync=DisplayServer.window_get_vsync_mode()
	uncapped=true
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	began_setup=Time.get_ticks_msec()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	var deadline := Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play or not world.production.no_save:
		push_error("Isolated Main did not become ready"); quit(3); return
	# O autoload de configurações de vídeo já está totalmente aplicado; guarda as configurações
	# normais efetivas antes de desligar o ritmo delas para o diagnóstico deste processo.
	normal_cap=Engine.max_fps if Engine.max_fps>0 else normal_cap
	normal_vsync=DisplayServer.window_get_vsync_mode() if DisplayServer.window_get_vsync_mode()!=0 else normal_vsync
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if background_run: apply_background_policy()
	OS.low_processor_usage_mode=false
	world.production.set_population(24)
	world.gameplay.health=1000000
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.set_process(false)
	world.player.teleport(Vector3(150,.05,107.8))
	world.production.region.set_focus(world.player.global_position)
	var camera_anchor := Node3D.new()
	camera_anchor.name="FleetBenchmarkCameraAnchor"
	camera_anchor.position=Vector3(150,.7,107.8)
	world.add_child(camera_anchor)
	world.camera.target=camera_anchor
	world.camera.locked=true
	world.camera.heading=0.0
	world.camera.offset=Vector3(0,40,40)
	world.camera.target_size=48.0
	world.camera.size=48.0
	world.camera.global_position=Vector3(150,40,147.8)
	world.camera.look_at(Vector3(150,.7,107.8))
	var warm_deadline := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<warm_deadline: await process_frame
	if not await place_targets():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/setup-failed.png")
		write_json("setup-failed",{"targets":targets.size(),"expected":IDS.size(),"load":load_snapshot()})
		world.free(); quit(4); return
	car=targets[0].body
	car_origin=car.global_position
	# Mantém fixa a composição fotografada; o controlador da câmera fica travado.
	world.player.teleport(Vector3(147,.05,111.3))
	for target in targets:
		target.origin=target.body.global_position
		target.health=target.body.health
	fixture={"archetypes":IDS,"target_count":targets.size(),"seed":11102026,
		"requested_population":24,"scenario":"ten parked vehicle presentations in active Main near Maciota; fixed physical bodies, camera and live city",
		"camera_position":str(world.camera.global_position),"camera_rotation":str(world.camera.global_rotation),"camera_size":world.camera.size,
		"setup_seconds":float(Time.get_ticks_msec()-began_setup)/1000.0,"normal_cap":normal_cap,"normal_vsync":normal_vsync}
	fixture.runtime_sha256={}
	for source in ["res://gameplay/VehicleEquipment.gd","res://runtime/VehicleSurfaceRoles.gd","res://runtime/VehicleFinish.gd","res://runtime/FleetCatalog.gd","res://scripts/Vehicle.gd","res://scripts/Driving.gd"]:
		fixture.runtime_sha256[source]=FileAccess.get_sha256(source)
	paired_contract={"targets":[],"camera_transform":str(world.camera.global_transform),"camera_size":world.camera.size,"player_position":str(world.player.global_position)}
	for target in targets:
		paired_contract.targets.append({"id":target.id,"body_id":target.body.get_instance_id(),"position":str(target.origin),"wheel_pivots":target.body.wheels.size(),
			"before":target.before_metrics,"after":target.after_metrics,"before_path":target.before_path,"after_path":FLEET.REDESIGNED.scene_path(target.id),
			"before_sha256":FileAccess.get_sha256(target.before_path),"after_sha256":FileAccess.get_sha256(FLEET.REDESIGNED.scene_path(target.id))})
	write_json("paired-preparation",paired_contract)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/ten-cars-prepared.png")
	print("FLEET_BENCH_PREPARED ",JSON.stringify(fixture))
	# Deixa o trânsito/população normais chegarem à carga regular de operação. Nenhuma IA,
	# colisão, streaming, luz ou sombra é desligada para baratear isto.
	warm_deadline=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<warm_deadline: await process_frame
	for target in targets:
		target.origin=target.body.global_position
		target.health=target.body.health
	car_origin=car.global_position
	if not await wait_stable_window():
		paired_valid=false; write_paired_summary(); world.free(); quit(5); return
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	render_timing_enabled=true
	initial_load=load_snapshot()
	var nights: Array=[false,true] if confirm_case.is_empty() else [confirm_case=="night"]
	var order: Array=["baseline","final","final","baseline"] if confirm_case.is_empty() else ["final","baseline","baseline","final"]
	for night: bool in nights:
		for index in range(4):
			var variant: String=order[index]
			select_paired_model(variant)
			var sample_name := ("night" if night else "day")+"-%02d-"%(index+1)+variant
			var report: Dictionary=await scenario(night,sample_name)
			paired_reports.append(report)
			var focus_ok: bool=report.focused_frames==int(report.summary.get("frames",0)) if expected_focus_mode=="focused" else report.focused_frames==0
			paired_focus_condition=expected_focus_mode
			paired_valid=paired_valid and report.sample_complete and report.paired_invariants.valid and focus_ok and report.minimized_frames==0
			write_paired_summary()
			if not paired_valid: break
		if not paired_valid: break
	select_paired_model("final")
	if paired_valid and confirm_case.is_empty():
		Engine.max_fps=normal_cap
		DisplayServer.window_set_vsync_mode(normal_vsync)
		uncapped=false
		await scenario(false,"normal-day")
		await scenario(true,"normal-night")
	write_paired_summary()
	world.free()
	await process_frame
	quit(0 if paired_valid else 5)

func place_targets() -> bool:
	var candidates: Array[Vector3]=[]
	for z in [-14.0,-7.0,0.0,7.0,14.0]:
		for x in [-20.0,-16.0,-12.0,-8.0,-4.0,0.0,4.0,8.0,12.0,16.0,20.0]:
			candidates.append(Vector3(150+x,.3,107.8+z))
	candidates.sort_custom(func(a: Vector3,b: Vector3): return a.distance_squared_to(Vector3(150,0,107.8))<b.distance_squared_to(Vector3(150,0,107.8)))
	for candidate in candidates:
		if targets.size()==IDS.size(): break
		var close := false
		for target in targets:
			var delta: Vector3=target.body.global_position-candidate
			if absf(delta.x)<3.1 and absf(delta.z)<6.9: close=true; break
		if close: continue
		world.production.region.prepare_collision_at(candidate)
		await physics_frame
		var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*1.0,candidate-Vector3.UP*2.0,1))
		if ground.is_empty() or ground.normal.y<.98 or absf(ground.position.y)>.4: continue
		candidate=ground.position+Vector3.UP*.035
		var ray := PhysicsRayQueryParameters3D.create(world.camera.global_position,candidate+Vector3.UP*.85,1)
		if not space.intersect_ray(ray).is_empty(): continue
		var id: String=IDS[targets.size()]
		var body: CharacterBody3D=world.production.spawn_vehicle(id,candidate,0.0)
		if body==null: continue
		body.vehicle_id="fleet_benchmark_"+id
		body.external_input=true
		body.throttle_input=0.0
		body.brake_input=true
		# Mantém a pintura real de spawn, incluindo a pintura branca de polícia/médica.
		# A apresentação de linha de base abaixo recebe esta mesma cor por veículo.
		body.ensure_equipment(world)
		var row: Dictionary=manifest.vehicles[id]
		var before_path := "res://evidence/fleet-redesign-20261011/"+str(row.group)+"/original/"+id+".scn"
		if row.group=="utility": before_path="res://evidence/fleet-redesign-20261011/utility/"+id+"-before.scn"
		if row.group=="service": before_path="res://evidence/fleet-redesign-20261011/service/before/"+id+".scn"
		var before: Node3D=(load(before_path) as PackedScene).instantiate()
		before.name="BaselinePresentation"
		before.scale=body.visual.scale
		before.visible=false
		body.add_child(before)
		var paint := PAINT.new()
		paint.bind(before,id)
		paint.apply(body.paint_color)
		preload("res://runtime/VehicleUsage.gd").apply(before,id,body.vehicle_id,paint.materials)
		var materials := {}
		var mounts: Array[Vector3]=[]
		var bars: Array[Vector3]=[]
		for part: MeshInstance3D in before.find_children("*","MeshInstance3D",true,false):
			if part.mesh==null or part.has_meta("wheel_center"): continue
			for surface in (1 if part.material_override!=null else part.mesh.get_surface_count()):
				body.equipment._bind_lens(part,surface,materials,mounts,bars)
		body.equipment._lens_state=-1
		body.equipment._tail_state=-1
		body.equipment._refresh()
		targets.append({"id":id,"body":body,"before":before,"after":body.visual,"before_path":before_path,"before_metrics":mesh_metrics(before),"after_metrics":mesh_metrics(body.visual)})
		await physics_frame
	return targets.size()==IDS.size()

func wait_stable_window() -> bool:
	if background_run:
		expected_focus_mode="unfocused"
		# O Windows pode deixar uma janela recém-criada com foco mesmo depois de NO_FOCUS
		# ser definido. Solta-o uma vez, antes de qualquer amostra, e restaura o mesmo tamanho.
		# Nenhum quadro minimizado é aceito por wait_background_ready/scenario.
		if DisplayServer.window_is_focused():
			var sample_size := DisplayServer.window_get_size()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
			await create_timer(.25).timeout
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(sample_size)
		return await wait_background_ready()
	var began := Time.get_ticks_msec()
	var stable_since := began
	var previous := ""
	var transitions: Array=[]
	while Time.get_ticks_msec()-began<60000:
		await process_frame
		var now := Time.get_ticks_msec()
		var state := "minimized" if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED else ("focused" if DisplayServer.window_is_focused() else "unfocused")
		if state!=previous:
			transitions.append({"seconds":float(now-began)/1000.0,"state":state})
			previous=state
			stable_since=now
		if state!="minimized" and now-stable_since>=5000:
			expected_focus_mode=state
			write_json("window-ready",{"ready":true,"required_focus":state,"seconds":float(now-began)/1000.0,"transitions":transitions})
			print("FLEET_BENCH_WINDOW_READY ",state)
			return true
	write_json("window-ready",{"ready":false,"transitions":transitions})
	return false

func select_paired_model(variant: String) -> void:
	active_variant=variant
	var aggregate := {"meshes":0,"surfaces":0,"triangles":0}
	for target in targets:
		target.before.visible=variant=="baseline"
		target.after.visible=variant=="final"
		var counts: Dictionary=target.before_metrics if variant=="baseline" else target.after_metrics
		for key in aggregate: aggregate[key]+=counts[key]
	active_model=targets[0].before if variant=="baseline" else targets[0].after
	active_model_source=targets[0].before_path if variant=="baseline" else FLEET.REDESIGNED.scene_path(targets[0].id)
	fixture=fixture.duplicate(true)
	fixture.model=aggregate
	fixture.paired_variant=variant

func check_paired_contract() -> Dictionary:
	var valid: bool=targets.size()==10 and str(world.camera.global_transform)==paired_contract.camera_transform and world.camera.size==paired_contract.camera_size
	var states: Array=[]
	for target in targets:
		var body: CharacterBody3D=target.body
		var displacement := body.global_position.distance_to(target.origin)
		var visible_models := int(target.before.visible)+int(target.after.visible)
		var state := {"id":target.id,"displacement_m":displacement,"health":body.health,"wheels":body.wheels.size(),"visible_models":visible_models,"in_frustum":world.camera.is_position_in_frustum(body.global_position+Vector3.UP*.7)}
		states.append(state)
		valid=valid and visible_models==1 and displacement<.05 and body.health==target.health and not body.controlled and not body.traffic and state.in_frustum
	return {"valid":valid,"states":states,"contracts":paired_contract}

func load_snapshot() -> Dictionary:
	var result := super.load_snapshot() if is_instance_valid(active_model) else {"pedestrians":world.people.size(),"vehicles":world.production.vehicles.size(),"traffic":world.production._ambient_traffic_count()}
	result.target_count=targets.size()
	result.target_archetypes=IDS
	return result

func write_paired_summary() -> void:
	super.write_paired_summary()
	var path := folder+"/paired-summary.json"
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	report.measurement_valid=paired_valid and paired_reports.size()==expected_samples
	report.order=["baseline","final","final","baseline"] if confirm_case.is_empty() else ["final","baseline","baseline","final"]
	report.confirm_case=confirm_case
	report.initial_focus_reselected=initial_focus_reselected
	report.focus_selection_policy="One initial OS focus reselection allowed only before any complete paired window, discarding all prior frames and restarting warmup. The chosen focus condition is then fixed for every accepted window. No reselection based on performance; 120 s absolute deadline per window."
	report.notes="Finite ABBA day/night with ten real parked vehicles in active Main. Both model variants resident; same physical bodies, collision, equipment, camera and background city. Only target visibility switches. No AI/physics/lighting reduction. This is ten-car presentation cost in gameplay, not ten simultaneous drivers or a fleet-wide simulation benchmark. One focus condition selected before sampling and required throughout, non-minimized window and low-CPU mode off; normal settings checked separately. Live traffic variation remains visible in per-second load samples. 60 FPS/16.67 ms provisional target; >5% p95/p99 increase triggers at most one equivalent finite confirmation, not automatic approval. No readbacks during sampling."
	report.initial_load=initial_load
	report.target_count=targets.size()
	write_json("paired-summary",report)

func write_json(name: String,data: Dictionary) -> void:
	FileAccess.open(folder+"/"+name+".json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
