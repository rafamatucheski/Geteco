extends RefCounted
const RADIUS := 230.0
const FRAGMENT_RADIUS := 110.0
const MATERIAL := preload("res://audio/combat/ImpactMaterial.gd")
const REMAINS := preload("res://world/shared/combat/ExplosionRemains.gd")
const IMPULSE := preload("res://world/shared/combat/BlastImpulse.gd")

static func apply(source: Node2D) -> void:
	var subjects: Array[Node] = []
	for group in ["damageable", "vehicle", "pedestrian", "police_officer", "firefighter", "paramedic", "mortician"]:
		for body in source.get_tree().get_nodes_in_group(group):
			if not subjects.has(body): subjects.append(body)
	for body in subjects:
		if body == source or not is_instance_valid(body) or not body is Node2D or not body.is_visible_in_tree(): continue
		var distance: float = source.global_position.distance_to(body.global_position)
		if distance >= RADIUS or not body.has_method("take_damage"): continue
		var query := PhysicsRayQueryParameters2D.create(source.global_position, body.global_position, 1)
		var excluded: Array[RID] = []
		if source is CollisionObject2D: excluded.append(source.get_rid())
		if body is CollisionObject2D: excluded.append(body.get_rid())
		query.exclude = excluded
		if not source.get_world_2d().direct_space_state.intersect_ray(query).is_empty(): continue
		var strength := 1.0 - distance / RADIUS
		var damage := maxi(1, int(165.0 * strength))
		var flesh := MATERIAL.resolve(body) == &"flesh"
		# Incapacitated pedestrians normally reject gun damage while awaiting rescue.
		if flesh and body.get("is_incapacitated") == true and damage >= int(body.get("health")):
			body.set("is_incapacitated", false)
		body.take_damage(damage, bool(source.get_meta("explosion_player_caused", false)))
		if flesh and body.get("is_dead") == true and distance <= FRAGMENT_RADIUS and not body.is_in_group("player"):
			REMAINS.spawn(body, source.global_position, source as CollisionObject2D)
		elif flesh and body is CharacterBody2D:
			var direction: Vector2 = source.global_position.direction_to(body.global_position)
			if direction.is_zero_approx(): direction = Vector2.RIGHT
			IMPULSE.apply(body, direction * lerpf(90.0, 420.0, strength))
	var camera := source.get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"):
		var proximity := source.global_position.distance_to(camera.global_position)
		if proximity < 700.0: camera.apply_shake(0.6 * (1.0 - proximity / 700.0))
