extends Node3D
## Native bodies, real human rigs and work props live only with the active floor.
const CONTENT := preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const RESIDENT := preload("res://world/places/harbor_buildings/HarborBuildingResident.gd")
var gameplay: Node
var residents: Array[CharacterBody3D] = []
var illicit := false
var family := ""

static func populate(room: Node3D, definition: Dictionary, floor_index: int) -> Node3D:
	var group := new()
	group.name = "BuildingOccupants"
	var ancestor: Node = room
	while is_instance_valid(ancestor):
		if "gameplay" in ancestor:
			group.gameplay = ancestor.gameplay
			break
		ancestor = ancestor.get_parent()
	room.add_child(group)
	var specification := CONTENT.floor_spec(definition, floor_index)
	group.illicit = bool(specification.get("illicit", false))
	group.family = str(specification.get("family", ""))
	for station in specification.get("occupants", []):
		var point: Vector3 = station.position
		if room.has_method("is_floor_clear") and not room.is_floor_clear(point, .34):
			push_error("Building resident station obstructed: %s / %s" % [definition.id, station.id])
			continue
		var actor := RESIDENT.new()
		actor.specification = station
		actor.position = point
		actor.rotation.y = float(station.yaw)
		actor.set_meta("region_id", str(definition.get("region", "harbor")))
		group.add_child(actor)
		group.residents.append(actor)
		var reaction: Node
		if is_instance_valid(group.gameplay):
			reaction = preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd").install(actor, actor.resident_model, group.gameplay)
			if reaction != null: reaction.threat_started.connect(func(_resident: Node3D):
				if is_instance_valid(actor.prop): actor.prop.hide())
		actor.configure_social(group.gameplay, reaction, group.illicit)
	return group

func notice_intrusion(origin: Vector3, owner_session) -> void:
	var witnesses := 0
	for resident in residents:
		if not is_instance_valid(resident) or resident.dead or not resident.is_visible_in_tree(): continue
		if resident.global_position.distance_to(origin) > 12.0: continue
		if absf(resident.global_position.y - origin.y) > 1.15: continue
		if not is_instance_valid(gameplay) or not is_instance_valid(gameplay.police_case): continue
		if not gameplay.police_case.visible_event(resident, origin): continue
		var reaction := resident.get_node_or_null("WorkplaceThreatReaction")
		if reaction == null: continue
		reaction._notice(origin, 12.0)
		witnesses += 1
	if witnesses == 0: return
	owner_session.show_message("Larga essa porta. Você não devia estar aqui." if illicit else "Ei! Vou chamar a polícia!")
	# The visible break-in starts testimony; police only learn it after the call.
	if not illicit and is_instance_valid(gameplay): gameplay.report_observed_crime(12, origin, "burglary")
