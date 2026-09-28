extends Node3D
## Transfers existing officers through the player's native interior boundary.
## Entry requires an observed crossing or a real interior report. No squad is
## generated in a room, and Maciota is never admitted as a pursuit context.
const NAVIGATION := preload("res://gameplay/police_response/tactics/PoliceInteriorNavigation.gd")
const PHYSICS := preload("res://gameplay/police_response/tactics/PoliceTactics.gd")
const MAX_VISITORS := 4
const DOOR_RANGE := 2.3
var gameplay: Node3D
var _session: Node
var _room: Node3D
var _place := ""
var _region := ""
var _known := false
var _reported_place := ""
var _return := Vector3.INF
var _last_seen_exterior := Vector3.INF
var _last_seen_age := INF
var _clock := 0.0
var _entry_cooldown := 0.0
var _visitors: Array[CharacterBody3D] = []
var _navigator := NAVIGATION.new()
var _physics := PHYSICS.new()

func configure(controller: Node3D) -> void:
	gameplay = controller
	gameplay.set_meta("police_interior_pursuit", self)
	process_physics_priority = -1

func report_interior(place_id: String) -> void:
	if place_id.is_empty() or place_id in ["maciota", "harbor_garage"]: return
	_reported_place = place_id
	if place_id == _place: _known = true

func knows_current_interior() -> bool:
	return _known and not _place.is_empty() and is_instance_valid(_room) and _weapons_allowed()

func exterior_access_for(officer: CharacterBody3D) -> Vector3:
	if not knows_current_interior() or not str(officer.get_meta("police_place_id", "")).is_empty(): return Vector3.INF
	return _return

func path_for(officer: CharacterBody3D, finish: Vector3) -> PackedVector3Array:
	if str(officer.get_meta("police_place_id", "")) != _place or not is_instance_valid(_room): return PackedVector3Array()
	return _navigator.path(officer.global_position, finish)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(gameplay) or not is_instance_valid(gameplay.get("world")): return
	_session = gameplay.world.get("session") as Node
	if not is_instance_valid(_session) or gameplay.get("state") == null: return
	_last_seen_age += delta
	_entry_cooldown = maxf(0.0, _entry_cooldown - delta)
	var place: String = str(gameplay.state.place_id)
	var region: String = str(gameplay.state.region_id)
	var next_room := _session.get("room") as Node3D
	if place != _place or next_room != _room or region != _region:
		_change_context(place, region, next_room)
	if place.is_empty():
		# Only a recent visual/radio contact beside the actual entrance licenses
		# following a crossing; knowing that a player owns a house never does.
		if gameplay.stars > 0 and gameplay.last_known_valid and float(gameplay.contact_age) <= .3:
			if gameplay.last_known.distance_to(gameplay.player.global_position) < 2.0:
				_last_seen_exterior = gameplay.last_known
				_last_seen_age = float(gameplay.contact_age)
		return
	if gameplay.stars <= 0 or gameplay.health <= 0 or not _weapons_allowed():
		_clear_visitors()
		_known = false
		return
	if not knows_current_interior(): return
	if _session.has_method("is_transition_blocked") and _session.is_transition_blocked(): return
	_clock -= delta
	if _clock > 0.0: return
	_clock = .25
	_visitors = _visitors.filter(func(officer): return is_instance_valid(officer))
	var limit := mini(MAX_VISITORS, 2 if gameplay.stars <= 2 else 4)
	if _living_visitors() >= limit or _entry_cooldown > 0.0: return
	for candidate in get_tree().get_nodes_in_group("v2_police_officers"):
		var officer := candidate as CharacterBody3D
		if not is_instance_valid(officer) or officer.dead or officer.controller != gameplay: continue
		if not str(officer.get_meta("police_place_id", "")).is_empty(): continue
		if not officer.is_physics_processing() or not officer.is_visible_in_tree(): continue
		if "mode" in officer and officer.mode != "combat": continue
		if not _at_exterior_door(officer): continue
		if admit(officer):
			_entry_cooldown = .9
			break

func _change_context(place: String, region: String, next_room: Node3D) -> void:
	# Rooms unload when the player exits. Visitors unload with that room rather
	# than teleporting through furniture or appearing at an exterior entrance.
	_clear_visitors()
	var same_region := _region.is_empty() or region == _region
	_place = place
	_region = region
	_room = next_room
	_known = false
	_return = Vector3.INF
	_navigator.configure(_room)
	if place.is_empty() or not is_instance_valid(_room):
		_reported_place = ""
		if not same_region:
			_last_seen_exterior = Vector3.INF
			_last_seen_age = INF
		return
	_return = _session.get("return_point")
	if _weapons_allowed() and same_region:
		_known = _reported_place == place or (_last_seen_age <= 2.5 and _last_seen_exterior.is_finite() and _last_seen_exterior.distance_to(_return) <= 6.0)
	_reported_place = ""
	_clock = .25
	_entry_cooldown = .6

func _weapons_allowed() -> bool:
	return is_instance_valid(gameplay) and gameplay.get("state") != null and gameplay.state.weapons_allowed() and _place not in ["maciota", "harbor_garage"]

func _at_exterior_door(officer: CharacterBody3D) -> bool:
	if not _return.is_finite(): return false
	var offset := officer.global_position - _return
	return Vector2(offset.x, offset.z).length() <= DOOR_RANGE and absf(offset.y) <= 1.2 and _physics.segment_clear(officer, officer.global_position, _return)

func admit(officer: CharacterBody3D) -> bool:
	if not knows_current_interior() or not _at_exterior_door(officer): return false
	if officer.dead or _living_visitors() >= MAX_VISITORS: return false
	var point := admission_point(officer)
	if not point.is_finite(): return false
	var dispatcher: Variant = gameplay.world.get("dispatch")
	if "dispatch_controller" in officer and is_instance_valid(officer.dispatch_controller):
		if not is_instance_valid(dispatcher) or not dispatcher.has_method("take_agent_for_interior") or not dispatcher.take_agent_for_interior(officer): return false
	if not gameplay.police.has(officer): gameplay.police.append(officer)
	officer.global_position = point
	officer.velocity = Vector3.ZERO
	officer.reset_pursuit_context(_place, search_destination(officer))
	# Native room and officer already share the real 3D world and depth buffer.
	# No sprite scaling, cloned rig or per-officer viewport is needed.
	_visitors.append(officer)
	return true

func admission_point(officer: CharacterBody3D) -> Vector3:
	if not is_instance_valid(_room): return Vector3.INF
	var doorway: Vector3 = _room.get("exit_position")
	var spawn: Vector3 = _room.get("spawn_position")
	var inward := spawn - doorway
	inward.y = 0
	if inward.length_squared() < .04: inward = _room.global_basis * Vector3.FORWARD
	inward = inward.normalized()
	var side := Vector3(-inward.z, 0, inward.x)
	for offset in [inward * .75, inward * 1.5, inward * .8 + side * .8, inward * .8 - side * .8, inward * 1.7 + side * .8, inward * 1.7 - side * .8]:
		var candidate: Vector3 = doorway + offset + Vector3.UP * .05
		if "definition" in _room:
			var size: Vector2 = _room.definition.get("size", Vector2.ZERO)
			var local := _room.to_local(candidate)
			if size != Vector2.ZERO and (absf(local.x) > size.x * .5 - .35 or absf(local.z) > size.y * .5 - .35): continue
		if _room.has_method("is_floor_clear") and not _room.is_floor_clear(_room.to_local(candidate), .34): continue
		if not _physics.point_clear(officer, candidate, 7): continue
		var overlaps := false
		for visitor in _visitors:
			if is_instance_valid(visitor) and visitor.global_position.distance_to(candidate) < .8:
				overlaps = true
				break
		if not overlaps: return candidate
	return Vector3.INF

func search_destination(officer: CharacterBody3D) -> Vector3:
	if not is_instance_valid(_room): return officer.global_position
	var center: Vector3 = _room.global_position
	if "definition" in _room:
		center = _room.to_global(_room.definition.get("camera_target", Vector3.ZERO))
	center.y = officer.global_position.y
	var slot := int(officer.get_meta("police_tactic_slot", 0))
	var cycle := int(Time.get_ticks_msec() / 5000) + slot
	var offsets := [Vector3.ZERO, Vector3(2.0, 0, 0), Vector3(-2.0, 0, 0), Vector3(0, 0, -2.0), Vector3(0, 0, 2.0)]
	for index in offsets.size():
		var point: Vector3 = center + offsets[posmod(cycle + index, offsets.size())]
		if _room.has_method("is_floor_clear") and not _room.is_floor_clear(_room.to_local(point), .34): continue
		if _physics.point_clear(officer, point): return point
	return officer.global_position

func _living_visitors() -> int:
	var count := 0
	for officer in _visitors:
		if is_instance_valid(officer) and not officer.dead: count += 1
	return count

func _clear_visitors() -> void:
	for officer in _visitors:
		if not is_instance_valid(officer): continue
		if is_instance_valid(gameplay): gameplay.police.erase(officer)
		officer.set_physics_process(false)
		officer.queue_free()
	_visitors.clear()

func _exit_tree() -> void:
	_clear_visitors()
	if is_instance_valid(gameplay) and gameplay.has_meta("police_interior_pursuit") and gameplay.get_meta("police_interior_pursuit") == self:
		gameplay.remove_meta("police_interior_pursuit")
