extends RefCounted
## Cobras feed the same swept projectile flight and impacts as police.
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")

static func fire(gameplay, shooter: CharacterBody3D, model: Node3D, target: Node3D, weapon_id: String, amount: float = -1.0, bridge_origin: Vector3 = Vector3.INF) -> bool:
	if not is_instance_valid(shooter) or not is_instance_valid(target) or not is_instance_valid(model): return false
	if gameplay.health <= 0 or not gameplay.state.weapons_allowed(): return false
	# A pé, só atira com o peito virado para o alvo (o modelo antigo olha para -Z): de costas ou
	# virando, o tiro saía da arma apontada para outro lado. No banco do carro o braço mira sozinho.
	if not bridge_origin.is_finite():
		var facing := -model.global_basis.z
		var toward := target.global_position - shooter.global_position
		facing.y = 0.0
		toward.y = 0.0
		if facing.length_squared() > 0.0001 and toward.length_squared() > 0.0001 and facing.normalized().dot(toward.normalized()) < cos(deg_to_rad(35.0)): return false
	var data: Dictionary = CATALOG.get_weapon(weapon_id)
	var pellets := int(data.get("pellets", 1))
	if gameplay._police_rounds.size() + pellets > 128: return false
	var origin: Vector3 = model.muzzle_position()
	var direction := origin.direction_to(target.global_position + Vector3.UP)
	var speed := float(data.get("projectile_speed", 920.0)) / 16.0
	var center: Vector3 = shooter.global_position + Vector3.UP * 1.1 if not bridge_origin.is_finite() else bridge_origin
	var bridge := PhysicsRayQueryParameters3D.create(center, origin, 7, [shooter.get_rid()])
	var blocked: Dictionary = shooter.get_world_3d().direct_space_state.intersect_ray(bridge)
	for pellet in pellets:
		var spread: Vector3 = direction.rotated(Vector3.UP, gameplay._rng.randf_range(-float(data.spread), float(data.spread)))
		var token: Dictionary = gameplay.effects.police_tracer(origin, spread, speed, data.get("tracer_color", Color("ffe36b")), float(data.damage)) if is_instance_valid(gameplay.effects) else {}
		gameplay._police_rounds.append({"point": origin, "direction": spread, "speed": speed,
			"distance": 0.0, "range": float(data.max_range) / 16.0,
			"damage": float(data.damage) if amount < 0.0 else amount, "data": data,
			"source": weakref(shooter), "rid": shooter.get_rid(), "visual": token, "blocked": blocked})
	model.attack()
	if is_instance_valid(gameplay.effects):
		gameplay.effects.muzzle_smoke(origin, direction)
		gameplay.effects.weapon_shot(weapon_id, model.weapon.global_position, direction, 1)
	gameplay._sound(weapon_id, origin)
	gameplay.npc_gunfire.emit(origin, direction, shooter)
	return true
