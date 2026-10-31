extends "res://tests/measure/measure_desert.gd"
## Main real com carro real, ações comuns de Input e câmera de jogo.
## --baseline suprime só o novo teste; as duas variantes fazem a mesma lavagem.
const COURSE := preload("res://activities/desert_wash/DesertWashCourse.gd")
var race
var car
var baseline:=false
var functional:=false
var trace: Array[Dictionary]=[]
var failures: Array[String]=[]

func fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func run() -> void:
	functional="--functional" in OS.get_cmdline_user_args()
	if (not functional and (DisplayServer.get_name()=="headless" or "--benchmark" not in OS.get_cmdline_user_args())) or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET with --benchmark --no-save required"); quit(2); return
	baseline="--baseline" in OS.get_cmdline_user_args()
	Engine.set_meta("desert_wash_benchmark_disabled",baseline)
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-wash-baseline" if baseline else "desert-wash-after")
	var start:=COURSE.gate(0)
	# Mantém o pedestre salvo fora da carroceria do carro pedido. O spawn de produção
	# rejeita com razão a sobreposição com o Dante; a fixture precisa obedecer essa admissão.
	var pedestrian_start:=start+COURSE.direction(0).cross(Vector3.UP)*6.0
	var snapshot:=FIXTURE.full_snapshot(pedestrian_start,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[pedestrian_start.x,pedestrian_start.y,pedestrian_start.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	fingerprint=source_fingerprint()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path or world.production.save_invalid:
		push_error("Isolated Main failed startup"); quit(1); return
	if world.player.global_position.distance_to(pedestrian_start)>3.0:
		push_error("Saved wash pedestrian was not admitted: "+str(world.player.global_position)); quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: push_error("Compiled .NET required"); quit(1); return
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	world.production.region.prepare_collision_at(start)
	await create_timer(2).timeout
	var yaw:=Basis.looking_at(COURSE.direction(0),Vector3.UP).get_euler().y
	car=world.production.spawn_vehicle("desert_coyote",start,yaw)
	if not is_instance_valid(car): push_error("Wash car rejected"); quit(1); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	if not world.driving.interact():
		print("WASH_BOARD_DIAGNOSTIC ",{"player":str(world.player.global_position),"car":str(car.global_position),"door":str(car.driver_door_anchor(1)),"player_locked":world.player.input_locked,"transition":world.session.is_transition_blocked(),"busy":world.session.desert.busy(),"speed":car.speed,"visible":car.is_visible_in_tree(),"awaiting":car.has_meta("awaiting_ground"),"entry":world.driving._entry_option()})
		push_error("Ordinary car boarding rejected"); quit(1); return
	for i in 600:
		await physics_frame
		if world.driving.occupied and world.driving.car==car and car.controlled and not car.input_locked and not world.driving.is_body_transition_active(): break
	if not world.driving.occupied or car.input_locked: push_error("Boarding not finished"); quit(1); return
	if not baseline:
		race=world.find_child("DesertWash",true,false)
		if not is_instance_valid(race):
			push_error("Production session did not install wash activity"); quit(1); return
	if not functional:
		await create_timer(10).timeout
		await measure("wash-start")
	else:
		for i in 60: await physics_frame
	if not baseline:
		if world.session.nearest().get("target","")!="wash:start": fail("Public E action did not discover wash")
		if not world.session.interact() or not race.active: push_error("Start blocked: "+race.start_block_reason()); quit(1); return
		# Safe abort and immediate retry prove countdown unlocks normal vehicle input.
		if race.save_block_reason().is_empty(): fail("Active race did not block save")
		var count_before: float=race.countdown
		world.session._menu("Pausa")
		for i in 12: await physics_frame
		if not is_equal_approx(count_before,race.countdown): fail("Modal failed to pause countdown")
		world.session.close_menu()
		if not world.session.interact(): fail("Public E cancel rejected")
		if car.input_locked or race.active: fail("Cancel leaked control lock")
		if not world.session.interact() or not race.active: fail("Public E retry blocked")
		while race.active and race.phase=="countdown": await physics_frame
		if not race.active: fail("Countdown failed")
		var elapsed_before: float=race.elapsed
		world.session._menu("Pausa")
		for i in 12: await physics_frame
		if not is_equal_approx(elapsed_before,race.elapsed): fail("Modal failed to pause running clock")
		world.session.close_menu()
		if car.input_locked: fail("Closing pause blocked ordinary steering")
	else: await create_timer(3).timeout
	samples.clear(); cpu.clear(); physics.clear()
	previous=Time.get_ticks_usec(); sampling=true
	var deadline:=Time.get_ticks_msec()+65000
	var last_capture:=0
	var route_done:=false
	while Time.get_ticks_msec()<deadline:
		var p: Vector3=car.global_position
		var t:=clampf((-p.z-970)/210,COURSE.START_T,COURSE.END_T)
		var target:=COURSE.point(minf(1.0,t+.045))
		var desired:=atan2(-(target-p).x,-(target-p).z)
		var difference:=angle_difference(car.rotation.y,desired)
		var steer:=clampf(difference*3.5,-1.0,1.0)
		Input.action_release("move_left"); Input.action_release("move_right")
		Input.action_press("move_left" if steer>0 else "move_right",absf(steer))
		Input.action_press("accelerate",clampf((7.5-car.speed)*.3,0.0,.65))
		if Time.get_ticks_msec()-last_capture>1000:
			last_capture=Time.get_ticks_msec()
			trace.append({"position":[p.x,p.y,p.z],"speed":car.speed,"gate":race.next_gate if is_instance_valid(race) else 0,"seconds":Time.get_ticks_msec()/1000.0,"on_floor":car.is_on_floor()})
			# A rodada visual opcional é marcada à parte: travadas de compressão PNG nunca
			# podem ser confundidas com desempenho comum de quadro no relatório A/B.
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("route-%03d.png"%trace.size()))
		if p.y<-.5: fail("Vehicle fell through course"); break
		if COURSE.distance_to_course(p)>16: fail("Input-driven car left course"); break
		if (p-COURSE.gate(COURSE.GATES-1)).dot(COURSE.direction(COURSE.GATES-1))>1.0:
			route_done=true; break
		if not baseline and not race.active:
			route_done=race.last_result.get("finished",false)
			break
		await physics_frame
	sampling=false
	for action in ["move_left","move_right","accelerate"]: Input.action_release(action)
	Input.action_press("handbrake")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("wash-finish.png"))
	if not route_done: fail("Route did not finish physically")
	if not baseline and not race.last_result.get("finished",false): fail("Sequential checkpoint finish missing")
	if not baseline and car.input_locked: fail("Finish leaked input lock")
	var completed_result: Dictionary=race.last_result.duplicate(true) if is_instance_valid(race) else {}
	reports.append({"id":"wash-physical-route","summary":stats(samples),"intervals_ms":samples.duplicate(),"cpu_ms":cpu.duplicate(),"physics_ms":physics.duplicate(),"trace":trace})
	if functional and not baseline and failures.is_empty(): await verify_discontinuity()
	var report:={"baseline":baseline,"functional_only":functional,"capture_run":"--capture" in OS.get_cmdline_user_args(),"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"source_stable":fingerprint==source_fingerprint(fingerprint),"scenarios":reports,"failures":failures,"result":completed_result}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WASH_MEASURE ",output," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func verify_discontinuity() -> void:
	# Caso adversarial DEPOIS do término genuíno guiado por entrada; estes teleportes
	# explícitos da fixture nunca contam para a rota validada nem para o tempo dela.
	var saved: Dictionary=preload("res://activities/desert_wash/DesertWashState.gd").data(world.session.state.world_state)
	var balance: int=world.session.state.economy.balance
	var start:=COURSE.gate(0)
	world.production.region.prepare_collision_at(start)
	await physics_frame
	car.place(start,Basis.looking_at(COURSE.direction(0),Vector3.UP).get_euler().y)
	Input.action_release("handbrake")
	for i in 30: await physics_frame
	if not world.session.interact() or not race.active: fail("Anti-teleport setup rejected"); return
	while race.active and race.phase=="countdown": await physics_frame
	var before: Vector3=car.global_position
	car.place(COURSE.gate(3),car.rotation.y)
	for i in 3: await physics_frame
	if race.active or race.last_result.get("reason","")!="discontinuity": fail("Teleport advanced race instead of cancelling")
	if preload("res://activities/desert_wash/DesertWashState.gd").data(world.session.state.world_state)!=saved or world.session.state.economy.balance!=balance: fail("Rejected teleport changed progress or wallet")
	if car.input_locked: fail("Rejected teleport leaked controls")
	print("WASH_GUARDS teleport_cancel=",race.last_result," displacement=",before.distance_to(car.global_position))

func source_fingerprint(reference: Dictionary = {}) -> Dictionary:
	var result:=super.source_fingerprint(reference)
	if not reference.is_empty(): return result
	for filename in DirAccess.get_files_at("res://activities/desert_wash"):
		if filename.ends_with(".gd"):
			var path:="res://activities/desert_wash/"+filename
			result[path]=FileAccess.get_sha256(path)
	result["res://tests/measure/measure_desert_wash.gd"]=FileAccess.get_sha256("res://tests/measure/measure_desert_wash.gd")
	return result
