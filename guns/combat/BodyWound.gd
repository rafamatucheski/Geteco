extends Node

## Body wound reaction and blood transfer for flesh impacts
static func apply(actor: Node2D, direction: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	preload("res://guns/combat/BodyWoundTrail.gd").attach(actor, direction)
	var ground_blood := preload("res://guns/combat/GroundBlood.gd")
	if ground_blood != null:
		ground_blood.spawn(actor, false)
	# Shoes acquire residue only when a planted foot touches a ground stain.
