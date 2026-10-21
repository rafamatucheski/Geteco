extends Node
## Owns only the mine's initial equipment. Once driven, fleet/save owns vehicles.
const FLEET := preload("res://gameplay/mining/MiningFleet.gd")
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const ORIGIN := LAYOUT.CENTER
const VEHICLE_IDS := ["mineradora_backhoe","mineradora_tractor","mineradora_haul","mineradora_haul_pit","mineradora_escape","mineradora_employee_1","mineradora_employee_2","mineradora_employee_3","mineradora_employee_4"]
const ARCHETYPES := ["mining_backhoe","mining_tractor","mining_haul_truck","mining_haul_truck","desert_bison","desert_faisca","ranch_single","desert_siroco","station_wagon"]
var session: Node
var world: Node3D
var _clock := 0.0
var _spawned := false
var rocks: Array[RigidBody3D] = []
var _records: Dictionary = {}

func configure(owner_session: Node) -> void:
	session = owner_session
	world = session.world
	var saved: Variant = session.state.world_state.get("mining_equipment",{})
	if saved is Dictionary and validate_snapshot(saved): _records = saved.duplicate(true)

func _ready() -> void:
	add_to_group("mining_operation")

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player): return
	_clock -= delta
	if _clock > 0: return
	_clock = .5
	_sync_rocks()
	if not _spawned or rocks.is_empty():
		_spawned = false
		spawn_equipment()

func spawn_equipment() -> void:
	if _spawned: return
	_spawned = true
	for definition in LAYOUT.machine_spawns():
		var identity := str(definition.id)
		var found: CharacterBody3D
		for existing in world.production.vehicles:
			if is_instance_valid(existing) and existing.vehicle_id == identity: found = existing; break
		if found != null:
			_watch_equipment(found)
			continue
		var record: Dictionary = _records.get(identity,{})
		# A destroyed machine does not magically return when the save is loaded.
		if not record.is_empty() and float(record.health) <= 0: continue
		var point: Vector3 = definition.point+Vector3.UP*.15
		if not record.is_empty(): point = Vector3(record.position[0],record.position[1],record.position[2])
		var region := str(record.get("region","desert"))
		if region != session.state.region_id or point.distance_to(world.player.global_position) > 125.0:
			_spawned = false
			continue
		# Per-vehicle residency, including equipment driven and saved elsewhere.
		# Production's 145 m distance cleanup remains the owner of despawning.
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point-Vector3.UP*4,1)
		if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): _spawned = false; continue
		var car: CharacterBody3D = world.production.spawn_vehicle(str(definition.archetype),point,float(record.get("yaw",definition.yaw)))
		if car == null: _spawned = false; continue
		car.vehicle_id = identity
		car.name = identity
		car.set_meta("region_id",str(record.get("region","desert")))
		car.set_meta("mining_equipment",true)
		_watch_equipment(car)
		if not record.is_empty():
			car.restore_health(float(record.health))
			car.restore_body_dents(record.get("body_dents",[]),record.get("breakaway_parts",{}))
			car.restore_blood_stains(int(record.get("blood_stains",0)))
			car.paint_color = Color.html(str(record.get("paint",car.paint_color.to_html())))
			car.equipment_state = record.get("equipment",{}).duplicate(true)
	if not rocks.is_empty() or world.player.global_position.distance_to(ORIGIN) > 155.0 or session.state.region_id != "desert": return
	var cargo_points := LAYOUT.cargo_spawns()
	if cargo_points.is_empty(): return
	var yard_ray := PhysicsRayQueryParameters3D.create(cargo_points[0]+Vector3.UP*8,cargo_points[0]-Vector3.UP*3,1)
	if world.get_world_3d().direct_space_state.intersect_ray(yard_ray).is_empty(): return
	for index in cargo_points.size():
		var rock := create_rock(index)
		rock.position = cargo_points[index]+Vector3.UP*.68
		world.add_child(rock)
		rocks.append(rock)

func _watch_equipment(car: CharacterBody3D) -> void:
	var callback := _record_destroyed.bind(car)
	if not car.destroyed.is_connected(callback): car.destroyed.connect(callback)
	var departure := _record_departure.bind(car)
	if not car.tree_exiting.is_connected(departure): car.tree_exiting.connect(departure)

func _record_departure(car: CharacterBody3D) -> void:
	if not is_instance_valid(car) or not is_instance_valid(world) or world.is_queued_for_deletion(): return
	_records[car.vehicle_id] = preload("res://runtime/FleetState.gd").capture(car,str(car.get_meta("region_id","desert")))
	_spawned = false

func _sync_rocks() -> void:
	for rock in rocks:
		if not is_instance_valid(rock) or rock.has_meta("mining_carried_by"): continue
		var near: bool = rock.global_position.distance_to(world.player.global_position) < 135.0
		if near and rock.get_meta("mining_stream_suspended",false):
			var ray := PhysicsRayQueryParameters3D.create(rock.global_position+Vector3.UP*2,rock.global_position-Vector3.UP*6,1,[rock.get_rid()])
			var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty(): continue
			rock.global_position.y = maxf(rock.global_position.y,float(hit.position.y)+float(rock.get_meta("mining_origin_height",.58))+.03)
			rock.freeze = false
			rock.remove_meta("mining_stream_suspended")
		elif not near and not rock.freeze:
			rock.freeze = true
			rock.linear_velocity = Vector3.ZERO
			rock.angular_velocity = Vector3.ZERO
			rock.set_meta("mining_stream_suspended",true)

func _record_destroyed(car: CharacterBody3D) -> void:
	if not is_instance_valid(car): return
	var record := preload("res://runtime/FleetState.gd").capture(car,str(car.get_meta("region_id","desert")))
	record.health = 0.0
	record.was_driven = false
	_records[car.vehicle_id] = record

static func create_rock(index: int) -> RigidBody3D:
	var rock := RigidBody3D.new()
	rock.name = "MinableRock%d" % index
	rock.mass = 180.0+index*13.0
	rock.collision_layer = 1
	rock.collision_mask = 7
	rock.continuous_cd = true
	rock.linear_damp = .8
	rock.angular_damp = 1.2
	rock.add_to_group("mining_cargo")
	rock.set_meta("mining_origin_height",.58)
	# Fractured quarry blocks, with the same maximum load envelope as before.
	var mesh: Mesh = preload("res://world/mining/MiningBatch.gd").mesh("rock")
	var radius := .66+float(index%3)*.07
	var rock_scale := Vector3(radius/.56,1.15/1.08,radius/.56)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = rock_scale
	visual.material_override = preload("res://world/mining/operation/MiningMachineModel.gd").material("ore_rock",Color("797164"))
	rock.add_child(visual)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var points := PackedVector3Array()
	for vertex in vertices: points.append(vertex*rock_scale)
	convex.points = points
	shape.shape = convex
	rock.add_child(shape)
	return rock

func nearest_action() -> Dictionary: return {}
func perform(_id: String) -> bool: return false
func save_block_reason() -> String:
	for machine in get_tree().get_nodes_in_group("mining_machine"):
		if is_instance_valid(machine.cargo): return "Solte a carga da máquina antes de salvar."
	return ""
func write_snapshot(data: Dictionary) -> void:
	for car in world.production.vehicles:
		if not is_instance_valid(car) or car.vehicle_id not in VEHICLE_IDS: continue
		var record := preload("res://runtime/FleetState.gd").capture(car,str(car.get_meta("region_id","desert")))
		record.was_driven = world.driving.occupied and world.driving.car == car
		_records[car.vehicle_id] = record
	data["mining_equipment"] = _records.duplicate(true)

static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.size() > VEHICLE_IDS.size(): return false
	for id in value:
		if id not in VEHICLE_IDS or not value[id] is Dictionary: return false
		var record: Dictionary = value[id]
		if not preload("res://runtime/FleetState.gd").validate(record): return false
		if record.get("vehicle_id","") != id or record.archetype != ARCHETYPES[VEHICLE_IDS.find(id)]: return false
	return true
func cancel() -> void:
	for machine in get_tree().get_nodes_in_group("mining_machine"): machine.release_cargo()
func cleanup() -> void:
	cancel()
	for rock in rocks:
		if is_instance_valid(rock): rock.queue_free()
	rocks.clear()
func _exit_tree() -> void: cleanup()
