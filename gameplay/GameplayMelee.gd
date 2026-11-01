extends RefCounted
## Corpo a corpo do Gameplay: aviso de alcance (melee_feedback), escolha do alvo (_melee_pick), o golpe
## (melee), o peso do contato (tranco e empurrão), a fila de cliques, o soco da UAL e o rastro do taco/machado.
## Separado em 01/11 (Onda 2 de docs/plano-divisao-arquivos-grandes-20261101.md) para o Gameplay.gd caber
## na leitura. O estado (_melee_action, _melee_buffer, _pending_contact, _shoves, _swing_*, _clip_*...) e
## as tabelas (MELEE_KICK, MELEE_SHOVE, PUNCH_CLIPS...) continuam no Gameplay, onde testes, HUD e a mira os
## leem; cada função antiga virou delegação de uma linha com a mesma assinatura e os mesmos padrões.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem _damage, _hit_effect,
## _kick_camera, attack_allowed e equipped numa subclasse do Gameplay e o despacho tem de continuar igual.

const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const GYM := preload("res://activities/gym/GymState.gd")
const MELEE_CONTROL := preload("res://gameplay/MeleeControl.gd")
const RIG_POSE := preload("res://gameplay/WeaponRigPose.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Balanço da arma e torção do corpo durante o golpe. Parcial: não há pose de braço (o V1 usa IK sobre o
## rig Meshy, `PlayerCombatPose`/`MeshyMeleePose`); aqui só a arma na mão balança e o corpo gira.
func _start_swing(data: Dictionary, direction: Vector3) -> void:
	g._swing_age = 0.0
	g._swing_stance = String(data.get("stance", ""))
	g._swing_side = -g._swing_side
	g._swing_yaw = atan2(-direction.x, -direction.z)

## Soco da UAL (punhos e soqueira). Como o clipe de arma de fogo, só com o jogador parado.
func _play_punch_clip(id: String) -> void:
	if not RIG_POSE.ab_punch_clip or id not in ["fists", "knuckles"] or not is_instance_valid(g.player) or not "animation" in g.player: return
	if g.player is CharacterBody3D and (g.player as CharacterBody3D).velocity.length() > g.GUN_CLIP_MAX_SPEED: return
	var spec: Array = g.PUNCH_CLIPS["left" if g._rig_pose.punch_left else "right"]
	var animation: AnimationPlayer = g.player.animation
	if animation == null or not animation.has_animation(spec[0]): return
	var start := maxf(0.0, float(spec[1]) - float(RIG_POSE.MELEE_CONTACT.get(id, 0.14)))
	g._clip_name = spec[0]
	g._clip_start = start
	g._clip_end = start + g.PUNCH_CLIP_SECONDS
	g._clip_age = 0.0
	g._clip_rate = 1.0
	g._clip_weapon = g.equipped()

func _update_swing(delta: float) -> void:
	if g._swing_age < 0.0: return
	g._swing_age += delta
	var progress: float = g._swing_age / g.SWING_DURATION
	if progress >= 1.0 or not g.attack_allowed():
		g._swing_age = -1.0
	# A janela acima só acompanha a ação lógica. A trajetória visual é específica
	# de cada arma em WeaponRigPose; não sobrepor um balanço genérico ao IK.

func melee_feedback_active() -> bool:
	# Estados de teste (FakeState) não têm arma equipada nem regra de ataque: sem aviso de mira.
	if g.state == null or not "equipped_weapon" in g.state or not g.state.has_method("can_attack"): return false
	var id: String = g.equipped() if not g.equipped().is_empty() else "fists"
	if not is_instance_valid(g.player) or not CATALOG.WEAPONS.get(id, {}).get("is_melee", false) or not g.attack_allowed() or not g.free_play_ok() or g.player.input_locked: return false
	var preparing := InputMap.has_action("aim") and Input.is_action_pressed("aim")
	var striking: bool = not g._melee_action.is_empty() and g._melee_action.id == id and g._rig_pose.action_age <= float(g._melee_action.contact) + float(g._melee_action.window)
	return preparing or striking

func melee_feedback() -> Dictionary:
	var frame := Engine.get_physics_frames()
	if frame == g._melee_feedback_frame and not g._melee_feedback_cache.is_empty(): return g._melee_feedback_cache
	g._melee_feedback_frame = frame
	var origin: Vector3 = g.player.global_position + Vector3.UP * 1.05
	var direction: Vector3 = g._melee_direction()
	var id: String = g.equipped() if not g.equipped().is_empty() else "fists"
	var data: Dictionary = g.weapon_data(id)
	var reach := float(data.get("melee_range", 46.0)) / 16.0
	var pick: Dictionary = g._melee_pick(origin, direction, data, id)
	g._melee_feedback_cache = {"origin": origin, "direction": direction, "reach": reach, "point": pick.get("point", origin + direction * reach), "blocked": pick.get("blocked", false), "in_range": pick.has("actor"), "confirmed": g.hitmarker_active()}
	return g._melee_feedback_cache

func _melee_direction() -> Vector3:
	if not g._melee_action.is_empty() and bool(g._melee_action.locked) and g._rig_pose.action_age <= float(g._melee_action.contact) + float(g._melee_action.window): return g._melee_action.direction
	var direction: Vector3 = g.aim_direction()
	if direction.length_squared() > 0.001: g._last_melee_direction = direction
	return g._last_melee_direction

func _clear_melee_action() -> void:
	g._melee_buffer.clear()
	g._melee_action.clear()
	g._melee_rate = 1.0
	g._melee_feedback_cache.clear()
	if not g._pending_contact.is_empty() and g._pending_contact.id != "grenade": g._pending_contact.clear()
	if not g._pending_swing.is_empty(): g._pending_swing.clear()
	if is_instance_valid(g.player): g.player.set_meta("melee_movement_scale", 1.0)

func update_melee_buffer() -> void:
	if g._melee_buffer.is_empty(): return
	var id: String = g.equipped()
	if id.is_empty(): id = "fists"
	if not g.attack_allowed() or not g.free_play_ok() or g.player.input_locked or id != g._melee_buffer.id or g._combat_clock > float(g._melee_buffer.until):
		g._melee_buffer.clear()
		return
	if g.cooldown > 0.0 or not g._pending_contact.is_empty(): return
	g._melee_buffer.clear()
	g._stall_fire_at(g.aim_point)

## Compartilhado pela prévia e pelo dano. A fase larga é limitada; a fase estreita respeita
## o arco da arma, a altura, o alcance e a oclusão sólida. Nunca redireciona o cursor.
func _melee_pick(origin: Vector3, direction: Vector3, data: Dictionary, id: String) -> Dictionary:
	var reach := float(data.get("melee_range", 46.0)) / 16.0
	var profile: Dictionary = MELEE_CONTROL.profile(id)
	var half_width := float(profile.width) * 0.5
	var arc := deg_to_rad(float(profile.arc))
	var box := BoxShape3D.new()
	box.size = Vector3(float(profile.width) + sin(arc) * reach * 2.0, 2.1, reach + 0.4)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), origin + direction * (reach * 0.5))
	query.collision_mask = 2
	query.exclude = [g.player.get_rid()]
	var candidates: Array[Node3D] = []
	for result in g.get_world_3d().direct_space_state.intersect_shape(query, 16):
		if result.collider is Node3D and not candidates.has(result.collider): candidates.append(result.collider)
	if id in ["katana", "axe"] and is_instance_valid(g.katana_wounds):
		for corpse in g.katana_wounds.candidates_near(origin, reach):
			if not candidates.has(corpse): candidates.append(corpse)
	var selected: Dictionary = {}
	var best_score := INF
	var blocked_pick: Dictionary = {}
	for actor in candidates:
		if not is_instance_valid(actor) or actor == g.player or g._is_invulnerable(actor) or not actor.has_method("receive_damage"): continue
		var dead: bool = actor.get("dead") == true
		if dead and (not id in ["katana", "axe"] or not is_instance_valid(g.katana_wounds) or not g.katana_wounds.can_sever(actor)): continue
		var target := actor.global_position + Vector3.UP
		if dead: target = g.katana_wounds.closest_cut_point(actor, origin + direction * minf(reach, origin.distance_to(actor.global_position)))
		var flat := target - origin
		if absf(flat.y) > 1.6: continue
		flat.y = 0.0
		var forward := direction.dot(flat)
		var lateral := absf(direction.cross(flat).y)
		if forward < -0.15 or flat.length() > reach + 0.25 or lateral > half_width + maxf(0.0, forward) * tan(arc): continue
		var ray := PhysicsRayQueryParameters3D.create(origin, target, 7, [g.player.get_rid()])
		ray.hit_from_inside = true
		var obstruction := g.get_world_3d().direct_space_state.intersect_ray(ray)
		if not obstruction.is_empty() and obstruction.collider != actor:
			if blocked_pick.is_empty(): blocked_pick = {"point": obstruction.position, "blocked": true, "surface": obstruction.collider}
			continue
		var score := MELEE_CONTROL.target_score(origin, direction, target) + (100.0 if dead else 0.0)
		if score < best_score:
			best_score = score
			selected = {"actor": actor, "point": target, "blocked": false}
	if not selected.is_empty(): return selected
	if not blocked_pick.is_empty(): return blocked_pick
	var wall_ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * reach, 5, [g.player.get_rid()])
	wall_ray.hit_from_inside = true
	var wall := g.get_world_3d().direct_space_state.intersect_ray(wall_ray)
	if not wall.is_empty(): return {"point": wall.position, "blocked": true, "surface": wall.collider}
	return {}

func melee(origin: Vector3, direction: Vector3, data: Dictionary, id: String = "") -> bool:
	var pick: Dictionary = g._melee_pick(origin, direction, data, id)
	if not pick.has("actor"):
		if pick.get("blocked", false) and pick.has("surface"):
			g._melee_hit_sound(id, pick.surface, pick.point, float(data.damage))
			g._rig_pose.impact(id)
			return true
		return false
	var actor: Node3D = pick.actor
	var target: Vector3 = pick.point
	var was_living: bool = actor.get("dead") != true
	# Força treinada na academia (GymState) só vale para o golpe do Dante.
	var strength: float = GYM.melee_damage_scale(g._gym_world()) * (g.SHIELD_KICK_DAMAGE if g._shield_kicking and id == "sword_shield" else 1.0)
	if was_living: g._damage(actor, float(data.damage) * strength, g.player)
	var severed := false
	if actor.get("dead") == true and is_instance_valid(g.katana_wounds):
		g.katana_wounds.register_defeated(actor)
		# Lâminas longas cortam já no golpe que derruba (o 2º), não só no pesado do fim do combo.
		var heavy_cut: bool = bool(g._melee_action.get("heavy", g._rig_pose.heavy_attack())) or id in g.NATIVE_SWORDS or (id == "katana" and is_instance_valid(g.rage) and g.rage.active)
		# Projeta o golpe sobre a vítima em vez de escolher um membro fixo do combo.
		var closest := origin + direction * maxf(0.0, direction.dot(target - origin)) if was_living else target
		severed = g.katana_wounds.try_sever(actor, id, float(data.damage), heavy_cut, closest, direction)
	if not was_living and not severed: return false
	g._melee_hit_sound(id if id != "" else String(data.get("stance", "")), actor, target, float(data.damage), severed)
	if was_living:
		g._hit_effect({"collider": actor, "position": target, "normal": -direction}, float(data.damage), direction)
		g._melee_impact(actor, direction, id)
	else:
		# Post-mortem cuts produce no second damage/death/reward/crime event.
		g._rig_pose.impact(id)
		g.hitmarker_until = g._combat_clock + 0.16
	return true

## Peso do contato: o golpe trava no alvo (hit-stop), a câmera dá um tranco e a
## vítima viva é empurrada no sentido do golpe. Só apresentação: o dano já entrou.
func _melee_impact(actor: Node3D, direction: Vector3, id: String) -> void:
	var heavy := bool(g._melee_action.get("heavy", g._rig_pose.heavy_attack()))
	var factor: float = g.HEAVY_IMPACT if heavy else 1.0
	g._rig_pose.impact(id)
	g._kick_camera(float(g.MELEE_KICK.get(id, 0.0)) * factor)
	if not actor is CharacterBody3D or actor == g.player or actor.get("dead") == true or g._is_invulnerable(actor): return
	var distance: float = float(g.MELEE_SHOVE.get(id, 0.0)) * factor * (g.SHIELD_KICK_SHOVE if g._shield_kicking and id == "sword_shield" else 1.0)
	if distance <= 0.0: return
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	# Velocidade decrescendo linearmente até zero: percorre `distance` em SHOVE_SECONDS.
	g._shoves.append({"id": actor.get_instance_id(), "velocity": flat * (2.0 * distance / g.SHOVE_SECONDS), "age": 0.0})

func _update_shoves(delta: float) -> void:
	if g._shoves.is_empty(): return
	var remaining: Array[Dictionary] = []
	for shove in g._shoves:
		var body := instance_from_id(int(shove.id)) as CharacterBody3D
		if body == null or not is_instance_valid(body) or body.get("dead") == true: continue
		var age := float(shove.age)
		var speed := maxf(0.0, 1.0 - age / g.SHOVE_SECONDS)
		# Com colisão: parede ou carro seguram a vítima em vez de atravessá-la.
		body.move_and_collide((shove.velocity as Vector3) * speed * delta)
		shove.age = age + delta
		if float(shove.age) < g.SHOVE_SECONDS: remaining.append(shove)
	g._shoves = remaining

## Rastro de movimento do taco/machado só no trecho rápido do golpe.
func _update_swing_trail(delta: float) -> void:
	var id: String = g.equipped()
	if id not in ["axe", "bat"] or not is_instance_valid(g.gun):
		g._swing_trail = null
		return
	if not is_instance_valid(g._swing_trail) or not g.gun.is_ancestor_of(g._swing_trail):
		g._swing_trail = g.gun.find_child("AxeSwingTrail", true, false)
		if g._swing_trail == null: return
	g._swing_trail.update_trail(delta, bool(g._pose_frame.get("swing_trail", false)))
