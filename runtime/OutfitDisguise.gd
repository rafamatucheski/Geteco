extends RefCounted
## Player actions only: applying an appearance during load is not a disguise.
const POLICE_DISTANCE := 30.0

static func equip(session, id: String, at_shop: bool = false) -> bool:
	var previous: String = session.state.economy.outfit
	if not session.state.economy.equip_outfit(id): return false
	session.apply_outfit()
	if previous == id: return true
	# Ski rental overrides the equipped outfit, so no visible disguise occurred.
	if session.mountain_progression != null and session.mountain_progression.data.rental: return true
	var gameplay = session.world.gameplay
	if gameplay.stars <= 0: return true
	var at_home: bool = not session.state.place_id.is_empty() and session.activities.residence.can_enter(session.state.place_id)
	if at_home or (at_shop and police_far(session)):
		gameplay.clear_wanted()
	return true

static func police_far(session) -> bool:
	var gameplay = session.world.gameplay
	var place: String = session.state.place_id
	var player_point: Vector3 = session.world.player.global_position
	var exterior_point: Vector3 = session.return_point if not place.is_empty() else player_point
	var officers: Array = gameplay.police.duplicate()
	for officer in gameplay.get_tree().get_nodes_in_group("v2_police_officers"):
		if not officers.has(officer): officers.append(officer)
	for officer in officers:
		if not is_instance_valid(officer) or officer.is_queued_for_deletion() or officer.dead: continue
		var officer_place := str(officer.get_meta("police_place_id", ""))
		if officer_place != place and not officer_place.is_empty(): continue
		var point: Vector3 = player_point if officer_place == place else exterior_point
		if officer.global_position.distance_to(point) <= POLICE_DISTANCE: return false
	if is_instance_valid(gameplay.police_air):
		var helicopter = gameplay.police_air.helicopter
		if is_instance_valid(helicopter) and helicopter.global_position.distance_to(exterior_point) <= POLICE_DISTANCE: return false
	return true
