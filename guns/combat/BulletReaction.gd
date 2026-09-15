extends Node
## Short collision-aware recoil; damage and medical state remain actor-owned.
var impulse := Vector2.ZERO
var remaining := 0.22

static func apply(actor: Node2D) -> void:
	if actor.get("is_dead") == true or actor.get("is_incapacitated") == true: return
	var reaction := actor.get_node_or_null("BulletReaction")
	if reaction == null:
		reaction = load("res://guns/combat/BulletReaction.gd").new()
		reaction.name = "BulletReaction"
		actor.add_child(reaction)
	reaction.impulse = actor.get_meta("bullet_impulse", Vector2.ZERO)
	reaction.remaining = 0.22

func _physics_process(delta: float) -> void:
	var actor := get_parent() as CharacterBody2D
	if actor == null or actor.get("is_dead") == true or actor.get("is_incapacitated") == true:
		queue_free()
		return
	# Sweep the whole body against its existing masks/exceptions, including
	# cars. Do not replace the walking velocity or move a point through solids.
	var saved_mask := actor.collision_mask
	actor.collision_mask |= 3
	var collision := actor.move_and_collide(impulse * minf(delta, remaining))
	actor.collision_mask = saved_mask
	if collision: impulse = impulse.slide(collision.get_normal())
	impulse = impulse.move_toward(Vector2.ZERO, 950.0 * delta)
	remaining -= delta
	if remaining <= 0.0: queue_free()
