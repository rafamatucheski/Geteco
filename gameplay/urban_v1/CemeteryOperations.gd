extends Node3D
## Productive V1 cemetery behavior adapted to the native V2 world: stable death
## identity, plot reservation, funeral worker, keeper, storyteller and restored
## grave markers. Runtime actors are attachments; the case ledger is the owner.

const ACTOR := preload("res://gameplay/urban_v1/UrbanRoutineActor.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const SCALE := 1.0 / 16.0
const CENTER := Vector3(-650,0,1740) * SCALE
const GATE := CENTER + Vector3(0,0,-350) * SCALE
const HEARSE_STOP := GATE + Vector3(0,0,-90) * SCALE
const KEEPER_WORK := CENTER + Vector3(-65,0,274) * SCALE
const STORY_STOPS := [Vector3(-90,0,-225),Vector3(-90,0,-65),Vector3(90,0,35),Vector3(90,0,215)]
const STORIES := [
	"Dona Alzira consertava as redes do cais. Nos dias de tempestade, deixava uma vela acesa para quem ainda estava no mar.",
	"Bento era maquinista. Reconhecia cada passageiro pelo passo na plataforma. No último dia, ninguém veio se despedir.",
	"Rosa plantava flores nas janelas da rua inteira. Esta aqui aparece todo inverno. Eu nunca vi quem traz.",
	"Samuel guardava cartas que nunca enviou. Dizia que algumas verdades precisavam esperar. Uma delas desapareceu.",
]
const CASE_PHASES := ["discovered","dispatched","collection","morgue","burial","buried","unrecovered"]
const GUEST_NAMES := ["Lúcia", "Raul", "Otávio", "Marta", "Vicente"]

var session
var cases: Dictionary = {}
var serial := 0
var secret_known := false
var incident_links: Dictionary = {}
var active := false
var scan_clock := 0.0
var keeper: CharacterBody3D
var storyteller: CharacterBody3D
var storyteller_stop := 0
var storyteller_wait := 0.0
var storyteller_told := false
var mortician: CharacterBody3D
var hearse: CharacterBody3D
var mourners: Array[CharacterBody3D] = []
var trip_identity := ""
var trip_phase := "idle"
var trip_clock := 0.0
var graves: Dictionary = {}
var wind: AudioStreamPlayer3D
var deaths: Dictionary = {}
var quiet_left := 0.0
var bodies: Array[Node] = []

func _alive(actor: Node) -> bool:
	return is_instance_valid(actor) and not actor.dead and not actor.is_queued_for_deletion()

func _aisle_route(actor: Node3D, target: Vector3, lane_offset := 0.0) -> PackedVector3Array:
	return PackedVector3Array([Vector3(CENTER.x+lane_offset, .04, actor.global_position.z), Vector3(CENTER.x+lane_offset, .04, target.z), target])

func _arrival_visible() -> bool:
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return false
	for origin in [GATE, HEARSE_STOP, (GATE + HEARSE_STOP) * .5]:
		for offset in [Vector3.ZERO, Vector3(-2,0,-2), Vector3(2,0,-2), Vector3(-2,0,2), Vector3(2,0,2)]:
			if camera.is_position_in_frustum(origin + offset + Vector3.UP): return true
	return false

func _departure_visible() -> bool:
	if _arrival_visible(): return true
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return false
	for actor in mourners:
		if _alive(actor) and camera.is_position_in_frustum(actor.global_position + Vector3.UP): return true
	return _alive(mortician) and camera.is_position_in_frustum(mortician.global_position + Vector3.UP)

func configure(owner_session) -> void:
	session = owner_session
	name = "V1CemeteryOperations"
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _ready() -> void:
	wind = AudioStreamPlayer3D.new()
	wind.name = "CemeteryWind"
	wind.stream = preload("res://audio/regional/wind_0.ogg")
	wind.max_distance = 42
	wind.volume_db = -19
	wind.position = CENTER
	add_child(wind)
	_restore_graves()
	refresh_context()

func _exit_tree() -> void:
	# Funeral actors and the hearse are world siblings, not children of this
	# service. Never leave them running if the service is replaced or stopped.
	_free_actor(mortician)
	mortician = null
	for mourner in mourners: _free_actor(mourner)
	mourners.clear()
	if is_instance_valid(hearse): hearse.queue_free()
	hearse = null
	_free_actor(keeper)
	keeper = null
	_free_actor(storyteller)
	storyteller = null
	trip_identity = ""
	trip_phase = "idle"
	trip_clock = 0.0
	incident_links.clear()
	active = false
	for body in bodies: _free_actor(body)
	bodies.clear()

func refresh_context() -> void:
	if session == null or session.state == null: return
	var in_house: bool = session.state.region_id == "harbor" and session.state.place_id == "cemetery_keeper"
	var near_yard := false
	if session.state.region_id == "harbor" and session.state.place_id.is_empty():
		var focus: Vector3 = session.world.driving.car.global_position if session.world.driving.occupied else session.world.player.global_position
		near_yard = focus.distance_to(CENTER) <= 72.0
	var next_active: bool = in_house or near_yard
	if next_active != active:
		active = next_active
		if not active: _deactivate()
	if active:
		_sync_residents(in_house)
		if not wind.playing and near_yard: wind.play()
		elif not near_yard: wind.stop()
		if near_yard: _try_start_trip()

func _process(delta: float) -> void:
	if session == null or not is_instance_valid(session.world.player): return
	scan_clock -= delta
	if scan_clock <= 0:
		scan_clock = .25
		_observe_emergency()
		refresh_context()
	if not active or not is_finite(delta) or delta <= 0: return
	quiet_left = maxf(0.0, quiet_left - delta)
	if quiet_left == 0.0:
		for resident in [keeper, storyteller]:
			if _alive(resident) and resident.frightened and resident.finished():
				resident.frightened = false
				if resident == storyteller: _story_route()
				else: resident.set_route(_aisle_route(resident, KEEPER_WORK + Vector3.UP * .04))
	_tick_storyteller(delta)
	_tick_trip(delta)

func _observe_emergency() -> void:
	var emergency = session.world.gameplay.emergency if is_instance_valid(session.world.gameplay) else null
	if not is_instance_valid(emergency): return
	var seen := {}
	for key in emergency.incidents:
		var record: Dictionary = emergency.incidents[key]
		if record.get("role","") != "mortician" or not is_instance_valid(record.get("actor")): continue
		seen[key] = true
		var actor: Node = record.actor
		var identity := str(actor.get_meta("urban_burial_identity",""))
		if identity.is_empty():
			identity = _next_deceased_identity()
			actor.set_meta("urban_burial_identity",identity)
		if not cases.has(identity):
			cases[identity] = {"identity":identity,"name":_actor_name(actor),"phase":"discovered","plot":-1}
		var link: Dictionary = incident_links.get(key,{"identity":identity,"assigned":false,"serviced":false})
		link.identity = identity
		link.assigned = bool(record.get("assigned",false))
		var crew: Variant = record.get("crew")
		if is_instance_valid(crew) and str(crew.get("mode")) == "service": link.serviced = true
		incident_links[key] = link
		if bool(link.serviced): cases[identity].phase = "collection"
		elif bool(link.assigned) and cases[identity].phase == "discovered": cases[identity].phase = "dispatched"
	for key in incident_links.keys():
		if seen.has(key): continue
		var link: Dictionary = incident_links[key]
		var identity: String = str(link.identity)
		if cases.has(identity) and cases[identity].phase not in ["buried","morgue","burial"]:
			cases[identity].phase = "morgue" if bool(link.serviced) else "unrecovered"
		incident_links.erase(key)

func _next_deceased_identity() -> String:
	# A tolerated legacy/synthetic payload may carry a serial lower than one of
	# its stable identities. Skip occupied numbers instead of aliasing two deaths.
	serial += 1
	var identity := "harbor_deceased:%08d" % serial
	while cases.has(identity):
		serial += 1
		identity = "harbor_deceased:%08d" % serial
	return identity

func register_synthetic_case(identity: String, display_name: String) -> bool:
	# Deterministic integration seam used by tests and by a future explicit
	# EmergencyManager signal. It never grants money or touches personal saves.
	if identity.is_empty() or identity.length()>128 or cases.has(identity): return false
	cases[identity] = {"identity":identity,"name":display_name.left(96),"phase":"morgue","plot":-1}
	return true

func _actor_name(actor: Node) -> String:
	var value := str(actor.get_meta("display_name",actor.name)).strip_edges()
	return "Não identificado" if value.is_empty() else value.left(96)

func _sync_residents(in_house: bool) -> void:
	if in_house:
		_free_actor(storyteller)
		storyteller = null
		if not is_instance_valid(session.room): return
		if deaths.has("keeper"): return
		if not is_instance_valid(keeper):
			keeper = _actor("keeper","ANSELMO")
		if keeper.dead or keeper.frightened: return
		if keeper.get_meta("keeper_room", 0) != session.room.get_instance_id():
			# Leave room for the .30 m capsule in front of the workbench.
			# Context scans must not undo physical movement every quarter second.
			keeper.global_position = session.room.to_global(Vector3(-2.35,.04,-1.85))
			keeper.velocity = Vector3.ZERO
			keeper.reset_physics_interpolation()
			keeper.set_route(PackedVector3Array())
			keeper.set_working(false)
			keeper.set_meta("keeper_room", session.room.get_instance_id())
		return
	if is_instance_valid(keeper) and keeper.global_position.distance_to(CENTER)>90:
		_free_actor(keeper)
		keeper = null
	if not is_instance_valid(keeper) and not deaths.has("keeper"):
		keeper = _actor("keeper","ANSELMO")
		keeper.position = KEEPER_WORK+Vector3.UP*.04
		keeper.set_working(true)
	if not is_instance_valid(storyteller) and not deaths.has("storyteller"):
		storyteller = _actor("storyteller","ELIAS")
		storyteller.position = CENTER+Vector3(0,0,-280)*SCALE+Vector3.UP*.04
		_story_route()

func _actor(role: String, display_name: String, shirt_override := Color.TRANSPARENT) -> CharacterBody3D:
	var actor = ACTOR.new()
	actor.configure(role,display_name,shirt_override)
	session.world.add_child(actor)
	actor.bind_combat(session.world.gameplay)
	actor.died.connect(_actor_died)
	actor.threatened.connect(_actor_threatened)
	return actor

func _death_key(actor: Node) -> String:
	if actor.role in ["keeper", "storyteller"]: return actor.role
	return str(actor.get_meta("funeral_identity", trip_identity)) + ":" + str(actor.get_meta("persistent_id", ""))

func _actor_died(actor: CharacterBody3D) -> void:
	deaths[_death_key(actor)] = true
	_actor_threatened(actor)

func _actor_threatened(_threatened_actor: CharacterBody3D) -> void:
	quiet_left = 30.0
	if not trip_identity.is_empty() and trip_phase != "returning":
		if cases[trip_identity].phase == "burial": cases[trip_identity].phase = "morgue"
		trip_phase = "returning"
		_send_funeral_home()
	for resident in [keeper, storyteller]:
		if not _alive(resident): continue
		resident.frightened = true
		resident.speech.hide()
		if session.state.place_id.is_empty():
			var side := -1.0 if resident == keeper else 1.0
			var escape := _aisle_route(resident, GATE + Vector3(side * .65, .04, -1.2))
			escape.append(GATE + Vector3(side * 4.5, .04, -1.2))
			resident.set_route(escape)
		else: resident.set_route(PackedVector3Array())

func _story_route() -> void:
	if not _alive(storyteller) or storyteller.frightened: return
	var target: Vector3 = CENTER+STORY_STOPS[storyteller_stop]*SCALE+Vector3.UP*.04
	# V1 keeps Elias on the central aisle before he turns toward a grave.
	storyteller.set_route(PackedVector3Array([
		Vector3(CENTER.x,.04,storyteller.global_position.z),
		Vector3(CENTER.x,.04,target.z),
		target,
	]))
	storyteller_wait = 0
	storyteller_told = false

func _tick_storyteller(delta: float) -> void:
	if not _alive(storyteller) or storyteller.frightened or not storyteller.finished(): return
	storyteller_wait += delta
	var nearby: bool = session.state.place_id.is_empty() and session.world.player.global_position.distance_to(storyteller.global_position)<8.45
	if nearby and not storyteller_told:
		storyteller.say("ELIAS: "+STORIES[storyteller_stop],12)
		storyteller_told = true
		storyteller_wait = 0
	elif not nearby and storyteller_told and is_instance_valid(storyteller.speech):
		storyteller.speech.hide()
	if storyteller_wait > 18:
		storyteller_stop = (storyteller_stop+1)%STORY_STOPS.size()
		_story_route()

func nearest_action() -> Dictionary:
	if not active or session.world.driving.occupied or not _alive(keeper) or keeper.frightened: return {}
	if session.world.player.global_position.distance_to(keeper.global_position)>1.7: return {}
	return {"id":"urban_v1","target":"cemetery_keeper","label":"Conversar","position":keeper.global_position}

func perform(target: String) -> bool:
	if target != "cemetery_keeper" or nearest_action().get("target","") != target: return false
	secret_known = true
	session.show_dialogue([{"speaker":"ANSELMO","message":"Samuel não está lá. A carta, junto ao muro sudeste... não mostre a ninguém."}])
	return true

func _try_start_trip() -> void:
	if not active or not trip_identity.is_empty() or session.state.place_id != "": return
	if quiet_left > 0.0 or _arrival_visible(): return
	var identities: Array = cases.keys()
	identities.sort()
	for identity in identities:
		if cases[identity].phase != "morgue": continue
		if deaths.has(str(identity) + ":cemetery_mortician"): continue
		_start_trip(identity)
		return

func _start_trip(identity: String) -> void:
	if not cases.has(identity) or cases[identity].phase != "morgue": return
	var plot := int(cases[identity].plot)
	if plot < 0:
		plot = _free_plot()
		if plot < 0: return
		cases[identity].plot = plot
	trip_identity = identity
	trip_phase = "arriving"
	trip_clock = 0
	cases[identity].phase = "burial"
	hearse = VEHICLE.new()
	hearse.archetype = "station_wagon"
	hearse.paint_color = Color("202128")
	hearse.vehicle_id = "funeral_hearse:"+identity
	hearse.input_locked = true
	hearse.engine_disabled = true
	hearse.set_meta("gameplay_role","funeral_service")
	session.world.add_child(hearse)
	hearse.place(HEARSE_STOP+Vector3.UP*.04,0)
	mortician = _actor("mortician","Agente funerário")
	mortician.set_meta("funeral_identity", identity)
	mortician.position = HEARSE_STOP+Vector3(1.5,.04,0)
	var point := _plot_position(plot)
	var plot_side := signf(point.x - CENTER.x)
	mortician.attention = point
	mortician.has_attention = true
	mortician.set_route(PackedVector3Array([GATE+Vector3(1.5,.04,-2), GATE+Vector3.UP*.04, Vector3(CENTER.x,.04,point.z), point+Vector3(plot_side*1.5,.04,0)]))
	if _alive(keeper): keeper.set_route(_aisle_route(keeper, point+Vector3(0,.04,-1.6)))
	# HarborWorldEvents creates five staggered funeral guests in production V1.
	# They remain attachments to this one ledger-owned funeral, never save owners.
	for index in 5:
		if deaths.has(identity + ":cemetery_mourner_%02d" % index): continue
		var mourner = _actor("mourner",GUEST_NAMES[index],Color("343543") if index%2 else Color("45434b"))
		mourner.set_meta("persistent_id","cemetery_mourner_%02d" % index)
		mourner.set_meta("funeral_identity", identity)
		mourner.attention = point
		mourner.has_attention = true
		var lane := -0.65 if index%2==0 else 0.65
		mourner.position = GATE+Vector3(signf(lane)*1.6,.04,-1.8-index*.85)
		mourner.departure_delay = .8 + index * .65
		# Keep the central aisle free even for the two plots nearest its edge.
		# Whole-number grouping/index; preserve integer truncation and precision.
		@warning_ignore("integer_division")
		var target := Vector3(CENTER.x+plot_side*(5.8-float(index%3)*1.1),.04,point.z+1.8+float(index/3)*1.1)
		mourner.set_route(PackedVector3Array([GATE+Vector3(signf(lane)*1.6,.04,-1.2), GATE+Vector3(lane,.04,1.2), Vector3(CENTER.x+lane,.04,target.z), target]))
		mourners.append(mourner)

func _tick_trip(delta: float) -> void:
	if trip_identity.is_empty(): return
	if not cases.has(trip_identity):
		_interrupt_trip()
		return
	match trip_phase:
		"arriving":
			if _alive(mortician) and mortician.finished() and _guests_finished():
				trip_phase = "working"
				trip_clock = 0
				mortician.set_working(true)
				if is_instance_valid(keeper): keeper.set_working(true)
		"working":
			trip_clock += delta
			if trip_clock >= 5.0: _finish_burial()
		"returning":
			if (not _alive(mortician) or mortician.finished()) and _guests_finished() and not _departure_visible(): _complete_trip()

func _guests_finished() -> bool:
	for mourner in mourners:
		if _alive(mourner) and not mourner.finished(): return false
	return true

func _finish_burial() -> void:
	var identity := trip_identity
	cases[identity].phase = "buried"
	_build_grave(identity)
	trip_phase = "returning"
	trip_clock = 0
	_send_funeral_home()
	if _alive(keeper):
		keeper.set_working(false)
		var opposite_lane := -signf(_plot_position(int(cases[identity].plot)).x - CENTER.x) * .85
		keeper.set_route(_aisle_route(keeper, KEEPER_WORK+Vector3.UP*.04, opposite_lane))

func _send_funeral_home() -> void:
	if _alive(mortician):
		mortician.set_working(false)
		mortician.has_attention = false
		mortician.frightened = quiet_left > 0.0
		mortician.carrying_body = false
		var rear_clearance: float = hearse.half_length + .75 if is_instance_valid(hearse) else 3.05
		mortician.set_route(_aisle_route(mortician, HEARSE_STOP+Vector3(0,.04,rear_clearance)))
	for index in mourners.size():
		var mourner = mourners[index]
		if _alive(mourner):
			mourner.has_attention = false
			mourner.frightened = quiet_left > 0.0
			var lane := -.85 if mourner.global_position.x < CENTER.x else .85
			# Leave the walking lane before waiting. Arrival order can change when
			# visitors avoid each other, so merely reversing queue slots is unsafe.
			var stop_z := -2.0 - index * .85
			mourner.set_route(PackedVector3Array([Vector3(CENTER.x+lane,.04,mourner.global_position.z-.75),GATE+Vector3(lane,.04,1.2),GATE+Vector3(signf(lane)*1.6,.04,-1.2),GATE+Vector3(signf(lane)*1.6,.04,stop_z),GATE+Vector3(signf(lane)*3.2,.04,stop_z)]))

func _complete_trip() -> void:
	_release_guest(mortician)
	mortician = null
	for mourner in mourners: _release_guest(mourner)
	mourners.clear()
	if is_instance_valid(hearse): hearse.queue_free()
	hearse = null
	trip_identity = ""
	trip_phase = "idle"
	trip_clock = 0
	_try_start_trip()

func _release_guest(actor: Node) -> void:
	if not is_instance_valid(actor): return
	if actor.dead and active:
		bodies.append(actor)
	else: _free_actor(actor)

func _interrupt_trip() -> void:
	if cases.has(trip_identity) and cases[trip_identity].phase == "burial": cases[trip_identity].phase = "morgue"
	_complete_trip()

func _free_plot() -> int:
	var used := {}
	for record in cases.values():
		if int(record.get("plot",-1)) >= 0: used[int(record.plot)] = true
	for index in 12:
		if not used.has(index): return index
	return -1

func _plot_position(index: int) -> Vector3:
	# Whole-number grouping/index; preserve integer truncation and precision.
	@warning_ignore("integer_division")
	var row := index / 4
	var col := index % 4
	return CENTER+Vector3(-78+col*52,0,-20+row*62)*SCALE

func _build_grave(identity: String) -> void:
	if graves.has(identity) and is_instance_valid(graves[identity]): return
	var record: Dictionary = cases.get(identity,{})
	var plot := int(record.get("plot",-1))
	if plot < 0 or plot >= 12: return
	var grave := Node3D.new()
	grave.name = "Burial_"+identity.validate_node_name()
	grave.position = _plot_position(plot)
	grave.set_meta("burial_identity",identity)
	add_child(grave)
	_box(grave,Vector3(0,.035,0),Vector3(1.45,.07,2.15),Color("493c31"))
	_box(grave,Vector3(0,.45,-.78),Vector3(.12,.9,.12),Color("745b43"))
	_box(grave,Vector3(0,.63,-.78),Vector3(.55,.12,.12),Color("745b43"))
	graves[identity] = grave

func _restore_graves() -> void:
	for identity in cases:
		if cases[identity].phase == "buried": _build_grave(identity)

func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .92
	node.material_override = material
	parent.add_child(node)

func _deactivate() -> void:
	wind.stop()
	_free_actor(storyteller)
	storyteller = null
	_free_actor(keeper)
	keeper = null
	if not trip_identity.is_empty(): _interrupt_trip()
	for body in bodies: _free_actor(body)
	bodies.clear()

func _free_actor(actor: Node) -> void:
	if is_instance_valid(actor): actor.queue_free()

func snapshot() -> Dictionary:
	var records: Array = []
	var identities: Array = cases.keys()
	identities.sort()
	for identity in identities:
		var source: Dictionary = cases[identity]
		var phase: String = str(source.phase)
		# A half-materialized funeral never survives a save as a duplicated actor;
		# it resumes from the persisted morgue queue. Emergency actors themselves
		# are not persisted, so uncollected calls become a stable unrecovered case.
		if phase in ["collection","burial"]: phase = "morgue"
		elif phase in ["discovered","dispatched"]: phase = "unrecovered"
		records.append({"identity":identity,"name":str(source.name),"phase":phase,"plot":int(source.plot)})
	return {"version":1,"serial":serial,"secret_known":secret_known,"storyteller_stop":storyteller_stop,"cases":records,"deaths":deaths.keys()}

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	_free_actor(keeper)
	keeper = null
	_free_actor(storyteller)
	storyteller = null
	for body in bodies: _free_actor(body)
	bodies.clear()
	deaths.clear()
	for identity in data.get("deaths", []): deaths[identity] = true
	quiet_left = 0.0
	# Runtime funeral actors are attachments, never save owners. A restore first
	# tears them down and reconstructs only from the case ledger.
	_free_actor(mortician)
	mortician = null
	for mourner in mourners: _free_actor(mourner)
	mourners.clear()
	if is_instance_valid(hearse): hearse.queue_free()
	hearse = null
	trip_identity = ""
	trip_phase = "idle"
	trip_clock = 0
	incident_links.clear()
	cases.clear()
	serial = int(data.serial)
	secret_known = bool(data.secret_known)
	storyteller_stop = int(data.storyteller_stop)
	for source in data.cases:
		cases[source.identity] = source.duplicate(true)
	for grave in graves.values():
		if is_instance_valid(grave): grave.queue_free()
	graves.clear()
	_restore_graves()
	if active: refresh_context()
	return true

static func validate_snapshot(data: Dictionary) -> bool:
	if data.get("version") != 1 or not data.get("cases") is Array or data.cases.size()>64: return false
	if typeof(data.get("serial")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data.serial)) or float(data.serial)!=floorf(float(data.serial)) or int(data.serial)<0 or int(data.serial)>10000000: return false
	if not data.get("secret_known") is bool: return false
	var stop: Variant = data.get("storyteller_stop")
	if typeof(stop) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(stop)) or float(stop)!=floorf(float(stop)) or int(stop)<0 or int(stop)>=STORY_STOPS.size(): return false
	var identities := {}
	var plots := {}
	for record in data.cases:
		if not record is Dictionary or not record.get("identity") is String or record.identity.is_empty() or record.identity.length()>128 or identities.has(record.identity): return false
		if not record.get("name") is String or record.name.length()>96 or record.get("phase") not in ["morgue","buried","unrecovered"]: return false
		var plot_value: Variant = record.get("plot")
		if typeof(plot_value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(plot_value)) or float(plot_value)!=floorf(float(plot_value)): return false
		var plot := int(plot_value)
		if plot < -1 or plot >= 12 or (plot >= 0 and plots.has(plot)): return false
		if record.phase == "buried" and plot < 0: return false
		identities[record.identity] = true
		if plot >= 0: plots[plot] = true
	var saved_deaths: Variant = data.get("deaths", [])
	if not saved_deaths is Array or saved_deaths.size() > 386: return false
	var seen := {}
	for identity in saved_deaths:
		if not identity is String or seen.has(identity): return false
		if identity not in ["keeper", "storyteller"]:
			var valid := false
			for case_id in identities:
				if identity == case_id + ":cemetery_mortician": valid = true
				for index in 5:
					if identity == case_id + ":cemetery_mourner_%02d" % index: valid = true
			if not valid: return false
		seen[identity] = true
	return true
