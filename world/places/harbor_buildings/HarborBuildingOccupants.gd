extends Node3D
## Corpos nativos, rigs humanos reais e props de trabalho vivem só com o andar ativo.
## A estação (posição, pessoa e atividades aceitas) vem da semente do prédio;
## a atividade desta visita e as reações a ameaça são sorteadas aqui.
const CONTENT := preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const RESIDENT := preload("res://world/places/harbor_buildings/HarborBuildingResident.gd")
const WANDER_CLEARANCE := .42
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
	var by_id := {}
	var claimed: Array[Vector3] = []
	for station in specification.get("occupants", []): claimed.append(station.position)
	for station in specification.get("occupants", []):
		var point: Vector3 = station.position
		if room.has_method("is_floor_clear") and not room.is_floor_clear(point, .34):
			push_error("Building resident station obstructed: %s / %s" % [definition.id, station.id])
			continue
		var visit: Dictionary = station.duplicate(true)
		var choices: Array = station.get("activities", [station.activity])
		visit.activity = str(choices[randi() % choices.size()]) if not choices.is_empty() else str(station.activity)
		var actor := RESIDENT.new()
		actor.position = point
		actor.rotation.y = float(station.yaw)
		if visit.activity == "sleep":
			var bed := _bed_side(room, point)
			if bed.is_empty(): visit.activity = "sit_doze"
			else:
				actor.position = bed.point
				actor.sleep_bed = room.global_transform * bed.bed
		elif visit.activity == "wander":
			var route := _wander_route(room, definition, point, claimed)
			if route.size() < 2: visit.activity = "stretch"
			else:
				for local in route: actor.wander_points.append(room.to_global(local))
		actor.specification = visit
		actor.set_meta("region_id", str(definition.get("region", "harbor")))
		group.add_child(actor)
		group.residents.append(actor)
		by_id[str(station.id)] = actor
		var reaction: Node
		if is_instance_valid(group.gameplay):
			reaction = preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd").install(actor, actor.resident_model, group.gameplay)
			if reaction != null:
				# Pesos por temperamento (semente do prédio); cada incidente sorteia.
				reaction.styles = station.get("reactions", {})
				reaction.threat_started.connect(func(_resident: Node3D):
					if is_instance_valid(actor.prop): actor.prop.hide())
		actor.configure_social(group.gameplay, reaction, group.illicit)
	# Conversas em dupla: cada um olha para o outro e a fala alterna.
	for actor in group.residents:
		var partner_id := str(actor.specification.get("partner", ""))
		if partner_id.is_empty() or not by_id.has(partner_id): continue
		actor.chat_partner = by_id[partner_id]
		actor.chat_offset = 3.2 if str(actor.specification.id).ends_with("_partner") else 0.0
	return group

## Ponto livre ao lado da cama mais próxima do andar, por onde quem dorme
## deitou e por onde levanta. Sem lado livre, a estação não dorme.
static func _bed_side(room: Node3D, station: Vector3) -> Dictionary:
	var model: Node = room.get("model")
	if not is_instance_valid(model) or not model.has_meta("dressing_beds"): return {}
	var best := {}
	var best_distance := INF
	for bed: Transform3D in model.get_meta("dressing_beds"):
		var local_bed: Transform3D = model.transform * bed
		# Lados da cama e o pé dela (a cabeceira fica na parede).
		var offsets: Array[Vector2] = []
		for side in [1.15, -1.15, 1.35, -1.35]:
			for along in [.25, -.15, .55, .85]: offsets.append(Vector2(side, along))
		for across in [0.0, .35, -.35]: offsets.append(Vector2(across, 1.62))
		for offset in offsets:
			var point: Vector3 = local_bed * Vector3(offset.x, -local_bed.origin.y + station.y, offset.y)
			point.y = station.y
			if not room.is_floor_clear(point, .36): continue
			var distance := point.distance_squared_to(station)
			if distance < best_distance:
				best_distance = distance
				best = {"point":point, "bed":local_bed}
	return best

## Dois ou três pontos de piso livre no cômodo, com segmentos desimpedidos
## (amostras de 25 cm) e longe das outras estações, da escada e da porta.
static func _wander_route(room: Node3D, definition: Dictionary, start: Vector3, claimed: Array[Vector3]) -> Array[Vector3]:
	var size: Vector2 = definition.size
	var candidates: Array[Vector3] = []
	var z := -size.y * .5 + 1.2
	while z < size.y * .5 - 1.0:
		var x := -size.x * .5 + 1.0
		while x < size.x * .5 - 1.0:
			var point := Vector3(x, start.y, z)
			x += .9
			if absf(point.x - start.x) + absf(point.z - start.z) < 1.6: continue
			if point.distance_to(start) > 5.5: continue
			# Escada e patamar ficam livres para o jogador.
			if Rect2(-size.x * .5 + .2, -2.2, 3.4, 4.8).has_point(Vector2(point.x, point.z)): continue
			if int(definition.get("building_floor_index", -1)) <= 0 and absf(point.x - float(definition.get("entrance_local", Vector3.ZERO).x)) < 1.3 and point.z > size.y * .5 - 2.6: continue
			if not room.is_floor_clear(point, WANDER_CLEARANCE + .08): continue
			var near_other := false
			for other in claimed:
				if other != start and other.distance_to(point) < 1.4: near_other = true
			if near_other: continue
			candidates.append(point)
		z += .9
	candidates.shuffle()
	var route: Array[Vector3] = [start]
	for candidate in candidates:
		if route.size() >= 3: break
		if not _segment_clear(room, route[-1], candidate, claimed, start): continue
		if route.size() == 2 and not _segment_clear(room, candidate, start, claimed, start): continue
		route.append(candidate)
	if route.size() == 2 and not _segment_clear(room, route[1], start, claimed, start): route.resize(1)
	return route

static func _segment_clear(room: Node3D, from: Vector3, to: Vector3, claimed: Array[Vector3], own: Vector3) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / .25))
	for step in steps + 1:
		var point := from.lerp(to, float(step) / steps)
		if not room.is_floor_clear(point, WANDER_CLEARANCE): return false
		for other in claimed:
			if other != own and Vector2(other.x - point.x, other.z - point.z).length() < .9: return false
	return true

func notice_intrusion(origin: Vector3, owner_session) -> void:
	var witnesses := 0
	var speaker: Node3D
	for resident in residents:
		if not is_instance_valid(resident) or resident.dead or not resident.is_visible_in_tree(): continue
		if resident.global_position.distance_to(origin) > 12.0: continue
		if absf(resident.global_position.y - origin.y) > 1.15: continue
		if not is_instance_valid(gameplay) or not is_instance_valid(gameplay.police_case): continue
		if not gameplay.police_case.visible_event(resident, origin): continue
		var reaction := resident.get_node_or_null("WorkplaceThreatReaction")
		if reaction == null: continue
		reaction._notice(origin, 12.0)
		if speaker == null: speaker = resident
		witnesses += 1
	if witnesses == 0: return
	var canonical := "Larga essa porta. Você não devia estar aqui." if illicit else "Ei! Vou chamar a polícia!"
	var binding := preload("res://audio/VoiceActorBinding.gd").resolve(speaker, "building_warning")
	var spoken := preload("res://audio/ActorDialogueVoice.gd").speak(speaker, canonical, binding)
	owner_session.show_speech(str(speaker.social_snapshot().get("name", "")), str(spoken.get("message", canonical)), maxf(3.0, float(spoken.get("duration", 0.0))), false, str(binding.get("persona", "")), canonical, str(binding.get("character_id", "")), str(binding.get("section", "")))
	# O arrombamento visível inicia o testemunho; a polícia só fica sabendo depois da ligação.
	if not illicit and is_instance_valid(gameplay): gameplay.report_observed_crime(12, origin, "burglary")
