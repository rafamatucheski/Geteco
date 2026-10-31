extends SceneTree
## Reprodução funcional, não teste de FPS nem aprovação de cruzamentos da cidade inteira.
## Construção real de Vehicle/BiarticulatedBus e corpos de colisão BoxShape3D.
## Quadros de física normais registram/movem os corpos. Só o timestamp registrado da concessão
## é envelhecido de forma sintética; nenhuma implementação de ocupação proposta é usada como oráculo.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const BUS = preload("res://runtime/transit/BiarticulatedBus.gd")
const JUNCTIONS = preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const CENTER := Vector3.ZERO
var checks := 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []
var costs: Dictionary = {}
var world: Node3D
var challenger: CharacterBody3D
var key := Vector3i.ZERO
var output := "user://traffic-junction-ttl.json"

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func frames(count := 3) -> void:
	for index in count: await physics_frame
	await process_frame

func curve() -> Curve3D:
	var result := Curve3D.new()
	result.add_point(Vector3(0, 0, 50))
	result.add_point(CENTER)
	result.add_point(Vector3(0, 0, -50))
	result.set_meta("traffic_open", true)
	return result

func make_car(point: Vector3, archetype := "union_sedan") -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = archetype
	car.position = point
	world.add_child(car)
	return car

func aged(owner_id: int) -> bool:
	var owners: Dictionary = JUNCTIONS.owners.get(key, {})
	var exists := owners.has(owner_id)
	check(exists, "precondition: reservation exists before synthetic expiry")
	if exists: owners[owner_id][1] = Time.get_ticks_msec() - JUNCTIONS.HOLD_LIMIT_MSEC - 1
	return exists

func acquire(owner: Node3D) -> bool:
	JUNCTIONS.release(key, challenger.get_instance_id())
	var granted := JUNCTIONS.request(key, owner.get_instance_id(), Vector3.FORWARD, -2.0, 0.0)
	check(granted, "precondition: committed approach acquires the empty junction")
	return granted

func core_colliders(protected := false) -> Array[int]:
	# Cruzamento físico de ruas definido de forma independente: duas ruas de 8 m de largura em y=0.
	# As fixtures põem um casco completo no centro, claramente fora dele ou 12 m acima.
	# Nenhum SAT, implementação de concessão ou helper proposto do controlador é consultado.
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(14.0, 4.4, 14.0) if protected else Vector3(8.0, 6.0, 8.0)
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.8 if protected else 3.0, 0))
	query.collision_mask = 4
	query.exclude = [challenger.get_rid()]
	var result: Array[int] = []
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query, 16):
		result.append(hit.collider.get_instance_id())
	return result

func ask_crossing(title: String, owner_id: int, expected: bool) -> void:
	JUNCTIONS.release(key, challenger.get_instance_id())
	var colliders := core_colliders()
	var before: Dictionary = JUNCTIONS.owners.get(key, {}).duplicate(true)
	var admitted := JUNCTIONS.request(key, challenger.get_instance_id(), Vector3.RIGHT, 1.0, 0.2)
	check(admitted == expected, title + (": conflicting entry allowed" if expected else ": conflicting entry denied"))
	cases.append({"case": title, "owner_id": str(owner_id), "owner_valid": is_instance_id_valid(owner_id),
		"core_colliders": colliders, "expected_admitted": expected, "admitted": admitted,
		"owners_before": before, "owners_after": JUNCTIONS.owners.get(key, {}).duplicate(true)})
	JUNCTIONS.release(key, challenger.get_instance_id())

func graph() -> Dictionary:
	return {"vertices": [CENTER, Vector3(50,0,0), Vector3(-50,0,0), Vector3(0,0,50), Vector3(0,0,-50)],
		"edges": {0: [{"to":1}, {"to":2}, {"to":3}, {"to":4}]}}

func timing(samples: Array[int]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	for sample in sorted: total += sample
	return {"samples": sorted.size(), "mean_us": float(total)/sorted.size(),
		"p50_us": sorted[floori((sorted.size()-1)*.50)], "p95_us": sorted[floori((sorted.size()-1)*.95)],
		"p99_us": sorted[floori((sorted.size()-1)*.99)], "max_us": sorted[-1]}

func registry_costs(owner: Node3D, title: String) -> void:
	var id := owner.get_instance_id()
	var registry := JUNCTIONS.new()
	acquire(owner)
	for expired in [false, true]:
		for method in ["request", "has_reservation", "occupies"]:
			if not registry.has_method(method): continue
			if method == "occupies" and not expired: continue
			var samples: Array[int] = []
			for index in 520:
				# A preparação do timestamp e a alocação da amostra ficam fora de cada chamada medida.
				var records: Dictionary = JUNCTIONS.owners[key]
				records[id][1] = Time.get_ticks_msec() - (JUNCTIONS.HOLD_LIMIT_MSEC + 1 if expired else 0)
				var started := Time.get_ticks_usec()
				if method == "request": JUNCTIONS.request(key, id, Vector3.FORWARD, -2.0, 0.0)
				else: registry.call(method, key, id)
				var elapsed := Time.get_ticks_usec() - started
				if index >= 20: samples.append(elapsed)
			costs[title + ":" + method + (":expired" if expired else ":valid")] = timing(samples)
	# Restore a fresh lease so timing setup cannot affect following contracts.
	JUNCTIONS.owners[key][id][1] = Time.get_ticks_msec()

func boundary_contracts() -> void:
	var owner = make_car(Vector3(0, .1, 0))
	owner.set_physics_process(false)
	var points: Array[Dictionary] = []
	# Consulta física do volume protegido documentado: +/-7 m na horizontal,
	# espaço da rua de -0.4 a +4 m. Os centros de teste ficam 0.25 m de cada lado do contato,
	# evitando as margens do solver. Estes testes não chamam o helper SAT do candidato.
	for side in [-1.0, 1.0]:
		for inside in [true, false]:
			var margin := -.25 if inside else .25
			points.append({"point": Vector3(side*(7.0+owner.half_width+margin), .1, 0), "inside":inside, "axis":"x"})
			points.append({"point": Vector3(0, .1, side*(7.0+owner.half_length+margin)), "inside":inside, "axis":"z"})
	for inside in [true, false]:
		points.append({"point":Vector3(0, 4.0+(-.25 if inside else .25), 0), "inside":inside, "axis":"upper_y"})
		points.append({"point":Vector3(0, -.4-owner.body_height+(.25 if inside else -.25), 0), "inside":inside, "axis":"lower_y"})
	for item in points:
		owner.place(item.point, 0)
		acquire(owner)
		await frames()
		var physical := core_colliders(true).has(owner.get_instance_id())
		var title := "protected boundary %s %s" % [item.axis, str(item.point)]
		check(physical == bool(item.inside), title + ": independent physical precondition")
		if aged(owner.get_instance_id()): ask_crossing(title, owner.get_instance_id(), not bool(item.inside))
	owner.queue_free()
	await frames()

func reconfiguration_contracts() -> void:
	# Um SubViewport isolado usa um mundo de física genuinamente diferente, não uma
	# flag de visibilidade nem um dicionário fingindo que o colisor sumiu.
	var isolated := SubViewport.new()
	isolated.size = Vector2i(32, 32)
	isolated.world_3d = World3D.new()
	root.add_child(isolated)
	var other := VEHICLE.new()
	other.archetype = "union_sedan"
	isolated.add_child(other)
	other.set_physics_process(false)
	other.place(Vector3(0, .1, 0), 0)
	await frames()
	check(other.get_world_3d() != challenger.get_world_3d(), "isolated actor belongs to a different actual World3D")
	check(not core_colliders().has(other.get_instance_id()), "main world's physical query cannot see isolated actor")
	var query := PhysicsShapeQueryParameters3D.new()
	var volume := BoxShape3D.new()
	volume.size = Vector3(8, 6, 8)
	query.shape = volume
	query.transform.origin = Vector3(0, 3, 0)
	query.collision_mask = 4
	var found := false
	for hit in other.get_world_3d().direct_space_state.intersect_shape(query):
		found = found or hit.collider == other
	check(found, "isolated world's query confirms its collider is still present")
	acquire(other)
	JUNCTIONS.configure(graph())
	ask_crossing("rebuild cannot import collision from another World3D", other.get_instance_id(), true)
	isolated.queue_free()
	await frames()

	var owner = make_car(Vector3(0, .1, 0))
	owner.set_physics_process(false)
	await frames()
	JUNCTIONS.axes[key] = Vector2.DOWN
	acquire(owner)
	JUNCTIONS.configure(graph())
	check(JUNCTIONS.owners.get(key, {}).has(owner.get_instance_id()), "same-world rebuild keeps valid reservation")
	ask_crossing("rebuild maps old axis to the same physical movement", owner.get_instance_id(), false)
	var same_axis := JUNCTIONS.request(key, challenger.get_instance_id(), Vector3.FORWARD, 1.0, .2)
	check(same_axis, "remapped axis still admits the same movement direction")
	JUNCTIONS.release(key, challenger.get_instance_id())
	var elevated := graph()
	for i in elevated.vertices.size(): elevated.vertices[i] += Vector3.UP * 12.0
	JUNCTIONS.configure(elevated)
	check(not JUNCTIONS.owners.get(key, {}).has(owner.get_instance_id()), "changed graph elevation cannot inherit lower-road reservation")
	JUNCTIONS.configure(null)
	check(JUNCTIONS.owners.is_empty() and JUNCTIONS.junctions.is_empty() and JUNCTIONS.axes.is_empty(), "configure(null) still clears all reservations and graph associations")
	owner.queue_free()
	await frames()
	JUNCTIONS.configure(graph())

func orphan_and_tail_contracts() -> void:
	var car = make_car(Vector3(0, .1, 0))
	car.route = curve()
	car.traffic = true
	await frames(8)
	check(car._held_junction == key, "orphan test starts with an actual locally acquired token")
	# A posse no registro pode sumir independente do token local de um motorista.
	# Antes da linha de parada, um token faltando precisa obedecer de novo à regra PARE atual.
	car.place(Vector3(0, .1, 20), 0)
	JUNCTIONS.release(key, car.get_instance_id())
	await frames(8)
	check(not core_colliders().has(car.get_instance_id()), "orphan owner is still before the physical crossing")
	check(car.junction_wait and car.junction_gap > 0, "orphan token before the line cannot bypass the current stop rule")
	check(car._held_junction == null, "orphan token is cleared when registry no longer owns it")
	# Já um veículo comprometido continua liberando o cruzamento e
	# republica a ocupação real dele, em vez de parar no meio.
	car.place(Vector3(0, .1, 0), 0)
	await frames(8)
	check(car._held_junction == key, "owner inside the crossing has acquired a token")
	JUNCTIONS.release(key, car.get_instance_id())
	await frames(8)
	check(core_colliders().has(car.get_instance_id()), "orphan occupancy query sees the actual body")
	check(JUNCTIONS.owners.get(key, {}).has(car.get_instance_id()), "committed orphan republishes registry ownership")
	ask_crossing("registry recovered for committed orphan", car.get_instance_id(), false)
	car.queue_free()
	await frames()

	# Veículo real do catálogo: um ônibus urbano de 9.78 m usando a lógica comum de Vehicle.
	# O centro dele passou do EXIT, enquanto a traseira física ainda atravessa a rua.
	var long_car = make_car(Vector3(0, .1, 0), "route_city")
	long_car.route = curve()
	long_car.traffic = true
	await frames(8)
	check(long_car._held_junction == key, "long ordinary Vehicle acquired a local token")
	long_car.place(Vector3(0, .1, -7.4), 0)
	await frames(8)
	check(long_car.global_position.z < -JUNCTIONS.EXIT, "long Vehicle centre has already passed EXIT")
	check(core_colliders().has(long_car.get_instance_id()), "independent query still sees the long Vehicle rear inside")
	ask_crossing("normal departure retains the long Vehicle rear", long_car.get_instance_id(), false)
	long_car.place(Vector3(0, .1, -20), 0)
	await frames(8)
	check(not core_colliders().has(long_car.get_instance_id()), "entire long Vehicle has physically cleared")
	check(not JUNCTIONS.owners.get(key, {}).has(long_car.get_instance_id()), "normal departure releases without waiting for TTL")
	ask_crossing("normal departure releases after the rear clears", long_car.get_instance_id(), true)
	long_car.queue_free()
	await frames()

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--junction-ttl-output="): output = argument.trim_prefix("--junction-ttl-output=")
	if "--no-save" not in OS.get_cmdline_user_args() or not ClassDB.class_exists(&"CSharpScript"):
		push_error("Requires compiled Godot .NET and --no-save")
		quit(2)
		return
	create_timer(90.0).timeout.connect(func(): push_error("Junction TTL fixture timeout"); quit(3))
	JUNCTIONS.configure(graph())
	key = JUNCTIONS.key_of(CENTER)
	world = Node3D.new()
	world.name = "JunctionLeaseFixture"
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(160, 1, 160)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	challenger = make_car(Vector3(-13, 0.1, 0))
	challenger.rotation.y = -PI * 0.5
	var owner = make_car(Vector3(0, 0.1, 0))
	owner.route = curve()
	owner.traffic = true
	await frames(8)
	check(owner.shape.shape is BoxShape3D and challenger.shape.shape is BoxShape3D, "real Vehicle hulls are BoxShape3D")
	check(owner._held_junction == key, "normal Vehicle physics acquired its local junction token")
	check(core_colliders().has(owner.get_instance_id()), "physical query sees the active owner's hull in the road crossing")
	if aged(owner.get_instance_id()): ask_crossing("expired lease, active owner in centre", owner.get_instance_id(), false)

	# Um heartbeat faltando não pode transformar um colisor parado real em espaço livre.
	owner.set_physics_process(false)
	owner.place(Vector3(0, 0.1, 0), 0)
	acquire(owner)
	await frames()
	check(core_colliders().has(owner.get_instance_id()), "paused owner remains physically in the crossing")
	if aged(owner.get_instance_id()): ask_crossing("expired lease, paused owner in centre", owner.get_instance_id(), false)
	owner.visible = false
	acquire(owner)
	await frames()
	check(core_colliders().has(owner.get_instance_id()), "invisible body still physically collides")
	if aged(owner.get_instance_id()): ask_crossing("invisible owner with enabled collision", owner.get_instance_id(), false)
	owner.visible = true
	owner.collision_mask = 0
	acquire(owner)
	await frames()
	check(core_colliders().has(owner.get_instance_id()), "owner mask zero remains detectable by traffic layer")
	if aged(owner.get_instance_id()): ask_crossing("owner mask zero still blocks other vehicles", owner.get_instance_id(), false)
	owner.collision_mask = 7
	owner.collision_layer = 0
	acquire(owner)
	await frames()
	check(not core_colliders().has(owner.get_instance_id()), "layer zero removes owner from traffic collision")
	if aged(owner.get_instance_id()): ask_crossing("collision layer removed", owner.get_instance_id(), true)
	owner.collision_layer = 4
	owner.shape.set_deferred("disabled", true)
	acquire(owner)
	await frames()
	check(not core_colliders().has(owner.get_instance_id()), "disabled CollisionShape3D is absent from query")
	if aged(owner.get_instance_id()): ask_crossing("collision shape disabled", owner.get_instance_id(), true)
	owner.shape.set_deferred("disabled", false)
	await frames()
	var shape_owner: int = owner.get_shape_owners()[0]
	owner.call_deferred("shape_owner_set_disabled", shape_owner, true)
	acquire(owner)
	await frames()
	check(not core_colliders().has(owner.get_instance_id()), "disabled shape owner is absent even when the node flag is enabled")
	if aged(owner.get_instance_id()): ask_crossing("physics shape owner disabled", owner.get_instance_id(), true)
	owner.call_deferred("shape_owner_set_disabled", shape_owner, false)
	await frames()
	owner.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	owner.process_mode = Node.PROCESS_MODE_DISABLED
	acquire(owner)
	await frames()
	check(core_colliders().has(owner.get_instance_id()), "disabled processing with KEEP_ACTIVE still has collision")
	if aged(owner.get_instance_id()): ask_crossing("disabled processing keeps active collider", owner.get_instance_id(), false)
	owner.disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE
	acquire(owner)
	await frames()
	check(not core_colliders().has(owner.get_instance_id()), "DISABLE_MODE_REMOVE actually removes physics body")
	if aged(owner.get_instance_id()): ask_crossing("disabled processing removes collider only with REMOVE", owner.get_instance_id(), true)
	owner.process_mode = Node.PROCESS_MODE_INHERIT
	await frames()
	owner.health = 0.0
	owner.traffic = false
	acquire(owner)
	await frames()
	check(core_colliders().has(owner.get_instance_id()), "wreck with collision enabled remains physically in the crossing")
	if aged(owner.get_instance_id()): ask_crossing("expired lease, wreck in centre", owner.get_instance_id(), false)
	registry_costs(owner, "single_vehicle_centre")
	acquire(owner)
	JUNCTIONS.configure(graph())
	check(core_colliders().has(owner.get_instance_id()), "graph rebuild leaves the wreck collision present")
	ask_crossing("graph rebuild preserves surviving crossing occupancy", owner.get_instance_id(), false)

	# Same still-valid object, but no remaining physical obstruction.
	owner.place(Vector3(25, 0.1, -25), 0)
	acquire(owner)
	await frames()
	check(not core_colliders().has(owner.get_instance_id()), "moved owner is physically outside the crossing")
	if aged(owner.get_instance_id()): ask_crossing("expired abandoned lease, owner away", owner.get_instance_id(), true)
	owner.place(Vector3(0, 12.0, 0), 0)
	acquire(owner)
	await frames()
	check(not core_colliders().has(owner.get_instance_id()), "owner at another elevation does not intersect the road crossing")
	if aged(owner.get_instance_id()): ask_crossing("expired lease, same XZ but separate elevation", owner.get_instance_id(), true)
	world.remove_child(owner)
	acquire(owner)
	await frames()
	check(is_instance_valid(owner) and not owner.is_inside_tree(), "detached owner remains alive outside the scene tree")
	check(not core_colliders().has(owner.get_instance_id()), "detached body's collision is absent")
	if aged(owner.get_instance_id()): ask_crossing("live owner outside the scene tree", owner.get_instance_id(), true)
	world.add_child(owner)
	owner.place(Vector3(0, 0.1, 0), 0)
	acquire(owner)
	var freed_id := owner.get_instance_id()
	owner.queue_free()
	await frames()
	check(not is_instance_id_valid(freed_id), "owner was actually freed through the scene tree")
	ask_crossing("freed owner releases reservation", freed_id, true)

	# Actual 22.7 m bus: tractor AND middle section clear, rear section still inside.
	var bus := BUS.new()
	world.add_child(bus)
	bus.set_route(curve(), 70.0)
	bus.set_active(true)
	acquire(bus)
	bus.junction_tokens[key] = true
	await frames()
	check(bus.sections.size() == 3 and bus.hulls.size() == 3, "actual biarticulated bus has three collision hulls")
	var bus_hits := core_colliders()
	check(not bus_hits.has(bus.get_instance_id()) and not bus_hits.has(bus.sections[1].get_instance_id()), "tractor and middle section have physically cleared the crossing")
	check(bus_hits.has(bus.sections[2].get_instance_id()), "last bus section still physically intersects the crossing")
	if aged(bus.get_instance_id()): ask_crossing("expired lease, only rear bus section occupies crossing", bus.get_instance_id(), false)
	registry_costs(bus, "bus_rear_only")
	JUNCTIONS.release(key, bus.get_instance_id())
	# Public controller query, not a manually invoked engine callback.
	bus.signal_gap()
	check(JUNCTIONS.owners.get(key, {}).has(bus.get_instance_id()), "bus tail with orphan token republishes registry occupancy")
	ask_crossing("bus rear protected after orphan token recovery", bus.get_instance_id(), false)
	# Move os corpos sem set_route(), que liberaria o token de propósito.
	for section in bus.sections: section.global_position += Vector3(0, 0, -30)
	acquire(bus)
	await frames()
	bus_hits = core_colliders()
	var all_clear := true
	for section in bus.sections: all_clear = all_clear and not bus_hits.has(section.get_instance_id())
	check(all_clear, "all bus collision sections have physically cleared")
	if aged(bus.get_instance_id()): ask_crossing("expired abandoned bus lease, all sections clear", bus.get_instance_id(), true)
	bus.queue_free()
	await frames()
	await orphan_and_tail_contracts()
	await boundary_contracts()
	await reconfiguration_contracts()
	world.queue_free()
	await process_frame
	JUNCTIONS.configure(null)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Could not write TTL fixture evidence")
		quit(4)
		return
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": cases, "direct_api_costs": costs,
		"scope": "Functional registry safety with actual Vehicle/biarticulated collision hulls in a synthetic flat road crossing. TTL aged directly; normal engine frames, no adopted callbacks. Not FPS, all road geometry, signal turns or every junction."}, "\t"))
	print("TRAFFIC_JUNCTION_TTL checks=", checks, " failures=", failures.size(), " output=", output)
	quit(0 if failures.is_empty() else 1)
