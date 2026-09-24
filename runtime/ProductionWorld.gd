extends Node
const REGION := preload("res://world/regions/NativeRegion.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const PORT_POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
# Orçamento medido em 2026-09-23 (RTX 4060 Laptop, 1280x720): 100 pedestres + 100 carros
# + 3 estrelas custavam 25,8 ms de física/scripts por quadro e derrubavam para 34,5 FPS;
# 40 pedestres mantiveram 59,8 FPS no mesmo cenário.
const MAX_POPULATION := 40
const TRAFFIC_TARGET := 40
# Como em GTA: gente e trânsito ambiente nascem e somem num anel em volta do jogador,
# sempre fora do quadro da câmera, para nada aparecer ou desaparecer na tela.
const POPULATION_SPAWN_MIN := 45.0
const POPULATION_SPAWN_MAX := 95.0
const POPULATION_DESPAWN := 120.0
const TRAFFIC_CAR_TYPES := ["sport_coupe", "union_sedan", "courier_van", "ranch_single", "arctic_jeep", "nimbus_minivan"]
const TRAFFIC_MOTORCYCLE_TYPES := ["bike_urban", "bike_sport", "bike_cruiser"]
signal logical_region_changed(previous_region: String, next_region: String)
const CONNECTION_PRELOAD_DISTANCE := 240.0
const CONNECTION_RELEASE_DISTANCE := 320.0
var world
var state = preload("res://runtime/GameState.gd").new()
var store = preload("res://runtime/SaveStore.gd").new()
var region: Node3D
var regions: Dictionary = {}
var connection: Node3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var vehicles: Array[CharacterBody3D] = []
var no_save := false
var save_invalid := false
var loaded_save := false
var ready_for_play := false
var travel_busy := false
var population_clock := 0.0
var requested_population := MAX_POPULATION
var session
var urban_transit: Node3D
var world_audio: Node
var civilian_reactions: Node
var traffic_routes = preload("res://gameplay/NativeTrafficRoutes.gd").new()
var ambient_traffic_routes = preload("res://gameplay/NativeTrafficRoutes.gd").new()
var ambient_roads_cache: Array[Dictionary] = []
var chairlift_schedule_initialized := false
var chairlift_operating := false
## Regiões preparadas fora da árvore: reentrar não repete a preparação (~340 ms em Mountain).
var _region_cache: Dictionary = {}
## Cenas dos modelos de trânsito mantidas vivas. FleetCatalog.create faz load() a cada
## nascimento; quando o último carro de um modelo saía de cena, o recurso era liberado
## e o próximo nascimento relia o arquivo: 1,7 s num quadro (medido 2026-09-23).
var _fleet_scenes: Array[Resource] = []

func build() -> void:
	no_save = "--no-save" in OS.get_cmdline_user_args()
	var launch = get_node_or_null("/root/V2Launch")
	if launch != null: store.path = launch.selected_path
	if not no_save:
		var result: Dictionary = store.load_into(state)
		save_invalid = result.get("invalid",false)
		loaded_save = result.get("ok",false)
	state.world = world
	var curtain = preload("res://runtime/StartupCurtain.gd").new()
	world.add_child(curtain)
	environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("829da6")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c0d0e2")
	environment.environment.ambient_light_energy = .65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-30,0)
	sun.light_color = Color("fffdf5")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	world.add_child(sun)
	world.maciota_place = preload("res://world/maciota/MaciotaPlace.gd").new()
	world.maciota_place.exterior_origin = Vector3(790.0/16,0,1495.0/16)
	world.maciota_place.interior_origin = Vector3(0,0,-2000)
	world.add_child(world.maciota_place)
	region = _mount_region(state.region_id)
	var startup_position := _startup_position()
	region.set_focus(startup_position)
	world.street = region
	_refresh_route_consumers()
	world.player = ACTOR.new()
	world.player.is_player = true
	world.player.name = "Dante"
	world.player.position = startup_position
	region.set_focus(world.player.position)
	world.add_child(world.player)
	_update_physical_residency(world.player.position)
	world.camera = preload("res://scripts/CameraRig.gd").new()
	world.camera.target = world.player
	world.add_child(world.camera)
	world.player.camera = world.camera
	world._build_hud()
	world.driving = preload("res://scripts/Driving.gd").new()
	world.driving.world = world
	world.add_child(world.driving)
	world.driving.car.vehicle_id = "player_coupe"
	world.driving.car.set_meta("region_id",state.region_id)
	vehicles.append(world.driving.car)
	world.traffic = Node3D.new()
	world.add_child(world.traffic)
	world.gameplay = preload("res://gameplay/Gameplay.gd").new()
	world.gameplay.configure(world,world.player,world.camera,state)
	world.add_child(world.gameplay)
	civilian_reactions = preload("res://gameplay/civilian_reactions/CivilianReactionDirector.gd").new()
	civilian_reactions.name = "CivilianReactionDirector"
	civilian_reactions.configure(world,world.gameplay)
	world.add_child(civilian_reactions)
	if not world.get_meta("skip_dispatch",false) and not "--no-dispatch" in OS.get_cmdline_user_args():
		world.dispatch = preload("res://gameplay/dispatch/DispatchController.gd").new()
		world.dispatch.configure(world,world.gameplay,traffic_routes)
		world.add_child(world.dispatch)
		world.dispatch.set_enabled(true)
		world.dispatch.set_physics_process(false)
	if not world.get_meta("skip_traffic_yield",false) and not "--no-traffic-yield" in OS.get_cmdline_user_args():
		world.traffic_yield = preload("res://gameplay/traffic_yield/TrafficYieldController.gd").new()
		world.traffic_yield.configure(world,traffic_routes)
		world.add_child(world.traffic_yield)
		world.traffic_yield.set_physics_process(false)
	world.session = preload("res://runtime/FullSession.gd").new()
	world.session.world = world
	world.session.controller = self
	world.add_child(world.session)
	session = world.session
	var v1_routines = preload("res://gameplay/routines_v1/RoutineDirector.gd").new()
	v1_routines.configure(world,session,self)
	world.add_child(v1_routines)
	urban_transit = preload("res://runtime/UrbanTransitPresentation.gd").new()
	urban_transit.configure(self)
	world.add_child(urban_transit)
	var saved_vehicle := starting_vehicle()
	if not saved_vehicle.is_empty() and saved_vehicle.get("was_driven",false) and saved_vehicle.region == state.region_id and state.place_id.is_empty():
		region.set_focus(Vector3(saved_vehicle.position[0],saved_vehicle.position[1],saved_vehicle.position[2]))
	if session.cold != null and not saved_vehicle.is_empty() and saved_vehicle.region == state.region_id:
		session.cold.prepare_collision_at(Vector3(saved_vehicle.position[0],saved_vehicle.position[1],saved_vehicle.position[2]))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--population="): requested_population = clampi(arg.split("=")[1].to_int(),0,MAX_POPULATION)
	for i in 12: await get_tree().physics_frame
	_prewarm_regions()
	var road_point := nearest_road(world.player.position)
	world.driving.car.place(road_point+Vector3.UP*.12,road_yaw(road_point))
	_restore_player_vehicle()
	# Weather must exist before the world is marked ready_for_play: the
	# environment/sun start out at the raw defaults set in build() above
	# (a flat pale sky colour), and Weather._ready() is what grades them into
	# the saved time-of-day/season. Creating it after ready_for_play left a
	# frame window where the player already saw and could move through the
	# world under that raw default look, reading as an icy, washed-out scene
	# until Weather caught up.
	var weather = preload("res://runtime/Weather.gd").new()
	weather.controller = self
	world.add_child(weather)
	session.weather = weather
	var city_look = preload("res://world/city_look/CityLook.gd").new()
	city_look.controller = self
	world.add_child(city_look)
	var street_physics = preload("res://gameplay/street_physics/StreetPhysics.gd").new()
	street_physics.controller = self
	world.add_child(street_physics)
	var rain_puddles = preload("res://world/rain/RainPuddles3D.gd").new()
	rain_puddles.controller = self
	world.add_child(rain_puddles)
	var wildlife = preload("res://gameplay/wildlife/MountainWildlife.gd").new()
	wildlife.controller = self
	world.add_child(wildlife)
	var roadside = preload("res://world/mountain_detail/MountainRoadside3D.gd").new()
	roadside.controller = self
	world.add_child(roadside)
	var grass = preload("res://world/mountain_detail/MountainGrass3D.gd").new()
	grass.controller = self
	world.add_child(grass)
	ready_for_play = true
	await session.restore_location()
	curtain.lift()
	set_population(requested_population)
	world_audio = _audio()
	world.add_child(world_audio)
	_update_chairlift_schedule()
	session.arrival.start_or_resume(loaded_save or "--skip-arrival" in OS.get_cmdline_user_args() or world.get_meta("skip_arrival",false))
	if is_instance_valid(world.dispatch):
		session.sync_dispatch_location()
		world.dispatch.set_physics_process(true)
	if is_instance_valid(world.traffic_yield): world.traffic_yield.set_physics_process(true)
	session.show_message("Geteco V2 · E interagir · J missões · M mapa · Tab inventário")

## Sob a cortina de carregamento: prepara a outra região e aquece os caches de
## texturas/malhas das duas (medido 2026-09-23: 2,5 s Harbor + 1,2 s Mountain),
## para a primeira passagem por cada lugar não travar a direção.
func _prewarm_regions() -> void:
	_hold_fleet_scenes()
	if "--no-prewarm" in OS.get_cmdline_user_args() or world.get_meta("skip_prewarm",false): return
	var began := Time.get_ticks_msec()
	if is_instance_valid(region): region.prewarm()
	for id in ["harbor","mountain"]:
		if regions.has(id): continue
		var detached: Node3D = REGION.build_region(id)
		if detached == null: continue
		world.add_child(detached)
		detached.prewarm()
		detached.release_chunks()
		world.remove_child(detached)
		_region_cache[id] = detached
	# Grafos de rota das três combinações residentes, sob a cortina.
	var live := regions.duplicate()
	var all := live.duplicate()
	for id in _region_cache: all[id] = _region_cache[id]
	for combo in [["harbor"],["mountain"],["harbor","mountain"]]:
		regions = {}
		for id in combo:
			if all.has(id): regions[id] = all[id]
		if regions.size() == combo.size(): _configure_routes()
	regions = live
	_configure_routes()
	print("Pré-aquecimento das regiões: ", Time.get_ticks_msec()-began, " ms")

func _hold_fleet_scenes() -> void:
	if not _fleet_scenes.is_empty(): return
	# Trânsito e as viaturas do despacho (DispatchRules.ARCHETYPES): nascem e somem igual.
	for id in TRAFFIC_CAR_TYPES+TRAFFIC_MOTORCYCLE_TYPES+["police_cruiser","medic_box","rescue_pumper","station_wagon"]:
		var definition: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(id)
		if definition.has("scene"):
			var scene := load(definition.scene)
			if scene != null: _fleet_scenes.append(scene)

func _exit_tree() -> void:
	for cached in _region_cache.values():
		if is_instance_valid(cached): cached.free()
	_region_cache.clear()

func _startup_position() -> Vector3:
	# Mount and frame the saved destination from the first rendered frame.  The
	# previous Maciota-first staging exposed unloaded pale terrain/building chunks
	# for several seconds before restore_location teleported Dante to the save.
	var fallback: Vector3 = world.maciota_place.exterior_return+Vector3(0,.08,2) if state.region_id == "harbor" else region.spawn_position+Vector3.UP*.08
	if not state.place_id.is_empty(): return fallback
	var saved_vehicle := starting_vehicle()
	if not saved_vehicle.is_empty() and saved_vehicle.get("was_driven",false) and saved_vehicle.get("region","") == state.region_id:
		var vehicle_position: Array = saved_vehicle.get("position",[])
		if vehicle_position.size() == 3:
			return Vector3(float(vehicle_position[0]),float(vehicle_position[1]),float(vehicle_position[2]))
	var pedestrian: Dictionary = state.world_state.get("pedestrian",{})
	var coordinates: Array = pedestrian.get("position",[])
	if pedestrian.get("region","") == state.region_id and coordinates.size() == 3:
		return Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
	return fallback

func _audio() -> Node:
	var audio = preload("res://audio/WorldAudio.gd").new()
	audio.world = world
	return audio

func _physical_focus() -> Vector3:
	if is_instance_valid(world.driving) and world.driving.occupied and is_instance_valid(world.driving.car):
		return world.driving.car.global_position
	if session != null and is_instance_valid(session.passenger_transport) and session.passenger_transport.riding and is_instance_valid(session.passenger_transport.car):
		return session.passenger_transport.car.global_position
	return world.player.global_position if is_instance_valid(world.player) else Vector3.ZERO

func _mount_region(id: String, requested_focus: Vector3 = Vector3.INF) -> Node3D:
	if regions.has(id) and is_instance_valid(regions[id]): return regions[id]
	var traced := Time.get_ticks_usec() if is_instance_valid(world) and world.get_meta("benchmark_trace",false) else 0
	var mounted_region := _mount_region_now(id,requested_focus)
	_trace_cost("mount_region:"+id,traced)
	return mounted_region

func _mount_region_now(id: String, requested_focus: Vector3) -> Node3D:
	var first_focus := requested_focus if requested_focus.is_finite() else (_physical_focus() if is_instance_valid(world.player) else Vector3.INF)
	var mounted: Node3D = null
	if _region_cache.has(id) and is_instance_valid(_region_cache[id]):
		mounted = _region_cache[id]
		_region_cache.erase(id)
		mounted.initial_focus = first_focus
	else:
		mounted = REGION.build_region(id,first_focus)
	if mounted == null: return null
	regions[id] = mounted
	world.add_child(mounted)
	if chairlift_schedule_initialized and mounted.has_method("set_chairlift_operating"): mounted.set_chairlift_operating(chairlift_operating)
	if first_focus.is_finite(): mounted.set_focus(first_focus)
	_refresh_route_consumers()
	return mounted

func _unmount_region(id: String) -> void:
	if id == state.region_id or not regions.has(id): return
	var mounted: Node3D = regions[id]
	regions.erase(id)
	if is_instance_valid(mounted):
		mounted.release_chunks()
		world.remove_child(mounted)
		_region_cache[id] = mounted
	_refresh_route_consumers()

func _resident_roads() -> Array:
	var result: Array = []
	for id in ["harbor","mountain"]:
		if not regions.has(id) or not is_instance_valid(regions[id]): continue
		result.append_array(regions[id].roads)
	if regions.has("harbor") and regions.has("mountain"):
		result.append_array(WORLD_CONNECTION.traffic_connectors())
	return result

## Grafos de rota por conjunto de regiões residentes. configure() cruza todos os
## trechos entre si (~55 + 65 ms com Harbor e Mountain); na costura isso se repetia a
## cada montagem/desmontagem de Mountain. Cópias rasas: configure() esvazia no lugar.
var _route_cache: Dictionary = {}

func _route_key() -> String:
	var ids: Array = []
	for id in ["harbor","mountain"]:
		if regions.has(id) and is_instance_valid(regions[id]): ids.append(id)
	return ",".join(ids)

static func _graph_snapshot(graph) -> Array:
	return [graph.segments.duplicate(),graph.vertices.duplicate(),graph.edges.duplicate(),graph._vertex_ids.duplicate()]

static func _graph_restore(graph, snapshot: Array) -> void:
	graph.segments = snapshot[0].duplicate()
	graph.vertices = snapshot[1].duplicate()
	graph.edges = snapshot[2].duplicate()
	graph._vertex_ids = snapshot[3].duplicate()

func _configure_routes() -> void:
	var key := _route_key()
	var cached: Dictionary = _route_cache.get(key,{})
	if not cached.is_empty():
		_graph_restore(traffic_routes,cached.traffic)
		_graph_restore(ambient_traffic_routes,cached.ambient)
		ambient_roads_cache = cached.ambient_roads.duplicate()
		return
	var roads := _resident_roads()
	traffic_routes.configure(roads)
	ambient_roads_cache = PORT_POLICY.ambient_roads(roads)
	ambient_traffic_routes.configure(ambient_roads_cache)
	_route_cache[key] = {"traffic":_graph_snapshot(traffic_routes),"ambient":_graph_snapshot(ambient_traffic_routes),"ambient_roads":ambient_roads_cache.duplicate()}

func _refresh_route_consumers() -> void:
	if traffic_routes == null: return
	var traced := Time.get_ticks_usec() if is_instance_valid(world) and world.get_meta("benchmark_trace",false) else 0
	_configure_routes()
	preload("res://gameplay/traffic_junctions/TrafficJunctions.gd").configure(ambient_traffic_routes)
	_trace_cost("route_graphs",traced)
	if is_instance_valid(world) and is_instance_valid(world.dispatch): world.dispatch.refresh_roads()
	if is_instance_valid(world) and is_instance_valid(world.traffic_yield): world.traffic_yield.refresh_roads(traffic_routes)

func _persistent_vehicle_support() -> Dictionary:
	var support := {"harbor":[],"mountain":[]}
	for car in vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion() or not car.visible or not car.is_physics_processing(): continue
		if _is_ambient_traffic(car): continue
		if car != world.driving.car and car.vehicle_id not in ["neco_tow_truck","story_tow_vehicle"] and not car.get_meta("residence_vehicle",false) and not car.get_meta("garage_reward",false) and not car.get_meta("port_work_vehicle",false) and not car.get_meta("secret_discovery_vehicle",false): continue
		var id: String = WORLD_CONNECTION.logical_region(car.global_position)
		var radius: float = Vector2(car.half_width,car.half_length).length()+0.5
		support[id].append({"position":car.global_position,"radius":radius})
	return support

func _update_physical_residency(point: Vector3) -> void:
	var physical_region := WORLD_CONNECTION.logical_region(point)
	var support := _persistent_vehicle_support()
	_mount_region(physical_region,point)
	var seam_distance := Vector2(point.x-WORLD_CONNECTION.SEAM.x,point.z-WORLD_CONNECTION.SEAM.z).length()
	var seam_anchor := point
	var seam_preload := seam_distance <= CONNECTION_PRELOAD_DISTANCE
	var seam_keep := seam_distance <= CONNECTION_RELEASE_DISTANCE
	for id in ["harbor","mountain"]:
		for vehicle in support[id]:
			var position: Vector3 = vehicle.position
			var distance := Vector2(position.x-WORLD_CONNECTION.SEAM.x,position.z-WORLD_CONNECTION.SEAM.z).length()
			if distance <= CONNECTION_PRELOAD_DISTANCE and not seam_preload:
				seam_anchor = position
				seam_preload = true
			if distance <= CONNECTION_RELEASE_DISTANCE: seam_keep = true
		if not support[id].is_empty(): _mount_region(id,support[id][0].position)
	if seam_preload:
		_mount_region("harbor",seam_anchor)
		_mount_region("mountain",seam_anchor)
		if not is_instance_valid(connection):
			var traced := Time.get_ticks_usec() if world.get_meta("benchmark_trace",false) else 0
			connection = WORLD_CONNECTION.new()
			world.add_child(connection)
			_trace_cost("world_connection",traced)
	elif not seam_keep:
		for id in ["harbor","mountain"]:
			if id != physical_region and support[id].is_empty(): _unmount_region(id)
		if is_instance_valid(connection):
			connection.queue_free()
			connection = null
	for id in regions:
		var mounted: Node3D = regions[id]
		if not is_instance_valid(mounted): continue
		mounted.set_vehicle_support(support[id])
		mounted.set_retention_radius(2 if id == physical_region else 1)
		var region_focus := point
		if id != physical_region and seam_distance > CONNECTION_PRELOAD_DISTANCE:
			if not support[id].is_empty(): region_focus = support[id][0].position
			elif seam_preload: region_focus = seam_anchor
		mounted.set_focus(region_focus)

func _update_logical_region(point: Vector3) -> void:
	if not state.place_id.is_empty(): return
	var next_region := WORLD_CONNECTION.logical_region(point)
	if next_region == state.region_id or not regions.has(next_region): return
	_commit_logical_region(next_region)

func _commit_logical_region(next_region: String) -> void:
	if next_region == state.region_id or not regions.has(next_region): return
	var previous: String = state.region_id
	state.set_location(next_region)
	region = regions[next_region]
	world.street = region
	# Player-owned and passenger-occupied vehicles retain the same instances,
	# velocity, occupants and attachments; only their logical routing context changes.
	if world.driving.occupied and is_instance_valid(world.driving.car): world.driving.car.set_meta("region_id",next_region)
	if session != null and is_instance_valid(session.passenger_transport) and session.passenger_transport.riding and is_instance_valid(session.passenger_transport.car):
		session.passenger_transport.car.set_meta("region_id",next_region)
	_repath_ambient_traffic()
	_refresh_route_consumers()
	if is_instance_valid(urban_transit): urban_transit.on_region_changed()
	if session != null:
		session.sync_dispatch_location()
		session._refresh_routine_context()
		if is_instance_valid(session.weather): session.weather._update()
	if is_instance_valid(world_audio) and world_audio.has_method("on_region_changed"):
		world_audio.on_region_changed(previous,next_region)
	logical_region_changed.emit(previous,next_region)

func _update_mobile_region_metadata() -> void:
	for car in vehicles:
		if not is_instance_valid(car) or not car.is_visible_in_tree(): continue
		car.set_meta("region_id",WORLD_CONNECTION.logical_region(car.global_position))

func _update_chairlift_schedule() -> void:
	if session == null or not is_instance_valid(session.weather): return
	var hour := float(session.weather.time_of_day)*24.0
	var operating := hour >= 8.0 and hour < 18.0
	if chairlift_schedule_initialized and operating == chairlift_operating: return
	chairlift_schedule_initialized = true
	chairlift_operating = operating
	for mounted in regions.values():
		if is_instance_valid(mounted) and mounted.has_method("set_chairlift_operating"): mounted.set_chairlift_operating(operating)

func starting_vehicle() -> Dictionary:
	var saved: Array = state.world_state.get("vehicles",[])
	return saved[0] if not saved.is_empty() else {}

func _restore_player_vehicle() -> void:
	var saved := starting_vehicle()
	if saved.is_empty(): return
	var car: CharacterBody3D = world.driving.car
	var point := Vector3(saved.position[0],saved.position[1],saved.position[2])
	car.equipment_state = saved.get("equipment",{}).duplicate(true)
	if saved.has("paint"): car.paint_color = Color.html(saved.paint)
	if saved.has("vehicle_id"): car.vehicle_id = str(saved.vehicle_id)
	car.set_meta("region_id",saved.region)
	if saved.region != state.region_id or (point.distance_to(world.player.position)>75 and not saved.get("was_driven",false)):
		car.place(point,float(saved.yaw))
		car.set_meta("awaiting_ground",true)
		car.set_physics_process(false)
		car.visible = saved.region == state.region_id
	elif vehicle_position_clear(car,point,float(saved.yaw)):
		car.place(point,float(saved.yaw))
	car.receive_damage(car.max_health-float(saved.health))

func capture_player_vehicle() -> void:
	var car: CharacterBody3D = world.driving.car
	if car.vehicle_id in ["story_tow_vehicle","neco_tow_truck"] or car.get_meta("residence_vehicle",false) or car.get_meta("garage_reward",false): return
	state.world_state.vehicles = [preload("res://runtime/FleetState.gd").capture(car,state.region_id)]
	state.world_state.vehicles[0].was_driven = world.driving.occupied

func nearest_road(point: Vector3) -> Vector3:
	var closest := point
	var distance := INF
	for road in _resident_roads():
		for i in range(road.points.size()-1):
			var candidate := Geometry3D.get_closest_point_to_segment(point,road.points[i],road.points[i+1])
			var offset: Vector3 = (road.points[i+1]-road.points[i]).normalized().cross(Vector3.UP)*road.width*.25
			candidate += offset
			if point.distance_squared_to(candidate) < distance:
				distance = point.distance_squared_to(candidate)
				closest = candidate
	return closest

func set_population(count: int) -> void:
	requested_population = clampi(count,0,MAX_POPULATION)
	if not ready_for_play: return
	while world.people.size() > requested_population:
		var actor = world.people.pop_back()
		if is_instance_valid(actor): actor.queue_free()
	world.population = world.people.size()

func _process(delta: float) -> void:
	if not ready_for_play: return
	_update_chairlift_schedule()
	if travel_busy: return
	# Admission routines own focus while awaiting collision synchronization.
	# Following the old player position here would unload their destination.
	if session == null or not session.ready_for_play or session.is_transition_blocked(): return
	if state.place_id.is_empty():
		var focus := _physical_focus()
		_update_physical_residency(focus)
		_update_logical_region(focus)
	population_clock += delta
	if population_clock < .25 or not state.place_id.is_empty(): return
	population_clock = 0
	_update_mobile_region_metadata()
	for index in range(world.people.size()-1,-1,-1):
		var actor = world.people[index]
		if not is_instance_valid(actor): world.people.remove_at(index)
		elif PORT_POLICY.contains_private_area(actor.global_position):
			world.people.remove_at(index)
			actor.queue_free()
		elif actor.position.distance_to(world.player.position) > POPULATION_DESPAWN and not _on_screen(actor.global_position,1.0):
			world.people.remove_at(index)
			actor.queue_free()
	if world.people.size() < requested_population: _spawn_citizen()
	if _ambient_traffic_count() < TRAFFIC_TARGET and not "--no-traffic" in OS.get_cmdline_user_args(): _spawn_vehicle()
	for index in range(vehicles.size()-1,-1,-1):
		var car = vehicles[index]
		if not is_instance_valid(car): vehicles.remove_at(index)
		elif _is_ambient_traffic(car) and PORT_POLICY.contains_private_area(car.global_position):
			vehicles.remove_at(index)
			car.queue_free()
		elif _is_ambient_traffic(car) and car.health <= 0.0 and car != world.driving.car and _wreck_expired(car) and car.global_position.distance_to(world.player.global_position) > 20.0 and not _on_screen(car.global_position,3.0):
			# Carcaça de trânsito (traffic=false ao ser destruída) nunca saía de cena e
			# travava cruzamentos. Some fora do quadro, depois de alguns segundos.
			vehicles.remove_at(index)
			car.queue_free()
		elif _is_ambient_traffic(car) and car.traffic and car.global_position.distance_to(world.player.global_position) > POPULATION_DESPAWN and not _on_screen(car.global_position,3.0):
			# Trânsito ambiente sai de cena só longe e fora do quadro, como entra.
			vehicles.remove_at(index)
			car.queue_free()
		elif car.get_meta("region_id",state.region_id) != state.region_id: continue
		elif car.has_meta("awaiting_ground"):
			if vehicle_position_clear(car,car.position,car.rotation.y):
				car.remove_meta("awaiting_ground")
				car.set_physics_process(true)
		elif not car.traffic and car != world.driving.car and car.vehicle_id not in ["story_tow_vehicle","neco_tow_truck"] and not car.get_meta("residence_vehicle",false) and not car.get_meta("garage_reward",false) and not car.get_meta("port_work_vehicle",false) and not car.get_meta("secret_discovery_vehicle",false) and car.position.distance_to(world.player.position) > 145:
			vehicles.remove_at(index)
			car.queue_free()
	# Trânsito e motoristas NPC ganham faróis e lanternas, que acendem sozinhos à
	# noite (V1 `set_headlights`). Dois por ciclo, para o custo de montar as
	# lentes não cair inteiro num quadro só.
	var equipped := 0
	for car in vehicles:
		if equipped >= 2: break
		if not is_instance_valid(car) or is_instance_valid(car.equipment): continue
		if car.traffic or (car.controlled and car.external_input):
			car.ensure_equipment(world)
			equipped += 1
	world.population = world.people.size()

func vehicle_position_clear(car: CharacterBody3D, point: Vector3, yaw: float) -> bool:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var basis := Basis(Vector3.UP,yaw)
	# Distant saved cars wait for their terrain before requesting streamed props.
	for x in [-car.half_width*.8,car.half_width*.8]:
		for z in [-car.half_length*.8,car.half_length*.8]:
			var support: Vector3 = point+basis*Vector3(x,0,z)
			var ray := PhysicsRayQueryParameters3D.create(support+Vector3.UP*.3,support-Vector3.UP*.5,1)
			if space.intersect_ray(ray).is_empty(): return false
	if session != null and session.cold != null and not session.cold.prepare_collision_at(point): return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car.shape.shape
	query.transform = Transform3D(basis,point+basis*car.shape.position)
	query.collision_mask = 7
	query.exclude = [car.get_rid()]
	if not space.intersect_shape(query,1).is_empty(): return false
	return true

func spawn_vehicle(id: String, point: Vector3, yaw: float = 0.0) -> CharacterBody3D:
	if preload("res://runtime/FleetCatalog.gd").spec(id).is_empty(): return null
	var car = VEHICLE.new()
	car.archetype = id
	car.vehicle_id = "vehicle_"+str(Time.get_ticks_usec())
	car.position = point
	car.set_meta("region_id",state.region_id)
	car.rotation.y = yaw
	var traced := Time.get_ticks_usec() if world.get_meta("benchmark_trace",false) else 0
	world.add_child(car)
	_trace_cost("spawn_vehicle_add_child:"+id,traced)
	traced = Time.get_ticks_usec() if traced != 0 else 0
	var clear := vehicle_position_clear(car,point,yaw)
	_trace_cost("spawn_vehicle_position_clear",traced)
	if not clear:
		if point.distance_to(world.player.position) < 75:
			car.queue_free()
			return null
		car.set_meta("awaiting_ground",true)
		car.set_physics_process(false)
	car.destroyed.connect(func():
		if is_instance_valid(world.gameplay):
			world.gameplay.explode(car.global_position+Vector3.UP*.4,5.0,35.0,car,false)
			if is_instance_valid(world.gameplay.emergency):
				world.gameplay.emergency.ignite(car.global_position,car))
	vehicles.append(car)
	return car

func _ambient_traffic_count() -> int:
	var count := 0
	for car in vehicles:
		if is_instance_valid(car) and _is_ambient_traffic(car) and car.traffic and car.health > 0.0: count += 1
	return count

func _is_ambient_traffic(car: Variant) -> bool:
	return is_instance_valid(car) and car is Node and car.get_meta("ambient_traffic", false) == true

func _repath_ambient_traffic() -> void:
	for car in vehicles:
		if not _is_ambient_traffic(car) or not car.traffic or car.health <= 0.0: continue
		var route: Curve3D = ambient_traffic_routes.route_near(car.global_position)
		if route == null or route.get_baked_length() < 12.0 or not PORT_POLICY.route_is_ambient_safe(route):
			car.queue_free()
			continue
		car.route = route
		car.route_distance = route.get_closest_offset(car.global_position)

func _near_segment() -> Dictionary:
	var options := []
	for road in ambient_roads_cache:
		for i in range(road.points.size()-1):
			var a: Vector3 = road.points[i]
			var b: Vector3 = road.points[i+1]
			var point := Geometry3D.get_closest_point_to_segment(world.player.position,a,b)
			if point.distance_to(world.player.position) < POPULATION_SPAWN_MAX and a.distance_to(b) > 4:
				options.append({"a":a,"b":b,"width":road.width})
	return options.pick_random() if not options.is_empty() else {}

## Ponto dentro do quadro da câmera (com folga de `radius` metros e 10% da tela).
func _on_screen(point: Vector3, radius: float = 1.0) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return false
	var rect := get_viewport().get_visible_rect().grow(get_viewport().get_visible_rect().size.x*.1)
	for offset in [Vector3.ZERO,Vector3.UP*2.0,Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
		var sample: Vector3 = point+offset
		if not camera.is_position_behind(sample) and rect.has_point(camera.unproject_position(sample)): return true
	return false

func _on_carriageway(point: Vector3) -> bool:
	var flat := Vector2(point.x,point.z)
	for road in _resident_roads():
		var points: PackedVector3Array = road.points
		var half := float(road.width)*.5+.3
		for i in range(points.size()-1):
			var nearest := Geometry2D.get_closest_point_to_segment(flat,Vector2(points[i].x,points[i].z),Vector2(points[i+1].x,points[i+1].z))
			if flat.distance_to(nearest) < half: return true
	return false

const WRECK_LINGER_MSEC := 6000

func _wreck_expired(car: Node) -> bool:
	if not car.has_meta("wrecked_msec"): car.set_meta("wrecked_msec",Time.get_ticks_msec())
	return Time.get_ticks_msec()-int(car.get_meta("wrecked_msec")) > WRECK_LINGER_MSEC

## Anel de entrada/saída: longe o bastante e fora do quadro.
func _spawn_point_allowed(point: Vector3, radius: float) -> bool:
	var distance := Vector2(point.x-world.player.global_position.x,point.z-world.player.global_position.z).length()
	return distance >= POPULATION_SPAWN_MIN and distance <= POPULATION_SPAWN_MAX and not _on_screen(point,radius)

func road_yaw(point: Vector3) -> float:
	var best := INF
	var yaw := 0.0
	for road in _resident_roads():
		for index in range(road.points.size()-1):
			var a: Vector3 = road.points[index]
			var b: Vector3 = road.points[index+1]
			var distance := Geometry3D.get_closest_point_to_segment(point,a,b).distance_squared_to(point)
			if distance < best:
				best = distance
				var direction := b-a
				yaw = atan2(-direction.x,-direction.z)
	return yaw

func _spawn_citizen() -> void:
	var began := Time.get_ticks_usec() if world.get_meta("benchmark_trace",false) else 0
	_create_citizen()
	_trace_cost("population_spawn",began)

func _trace_cost(label: String, began: int) -> void:
	if began == 0: return
	var elapsed := Time.get_ticks_usec()-began
	if elapsed < 2000: return
	var costs: Array = world.get_meta("perf_costs",[])
	if costs.size()<512: costs.append({"label":label,"start_usec":began,"duration_usec":elapsed})
	world.set_meta("perf_costs",costs)

func _create_citizen() -> void:
	var segment := _near_segment()
	if segment.is_empty(): return
	var along: Vector3 = (segment.b-segment.a).normalized()
	var point: Vector3 = segment.a.lerp(segment.b,randf_range(.1,.9))
	var offset: Vector3 = along.cross(Vector3.UP)*(segment.width*.5+.85)*(1 if randf()>.5 else -1)
	point += offset
	if not _spawn_point_allowed(point,1.0): return
	# Vias de mão única lado a lado (ponte, acessos) põem a "calçada" de uma dentro
	# da pista da outra: pedestre nunca nasce nem caminha sobre pista autorada.
	for end in [point,point-along*8,point+along*8]:
		if _on_carriageway(end): return
	var pedestrian_route := PackedVector3Array([point-along*8,point+along*8])
	if PORT_POLICY.contains_private_area(point) or PORT_POLICY.segment_enters_private_area(pedestrian_route[0],pedestrian_route[1]): return
	if not session.position_clear(point+Vector3.UP*.06): return
	var actor = ACTOR.new()
	actor.identity = randi_range(0,10000)
	actor.position = point+Vector3.UP*.08
	actor.speed = randf_range(1.15,1.75)
	actor.route = pedestrian_route
	actor.set_meta("region_id",state.region_id)
	world.add_child(actor)
	world.people.append(actor)

func _spawn_vehicle() -> void:
	var began := Time.get_ticks_usec() if world.get_meta("benchmark_trace",false) else 0
	_create_traffic_vehicle()
	_trace_cost("traffic_spawn",began)

func _create_traffic_vehicle() -> void:
	var roads := ambient_roads_cache
	if roads.is_empty(): return
	var start := randi_range(0,roads.size()-1)
	# Orçamento por tentativa: cada route_near monta uma rota inteira. Com o anel fora
	# da câmera recusando muitos pontos, a busca chegou a 1,6 s num quadro (2026-09-23).
	# Sem lugar agora, tenta de novo no próximo ciclo (0,25 s).
	var began := Time.get_ticks_usec()
	var route_attempts := 0
	for road_offset in roads.size():
		if Time.get_ticks_usec()-began > 3000: return
		var road: Dictionary = roads[(start+road_offset)%roads.size()]
		var points: PackedVector3Array = road.get("points",PackedVector3Array())
		for segment_index in range(points.size()-1):
			var a: Vector3 = points[segment_index]
			var b: Vector3 = points[segment_index+1]
			if a.distance_to(b) < 16: continue
			var direction := (b-a).normalized()
			var lane := direction.cross(Vector3.UP)*float(road.get("width",7.5))*.25
			var point := a.lerp(b,randf_range(.25,.75))+lane
			if not _spawn_point_allowed(point,3.0): continue
			var occupied := false
			for existing in vehicles:
				if is_instance_valid(existing) and existing.traffic and existing.global_position.distance_to(point) < 16:
					occupied = true
					break
			if occupied: continue
			if route_attempts >= 2: return
			route_attempts += 1
			var traced := Time.get_ticks_usec() if world.get_meta("benchmark_trace",false) else 0
			var route: Curve3D = ambient_traffic_routes.route_near(point)
			var safe := route != null and route.get_baked_length() >= 12 and PORT_POLICY.route_is_ambient_safe(route)
			_trace_cost("traffic_spawn_route",traced)
			if not safe: continue
			var offset := route.get_closest_offset(point)
			point = route.sample_baked(offset,true)
			var ahead := route.sample_baked(minf(offset+.5,route.get_baked_length()),true)-route.sample_baked(maxf(offset-.5,0),true)
			var id: String = TRAFFIC_MOTORCYCLE_TYPES.pick_random() if randi_range(0,9) == 0 else TRAFFIC_CAR_TYPES.pick_random()
			traced = Time.get_ticks_usec() if world.get_meta("benchmark_trace",false) else 0
			var car = spawn_vehicle(id,point+Vector3.UP*.12,atan2(-ahead.x,-ahead.z))
			_trace_cost("traffic_spawn_vehicle:"+id,traced)
			if car == null: continue
			car.vehicle_id = "street_"+str(Time.get_ticks_usec())
			car.route = route
			car.route_distance = offset
			car.set_meta("ambient_traffic", true)
			car.traffic = true
			return

func travel(region_id: String) -> bool:
	if travel_busy or not session.ready_for_play or session.is_transition_blocked(): return false
	if region_id not in ["harbor","mountain"] or region_id == state.region_id or world.driving.occupied or not state.place_id.is_empty(): return false
	if session.passenger_transport.riding or world.gameplay.health <= 0: return false
	travel_busy = true
	_travel_checked(region_id)
	return true # Request admitted; completion owns the save after physical admission.

func _travel_checked(region_id: String) -> void:
	var was_paused := get_tree().paused
	var was_locked: bool = world.player.input_locked
	session.ready_for_play = false
	world.player.input_locked = true
	get_tree().paused = true
	var was_resident := regions.has(region_id) and is_instance_valid(regions[region_id])
	var next_region: Node3D = _mount_region(region_id)
	var destination: Vector3 = next_region.spawn_position+Vector3.UP*.12
	next_region.set_focus(destination)
	# Keep the source region intact until the destination has synchronized collision.
	for i in 3: await get_tree().physics_frame
	if not session.position_clear(destination):
		if not was_resident: _unmount_region(region_id)
		travel_busy = false
		session.ready_for_play = true
		world.player.input_locked = was_locked
		get_tree().paused = was_paused
		session.show_message("Destino ocupado ou sem solo. Viagem não realizada.")
		return
	session.passenger_transport.cancel_for_transition()
	session.activities.cancel_attempt()
	session.mountain_progression.cancel_attempt()
	session.garage_rewards.cancel_press_delivery()
	if is_instance_valid(world.traffic_yield): world.traffic_yield.release_all("travel")
	if is_instance_valid(world.dispatch): world.dispatch.dismiss_all("travel")
	world.gameplay.on_region_changed()
	world.gameplay.emergency.reset_region()
	# Fast travel unloads the population. Logical city/mountain seam crossings do
	# not call this, so an active reaction survives an ordinary region_id change.
	if is_instance_valid(civilian_reactions): civilian_reactions.reset_population()
	for citizen in world.people:
		if is_instance_valid(citizen): citizen.queue_free()
	world.people.clear()
	for vehicle in vehicles:
		if not is_instance_valid(vehicle): continue
		if vehicle == world.driving.car or vehicle.vehicle_id in ["neco_tow_truck","story_tow_vehicle"] or vehicle.get_meta("residence_vehicle",false) or vehicle.get_meta("garage_reward",false):
			if not vehicle.has_meta("region_id"): vehicle.set_meta("region_id",state.region_id)
			vehicle.set_physics_process(false)
			vehicle.hide()
		else: vehicle.queue_free()
	vehicles = vehicles.filter(func(vehicle): return is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion())
	state.world_state.erase("pedestrian")
	world.player.teleport(destination)
	_commit_logical_region(region_id)
	region.set_focus(region.spawn_position)
	_update_physical_residency(destination)
	for vehicle in vehicles:
		vehicle.visible = vehicle.get_meta("region_id","") == region_id and not vehicle.has_meta("tow_pending")
		if vehicle.visible and vehicle.collision_layer != 0: vehicle.set_meta("awaiting_ground",true)
	world.camera.initialized = false
	session.garage_rewards.on_location_changed()
	session.sync_dispatch_location()
	if is_instance_valid(urban_transit): urban_transit.on_region_changed()
	travel_busy = false
	session.ready_for_play = true
	world.player.input_locked = was_locked
	get_tree().paused = was_paused
	session.save_game()
