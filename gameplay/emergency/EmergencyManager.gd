extends Node3D

const RESPONDER = preload("res://gameplay/emergency/Responder.gd")
const FIRE = preload("res://gameplay/emergency/Fire.gd")
const VEHICLE = preload("res://scripts/Vehicle.gd")
const RULES = preload("res://gameplay/dispatch/DispatchRules.gd")
const MAX_INCIDENTS := 24
const RESPONSE_RADIUS := 68.75
var world: Node3D
var gameplay: Node3D
var incidents: Dictionary = {}
var crews: Array[CharacterBody3D] = []
var fires: Array[Node3D] = []
var dispatch_clock := 0.0
var mortician_clock := 0.0
var dispatch_owned := false
var scan_clock := 0.0
var serial := 0

func configure(p_world: Node3D, p_gameplay: Node3D) -> void:
	world = p_world
	gameplay = p_gameplay
	# Buzina, sirene e alarme são sintetizados em GDScript no 1º uso (sirene ~17 ms, medido
	# em tests/measure/probe_first_emergency.gd --action=audio): o custo caía no quadro em
	# que a primeira viatura de emergência ligava a sirene. Sai da carga do jogo.
	var vehicle_audio := preload("res://gameplay/VehicleEquipmentAudio.gd")
	vehicle_audio.horn_stream()
	vehicle_audio.siren_stream()
	vehicle_audio.alarm_stream()

func reset_region() -> void:
	# Incident actors/sources belong to the world: never delete them on travel.
	for crew in crews:
		if not is_instance_valid(crew): continue
		if is_instance_valid(crew.vehicle) and not crew.vehicle.controlled: crew.vehicle.queue_free()
		crew.queue_free()
	crews.clear()
	for child in get_children():
		if child.get_meta("gameplay_role","") == "emergency" and not child.is_queued_for_deletion(): child.queue_free()
	for fire in fires:
		if is_instance_valid(fire): fire.queue_free()
	fires.clear()
	incidents.clear()
	dispatch_clock = 0.0
	mortician_clock = 0.0
	scan_clock = 0.0

func report_injury(actor: Node3D, fatal: bool = false) -> void:
	if is_instance_valid(actor) and actor.get_meta("interior_actor", false): return
	if not is_instance_valid(actor) or actor == gameplay.player or not actor.has_method("receive_damage"): return
	if actor.get_meta("gameplay_role", "") == "police": return # Police own their bounded removal.
	for record in incidents.values():
		if record.actor == actor:
			if fatal: record.role = "mortician"
			return
	serial += 1
	incidents[serial] = {"actor":actor, "role":"mortician" if fatal else "medic", "age":0.0, "assigned":false, "point":actor.global_position}
	while incidents.size() > MAX_INCIDENTS:
		var removable := -1
		for key in incidents:
			if not incidents[key].assigned:
				removable = key
				break
		if removable < 0: break
		_cleanup(removable)

func ignite(point: Vector3, source: Node = null, intensity: float = 1.0) -> Node3D:
	if intensity <= 0 or not gameplay.state.weapons_allowed(): return null
	for fire in fires:
		if is_instance_valid(fire) and fire.global_position.distance_to(point) < 1.5:
			fire.intensity = minf(2.0, fire.intensity + intensity * 0.2)
			return fire
	if fires.size() >= 12: return null
	var floor_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point - Vector3.UP * 3, 1)
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_ray)
	if floor_hit.is_empty(): return null
	var fire := FIRE.new()
	fire.manager = self
	fire.source = source
	fire.intensity = clampf(intensity, 0.1, 2.0)
	add_child(fire)
	fire.global_position = floor_hit.position + Vector3.UP * 0.03
	fires.append(fire)
	serial += 1
	incidents[serial] = {"actor":fire, "role":"fire", "age":0.0, "assigned":false, "point":fire.global_position}
	return fire

func extinguish(fire: Node3D, amount: float) -> void:
	if not is_instance_valid(fire) or amount <= 0: return
	fire.intensity = maxf(0, fire.intensity - amount)
	if fire.intensity == 0: fire.queue_free()

## Política automática compartilhada pelo despacho físico e pelo fallback legado.
func mortician_dispatch_allowed(key: int) -> bool:
	if gameplay.stars > RULES.MORTICIAN_MAX_STARS or mortician_clock > 0.0: return false
	return incidents.has(key) and float(incidents[key].age) >= RULES.mortician_response_delay(key)

func _physics_process(delta: float) -> void:
	dispatch_clock = maxf(0, dispatch_clock - delta)
	mortician_clock = maxf(0, mortician_clock - delta)
	scan_clock -= delta
	if scan_clock > 0: return
	scan_clock = 0.5
	fires = fires.filter(func(fire): return is_instance_valid(fire))
	crews = crews.filter(func(crew): return is_instance_valid(crew))
	for crew in crews.duplicate():
		if not crew.dead: continue
		if incidents.has(crew.incident_id): incidents[crew.incident_id].assigned = false
		if is_instance_valid(crew.vehicle) and not crew.vehicle.controlled: crew.vehicle.queue_free()
		crews.erase(crew)
	for key in incidents.keys():
		var record: Dictionary = incidents[key]
		record.age += 0.5
		if not is_instance_valid(record.actor):
			incidents.erase(key)
			continue
		if record.assigned and not is_instance_valid(record.get("crew")): record.assigned = false
		if record.age > 120 and not record.assigned:
			_cleanup(key)
			continue
		if dispatch_owned or record.assigned or dispatch_clock > 0 or crews.size() >= 3: continue
		if record.role == "mortician" and not mortician_dispatch_allowed(key): continue
		if gameplay.player.global_position.distance_to(record.actor.global_position) > RESPONSE_RADIUS: continue
		if _dispatch(key): dispatch_clock = 10.0

func _dispatch(key: int) -> bool:
	if dispatch_owned: return false
	var record: Dictionary = incidents.get(key, {})
	if record.is_empty() or not is_instance_valid(record.actor): return false
	var point: Vector3 = record.actor.global_position
	for attempt in 24:
		var angle := float(attempt) * TAU / 24
		var parking := point + Vector3(cos(angle), 0, sin(angle)) * (12.0 + (attempt % 3) * 2.0)
		var query := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.3, 2.8, 7.8)
		query.shape = box
		query.transform.origin = parking + Vector3.UP * 1.5
		query.collision_mask = 7
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
		var floor_ray := PhysicsRayQueryParameters3D.create(parking + Vector3.UP, parking - Vector3.UP * 2, 1)
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_ray)
		if floor_hit.is_empty(): continue
		var unit := VEHICLE.new()
		unit.archetype = "medic_box" if record.role == "medic" else ("rescue_pumper" if record.role == "fire" else "station_wagon")
		unit.paint_color = Color("202128") if record.role == "mortician" else Color.WHITE
		unit.vehicle_id = "emergency_" + str(key)
		world.add_child(unit)
		unit.place(floor_hit.position + Vector3.UP * 0.04, 0)
		var crew := RESPONDER.new()
		crew.manager = self
		crew.role = record.role
		crew.incident_id = key
		crew.destination = point
		crew.vehicle = unit
		add_child(crew)
		crew.global_position = unit.to_global(Vector3(unit.half_width + 0.9, 0, 0))
		if not gameplay._clear_at(crew.global_position):
			crew.queue_free()
			unit.queue_free()
			continue
		crews.append(crew)
		record.assigned = true
		record.crew = crew
		if record.role == "mortician": mortician_clock = RULES.MORTICIAN_COOLDOWN
		return true
	return false

func complete(key: int) -> void:
	if not incidents.has(key): return
	var record: Dictionary = incidents[key]
	var actor: Node3D = record.actor
	if is_instance_valid(actor):
		if record.role == "mortician":
			actor.queue_free()
		elif record.role == "medic":
			if actor.has_method("recover_from_injury"):
				actor.recover_from_injury()
			else:
				actor.health = 100.0
				if "dead" in actor: actor.dead = false
				if "incapacitated" in actor: actor.incapacitated = false
				actor.collision_layer = 2
				actor.collision_mask = 7
				actor.set_physics_process(true)
				if is_instance_valid(actor.get("visual")):
					actor.visual.rotation.z = 0
					actor.visual.position.y = 0
	incidents.erase(key)

func _cleanup(key: int) -> void:
	var record: Dictionary = incidents.get(key, {})
	if record.is_empty(): return
	if is_instance_valid(record.actor) and record.role == "mortician": record.actor.queue_free()
	incidents.erase(key)

func release(crew: CharacterBody3D) -> void:
	if incidents.has(crew.incident_id): incidents[crew.incident_id].assigned = false
	if is_instance_valid(crew.vehicle) and not crew.vehicle.controlled:
		crew.vehicle.queue_free()
	crews.erase(crew)
	crew.queue_free()
