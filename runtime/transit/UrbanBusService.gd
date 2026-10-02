extends Node3D
## Line 510 operates independently of the player. Identities and trips survive
## distance culling; only nearby actors and vehicles participate in physics.
const BUS := preload("res://runtime/transit/BiarticulatedBus.gd")
const PATH := preload("res://runtime/transit/ArticulatedPath.gd")
const GRAPH := preload("res://gameplay/NativeTrafficRoutes.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const CORRIDOR := ["dock_street","westgate_drive","foundry_avenue","quay_boulevard"]
const CAPACITY := 36
const GATE_X := [-121.0,14.2,133.4]
var controller
var route: Curve3D
var path_poses: RefCounted
var stops: Array[Dictionary] = []
var fleet: Array = []
var people: Array[Dictionary] = []
var prepared := false
var failure := ""
var _clock := 0.0
var boarded := 0
var alighted := 0
var requested_destination := -1
var _person_query := PhysicsShapeQueryParameters3D.new()
var person_blocker := ""
var measured_usec := 0
var measured_ticks := 0

func configure(value) -> void:
	controller = value
	name = "UrbanBusService"
	var capsule := CapsuleShape3D.new()
	capsule.radius = .31; capsule.height = 1.7
	_person_query.shape = capsule; _person_query.collision_mask = 7

static func station_point(definition: Dictionary, pixels: Vector2, height := .2) -> Vector3:
	var point := pixels.rotated(float(definition.angle))/16.0
	var local := Vector3(point.x,height,point.y)
	var row: Dictionary = definition.get("edit",{})
	var stretch: Array = row.get("stretch",[1,1])
	return definition.position+Basis(Vector3.UP,deg_to_rad(float(row.get("rotation",0))))*Vector3(local.x*stretch[0],local.y,local.z*stretch[1])

func build() -> void:
	prepared = true
	var roads: Array = []
	for road in controller.regions.harbor.roads:
		if road.id in CORRIDOR: roads.append(road)
	if roads.size()!=4: failure="Corredor incompleto"; return
	for road in roads:
		if int(road.get("lanes_per_direction",1)) != 2: failure="Corredor requer duas faixas por sentido"; return
	var graph := GRAPH.new()
	graph.configure(roads)
	route = graph.route_near(Vector3(110,0,143),1)
	if route==null or route.get_meta("traffic_open",true): failure="Corredor sem circuito conectado"; route=null; return
	path_poses = PATH.new()
	path_poses.configure(route)
	for index in 6:
		var definition: Dictionary = controller.urban_transit.definitions[index]
		if definition.get("deleted",false): continue
		var local_gate := station_point(definition,Vector2(-121,27))
		var along := (station_point(definition,Vector2(-105,27))-local_gate).normalized()
		var normal := (station_point(definition,Vector2(-121,43))-local_gate).normalized()
		var berth := local_gate+normal*2.3+along*2.7
		berth.y = 0
		var offset := route.get_closest_offset(berth)
		var pose: Transform3D = path_poses.front(offset)
		if pose.origin.distance_to(berth)>.65 or (-pose.basis.z).dot(-along)<.98:
			failure="Estação fora da faixa ou invertida: "+str(definition.name)
			continue
		stops.append({"id":index,"offset":offset,"definition":definition,"gate":local_gate,"inside":station_point(definition,Vector2(-121,12)),"berth":berth})
	stops.sort_custom(func(a,b): return a.offset<b.offset)
	if stops.size()<2: failure="Menos de duas estações alinhadas"; route=null; return
	for index in stops.size():
		for seat in 3:
			people.append({"id":600+index*3+seat,"actor":null,"stop":index,"destination":(index+2+seat)%stops.size(),"phase":"waiting","bus":null,"slot":seat,"age":0.0})
	for index in 2:
		var bus := BUS.new()
		bus.name = "Biarticulado510_%d" % index
		add_child(bus)
		bus.path_poses = path_poses
		# Whole-number grouping/index; preserve integer truncation and precision.
		@warning_ignore("integer_division")
		bus.service_stop = index*stops.size()/2
		bus.set_route(route,float(stops[bus.service_stop].offset))
		bus._apply_poses(path_poses.at(bus.route_distance),false)
		bus.stop_offset = bus.route_distance
		bus.service_state = "exchange"
		bus.dwell = 9+index*3
		fleet.append(bus)
	refresh_presence()

func service_open() -> bool:
	var hour: float = controller.session.weather.time_of_day*24.0
	return hour<2 or hour>=5

func _physics_process(delta: float) -> void:
	if controller==null or controller.session==null or not controller.session.ready_for_play: return
	if not prepared:
		if controller.regions.has("harbor"): build()
		return
	if route==null: return
	if controller.session.modal: return
	var began := Time.get_ticks_usec() if controller.world.get_meta("measure_urban_service",false) else 0
	_clock += delta
	if _clock >= .3:
		_clock=0
		refresh_presence()
	for bus in fleet: tick_bus(bus,delta)
	for person in people:
		if is_instance_valid(person.actor) and person.actor.dead and person.phase!="aboard":
			person.phase="unavailable"
			continue
		if person.phase=="leaving" and is_instance_valid(person.actor) and person.actor.visible:
			var step: int = person.get("walk_step",0)
			var pixels := Vector2(GATE_X[person.get("door",0)],-4) if step==0 else Vector2(-96+person.slot*18,-4)
			var target := station_point(stops[person.stop].definition,pixels) if step<2 else waiting_point(person)
			if walk(person,target):
				person.walk_step=step+1
				if step>=2: person.phase="resting"; person.age=12
		elif person.phase=="resting":
			person.age -= delta
			if person.age<=0: person.phase="waiting"; person.destination=(person.stop+1+person.id%(stops.size()-1))%stops.size()
		elif person.phase=="waiting" and is_instance_valid(person.actor) and person.actor.is_on_floor(): person.actor.set_physics_process(false)
	if began:
		measured_usec+=Time.get_ticks_usec()-began
		measured_ticks+=1

func waiting_point(person: Dictionary) -> Vector3:
	return station_point(stops[person.stop].definition,Vector2(-96+person.slot*18,8))

func create_actor(person: Dictionary, point: Vector3) -> void:
	var actor := ACTOR.new()
	actor.identity = person.id
	actor.controlled_automatically=true; actor.speed=1.35
	actor.position=point+Vector3.UP*.04
	actor.set_meta("persistent_id","urban_passenger_%d" % person.id)
	add_child(actor)
	person.actor=actor

func free_slot(index: int, except: Dictionary) -> int:
	for slot in 14:
		if not people.any(func(p): return p!=except and p.bus==null and p.stop==index and p.slot==slot): return slot
	return 13

func refresh_presence() -> void:
	var enabled: bool = controller.state.region_id=="harbor" and controller.state.place_id.is_empty()
	var focus: Vector3 = controller.world.player.global_position
	for bus in fleet:
		var point: Vector3 = path_poses.front(bus.route_distance).origin
		var near: bool = enabled and (bus.player_aboard or point.distance_to(focus)<(110 if bus.active else 85) or controller._on_screen(point,25))
		bus.set_meta("physical_required",near)
		for light in bus.headlights: light.visible=bus.active and (controller.session.weather.time_of_day<.24 or controller.session.weather.time_of_day>.76)
		if near and not bus.active:
			var poses: Array[Transform3D] = path_poses.at(bus.route_distance)
			for pose in poses: controller.regions.harbor.prepare_collision_at(pose.origin)
			bus._apply_poses(poses,false)
			if bus.admits(poses,false): bus.set_active(true)
		elif not near and bus.active:
			if not bus.player_aboard and not controller._on_screen(point,25): bus.set_active(false)
	for person in people:
		var near: bool = enabled and person.bus==null and waiting_point(person).distance_to(focus)<75 and controller.urban_transit.instances.has(stops[person.stop].definition.id)
		if near and not is_instance_valid(person.actor):
			var point := waiting_point(person)
			if not clear_person(point): continue
			create_actor(person,point)
		if is_instance_valid(person.actor):
			if near and not person.actor.visible:
				var point := waiting_point(person)
				if not clear_person(point,person.actor): continue
				person.actor.teleport(point)
				if person.phase in ["boarding","to_door","leaving"]: person.phase="waiting"
			person.actor.visible=near
			person.actor.collision_layer=2 if near else 0
			person.actor.collision_mask=7 if near else 0
			person.actor.process_mode=Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED

func tick_bus(bus, delta: float) -> void:
	if bus.health<=0:
		bus.speed=0
		bus.set_doors(1)
		return
	if bus.service_state=="approach":
		if bus.active:
			controller.regions.harbor.prepare_collision_at(bus.global_position-bus.global_basis.z*8)
			bus.drive(delta)
		else:
			if bus.get_meta("physical_required",false): return
			var remaining := fposmod(bus.stop_offset-bus.route_distance,route.get_baked_length())
			bus.route_distance = fposmod(bus.route_distance+minf(remaining,4.5*delta),route.get_baked_length())
		var gap := fposmod(bus.stop_offset-bus.route_distance,route.get_baked_length())
		if gap<.035 or gap>route.get_baked_length()-.035:
			bus.speed=0; bus.service_state="exchange"; bus.dwell=7
	elif bus.service_state=="exchange":
		if not bus.active and bus.get_meta("physical_required",false): return
		bus.set_doors(move_toward(bus.door_amount,1,delta*1.5))
		gate(bus.service_stop,bus.active)
		bus.dwell=maxf(0,bus.dwell-delta)
		if bus.door_amount<.99: return
		var done := exchange(bus) if bus.active else virtual_exchange(bus)
		if done and bus.dwell<=0 and service_open() and not doorway_occupied(bus): bus.service_state="closing"
	elif bus.service_state=="closing":
		if doorway_occupied(bus): bus.service_state="exchange"; bus.dwell=2; return
		gate(bus.service_stop,false)
		bus.set_doors(move_toward(bus.door_amount,0,delta*1.5))
		if bus.door_amount<=0:
			bus.service_stop=(bus.service_stop+1)%stops.size()
			bus.stop_offset=stops[bus.service_stop].offset
			bus.service_state="approach"

func gate(index: int, opened: bool) -> void:
	var id: String = stops[index].definition.id
	if not controller.urban_transit.instances.has(id): return
	var station = controller.urban_transit.instances[id].find_child("StationModel",true,false)
	if station==null: station=controller.urban_transit.instances[id].find_child("StationTerminalModel",true,false)
	if station!=null: station.set_boarding_gate(opened)

func clear_person(point: Vector3, actor: CharacterBody3D = null) -> bool:
	_person_query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.86)
	_person_query.exclude = [] if actor==null else [actor.get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(_person_query,1)
	person_blocker = "" if hits.is_empty() else str(hits[0].collider.get_path())+" @ "+str(point)
	return hits.is_empty()

func walk(person: Dictionary, target: Vector3) -> bool:
	var actor = person.actor
	if not is_instance_valid(actor) or actor.dead: return false
	actor.set_physics_process(true)
	var offset: Vector3=target-actor.global_position
	offset.y=0
	actor.automatic_direction=offset.normalized() if offset.length()>.16 else Vector3.ZERO
	return offset.length()<.16

func exchange(bus) -> bool:
	var index: int=bus.service_stop
	for person in bus.passengers.duplicate():
		if person.destination!=index: continue
		var door: int = person.id%3
		var point: Vector3=bus.door_point(door)
		if not clear_person(point,person.actor): bus.blocked_by="Passenger exit: "+person_blocker; return false
		bus.blocked_by=""
		person.bus=null; person.stop=index; person.phase="leaving"; person.walk_step=0; person.door=door
		person.slot=free_slot(index,person)
		bus.passengers.erase(person); alighted+=1
		if not is_instance_valid(person.actor): create_actor(person,point)
		if is_instance_valid(person.actor):
			person.actor.teleport(point)
			person.actor.visible=true
			person.actor.process_mode=Node.PROCESS_MODE_INHERIT
			person.actor.collision_layer=2; person.actor.collision_mask=7
		return false
	for person in people:
		if person.stop==index and person.phase=="to_door":
			if not walk(person,bus.door_point()): return false
			person.bus=bus; person.phase="aboard"
			person.actor.hide(); person.actor.collision_layer=0; person.actor.collision_mask=0
			person.actor.process_mode=Node.PROCESS_MODE_DISABLED
			bus.passengers.append(person); boarded+=1
			return false
	var queue := people.duplicate()
	queue.sort_custom(func(a,b): return a.slot<b.slot)
	for person in queue:
		if person.stop!=index or person.bus!=null or person.phase not in ["waiting","boarding"]: continue
		if bus.passengers.size()+int(bus.player_aboard)>=CAPACITY: return true
		if not is_instance_valid(person.actor) or not person.actor.visible: continue
		if person.actor.dead: person.phase="unavailable"; continue
		person.phase="boarding"
		if not walk(person,stops[index].inside): return false
		# The capsule reaches the gate before boarding; no wall crossing is hidden.
		person.phase="to_door"
		return false
	return not people.any(func(p): return p.stop==index and p.phase in ["boarding","to_door","leaving"])

func virtual_exchange(bus) -> bool:
	for person in bus.passengers.duplicate():
		if person.destination==bus.service_stop:
			hide_person(person)
			person.bus=null; person.stop=bus.service_stop; person.phase="resting"; person.age=12
			person.slot=free_slot(person.stop,person)
			bus.passengers.erase(person)
	for person in people:
		if person.stop==bus.service_stop and person.phase=="waiting" and person.bus==null and bus.passengers.size()<CAPACITY:
			hide_person(person)
			person.bus=bus; person.phase="aboard"; bus.passengers.append(person)
	return true

func hide_person(person: Dictionary) -> void:
	if not is_instance_valid(person.actor): return
	person.actor.hide()
	person.actor.collision_layer=0; person.actor.collision_mask=0
	person.actor.process_mode=Node.PROCESS_MODE_DISABLED

func doorway_occupied(bus) -> bool:
	if not bus.active: return false
	var player: Vector3=controller.world.player.global_position
	for door in 3:
		var point: Vector3 = bus.door_point(door)
		if not bus.player_aboard and player.distance_to(point)<1.2: return true
		if people.any(func(p): return is_instance_valid(p.actor) and p.actor.visible and p.actor.global_position.distance_to(point)<.8): return true
	return false

func boardable_bus():
	if not service_open(): return null
	for bus in fleet:
		if not bus.active or bus.health<=0 or bus.service_state!="exchange" or bus.door_amount<.99: continue
		if bus.passengers.size()>=CAPACITY: continue
		var player: Vector3=controller.world.player.global_position
		if player.distance_to(stops[bus.service_stop].inside)<1.8 or player.distance_to(bus.door_point())<1.5: return bus
	return null

func exit_point(bus) -> Vector3:
	if bus.service_state!="exchange" or bus.door_amount<.99: return Vector3.INF
	var point: Vector3=bus.door_point()
	return point if clear_person(point,controller.world.player) else Vector3.INF
