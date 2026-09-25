extends Node

## Physical walk-up access; NPC interactions remain owned by FullSession.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const IDS := ["harbor_ammunation", "mountain_gunshop", "harbor_police", "harbor_bank", "maciota", "port_boss_garage", "harbor_clothing", "harbor_fuel", "harbor_hospital", "harbor_fire_station",
	"mountain_cabin", "mountain_cabin_encosta", "mountain_cabin_forest", "mountain_cabin_village_1", "mountain_cabin_village_2", "mountain_cabin_village_3", "mountain_cabin_village_4",
	"lumberjack_shelter", "lumberjack_shelter_2", "lumberjack_shelter_3", "mountain_outfitters", "mountain_boutique", "mountain_village_outfitters",
	"westgate_garden", "quayside_house", "canal_north", "cemetery_keeper", "mountain_bunker", "ski_lodge"]
const CAMERA_SECONDS := 0.55
const POLICE_DOOR_Z := 250.0 / 32.0 + 0.35
const BANK_DOOR_Z := 180.0 / 32.0 - 0.72

var session: Node
var _facade: Node3D
var _facade_id := ""
var _door_amount := 0.0
var _entering := false
var _leaving := false
var _definitions: Dictionary = {}
var _blocked_entry_id := ""
var _reentry_remaining := 0.0
var _entry_cancelled := false
var _entry_generation := -1

func handles_place(id: String) -> bool:
	return id in IDS

func _definition_for(id: String) -> Dictionary:
	if _definitions.is_empty():
		for definition in PLACES.definitions():
			if handles_place(definition.id): _definitions[definition.id] = definition
		_definitions["maciota"] = {"id":"maciota", "region":"harbor"}
		for index in 2:
			var alias: Dictionary = _definitions.lumberjack_shelter.duplicate()
			alias["place_id"] = "lumberjack_shelter"
			alias.id = "lumberjack_shelter_%d" % (index + 2)
			alias.exterior_position = PLACES.shelter_access_exterior(index)
			_definitions[alias.id] = alias
	return _definitions.get(id, {})

func update(delta: float) -> void:
	if not is_instance_valid(session) or not session.ready_for_play or session.get_tree().paused:
		return
	_reentry_remaining = maxf(0.0, _reentry_remaining - delta)
	if _entering and _entry_interrupted():
		_entry_cancelled = true
		session.world.camera.clear_store_focus()
	if handles_place(session.state.place_id):
		_update_exit()
		return
	if not session.state.place_id.is_empty() or session.world.driving.occupied:
		return
	var player: CharacterBody3D = session.world.player
	var id := ""
	var closest := INF
	# Cached accesses; no catalog construction or scene traversal per frame.
	for candidate in IDS:
		var candidate_definition := _definition_for(candidate)
		if candidate_definition.region != session.state.region_id: continue
		var distance := player.global_position.distance_squared_to(_door_position(candidate, candidate_definition))
		if distance < closest:
			closest = distance
			id = candidate
	if id.is_empty(): return
	if _facade_id != id and is_instance_valid(_facade):
		_facade.set_open_amount(0.0)
		_facade = null
		_facade_id = ""
		_door_amount = 0.0
	var definition := _definition_for(id)
	var door := _door_position(id, definition)
	var near := closest < 81.0
	if near or (_facade_id == id and is_instance_valid(_facade)):
		_update_facade(id, near, delta)
	var local := player.global_position - door
	var inward := _inward(id)
	var across := Vector3(-inward.z, 0, inward.x)
	var depth := local.dot(inward)
	var width := _half_width(id)
	if not _blocked_entry_id.is_empty():
		if _blocked_entry_id != id or depth < -1.6 or absf(local.dot(across)) > width + .5:
			_blocked_entry_id = ""
	if not near or _entering or _leaving or _reentry_remaining > 0.0 or _blocked_entry_id == id or _blocked():
		return
	# Proximity opens the door; only an intentional inward crossing transfers.
	if absf(local.dot(across)) > width or player.velocity.dot(inward) < .7: return
	var outer := -.1 if id == "harbor_police" else -1.15 if id in ["harbor_ammunation", "mountain_gunshop"] else -.8
	var inner := .6 if id == "harbor_police" else -.15 if id in ["harbor_ammunation", "mountain_gunshop"] else .3
	if depth < outer or depth > inner: return
	_blocked_entry_id = id
	if not _entry_available(id): return
	_enter(id, definition)

func _blocked() -> bool:
	return session.modal or session.is_transition_blocked() or session.world.player.input_locked or session.world.gameplay.health <= 0 or session.world.driving.occupied or session.world.driving.is_body_transition_active()

func _entry_available(id: String) -> bool:
	if session.activities != null and not session.activities.can_enter_home(id):
		session.show_message("Esta casa ainda não é sua.")
		return false
	if session.garage_rewards != null and not session.garage_rewards.can_enter(id):
		session.show_message("A garagem abre entre 1h e 5h.")
		return false
	if id == "harbor_bank" and not session.robberies.can_enter_bank():
		session.show_message("O banco está fechado para investigação.")
		return false
	return true

func _entry_interrupted() -> bool:
	return session.modal or session.is_transition_blocked() or session.transition_generation != _entry_generation or session.world.gameplay.health <= 0 or session.world.driving.occupied or session.world.driving.is_body_transition_active()

func _update_facade(id: String, near: bool, delta: float) -> void:
	# These garages already have raised/open gates; do not search for hinges.
	if id in ["maciota", "port_boss_garage"]: return
	if not is_instance_valid(_facade) or _facade_id != id:
		_facade = null
		_facade_id = ""
		for candidate in get_tree().get_nodes_in_group("v2_walkin_facade"):
			if str(candidate.get_meta("place_id", "")) == id:
				_facade = candidate
				_facade_id = id
				_door_amount = float(candidate.get("open_amount"))
				break
	if not is_instance_valid(_facade): return
	var next := move_toward(_door_amount, 1.0 if near or _entering else 0.0, delta / .28)
	if not is_equal_approx(next, _door_amount):
		_door_amount = next
		_facade.set_open_amount(_door_amount)

func _enter(id: String, definition: Dictionary) -> void:
	_entering = true
	_entry_cancelled = false
	_entry_generation = session.transition_generation
	var player: CharacterBody3D = session.world.player
	player.input_locked = true
	var camera = session.world.camera
	var focus := _door_position(id, definition) + _inward(id) * 1.0 + Vector3.UP * 1.2
	if id == "harbor_ammunation": focus = definition.exterior_position + Vector3(0, 1.2, 2.0)
	elif id == "mountain_gunshop": focus = definition.exterior_position + Vector3(0, 1.2, 0)
	camera.focus_on_store(focus, _close_size(id), CAMERA_SECONDS)
	await get_tree().create_timer(CAMERA_SECONDS).timeout
	if not is_instance_valid(session) or not is_instance_valid(player):
		_entering = false
		return
	# A death, arrest or vehicle transition may take ownership during the zoom.
	var interrupted := _entry_cancelled or _entry_interrupted()
	if not session.modal and not session.is_transition_blocked() and not session.world.driving.is_body_transition_active():
		player.input_locked = false
	if not interrupted:
		if session.state.place_id.is_empty() and session.state.region_id == definition.region:
			await session.enter_place(str(definition.get("place_id", id)), true, id)
	if is_instance_valid(camera): camera.clear_store_focus()
	_entering = false

func _update_exit() -> void:
	if _leaving or _entering or _blocked() or not is_instance_valid(session.room): return
	var player: CharacterBody3D = session.world.player
	var local: Vector3 = player.global_position - session.room.exit_position
	if absf(local.x) > .75 or local.z < -.55 or local.z > .45 or player.velocity.z < .7: return
	_leave()

func _leave() -> void:
	_leaving = true
	var id: String = session.state.place_id
	if handles_place(session.access_id): id = session.access_id
	var definition := _definition_for(id)
	var player: CharacterBody3D = session.world.player
	player.input_locked = true
	var left: bool = await session.leave_place()
	if is_instance_valid(player):
		if left:
			_blocked_entry_id = id
			_reentry_remaining = CAMERA_SECONDS + .15
			player.input_locked = true
			var camera = session.world.camera
			camera.zoom_out_from_store(_door_position(id, definition), _close_size(id), CAMERA_SECONDS)
			# Establish the close starting frame before the exterior can render.
			camera._process(0.0)
			await get_tree().create_timer(CAMERA_SECONDS).timeout
			if is_instance_valid(camera): camera.clear_store_focus()
		if is_instance_valid(session) and not session.is_transition_blocked() and not session.modal:
			player.input_locked = false
	_leaving = false

func player_near_police(player: CharacterBody3D, definition: Dictionary) -> bool:
	return player.global_position.distance_to(_door_position("harbor_police", definition)) < 12.0

func _inward(id: String) -> Vector3:
	return Vector3.LEFT if id == "port_boss_garage" else Vector3.FORWARD

func _half_width(id: String) -> float:
	match PLACES.walkup_family(id):
		"cabin": return .16
		"shop", "residence", "keeper": return .23
		"bunker": return .34
		"lodge": return .42
	match id:
		"maciota", "port_boss_garage": return 1.8
		"harbor_ammunation": return 1.05
		"harbor_police": return .95
		"harbor_hospital": return 1.1
		"harbor_fire_station": return 1.4
		"harbor_bank", "harbor_clothing", "harbor_fuel": return .48
	return .62

func _close_size(id: String) -> float:
	if PLACES.walkup_family(id) == "cabin": return 8.0
	if id in ["mountain_bunker", "ski_lodge"]: return 14.0
	return 8.0 if id == "mountain_gunshop" else 14.0 if id in ["port_boss_garage", "harbor_fire_station"] else 11.0

func _door_position(id: String, definition: Dictionary) -> Vector3:
	var family := PLACES.walkup_family(id)
	if not family.is_empty(): return definition.exterior_position + Vector3(0, 0, PLACES.walkup_door_z(family))
	if id == "maciota": return session.world.maciota_place.entry_position - Vector3(0, 0, .4875)
	if id == "port_boss_garage": return definition.exterior_position + Vector3(-4.5, 0, 0)
	if id == "harbor_hospital": return definition.exterior_position + Vector3(0, 0, 120.0 / (18.0 * .76822128))
	if id == "harbor_fire_station": return definition.exterior_position + PLACES.FIRE_STATION_DOOR_OFFSET
	if id in ["harbor_clothing", "harbor_fuel"]: return definition.exterior_position + Vector3(0, 0, BANK_DOOR_Z)
	var z := POLICE_DOOR_Z if id == "harbor_police" else BANK_DOOR_Z if id == "harbor_bank" else 5.8 if id == "harbor_ammunation" else 2.7
	return definition.exterior_position + Vector3(0, 0, z)
