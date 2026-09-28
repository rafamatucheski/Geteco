extends Node
## Drivable yard forklifts for Vértice. They are ordinary `port_forklift`
## vehicles (enter/drive like any car), parked in bays that keep the truck loop,
## the dock row and the guard patrol clear. The fence already blocks the sides;
## the open gate is closed to forklifts by a positional stop, not an invisible
## collider: unmasked ray queries (shots, probes) would hit such a body.
const GATE_STOP_Z := 74.5
const BAYS := [
	{"point":Vector3(-30,.12,40),"yaw":0.0},
	{"point":Vector3(19,.12,40),"yaw":0.0},
	{"point":Vector3(25,.12,40),"yaw":0.0}]
const YARD := Rect2(-49.2,-29.2,98.4,106.4)
var company: Node3D
var vehicles: Array = [null,null,null]
var _cursor := 0

func _ready() -> void:
	name = "VerticeYardForklifts"

func set_region_active(_active: bool) -> void:
	pass

func tick(near: bool) -> void:
	var session = company.session
	if session == null or not session.ready_for_play: return
	for i in vehicles.size():
		var vehicle = vehicles[i]
		if is_instance_valid(vehicle) and vehicle.health <= 0 and not _driven(vehicle) and not near:
			# A burnt-out wreck gives up its bay once nobody is watching.
			vehicle.vehicle_id += "_wreck_"+str(vehicle.get_instance_id())
			vehicle.remove_meta("port_work_vehicle")
			vehicles[i] = null
			vehicle = null
		if is_instance_valid(vehicle):
			_confine(vehicle)
			if not _driven(vehicle):
				vehicle.set_physics_process(near and not vehicle.has_meta("awaiting_ground"))
	if not near: return
	# One spawn per call avoids a model-build spike on first arrival.
	for step in vehicles.size():
		var slot := (_cursor+step)%vehicles.size()
		if is_instance_valid(vehicles[slot]): continue
		_cursor = slot+1
		_spawn(slot)
		return

func _driven(vehicle) -> bool:
	var session = company.session
	return vehicle.controlled or (session.world.driving.occupied and session.world.driving.car == vehicle)

func _confine(vehicle) -> void:
	var local: Vector3 = vehicle.global_position-company.global_position
	if local.z > GATE_STOP_Z and local.z < GATE_STOP_Z+6 and absf(local.x) < 9:
		# Gate line: stop at the threshold, whichever way the forklift faces.
		var facing_out: bool = (-vehicle.global_basis.z).z*signf(vehicle.speed) > 0
		if facing_out or local.z > GATE_STOP_Z+.4:
			vehicle.speed = 0.0
			vehicle.velocity = Vector3.ZERO
			vehicle.global_position.z = company.global_position.z+GATE_STOP_Z
		return
	# Anything that still puts one outside (explosion, spawn fallback) returns it.
	if YARD.has_point(Vector2(local.x,local.z)) or local.y > 6: return
	if _driven(vehicle): vehicle.speed = 0.0
	var inside := Vector2(clampf(local.x,YARD.position.x+2,YARD.end.x-2),clampf(local.z,YARD.position.y+2,YARD.end.y-3))
	vehicle.global_position = company.global_position+Vector3(inside.x,maxf(local.y,.12),inside.y)
	vehicle.velocity = Vector3.ZERO

func _spawn(slot: int) -> void:
	var session = company.session
	var id := "vertice_forklift_%02d"%slot
	# Persistent work vehicles are restored by the generic fleet save; adopt it.
	for existing in session.controller.vehicles:
		if is_instance_valid(existing) and existing.vehicle_id == id:
			vehicles[slot] = existing
			return
	var bay: Dictionary = BAYS[slot]
	var region = session.controller.regions.get("harbor")
	var point: Vector3 = company.global_position+bay.point
	if not is_instance_valid(region) or not region.prepare_collision_at(point): return
	var vehicle = session.controller.spawn_vehicle("port_forklift",point,bay.yaw)
	if not is_instance_valid(vehicle): return
	vehicle.vehicle_id = id
	vehicle.set_meta("port_work_vehicle",true)
	vehicle.set_meta("region_id","harbor")
	vehicle.traffic = false
	vehicle.brake_input = true
	vehicles[slot] = vehicle
