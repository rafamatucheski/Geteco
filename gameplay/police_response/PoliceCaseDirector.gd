extends Node
## Crime, testimony, pursuit and investigation are separate states. A witness
## must perceive the event; hearing alone reports a location, never an identity.
const MAX_REPORTS := 24
const REPORT_SECONDS := 2.5
const INVESTIGATION_SECONDS := 300.0
const THREAT_SECONDS := 45.0
const VIOLENT := ["gunfire", "suppressed", "explosion", "assault", "police_assault", "police_killed", "vehicle_assault"]
var gameplay: Node3D
var pending: Array[Dictionary] = []
var investigation_left := 0.0
var threat_left := 0.0
var evidence_points := 0
var case_point := Vector3.ZERO
var case_region := ""
var case_place := ""
var surrendering := false
var surrender_time := 0.0
var surrender_block := 0.0
var descending := false
var _sense_clock := 0.0
var _last_phase := ""

func configure(owner_gameplay: Node3D) -> void:
	gameplay = owner_gameplay
	set_process(false)

func location() -> String:
	return String(gameplay.state.get("place_id")) if "place_id" in gameplay.state else ""

func region() -> String:
	return String(gameplay.state.get("region_id")) if "region_id" in gameplay.state else ""

func exterior_point(point: Vector3) -> Vector3:
	var session: Variant = gameplay.world.get("session") if is_instance_valid(gameplay.world) else null
	return session.return_point if is_instance_valid(session) and not location().is_empty() else point

func confirmed(points: int, point: Vector3, kind: String, testimony: Dictionary = {}) -> void:
	descending = false
	evidence_points = mini(600, evidence_points + points)
	case_point = testimony.get("exterior", exterior_point(point))
	case_region = testimony.get("region", region())
	case_place = testimony.get("place", location())
	investigation_left = INVESTIGATION_SECONDS
	if kind in VIOLENT:
		threat_left = THREAT_SECONDS
		surrendering = false
		surrender_block = 1.0
	if not case_place.is_empty() and case_place == location() and case_region == region():
		var interior := gameplay.get_node_or_null("PoliceInteriorPursuit")
		if interior != null: interior.report_interior(case_place)

func observe(points: int, point: Vector3, kind: String, victim: Node3D = null) -> bool:
	if points <= 0 or not gameplay.state.weapons_allowed() or gameplay.health <= 0: return false
	# The actual attacked officer has direct evidence, even when the blow was fatal.
	if is_instance_valid(victim) and victim.get_meta("gameplay_role", "") == "police":
		gameplay.register_crime(points, point, kind)
		return true
	var witnesses: Array[Dictionary] = []
	var candidates: Array[Node] = []
	if is_instance_valid(victim): candidates.append(victim)
	for actor in get_tree().get_nodes_in_group("police_witness"):
		if not candidates.has(actor): candidates.append(actor)
	for actor in get_tree().get_nodes_in_group("v2_damageable"):
		if actor != gameplay.player and not candidates.has(actor): candidates.append(actor)
	var tested := 0
	for actor in candidates:
		if not actor is Node3D or actor.get("dead") == true or not actor.is_visible_in_tree(): continue
		var role := String(actor.get_meta("gameplay_role", ""))
		if role not in ["civilian", "emergency", "police"]: continue
		if actor.global_position.distance_to(point) > (13.0 if kind == "suppressed" else 40.0): continue
		if role == "police" and String(actor.get_meta("police_place_id", "")) != location(): continue
		if tested >= 32: break
		tested += 1
		var identified := actor == victim or visible_event(actor, point, victim)
		if role == "police" and identified:
			gameplay.register_crime(points, point, kind)
			return true
		if not identified and kind not in ["gunfire", "explosion"]: continue
		witnesses.append({"ref": weakref(actor), "identified": identified})
		if witnesses.size() >= 4: break
	if witnesses.is_empty(): return false
	# A burst is one pending testimony with accumulated consequences, not an
	# unbounded queue of callbacks. Each report retains its observed position.
	for report in pending:
		if report.kind == kind and report.place == location() and report.region == region() and report.point.distance_to(point) < 4.0 and report.age < 0.5:
			report.points = mini(600, int(report.points) + points)
			return true
	if pending.size() >= MAX_REPORTS: return false
	pending.append({"points": points, "point": point, "exterior": exterior_point(point), "kind": kind,
		"age": 0.0, "place": location(), "region": region(), "witnesses": witnesses})
	return true

func visible_event(observer: Node3D, point: Vector3, subject: Node3D = null) -> bool:
	if not observer.is_inside_tree(): return false
	var exclusions: Array[RID] = []
	if observer is CollisionObject3D: exclusions.append(observer.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(observer.global_position + Vector3.UP * 1.4, point + Vector3.UP, 7, exclusions)
	var hit := observer.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == gameplay.player or (is_instance_valid(subject) and hit.collider == subject) or hit.position.distance_to(point + Vector3.UP) < 0.7

func preserve_departing_witnesses() -> void:
	# Streaming unloads people, not testimony they have already started. Keep
	# only the evidence of witnesses alive at this boundary, with its countdown.
	for report in pending:
		for witness in report.witnesses:
			var actor: Variant = witness.ref.get_ref()
			if is_instance_valid(actor) and actor.get("dead") != true:
				report["departed_heard"] = true
				report["departed_identified"] = bool(report.get("departed_identified", false)) or bool(witness.identified)
		report.witnesses = []

func _witness_evidence(report: Dictionary) -> Dictionary:
	var result := {"heard": bool(report.get("departed_heard",false)), "identified": bool(report.get("departed_identified",false))}
	for witness in report.witnesses:
		var actor: Variant = witness.ref.get_ref()
		if not is_instance_valid(actor) or actor.get("dead") == true: continue
		result.heard = true
		result.identified = bool(result.identified) or bool(witness.identified)
	return result

func tick(delta: float) -> void:
	threat_left = maxf(0.0, threat_left - delta)
	surrender_block = maxf(0.0, surrender_block - delta)
	if gameplay.stars == 0: investigation_left = maxf(0.0, investigation_left - delta)
	if investigation_left <= 0.0: evidence_points = 0
	for report in pending.duplicate():
		report.age += delta
		if report.age < REPORT_SECONDS: continue
		pending.erase(report)
		var heard := bool(report.get("departed_heard", false))
		var identified := bool(report.get("departed_identified", false))
		for witness in report.witnesses:
			var actor: Variant = witness.ref.get_ref()
			if not is_instance_valid(actor) or actor.get("dead") == true: continue
			heard = true
			identified = identified or bool(witness.identified)
		if not heard: continue
		# A call keeps the original crime position. It never reads the player's
		# current position after they have escaped or changed context.
		if report.region != region() or report.place != location():
			if identified: gameplay.register_crime(int(report.points), report.point, report.kind, report)
			else:
				case_point = report.exterior
				case_region = report.region
				case_place = report.place
				investigation_left = INVESTIGATION_SECONDS
			continue
		if identified:
			gameplay.register_crime(int(report.points), report.point, report.kind)
			gameplay.report_contact(report.point)
		else:
			case_point = report.exterior
			case_region = report.region
			investigation_left = INVESTIGATION_SECONDS
	if surrendering:
		if not can_surrender() or _player_moving() or gameplay.equipped() not in ["", "fists"]:
			cancel_surrender()
		else: surrender_time += delta
	_sense_clock -= delta
	if _sense_clock <= 0.0:
		_sense_clock = 0.25
		var next := phase()
		if next != _last_phase:
			_last_phase = next
			gameplay.changed.emit()

func can_surrender() -> bool:
	if gameplay.stars <= 0 or gameplay.health <= 0 or not gameplay.state.weapons_allowed(): return false
	if surrender_block > 0.0 or gameplay.player.input_locked: return false
	var driving: Variant = gameplay.world.get("driving") if is_instance_valid(gameplay.world) else null
	return not is_instance_valid(driving) or not driving.occupied

func request_surrender() -> bool:
	if not can_surrender() or _player_moving(): return false
	if gameplay.state.has_method("equip_weapon"): gameplay.state.equip_weapon("fists")
	if gameplay.equipped() not in ["", "fists"]: return false
	surrendering = true
	surrender_time = 0.0
	for round_index in gameplay._police_rounds.duplicate():
		# Hostile civilians use the same projectile array. Their bullets keep
		# flying; surrender is an agreement with the police, not invulnerability.
		var source: Variant = round_index.source.get_ref() if round_index.get("source") is WeakRef else null
		if not is_instance_valid(source) or not source is Node: continue
		if source.get_meta("gameplay_role", "") != "police" and not source.get_meta("dispatch_unit",false): continue
		if is_instance_valid(gameplay.effects) and not round_index.visual.is_empty():
			gameplay.effects.move_police_tracer(round_index.visual, round_index.point, true)
		gameplay._police_rounds.erase(round_index)
	gameplay.message.emit("Rendição: fique parado e aguarde a abordagem.")
	gameplay.changed.emit()
	return true

func cancel_surrender() -> void:
	if not surrendering: return
	surrendering = false
	surrender_time = 0.0
	gameplay.message.emit("Rendição cancelada.")
	gameplay.changed.emit()

func _player_moving() -> bool:
	return Vector2(gameplay.player.velocity.x, gameplay.player.velocity.z).length() > 0.65

func force_authorized() -> bool:
	return gameplay.stars > 0 and threat_left > 0.0 and not surrendering and gameplay.state.weapons_allowed()

func investigation_active() -> bool:
	return gameplay.stars == 0 and investigation_left > 0.0 and case_region == region() and location().is_empty()

func phase() -> String:
	if surrendering: return "surrender"
	if gameplay.stars > 0: return "pursuit" if gameplay.contact_age <= 1.0 else "search"
	if investigation_left > 0.0: return "investigation"
	if not pending.is_empty(): return "reported"
	return "clear"

func reset() -> void:
	descending = false
	pending.clear()
	investigation_left = 0.0
	evidence_points = 0
	threat_left = 0.0
	surrendering = false
	surrender_time = 0.0
	case_place = ""
	case_region = ""

func snapshot() -> Dictionary:
	var reports: Array[Dictionary] = []
	for report in pending.slice(0,MAX_REPORTS):
		var evidence := _witness_evidence(report)
		if not evidence.heard: continue
		# Snapshot the ongoing call, not live NPC identity. Loading streams new
		# people; an already perceived crime must retain its remaining call time.
		reports.append({"points":int(report.points),"point":[report.point.x,report.point.y,report.point.z],
			"exterior":[report.exterior.x,report.exterior.y,report.exterior.z],"kind":report.kind,
			"age":float(report.age),"region":report.region,"place":report.place,
			"heard":true,"identified":bool(evidence.identified)})
	return {"remaining": investigation_left, "threat": threat_left, "evidence": evidence_points,
		"point": [case_point.x, case_point.y, case_point.z], "region": case_region, "place": case_place,
		"descending":descending,"pending":reports}

static func _valid_point(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for component in value:
		if typeof(component) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(component)) or absf(float(component)) > 100000: return false
	return true

static func validate(data: Dictionary) -> bool:
	for key in ["remaining", "threat", "evidence"]:
		if not data.has(key) or typeof(data[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key]) < 0.0: return false
	if data.remaining > INVESTIGATION_SECONDS or data.threat > THREAT_SECONDS or data.evidence > 600 or float(data.evidence) != floorf(float(data.evidence)): return false
	if not _valid_point(data.get("point")): return false
	if data.has("descending") and not data.descending is bool: return false
	if data.has("pending"):
		if not data.pending is Array or data.pending.size() > MAX_REPORTS: return false
		for report in data.pending:
			if not report is Dictionary: return false
			for key in ["points","age"]:
				if typeof(report.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(report[key])): return false
			if report.points < 1 or report.points > 600 or float(report.points) != floorf(float(report.points)): return false
			if report.age < 0 or report.age > REPORT_SECONDS: return false
			if not _valid_point(report.get("point")) or not _valid_point(report.get("exterior")): return false
			for key in ["region","place","kind"]:
				if not report.get(key) is String or report[key].length() > 128: return false
			if report.kind.is_empty() or report.get("heard") != true or not report.get("identified") is bool: return false
	return data.get("region") is String and data.get("place") is String

func restore(data: Dictionary) -> void:
	reset()
	if data.is_empty(): return
	investigation_left = float(data.remaining)
	threat_left = float(data.threat)
	evidence_points = int(data.evidence)
	case_point = Vector3(data.point[0], data.point[1], data.point[2])
	case_region = data.region
	case_place = data.place
	descending = bool(data.get("descending",false))
	for report in data.get("pending",[]):
		pending.append({"points":int(report.points),"point":Vector3(report.point[0],report.point[1],report.point[2]),
			"exterior":Vector3(report.exterior[0],report.exterior[1],report.exterior[2]),"kind":report.kind,
			"age":float(report.age),"region":report.region,"place":report.place,"witnesses":[],
			"departed_heard":true,"departed_identified":bool(report.identified)})
