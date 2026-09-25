extends Node3D
signal work_truck_removed(index: int)
## Three V1 quay cranes transfer cargo between Santa Mare and the terminal.
## Cargo remains attached to the gantry cycle and blocks its landing pad only
## while resting on the ground, matching the original 48-second operation.

const LAYOUT := preload("res://world/regions/OriginalSouthPortLayout.gd")
const PORT_SHIP_PAINT := preload("res://world/regions/PortShipMaterials3D.gd")
const SCALE := 1.0 / 16.0
const ACTIVE_DISTANCE := 150.0
const CYCLE_SECONDS := 48.0
const START_CLOCKS := [0.0, 16.0, 32.0]
const CRANE_WIDTH := 12.0
const CRANE_DEPTH := 25.625
const FORKLIFT_POINTS := [Vector2(4400,3440), Vector2(5000,3440)]
const CARGO_TRUCKS := ["31577a", "9e563b", "607b58"]
const TRUCK_START_GAP := 210.0 * SCALE

var session
var cranes: Array[Dictionary] = []
var work_trucks: Array[Dictionary] = []
var forklifts: Array[CharacterBody3D] = []
var forklift_crates: Array[Dictionary] = []
var crew_crates: Array[Dictionary] = []
var truck_route: Curve3D
var active := false
var scan_clock := 0.0
var unloaded_containers := 0
var loaded_containers := 0
var _work_shift_open := false
var _vehicle_spawn_cursor := 0
var freight

func configure(owner_session) -> void:
	session = owner_session
	name = "V1PortCargoOperations"
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _ready() -> void:
	for index in LAYOUT.CRANES.size(): _build_crane(index)
	_build_truck_route()
	for _index in FORKLIFT_POINTS.size(): forklifts.append(null)
	_build_forklift_crates()
	refresh_context()
	set_process(true)

func _build_crane(index: int) -> void:
	var authored: Vector2 = LAYOUT.CRANES[index]
	var origin_2d := authored + Vector2(85.0, -155.0)
	var origin := Vector3(origin_2d.x * SCALE, 0.0, origin_2d.y * SCALE)
	var gantry_base := Vector3(-CRANE_WIDTH * .4, 0.0, CRANE_DEPTH * .42)
	var quay_local := gantry_base + Vector3(0.0, 7.0, 4.0)
	var ship_local := Vector3(CRANE_WIDTH * .48, 8.0, -CRANE_DEPTH * .42)
	var quay := origin + Vector3(quay_local.x * 1.25, 0.0, quay_local.z)
	var ship := origin + Vector3(ship_local.x * 1.25, 0.0, ship_local.z)

	var cargo := Node3D.new()
	cargo.name = "MovingTransferCargo%d" % index
	var container := MeshInstance3D.new()
	var container_mesh := BoxMesh.new()
	container_mesh.size = Vector3(5.85, 2.45, 2.45)
	container.mesh = container_mesh
	container.position.y = 1.225
	var container_material := StandardMaterial3D.new()
	container_material.albedo_color = [Color("ae5946"),Color("447f91"),Color("c09b52")][index]
	container_material.roughness = .82
	container.material_override = container_material
	cargo.add_child(container)
	add_child(cargo)
	cargo.hide()
	var trolley := MeshInstance3D.new()
	trolley.name = "CraneTrolley%d" % index
	var trolley_shape := BoxMesh.new()
	trolley_shape.size = Vector3(1.0,.38,.8)
	trolley.mesh = trolley_shape
	trolley.material_override = PORT_SHIP_PAINT.material("crane")
	trolley.hide()
	add_child(trolley)
	var cable := MeshInstance3D.new()
	cable.name = "CraneHoistCable%d" % index
	var cable_shape := BoxMesh.new()
	cable_shape.size = Vector3(.055,1.0,.055)
	cable.mesh = cable_shape
	var cable_material := StandardMaterial3D.new()
	cable_material.albedo_color = Color("35454a")
	cable_material.roughness = .72
	cable.material_override = cable_material
	cable.hide()
	add_child(cable)

	var body := StaticBody3D.new()
	body.name = "TransferCargoCollision%d" % index
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.85, 2.55, 2.45)
	collision.shape = shape
	collision.position.y = 1.275
	collision.disabled = true
	body.add_child(collision)
	add_child(body)
	cranes.append({
		"clock":START_CLOCKS[index],
		"ship":ship,
		"quay":quay,
		"visual":cargo,
		"trolley":trolley,
		"cable":cable,
		"body":body,
		"collision":collision,
	})

func refresh_context() -> void:
	if session == null or session.state == null or not is_instance_valid(session.world.player): return
	var focus: Vector3 = session.world.driving.car.global_position if session.world.driving.occupied else session.world.player.global_position
	var center := Vector3(4885.0 * SCALE, 0.0, 3400.0 * SCALE)
	var should_activate: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty() and focus.distance_to(center) <= ACTIVE_DISTANCE
	if should_activate == active: return
	active = should_activate
	for index in cranes.size():
		var crane: Dictionary = cranes[index]
		if not work_trucks[index].loaded: (crane.visual as Node3D).visible = active
		(crane.trolley as MeshInstance3D).visible = active and not work_trucks[index].loaded
		(crane.cable as MeshInstance3D).visible = active and not work_trucks[index].loaded
		(crane.collision as CollisionShape3D).set_deferred("disabled", not active or work_trucks[index].loaded)
	for crate in forklift_crates:
		(crate.visual as Node3D).visible = active
		(crate.collision as CollisionShape3D).set_deferred("disabled", not active)
	for crate in crew_crates:
		(crate.visual as Node3D).visible = active
		(crate.collision as CollisionShape3D).set_deferred("disabled", not active)
	_sync_work_vehicle_visibility()
	if active:
		for index in cranes.size(): _sync_crane(index)

func _process(delta: float) -> void:
	if session == null or not is_instance_valid(session.world.player): return
	scan_clock -= delta
	if scan_clock <= 0.0:
		scan_clock = .25
		refresh_context()
		if active: _ensure_work_vehicles()
	if not active or not is_finite(delta) or delta <= 0.0: return
	var shift_open := _shift_open()
	if shift_open != _work_shift_open:
		_work_shift_open = shift_open
		_sync_work_vehicle_visibility()
	if not shift_open: return
	for index in work_trucks.size(): _tick_truck(index, delta)
	for index in cranes.size(): _tick_crane(index, delta)

func _shift_open() -> bool:
	return session.weather != null and float(session.weather.time_of_day) * 24.0 >= 6.0 and float(session.weather.time_of_day) * 24.0 < 18.0

func _build_truck_route() -> void:
	truck_route = Curve3D.new()
	truck_route.bake_interval = .35
	var y: float = cranes[0].quay.z
	var source_points := [
		Vector2(3900,y / SCALE), Vector2(5630,y / SCALE), Vector2(5720,y / SCALE + 90),
		Vector2(5720,5500), Vector2(5630,5620), Vector2(3870,5620),
		Vector2(3780,5500), Vector2(3780,3500), Vector2(3900,y / SCALE),
	]
	for point in source_points: truck_route.add_point(Vector3(point.x*SCALE,0.0,point.y*SCALE))
	_build_route_support(source_points)
	truck_route.set_meta("traffic_open",false)
	truck_route.set_meta("port_work_route",true)
	for index in cranes.size():
		var stop: Vector3 = cranes[index].quay + Vector3(74.0 / 4.46 * SCALE, 0.0, 0.0)
		var depot := Vector3(float(5400-index*350)*SCALE,0,5650*SCALE)
		work_trucks.append({"truck":null,"phase":"approach","bay":index,"stop":stop,"stop_offset":truck_route.get_closest_offset(stop),"depot_offset":truck_route.get_closest_offset(depot),"loaded":false,"remaining":0.0,"deliveries":0})

func _build_route_support(points: Array) -> void:
	# The production region streams around the player. Freight still needs a
	# physical floor when its circuit reaches warehouses two chunks away.
	for index in points.size()-1:
		var a: Vector2 = points[index]*SCALE
		var b: Vector2 = points[index+1]*SCALE
		var delta := b-a
		var body := StaticBody3D.new()
		body.name = "PortFreightRouteFloor%d" % index
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3((a.x+b.x)*.5,-.13,(a.y+b.y)*.5)
		body.rotation.y = atan2(delta.x,delta.y)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(5.4,.26,delta.length()+2.0)
		collider.shape = shape
		body.add_child(collider)
		add_child(body)

func _build_forklift_crates() -> void:
	var colors := [Color("9d7951"),Color("b28c5d"),Color("71604d")]
	for forklift_index in FORKLIFT_POINTS.size():
		for crate_index in 3:
			var point: Vector2 = Vector2(4480 + forklift_index * 600 + crate_index * 36,3450)
			var root := Node3D.new()
			root.name = "PortForkliftCrate%d_%d" % [forklift_index,crate_index]
			root.position = Vector3(point.x*SCALE,0.0,point.y*SCALE)
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.0,.72,1.0)
			mesh.mesh = box
			mesh.position.y = .36
			var material := StandardMaterial3D.new()
			material.albedo_color = colors[crate_index]
			material.roughness = .9
			mesh.material_override = material
			root.add_child(mesh)
			root.hide()
			add_child(root)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = box.size
			collision.shape = shape
			collision.position.y = .36
			collision.disabled = true
			body.add_child(collision)
			body.position = root.position
			add_child(body)
			forklift_crates.append({"visual":root,"body":body,"collision":collision})
	# Three small pickup stocks sit beside the authored worker circuits. Their
	# bodies stay out of each route, while the visible stacks explain where the
	# carried crates come from.
	for index in 3:
		var source_x: float = [3900.0,4430.0,5020.0][index]
		var point := Vector3((source_x+34.0)*SCALE,0,3410.0*SCALE)
		var root := Node3D.new()
		root.name = "PortCrewPickupStock%d" % index
		root.position = point
		var crate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.05,.72,.86)
		crate.mesh = box
		crate.position.y = .36
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("a17c51")
		wood.roughness = .88
		crate.material_override = wood
		root.add_child(crate)
		var slat_material := StandardMaterial3D.new()
		slat_material.albedo_color = Color("c6a477")
		slat_material.roughness = .9
		for side in [-.4,.4]:
			var slat := MeshInstance3D.new()
			var slat_box := BoxMesh.new()
			slat_box.size = Vector3(.075,.76,.9)
			slat.mesh = slat_box
			slat.position = Vector3(side,.36,0)
			slat.material_override = slat_material
			root.add_child(slat)
		root.hide()
		add_child(root)
		var body := StaticBody3D.new()
		body.name = "PortCrewPickupStockSolid%d" % index
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = point
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		collision.shape = shape
		collision.position.y = .36
		collision.disabled = true
		body.add_child(collision)
		add_child(body)
		crew_crates.append({"visual":root,"body":body,"collision":collision})

func _ensure_work_vehicles() -> void:
	# Mount one detailed vehicle per scan so first arrival cannot cause a single
	# large model-build spike. Failed clearance probes are retried on later scans.
	for step in 5:
		var slot := posmod(_vehicle_spawn_cursor + step, 5)
		if slot < FORKLIFT_POINTS.size():
			if is_instance_valid(forklifts[slot]): continue
			_spawn_forklift(slot)
			_vehicle_spawn_cursor = posmod(slot + 1, 5)
			return
		var index := slot - FORKLIFT_POINTS.size()
		var state: Dictionary = work_trucks[index]
		if is_instance_valid(state.truck) or state.phase in ["interrupted", "freight", "freight_pending"]: continue
		_spawn_work_truck(index)
		_vehicle_spawn_cursor = posmod(slot + 1, 5)
		return

func _spawn_forklift(index: int) -> void:
	var point: Vector2 = FORKLIFT_POINTS[index]
	var position := Vector3(point.x*SCALE,.12,point.y*SCALE)
	var vehicle = session.controller.spawn_vehicle("port_forklift",position,PI*.5)
	if not is_instance_valid(vehicle): return
	vehicle.vehicle_id = "south_port_forklift_%02d" % index
	vehicle.set_meta("port_work_vehicle",true)
	vehicle.set_meta("region_id","harbor")
	vehicle.traffic = false
	vehicle.brake_input = true
	vehicle.visible = active
	vehicle.set_physics_process(active)
	forklifts[index] = vehicle

func _spawn_work_truck(index: int) -> void:
	var route_length := truck_route.get_baked_length()
	if route_length < 30.0: return
	var offset := fposmod(float(work_trucks[index].stop_offset) - TRUCK_START_GAP, route_length)
	var point := truck_route.sample_baked(offset, true)
	var ahead := truck_route.sample_baked(fposmod(offset + .5,route_length),true) - truck_route.sample_baked(fposmod(offset - .5,route_length),true)
	var vehicle = session.controller.spawn_vehicle("cargo_flatbed_truck",point + Vector3.UP*.12,atan2(-ahead.x,-ahead.z))
	if not is_instance_valid(vehicle): return
	vehicle.vehicle_id = "south_port_cargo_truck_%02d" % index
	vehicle.set_meta("port_work_vehicle",true)
	vehicle.set_meta("region_id","harbor")
	vehicle.paint_color = Color(CARGO_TRUCKS[index])
	vehicle.route = truck_route
	vehicle.route_distance = offset
	vehicle.traffic = active and _work_shift_open
	vehicle.brake_input = not vehicle.traffic
	vehicle.visible = active
	vehicle.set_physics_process(active and _work_shift_open)
	work_trucks[index].truck = vehicle
	var state: Dictionary = work_trucks[index]
	_watch_work_truck(index, vehicle)

func _watch_work_truck(index: int, vehicle: CharacterBody3D) -> void:
	if vehicle.get_meta("port_cargo_watcher", 0) == get_instance_id(): return
	vehicle.set_meta("port_cargo_watcher", get_instance_id())
	if not vehicle.destroyed.is_connected(_work_truck_destroyed.bind(index)):
		vehicle.destroyed.connect(_work_truck_destroyed.bind(index))
	vehicle.tree_exiting.connect(_work_truck_exiting.bind(index, weakref(vehicle)))

func _work_truck_exiting(index: int, reference: WeakRef) -> void:
	var vehicle = reference.get_ref()
	# Reparenting and world teardown are not a destroyed shipment.
	if not is_inside_tree() or is_queued_for_deletion() or session.world.is_queued_for_deletion(): return
	if is_instance_valid(vehicle) and vehicle.is_queued_for_deletion(): _work_truck_destroyed(index)

func _work_truck_destroyed(index: int) -> void:
	work_trucks[index].phase = "interrupted"
	work_truck_removed.emit(index)

func _sync_work_vehicle_visibility() -> void:
	for vehicle in forklifts:
		if not is_instance_valid(vehicle): continue
		var player_driving: bool = session.world.driving.occupied and session.world.driving.car == vehicle
		if player_driving: continue
		vehicle.visible = active
		vehicle.set_physics_process(active)
	for state in work_trucks:
		var vehicle = state.truck
		if not is_instance_valid(vehicle): continue
		if state.phase in ["freight", "freight_pending", "interrupted"]: continue
		var player_driving: bool = session.world.driving.occupied and session.world.driving.car == vehicle
		if player_driving: continue
		vehicle.visible = active
		var should_run := active and _work_shift_open
		vehicle.set_physics_process(should_run and not vehicle.has_meta("awaiting_ground"))
		if state.phase in ["approach","departed","returning"]:
			vehicle.traffic = should_run
			vehicle.brake_input = not should_run

func _tick_truck(index: int, delta: float) -> void:
	var state: Dictionary = work_trucks[index]
	var vehicle = state.truck
	if not is_instance_valid(vehicle): return
	if state.phase in ["freight", "freight_pending"]: return
	if session.world.driving.occupied and session.world.driving.car == vehicle or vehicle.controlled:
		state.phase = "interrupted"
		return
	match str(state.phase):
		"approach":
			var remaining := fposmod(float(state.stop_offset) - float(vehicle.route_distance), truck_route.get_baked_length())
			if remaining < 1.5:
				state.phase = "waiting"
				vehicle.traffic = false
				vehicle.brake_input = true
		"waiting":
			var crane_phase := fposmod(float(cranes[index].clock),CYCLE_SECONDS)
			if absf(vehicle.speed) < .2 and (crane_phase < 4.0 or (crane_phase >= 16.0 and crane_phase <= 20.5)):
				state.phase = "loading"
				if crane_phase < 4.0: cranes[index].clock = floor(float(cranes[index].clock)/CYCLE_SECONDS)*CYCLE_SECONDS
		"securing":
			state.remaining = maxf(0.0,float(state.remaining)-delta)
			if state.remaining <= 0.0:
				state.phase = "departed"
				vehicle.traffic = true
				vehicle.brake_input = false
		"departed":
			var depot_remaining := fposmod(float(state.depot_offset)-float(vehicle.route_distance),truck_route.get_baked_length())
			if depot_remaining < 1.5:
				state.phase = "delivering"
				state.remaining = 3.0
				vehicle.traffic = false
				vehicle.brake_input = true
		"delivering":
			if absf(vehicle.speed) > .25: return
			state.remaining = maxf(0.0,float(state.remaining)-delta)
			if state.remaining <= 0.0:
				_reset_truck_load(index)
				state.phase = "approach"
				state.deliveries = int(state.deliveries)+1
				vehicle.traffic = true
				vehicle.brake_input = false

func _truck_mount_position(index: int) -> Vector3:
	var state: Dictionary = work_trucks[index]
	var vehicle = state.truck
	if not is_instance_valid(vehicle): return cranes[index].quay
	return vehicle.global_position + vehicle.global_basis * Vector3(0.0,0.0,vehicle.half_length*.16) + Vector3.UP*1.25

func _finish_truck_load(index: int) -> void:
	var state: Dictionary = work_trucks[index]
	var vehicle = state.truck
	if not is_instance_valid(vehicle):
		state.phase = "interrupted"
		return
	state.loaded = true
	state.remaining = 30.0 if is_instance_valid(freight) and freight.bay_available(index) else 3.5
	state.phase = "securing"
	var visual: Node3D = cranes[index].visual
	visual.reparent(vehicle,true)
	visual.position = Vector3(0.0,1.15,vehicle.half_length*.16)
	visual.rotation.y = PI*.5
	visual.show()
	vehicle.set_meta("port_container_loaded",true)
	(cranes[index].collision as CollisionShape3D).set_deferred("disabled",true)

func _reset_truck_load(index: int) -> void:
	var state: Dictionary = work_trucks[index]
	var visual := cranes[index].visual as Node3D
	if is_instance_valid(visual):
		visual.reparent(self,true)
		visual.visible = active
	state.loaded = false
	cranes[index].clock = 0.0
	(cranes[index].trolley as MeshInstance3D).visible = active
	(cranes[index].cable as MeshInstance3D).visible = active
	_sync_crane(index)
	if is_instance_valid(state.truck): state.truck.remove_meta("port_container_loaded")

func _tick_crane(index: int, delta: float) -> void:
	var crane: Dictionary = cranes[index]
	if not is_instance_valid(crane.visual): return
	var before := float(crane.clock)
	var after := before + delta
	var phase := fposmod(after, CYCLE_SECONDS)
	var truck_state: Dictionary = work_trucks[index]
	if truck_state.loaded:
		crane.clock = minf(after, ceil(before / CYCLE_SECONDS) * CYCLE_SECONDS)
		return
	if truck_state.phase in ["approach", "waiting"] and fposmod(before, CYCLE_SECONDS) < 4.0:
		crane.clock = minf(after, floor(before / CYCLE_SECONDS) * CYCLE_SECONDS + 3.9)
		_sync_crane(index)
		return
	var landing := (phase >= 16.0 and phase <= 20.5) or (phase >= 40.0 and phase <= 44.5)
	if landing:
		var destination: Vector3 = _truck_mount_position(index) if truck_state.phase == "loading" else (crane.quay if phase < 28.0 else crane.ship)
		var excluded: Array[RID] = []
		if truck_state.phase == "loading" and is_instance_valid(truck_state.truck): excluded.append(truck_state.truck.get_rid())
		if _cargo_bay_occupied(destination, excluded): return
	unloaded_containers += int(floor((after - 20.0) / CYCLE_SECONDS) - floor((before - 20.0) / CYCLE_SECONDS))
	loaded_containers += int(floor((after - 44.0) / CYCLE_SECONDS) - floor((before - 44.0) / CYCLE_SECONDS))
	crane.clock = after
	if truck_state.phase == "loading" and floor((after - 20.0) / CYCLE_SECONDS) > floor((before - 20.0) / CYCLE_SECONDS):
		_finish_truck_load(index)
	_sync_crane(index)

func cargo_pose(index: int, time: float) -> Dictionary:
	var phase := fposmod(time, CYCLE_SECONDS)
	var along := 0.0
	var lift := 0.0
	if phase >= 4.0 and phase < 8.0: lift = (phase - 4.0) / 4.0
	elif phase >= 8.0 and phase < 16.0:
		along = smoothstep(8.0, 16.0, phase)
		lift = 1.0
	elif phase >= 16.0 and phase < 20.0:
		along = 1.0
		lift = (20.0 - phase) / 4.0
	elif phase >= 20.0 and phase < 28.0: along = 1.0
	elif phase >= 28.0 and phase < 32.0:
		along = 1.0
		lift = (phase - 28.0) / 4.0
	elif phase >= 32.0 and phase < 40.0:
		along = 1.0 - smoothstep(32.0, 40.0, phase)
		lift = 1.0
	elif phase >= 40.0 and phase < 44.0: lift = (44.0 - phase) / 4.0
	var crane: Dictionary = cranes[index]
	var truck_state: Dictionary = work_trucks[index] if index < work_trucks.size() else {}
	var destination: Vector3 = _truck_mount_position(index) if truck_state.get("phase","") == "loading" and is_instance_valid(truck_state.get("truck")) else crane.quay
	var ground: Vector3 = (crane.ship as Vector3).lerp(destination, along)
	return {"ground":ground, "lift":lift * 70.0 * SCALE, "along":along}

func _sync_crane(index: int) -> void:
	var crane: Dictionary = cranes[index]
	if not is_instance_valid(crane.visual):
		(crane.collision as CollisionShape3D).set_deferred("disabled", true)
		return
	var truck_state: Dictionary = work_trucks[index]
	if truck_state.loaded:
		(crane.collision as CollisionShape3D).set_deferred("disabled", true)
		(crane.trolley as MeshInstance3D).hide()
		(crane.cable as MeshInstance3D).hide()
		return
	var pose := cargo_pose(index, float(crane.clock))
	var visual := crane.visual as Node3D
	visual.global_position = pose.ground + Vector3.UP * pose.lift
	var ground: Vector3 = pose.ground
	var upper_y := lerpf(8.0,7.0,float(pose.along))
	var cargo_top := float(pose.lift)+2.45
	var cable_length := maxf(.15,upper_y-cargo_top)
	(crane.trolley as MeshInstance3D).global_position = ground+Vector3.UP*upper_y
	var cable := crane.cable as MeshInstance3D
	cable.global_position = ground+Vector3.UP*(cargo_top+cable_length*.5)
	cable.scale.y = cable_length
	var collision := crane.collision as CollisionShape3D
	var body := crane.body as StaticBody3D
	body.global_position = pose.ground
	collision.set_deferred("disabled", not active or float(pose.lift) > .01)

func _cargo_bay_occupied(point: Vector3, excluded: Array[RID] = []) -> bool:
	if not is_inside_tree(): return false
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.5, 2.3, 2.35)
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 1.2)
	query.collision_mask = 6
	query.exclude = excluded
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var collider: Variant = hit.get("collider")
		if collider is CharacterBody3D: return true
	return false
