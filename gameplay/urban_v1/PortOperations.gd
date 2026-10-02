extends Node3D
## Functional V1 South Port launch cycle. The authored 2D coordinates are
## converted once to the native V2 metre grid; workers move physical bodies and
## cargo is conserved instead of being a decorative animation.

const WORKER := preload("res://gameplay/urban_v1/PortWorker.gd")
const SCALE := 1.0 / 16.0
const ACTIVE_DISTANCE := 92.0
const BERTHS := [Vector3(6380, 0, 3700) * SCALE, Vector3(6380, 0, 4260) * SCALE]
const DAY_SECONDS := 600.0

var session
var boats: Array[Dictionary] = []
var saved_workers: Array[Dictionary] = [{}, {}]
var active := false
var scan_clock := 0.0
var materials: Dictionary = {}
var worker_respawn: Array[float] = [0.0,0.0]
var worker_was_dead: Array[bool] = [false,false]

func configure(owner_session) -> void:
	session = owner_session
	name = "V1PortOperations"
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _ready() -> void:
	for index in BERTHS.size():
		var visual := _build_launch(index)
		visual.name = "CargoLaunch%02d" % index
		visual.position = BERTHS[index]
		visual.hide()
		add_child(visual)
		var stock_visual := _build_stock()
		stock_visual.name = "CargoStock%02d" % index
		stock_visual.position = Vector3(6120.0*SCALE,0,BERTHS[index].z)
		stock_visual.hide()
		add_child(stock_visual)
		boats.append({
			"id":"south_port_launch_%02d" % index,
			"berth":BERTHS[index], "visual":visual, "stock_visual":stock_visual, "worker":null,
			"load":0, "phase":"loading", "clock":0.0,
		})
	refresh_context()

func _exit_tree() -> void:
	# Loaders live under the world so they do not inherit the launch transform.
	# Explicitly release those sibling attachments when this service is removed.
	for index in boats.size():
		var boat: Dictionary = boats[index]
		if is_instance_valid(boat.worker): boat.worker.queue_free()
		boat.worker = null
	active = false

func refresh_context() -> void:
	if session == null or session.state == null: return
	var should_activate: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	if should_activate:
		var focus: Vector3 = session.world.driving.car.global_position if session.world.driving.occupied else session.world.player.global_position
		should_activate = focus.distance_to((BERTHS[0] + BERTHS[1]) * .5) <= ACTIVE_DISTANCE
	if should_activate == active: return
	active = should_activate
	for index in boats.size():
		var boat: Dictionary = boats[index]
		boat.visual.visible = active and boat.phase != "away"
		boat.stock_visual.visible = active and boat.phase == "loading"
		if active: _ensure_worker(index)
		else: _suspend_worker(index)

func _process(delta: float) -> void:
	for i in 2: worker_respawn[i] = maxf(0,worker_respawn[i]-delta)
	if session == null or not is_instance_valid(session.world.player): return
	scan_clock -= delta
	if scan_clock <= 0:
		scan_clock = .25
		refresh_context()
		if active:
			for i in boats.size(): _ensure_worker(i)
	if not active or not is_finite(delta) or delta <= 0: return
	for index in boats.size(): _tick_boat(index, delta)

func _tick_boat(index: int, delta: float) -> void:
	var boat: Dictionary = boats[index]
	var worker = boat.worker
	if not is_instance_valid(worker): return
	match str(boat.phase):
		"loading":
			if worker.crate_stock[1] > 0:
				boat.load = mini(30, int(boat.load) + int(worker.crate_stock[1]))
				worker.crate_stock[1] = 0
				_set_load(boat.visual, int(boat.load))
			_set_stock(boat.stock_visual,int(worker.crate_stock[0]))
			if int(boat.load) == 30 and worker.activity == "rest":
				boat.phase = "departing"
				boat.clock = 0.0
				boat.visual.rotation.y = PI
				boat.stock_visual.hide()
				_configure_worker(worker, boat.berth, false)
		"departing":
			boat.clock = float(boat.clock) + delta
			var leg := DAY_SECONDS / 48.0 * .2
			boat.visual.position = boat.berth + Vector3(0, 0, 81.25 * minf(1.0, float(boat.clock) / leg))
			if float(boat.clock) >= leg:
				boat.visual.hide()
				boat.phase = "away"
				boat.clock = 0.0
		"away":
			boat.clock = float(boat.clock) + delta
			if float(boat.clock) >= DAY_SECONDS / 48.0 * .6:
				boat.load = 0
				_set_load(boat.visual, 0)
				boat.visual.rotation.y = 0
				boat.visual.position = boat.berth + Vector3(0, 0, 81.25)
				boat.visual.show()
				boat.phase = "returning"
				boat.clock = 0.0
		"returning":
			var leg := DAY_SECONDS / 48.0 * .2
			boat.visual.position = boat.visual.position.move_toward(boat.berth, delta * 81.25 / leg)
			if boat.visual.position.distance_to(boat.berth) < .05 and not worker.carrying:
				boat.visual.position = boat.berth
				boat.phase = "loading"
				boat.clock = 0.0
				_configure_worker(worker, boat.berth, true)
				boat.stock_visual.show()
				_set_stock(boat.stock_visual,30)

func _ensure_worker(index: int) -> void:
	var boat: Dictionary = boats[index]
	if is_instance_valid(boat.worker):
		if not boat.worker.get_meta("workplace_threatened",false) and not boat.worker.get_meta("street_down",false): boat.worker.set_physics_process(true)
		return
	if worker_respawn[index]>0: return
	var berth: Vector3 = boat.berth
	var source := Vector3(6120.0 * SCALE, 0, berth.z)
	if worker_was_dead[index] and not WORKER.safe_to_return(session.world,source): return
	if not session.position_clear(source+Vector3.UP*.06): return
	var destination := Vector3((6315.0 if boat.phase == "loading" else 6180.0) * SCALE, 0, berth.z)
	var route: Array[Vector3] = [source, Vector3(6160.0 * SCALE,0,berth.z), destination, Vector3(6160.0 * SCALE,0,berth.z + 18.0 * SCALE)]
	var definition := {
		"id":"south_port_launch_loader_%02d" % index,
		"display_name":"Carregador do cais", "region":"harbor", "place_id":"",
		"kind":"dock_worker", "position":route[0], "route":route,
		"stations":[route[0],route[2]], "worker_index":40 + index,
		"night_shift":true, "lines":[],
		"source":"world/harbor/HarborSouthPort.gd -> HarborLaunchRoutine.gd",
	}
	var worker = WORKER.new()
	worker.configure(definition, Callable(session,"position_clear"))
	worker.died.connect(_loader_died.bind(index))
	session.world.add_child(worker)
	if not saved_workers[index].is_empty():
		worker.restore_routine(saved_workers[index])
	else:
		worker.crate_stock.assign([30 if boat.phase == "loading" else 3, 0])
	boat.worker = worker
	_set_stock(boat.stock_visual,int(worker.crate_stock[0]))

func _loader_died(actor: CharacterBody3D, index: int) -> void:
	worker_respawn[index] = 180.0
	worker_was_dead[index] = true
	# Return any held crate to its source; death must not create or erase freight.
	var interrupted: Dictionary = actor.snapshot_routine()
	if interrupted.carrying:
		interrupted.crate_stock[int(interrupted.source_index)] += 1
	interrupted.carrying = false
	interrupted.activity = "return"
	interrupted.route_index = int(interrupted.source_index)*2
	interrupted.position = actor.home
	interrupted.velocity = Vector3.ZERO
	saved_workers[index] = interrupted
	boats[index].worker = null
	get_tree().create_timer(60.0,false).timeout.connect(func():
		if is_instance_valid(actor): actor.queue_free())

func _suspend_worker(index: int) -> void:
	var boat: Dictionary = boats[index]
	if not is_instance_valid(boat.worker): return
	saved_workers[index] = boat.worker.snapshot_routine()
	boat.worker.queue_free()
	boat.worker = null

func _configure_worker(worker, berth: Vector3, loading: bool) -> void:
	var source := Vector3(6120.0 * SCALE,0,berth.z)
	var destination := Vector3((6315.0 if loading else 6180.0) * SCALE,0,berth.z)
	var route: Array[Vector3] = [source,Vector3(6160.0*SCALE,0,berth.z),destination,Vector3(6160.0*SCALE,0,berth.z+18.0*SCALE)]
	worker.route = route
	worker.definition.route = worker.route.duplicate()
	worker.definition.stations = [source,destination]
	worker.crate_stock.assign([30 if loading else 3,0])
	worker.source_index = 0
	worker.route_index = 0
	worker.destination = source
	worker.carrying = false
	worker._set_activity("return")

func snapshot() -> Dictionary:
	var records: Array = []
	for index in boats.size():
		var boat: Dictionary = boats[index]
		var worker_state: Dictionary = boat.worker.snapshot_routine() if is_instance_valid(boat.worker) else saved_workers[index]
		records.append({
			"id":boat.id, "load":int(boat.load), "phase":str(boat.phase),
			"clock":float(boat.clock), "position":[boat.visual.position.x,boat.visual.position.y,boat.visual.position.z],
			"worker":_encode_worker(worker_state),
		})
	return {"version":1,"boats":records}

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	# Restore is authoritative even while the berth is streamed in. Dispose the
	# live attachment first so one loader cannot survive beside its restored copy.
	for index in boats.size():
		var live_boat: Dictionary = boats[index]
		if is_instance_valid(live_boat.worker): live_boat.worker.queue_free()
		live_boat.worker = null
	for source_value in data.boats:
		var source: Dictionary = source_value
		var index := 0 if source.id == "south_port_launch_00" else 1
		var boat: Dictionary = boats[index]
		boat.load = int(source.load)
		boat.phase = str(source.phase)
		boat.clock = float(source.clock)
		boat.visual.position = Vector3(source.position[0],source.position[1],source.position[2])
		boat.visual.rotation.y = PI if boat.phase in ["departing","away"] else 0.0
		_set_load(boat.visual,int(boat.load))
		saved_workers[index] = _decode_worker(source.worker)
		boat.visual.visible = active and boat.phase != "away"
		boat.stock_visual.visible = active and boat.phase == "loading"
	if active:
		for index in boats.size(): _ensure_worker(index)
	refresh_context()
	return true

static func validate_snapshot(data: Dictionary) -> bool:
	if data.get("version") != 1 or not data.get("boats") is Array or data.boats.size() != 2: return false
	var ids := {}
	for record in data.boats:
		if not record is Dictionary or record.get("id") not in ["south_port_launch_00","south_port_launch_01"] or ids.has(record.id): return false
		ids[record.id] = true
		if record.get("phase") not in ["loading","departing","away","returning"]: return false
		var load_value: Variant = record.get("load")
		if typeof(load_value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(load_value)) or float(load_value)!=floorf(float(load_value)) or int(load_value)<0 or int(load_value)>30: return false
		if typeof(record.get("clock")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(record.clock)) or float(record.clock)<0 or float(record.clock)>600: return false
		if not record.get("position") is Array or record.position.size()!=3: return false
		for value in record.position:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value))>100000: return false
		if not record.get("worker") is Dictionary: return false
		var worker: Dictionary = record.worker
		if worker.is_empty():
			if record.phase != "loading" or int(record.load) != 0: return false
			continue
		if not _worker_payload_valid(worker): return false
		var stock: Array = worker.crate_stock
		var total := int(stock[0])+int(stock[1])+int(bool(worker.carrying))
		if record.phase == "loading":
			if int(record.load)+total != 30: return false
		elif total != 3: return false
	return true

static func _worker_payload_valid(worker: Dictionary) -> bool:
	for key in ["position","velocity","destination"]:
		var vector: Variant = worker.get(key)
		if not vector is Array or vector.size()!=3: return false
		for value in vector:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value))>100000: return false
	var stock: Variant = worker.get("crate_stock")
	if not stock is Array or stock.size()!=2: return false
	for value in stock:
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or float(value)!=floorf(float(value)) or int(value)<0 or int(value)>30: return false
	if not worker.get("carrying") is bool: return false
	for key in ["route_index","deliveries","source_index","routine_cycle","dialogue_index"]:
		var value: Variant = worker.get(key)
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or float(value)!=floorf(float(value)) or int(value)<0 or int(value)>10000000: return false
	if int(worker.source_index)>1 or not worker.get("activity") is String or worker.activity.length()>32: return false
	for key in ["activity_left","travel_left"]:
		var value: Variant = worker.get(key)
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<0 or float(value)>100000: return false
	var rng_state: Variant = worker.get("rng_state")
	return typeof(rng_state) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(rng_state)) and float(rng_state)==floorf(float(rng_state))

func _encode_worker(state: Dictionary) -> Dictionary:
	if state.is_empty(): return {}
	var result := state.duplicate(true)
	for key in ["position","velocity","destination"]:
		if result.get(key) is Vector3:
			var value: Vector3 = result[key]
			result[key] = [value.x,value.y,value.z]
	return result

func _decode_worker(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	for key in ["position","velocity","destination"]:
		var value: Variant = result.get(key)
		if value is Array and value.size()==3: result[key] = Vector3(value[0],value[1],value[2])
	return result

func _build_launch(_index: int) -> Node3D:
	var root := Node3D.new()
	_box(root,Vector3(0,.34,0),Vector3(4.2,.65,10),"344e59")
	_box(root,Vector3(0,.72,0),Vector3(3.8,.12,9.6),"a39170")
	for x in [-2.0,2.0]: _box(root,Vector3(x,1.02,0),Vector3(.18,.8,10),"d0c8ad")
	_box(root,Vector3(0,1.02,5),Vector3(4.1,.8,.18),"d0c8ad")
	_box(root,Vector3(0,1.60,3.6),Vector3(2.9,1.7,2),"ded5b8")
	_box(root,Vector3(0,1.92,2.57),Vector3(2.5,.7,.04),"365965")
	_box(root,Vector3(0,2.50,3.6),Vector3(3.2,.15,2.3),"eeead8")
	_box(root,Vector3(0,3.25,3.9),Vector3(.09,1.5,.09),"69777a")
	_box(root,Vector3(0,4.0,3.9),Vector3(.7,.08,.1),"e7ded0")
	_build_bow(root)
	for x in [-2.15,2.15]:
		for z in [-3.5,0.0,3.5]: _ellipsoid(root,Vector3(x,.88,z),Vector3(.4,.6,.65),"242c30")
	var cargo := MultiMeshInstance3D.new()
	cargo.name = "Cargo"
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = BoxMesh.new()
	multi.mesh.size = Vector3(.85,.75,.85)
	multi.instance_count = 30
	multi.visible_instance_count = 0
	for n in 30:
		# Whole-number grouping/index; preserve integer truncation and precision.
		@warning_ignore("integer_division")
		multi.set_instance_transform(n,Transform3D(Basis.IDENTITY,Vector3((n%3-1)*.95,1.14+float(n/15)*.78,-3.6+float((n%15)/3)*1.02)))
	cargo.multimesh = multi
	cargo.material_override = _material("ab7c49")
	root.add_child(cargo)
	root.set_meta("cargo",cargo)
	var straps := MultiMeshInstance3D.new()
	straps.name = "CargoStraps"
	var strap_multi := MultiMesh.new()
	strap_multi.transform_format = MultiMesh.TRANSFORM_3D
	strap_multi.mesh = BoxMesh.new()
	strap_multi.mesh.size = Vector3(.09,.78,.89)
	strap_multi.instance_count = 60
	strap_multi.visible_instance_count = 0
	for n in 30:
		# Whole-number grouping/index; preserve integer truncation and precision.
		@warning_ignore("integer_division")
		var center := Vector3((n%3-1)*.95,1.14+float(n/15)*.78,-3.6+float((n%15)/3)*1.02)
		strap_multi.set_instance_transform(n*2,Transform3D(Basis.IDENTITY,center+Vector3(-.3,0,0)))
		strap_multi.set_instance_transform(n*2+1,Transform3D(Basis.IDENTITY,center+Vector3(.3,0,0)))
	straps.multimesh = strap_multi
	straps.material_override = _material("d0a66b")
	root.add_child(straps)
	root.set_meta("cargo_straps",straps)
	return root

func _set_load(visual: Node3D, count: int) -> void:
	var cargo: MultiMeshInstance3D = visual.get_meta("cargo")
	cargo.multimesh.visible_instance_count = clampi(count,0,30)
	var straps: MultiMeshInstance3D = visual.get_meta("cargo_straps")
	straps.multimesh.visible_instance_count = clampi(count*2,0,60)

func _build_stock() -> MultiMeshInstance3D:
	var stock := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = BoxMesh.new()
	multi.mesh.size = Vector3(.85,.75,.85)
	multi.instance_count = 30
	for n in 30:
		# Whole-number grouping/index; preserve integer truncation and precision.
		@warning_ignore("integer_division")
		multi.set_instance_transform(n,Transform3D(Basis.IDENTITY,Vector3((n%5-2)*.94,.39+float(n/15)*.78,-float((n%15)/5)*.94)))
	stock.multimesh = multi
	stock.material_override = _material("ab7c49")
	return stock

func _set_stock(stock: MultiMeshInstance3D, count: int) -> void:
	stock.multimesh.visible_instance_count = clampi(count,0,30)

func _build_bow(parent: Node3D) -> void:
	var ring := [Vector3(-2,.75,-5),Vector3(0,.75,-6.8),Vector3(2,.75,-5)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [ring[0],ring[2],ring[1]]: surface.add_vertex(vertex)
	for index in 3:
		var a: Vector3 = ring[index]
		var b: Vector3 = ring[(index+1)%3]
		var c := b-Vector3(0,.65,0)
		var d := a-Vector3(0,.65,0)
		for vertex in [a,b,c,a,c,d]: surface.add_vertex(vertex)
	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	node.material_override = _material("344e59")
	parent.add_child(node)

func _ellipsoid(parent: Node3D, point: Vector3, size: Vector3, color: String) -> void:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = .5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	node.mesh = sphere
	node.position = point
	node.scale = size
	node.material_override = _material(color)
	parent.add_child(node)

func _box(parent: Node3D, point: Vector3, size: Vector3, color: String) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.material_override = _material(color)
	parent.add_child(node)

func _material(color: String) -> StandardMaterial3D:
	if not materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .82
		materials[color] = material
	return materials[color]
