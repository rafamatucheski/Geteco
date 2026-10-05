extends Node3D
## A small recurring evening meet on the persisted world calendar, never quota time.
const CAR := preload("res://gameplay/classic_meet/ClassicMeetCar.gd")
const GUEST := preload("res://gameplay/classic_meet/ClassicMeetGuest.gd")
const EVENINGS := [1,3,5] # Monday is zero: Tuesday, Thursday, Saturday.
const ACTIVATE_DISTANCE := 75.0
const RELEASE_DISTANCE := 95.0
const PAINTS := [Color("bb3834"),Color("479790"),Color("d0a347"),Color("537da6"),Color("ded8c4"),Color("773e68")]
const MODELS := ["gol","parati","passat","coupe","pickup","roadster"]
var session
var gameplay:
	get: return session.world.gameplay if session != null else null
var site: Node3D
var cars: Array[StaticBody3D] = []
var guests: Array[CharacterBody3D] = []
var active := false
var event_active := false
var mode := ""
var cycle_id := -1
var _scan := 0.0
var _car_slots: Dictionary = {}
var _guest_slots: Dictionary = {}
var _sleeping: Dictionary = {}
var _retired: Array[int] = []
var _needs_physics_frame := false

func configure(owner_session, owner_site: Node3D) -> void:
	session = owner_session
	site = owner_site
	name = "ClassicMeetController"

static func is_event_time(day: int, time_of_day: float) -> bool:
	if not is_finite(time_of_day) or time_of_day < 0.0 or time_of_day >= 1.0: return false
	var hour := time_of_day*24.0
	if hour >= 19.0: return posmod(day,7) in EVENINGS
	if hour < 1.0: return posmod(day-1,7) in EVENINGS
	return false

static func event_day(day: int, time_of_day: float) -> int:
	return day-1 if time_of_day*24.0 < 1.0 else day

func _process(delta: float) -> void:
	_scan -= delta
	if _scan > 0.0: return
	_scan = .25
	refresh_context()

func refresh_context() -> void:
	if session == null or not is_instance_valid(site) or session.weather == null: return
	var day := int(session.weather.moon_day())
	var clock := float(session.weather.time_of_day)
	event_active = is_event_time(day,clock)
	var night := clock < .25 or clock >= .75
	var outdoors: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	var player: Node3D = session.world.player
	var near := is_instance_valid(player) and player.global_position.distance_to(site.global_position) < (RELEASE_DISTANCE if active else ACTIVATE_DISTANCE)
	var wanted_active := outdoors and near
	# Teleport/restore may place the player in a formerly empty parked footprint.
	# Keep the population asleep until its physical space is free again.
	if wanted_active and not active and not _sleeping.is_empty():
		for car in cars:
			if is_instance_valid(car) and not _car_space_clear(car.global_position,car.rotation.y):
				wanted_active = false
				break
		if wanted_active:
			for actor in guests:
				if is_instance_valid(actor) and not actor.dead and not _guest_space_clear(actor.global_position):
					wanted_active = false
					break
	site.set_night_lighting(night and outdoors,event_active and wanted_active)
	var desired_mode := "meet" if event_active else ("day" if not night else "quiet")
	var desired_cycle := event_day(day,clock) if event_active else day
	if mode != desired_mode or cycle_id != desired_cycle:
		_record_casualties()
		_clear_population()
		mode = desired_mode
		cycle_id = desired_cycle
		_retired.clear()
		var saved: Dictionary = session.state.world_state.get("classic_meet_absences",{})
		if mode == "meet" and int(saved.get("day",-999)) == cycle_id:
			for index in saved.get("guests",[]): _retired.append(int(index))
		_needs_physics_frame = true
	_set_active(wanted_active)
	if not active: return
	_record_casualties()
	if _needs_physics_frame:
		_needs_physics_frame = false
		return
	_spawn_next()

func _record_casualties() -> void:
	if mode != "meet": return
	for index in _guest_slots:
		var actor = _guest_slots[index]
		if (not is_instance_valid(actor) or actor.dead) and int(index) not in _retired:
			_retired.append(int(index))
	if not _retired.is_empty():
		session.state.world_state["classic_meet_absences"] = {"day":cycle_id,"guests":_retired.duplicate()}

func _set_active(enabled: bool) -> void:
	if active == enabled: return
	active = enabled
	visible = enabled
	if enabled:
		for node in _sleeping:
			if not is_instance_valid(node): continue
			var state: Dictionary = _sleeping[node]
			node.process_mode = state.process_mode
			if node is CollisionObject3D:
				# Damage can arrive via shared fire/emergency systems while suspended.
				# An old cached layer must never give a corpse its standing capsule back.
				node.collision_layer = 0 if node.get("dead") == true else state.layer
				node.collision_mask = 0 if node.get("dead") == true else state.mask
		_sleeping.clear()
	else:
		for node in find_children("*","",true,false):
			var state := {"process_mode":node.process_mode}
			if node is CollisionObject3D:
				state.layer = node.collision_layer
				state.mask = node.collision_mask
				node.collision_layer = 0
				node.collision_mask = 0
			_sleeping[node] = state
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _spawn_next() -> void:
	var slots: Array = site.parking_slots()
	var car_count := 6 if mode == "meet" else (2 if mode == "day" else 1)
	for index in mini(car_count,slots.size()):
		if _car_slots.has(index): continue
		var slot: Dictionary = slots[index]
		var at: Vector3 = site.to_global(slot.position)
		if not _car_space_clear(at,float(slot.yaw)): continue
		var car := CAR.new()
		car.model_id = MODELS[index] if mode == "meet" else ["gol","parati"][index%2]
		car.paint = PAINTS[index] if mode == "meet" else [Color("adafa9"),Color("607c77")][index%2]
		car.hood_open = mode == "meet" and index in [0,2,5]
		car.neon = (Color("29cce5") if index == 1 else Color("cc50de")) if mode == "meet" and index in [1,5] else Color.TRANSPARENT
		car.position = to_local(at)
		car.rotation.y = float(slot.yaw)
		add_child(car)
		cars.append(car)
		_car_slots[index] = car
		return # One indivisible car build per scan; actors wait for its collision.
	var spots: Array = site.pedestrian_spots() if mode == "meet" else []
	if mode == "day":
		for route in site.customer_routes():
			if route.size() > 1: spots.append({"position":route[0],"yaw":0.0,"activity":"walk","route":route})
	for index in spots.size():
		if _guest_slots.has(index) or index in _retired: continue
		var spec: Dictionary = spots[index]
		var at: Vector3 = site.to_global(spec.position)+Vector3.UP*.04
		if not _guest_space_clear(at): continue
		var guest := GUEST.new()
		guest.name = "MeetGuest%d" % index if mode == "meet" else "Customer%d" % index
		guest.identity = 730+index
		guest.initial_yaw = float(spec.yaw)
		guest.meetup_activity = str(spec.activity)
		guest.owner_gameplay = session.world.gameplay
		guest.position = to_local(at)
		guest.set_meta("classic_meet_guest",index)
		guest.died.connect(func(_actor): _record_casualties())
		var path: PackedVector3Array = spec.get("route",PackedVector3Array())
		for point in path: guest.route.append(site.to_global(point))
		# Customer routes describe an approach to the facade. Return along that
		# same aisle, never close the loop diagonally through occupied bays.
		for point_index in range(path.size()-2,0,-1): guest.route.append(site.to_global(path[point_index]))
		add_child(guest)
		guests.append(guest)
		_guest_slots[index] = guest
		return

func _guest_space_clear(point: Vector3) -> bool:
	# FullSession.position_clear intentionally excludes the player for relocation.
	# Ambient admission must include them, otherwise a guest can spawn inside them.
	if not session.position_clear(point): return false
	var shape := CapsuleShape3D.new()
	shape.radius = .34
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = point+Vector3.UP*.9
	query.collision_mask = 6
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _car_space_clear(point: Vector3, yaw: float) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0,2.0,4.7)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP,yaw),point+Vector3.UP*1.0)
	query.collision_mask = 6 # Dynamic actor/vehicle layers, not the supporting pavement.
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _clear_population() -> void:
	for car in cars:
		if is_instance_valid(car):
			car.collision_layer = 0
			car.hide()
			car.queue_free()
	for actor in guests:
		if is_instance_valid(actor):
			actor.collision_layer = 0
			actor.collision_mask = 0
			actor.hide()
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			actor.queue_free()
	cars.clear()
	guests.clear()
	_car_slots.clear()
	_guest_slots.clear()
	_sleeping.clear()
