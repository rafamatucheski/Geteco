extends Node
## First arrival, saved at narrative boundaries. M00 precedes Primeiro giro.
const CAR := preload("res://world/harbor/campaign/MaciotaTourCar.gd")
const YARD := preload("res://world/shared/salvage/SalvageLocation.gd")
const PARK := YARD.HARBOR_CENTER + Vector2(0,380)
const CAR_SEAT_OFFSET := 35.0
var mission: Node
var world: Node2D
var player: Node2D
var police: Node2D
var car: CharacterBody2D
var maciota: CharacterBody2D
var lines: Array = []
var line_index := 0
var after_dialogue: Callable
var active := false
var tour_route := PackedVector2Array()
var tour_caption := -1
var transition_busy := false
var actor_was_visible := true
var actor_layer := 0
var actor_mask := 0
var riding := false
var motion_tween: Tween
var reserved_lanes: Array[Path2D] = []
var traffic_reservation: Node
var caption_wait := 0.0
var tour_voice_streams: Array[AudioStream] = []
var _boarding_generation := 0
var maciota_layer := 0
var maciota_mask := 0
var exit_pending := false
var cancel_pending := false
var boarding_views: Array[Node] = []
var garage_walk_active := false

func tour_captions() -> Array[String]:
	return [
		say("Aqui é o ferro-velho do Neko. Sempre tem gente atrás de peça por aqui.","This is Neko's scrapyard. People are always looking for parts here."),
		say("O porto vive de carga e de oficina. Muita gente se conhece por causa de carro.","The port runs on cargo and workshops. Cars bring a lot of people together."),
		say("Mas tem quem misture trabalho com contrabando e corrida. É melhor saber com quem você está falando.","Some mix work with smuggling and racing. You should know who you're talking to."),
		say("Minha garagem fica mais à frente. Lá a gente conversa com calma.","My garage is up ahead. We can talk properly there."),
	]

func _reserve_tour() -> void:
	if is_instance_valid(traffic_reservation): return
	traffic_reservation = preload("res://world/harbor/campaign/TourTrafficReservation.gd").new()
	add_child(traffic_reservation)
	traffic_reservation.configure(reserved_lanes, player)

func _release_tour() -> void:
	if is_instance_valid(traffic_reservation):
		remove_child(traffic_reservation)
		traffic_reservation.queue_free()
	traffic_reservation = null

func en() -> bool:
	return TranslationServer.get_locale().begins_with("en")

func say(pt: String, english: String) -> String:
	return english if en() else pt

func configure(owner_mission: Node) -> void:
	mission = owner_mission
	world = mission.world
	player = mission.player
	police = world.get_node("Interiors").police_interior
	active = mission._flag("harbor_story_arrival_v2")
	if not mission._flag("harbor_arrival_call_complete") and not mission._flag("harbor_maciota_met") and not mission._flag("harbor_delivery_started"):
		active = true
		flag("harbor_story_arrival_v2")
	if not active or mission._flag("harbor_maciota_met"): return
	world.get_node("Interiors").actor_returned_to_exterior.connect(_returned)
	world.get_node("Interiors").actor_entered_interior.connect(_entered)
	if not mission._flag("harbor_police_briefed"):
		police.sergeant_npc.set_process_unhandled_input(false)
	if not mission._flag("harbor_city_tour_complete"):
		mission.garage.jager_npc.hide()
		mission.garage.jager_npc.set_process_unhandled_input(false)

func flag(id: String) -> void:
	mission.campaign.set_campaign_flag(StringName(id),true)

func resume() -> void:
	mission._unlock_player()
	if mission._flag("harbor_city_tour_complete"):
		_finish_tour()
	elif mission._flag("harbor_arrival_call_complete"):
		if mission._flag("harbor_city_tour_started"):
			# A save made while seated resumes at the meeting checkpoint, with
			# fresh actors, rather than an invisible passenger without a car.
			player.global_position = PARK+Vector2(-55,0)
			player.reset_physics_interpolation()
		meet_at_yard()
	elif mission._flag("harbor_police_briefed"):
		if police.contains_point(player.global_position):
			mission._set_phase("police_exit",say("Saia da delegacia.","Leave the police station."),police.exit_door.global_position)
		else:
			_wait_for_call()
	else:
		mission._set_phase("police_visit",say("Vá à delegacia perguntar pelo seu irmão.","Ask about your brother at the police station."),world.get_node("District/Police/Entrance").global_position)
		if police.contains_point(player.global_position): _entered(player,&"police")

func interact() -> bool:
	if not active or player.get("is_dead") == true or player.get("is_control_disabled") == true or not player.visible: return false
	if mission.phase == "police_visit" and police.contains_point(player.global_position) and player.global_position.distance_to(police.sergeant_npc.global_position)<90:
		story([
			["DANTE","Vim procurar meu irmão. Vicente Ferraz. Ele estava preso aqui.","I'm looking for my brother. Vicente Ferraz. He was in custody here."],
			["ATENDENTE","Sim. Ele foi solto há alguns meses.","Yes. He was released a few months ago."],
			["DANTE","Há meses? E vocês sabem onde ele está?","Months ago? Do you know where he is?"],
			["ATENDENTE","Ele está envolvido com contrabando de mercadorias para carros e rachas ilegais. Estamos procurando por ele.","He's involved in smuggling car goods and illegal street races. We're looking for him."],
			["DANTE","Espera... contrabando? Eu não estou entendendo.","Wait... smuggling? I don't understand."],
		],_police_done)
		return true
	if mission.phase == "yard_meeting" and is_instance_valid(maciota) and player.global_position.distance_to(maciota.global_position)<85:
		story([
			["MACIOTA","Maciota. E você?","Maciota. And you?"],
			["DANTE","Dante. Foi você que me ligou?","Dante. Were you the one who called?"],
			["MACIOTA","Fui eu, sim. Vamos dar uma volta.","That was me. Let's go for a ride."],
		],_board)
		return true
	if mission.phase == "tour_board" and is_instance_valid(car) and player.global_position.distance_to(car.seat(1))<70:
		_board()
		return true
	return false

func story(script_lines: Array, done: Callable) -> void:
	lines = script_lines
	line_index = 0
	after_dialogue = done
	mission._set_phase("story_dialogue","",Vector2.ZERO)
	mission._lock_player()
	mission._dialog.show()
	_show_line()

func _show_line() -> void:
	mission._speaker.text = lines[line_index][0]
	mission._text.text = lines[line_index][2] if en() else lines[line_index][1]
	mission._next.text = say("Continuar","Continue")
	mission._next.show()
	mission._phone_audio.stop()
	mission._phone_audio.stream = preload("res://ExpressiveVoice.gd").line(mission._text.text,"dante" if lines[line_index][0] == "DANTE" else "maciota")
	mission._phone_audio.play()

func advance() -> void:
	line_index += 1
	if line_index < lines.size():
		_show_line()
		return
	mission._dialog.hide()
	mission._phone_audio.stop()
	mission._unlock_player()
	after_dialogue.call()

func _police_done() -> void:
	flag("harbor_police_briefed")
	police.sergeant_npc.set_process_unhandled_input(true)
	mission._set_phase("police_exit",say("Saia da delegacia.","Leave the police station."),police.exit_door.global_position)

func _returned(actor: Node2D, id: StringName) -> void:
	if actor == player and id == &"police" and mission.phase == "police_exit": _wait_for_call()
	elif actor == player and id == &"police" and mission.phase == "police_visit": resume()

func _wait_for_call() -> void:
	mission._phone_wait = 0
	mission._set_phase("arrival_wait",say("Preciso entender o que aconteceu...","I need to understand what happened..."),Vector2.ZERO)

func _entered(actor: Node2D, id: StringName) -> void:
	if actor != player: return
	if id == &"police" and mission.phase == "police_visit":
		mission._set_phase("police_visit",say("[E] Pergunte pelo seu irmão no balcão.","[E] Ask about your brother at the desk."),world.get_node("District/Police/Entrance").global_position)
	if id == &"garage" and mission._flag("harbor_city_tour_complete") and is_instance_valid(maciota): maciota.hide()

func meet_at_yard() -> void:
	_spawn_encounter()
	mission._set_phase("yard_meeting",say("Encontre o contato no ferro-velho do Neko. [E] Conversar","Meet the contact at Neko's scrapyard. [E] Talk"),maciota.global_position)

func _spawn_encounter() -> void:
	if is_instance_valid(car): return
	car = CAR.new()
	car.position = PARK
	world.add_child(car)
	car.arrived.connect(_arrived)
	car.obstructed.connect(func() -> void:
		mission._text.text = say("Maciota: O caminho está bloqueado. Vamos esperar. [Esc] Descer","Maciota: The road is blocked. Let's wait. [Esc] Get out"))
	maciota = preload("res://JagerNPC.gd").new()
	# The garage contact normally stands still and only has an interaction
	# area. The walking tour actor also needs a real physical body.
	var npc_collision := CollisionShape2D.new()
	npc_collision.name = "WalkingCollision"
	var npc_circle := CircleShape2D.new()
	npc_circle.radius = 8.0
	npc_collision.shape = npc_circle
	maciota.add_child(npc_collision)
	maciota.collision_layer = 2
	maciota.collision_mask = 15
	maciota.position = car.seat(0)+Vector2(0,14)
	world.add_child(maciota)
	maciota.greeting_cooldown = 1000000
	maciota.greeting_label.hide()
	maciota.set_process_unhandled_input(false)
	mission.garage.jager_npc.hide()
	mission.garage.jager_npc.set_process_unhandled_input(false)
	# Prepare while the meeting is set up, not on the first spoken driving frame.
	tour_voice_streams.clear()
	for caption in tour_captions():
		tour_voice_streams.append(preload("res://ExpressiveVoice.gd").line(caption,"maciota"))
	tour_route = build_route()
	_reserve_tour()

func build_route() -> PackedVector2Array:
	# The scrapyard driveway is authored by SalvageLocation; the rest follows
	# directed street lanes and their actual curved intersection connectors.
	reserved_lanes.clear()
	var points := _round_driveway(PackedVector2Array([PARK,Vector2(-750,1000),Vector2(-1250,1000),Vector2(-1250,1225),Vector2(-1180,1225)]))
	var probe := CharacterBody2D.new()
	world.add_child(probe)
	probe.global_position = points[-1]
	var router := preload("res://world/shared/traffic/TaxiRoute.gd").new()
	# Approach the current garage from its service road. The former Dock
	# Street destination required a tight reversal beside articulated buses.
	var road_arrival: Vector2 = mission.entrance.global_position + Vector2(-250,120)
	var legs := router.plan(probe,road_arrival)
	probe.queue_free()
	if legs.is_empty(): return PackedVector2Array()
	for leg in legs:
		var path := leg.path as Path2D
		if not reserved_lanes.has(path): reserved_lanes.append(path)
		var length := float(leg.end)-float(leg.start)
		var steps := maxi(1,ceili(length/10.0))
		for i in steps+1:
			var p := path.to_global(path.curve.sample_baked(lerpf(leg.start,leg.end,float(i)/steps),true))
			if p.distance_to(points[-1])>1: points.append(p)
	# Turn off the service road before lining up parallel to the frontage.
	# Parallel to the frontage, inside the paved access strip and off the
	# service road. Leave room on both sides for the occupants to get out.
	var garage_approach: Vector2 = mission.entrance.global_position + Vector2(-70,45)
	# A shallow lane change keeps the existing heading. Two tight right-angle
	# corners could not fit between this lane and the facade with the full car.
	var final_heading := (points[-1]-points[-2]).angle()
	var parking_poses := preload("res://world/shared/traffic/EmergencyRoadManeuver.gd").connection(Transform2D(final_heading,points[-1]),Transform2D(final_heading,garage_approach),30.0)
	if parking_poses.is_empty(): return PackedVector2Array()
	for pose in parking_poses.slice(1): points.append(pose.origin)
	# Include the public approaches touched by the complete authored route. Their
	# existing cars must be allowed to drain through the closure, not trapped
	# immediately in front of the mission car at its first turn.
	var roads: Dictionary = {}
	for lane in reserved_lanes:
		var road_id := String(lane.get_meta("traffic_road_id",""))
		if not road_id.is_empty(): roads[road_id] = true
	for lane in get_tree().get_nodes_in_group("unified_traffic_lane"):
		if not lane is Path2D or lane.curve == null: continue
		var include := roads.has(String(lane.get_meta("traffic_road_id","")))
		for corner in points:
			if include: break
			if lane.to_global(lane.curve.get_closest_point(lane.to_local(corner))).distance_to(corner) < 100: include = true
		if include and not reserved_lanes.has(lane): reserved_lanes.append(lane)
	var sampled := PackedVector2Array([points[0]])
	for i in range(1,points.size()):
		var steps := maxi(1,ceili(points[i-1].distance_to(points[i])/10.0))
		for j in range(1,steps+1): sampled.append(points[i-1].lerp(points[i],float(j)/steps))
	return sampled

func _round_driveway(corners: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array([corners[0]])
	for i in range(1,corners.size()-1):
		var radius := minf(36,minf(corners[i-1].distance_to(corners[i]),corners[i].distance_to(corners[i+1]))*.4)
		var a := corners[i]+corners[i].direction_to(corners[i-1])*radius
		var b := corners[i]+corners[i].direction_to(corners[i+1])*radius
		result.append(a)
		for j in range(1,9):
			var t := float(j)/8
			result.append(a.lerp(corners[i],t).lerp(corners[i].lerp(b,t),t))
	result.append(corners[-1])
	return result

func _board() -> void:
	if transition_busy: return
	if tour_route.is_empty(): tour_route = build_route()
	if tour_route.is_empty():
		mission._set_phase("tour_board",say("Aguarde a rua liberar. [E] Tentar a volta","Wait for the street to clear. [E] Try the ride"),car.seat(1))
		return
	transition_busy = true
	_boarding_generation += 1
	var generation := _boarding_generation
	_reserve_tour()
	mission._set_phase("tour_boarding","",Vector2.ZERO)
	mission._lock_player()
	# Walking to separate doors stays visible; the actor is hidden only seated.
	var forward := Vector2.from_angle(car.heading)
	var normal := Vector2.from_angle(car.heading+PI/2)
	var passenger_door: Vector2 = car.seat(1)
	# Go around the front bumper when Dante approaches from the driver side.
	var steps := PackedVector2Array()
	if (player.global_position-car.global_position).dot(normal)<0:
		steps.append(car.global_position+forward*65-normal*42)
		steps.append(car.global_position+forward*65+normal*42)
	steps.append(passenger_door)
	for point in steps:
		if not await _walk_to(player,point,generation):
			_board_failed()
			return
	if not await _walk_to(maciota,car.seat(0),generation):
		_board_failed()
		return
	car.model.door(0,true)
	car.model.door(1,true)
	await get_tree().create_timer(.5).timeout
	# Reach and bend before the seat handoff. The transition has its own pose.
	var entry_pose := preload("res://scripts/player/VehicleBoardingPose.gd").new()
	entry_pose.setup(player)
	var entry_view := _show_boarding_depth(player,1.0)
	var driver_view := _show_boarding_depth(maciota,-1.0)
	var driver_pose := preload("res://world/harbor/campaign/MaciotaBoardingPose.gd").new()
	driver_pose.setup(maciota)
	var driver_physics: bool = maciota.is_physics_processing()
	maciota.set_physics_process(false)
	var was_physics: bool = player.is_physics_processing()
	player.set_physics_process(false)
	var entry_time := 0.0
	while entry_time < .9 and generation == _boarding_generation:
		await get_tree().physics_frame
		entry_time += get_physics_process_delta_time()
		entry_pose.apply(player,"car",1.0,clampf(entry_time/.9,0.0,1.0),car.heading)
		entry_view.entry = clampf(entry_time/.9,0.0,1.0)
		driver_view.entry = entry_view.entry
		driver_pose.apply(entry_view.entry,car.heading)
	entry_pose.restore()
	driver_pose.restore()
	_clear_boarding_views()
	maciota.set_physics_process(driver_physics)
	player.set_physics_process(was_physics)
	if not is_instance_valid(player): return
	actor_was_visible = player.visible
	actor_layer = player.collision_layer
	actor_mask = player.collision_mask
	player.collision_layer = 0
	player.collision_mask = 0
	maciota_layer = maciota.collision_layer
	maciota_mask = maciota.collision_mask
	maciota.collision_layer = 0
	maciota.collision_mask = 0
	player.hide()
	maciota.hide()
	for person in car.model.occupants: person.show()
	car.model.door(0,false)
	car.model.door(1,false)
	await get_tree().create_timer(.55).timeout
	riding = true
	flag("harbor_city_tour_started")
	transition_busy = false
	tour_caption = -1
	caption_wait = 4.0
	mission._set_phase("city_tour",say("Conheça a cidade com Maciota.","See the city with Maciota."),mission.entrance.global_position)
	mission._dialog.hide()
	mission._next.hide()
	car.start(tour_route)

func _walk_to(actor: CharacterBody2D, point: Vector2, generation: int) -> bool:
	var was_physics := actor.is_physics_processing()
	actor.set_physics_process(false)
	var waited := 0.0
	var elapsed := 0.0
	var limit := actor.global_position.distance_to(point)/40.0+3.0
	var depth: Node
	while actor.global_position.distance_to(point) > 1.5 and generation == _boarding_generation:
		await get_tree().physics_frame
		var delta := get_physics_process_delta_time()
		elapsed += delta
		var offset := point-actor.global_position
		var before := actor.global_position
		if is_instance_valid(car) and actor.global_position.distance_to(car.global_position) < 72 and depth == null:
			depth = _show_boarding_depth(actor,1.0 if actor == player else -1.0)
		actor.velocity = offset.normalized()*minf(58.0,offset.length()/maxf(delta,.001))
		actor.move_and_slide()
		var moved := actor.global_position.distance_to(before)
		if actor.has_method("_advance_gait"):
			actor._advance_gait(moved,delta,moved>.01,false)
			actor._update_locomotion(delta,moved>.01,false)
			actor.combat_pose.update(actor,delta,false,false,actor._gait_arm_swing())
		if is_instance_valid(actor.model_root): actor.model_root.rotation.y = -offset.angle()-PI*.5
		waited = waited+delta if moved < .01 else 0.0
		if waited > 2.0 or elapsed > limit:
			actor.velocity = Vector2.ZERO
			actor.set_physics_process(was_physics)
			return false
	actor.velocity = Vector2.ZERO
	actor.set_physics_process(was_physics)
	return generation == _boarding_generation

func _show_boarding_depth(actor: CharacterBody2D, side: float) -> Node:
	for view in boarding_views:
		if is_instance_valid(view) and view.actor == actor: return view
	var view := preload("res://world/harbor/campaign/TourActorPresentation.gd").new()
	add_child(view)
	view.configure(actor,car,side)
	boarding_views.append(view)
	return view

func _clear_boarding_views() -> void:
	for view in boarding_views:
		if is_instance_valid(view):
			view.restore()
			view.queue_free()
	boarding_views.clear()

func _board_failed() -> void:
	_clear_boarding_views()
	_release_tour()
	transition_busy = false
	mission._unlock_player()
	mission._set_phase("tour_board",say("[E] Aproxime-se da porta do passageiro para entrar.","[E] Approach the passenger door to board."),car.seat(1))

func _process(_delta: float) -> void:
	if not active: return
	if is_instance_valid(maciota):
		maciota.prompt_badge.visible = mission.phase == "yard_meeting" and player.global_position.distance_to(maciota.global_position)<85
	if riding and is_instance_valid(car):
		player.global_position = car.global_position
		if cancel_pending:
			cancel_ride()
			return
		if exit_pending:
			_arrived()
			return
		if player.get("is_dead") == true or player.get("is_arrested") == true:
			cancel_ride()
			return
		caption_wait = maxf(0.0,caption_wait-_delta)
		var index := tour_caption+1
		if index < 4 and caption_wait <= 0 and not mission._phone_audio.playing and car.travelled >= index*600.0:
			tour_caption = index
			var captions := [
				say("Aqui é o ferro-velho do Neko. Sempre tem gente atrás de peça por aqui.","This is Neko's scrapyard. People are always looking for parts here."),
				say("O porto vive de carga e de oficina. Muita gente se conhece por causa de carro.","The port runs on cargo and workshops. Cars bring a lot of people together."),
				say("Mas tem quem misture trabalho com contrabando e corrida. É melhor saber com quem você está falando.","Some mix work with smuggling and racing. You should know who you're talking to."),
				say("Minha garagem fica mais à frente. Lá a gente conversa com calma.","My garage is up ahead. We can talk properly there."),
			]
			mission._dialog.show()
			mission._speaker.text = "MACIOTA"
			mission._text.text = captions[index]
			mission._phone_audio.stream = tour_voice_streams[index]
			mission._phone_audio.play()
			caption_wait = maxf(7.0,mission._phone_audio.stream.get_length())+3.0

func _arrived() -> void:
	if not _restore_rider():
		exit_pending = true
		return
	exit_pending = false
	flag("harbor_city_tour_complete")
	_finish_tour()

func _restore_rider() -> bool:
	if not riding: return true
	car.driving = false
	car.speed = 0
	car.velocity = Vector2.ZERO
	car.pose()
	var dante_exit := _safe_exit(player,1)
	var maciota_exit := _safe_exit(maciota,0,dante_exit)
	if not dante_exit.is_finite() or not maciota_exit.is_finite():
		mission._dialog.show()
		mission._text.text = say("Aguarde um espaço livre para descer.","Wait for a clear space to get out.")
		return false
	riding = false
	_release_tour()
	car.driving = false
	car.velocity = Vector2.ZERO
	car.model.door(0,true)
	car.model.door(1,true)
	player.global_position = dante_exit
	player.reset_physics_interpolation()
	player.collision_layer = actor_layer
	player.collision_mask = actor_mask
	player.visible = actor_was_visible
	player.velocity = Vector2.ZERO
	maciota.global_position = maciota_exit
	maciota.reset_physics_interpolation()
	maciota.collision_layer = maciota_layer
	maciota.collision_mask = maciota_mask
	maciota.show()
	for person in car.model.occupants: person.hide()
	var door_car := car
	create_tween().tween_interval(.65).finished.connect(func() -> void:
		if is_instance_valid(door_car):
			door_car.model.door(0,false)
			door_car.model.door(1,false))
	mission._dialog.hide()
	mission._next.show()
	mission._phone_audio.stop()
	mission._unlock_player()
	return true

func _safe_exit(actor: CharacterBody2D, side: int, occupied := Vector2.INF) -> Vector2:
	var forward := Vector2.from_angle(car.heading)
	var outward := Vector2.from_angle(car.heading+PI*.5)
	# Try the requested sill first, then the opposite side if a roadside post,
	# parked car, or another solid blocks the normal exit. The wider sedan needs
	# a larger walk-out envelope than the former coupe.
	var requested_sign := 1.0 if side == 1 else -1.0
	# Passenger exits preserve the mission's explicit "blocked" contract: a
	# parked obstacle keeps Dante seated until the space is actually free. The
	# driver gets a wider fallback envelope so roadside furniture beside the new
	# sedan does not deadlock the end of the tour.
	var side_signs := [requested_sign] if side == 1 else [requested_sign, -requested_sign]
	var lateral_options := [0.0,12.0,24.0,40.0] if side == 1 else [0.0,12.0,24.0,40.0,56.0,72.0,92.0]
	for side_sign in side_signs:
		var normal: Vector2 = outward*side_sign
		for lateral in lateral_options:
			for along in [0.0,-18.0,18.0,-36.0,36.0]:
				var at: Vector2 = car.global_position+normal*(CAR_SEAT_OFFSET+float(lateral))+forward*float(along)
				if occupied.is_finite() and at.distance_to(occupied)<30: continue
				var clear := true
				for collision in actor.get_children():
					if not collision is CollisionShape2D or collision.shape == null: continue
					var query := PhysicsShapeQueryParameters2D.new()
					query.shape = collision.shape
					query.transform = Transform2D(0,at)*collision.transform
					query.collision_mask = 15
					query.margin = 2.0
					query.exclude = [player.get_rid(),maciota.get_rid()]
					if not actor.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): clear = false; break
				if clear: return at
	return Vector2.INF

func _finish_tour() -> void:
	if is_instance_valid(maciota) and maciota.visible and not garage_walk_active and not mission.garage.contains_point(player.global_position):
		_walk_to_garage()
	mission.garage.jager_npc.show()
	mission.garage.jager_npc.set_process_unhandled_input(true)
	mission.garage.set_campaign_contact_enabled(true)
	mission._set_phase("meet_maciota",say("Entre na garagem e converse com Maciota.","Enter the garage and talk to Maciota."),mission.entrance.global_position)

func _walk_to_garage() -> void:
	garage_walk_active = true
	var forward := Vector2.from_angle(car.heading)
	var normal := Vector2.from_angle(car.heading+PI*.5)
	var lateral: float = (maciota.global_position-car.global_position).dot(normal)
	if not await _walk_to(maciota,car.global_position+forward*65+normal*lateral,_boarding_generation):
		_clear_boarding_views()
		garage_walk_active = false
		return
	var entry: Vector2 = mission.entrance.global_position + Vector2(0,32)
	if not await _walk_to(maciota,Vector2(entry.x,maciota.global_position.y),_boarding_generation):
		_clear_boarding_views()
		garage_walk_active = false
		return
	if await _walk_to(maciota,entry,_boarding_generation): maciota.hide()
	_clear_boarding_views()
	garage_walk_active = false

func cancel_ride() -> void:
	if not _restore_rider():
		cancel_pending = true
		return
	cancel_pending = false
	# Resume from this car's physical location, without replaying or teleporting.
	tour_route = car.route.slice(maxi(0,car.cursor-1))
	if not tour_route.is_empty(): tour_route[0] = car.global_position
	mission._set_phase("tour_board",say("[E] Voltar ao passageiro para continuar o passeio","[E] Return to the passenger seat to continue the ride"),car.seat(1))

func _exit_tree() -> void:
	_boarding_generation += 1
	_clear_boarding_views()
	_release_tour()
	if motion_tween != null and motion_tween.is_valid(): motion_tween.kill()
	if riding and is_instance_valid(player):
		riding = false
		player.visible = actor_was_visible
		player.collision_layer = actor_layer
		player.collision_mask = actor_mask
		mission._unlock_player()
	if is_instance_valid(car): car.queue_free()
	if is_instance_valid(maciota): maciota.queue_free()
