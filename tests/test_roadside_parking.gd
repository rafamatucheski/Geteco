extends SceneTree
## Main real + vagas em streaming + colisão nativa de Vehicle/Actor. A preparação é explícita;
## isto protege a admissão/ciclo de vida, não a frequência de chegada natural nem o FPS renderizado.
const PARKING := preload("res://runtime/RoadsideParking.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var checks := 0
var failures: Array[String] = []
var world
var folder := ""
var capture_enabled := false
var snapshots: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): check(false,"bounded parking integration timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("ROADSIDE_PARKING ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-save; parking integration owns only an isolated fixture.")
		quit(2)
		return
	capture_enabled = "--parking-capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if capture_enabled: root.size = Vector2i(1280,720)
	folder = "res://evidence/roadside-parking-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var occupied := 0
	var empty := 0
	var two_people := 0
	var specials := 0
	var models := {}
	var mountain_valid := true
	for value in 256:
		var choice := PARKING.profile(value, false)
		if choice.occupied: occupied += 1
		else: empty += 1
		if choice.occupants == 2: two_people += 1
		if choice.special: specials += 1
		models[choice.model] = true
		var mountain := PARKING.profile(value, true)
		mountain_valid = mountain_valid and mountain.model in PARKING.MOUNTAIN_MODELS and not mountain.special
	check(mountain_valid,"256 mountain choices remain off-road")
	check(occupied > 90 and empty > 50,"occupancy varies across visits")
	check(two_people > 20 and two_people < 160,"one/two-occupant variation")
	check(specials > 0 and specials < 45 and models.size() >= 5,"civilian variety and occasional special model")
	for region_id in ["harbor", "mountain"]:
		await check_region(region_id)
	var report := {"checks":checks,"failures":failures,"scope":"real native cars, streamed collision, maneuver, theft ownership, cleanup; scripted staging",
		"rendered_capture":capture_enabled,"performance_certified":false,"snapshots":snapshots}
	var file := FileAccess.open(folder.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("ROADSIDE_PARKING_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func check_region(region_id: String) -> void:
	var state := STATE.new()
	var intro: Dictionary = state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	check(state.intro.restore_snapshot(intro), "isolated intro " + region_id)
	state.set_location(region_id, "")
	state.world_state.time = .45
	var spawn := Vector3(114,.12,65) if region_id == "harbor" else Vector3(618,.12,-299)
	state.world_state.pedestrian = {"region":region_id,"position":[spawn.x,spawn.y,spawn.z]}
	var store := STORE.new()
	store.path = folder.path_join(region_id + ".json")
	check(store.save(state) == OK, "isolated SaveStore fixture " + region_id)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", store.path)
	root.add_child(world)
	for index in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	# restore_location define session.ready por um instante antes de a corrotina de início
	# assentar os chunks e preencher as vagas sob a cortina. Não corre contra esse dono.
	var startup_ready: bool = world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled
	check(startup_ready, "production ready and startup streaming settled " + region_id)
	if not startup_ready:
		world.queue_free()
		await frames(3)
		return
	# Impede que a entrada externa de teclado/controle mova o jogador encenado;
	# trânsito, simulação de pedestres, vida e contatos físicos continuam ativos.
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.set_process_input(false)
	world.driving.set_process_unhandled_input(false)
	world.camera.set_process_unhandled_input(false)
	var director = world.get_node_or_null("RoadsideParking")
	check(director != null,"production installs roadside director " + region_id)
	if director == null:
		world.queue_free()
		await frames(3)
		return
	director.set_physics_process(false)
	director.reset()
	director._discover_regions()
	var candidates: Array = []
	for record in director.records:
		if record.site.region == region_id: candidates.append(record)
	check(not candidates.is_empty(),"authored collision-safe sites " + region_id)
	if candidates.is_empty():
		world.queue_free()
		await frames(3)
		return
	var record: Dictionary = candidates[0]
	world.player.teleport(record.slot.explore_position + record.site.forward * 4 + Vector3.UP * .1)
	world.production.regions[region_id].set_focus(record.slot.position)
	await frames(45)
	record.profile = {"occupied":true,"model":"arctic_jeep" if region_id=="mountain" else "union_sedan","special":false,"occupants":2,"returns":true,"reverse":false}
	check(director._spawn_parked(record),"spawn native parked car on real bay " + region_id)
	if not is_instance_valid(record.car):
		print("ROADSIDE_PARKING_SPAWN_DIAGNOSTIC ",JSON.stringify({"region":region_id,"slot":record.slot.id,"failure":director.last_spawn_failure,"state":director.debug_snapshot()}))
		world.queue_free()
		await frames(3)
		return
	var car: CharacterBody3D = record.car
	if "--parking-arrival-only" in OS.get_cmdline_user_args():
		director.reset()
		await frames(4)
		await check_arrivals(director,record,region_id)
		world.queue_free()
		await frames(4)
		return
	# Fixture explícita fechada/sem visita: a visitação aleatória de spawn não pode decidir
	# se a asserção da trava roda enquanto um passageiro abre a porta.
	director._parked(record, false)
	await frames(8)
	check(world.production.vehicle_position_clear(car,car.global_position+Vector3.UP*.08,car.rotation.y),"chassis has four-wheel support and no solids " + region_id)
	check(not car.traffic and not car.controlled and car.get_meta("vehicle_locked",false),"parked civilian is resting and locked " + region_id)
	var exit_route: Curve3D = director._departure_route(record)
	check(exit_route!=null,"parked car resolves a legal departure route " + region_id)
	if exit_route!=null:
		var wanted_lane := 0
		for road in world.production.ambient_roads_cache:
			if str(road.id)==str(record.site.road_id): wanted_lane=maxi(0,int(road.get("lanes_per_direction",1))-1)
		check(int(exit_route.get_meta("lane_index",-1))==wanted_lane,"departure selects the outer lane on its authored road " + region_id)
		var departure: Vector3 = record.slot.lane_position+record.site.forward*6.0
		var departure_offset := exit_route.get_closest_offset(departure)
		var at := exit_route.sample_baked(departure_offset,true)
		var direction := exit_route.sample_baked(minf(departure_offset+1,exit_route.get_baked_length()),true)-at
		if record.site.slots.size()>1:
			var neighbour_slot: Dictionary = record.site.slots[1]
			var neighbour: CharacterBody3D = world.production.spawn_vehicle(record.profile.model,neighbour_slot.position+Vector3.UP*.1,neighbour_slot.yaw)
			check(neighbour!=null,"native adjacent parked neighbour fixture " + region_id)
			if neighbour!=null:
				await frames(3)
				check(not PARKING.blocks_departure(car,neighbour,at,direction),"parked neighbour outside traffic corridor cannot veto departure " + region_id)
				# A realocação explícita da fixture testa o mesmo corpo físico na faixa.
				# Isto é cobertura de admissão, não afirmação de ter dirigido essa rota.
				neighbour.place(at+direction.normalized()*8+Vector3.UP*.1,record.slot.yaw)
				await frames(2)
				check(PARKING.blocks_departure(car,neighbour,at,direction),"vehicle occupying merge lane retains priority " + region_id)
				record.phase = "leaving"
				director._depart(record)
				check(director.maneuver==null and record.phase=="leaving","departure physically waits for an occupied lane " + region_id)
				world.production.vehicles.erase(neighbour)
				neighbour.queue_free()
				await frames(3)
				director._parked(record,false)
	await capture(region_id+"_parked",car,record)
	if "--parking-departure-only" in OS.get_cmdline_user_args():
		record.phase = "leaving"
		await physical_departure(director,record,car,region_id)
		world.queue_free()
		await frames(4)
		return
	for index in 90:
		if car.warm_doors(1800): break
		await physics_frame
	check(director._exit_occupant(record),"occupant exits on physical shoulder " + region_id)
	await capture(region_id+"_first_occupant",car,record)
	await frames(75)
	await capture(region_id+"_first_exploring",car,record)
	record.exit_count = 1
	check(director._exit_occupant(record),"second occupant exits without overlapping the first " + region_id)
	await frames(5)
	check(director.snapshot().people == 2,"visitor budget includes both occupants " + region_id)
	await capture(region_id+"_second_occupant",car,record)
	record.phase = "returning"
	record.due = 0.0
	record.return_timeout = director.seconds + 25
	for index in 1500:
		await physics_frame
		director.seconds += 1.0 / Engine.physics_ticks_per_second
		director._tick_visit(record)
		if record.phase != "returning": break
	check(record.phase == "leaving","living owners return to door before departure " + region_id)
	await capture(region_id+"_owners_returned",car,record)
	if not await physical_departure(director,record,car,region_id):
		world.queue_free()
		await frames(3)
		return
	# O carro que partiu continua dirigindo normalmente. Um carro estacionado separado,
	# encenado explicitamente, agora exercita roubo/cancelamento sem desfazer essa viagem.
	record.next_visit = director.seconds
	check(director._spawn_parked(record),"independent parked theft fixture after departure " + region_id)
	if not is_instance_valid(record.car):
		world.queue_free()
		await frames(3)
		return
	car = record.car
	director._parked(record,false)
	director.claim_vehicle(car)
	check(not car.get_meta("roadside_parking",false) and not car.has_meta("parking_theft_handler"),"stealing cancels ownership and reservations " + region_id)
	check(car.get_meta("vehicle_locked",false) and car.get_meta("ambient_parked",false),"canceled break-in can retry without losing lock " + region_id)
	check(record.car == null and car.player_damage_attribution,"player claim restores damage attribution " + region_id)
	director.reset()
	check(is_instance_valid(car) and not car.is_queued_for_deletion(),"reset never deletes a claimed car " + region_id)
	check(director.records.is_empty() and director.maneuver == null,"reset clears owned state " + region_id)
	world.production.vehicles.erase(car)
	car.queue_free()
	await frames(4)
	await check_arrivals(director,record,region_id)
	# O obstáculo é introduzido depois da admissão, como outro carro/pessoa entrando
	# na vaga. O motor físico precisa parar em vez de completar a spline.
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 1
	var collider := CollisionShape3D.new()
	var wall := BoxShape3D.new()
	wall.size = Vector3(2.8,2.0,2.8)
	collider.shape = wall
	collider.position.y = 1.0
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.global_position = record.slot.position
	await frames(2)
	record.initialized = false
	record.next_visit = director.seconds
	var bodies_before := get_nodes_in_group("drivable").size()
	check(not director._spawn_parked(record),"occupied slot rejected before vehicle construction " + region_id)
	check(get_nodes_in_group("drivable").size()==bodies_before,"blocked preflight creates no transient drivable body " + region_id)
	check(not record.initialized and record.next_visit>=director.seconds+5,"blocked slot retries later rather than being abandoned " + region_id)
	var delayed_until: float = record.next_visit
	check(not director._spawn_parked(record) and record.next_visit==delayed_until,"immediate retry respects the bounded backoff " + region_id)
	var blocked_car: CharacterBody3D = world.production.spawn_vehicle(record.profile.model,record.slot.approach+Vector3.UP*.10,record.slot.yaw)
	check(blocked_car != null,"obstacle approach fixture " + region_id)
	if blocked_car != null:
		var motor := preload("res://gameplay/roadside_parking/ParkingManeuver.gd").new()
		motor.begin(blocked_car,record.slot.position+Vector3.UP*.10,record.site.forward,false)
		var result := 0
		for index in 1200:
			await physics_frame
			result = motor.step(1.0/Engine.physics_ticks_per_second)
			if result != 0: break
		check(result == -1 and blocked_car.global_position.distance_to(record.slot.position)>2.0,"unexpected solid blocks parking without teleport " + region_id)
		world.production.vehicles.erase(blocked_car)
		blocked_car.queue_free()
	obstacle.queue_free()
	await frames(3)
	director.seconds = maxf(director.seconds, delayed_until + .01)
	check(director._spawn_parked(record),"blocked slot recovers after obstacle removal and retry deadline " + region_id)
	director._release(record,true)
	check(world.production.store.path==store.path,"personal saves untouched " + region_id)
	world.queue_free()
	await frames(4)

func check_arrivals(director: Node, record: Dictionary, region_id: String) -> void:
	# Força as duas variantes de entrada pelo motor de colisão real; as fixtures só
	# põem o carro na faixa correta. Durante cada manobra nenhuma posição é atribuída.
	for backwards in [false,true]:
		director._discover_regions()
		var target: Dictionary = {}
		for candidate in director.records:
			if candidate.slot.id == record.slot.id: target = candidate; break
		var start: Vector3 = target.slot.lane_position + target.site.forward * (8 if backwards else -9)
		var moving: CharacterBody3D = world.production.spawn_vehicle(record.profile.model,start+Vector3.UP*.10,target.slot.yaw)
		check(moving != null,"native lane fixture %s reverse=%s" % [region_id,backwards])
		if moving == null: continue
		director._own(target,moving)
		target.phase = "arriving"
		director._start_maneuver(target,target.slot.position+Vector3.UP*.10,backwards)
		var result := 0
		var threshold := 0
		var thresholds := [.15,.30,.45,.60,.80,1.0]
		for step in 1800:
			await physics_frame
			result = director.maneuver.step(1.0/Engine.physics_ticks_per_second)
			if capture_enabled and threshold < thresholds.size() and director.maneuver.progress >= float(thresholds[threshold]):
				await capture("%s_%s_%02d" % [region_id,"reverse" if backwards else "front",threshold],moving,target,director.maneuver.progress)
				threshold += 1
			if result != 0: break
		check(result==1 and moving.global_position.distance_to(target.slot.position)<.35,"physical front/reverse maneuver %s reverse=%s" % [region_id,backwards])
		if result!=1:
			print("PARKING_ARRIVAL_DIAGNOSTIC ",JSON.stringify({"region":region_id,"reverse":backwards,"health":moving.health,"stunned":moving.has_meta("crash_stun"),"motor":director.maneuver.diagnostic()}))
		director._finish_maneuver(result==1)
		director.reset()
		await frames(4)

func physical_departure(director: Node, record: Dictionary, car: CharacterBody3D, region_id: String) -> bool:
	var neighbour: CharacterBody3D
	var neighbour_start := Vector3.ZERO
	if record.site.slots.size()>1:
		var slot: Dictionary = record.site.slots[1]
		neighbour = world.production.spawn_vehicle(record.profile.model,slot.position+Vector3.UP*.1,slot.yaw)
		check(neighbour!=null,"occupied adjacent bay for physical departure " + region_id)
		if neighbour==null: return false
		await frames(4)
		neighbour_start = neighbour.global_position
	# O trânsito de passagem existente mantém a prioridade. Espera uma brecha real; nunca
	# apaga trânsito, desliga colisão nem teleporta este carro para fabricar uma.
	for step in 900:
		await physics_frame
		if step % 39 == 0: director._depart(record)
		if director.maneuver!=null: break
		if record.phase=="parked": break
	check(director.maneuver!=null,"real lane gap admits physical departure " + region_id)
	if director.maneuver==null:
		print("PARKING_DEPARTURE_DIAGNOSTIC ",JSON.stringify(director.debug_snapshot()))
		return false
	var threshold := 0
	var thresholds := [.15,.30,.45,.60,.80,1.0]
	for step in 2400:
		await physics_frame
		var result: int = director.maneuver.step(1.0/Engine.physics_ticks_per_second)
		if capture_enabled and threshold<thresholds.size() and director.maneuver.progress>=float(thresholds[threshold]):
			await capture("%s_departure_%02d" % [region_id,threshold],car,record,director.maneuver.progress)
			threshold += 1
		if result!=0: director._finish_maneuver(result>0)
		if director.maneuver==null: break
	await frames(6)
	var resumed: bool = car.traffic and car.get_meta("ambient_traffic",false) and not car.get_meta("roadside_parking",false) and record.car==null
	check(resumed,"owners physically depart and rejoin traffic with ownership released " + region_id)
	if is_instance_valid(neighbour):
		var shifted := neighbour.global_position-neighbour_start
		shifted.y = 0
		check(not neighbour.is_queued_for_deletion() and shifted.length()<.08,"adjacent parked car preserved during departure " + region_id)
		# Remove só o vizinho que pertence ao teste depois do evento completo observado.
		world.production.vehicles.erase(neighbour)
		neighbour.queue_free()
		await frames(3)
	if not resumed: print("PARKING_DEPARTURE_DIAGNOSTIC ",JSON.stringify({"state":director.debug_snapshot(),"car_position":str(car.global_position),"traffic":car.traffic}))
	return resumed

func capture(label: String, car: CharacterBody3D, record: Dictionary, progress := -1.0) -> void:
	if not capture_enabled or not is_instance_valid(car): return
	var camera: Camera3D = world.camera
	var previous := {"target":camera.target,"locked":camera.locked,"size":camera.size,"target_size":camera.target_size,
		"focus":camera.focus,"initialized":camera.initialized,"transform":camera.global_transform,"offset":camera.offset,"heading":camera.heading}
	# Mesma câmera externa produtiva, num quadro legível de 20 m. Só a apresentação
	# muda nestes quadros de diagnóstico; restaura o alvo normal depois de cada um.
	camera.target = car
	camera.locked = true
	camera.size = 20.0
	camera.target_size = 20.0
	camera.focus = car.global_position
	camera.offset = preload("res://scripts/CameraRig.gd").EXTERIOR_OFFSET
	camera.heading = 0.0
	camera.initialized = true
	camera.global_position = camera.focus + camera.offset
	camera.look_at(camera.focus)
	for submission in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	var path := folder.path_join(label+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"capture " + label)
	var occupants: Array = []
	for actor in record.actors:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion(): occupants.append({"position":str(actor.global_position),"dead":actor.dead})
	var row := {"label":label,"file":path,"slot":record.slot.id,"phase":record.phase,"progress":progress,
		"car_position":str(car.global_position),"car_yaw":car.rotation.y,"occupants":occupants,"camera_size":camera.size,
		"traffic_population":world.production.vehicles.size(),"pedestrian_population":world.people.size(),"t_ms":Time.get_ticks_msec()}
	snapshots.append(row)
	print("PARKING_CAPTURE_FRAME ",JSON.stringify(row))
	camera.target = previous.target
	camera.locked = previous.locked
	camera.size = previous.size
	camera.target_size = previous.target_size
	camera.focus = previous.focus
	camera.initialized = previous.initialized
	camera.offset = previous.offset
	camera.heading = previous.heading
	camera.global_transform = previous.transform
