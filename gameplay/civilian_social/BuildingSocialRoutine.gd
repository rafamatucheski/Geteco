extends Node
## Four perception scans per second; WorkplaceThreatReaction owns movement.
const SOCIAL := preload("res://gameplay/civilian_social/CivilianSocialState.gd")
const SENSE_INTERVAL := .25
const AIM_REPORT_SECONDS := 1.5
var actor: CharacterBody3D
var gameplay: Node
var reaction: Node
var social := SOCIAL.new()
var illicit := false
var partner: Node3D
var _sense_clock := 0.0
var _elapsed := 0.0
var _aim_seconds := 0.0
var _aim_reported := false
var _health := 100.0

func configure(owner_actor: CharacterBody3D, owner_gameplay: Node, owner_reaction: Node, specification: Dictionary, owner_illicit: bool) -> void:
	actor = owner_actor
	gameplay = owner_gameplay
	reaction = owner_reaction
	illicit = owner_illicit
	social.configure(specification)
	_health = float(actor.health)
	_sense_clock = float(absi(int(specification.get("identity", 0))) % 4) * .0625
	if is_instance_valid(reaction):
		# This adapter checks real weapons, floor and line of sight itself.
		reaction.react_to_aim = false
		reaction.threat_started.connect(_threat_started)
		if reaction.has_signal("call_requested"): reaction.call_requested.connect(_call_requested)

func _process(delta: float) -> void:
	if not _eligible():
		partner = null
		social.finish()
		_elapsed = 0.0
		if is_instance_valid(actor): actor.present_social_threat(false)
		return
	_elapsed += delta
	_sense_clock -= delta
	if _sense_clock > 0.0: return
	var elapsed := _elapsed
	_elapsed = 0.0
	_sense_clock = SENSE_INTERVAL
	var threat_active: bool = is_instance_valid(reaction) and reaction.active
	if float(actor.health) < _health:
		social.frightened(9.0)
		if is_instance_valid(reaction) and _has_gameplay():
			reaction._notice(gameplay.player.global_position, 30.0)
			threat_active = reaction.active
	_health = float(actor.health)
	var aimed := _player_aiming_at_us()
	if aimed:
		if is_instance_valid(reaction):
			reaction._notice(gameplay.player.global_position, 12.0)
			threat_active = reaction.active
		_aim_seconds += elapsed
		if not _aim_reported and _aim_seconds >= AIM_REPORT_SECONDS:
			_aim_reported = true
			_report_threat()
	else:
		_aim_seconds = 0.0
		_aim_reported = false
		if _nearby_armed_player(): social.frightened(4.0)
	social.advance(elapsed, threat_active, _report_pending())
	if threat_active or social.calling: partner = null
	if is_instance_valid(partner) and not _within_reach(partner): end_social()
	actor.set_meta("social_state", social.state)
	# The actor process sleeps during retreat; this child still shows the phone.
	actor.present_social_threat(social.calling)

func _eligible() -> bool:
	return is_instance_valid(actor) and not actor.dead and actor.is_inside_tree() and actor.is_visible_in_tree()

func _has_gameplay() -> bool:
	return is_instance_valid(gameplay) and is_instance_valid(gameplay.player)

func _weapon_visible() -> bool:
	if not _has_gameplay() or not gameplay.has_method("equipped"): return false
	return str(gameplay.equipped()) not in ["", "fists"]

func _visible_player(radius: float) -> bool:
	if not _has_gameplay(): return false
	var player: Node3D = gameplay.player
	if absf(player.global_position.y - actor.global_position.y) > 1.15: return false
	if actor.global_position.distance_squared_to(player.global_position) > radius * radius: return false
	var exclusions: Array[RID] = [actor.get_rid()]
	if player is CollisionObject3D: exclusions.append(player.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 1.35, player.global_position + Vector3.UP * 1.2, 1, exclusions)
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _nearby_armed_player() -> bool:
	return _weapon_visible() and _visible_player(5.0)

func _player_aiming_at_us() -> bool:
	if not _weapon_visible() or gameplay.get("aim_active") != true or not _visible_player(12.0): return false
	if gameplay.weapon_data(str(gameplay.equipped())).get("is_melee", false): return false
	var direction: Vector3 = gameplay._aim_direction()
	var offset: Vector3 = actor.global_position - gameplay.player.global_position
	return direction.normalized().dot(offset.normalized()) > .94

func _report_threat() -> void:
	if illicit or social.threat_cooldown > 0.0 or not _has_gameplay(): return
	social.threat_cooldown = 22.0
	# Several residents can see the same sustained aim. They are witnesses to
	# one threat, not separate offenses to accumulate through the shared merger.
	var director: Node = gameplay.get("police_case")
	if is_instance_valid(director):
		for report in director.pending:
			if report.kind == "intimidation" and report.place == director.location() and report.region == director.region() and report.point.distance_to(gameplay.player.global_position) < 4.0:
				return
	gameplay.report_observed_crime(12, gameplay.player.global_position, "intimidation", actor)

func _report_pending() -> bool:
	if illicit or not is_instance_valid(gameplay): return false
	var director: Node = gameplay.get("police_case")
	if not is_instance_valid(director): return false
	for report in director.pending:
		for witness in report.witnesses:
			if witness.ref.get_ref() == actor: return true
	return false

## Estilo "ligar para a polícia": só denuncia quem de fato vê o jogador armado;
## a mesma deduplicação e o mesmo atraso de testemunho de _report_threat.
func _call_requested(_resident: Node3D) -> void:
	if _weapon_visible() and _visible_player(15.0): _report_threat()

func _threat_started(_resident: Node3D) -> void:
	social.frightened(8.0)
	social.dangerous = true
	partner = null

func _within_reach(player: Node3D) -> bool:
	if not is_instance_valid(player) or not player.is_inside_tree(): return false
	if player.get("dead") == true: return false
	if absf(actor.global_position.y - player.global_position.y) > 1.15: return false
	if actor.global_position.distance_squared_to(player.global_position) > 2.4 * 2.4: return false
	var exclusions: Array[RID] = [actor.get_rid()]
	if player is CollisionObject3D: exclusions.append(player.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 1.35, player.global_position + Vector3.UP * 1.2, 1, exclusions)
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func begin_social(player: Node3D) -> bool:
	if not _eligible() or not _within_reach(player) or not social.begin(): return false
	partner = player
	return true

func end_social() -> void:
	partner = null
	social.finish()

func interact(action: String, player: Node3D = null) -> Dictionary:
	var target := player if is_instance_valid(player) else partner
	if not _eligible() or not _within_reach(target): return {"ok":false, "line":"", "close":true}
	var result := social.interact(action, _weapon_visible())
	if result.get("ok", false) and action == "intimidate":
		if result.get("report", false) and not illicit and is_instance_valid(gameplay):
			gameplay.report_observed_crime(12, target.global_position, "intimidation", actor)
		if is_instance_valid(reaction): reaction._notice(target.global_position, 3.0)
		end_social()
	return result

func snapshot() -> Dictionary:
	var result := social.snapshot()
	result.can_interact = _eligible() and social.can_interact()
	return result
