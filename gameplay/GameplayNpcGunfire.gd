extends RefCounted
## Tiro de NPC do Gameplay (polícia a pé e no carro, civil armado): balas com trajetória fatiada por
## quadro, zunido perto do jogador e recarga. Separado em 31/10 para o Gameplay.gd caber na leitura; a
## lista `_police_rounds` continua no Gameplay (testes a leem lá) e cada função antiga virou delegação.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem algumas delas numa
## subclasse do Gameplay (_play_stream, _kick_camera, _hit_effect...) e o despacho tem de continuar igual.

const AUDIO = preload("res://gameplay/CombatAudio.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## O passageiro atira para fora da janela lateral; o próprio carro fica excluído do tiro.
func police_vehicle_shoot(vehicle: CharacterBody3D, amount: float) -> bool:
	if g.police_surrendering() or not g.police_force_authorized() or g._police_rounds.size() >= 128: return false
	var suspect: Node3D = g.pursuit_target()
	if not is_instance_valid(suspect) or suspect == vehicle or g.health <= 0 or g.state == null or not g.state.weapons_allowed(): return false
	var side := signf(vehicle.to_local(suspect.global_position).x)
	if side == 0.0: side = 1.0
	var width := float(vehicle.get("half_width")) if vehicle.get("half_width") != null else 1.0
	var origin := vehicle.to_global(Vector3(side * (width + 0.18), 1.25, -0.35))
	var target := suspect.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(vehicle.global_position + Vector3.UP * 1.25, target, 7, [vehicle.get_rid()])
	var obstruction: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty() and obstruction.collider != suspect: return false
	var direction: Vector3 = origin.direction_to(target).rotated(Vector3.UP, g._rng.randf_range(-0.10, 0.10))
	var data := CATALOG.get_weapon("pistol")
	var token: Dictionary = g.effects.police_tracer(origin, direction, 34.0) if is_instance_valid(g.effects) else {}
	if is_instance_valid(g.effects): g.effects.muzzle_smoke(origin, direction)
	var bridge := PhysicsRayQueryParameters3D.create(vehicle.global_position + Vector3.UP * 1.25, origin, 7, [vehicle.get_rid()])
	var blocked: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(bridge)
	g._police_rounds.append({"point": origin, "direction": direction, "speed": 34.0, "distance": 0.0,
		"range": float(data.get("max_range", 420.0)) / 16.0, "damage": amount, "data": data,
		"source": weakref(vehicle), "rid": vehicle.get_rid(), "visual": token, "blocked": blocked})
	g.npc_gunfire.emit(origin, direction, vehicle)
	g._play_weapon_stream(AUDIO.gunfire_take("pistol", g._rng), origin, g.NPC_GUNFIRE_DB, 1.0, g.HEARING_GUNFIRE)
	return true

func civilian_shoot(shooter: CharacterBody3D, origin: Vector3, amount: float) -> bool:
	if not is_instance_valid(shooter) or shooter.get("dead") == true or not is_instance_valid(g.player) or g.health <= 0:
		return false
	if g.state == null or not g.state.weapons_allowed() or g._police_rounds.size() >= 128: return false
	var target: Vector3 = g.player.global_position + Vector3.UP
	var direction: Vector3 = origin.direction_to(target).rotated(Vector3.UP, g._rng.randf_range(-0.11, 0.11))
	var data := CATALOG.get_weapon("pistol")
	var token: Dictionary = g.effects.police_tracer(origin, direction, 32.0) if is_instance_valid(g.effects) else {}
	if is_instance_valid(g.effects): g.effects.muzzle_smoke(origin, direction)
	var bridge := PhysicsRayQueryParameters3D.create(shooter.global_position + Vector3.UP * 1.1, origin, 7, [shooter.get_rid()])
	var blocked: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(bridge)
	g._police_rounds.append({"point": origin, "direction": direction, "speed": 32.0,
		"distance": 0.0, "range": float(data.get("max_range", 420.0)) / 16.0,
		"damage": amount, "data": data, "source": weakref(shooter), "rid": shooter.get_rid(), "visual": token, "blocked": blocked})
	g._play_weapon_stream(AUDIO.gunfire_take("pistol", g._rng), origin, g.NPC_GUNFIRE_DB, g._rng.randf_range(0.95, 1.05), g.HEARING_GUNFIRE)
	g.npc_gunfire.emit(origin, direction, shooter)
	STALL_WORK.finish("shot.npc", STALL_WORK.begin())
	return true

func police_shoot(officer: CharacterBody3D, amount: float, weapon_id: String = "pistol") -> void:
	if g.police_surrendering(): return
	if not g.police_can_see(officer): return
	if g._police_rounds.size() >= 128: return
	var visual: Node3D = officer.get("visual")
	if not is_instance_valid(visual) or not visual.has_method("muzzle_position"): return
	var origin: Vector3 = visual.muzzle_position()
	var suspect: Node3D = g.pursuit_target()
	var tactical := int(officer.get("tier")) >= 2
	var spread := 0.10 if tactical else 0.13
	var direction: Vector3 = origin.direction_to(suspect.global_position + Vector3.UP).rotated(Vector3.UP, g._rng.randf_range(-spread, spread))
	var data := CATALOG.get_weapon(weapon_id)
	var police_bullet_speed := 45.0 if tactical else 34.0
	var token: Dictionary = g.effects.police_tracer(origin, direction, police_bullet_speed) if is_instance_valid(g.effects) else {}
	if is_instance_valid(g.effects): g.effects.muzzle_smoke(origin, direction)
	# A muzzle beyond a thin wall must not start the projectile on its far side.
	var bridge := PhysicsRayQueryParameters3D.create(officer.global_position + Vector3.UP * 1.1, origin, 7, [officer.get_rid()])
	var blocked: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(bridge)
	g._police_rounds.append({"point": origin, "direction": direction, "speed": police_bullet_speed,
		"distance": 0.0, "range": float(data.get("max_range", 420.0)) / 16.0,
		"damage": amount, "data": data, "source": weakref(officer), "rid": officer.get_rid(), "visual": token, "blocked": blocked})
	visual.attack()
	g.npc_gunfire.emit(origin, direction, officer)
	STALL_WORK.finish("shot.police", STALL_WORK.begin())
	# Corresponde à arma carregada e disparada por este policial despachado.
	g._play_weapon_stream(AUDIO.gunfire_take(weapon_id, g._rng), origin, g.NPC_GUNFIRE_DB, g._rng.randf_range(0.95, 1.05), g.HEARING_GUNFIRE)

func _advance_police_rounds(delta: float) -> void:
	for index in range(g._police_rounds.size() - 1, -1, -1):
		var round_index: Dictionary = g._police_rounds[index]
		g._bullet_whiz(round_index)
		var shot_from: Vector3 = round_index.point
		var glass_limit: Vector3 = shot_from + round_index.direction * minf(16.0,maxf(0.0,float(round_index.range)-float(round_index.distance)))
		var step := minf(float(round_index.speed) * delta, float(round_index.range) - float(round_index.distance))
		var end: Vector3 = round_index.point + round_index.direction * step
		var query := PhysicsRayQueryParameters3D.create(round_index.point, end, 7, [round_index.rid])
		var hit: Dictionary = round_index.blocked if not round_index.blocked.is_empty() else g.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): end = hit.position
		round_index.distance += (round_index.point as Vector3).distance_to(end)
		round_index.point = end
		var finished := not hit.is_empty() or float(round_index.distance) >= float(round_index.range) - 0.0001
		if is_instance_valid(g.effects) and not round_index.visual.is_empty(): g.effects.move_police_tracer(round_index.visual, end, finished)
		if not hit.is_empty():
			var data: Dictionary = round_index.data
			var damage := CATALOG.distance_damage(int(round_index.damage), float(round_index.distance) * 16.0, float(data.get("falloff_start", 170.0)), float(data.get("max_range", 420.0)), float(data.get("min_damage_ratio", 0.25)))
			g._damage_bullet(hit.collider, damage, round_index.source.get_ref(), shot_from, glass_limit, end, data)
			g._impact_sound(hit.collider, end, damage, hit.normal)
			g._hit_effect(hit, damage, round_index.direction)
		if finished: g._police_rounds.remove_at(index)

## Zunido da bala de NPC/polícia que passa a menos de 3 m do jogador: uma vez por bala, no ponto
## mais próximo da trajetória (só enquanto a bala ainda vai passar por ele).
func _bullet_whiz(round_index: Dictionary) -> void:
	if round_index.get("whizzed", false) or not is_instance_valid(g.player): return
	var offset: Vector3 = g.player.global_position + Vector3.UP * 1.0 - (round_index.point as Vector3)
	var along: float = offset.dot(round_index.direction)
	if along < -0.5 or along > float(round_index.speed) * 0.05: return
	var closest: Vector3 = (round_index.point as Vector3) + (round_index.direction as Vector3) * maxf(along, 0.0)
	if closest.distance_to(g.player.global_position + Vector3.UP * 1.0) > 3.0: return
	round_index["whizzed"] = true
	g._firefly_sound("weapons_fire", "bullet_whiz", closest, -6.0, 14.0, 0.06)

func police_reload(officer: Node3D, weapon_id: String) -> void:
	if not is_instance_valid(officer): return
	var sample := AUDIO.reload_take(weapon_id, g._rng)
	if sample != null:
		var duration := float(CATALOG.get_weapon(weapon_id).get("reload_duration",AUDIO.reload_seconds(weapon_id)))
		g._play_weapon_stream(sample, officer.global_position, 0.0, sample.get_length() / maxf(AUDIO.MIN_RELOAD, duration))
