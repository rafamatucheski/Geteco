extends RefCounted
## Visit-owned story participants can die without changing campaign progress.
static func receive(actor: Node3D, visual: Node3D, amount: float, source: Node) -> void:
	if actor.dead or not is_finite(amount) or amount <= 0: return
	if preload("res://gameplay/DamageProtection.gd").is_protected(actor): return
	actor.health = maxf(0.0, actor.health - amount)
	var push: Vector3 = actor.global_position - source.global_position if source is Node3D else Vector3.ZERO
	if actor.health <= 0:
		actor.dead = true
		actor.set_physics_process(false)
		actor.collision_layer = 0
		actor.collision_mask = 0
		visual.activity = ""
		preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(actor, visual, push)
	elif visual.has_method("take_hit"):
		visual.take_hit(push, clampf(amount / 35.0, .3, 1.0))
