extends RefCounted
const MATERIAL := preload("res://audio/combat/ImpactMaterial.gd")
const REMAINS := preload("res://world/shared/combat/ExplosionRemains.gd")
const IMPULSE := preload("res://world/shared/combat/BlastImpulse.gd")

static func exposed(source: Node2D, target: Node2D, origin: Vector2) -> bool:
	if not preload("res://world/shared/combat/CombatWorld.gd").shares_world(source, target): return false
	var ray := PhysicsRayQueryParameters2D.create(origin, target.global_position, 1 | 2)
	var excluded: Array[RID] = []
	if source is CollisionObject2D: excluded.append(source.get_rid())
	if target is CollisionObject2D: excluded.append(target.get_rid())
	ray.exclude = excluded
	return source.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

static func apply(target: Node2D, amount: int, origin: Vector2, source: Node2D, attacker: Node2D) -> void:
	if amount <= 0 or not target.has_method("take_damage"): return
	var flesh := MATERIAL.resolve(target) == &"flesh"
	if flesh and target.get("is_incapacitated") == true and amount >= int(target.get("health")):
		target.set("is_incapacitated", false)
	target.set_meta("combat_attacker", attacker)
	var player_caused := is_instance_valid(attacker) and attacker.is_in_group("player")
	# Some props expose the original one-argument damage contract.
	var argument_count := 1
	for method in target.get_method_list():
		if method.name == "take_damage":
			argument_count = method.args.size()
			break
	if argument_count >= 2: target.take_damage(amount, player_caused)
	else: target.take_damage(amount)
	if not flesh: return
	if target.get("is_dead") == true and not target.is_in_group("player"):
		REMAINS.spawn(target, origin, source as CollisionObject2D)
	elif target is CharacterBody2D:
		var outward := origin.direction_to(target.global_position)
		if outward.is_zero_approx(): outward = Vector2.RIGHT
		IMPULSE.apply(target, outward * clampf(amount * 3.0, 90, 420))
