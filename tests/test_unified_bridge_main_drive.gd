extends SceneTree
## Main real, campanha concluída/C#/tráfego/streaming e embarques produtivos.
## Pela fila .NET após build Harbor.csproj:
## --script res://tests/test_unified_bridge_main_drive.gd -- --no-save --population=24
## Posiciona fixtures ANTES de cada percurso; durante a rota só injeta ações normais.
## Não mede FPS nem substitui integração da obra fechada ou jogar toda a campanha.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const STORY := preload("res://runtime/desert/DesertStoryState.gd")
const KIT := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const NORTH := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PARK_FIXTURE := Vector3(394,.12,-125)
const ACTIONS := ["accelerate","brake","handbrake","move_left","move_right","move_up","move_down"]
var world
var car: VEHICLE
var folder := ""
var checkpoint := ""
var began := 0
var checks := 0
var failures: Array[String] = []
var drives: Array[Dictionary] = []
var input_before: Dictionary = {}
var fingerprint: Dictionary = {}
var completed_run := false
var route_filter := ""

func _initialize() -> void:
	create_timer(900,true,false,true).timeout.connect(func(): check(false,"limite global inicial de 900 s"); finish(3))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)
	print("UNIFIED_MAIN_DRIVE ","PASS " if value else "FAIL ",label)

func run() -> void:
	began=Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var selected_routes: Array[Dictionary] = routes()
	for arg in args:
		if not arg.begins_with("--drive-route="): continue
		if not route_filter.is_empty(): check(false,"filtro de percurso único"); finish(2); return
		route_filter=arg.trim_prefix("--drive-route=")
		var matching: Array[Dictionary] = []
		for scenario in selected_routes:
			if str(scenario.id)==route_filter: matching.append(scenario)
		if matching.size()!=1: check(false,"--drive-route exige ID exato de um dos quatro percursos"); finish(2); return
		selected_routes=matching
	if "--no-save" not in args or "--no-traffic" in args or not KIT.enabled() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		check(false,"exige --no-save, tráfego, ponte unificada e backend C# compilado")
		finish(2)
		return
	folder=FIXTURE.output_dir("unified-bridge-main-drive")
	var state := STATE.new()
	var data: Dictionary = FIXTURE.full_snapshot(Vector3(372.5,.12,-125),true)
	# O carro padrão não pode nascer junto de Dante nem dentro da rota da fixture.
	data.world.vehicles=[{"archetype":"sport_coupe","vehicle_id":"player_coupe","was_driven":false,"paint":"d5a544ff","position":[PARK_FIXTURE.x,PARK_FIXTURE.y,PARK_FIXTURE.z],"yaw":PI*.5,"health":80.0,"region":"harbor","equipment":{}}]
	var restored: bool = state.restore_snapshot(data)
	check(restored and state.campaign.complete_aftermath_call() and STORY.mark(state.world_state,"arrived"),"checkpoint autorado após campanha e conversas validado por APIs reais")
	if not failures.is_empty(): finish(2); return
	checkpoint=FIXTURE.write_fixture(folder,"checkpoint.json",state.snapshot())
	if checkpoint.is_empty(): check(false,"checkpoint isolado gravado"); finish(2); return
	fingerprint=FIXTURE.source_fingerprint()
	print("UNIFIED_MAIN_DRIVE_START ",ProjectSettings.globalize_path(folder))
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",checkpoint)
	root.add_child(world)
	current_scene=world
	var admission_deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<admission_deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play and world.production.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play and world.production.ready_for_play,"Main pronto dentro da janela de admissão")
	if not failures.is_empty(): finish(2); return
	check(world.production.no_save and world.production.store.path==checkpoint and world.production.loaded_save,"SaveStore produtivo usa somente checkpoint privado, com autosave desativado")
	var planned: Dictionary = world.dispatch.router.plan(Vector3(382.5,0,-200),Vector3(440,0,-281.3),Vector3.FORWARD)
	check(planned.get("ok",false) and world.dispatch.router._native!=null,"rota produtiva executou backend C# sem fallback")
	check(int(world.production.requested_population)>0,"população produtiva permanece habilitada")
	check(not world.session.dialogue_open and not world.session.modal,"checkpoint pós-diálogos não oculta entrada de condução")
	var default_car: VEHICLE = world.driving.car as VEHICLE
	check(is_instance_valid(default_car) and default_car.global_position.distance_to(PARK_FIXTURE)<1,"player_coupe restaurado no estacionamento isolado da fixture")
	check(world.session.position_clear(world.player.global_position) and world.gameplay.health>0 and not world.session.rescue_pending,"Dante inicia livre, vivo e sem recuperação pendente")
	if is_instance_valid(default_car): default_car.input_locked=true
	print("UNIFIED_MAIN_DRIVE_INITIAL ",JSON.stringify({"player":str(world.player.global_position),"health":world.gameplay.health,"rescue_pending":world.session.rescue_pending,"default_car":str(default_car.global_position) if is_instance_valid(default_car) else "missing","park_fixture":str(PARK_FIXTURE)}))
	if not failures.is_empty(): finish(2); return
	var game_input := get_root().get_node("GameInput")
	input_before={"using_gamepad":game_input.using_gamepad,"touch_move":game_input.touch_move}
	game_input.using_gamepad=false
	game_input.touch_move=Vector2.ZERO
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	for scenario in selected_routes:
		if not await prepare_car(scenario.path): break
		if not await drive(str(scenario.id),scenario.path): break
	completed_run=drives.size()==selected_routes.size()
	check(completed_run,"quatro percursos completos no Main, com ida/volta em cada braço" if route_filter.is_empty() else "percurso selecionado completo no Main: "+route_filter)
	var observed_traffic := false
	for report in drives: observed_traffic=observed_traffic or int(report.max_ambient_traffic)>0
	check(observed_traffic,"trânsito ambiente produtivo observado durante a travessia")
	check(world.production.no_save and world.production.store.path==checkpoint and not STORE.read_valid(checkpoint).is_empty(),"checkpoint permaneceu isolado e válido até o final")
	finish(0 if failures.is_empty() else 1)

func routes() -> Array[Dictionary]:
	# Mesmos eixos da fixture física; a volta usa a pista oposta porque há NPCs reais.
	var outward := PackedVector3Array([Vector3(372.5,0,-125),Vector3(376.5,0,-125)])
	var arc_steps := ceili(6.0*PI*.5)
	for i in range(1,arc_steps+1):
		var angle: float = lerpf(PI*.5,0,float(i)/arc_steps)
		outward.append(Vector3(376.5+cos(angle)*6,0,-131+sin(angle)*6))
	var inbound := PackedVector3Array([Vector3(644,0,-287.2)])
	var sections: Array = KIT.east_sections()
	for section in sections:
		var point: Vector3 = section.point
		if point.z>=-131: continue
		var side: Vector3 = section.side
		var lane: float = lerpf(7.5,2.2,clampf((point.x-405)/(468.25-405),0,1))
		outward.append(point+side*lane)
	outward.append(Vector3(644,0,-282.8))
	for i in range(sections.size()-1,-1,-1):
		var point: Vector3 = sections[i].point
		if is_equal_approx(point.x,375) and point.z> -131: continue
		var side: Vector3 = sections[i].side
		var lane: float = lerpf(7.5,2.2,clampf((point.x-405)/(468.25-405),0,1))
		inbound.append(point-side*lane)
	inbound.append(Vector3(367.5,0,-131))
	for i in range(1,arc_steps+1):
		var angle: float = lerpf(PI,PI*.5,float(i)/arc_steps)
		inbound.append(Vector3(373.5+cos(angle)*6,0,-131+sin(angle)*6))
	inbound.append(Vector3(377.5,0,-125))
	var north := PackedVector3Array()
	var direction: Vector3 = NORTH.sample(.2)-NORTH.sample(0)
	direction.y=0
	direction=direction.normalized()
	north.append(NORTH.APPROACH-direction*5)
	north.append(NORTH.APPROACH-direction*2)
	north.append(NORTH.sample(0))
	for i in range(1,ceili(NORTH.length()/2)): north.append(NORTH.sample(float(i)*2))
	for z in range(-374,-402,-2): north.append(Vector3(342.5,DESERT.surface_height(Vector2(342.5,z)),z))
	var south := north.duplicate()
	south.reverse()
	return [{"id":"tronco_curva_leste_ida","path":outward},{"id":"tronco_curva_leste_volta","path":inbound},{"id":"norte_ida","path":north},{"id":"norte_volta","path":south}]

func prepare_car(path: PackedVector3Array) -> bool:
	release_controls()
	if is_instance_valid(car):
		Input.action_press("handbrake")
		var stop_deadline := Time.get_ticks_msec()+8000
		while Time.get_ticks_msec()<stop_deadline and absf(car.speed)>.2: await physics_frame
		release_controls()
		var exited: bool = world.driving.interact()
		check(exited,"desembarque normal admitido antes da próxima fixture")
		if not exited: return false
		var exit_deadline := Time.get_ticks_msec()+20000
		while Time.get_ticks_msec()<exit_deadline:
			await physics_frame
			if not world.driving.occupied and not world.driving.is_body_transition_active(): break
		check(not world.driving.occupied and not world.driving.is_body_transition_active(),"desembarque real terminou")
		if world.driving.occupied or world.driving.is_body_transition_active(): return false
		world.production.vehicles.erase(car)
		car.queue_free()
		car=null
		await physics_frame
	var heading: Vector3 = path[1]-path[0]
	heading.y=0
	heading=heading.normalized()
	var side: Vector3 = Vector3(-heading.z,0,heading.x)
	# Única colocação da fixture: antes do início, com a sessão produtiva admitida.
	world.player.teleport(path[0]+side*3.0+Vector3.UP*.12)
	var wanted_region: String = CONNECTION.logical_region(world.player.global_position)
	var stream_deadline := Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<stream_deadline:
		await process_frame
		if world.session.state.region_id==wanted_region and world.production.region.is_streaming_idle(): break
	check(world.session.state.region_id==wanted_region and world.production.region.is_streaming_idle(),"região inicial e streaming admitidos antes do percurso: "+wanted_region)
	if world.session.state.region_id!=wanted_region or not world.production.region.is_streaming_idle(): return false
	world.production.region.prepare_collision_at(path[0])
	for frame in 5: await physics_frame
	var spawn_yaw: float = atan2(-heading.x,-heading.z)
	# Dimensões reais do mesmo arquétipo e escala autorada em Vehicle._ready.
	var dimensions: Array = FLEET.spec("winter_suv_heavy").bounds_size
	var half_width: float = maxf(.65,float(dimensions[0])*1.08)*.5
	var half_length: float = float(dimensions[2])*1.08*.5
	var spawn_basis := Basis(Vector3.UP,spawn_yaw)
	var support_samples: Array[Dictionary] = []
	var highest_floor := -INF
	for offset: Vector3 in [Vector3.ZERO,Vector3(-half_width,0,-half_length),Vector3(half_width,0,-half_length),Vector3(-half_width,0,half_length),Vector3(half_width,0,half_length)]:
		var probe: Vector3 = path[0]+spawn_basis*offset
		var hit: Dictionary = ray(probe+Vector3.UP*2,probe-Vector3.UP*2)
		support_samples.append({"point":str(probe),"hit":not hit.is_empty(),"floor":str(hit.get("position",Vector3.ZERO)),"body":str(hit.collider.get_path()) if not hit.is_empty() else ""})
		if not hit.is_empty(): highest_floor=maxf(highest_floor,float(hit.position.y))
	var all_supported: bool = support_samples.all(func(sample: Dictionary): return bool(sample.hit))
	check(all_supported,"cinco apoios físicos reais para admitir a fixture SUV")
	# A pose assentada do Actor pode penetrar milímetros no plano inclinado.
	# Como restore_location, admitir uma pose livre sobre o piso ANTES do settle.
	var staged: bool = stage_actor([path[0]+side*3,path[0]-side*3,path[0]+side*3-heading*2,path[0]-side*3-heading*2])
	check(staged,"pose de preparação de Dante apoiada e livre antes da criação do SUV")
	print("UNIFIED_MAIN_DRIVE_PREPARE ",JSON.stringify({"start":str(path[0]),"player":str(world.player.global_position),"health":world.gameplay.health,"rescue_pending":world.session.rescue_pending,"supports":support_samples,"highest_floor":highest_floor if all_supported else 0}))
	check(world.gameplay.health>0 and not world.session.rescue_pending and world.session.position_clear(world.player.global_position),"Dante vivo e livre antes de criar e embarcar no SUV")
	if not all_supported or not staged or world.gameplay.health<=0 or world.session.rescue_pending or not world.session.position_clear(world.player.global_position): return false
	var spawn_point: Vector3 = Vector3(path[0].x,highest_floor+.04,path[0].z)
	car=world.production.spawn_vehicle("winter_suv_heavy",spawn_point,spawn_yaw) as VEHICLE
	check(is_instance_valid(car),"SUV físico criado pela frota produtiva")
	if not is_instance_valid(car): return false
	car.set_meta("unified_bridge_test_fixture",true)
	car.warm_doors(2500)
	for frame in 5: await physics_frame
	var entered := false
	for door_side in [-1,1]:
		var door_point: Vector3 = car.driver_door_anchor(door_side)+car.global_basis.x*float(door_side)*.5
		if not stage_actor([door_point,door_point+heading*.4,door_point-heading*.4]): continue
		if world.driving.interact(): entered=true; break
	check(entered,"embarque normal Driving.interact admitido no SUV")
	if not entered: return false
	var boarding_deadline := Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<boarding_deadline:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active(): break
	var seated: bool = world.driving.occupied and world.driving.car==car and not world.driving.is_body_transition_active() and car.controlled and not car.external_input and not car.input_locked
	check(seated and world.camera.target==car,"embarque concluído: ocupação, handling do jogador e câmera seguem o carro real")
	return seated

func stage_actor(candidates: Array) -> bool:
	var diagnostics: Array[Dictionary] = []
	for candidate: Vector3 in candidates:
		var support: Dictionary = ray(candidate+Vector3.UP*2,candidate-Vector3.UP*2)
		if support.is_empty():
			diagnostics.append({"point":str(candidate),"supported":false})
			continue
		var pose: Vector3 = support.position+Vector3.UP*.12
		var clear: bool = world.session.position_clear(pose)
		var blockers: Array[Dictionary] = []
		if not clear:
			var capsule := CapsuleShape3D.new()
			capsule.radius=.32
			capsule.height=1.7
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape=capsule
			query.collision_mask=7
			query.transform=Transform3D(Basis.IDENTITY,pose+Vector3.UP*.9)
			var excluded: Array[RID] = []
			excluded.append(world.player.get_rid())
			query.exclude=excluded
			for hit in world.get_world_3d().direct_space_state.intersect_shape(query,8):
				blockers.append({"body":str(hit.collider.get_path()),"layer":int(hit.collider.collision_layer)})
		diagnostics.append({"point":str(pose),"supported":true,"clear":clear,"floor_body":str(support.collider.get_path()),"floor_normal":str(support.normal),"blockers":blockers})
		if not clear: continue
		world.player.teleport(pose)
		print("UNIFIED_MAIN_DRIVE_ACTOR_POSE ",JSON.stringify({"selected":str(pose),"probes":diagnostics}))
		return true
	print("UNIFIED_MAIN_DRIVE_ACTOR_POSE ",JSON.stringify({"selected":"none","probes":diagnostics}))
	return false

func ray(a: Vector3, b: Vector3, mask: int = 1) -> Dictionary:
	var excluded: Array[RID] = []
	if is_instance_valid(car): excluded.append(car.get_rid())
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,mask,excluded))

func drive(id: String, path: PackedVector3Array) -> bool:
	var waypoint := 1
	var route_length := 0.0
	for i in range(1,path.size()): route_length+=path[i-1].distance_to(path[i])
	var deadline_msec := int((route_length/4+30)*1000)
	var start := Time.get_ticks_msec()
	var last_position: Vector3 = car.global_position
	var supported := true
	var occupied := true
	var max_step := 0.0
	var max_error := 0.0
	var static_contacts: Array = []
	var dynamic_contacts: Array = []
	var static_damage: Array = []
	var positions: Array = []
	var blocked_frames := 0
	var max_traffic := 0
	var sample_at := start
	var health_before: float = car.health
	var previous_health: float = car.health
	while Time.get_ticks_msec()-start<deadline_msec and waypoint<path.size():
		var delta: Vector3 = path[waypoint]-car.global_position
		delta.y=0
		if delta.length()<2.1:
			waypoint+=1
			continue
		var yaw: float = atan2(-delta.x,-delta.z)
		var steering: float = clampf(angle_difference(car.rotation.y,yaw)*2.8,-1,1)
		var forward: Vector3 = -car.global_basis.z
		var obstacle: Dictionary = ray(car.global_position+forward*(car.half_length+.2)+Vector3.UP*.65,car.global_position+forward*(car.half_length+8)+Vector3.UP*.65,4)
		var blocked: bool = not obstacle.is_empty()
		if blocked: blocked_frames+=1
		apply_controls(steering,0.0 if blocked or car.speed>=5 else .35,blocked or car.speed>6)
		await physics_frame
		var step: float = car.global_position.distance_to(last_position)
		max_step=maxf(max_step,step)
		last_position=car.global_position
		var a: Vector3 = path[maxi(0,waypoint-1)]
		var b: Vector3 = path[waypoint]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(car.position.x,car.position.z),Vector2(a.x,a.z),Vector2(b.x,b.z))
		max_error=maxf(max_error,closest.distance_to(Vector2(car.position.x,car.position.z)))
		supported=supported and not ray(car.global_position+Vector3.UP*.5,car.global_position-Vector3.UP*.8).is_empty()
		occupied=occupied and world.driving.occupied and world.driving.car==car and not car.external_input and world.camera.target==car
		var static_hit := false
		var dynamic_hit := false
		for index in car.get_slide_collision_count():
			var hit: KinematicCollision3D = car.get_slide_collision(index)
			var collider: Node = hit.get_collider() as Node
			if collider==null: continue
			static_hit=static_hit or collider is StaticBody3D
			dynamic_hit=dynamic_hit or not collider is StaticBody3D
			if absf(hit.get_normal().y)>=.3: continue
			var contact: Dictionary = {"body":str(collider.get_path()),"point":str(hit.get_position()),"normal":str(hit.get_normal())}
			if collider is StaticBody3D:
				if static_contacts.size()<12: static_contacts.append(contact)
			elif dynamic_contacts.size()<12: dynamic_contacts.append(contact)
		if car.health<previous_health and static_hit and not dynamic_hit:
			static_damage.append({"milliseconds":Time.get_ticks_msec()-start,"damage":previous_health-car.health,"point":str(car.global_position)})
		previous_health=car.health
		if Time.get_ticks_msec()>=sample_at:
			var population: int = world.production._ambient_traffic_count()
			max_traffic=maxi(max_traffic,population)
			positions.append({"milliseconds":Time.get_ticks_msec()-start,"point":str(car.global_position),"region":world.session.state.region_id,"speed":car.speed,"ambient_traffic":population,"streaming_idle":world.production.region.is_streaming_idle()})
			sample_at=Time.get_ticks_msec()+1000
		if car.position.y< -1 or max_error>4 or max_step>3 or not occupied or not static_contacts.is_empty() or not static_damage.is_empty() or world.session.modal or world.session.dialogue_open: break
	release_controls()
	Input.action_press("handbrake")
	var reached: bool = waypoint==path.size()
	var report: Dictionary = {"id":id,"reached":reached,"supported":supported,"occupied":occupied,"waypoint":waypoint,"waypoints":path.size(),"seconds":float(Time.get_ticks_msec()-start)/1000,"deadline_seconds":float(deadline_msec)/1000,"max_position_step":max_step,"max_lateral_error":max_error,"health_before":health_before,"health_after":car.health,"max_ambient_traffic":max_traffic,"npc_blocked_physics_frames":blocked_frames,"static_contacts":static_contacts,"dynamic_contacts":dynamic_contacts,"static_damage_without_dynamic_contact":static_damage,"samples":positions,"fixture_teleports_during_route":0}
	drives.append(report)
	print("UNIFIED_MAIN_DRIVE_ROUTE_RESULT ",JSON.stringify(report))
	check(reached,id+": percurso completo no Main usando ações reais")
	check(supported,id+": suporte físico permaneceu sob o carro")
	check(occupied,id+": jogador, câmera e ocupação permaneceram no veículo produtivo")
	check(static_contacts.is_empty(),id+": nenhum contato estático horizontal inesperado")
	check(static_damage.is_empty(),id+": nenhum dano com contato exclusivamente estático")
	check(max_step<=3,id+": nenhuma recuperação por salto de posição durante percurso")
	check(car.health>0,id+": veículo operacional; contatos NPC separados dos estáticos")
	return reached and supported and occupied and static_contacts.is_empty() and static_damage.is_empty() and max_step<=3 and car.health>0

func apply_controls(steering: float, throttle: float, brake: bool) -> void:
	# get_vector aplica deadzone média aos quatro eixos. Compensar a entrada da
	# fixture preserva a intensidade desejada após a mesma API lida pelo jogador.
	var deadzone: float = (InputMap.action_get_deadzone("move_left")+InputMap.action_get_deadzone("move_right")+InputMap.action_get_deadzone("move_up")+InputMap.action_get_deadzone("move_down"))*.25
	var strength: float = 0.0 if absf(steering)<.001 else deadzone+(1-deadzone)*absf(steering)
	set_action("move_left",strength if steering>0 else 0)
	set_action("move_right",strength if steering<0 else 0)
	set_action("accelerate",throttle)
	set_action("brake",0)
	set_action("handbrake",1 if brake else 0)

func set_action(action: String, strength: float) -> void:
	if strength>0: Input.action_press(action,strength)
	else: Input.action_release(action)

func release_controls() -> void:
	for action in ACTIONS: Input.action_release(action)

func finish(code: int) -> void:
	release_controls()
	if not input_before.is_empty() and get_root().has_node("GameInput"):
		var game_input := get_root().get_node("GameInput")
		game_input.using_gamepad=bool(input_before.using_gamepad)
		game_input.touch_move=input_before.touch_move
	var report: Dictionary = {"checks":checks,"failures":failures,"completed_all_routes":completed_run and route_filter.is_empty(),"completed_selected_routes":completed_run,"drive_route_filter":route_filter,"drives":drives,"checkpoint":checkpoint,"source_stable":fingerprint==FIXTURE.source_fingerprint(),"elapsed_seconds":float(Time.get_ticks_msec()-began)/1000,"scope":"Main real, quatro embarques e inputs produtivos; colocações de fixture somente antes de cada rota. Campanha prévia/conversas não jogadas, obra fechada em teste complementar, sem medição de FPS."}
	if not folder.is_empty():
		var file := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("UNIFIED_MAIN_DRIVE_RESULT ",JSON.stringify(report))
	if is_instance_valid(world): world.free()
	quit(code)
