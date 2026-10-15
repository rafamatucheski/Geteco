extends Node

## Physical walk-up access; NPC interactions remain owned by FullSession.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const IDS := ["harbor_supermarket", "harbor_ammunation", "mountain_gunshop", "harbor_police", "harbor_bank", "maciota", "port_boss_garage", "harbor_clothing", "harbor_fuel", "harbor_hospital", "harbor_fire_station",
	"mountain_cabin", "mountain_cabin_encosta", "mountain_cabin_forest", "mountain_cabin_village_1", "mountain_cabin_village_2", "mountain_cabin_village_3", "mountain_cabin_village_4",
	"lumberjack_shelter", "lumberjack_shelter_2", "lumberjack_shelter_3", "mountain_outfitters", "mountain_boutique", "mountain_village_outfitters",
	"westgate_garden", "quayside_house", "canal_north", "cemetery_keeper", "mountain_bunker", "ski_lodge", "cobra_leader_house", "santa_lua_home_1", "santa_lua_home_2", "santa_lua_home_3", "santa_lua_home_4",
	# Umbra (parque): porta dupla de empurrar; antes só a ação "Entrar" e a porta não abria.
	"harbor_haunted_house",
	# Fagulha e Curitiba Cellar: folhas de correr que ninguém abria (só a ação silenciosa "Entrar").
	"harbor_arcade", "harbor_curitiba_cellar"]
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
var _push_remaining := 0.0
var _contact_depth := 0.0
var _push_age := 1.0
var _push_inward := Vector3.FORWARD

func _ready() -> void:
	process_physics_priority = 100 # Apply the gesture after Actor's walking pose.
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	_push_age += delta
	if _push_age >= .42 or not is_instance_valid(session) or _blocked() or not session.state.place_id.is_empty():
		set_physics_process(false)
		return
	var player = session.world.player
	if not is_instance_valid(player.skeleton) or player.combat_weapon_id not in ["", "fists"] or not player.combat_clip.is_empty(): return
	var weight := sin(PI * clampf(_push_age / .42, 0.0, 1.0))
	var before := {}
	for name in ["LeftArm", "LeftForeArm", "LeftHand"]:
		var bone: int = player.skeleton.find_bone(name)
		if bone >= 0: before[bone] = player.skeleton.get_bone_pose_rotation(bone)
	var across := Vector3(-_push_inward.z, 0, _push_inward.x)
	var palm: Vector3 = player.global_position + Vector3.UP * 1.22 + _push_inward * .48 - across * .18
	player._solve_combat_arm("Left", player.visual.to_local(palm), Basis.IDENTITY, false, -1.0)
	for bone in before:
		player.skeleton.set_bone_pose_rotation(bone, before[bone].slerp(player.skeleton.get_bone_pose_rotation(bone), weight))

func _movement_intent(player: CharacterBody3D) -> Vector3:
	# move_and_slide removes inward velocity at a closed door. Read the intended
	# movement instead, using the same camera basis and remapped controls as Actor.
	if player.controlled_automatically: return player.automatic_direction
	var axis: Vector2 = get_node("/root/GameInput").movement()
	var right: Vector3 = session.world.camera.global_basis.x
	var back: Vector3 = session.world.camera.global_basis.z
	right.y = 0.0
	back.y = 0.0
	return (right.normalized() * axis.x + back.normalized() * axis.y).limit_length()

func _push_requested(local: Vector3, inward: Vector3, width: float, intent: Vector3) -> bool:
	var across := Vector3(-inward.z, 0, inward.x)
	var depth := local.dot(inward) - _contact_depth
	return absf(local.y) <= 1.0 and absf(local.dot(across)) <= width and depth >= -.6 and depth <= .15 and intent.dot(inward) > .3

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
		# Parque desligado (linha de base de medição): a Umbra não existe.
		if candidate_definition.is_empty(): continue
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
		_push_remaining = 0.0
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
	# A locked home's physical door already blocks the body. Do not latch a
	# failed crossing here: buying at the threshold must immediately allow entry.
	if session.activities != null and not session.activities.can_enter_home(id): return
	if id == "cobra_leader_house" and not _leader_accessible(): return
	# Pushing opens the door; only an intentional inward crossing transfers.
	if is_instance_valid(_facade) and _facade_id == id and _door_amount < .85: return
	if absf(local.dot(across)) > width or _movement_intent(player).dot(inward) <= .3: return
	var outer := -.1 if id == "harbor_police" else -1.15 if id in ["harbor_ammunation", "mountain_gunshop"] else -.8
	var inner := .6 if id == "harbor_police" else -.15 if id in ["harbor_ammunation", "mountain_gunshop"] else .3
	if id in ["harbor_ammunation", "mountain_gunshop"]: inner = maxf(inner, _contact_depth + .35)
	if depth < outer or depth > inner: return
	_blocked_entry_id = id
	if not _entry_available(id): return
	_enter(id, definition)

func _blocked() -> bool:
	return session.modal or session.is_transition_blocked() or session.world.player.input_locked or session.world.gameplay.health <= 0 or session.world.driving.occupied or session.world.driving.is_body_transition_active()

func _entry_available(id: String) -> bool:
	if not preload("res://runtime/ShopSafety.gd").admission_allowed(id, session.world.gameplay.stars):
		session.show_message("Perca a polícia antes de entrar.")
		return false
	if id == "cobra_leader_house" and not _leader_accessible():
		session.show_message("Takeshi ainda não liberou o acesso à casa.")
		return false
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

func _leader_accessible() -> bool:
	return session.state.campaign.has_progress("cobra_finale") or (session.state.campaign.active_id == "cobra_finale" and session.state.campaign.step >= 6)

func _entry_interrupted() -> bool:
	return session.modal or session.is_transition_blocked() or session.transition_generation != _entry_generation or session.world.gameplay.health <= 0 or session.world.driving.occupied or session.world.driving.is_body_transition_active()

func _update_facade(id: String, near: bool, delta: float) -> void:
	# These garages already have raised/open gates; do not search for hinges.
	if id in ["maciota", "port_boss_garage"]: return
	if not is_instance_valid(_facade) or _facade_id != id:
		_push_remaining = 0.0
		set_physics_process(false)
		_facade = null
		_facade_id = ""
		for candidate in get_tree().get_nodes_in_group("v2_walkin_facade"):
			if str(candidate.get_meta("place_id", "")) == id:
				_facade = candidate
				_facade_id = id
				_door_amount = float(candidate.get("open_amount"))
				_contact_depth = 0.0
				var contact := _door_position(id, _definition_for(id))
				if "hinge" in candidate and is_instance_valid(candidate.hinge): contact = candidate.hinge.global_position
				elif "entrance_door" in candidate and is_instance_valid(candidate.entrance_door): contact = candidate.entrance_door.global_position
				elif "panels" in candidate and not candidate.panels.is_empty(): contact = candidate.panels[0].global_position
				elif "leaves" in candidate and not candidate.leaves.is_empty(): contact = candidate.leaves[0].global_position
				elif "police_door_visuals" in candidate and not candidate.police_door_visuals.is_empty(): contact = candidate.police_door_visuals[0].global_position
				_contact_depth = (contact - _door_position(id, _definition_for(id))).dot(_inward(id))
				break
	if not is_instance_valid(_facade): return
	# Ownership gates the physical hinge as well as admission into the room.
	var owned: bool = session.activities == null or session.activities.can_enter_home(id)
	owned = owned and preload("res://runtime/ShopSafety.gd").admission_allowed(id, session.world.gameplay.stars)
	if id == "harbor_bank" and not session.robberies.can_enter_bank(): owned = false
	if id == "cobra_leader_house" and not _leader_accessible(): owned = false
	var player: CharacterBody3D = session.world.player
	var inward := _inward(id)
	var pushing := near and owned and not _blocked() and _push_requested(player.global_position - _door_position(id, _definition_for(id)), inward, _half_width(id), _movement_intent(player))
	if pushing:
		if _push_remaining <= 0.0 and _door_amount < .1:
			_push_age = 0.0
			_push_inward = inward
			set_physics_process(true)
		_push_remaining = .65
	else:
		_push_remaining = maxf(0.0, _push_remaining - delta)
	# Presence cannot start an opening, but keeps an already open leaf from
	# closing through the capsule when the player stops in the threshold.
	var local := player.global_position - _door_position(id, _definition_for(id))
	var depth := local.dot(inward) - _contact_depth
	var across := Vector3(-inward.z, 0, inward.x)
	if owned and _door_amount > .1 and absf(local.y) <= 1.0 and absf(local.dot(across)) <= _half_width(id) and depth >= -.5 and depth <= .5:
		_push_remaining = maxf(_push_remaining, .2)
	var next := move_toward(_door_amount, 1.0 if owned and (_push_remaining > 0.0 or _entering) else 0.0, delta / .28)
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
	var bank: bool = session.state.place_id=="harbor_bank"
	var half_width := 1.08 if bank else .75
	var approach := -.8 if bank else -.55
	if absf(local.x) > half_width or local.z < approach or local.z > .45 or player.velocity.z < .7: return
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
	if id in preload("res://world/desert/village/DesertVillageHomes.gd").IDS:
		return Vector3.FORWARD.rotated(Vector3.UP, float(_definition_for(id).exterior_rotation))
	var direction := Vector3.LEFT if id == "port_boss_garage" else Vector3.FORWARD
	return direction.rotated(Vector3.UP,float(_definition_for(id).get("editor_rotation",0)))

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
		"cobra_leader_house": return .23
		"harbor_haunted_house", "harbor_arcade", "harbor_curitiba_cellar": return .9
	return .62

func _close_size(id: String) -> float:
	if PLACES.walkup_family(id) == "cabin": return 8.0
	if id in ["mountain_bunker", "ski_lodge"]: return 14.0
	return 8.0 if id == "mountain_gunshop" else 14.0 if id in ["port_boss_garage", "harbor_fire_station"] else 11.0

func _door_position(id: String, definition: Dictionary) -> Vector3:
	if definition.has("editor_door_position"): return definition.editor_door_position
	if definition.has("editor_transform"):
		var original := definition.duplicate()
		original.exterior_position = definition.editor_base_exterior
		definition.editor_door_position = definition.editor_transform*_original_door_position(id,original)
		return definition.editor_door_position
	return _original_door_position(id,definition)

func _original_door_position(id: String, definition: Dictionary) -> Vector3:
	if id in preload("res://world/desert/village/DesertVillageHomes.gd").IDS: return definition.walkup_door_position
	if id == "cobra_leader_house": return definition.walkup_door_position
	if id == "harbor_supermarket": return definition.exterior_position + Vector3(0,0,5.5)
	# Plano da fachada da Umbra (ParkLume._house): folhas da UmbraDoor.
	if id == "harbor_haunted_house": return definition.exterior_position + Vector3(0,0,7.5)
	# Plano das folhas de correr (ArcadeFacade / CuritibaCellarFacade).
	if id == "harbor_arcade": return definition.exterior_position + Vector3(0,0,4.91)
	if id == "harbor_curitiba_cellar": return definition.exterior_position + Vector3(0,0,5.39)
	var family := PLACES.walkup_family(id)
	if not family.is_empty(): return definition.exterior_position + Vector3(0, 0, PLACES.walkup_door_z(family))
	if id == "maciota": return session.world.maciota_place.entry_position - Vector3(0, 0, .4875)
	if id == "port_boss_garage": return definition.exterior_position + Vector3(-4.5, 0, 0)
	if id == "harbor_hospital": return definition.exterior_position + Vector3(0, 0, 120.0 / (18.0 * .76822128))
	if id == "harbor_fire_station": return definition.exterior_position + PLACES.FIRE_STATION_DOOR_OFFSET
	if id in ["harbor_clothing", "harbor_fuel"]: return definition.exterior_position + Vector3(0, 0, BANK_DOOR_Z)
	var z := POLICE_DOOR_Z if id == "harbor_police" else BANK_DOOR_Z if id == "harbor_bank" else 5.8 if id == "harbor_ammunation" else 2.7
	return definition.exterior_position + Vector3(0, 0, z)
