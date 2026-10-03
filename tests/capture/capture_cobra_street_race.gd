extends SceneTree
const COURSE:=preload("res://gameplay/urban_v1/CobraRaceCourse.gd")
var world
var failures: Array[String]=[]
var folder:="D:/geteco/artifacts/cobra-race-1002"
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func photo(label: String) -> void:
	if DisplayServer.get_name()=="headless" or "--no-photos" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): folder=argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(folder)
	create_timer(250).timeout.connect(func(): quit(3))
	seed(77001700)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play: await process_frame
	var session=world.session
	# Alvo de observação duradouro: dano continua ativo; o carro mantém a
	# durabilidade normal. A morte do jogador já encerrou a primeira captura.
	world.gameplay.health=5000
	session.weather.time_of_day=.45
	session.weather.weather_state=0
	session.weather._update()
	if "--measure" in OS.get_cmdline_user_args(): session.weather.set_process(false)
	var snapshot: Dictionary=session.state.campaign.snapshot()
	snapshot.completed=["primeiro_giro","cobra_contact"]
	snapshot.claimed_rewards=snapshot.completed.duplicate()
	snapshot.flags={"harbor_delivery_complete":true,"cobra_contact_complete":true}
	snapshot.active_id=""
	check(session.state.campaign.restore_snapshot(snapshot) and session.state.campaign.begin("cobra_race"),"Campaign pre-race restored")
	var mission=session.mission_world
	var car=world.driving.car
	car.place(mission.targets.ashbend_start+Vector3(-1.4,.12,3),0)
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.2+Vector3.UP*.1)
	world.production.region.set_focus(car.global_position)
	await create_timer(4).timeout
	check(world.driving.interact(),"Player enters real starting car")
	await create_timer(3).timeout
	check(world.driving.occupied,"Player is driving")
	if not world.driving.occupied: quit(1); return
	car=world.driving.car
	car.place(mission.targets.ashbend_start+Vector3(-1.4,.12,3),0)
	car.speed=0
	car.horizontal_velocity=Vector3.ZERO
	await physics_frame
	check(mission.perform("race_start"),"Player answers Cobra phone")
	for child in session.column.get_children():
		if child is Button and child.text=="Entrar na corrida": child.pressed.emit(); break
	var race=mission.street_race
	check(is_instance_valid(race) and race.running,"Confirmed phone creates real starting grid")
	if not is_instance_valid(race) or not race.running: quit(1); return
	check(race.racers.size()==6 and race.racers.filter(func(e):return e.cobra).size()==3,"Six cars: player, three Cobras, two guests")
	check(race.racers.filter(func(e):return e.car.archetype=="ranch_pickup").size()==1,"Grid includes racing pickup")
	var types:=[]
	for entry in race.racers:
		if entry.car.archetype not in types: types.append(entry.car.archetype)
		check(entry.car.collision_layer!=0 and entry.car.collision_mask!=0,"Racer keeps physical collision: "+entry.name)
	check(types.size()>=4,"Grid has at least four different vehicle models")
	check(race.gates.size()==4,"Four blue street checkpoints instantiated")
	world.camera.target_size=29
	await photo("grid")
	await create_timer(3.3).timeout
	check(not car.input_locked and session.state.campaign.race_status().get("countdown",-1)==0,"Countdown unlocks player's car")
	if "--chaos" in OS.get_cmdline_user_args():
		await chaos(race,car)
		return
	if "--finish-order" in OS.get_cmdline_user_args(): stage_finish(race,car)
	var driver:=preload("res://gameplay/urban_v1/CobraRaceDriver.gd").new()
	# O jogador larga na coluna da esquerda; preservar essa faixa evita que
	# o piloto do teste vire contra a caminhonete ao lado na própria largada.
	driver.setup(car,21.0,"--finish-order" not in OS.get_cmdline_user_args())
	car.player_damage_attribution=true
	var samples: Array[float]=[]
	var start:=Time.get_ticks_usec()
	var last:=start
	var next_photo:=0.0
	var rivals=race.racers.duplicate()
	while race.running and Time.get_ticks_usec()-start<(COURSE.TIME_LIMIT+5)*1e6:
		await process_frame
		var now:=Time.get_ticks_usec()
		var delta:=(now-last)/1e6
		samples.append((now-last)/1000.0)
		last=now
		if race.running: driver.tick(delta,false)
		var elapsed:=(now-start)/1e6
		if elapsed>=next_photo:
			print("STREET_AT ",snappedf(elapsed,.1)," position=",car.global_position," checkpoint=",session.state.campaign.race_status().get("checkpoint",-1)," health=",car.health," racers=",rivals.map(func(e): return {"name":e.name,"gate":e.run.get("checkpoint",-1),"dead":e.dnf,"position":str(e.car.global_position) if is_instance_valid(e.car) else "freed"}))
			await photo("race_%03d"%int(elapsed))
			next_photo=elapsed+10
	var finished: bool=session.state.campaign.snapshot().completed.has("cobra_race")
	var reason: String=session.state.campaign.snapshot().failure
	check(finished or reason=="race_lost","Physical street race resolves by finish order")
	if "--finish-order" not in OS.get_cmdline_user_args():
		check(rivals.filter(func(e):return not e.player and e.run.get("checkpoint",0)>=2).size()>=2,"Multiple rivals physically cross spaced street checkpoints")
	else:
		check(not finished and reason=="race_lost","Rival crossing first defeats player at real finish")
	check(rivals.filter(func(e):return is_finite(e.finish)).size()>=1,"At least one vehicle reaches actual finish")
	check(not race.running and race.gates.is_empty(),"Race resolution removes markers and stops race ownership")
	print("STREET_RESULT won=",finished," failure=",reason)
	car.set_external_driver(false)
	await photo("result")
	var sorted:=samples.duplicate()
	sorted.sort()
	var report:={"frames_ms":samples,"duration":(last-start)/1e6,"fps":samples.size()*1e6/(last-start),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":samples.filter(func(v):return v>33.3).size(),"over66":samples.filter(func(v):return v>66.7).size(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps}
	FileAccess.open(folder+"/race-frames.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	report.erase("frames_ms")
	print("STREET_PERF ",JSON.stringify(report))
	print("STREET_RACE failures=",failures)
	quit(0 if failures.is_empty() else 1)

func stage_finish(race, car) -> void:
	# Fixture de chegada, independente da auditoria do percurso inteiro: simula
	# os três primeiros portões já cumpridos, depois dirige fisicamente o último.
	var progress=preload("res://systems/campaign/CobraStreetProgress.gd")
	for i in race.racers.size():
		var entry: Dictionary=race.racers[i]
		var distance: float=[6.0,45.0,60.0,28.0,80.0,95.0][i]
		var at: Vector3=COURSE.gate(3)-COURSE.forward(3)*distance
		entry.car.place(at+Vector3.UP*.1,PI)
		entry.car.speed=0
		entry.car.horizontal_velocity=Vector3.ZERO
		entry.run=progress.start(entry.car.vehicle_id,Vector2(at.x,at.z))
		entry.run.countdown=0
		entry.run.initialized=true
		entry.run.checkpoint=3
		entry.run.progress=COURSE.offset(at,3)
		entry.elapsed=100.0
		entry.outside=0
	var campaign=world.session.state.campaign
	campaign._data.race_run=race.racers[3].run.duplicate(true)
	campaign._data.step=4
	campaign._data.race_elapsed=100.0
	world.production.region.set_focus(car.global_position)

func chaos(race, car) -> void:
	var rivals: Array=race.racers.duplicate()
	var victim=rivals[0].car
	world.gameplay.explode(victim.global_position+Vector3.UP*.4,2.0,500.0,car,true)
	await create_timer(1).timeout
	check(not is_instance_valid(victim) or victim.health<=0,"Real explosion destroys rival vehicle")
	check(race.running and rivals[0].dnf,"Destroyed rival is out; remaining racers continue")
	await photo("rival-explosion")
	world.gameplay.explode(car.global_position+Vector3.UP*.4,2.0,500.0,null,false)
	await create_timer(1).timeout
	check(car.health<=0,"Player's racing vehicle retains real explosion damage")
	check(not race.running and race.gates.is_empty(),"Destroyed player car cleans up race and gates")
	check(not car.input_locked,"Cancellation releases starting lock")
	check(rivals.filter(func(e):return is_instance_valid(e.car) and e.car.has_meta("race_owned")).is_empty(),"Cancellation releases all five persistent rivals")
	check(not world.session.state.campaign.snapshot().completed.has("cobra_race"),"Destruction cannot award a race win")
	await photo("cancelled-explosion")
	print("STREET_CHAOS failures=",failures)
	quit(0 if failures.is_empty() else 1)
