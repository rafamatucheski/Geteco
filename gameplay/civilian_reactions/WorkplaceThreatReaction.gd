extends Node
## Opt-in adapter for workers and counter staff excluded from street crowd AI.
## Owns a short collision-checked retreat, then returns to the interrupted post.
## It adds no damage or death API and never enrolls protected garage residents.
signal threat_started(actor: Node3D)
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const QUIET_SECONDS := 4.0
const RETREAT_DISTANCE := 1.6
const WALK_SPEED := 2.2
const HEARING_RADIUS := 30.0
const FIRE_RADIUS := 4.0
var actor: Node3D
var model: Node3D
var gameplay: Node
var body: Node3D
var active := false
var returning := false
var quiet_left := 0.0
var _scan_clock := 0.0
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _actor_physics := false
var _actor_process := false
var _body_process := false
var _body_lod := true
var _hand_provider := Callable()
var _hand_targets: Array = [null, null]
var _pose_owned := false
var _static_pose: Array[Dictionary] = []

static func install(owner_actor: Node3D, owner_model: Node3D, owner_gameplay: Node) -> Node:
	if not is_instance_valid(owner_actor) or not is_instance_valid(owner_model) or not is_instance_valid(owner_gameplay): return null
	if PROTECTION.is_protected(owner_actor) or PROTECTION.is_protected(owner_model): return null
	if str(owner_actor.get_meta("interior_npc_id", "")).to_lower() in ["maciota", "mechanic", "mecanico"]: return null
	if owner_actor.get("guard") == true: return null
	var existing := owner_actor.get_node_or_null("WorkplaceThreatReaction")
	if existing != null: return existing
	var reaction = load("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd").new()
	reaction.name = "WorkplaceThreatReaction"
	reaction.actor = owner_actor
	reaction.model = owner_model
	reaction.gameplay = owner_gameplay
	owner_actor.add_child(reaction)
	return reaction

func _ready() -> void:
	gameplay.weapon_fired.connect(_weapon_fired)
	gameplay.npc_gunfire.connect(_npc_gunfire)
	gameplay.explosion_occurred.connect(_explosion)
	set_physics_process(false)

func _eligible() -> bool:
	return is_instance_valid(actor) and actor.is_inside_tree() and actor.is_visible_in_tree() \
		and actor.get("dead") != true and not PROTECTION.is_protected(actor)

func _weapon_fired(weapon_id: String, origin: Vector3) -> void:
	if weapon_id in ["fists", "grenade"]: return
	var data: Dictionary = gameplay.weapon_data(weapon_id)
	var radius := 13.0 if data.get("suppressed", false) else HEARING_RADIUS
	if weapon_id == "flamethrower": radius = 8.0
	_notice(origin, radius)

func _npc_gunfire(origin: Vector3, _direction: Vector3, _shooter: Node3D) -> void:
	_notice(origin, HEARING_RADIUS)

func _explosion(origin: Vector3, radius: float, _source: Node) -> void:
	_notice(origin, maxf(HEARING_RADIUS, radius * 2.0))

func _notice(origin: Vector3, radius: float) -> void:
	if not _eligible() or actor.global_position.distance_squared_to(origin) > radius * radius: return
	quiet_left = QUIET_SECONDS
	if active:
		if returning:
			returning = false
			_target = _retreat_target(origin)
		return
	active = true
	returning = false
	_home = actor.global_position
	_target = _retreat_target(origin)
	_actor_physics = actor.is_physics_processing()
	_actor_process = actor.is_processing()
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.set_meta("workplace_threatened", true)
	if actor is CharacterBody3D: actor.velocity = Vector3.ZERO
	_claim_pose()
	set_physics_process(true)
	threat_started.emit(actor)

func _process(delta: float) -> void:
	_scan_clock -= delta
	if _scan_clock > 0.0: return
	_scan_clock = .25
	if not _eligible():
		if active: _release(is_instance_valid(actor) and actor.get("dead") != true)
		return
	if active and not _pose_owned: _claim_pose() # RigBodySwap can finish deferred.
	if actor.get_meta("v2_burning", false): _notice(actor.global_position, 1.0)
	var emergency: Node = gameplay.get("emergency")
	if emergency == null: return
	# EmergencyManager already caps this list at 12 fires; no scene/group scan.
	for fire in emergency.fires:
		if not is_instance_valid(fire) or fire.is_queued_for_deletion() or fire.intensity <= 0: continue
		if actor.global_position.distance_squared_to(fire.global_position) > FIRE_RADIUS * FIRE_RADIUS: continue
		var ray := PhysicsRayQueryParameters3D.create(fire.global_position + Vector3.UP * .5, actor.global_position + Vector3.UP, 1)
		if actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			_notice(fire.global_position, FIRE_RADIUS)
			break

func _physics_process(delta: float) -> void:
	if not _eligible():
		_release(is_instance_valid(actor) and actor.get("dead") != true)
		return
	quiet_left = maxf(0.0, quiet_left - delta)
	if quiet_left <= 0.0 and not returning:
		returning = true
		_target = _home
	if actor is CharacterBody3D:
		var offset := _target - actor.global_position
		offset.y = 0.0
		var movement := offset.limit_length(WALK_SPEED * delta)
		# Sweep ahead on both legs: a closed route leaves the NPC shielding in place.
		if movement.length_squared() > .000001 and _safe_motion(movement):
			actor.velocity.x = movement.x / delta
			actor.velocity.z = movement.z / delta
		else:
			actor.velocity.x = 0.0
			actor.velocity.z = 0.0
		actor.velocity.y = -1.0 if actor.is_on_floor() else actor.velocity.y - 20.0 * delta
		actor.move_and_slide()
		if returning and offset.length() < .06: _release(true)
	elif returning:
		_release(true)

func _retreat_target(origin: Vector3) -> Vector3:
	if not actor is CharacterBody3D: return actor.global_position
	var away := actor.global_position - origin
	away.y = 0
	if away.length_squared() < .01: away = Vector3.BACK
	away = away.normalized()
	for angle in [0.0, -.6, .6]:
		var movement := away.rotated(Vector3.UP, angle) * RETREAT_DISTANCE
		if _safe_motion(movement): return actor.global_position + movement
	return actor.global_position

func _safe_motion(movement: Vector3) -> bool:
	if actor.test_move(actor.global_transform, movement): return false
	var point := actor.global_position + movement
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .25, point - Vector3.UP * .4, 1)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.normal.y > .65

func _claim_pose() -> void:
	if actor.get("carrying") == true: return # Keep the existing physical cargo grip.
	if model.has_meta("workplace_shield_pivots"):
		for pair in model.get_meta("workplace_shield_pivots"):
			for joint in [pair.shoulder, pair.elbow]:
				_static_pose.append({"joint":joint,"transform":joint.transform})
			pair.shoulder.rotation = Vector3(-2.4, 0, -float(pair.side) * .1)
			pair.elbow.rotation.x = 2.9
		_pose_owned = true
		return
	body = model if model.get("hand_targets") != null else (model.get_meta("rig_body") if model.has_meta("rig_body") else null)
	if not is_instance_valid(body): return
	_hand_targets = body.hand_targets.duplicate()
	_hand_provider = body.hand_provider
	_body_process = body.is_processing()
	_body_lod = body.lod_enabled
	body.hand_provider = _shield_hands
	body.lod_enabled = false
	body.set_process(true)
	body._pose(0.0)
	_pose_owned = true

func _shield_hands() -> Array:
	return [body.to_global(Vector3(-.19, 1.6, .12)), body.to_global(Vector3(.19, 1.6, .12))]

func _release(resume: bool) -> void:
	for saved in _static_pose:
		if is_instance_valid(saved.joint): saved.joint.transform = saved.transform
	_static_pose.clear()
	if _pose_owned and is_instance_valid(body):
		body.hand_provider = _hand_provider
		body.hand_targets = _hand_targets
		body.lod_enabled = _body_lod
		if resume: body._pose(0.0)
		body.set_process(_body_process)
	_pose_owned = false
	if is_instance_valid(actor):
		actor.remove_meta("workplace_threatened")
		if actor is CharacterBody3D: actor.velocity = Vector3.ZERO
		if resume:
			actor.set_physics_process(_actor_physics)
			actor.set_process(_actor_process)
	active = false
	returning = false
	set_physics_process(false)
