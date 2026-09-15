extends Node
## Additive upper-body reaction after the native gait. Feet, collision and
## locomotion remain actor-owned; death and medical lifting own the full pose.
var hit_age := 1.0
var hit_strength := 0.0
var side := 1.0
var initial_health := 1.0
var applied: Array[Dictionary] = []
var actor: Node2D

static func apply(person: Node2D, amount: float, direction: Vector2, previous_health: float) -> void:
	if person.is_in_group("player"): return
	if person.get("is_dead") == true or person.get("is_incapacitated") == true: return
	if person.get("torso_node") == null: return
	var pose := person.get_node_or_null("WoundedPose")
	if pose == null:
		pose = load("res://guns/combat/WoundedPose.gd").new()
		pose.name = "WoundedPose"
		pose.initial_health = maxf(previous_health, float(person.get("max_health")) if "max_health" in person else previous_health)
		person.add_child(pose)
	pose.hit_age = 0.0
	pose.hit_strength = clampf(amount / pose.initial_health, .18, 1.0)
	pose.side = -1.0 if direction.x < 0 else 1.0

func _ready() -> void:
	actor = get_parent()
	process_physics_priority = 100
	get_tree().physics_frame.connect(_clear_pose)

func _clear_pose() -> void:
	for entry in applied:
		if not is_instance_valid(entry.joint): continue
		# Do not undo a new death/medical pose installed between physics ticks.
		if entry.joint.rotation.is_equal_approx(entry.after): entry.joint.rotation = entry.before
	applied.clear()

func _bend(joint: Node3D, offset: Vector3) -> void:
	if joint == null: return
	var before := joint.rotation
	joint.rotation += offset
	applied.append({"joint":joint, "before":before, "after":joint.rotation})

func _physics_process(delta: float) -> void:
	hit_age += delta
	if not is_instance_valid(actor) or actor.get("is_dead") == true or actor.get("is_incapacitated") == true or float(actor.health) >= initial_health:
		queue_free()
		return
	if not actor.is_visible_in_tree(): return
	if "_viewport_render_active" in actor and not actor._viewport_render_active: return
	var injury := clampf(1.0 - float(actor.health) / initial_health, 0, 1)
	var flinch := sin(clampf(hit_age / .36, 0, 1) * PI) * (.22 + hit_strength * .38)
	_bend(actor.torso_node, Vector3(injury*.24 + flinch*.65, 0, side*(injury*.07+flinch*.38)))
	_bend(actor.head_node, Vector3(-flinch*.35, 0, -side*flinch*.25))
	# Rescuers keep their hands on the cot; free civilians guard their wound.
	var free_hands: bool = actor.is_in_group("paramedic") or (actor.is_in_group("pedestrian") and actor.get("is_gangster") != true)
	if free_hands and not actor.has_meta("medical_managed"):
		_bend(actor.right_upper_arm, Vector3(injury*.65+flinch*.45, 0, -injury*.15))
		_bend(actor.right_lower_arm, Vector3(injury*.85+flinch*.5, 0, 0))
	if "viewport_3d" in actor: actor.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _exit_tree() -> void: _clear_pose()
