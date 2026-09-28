extends Node3D
## Small public waterfront. Bounded passengers and two fishing posts, no global crowd scan.
const ART := preload("res://world/regions/PortLifeArt.gd")
const VISITOR := preload("res://gameplay/urban_v1/PortVisitor.gd")
const WORKER := preload("res://gameplay/urban_v1/PortWorker.gd")
const BERTH := Vector3(233,0,183.5)
const ARRIVAL := Vector3(233,.56,188.2)
const EXIT := Vector3(223,.18,153)
const FISH_POSTS := [Vector3(239,.2,180.6),Vector3(239,.2,195.1)]
const DWELL := 120.0
const AWAY := 100.0
const TRAVEL := 32.0
var session
var art: Node3D
var ferry: Node3D
var bridge: Node3D
var quay: Node3D
var anglers: Array = [null,null]
var cooldown: Array[float] = [0.0,0.0]
var passengers: Array = []
var phase := "docked"
var clock := 0.0
var departures := 0
var spawned := 0
var spawn_clock := 2.0
var scan_clock := 0.0
var active := false
var arrival_hold := false
var motor: AudioStreamPlayer3D
var boarding_gate: Node3D
var gate_closed := false
var boat_locks: Control

func configure(owner_session) -> void:
	session = owner_session
	name = "HarborPassengerTerminal"

func _ready() -> void:
	art = ART.new()
	add_child(art)
	art.terminal()
	boarding_gate = ART.new()
	boarding_gate.name = "PassengerBoardingGate"
	add_child(boarding_gate)
	boarding_gate.rail(Vector3(232.25,.12,191.8),Vector3(233.75,.12,191.8))
	boarding_gate.flush()
	boarding_gate.hide()
	boarding_gate.solids.collision_layer = 0
	quay = ART.new()
	quay.name = "QuayWorkingDetails"
	add_child(quay)
	quay.quay_details()
	bridge = preload("res://world/urban_detail/UrbanFootbridge3D.gd").new()
	bridge.name = "HarborPublicFootbridge"
	bridge.position = Vector3(223,.13,174.7)
	bridge.width = 3.2
	bridge.accent = Color("435c5e")
	add_child(bridge)
	bridge.build()
	bridge.remove_from_group("footbridges") # This route owns its passengers.
	ferry = ART.new()
	ferry.name = "PassengerFerry"
	add_child(ferry)
	ferry.boat(true)
	ferry.position = BERTH
	motor = AudioStreamPlayer3D.new()
	motor.stream = preload("res://audio/acoustic/engine_diesel_0.wav").duplicate()
	if motor.stream is AudioStreamWAV:
		motor.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		motor.stream.loop_end = int(motor.stream.get_length()*motor.stream.mix_rate)
	motor.max_distance = 38
	motor.unit_size = 5
	motor.volume_db = -17
	if AudioServer.get_bus_index("SFX")>=0: motor.bus = "SFX"
	ferry.add_child(motor)
	var static_owners: Array = [art,quay]
	var lock_layer := CanvasLayer.new()
	lock_layer.name="FishingBoatHints"
	lock_layer.layer=2
	add_child(lock_layer)
	boat_locks=preload("res://gameplay/urban_v1/FishingBoatLocks.gd").new()
	boat_locks.terminal=self
	lock_layer.add_child(boat_locks)
	for i in 2:
		var boat := ART.new()
		boat.name = "FishingBoat%d"%i
		boat.position = Vector3(241,0,182.5+i*6.7)
		add_child(boat)
		boat.boat(false,i)
		boat_locks.anchors.append(boat.global_position+Vector3.UP*1.6)
		static_owners.append(boat)
	var consolidated := ART.new()
	consolidated.name = "BatchedWaterfrontDetails"
	add_child(consolidated)
	consolidated.merge_static_boxes(static_owners)
	refresh_context()

func _exit_tree() -> void:
	for actor in anglers+passengers:
		if is_instance_valid(actor): actor.queue_free()

func refresh_context() -> void:
	if session == null or not is_instance_valid(session.world.player): return
	active = session.state.region_id=="harbor" and session.state.place_id.is_empty() and session.world.player.global_position.distance_to(Vector3(230,0,192))<115
	visible = active
	if motor!=null:
		if active and phase!="away" and not motor.playing: motor.play()
		elif (not active or phase=="away") and motor.playing: motor.stop()
		motor.pitch_scale = .85 if phase=="docked" else 1.05
	for actor in anglers+passengers:
		if is_instance_valid(actor):
			actor.visible = active
			if actor.get("dead") != true and not actor.get_meta("workplace_threatened",false) and not actor.get_meta("street_down",false): actor.set_physics_process(active)

func _process(delta: float) -> void:
	for i in 2: cooldown[i] = maxf(0,cooldown[i]-delta)
	scan_clock -= delta
	if scan_clock<=0:
		scan_clock = .5
		refresh_context()
		if active:
			for i in 2: _ensure_angler(i)
			_clean_passengers()
	if not active: return
	_tick_ferry(delta)

func _ensure_angler(index: int) -> void:
	if is_instance_valid(anglers[index]): return
	if cooldown[index]>0: return
	if cooldown[index]==0 and has_meta("angler_dead_%d"%index) and not WORKER.safe_to_return(session.world,FISH_POSTS[index]): return
	if not session.position_clear(FISH_POSTS[index]+Vector3.UP*.04): return
	var actor := VISITOR.new()
	actor.fishing = true
	actor.fishing_clock = index*11.0
	actor.configure({"id":"harbor_fisher_%d"%index,"position":FISH_POSTS[index],"kind":"fisher","worker_index":index,"coat_color":Color("947349") if index==0 else Color("4b7674")})
	actor.died.connect(_angler_died.bind(index))
	session.world.add_child(actor)
	actor.model.rotation.y = PI if index==0 else 0.0
	anglers[index] = actor

func _angler_died(actor: CharacterBody3D, index: int) -> void:
	cooldown[index] = 180.0
	set_meta("angler_dead_%d"%index,true)
	anglers[index] = null
	get_tree().create_timer(60.0,false).timeout.connect(func():
		if is_instance_valid(actor): actor.queue_free())

func _clean_passengers() -> void:
	for i in range(passengers.size()-1,-1,-1):
		var actor = passengers[i]
		if not is_instance_valid(actor): passengers.remove_at(i); continue
		if actor.dead: continue
		if actor.point_index>=actor.points.size() and WORKER.safe_to_return(session.world,actor.global_position):
			actor.queue_free()
			passengers.remove_at(i)

func _tick_ferry(delta: float) -> void:
	clock += delta
	match phase:
		"docked":
			spawn_clock -= delta
			if spawn_clock<=0 and spawned<6 and passengers.size()<12:
				_spawn_passenger()
				spawn_clock = 5.0
			if clock>=DWELL and not arrival_hold and _boarding_clear():
				phase = "departing"
				clock = 0
		"departing":
			ferry.position = BERTH+Vector3(0,0,-100*smoothstep(0,TRAVEL,clock))
			if clock>=TRAVEL and WORKER.safe_to_return(session.world,ferry.global_position):
				phase = "away"
				clock = 0
				ferry.hide()
				departures += 1
		"away":
			if clock>=AWAY and WORKER.safe_to_return(session.world,BERTH+Vector3(0,0,-100)):
				phase = "approaching"
				clock = 0
				ferry.show()
		"approaching":
			ferry.position = BERTH+Vector3(0,0,-100*(1-smoothstep(0,TRAVEL,clock)))
			if clock>=TRAVEL:
				phase = "docked"
				clock = 0
				spawned = 0
				spawn_clock = 2
	_sync_gate()

func _sync_gate() -> void:
	gate_closed = phase!="docked"
	boarding_gate.visible = gate_closed
	boarding_gate.solids.collision_layer = 1 if gate_closed else 0

func _boarding_clear() -> bool:
	var player: Vector3 = session.world.player.global_position
	if absf(player.x-BERTH.x)<3 and player.z<192 and player.z>176: return false
	for actor in passengers:
		if is_instance_valid(actor) and not actor.dead and actor.global_position.z<192 and actor.global_position.x>231: return false
	return true

func _spawn_passenger() -> void:
	var point := Vector3(233,.56,185.25)
	if not session.position_clear(point): return
	var actor := VISITOR.new()
	actor.configure({"id":"harbor_passenger_%d_%d"%[departures,spawned],"kind":"passenger","position":point,"worker_index":departures*7+spawned})
	actor.points = PackedVector3Array([ARRIVAL,Vector3(233,.5,193.5),Vector3(223,.2,193.5),Vector3(223,5.73,184),Vector3(223,5.73,165.4),Vector3(223,.2,156.6),Vector3(223,.2,137)])
	actor.died.connect(func(dead_actor):
		get_tree().create_timer(60.0,false).timeout.connect(func():
			if is_instance_valid(dead_actor): dead_actor.queue_free()))
	session.world.add_child(actor)
	passengers.append(actor)
	spawned += 1

func prepare_arrival() -> void:
	arrival_hold = true
	phase = "docked"
	clock = 0
	ferry.position = BERTH
	ferry.show()
	_sync_gate()
	refresh_context()

func finish_arrival() -> void:
	arrival_hold = false

func snapshot() -> Dictionary:
	return {"phase":phase,"clock":minf(clock,600.0),"spawned":spawned,"departures":departures,"cooldown":cooldown.duplicate(),"fisher_dead":[has_meta("angler_dead_0"),has_meta("angler_dead_1")]}

static func validate_snapshot(data: Dictionary) -> bool:
	if data.get("phase") not in ["docked","departing","away","approaching"]: return false
	for key in ["clock","spawned","departures"]:
		if typeof(data.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key])<0: return false
	if float(data.clock)>600 or float(data.spawned)>6 or float(data.spawned)!=floorf(float(data.spawned)): return false
	if float(data.departures)>1000000 or float(data.departures)!=floorf(float(data.departures)): return false
	if not data.get("cooldown") is Array or data.cooldown.size()!=2 or not data.get("fisher_dead") is Array or data.fisher_dead.size()!=2: return false
	for value in data.cooldown:
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<0 or float(value)>180: return false
	for value in data.fisher_dead:
		if not value is bool: return false
	return true

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	for actor in anglers+passengers:
		if is_instance_valid(actor): actor.queue_free()
	anglers = [null,null]
	passengers.clear()
	phase = data.phase
	clock = float(data.clock)
	spawned = int(data.spawned)
	departures = int(data.departures)
	cooldown.assign(data.cooldown)
	for i in 2:
		if data.fisher_dead[i]: set_meta("angler_dead_%d"%i,true)
		elif has_meta("angler_dead_%d"%i): remove_meta("angler_dead_%d"%i)
	ferry.position = BERTH
	if phase=="departing": ferry.position.z -= 100*smoothstep(0,TRAVEL,clock)
	elif phase=="approaching": ferry.position.z -= 100*(1-smoothstep(0,TRAVEL,clock))
	elif phase=="away": ferry.position.z -= 100
	ferry.visible = phase!="away"
	_sync_gate()
	return true
