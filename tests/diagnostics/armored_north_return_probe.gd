extends "res://tests/test_armored_route_session.gd"
## Cobertura dirigida no Main: checkpoint de direção comum offset400 -> os quatro
## corpos reais passam os dois entroncamentos do retorno norte e entram na ponte offset>=690.
## Sem posicionar veículo depois da admissão de produção, sem sinais forçados, sem remover
## trânsito, sem alterar velocidade do motorista nem geometria. Streaming segue só o observador.
## PASS14/14 em2026-10-07,153.9s; vida100%,nenhum apoio faltando.
## Evidência: evidence/armored-north-return-final.log e
## evidence/armored-north-return-50788-5924479/. O serviço do banco não é coberto aqui.
## --desert-highway cobre a preparação comprovada na emenda da ponte setup690 -> os quatro>=1320;
## a preparação bate com capture_armored_night_temporal.gd --bridge-seam. Evidência
## independente por trecho, não a afirmação de outra viagem inteira do banco sem interrupção.
## Rodovia PASS15/15 em124.9s,629..649m porcorpo,vida100%,apoio intacto:
## evidence/armored-desert-highway-proven-bridge.log e
## evidence/armored-desert-highway-9880-5452509/.
## A preparação anterior em offset800 expôs um bug real de altura na admissão virtual na
## rampa descendente (Y linear da rota vs chão físico suave). Logs preservados;
## o início comprovado na ponte abaixo só isola a direção, não prova essa correção.
const JUNCTIONS = preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
var _highway := false
var _target_offset := 690.0
var _start_offset := 400.0
var _segment_limit := 240000
var _contact_samples: Array[Dictionary] = []
var _side_contact_count := 0
var _return_offsets: Array[float] = []

func _initialize() -> void:
	_highway="--desert-highway" in OS.get_cmdline_user_args()
	if _highway:
		_start_offset=690.0
		_target_offset=1320.0
		_segment_limit=300000
	create_timer(390 if _highway else 330).timeout.connect(func(): check(false,"bounded segment Main watchdog"); finish(3))
	run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or not ClassDB.class_exists(&"CSharpScript"):
		quit(2)
		return
	seed(7102026)
	origin="harbor_bank"
	_checkpoint_driving=true
	folder=FIXTURE.output_dir("armored-desert-highway" if _highway else "armored-north-return")
	var point:=Vector3(372,.12,-160)
	var region:="harbor"
	if _highway:
		# Ponto/offset exato do snapshot da captura aprovada --bridge-seam.
		# z=-285 é o deck alargado, ao contrário da preparação mais estreita que falhou em z=-305.
		point=Vector3(335,2.52,-285)
	var snapshot:=FIXTURE.full_snapshot(point,true)
	snapshot.campaign.aftermath={"call_complete":true}
	snapshot.region_id=region
	snapshot.world.pedestrian={"region":region,"position":[point.x,point.y,point.z]}
	snapshot.world.moon_day=1
	snapshot.world.time=9.0/24.0
	snapshot.world.weather=0
	var event:=SCHEDULE.initial(SCHEDULE.departure(1,9.0/24.0),0)
	event.phase="driving"
	event.cargo_cycles=[2,2]
	event.route_offset=_start_offset
	snapshot.world[SCHEDULE.KEY]={"version":1,"last_event":event.id,"security_level":0,"event":event}
	var path:=FIXTURE.write_fixture(folder,"checkpoint.json",snapshot)
	check(not path.is_empty(),"normal offset%d scheduled driving checkpoint accepted"%int(_start_offset))
	if path.is_empty(): finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	var ready_deadline:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<ready_deadline:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and (not _highway or world.production.startup_streaming_settled): break
	check(world.session!=null and world.session.ready_for_play and not world.production.save_invalid,"production Main checkpoint ready")
	if not failures.is_empty(): finish(1); return
	var session=world.session
	if session.modal: session.close_menu()
	check(world.production.no_save and world.production.store.path==path,"personal saves remain disabled")
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	if _highway:
		world.session.weather.weather_state=0
		world.session.weather.weather_timer=3600
		world.session.weather.time_of_day=9.0/24.0
		world.session.weather._update()
	world.production.region.set_focus(point)
	for frame in 3: await physics_frame
	var clear_observer: bool=session.position_clear(point)
	check(clear_observer,"declared observer foothold has real support and capsule clearance")
	if not clear_observer:
		print("SEGMENT_OBSERVER_REJECTED declared=",point," actual=",world.player.global_position)
		finish(1)
		return
	world.player.teleport(point)
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled native router active")
	var convoy=session.armored_transport
	_started=Time.get_ticks_msec()
	var admitted:=false
	var complete:=false
	var progress_anchor:=-INF
	var progress_at:=_started
	var first_offsets: Array[float]=[]
	while Time.get_ticks_msec()-_started<_segment_limit:
		await physics_frame
		if convoy.fleet.size()==4:
			_return_offsets.clear()
			for car in convoy.fleet: _return_offsets.append(convoy.road.get_closest_offset(car.global_position))
			if not admitted:
				admitted=true
				first_offsets=_return_offsets.duplicate()
				check(first_offsets.all(func(offset):return offset<850 if _highway else offset<500),"all four bodies admitted before the segment under validation")
				await photo("return-start")
			var last_offset: float=_return_offsets.min()
			if last_offset>progress_anchor+2.0:
				progress_anchor=last_offset
				progress_at=Time.get_ticks_msec()
				_service_wait_until=0
			_extend_service_wait(convoy)
			if Time.get_ticks_msec()>maxi(progress_at+70000,_service_wait_until):
				check(false,"rear of convoy stopped beyond traffic cycles and real emergency service deadlines")
				break
			if Time.get_ticks_msec()-_last_follow>=500:
				_last_follow=Time.get_ticks_msec()
				_follow(convoy)
				_observe_physics(convoy)
			if _return_offsets.all(func(offset):return offset>=_target_offset):
				complete=true
				_observe_physics(convoy)
				break
		elif admitted:
			_retired=true
			break
		elif Time.get_ticks_msec()-_started>30000:
			check(false,"four physical vehicles admitted within thirty seconds")
			break
		if Time.get_ticks_msec()-_last_trace>=15000:
			_last_trace=Time.get_ticks_msec()
			_trace(convoy)
			print("NORTH_RETURN_OFFSETS ",_return_offsets)
		if not convoy.data.is_empty() and (convoy.data.hostile or world.gameplay.health<=0): break
	check(admitted and not _retired,"four physical convoy bodies retained throughout the return")
	check(complete,"all four vehicles physically reached segment offset%d"%int(_target_offset))
	var occupying:=false
	for center in [Vector3(382.5,0,-262.5),Vector3(367.5,0,-262.5)]:
		for car in convoy.fleet:
			occupying=occupying or JUNCTIONS.occupies(JUNCTIONS.key_of(center),car.get_instance_id())
	check(complete and not occupying,"no convoy hull remains inside either affected crossing")
	check(_travelled.all(func(distance):return distance>(450 if _highway else 240)),"each vehicle drove more than%dm using normal traffic physics"%(450 if _highway else 240))
	check(_floor_failures==0,"all observed vehicle supports remained on actual road or bridge")
	check(_minimum_health>.65,"crossing caused no severe vehicle collision damage")
	check(not convoy.data.hostile and world.gameplay.stars==0,"lawful passage did not incriminate the observer")
	check(convoy.data.taken==[false,false] and convoy.data.pending==0,"route probe grants no robbery reward")
	check(SCHEDULE.valid_saved(session.state.world_state.get(SCHEDULE.KEY,{})),"live route checkpoint remains valid")
	_trace(convoy)
	print("NORTH_RETURN_RESULT ",JSON.stringify({"first_offsets":first_offsets,"final_offsets":_return_offsets,"travelled":_travelled,"checks":checks,"failures":failures,"minimum_health":_minimum_health,"floor_failures":_floor_failures,"side_contact_count":_side_contact_count,"contact_samples":_contact_samples,"coverage":"offset%d to all four bodies >=%d; bank service not covered"%[int(_start_offset),int(_target_offset)]}))
	await photo("return-result")
	finish(0 if failures.is_empty() else 1)

func _observe_physics(convoy) -> void:
	super._observe_physics(convoy)
	# Contatos fora do piso observados na cadência herdada de amostragem de 500 ms.
	# Isto é diagnóstico de colisão, não asserção de cada batida por quadro de física.
	for index in convoy.fleet.size():
		var car: CharacterBody3D=convoy.fleet[index]
		for hit_index in car.get_slide_collision_count():
			var hit:=car.get_slide_collision(hit_index)
			if absf(hit.get_normal().y)>.7: continue
			_side_contact_count+=1
			if _contact_samples.size()>=20: continue
			var collider=hit.get_collider()
			_contact_samples.append({"slot":index,"point":str(car.global_position),"normal":str(hit.get_normal()),"collider":str(collider.get_path()) if collider is Node else str(collider)})
