extends Node2D
## Bounded commuter population and a service clock independent of the coach terminal.
const STOP_DEFS := [
	{"name":"Terminal Sul","road":"dock_street","direction":-1,"point":Vector2(1650,2200)},
	{"name":"Westgate / Hospital","road":"westgate_drive","direction":-1,"point":Vector2(400,1730)},
	{"name":"Centro / Comércio","road":"westgate_drive","direction":-1,"point":Vector2(400,800)},
	{"name":"Foundry / Mercado","road":"foundry_avenue","direction":1,"point":Vector2(1900,400)},
	{"name":"Cais / Serviços","road":"quay_boulevard","direction":1,"point":Vector2(3000,920)},
	# Keep the station and its passenger exit north of the Northstar gangway (y=1742).
	{"name":"Docas / Trabalho","road":"quay_boulevard","direction":1,"point":Vector2(3000,1480)}
]
var network: Node2D
var clock: Node
var stops: Array[Node2D] = []
var buses: Array[CharacterBody2D] = []
var passengers: Array[Node2D] = []
var operating := true
var boarded := 0
var alighted := 0
var departures := 0
var _exchanges := {}
var _tick := 0.0
var ready_for_service := false
var player_ride: CanvasLayer

static func reserve_platform_spawns(world: Node2D) -> void:
	# Register before the deferred ambient population is created. Traffic may
	# drive through these areas, but must not spawn inside a waiting convoy.
	for def: Dictionary in STOP_DEFS:
		var horizontal: bool = def.road in ["dock_street","foundry_avenue"]
		var forward := (Vector2.RIGHT if horizontal else Vector2.DOWN)*float(def.direction)
		var center: Vector2 = def.point-forward*110
		var size := Vector2(500,160) if horizontal else Vector2(160,500)
		var zone := Node2D.new()
		zone.name = "UrbanPlatformSpawnExclusion%d"%world.get_child_count()
		zone.add_to_group("traffic_spawn_exclusion")
		zone.set_meta("traffic_spawn_exclusion_rect",Rect2(center-size*0.5,size))
		world.add_child(zone)

func _ready() -> void:
	add_to_group("urban_transit")
	_setup.call_deferred()

static func is_service_hour(hour: float) -> bool:
	var h := fposmod(hour,24.0)
	return h < 2.0 or h >= 5.0

func current_hour() -> float:
	return float(clock.time_of_day)*24 if is_instance_valid(clock) else 12.0

func _setup() -> void:
	network = get_parent().get_node("RoadNetwork")
	clock = get_parent().get("weather")
	if clock == null: clock = get_tree().get_first_node_in_group("day_night_manager")
	operating = is_service_hour(current_hour())
	# Set back the physical signal foundations around the express bus's turns.
	# The mast and its render move together; collision is never bypassed.
	for signal_view in get_tree().get_nodes_in_group("junction_signal_visual"):
		for corner in [Vector2(400,2200),Vector2(400,400),Vector2(3000,400),Vector2(3000,2200)]:
			if signal_view.global_position.distance_to(corner)<5:
				signal_view.extra_sidewalk_clearance = 26.0
				signal_view._rebuild_posts()
				break
	for i in STOP_DEFS.size():
		var def: Dictionary = STOP_DEFS[i]
		var lane: Path2D
		for candidate in network.find_children("*","Path2D",true,false):
			if candidate.is_in_group("unified_lane_connector"): continue
			if String(candidate.get_meta("traffic_road_id","")).get_file() == def.road and int(candidate.get_meta("traffic_direction",0)) == def.direction:
				lane = candidate
				break
		if lane == null:
			push_error("Urban transit lane missing: "+def.road)
			return
		var stop := preload("res://world/harbor/urban_transit/UrbanTubeStop.gd").new()
		stop.name = "UrbanStation%d"%i
		stop.stop_id = i
		stop.stop_name = def.name
		stop.terminal = i == 0
		stop.lane = lane
		stop.offset = lane.curve.get_closest_offset(lane.to_local(def.point))
		var pose := lane.curve.sample_baked_with_rotation(stop.offset,true)
		stop.rotation = pose.get_rotation()+lane.global_rotation
		stop.position = lane.to_global(pose.origin)-Vector2.RIGHT.rotated(stop.rotation)*90-Vector2.DOWN.rotated(stop.rotation)*60
		add_child(stop)
		stops.append(stop)
	for i in 24:
		var person := preload("res://world/harbor/urban_transit/UrbanPassenger.gd").new()
		person.name = "UrbanCommuter%02d"%i
		person.home_stop = i%stops.size()
		person.stop = stops[person.home_stop]
		person.destination_stop = (person.home_stop+1+i%3)%stops.size()
		person.activity = ["trabalho","estudo","compras","volta para casa"][i%4]
		person.district_theme = 1
		person.archetype_override = [0,1,2,6,7][i%5]
		person.ambient_running_enabled = false
		person.base_walk_speed = 48.0
		person.position = person.stop.sidewalk_position(i/6)
		add_child(person)
		passengers.append(person)
		if operating:
			person.walk_route(PackedVector2Array([person.stop.ramp_approach(),person.stop.platform_exit(),person.stop.queue_position(i/6)]),"arriving")
		else:
			person.walk_route(PackedVector2Array([person.global_position]),"off_duty")
	for initial_stop in [0,3]:
		var stop: Node2D = stops[initial_stop]
		var follow := PathFollow2D.new()
		follow.name = "UrbanExpressFollow%d"%initial_stop
		follow.loop = false
		stop.lane.add_child(follow)
		follow.progress = stop.offset
		var bus := preload("res://cars/traffic/TrafficVehicle.tscn").instantiate() as CharacterBody2D
		bus.set_script(preload("res://world/harbor/urban_transit/UrbanBus.gd"))
		bus.name = "UrbanExpress%d"%initial_stop
		bus.system = self
		bus.current_stop = initial_stop
		bus.next_stop = initial_stop
		follow.add_child(bus)
		buses.append(bus)
		bus_arrived(bus,stop)
	ready_for_service = true
	player_ride = preload("res://world/harbor/urban_transit/UrbanPlayerRide.gd").new()
	player_ride.system = self
	add_child(player_ride)
	_update_schedule()

func bus_arrived(bus: Node2D, stop: Node2D) -> void:
	stop.service_bus = bus
	var controller: Node = bus._get_junction_traffic_controller()
	if controller != null:
		var owned: int = controller._owned_junction_for_vehicle(bus.get_instance_id())
		if owned>=0 and not bus.occupies_junction(controller._junction_world_position(owned),float(controller._junctions[owned].radius)):
			controller.release_vehicle(bus.get_instance_id())
	_exchanges[bus] = {"stop":stop,"phase":"unload","elapsed":0.0,"dwell":0.0,"active":null}

func withdraw_bus(bus: Node2D) -> void:
	# A taken bus never rejoins the timetable when the player exits or at 05:00.
	buses.erase(bus)
	var data: Dictionary = _exchanges.get(bus,{})
	var active: Node2D = data.get("active")
	if is_instance_valid(active):
		active.walk_route(PackedVector2Array([active.stop.platform_exit(),active.stop.ramp_approach(),active.stop.sidewalk_position(active.get_index()%4)]),"walking_to_activity")
	_exchanges.erase(bus)
	for stop in stops:
		if stop.service_bus == bus: stop.service_bus = null
	for person in bus.onboard:
		if not is_instance_valid(person): continue
		person.bus = null
		person.global_position = bus.door_position()
		person.stop = stops[bus.current_stop]
		person.walk_route(PackedVector2Array([person.stop.boarding_position(),person.stop.platform_exit(),person.stop.ramp_approach(),person.stop.sidewalk_position(person.get_index()%4)]),"walking_to_activity")
	bus.onboard.clear()

func _physics_process(delta: float) -> void:
	if not ready_for_service: return
	_tick += delta
	if _tick >= 0.25:
		_tick = 0
		_update_schedule()
	_update_people(delta)
	for bus in _exchanges.keys():
		if not is_instance_valid(bus):
			_exchanges.erase(bus)
			continue
		if bus.get_meta("proximity_sleeping", false): continue
		_exchange(bus,delta)

func _update_schedule() -> void:
	var was_open := operating
	operating = is_service_hour(current_hour())
	for stop in stops:
		var count := 0
		for person in passengers:
			if is_instance_valid(person) and not person.is_dead and person.stop == stop and person.transit_state in ["waiting","arriving"]: count += 1
		stop.refresh(operating,count)
		if operating: _order_platform_queue(stop)
	for bus in buses:
		if not is_instance_valid(bus): continue
		if bus.body_model.destination_sign:
			bus.body_model.destination_sign.text = "510 CIRCULAR" if operating else "RECOLHENDO"
			bus._body_render_visible = false
		if operating and bus.suspended:
			bus.suspended = false
			bus.dwelling = true
			bus_arrived(bus,stops[bus.current_stop])
	if was_open and not operating:
		for person in passengers:
			if person.transit_state == "waiting_for_platform":
				person.walk_route(PackedVector2Array([person.stop.sidewalk_position(person.get_index()%4)]),"off_duty")
			elif person.transit_state in ["arriving","waiting"]:
				person.walk_route(PackedVector2Array([person.stop.platform_exit(),person.stop.ramp_approach(),person.stop.sidewalk_position(person.get_index()%4)]),"off_duty")
	elif operating and not was_open:
		for person in passengers:
			if person.transit_state == "off_duty" and not person.is_dead:
				person.walk_route(PackedVector2Array([person.stop.ramp_approach(),person.stop.platform_exit(),person.stop.queue_position(person.get_index()%4)]),"arriving")

func _order_platform_queue(stop: Node2D) -> void:
	# Fill from the far end. People never need to pass through a standing queue.
	var queue: Array = passengers.filter(func(person): return is_instance_valid(person) and not person.is_dead and person.stop == stop and person.transit_state in ["arriving","waiting","waiting_for_platform"])
	queue.sort_custom(func(a,b): return stop.to_local(a.global_position).x < stop.to_local(b.global_position).x)
	for i in queue.size():
		var person: Node2D = queue[i]
		if i >= 4:
			var outside: Vector2 = stop.sidewalk_position(i-4)
			if person.transit_state != "waiting_for_platform": person.walk_route(PackedVector2Array([outside]),"waiting_for_platform")
			continue
		var target: Vector2 = stop.queue_position(i)
		if person.transit_state == "waiting_for_platform":
			person.walk_route(PackedVector2Array([stop.ramp_approach(),stop.platform_exit(),target]),"arriving")
		elif not person.waypoints.is_empty():
			person.waypoints[-1] = target
			if person.waypoints.size() == 1: person.set_destination(target,"arriving")
		elif person.global_position.distance_to(target)>5:
			person.walk_route(PackedVector2Array([target]),"arriving")

func _update_people(delta: float) -> void:
	for person in passengers:
		if not is_instance_valid(person) or person.is_dead: continue
		if person.transit_state == "onboard":
			if is_instance_valid(person.bus): person.global_position = person.bus.global_position
		elif person.get_meta("proximity_sleeping", false):
			continue
		elif person.transit_state == "arriving" and person.waypoints.is_empty():
			person.set_destination(person.global_position,"waiting")
		elif person.transit_state == "walking_to_activity" and person.waypoints.is_empty():
			person.set_destination(person.global_position,"activity")
			person.rest_time = 18+person.get_index()%18
		elif person.transit_state == "activity":
			person.rest_time -= delta
			if person.rest_time <= 0:
				person.destination_stop = (person.stop.stop_id+1+person.trips%3)%stops.size()
				person.walk_route(PackedVector2Array([person.stop.ramp_approach(),person.stop.platform_exit(),person.stop.queue_position(person.get_index()%4)]),"arriving" if operating else "off_duty")

func _exchange(bus: Node2D, delta: float) -> void:
	var data: Dictionary = _exchanges[bus]
	var stop: Node2D = data.stop
	data.elapsed += delta
	data.dwell += delta
	if bus.doors < 0.95: return
	if is_instance_valid(player_ride) and player_ride.holds_stop(bus): return
	var active: Node2D = data.active
	if is_instance_valid(active):
		if active.is_dead or active.is_scared or data.elapsed>14:
			active.walk_route(PackedVector2Array([stop.platform_exit(),stop.ramp_approach(),stop.sidewalk_position(active.get_index()%4)]),"walking_to_activity")
			data.active = null
		elif active.waypoints.is_empty() and active.transit_state == "boarding":
			if operating and is_service_hour(current_hour()):
				active.bus = bus
				active.set_destination(bus.global_position,"onboard")
				active.hide()
				active.set_physics_process(false)
				active.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
				bus.onboard.append(active)
				boarded += 1
			else:
				active.walk_route(PackedVector2Array([stop.platform_exit(),stop.ramp_approach(),stop.sidewalk_position(active.get_index()%4)]),"off_duty")
			data.active = null
			data.elapsed = 0
		elif active.transit_state == "alighting" and active.waypoints.is_empty():
			active.walk_route(PackedVector2Array([stop.ramp_approach(),stop.sidewalk_position(active.get_index()%4)]),"walking_to_activity")
			data.active = null
			data.elapsed = 0
		return
	if data.phase == "unload":
		for person in bus.onboard.duplicate():
			if not is_instance_valid(person) or person.is_dead:
				bus.onboard.erase(person)
				continue
			if person.destination_stop != stop.stop_id and operating and not bus.is_broken: continue
			bus.onboard.erase(person)
			person.bus = null
			person.stop = stop
			person.trips += 1
			person.global_position = bus.door_position()
			person.walk_route(PackedVector2Array([stop.boarding_position(),stop.platform_exit()]),"alighting")
			data.active = person
			data.elapsed = 0
			alighted += 1
			return
		data.phase = "board"
	if not operating or not is_service_hour(current_hour()) or bus.is_broken:
		bus.suspended = true
		bus.dwelling = false
		# End passenger service at the next safe platform. No new boarding overnight.
		_exchanges.erase(bus)
		stop.service_bus = null
		return
	if data.phase == "board":
		var boarding_queue := passengers.duplicate()
		boarding_queue.sort_custom(func(a,b): return a.global_position.distance_squared_to(stop.boarding_position()) < b.global_position.distance_squared_to(stop.boarding_position()))
		for person in boarding_queue:
			if person.stop != stop or person.transit_state != "waiting" or person.is_dead or person.is_scared: continue
			if bus.onboard.size() >= 16: break
			person.allow_boarding(bus)
			person.walk_route(PackedVector2Array([stop.to_global(Vector2(123,14)),bus.door_position()]),"boarding")
			data.active = person
			data.elapsed = 0
			return
		if data.elapsed > 1.2 and data.dwell >= 6.0:
			bus.depart()
			departures += 1
			stop.service_bus = null
			_exchanges.erase(bus)

func _exit_tree() -> void:
	for bus in buses:
		if is_instance_valid(bus) and bus.get_parent() is PathFollow2D: bus.get_parent().queue_free()

func cleanup_removed_bus(reference: WeakRef, owned: Array) -> void:
	var bus := reference.get_ref() as Node
	if is_instance_valid(bus) and bus.is_inside_tree(): return
	for part in owned:
		if is_instance_valid(part): part.queue_free()
