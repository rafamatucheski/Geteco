extends RefCounted
## Tiro do Gameplay: o disparo (_stall_fire_at, em etapas), o contato adiado da granada e do golpe
## (_update_contact), a prévia da mira (aim_feedback), a obstrução da boca do cano, o coice, o clipe de
## pistola da UAL e o desligar do clarão e do lança-chamas. Separado em 01/11 (Onda 2 de
## docs/plano-divisao-arquivos-grandes-20261101.md) para o Gameplay.gd caber na leitura. O estado
## (cooldown, _pending_contact, _attack_serial, _in_pellet_volley, _recoil, _muzzle_timer...) e os sinais
## (weapon_fired, changed, message) continuam no Gameplay; fire_at, com o span gameplay.fire_at, também.
## Cada função antiga virou delegação de uma linha com a mesma assinatura e os mesmos padrões.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem _damage, _hit_effect,
## _play_stream, report_observed_crime, attack_allowed e equipped numa subclasse do Gameplay e o despacho
## tem de continuar igual.

const AUDIO := preload("res://gameplay/CombatAudio.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const MELEE_CONTROL := preload("res://gameplay/MeleeControl.gd")
const MELEE_FOLEY := preload("res://gameplay/MeleeFoley.gd")
const POSE := preload("res://gameplay/WeaponPoseData.gd")
const PROJECTILE := preload("res://gameplay/Projectile.gd")
const RIG_POSE := preload("res://gameplay/WeaponRigPose.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Apaga o clarão e para o rugido do lança-chamas quando o gatilho solta ou o ataque é bloqueado.
func _update_muzzle_and_flame(delta: float) -> void:
	if g._muzzle_timer > 0.0:
		g._muzzle_timer -= delta
		if g._muzzle_timer <= 0.0:
			if is_instance_valid(g._muzzle_flash): g._muzzle_flash.hide()
			if is_instance_valid(g._muzzle_light): g._muzzle_light.hide()
	if g._flame_clock > 0.0: g._flame_clock -= delta
	if g._flame_crime_clock > 0.0: g._flame_crime_clock -= delta
	g._prune_clock += delta
	if g._prune_clock >= g.REGISTER_PRUNE_INTERVAL:
		g._prune_clock = 0.0
		g._prune_combat_registers()
	if is_instance_valid(g._reload_audio) and g._reload_audio.playing and g.reload_timer <= 0.0: g._reload_audio.stop()
	if is_instance_valid(g._reload_audio) and g._reload_audio.playing and is_instance_valid(g.player): g._reload_audio.global_position = g.player.global_position
	if is_instance_valid(g._flame_audio) and g._flame_audio.playing and is_instance_valid(g.player): g._flame_audio.global_position = g.player.global_position
	if is_instance_valid(g._flame_audio) and g._flame_audio.playing and (g._flame_clock <= 0.0 or not g.attack_allowed() or g.equipped() != "flamethrower" or g.reload_timer > 0.0):
		g._flame_audio.stop()

## Clipe de arma de fogo da UAL. `rate` estica o clipe para caber no tempo real (recarga).
func _play_gun_clip(id: String, kind: String, rate: float = 1.0) -> void:
	var spec: Dictionary = g.GUN_CLIPS.get(id, {})
	if spec.is_empty() or not is_instance_valid(g.player) or not "animation" in g.player: return
	if g.player is CharacterBody3D and (g.player as CharacterBody3D).velocity.length() > g.GUN_CLIP_MAX_SPEED: return
	var animation: AnimationPlayer = g.player.animation
	if animation == null: return
	var start := 0.0
	var clip: String
	var end: float
	if kind == "shoot":
		clip = spec.shoot[0]; start = float(spec.shoot[1]); end = float(spec.shoot[2])
	else:
		clip = spec.reload
		if not animation.has_animation(clip): return
		end = animation.get_animation(clip).length
	if not animation.has_animation(clip): return
	g._clip_name = clip
	g._clip_start = start
	g._clip_end = end
	g._clip_age = 0.0
	g._clip_rate = rate
	g._clip_weapon = id

## Coice de arma de fogo com o `recoil` e a velocidade de retorno de `WeaponPoseData.PROFILES`.
func _update_recoil(delta: float) -> void:
	if g._recoil <= 0.0005:
		if g._recoil != 0.0:
			g._recoil = 0.0
		return
	var rate := float(POSE.PROFILES.get(g.equipped(), [Vector3.ZERO, Vector3.ZERO, 0.0, 12.0])[3])
	g._recoil *= exp(-rate * delta)

## Mesma boca do cano, trajetória horizontal, máscara e alcance do tiro, sem dispersão.
func aim_feedback() -> Dictionary:
	var origin: Vector3 = g.muzzle_world_position()
	var data: Dictionary = g.weapon_data(g.equipped())
	if not data.get("is_explosive", false) and not data.get("is_grenade", false) and not data.get("is_flame", false):
		var bridge: Dictionary = g._muzzle_obstruction(origin)
		if not bridge.is_empty():
			return {"point": bridge.position, "blocked": bridge.collider is CollisionObject3D and (bridge.collider.collision_layer & 1) != 0}
	var direction: Vector3 = g.aim_point - origin
	direction.y = 0.0
	if direction.length_squared() < 0.001: direction = Vector3.FORWARD
	var distance := minf(direction.length(), float(data.get("max_range", 420.0)) / 16.0)
	# Mantém o marcador do controle dentro do campo de visão útil. Os tiros mantêm o alcance total.
	var controls := g.get_node_or_null("/root/GameInput")
	if controls != null and (controls.using_gamepad or controls.get_meta("touch_controls_active", false) or not controls.touch_aim.is_zero_approx()): distance = minf(distance, 10.0)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * distance, 7, [g.player.get_rid()])
	var hit := g.get_world_3d().direct_space_state.intersect_ray(query)
	var blocked: bool = not hit.is_empty() and hit.collider is CollisionObject3D and (hit.collider.collision_layer & 1) != 0
	return {"point": hit.get("position", query.to), "blocked": blocked}

## Um cano longo pode atravessar uma parede antes que a cápsula de colisão do jogador
## chegue nela. Checa o caminho físico do peito do atirador até a boca do cano além do
## raio de saída, igual ao contrato de obstrução dos tiros de NPC.
func _muzzle_obstruction(origin: Vector3) -> Dictionary:
	var center: Vector3 = g.player.global_position + Vector3.UP * 1.1
	var bridge := PhysicsRayQueryParameters3D.create(center, origin, 7, [g.player.get_rid()])
	bridge.hit_from_inside = true
	return g.get_world_3d().direct_space_state.intersect_ray(bridge)

func _stall_fire_at(target: Vector3) -> bool:
	if not g.attack_allowed() or not g.free_play_ok() or not is_instance_valid(g.player) or g.player.input_locked:
		g._clear_melee_action()
		return false
	var id: String = g.equipped()
	if id.is_empty(): id = "fists"
	if not CATALOG.WEAPONS.has(id): return false
	if id != "fists" and not g.state.owns_weapon(id): return false
	var data: Dictionary = g.weapon_data(id)
	var melee_weapon: bool = data.get("is_melee", false)
	if g.cooldown > 0 or g.reload_timer > 0 or not g._pending_contact.is_empty():
		if melee_weapon and g.reload_timer <= 0 and g.cooldown <= MELEE_CONTROL.BUFFER_SECONDS:
			g._melee_buffer = {"id": id, "until": g._combat_clock + MELEE_CONTROL.BUFFER_SECONDS}
		return false
	g._melee_buffer.clear()
	g._melee_action.clear()
	g._melee_rate = MELEE_CONTROL.rate(id, float(CATALOG.WEAPONS[id].fire_interval), float(data.fire_interval)) if melee_weapon else 1.0
	var grenade: bool = data.get("is_grenade", false)
	var has_ammo: bool = int(g.state.get_ammo(id).get("magazine", 0)) > 0 if grenade else true
	if not melee_weapon and (not has_ammo or (not grenade and not g.state.consume_ammo(id, 1))):
		# V1 (`Player._shoot_towards`): pente vazio recarrega sozinho quando há reserva.
		g.cooldown = 0.25
		if not grenade: g._firefly_sound("weapons_fire", "dry_fire", g.player.global_position, -7.0, 20.0)
		if not g.reload_weapon(): g.message.emit("Sem munição.")
		return false
	_fire_commit(id, data, melee_weapon, grenade)
	g.aim_point = target
	var origin: Vector3 = g.muzzle_world_position()
	var direction := target - origin
	direction.y = 0
	if direction.length_squared() < 0.001: direction = Vector3.FORWARD
	direction = direction.normalized()
	if data.get("is_flame", false): origin = _flame_nozzle(origin, direction)
	var defense_ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * float(data.get("max_range", 420.0)) / 16.0, 7, [g.player.get_rid()])
	var muzzle_bridge: Dictionary = {}
	if not melee_weapon and not grenade and not data.get("is_explosive", false) and not data.get("is_flame", false):
		muzzle_bridge = g._muzzle_obstruction(origin)
	var defense_hit := muzzle_bridge if not muzzle_bridge.is_empty() else g.get_world_3d().direct_space_state.intersect_ray(defense_ray)
	var self_defense: bool = not defense_hit.is_empty() and defense_hit.collider.get_meta("gameplay_role", "") == "cobra"
	if "combat_facing" in g.player: g.player.combat_facing = atan2(-direction.x, -direction.z)
	elif is_instance_valid(g.player.visual): g.player.visual.rotation.y = atan2(-direction.x, -direction.z)
	if grenade:
		g._pending_contact = {"id": id, "target": target, "data": data, "time": RIG_POSE.GRENADE_RELEASE, "self_defense": self_defense}
	elif data.get("is_explosive", false): _fire_projectile(target, data, origin, direction)
	elif melee_weapon: _fire_melee(id, target, data, direction)
	else: _fire_volley(id, data, origin, direction, muzzle_bridge)
	if not melee_weapon and not grenade and not self_defense: _report_shot_crime(data)
	var tail_span := STALL_WORK.begin()
	g._play_gun_clip(id, "shoot")
	g.changed.emit()
	STALL_WORK.finish_slow("gameplay.fire_at.clip_changed", tail_span, 2000, g)
	return true

## Disparo aceito: cooldown, série do ataque, coice, sinal weapon_fired, som e clarão, nesta ordem.
func _fire_commit(id: String, data: Dictionary, melee_weapon: bool, grenade: bool) -> void:
	g.cooldown = float(data.fire_interval) / float(MELEE_CONTROL.profile(id).rate) if melee_weapon else float(data.fire_interval)
	g._attack_serial += 1
	g._aim_hold = g.AIM_HOLD + float(RIG_POSE.MELEE_CONTACT.get(id, 0.0))
	var bag_recoil: float = 3.0 if g.state.get("economy") != null and g.state.economy.grid_handbag() and not melee_weapon else 1.0
	g._rig_pose.attack(id, float(data.get("recoil_multiplier", 1.0))*bag_recoil)
	if not melee_weapon: g._recoil = float(POSE.PROFILES.get(id, [Vector3.ZERO, Vector3.ZERO, 0.0, 12.0])[2])*bag_recoil*float(data.get("recoil_multiplier", 1.0))
	if not melee_weapon and not grenade: g.weapon_fired.emit(id, g.player.global_position)
	# Spans por parte (27/10): `gameplay.fire_at` chegou a 33 ms num quadro (rodada de 24/10) sem dizer onde.
	var part_span := STALL_WORK.begin()
	if melee_weapon: g._melee_swing_sound(id, data)
	elif data.get("is_flame", false): g._flame_sound()
	elif grenade: g._firefly_sound("weapons_fire", "grenade_pin", g.player.global_position, -9.0, 14.0) # O arremesso e a munição acompanham a saída da mão.
	else: g._shot_sound(id, data)
	STALL_WORK.finish_slow("gameplay.fire_at.sound", part_span, 2000, g)
	part_span = STALL_WORK.begin()
	if not melee_weapon and not data.get("is_grenade", false): g._flash_muzzle(id)
	STALL_WORK.finish_slow("gameplay.fire_at.muzzle", part_span, 2000, g)

func _flame_nozzle(origin: Vector3, direction: Vector3) -> Vector3:
	# O bico lido acima ainda está na pose do quadro anterior; girando a mira, o
	# jato saía de lado ou de trás do Dante. Mantém altura e alcance do bico e o
	# gira para a direção nova.
	# Gira o bico real em torno do Dante pelo quanto a mira mudou desde o quadro
	# anterior. Antes o jato era recolocado no centro do corpo + direção x raio:
	# perdia o deslocamento lateral e a altura da arma na cintura e nascia no
	# ar à frente do peito, longe do lança-chamas (feedback de 25/09/2026).
	var barrel: Vector3 = -g.gun.global_basis.z if is_instance_valid(g.gun) else direction
	barrel.y = 0.0
	if barrel.length_squared() > 0.0001:
		var turn := barrel.normalized().signed_angle_to(direction, Vector3.UP)
		var offset: Vector3 = origin - g.player.global_position
		origin = g.player.global_position + offset.rotated(Vector3.UP, turn)
	# A pose do bico é do quadro anterior: andando, o jogador já avançou desde então e o jato nascia atrás da arma.
	origin += Vector3(g.player.velocity.x, 0.0, g.player.velocity.z) * g.get_physics_process_delta_time()
	return origin

## Foguete (a granada sai pela mão em _update_contact, depois de GRENADE_RELEASE).
func _fire_projectile(target: Vector3, data: Dictionary, origin: Vector3, direction: Vector3) -> void:
	var shot := PROJECTILE.new()
	shot.controller = g
	shot.shooter = g.player
	shot.grenade = data.get("is_grenade", false)
	shot.damage = data.damage
	shot.radius = float(data.blast_radius) / 16.0
	# V1: a granada dura 2,0 s e o alcance vem da distância até o alvo (60 px até
	# `throw_range`); o foguete não fere quem o disparou (`Bullet._trigger_explosion`).
	shot.fuse = g.GRENADE_FUSE if shot.grenade else float(data.max_range) / float(data.projectile_speed)
	shot.hurt_shooter = shot.grenade
	if shot.grenade:
		var flat_target := target - origin
		flat_target.y = 0
		var throw_distance := clampf(flat_target.length(), g.GRENADE_MIN_THROW, float(data.get("throw_range", 320.0)) / 16.0)
		shot.velocity = direction * (throw_distance * g.GRENADE_LANDING_SHARE / g.GRENADE_AIR_TIME)
		shot.velocity.y = 5.5
	else:
		shot.velocity = direction * float(data.projectile_speed) / 16.0
	g.add_child(shot)
	shot.global_position = origin
	if not shot.grenade: g.effects.backblast(origin, direction)

func _fire_melee(id: String, target: Vector3, data: Dictionary, direction: Vector3) -> void:
	# Golpe procedural da V1 (`WeaponRigPose`: socos alternados, soqueira em
	# quatro variações, faca, arco de ombro do machado/taco). Os clipes
	# `Attack`/`Punch_Forward_with_Both_Fists` do GLB moviam o corpo inteiro e
	# ignoravam a arma na mão; ficam fora do golpe.
	g._start_swing(data, direction)
	g._play_punch_clip(id)
	if id in g.NATIVE_SWORDS: g._play_katana_clip(id)
	var contact_time: float = g._katana_contact_time() if id in g.NATIVE_SWORDS else float(RIG_POSE.MELEE_CONTACT.get(id, 0.14))
	var profile: Dictionary = MELEE_CONTROL.profile(id)
	g._melee_action = {"id": id, "direction": direction, "locked": false, "contact": contact_time, "window": float(profile.window), "heavy": g._katana_combo == (2 if id == "sword_shield" else 1) if id in g.NATIVE_SWORDS else g._rig_pose.heavy_attack()}
	g._pending_contact = {"id": id, "target": target, "data": data, "time": contact_time}
	g._aim_hold = (contact_time + float(profile.window)) / g._melee_rate
	if (id in MELEE_FOLEY.WEAPONS or id in g.NATIVE_SWORDS) and not (id == "katana" and g.katana_style().saber) and not g._pending_swing.is_empty():
		var peak: float = {"knife": 0.08, "bat": 0.13, "katana": 0.11, "axe": 0.145, "sword_shield": 0.11}[id]
		g._pending_swing.time = maxf(0.0, contact_time - peak * g._melee_rate)

## Bala, chumbos e jato: um raio por chumbo; o dano de cada acerto sai em _fire_pellet_hit.
func _fire_volley(id: String, data: Dictionary, origin: Vector3, direction: Vector3, muzzle_bridge: Dictionary) -> void:
	g._in_pellet_volley = true
	var part_span := STALL_WORK.begin()
	if not data.get("is_flame", false):
		g.effects.weapon_shot(id, g.gun.to_global(Vector3(0.025, 0.05, -0.025)), direction, int(g.state.get_ammo(id).get("magazine", 0)))
	STALL_WORK.finish_slow("gameplay.fire_at.weapon_shot", part_span, 2000, g)
	# Chumbos no mesmo corpo viram UM respingo com o dano somado: oito respingos,
	# oito vozes de dor e até sete poças no mesmo cadáver (o corpo ainda está no
	# espaço de física durante a rajada) deixavam a escopeta estranha.
	var flesh_hits: Dictionary = {}
	var speed := Vector2(g.player.velocity.x, g.player.velocity.z).length()
	var spread: float = g._handling.shot_spread(id, data, g._combat_clock, speed, g.aim_active)
	for pellet in int(data.get("pellets", 1)):
		var ray_direction := direction.rotated(Vector3.UP, g._rng.randf_range(-spread, spread))
		var distance := float(data.get("max_range", 420.0)) / 16.0
		var query := PhysicsRayQueryParameters3D.create(origin, origin + ray_direction * distance, 7, [g.player.get_rid()])
		var hit := muzzle_bridge if not muzzle_bridge.is_empty() else g.get_world_3d().direct_space_state.intersect_ray(query)
		var end: Vector3 = hit.get("position", query.to)
		var shot_from: Vector3 = origin if muzzle_bridge.is_empty() else g.player.global_position + Vector3.UP * 1.1
		var shot_to: Vector3 = query.to if muzzle_bridge.is_empty() else end
		if not hit.is_empty():
			_fire_pellet_hit(hit, data, origin, end, shot_from, shot_to, ray_direction, flesh_hits)
		if data.get("is_flame", false):
			var reach := origin.distance_to(end)
			# O jato visual segue a mira com leque curto; o espalhamento de ±0,2 rad
			# do dano jogava cada pacote para um lado e a chama lia como borrifo.
			g.effects.flame(origin, direction.slerp(ray_direction, 0.3), reach)
			# Fogo no chão ao longo do fim do jato, não sempre na ponta do alcance:
			# errando o alvo, cada disparo acendia um foco a 8,75 m em leque.
			g.emergency.ignite(origin + ray_direction * reach * g._rng.randf_range(0.55, 1.0), g.player, 0.3)
		elif muzzle_bridge.is_empty():
			part_span = STALL_WORK.begin()
			g.effects.tracer(origin, end, float(data.get("projectile_speed", 920.0)) / 16.0, data.get("tracer_color", Color("ffe36b")), float(data.get("damage", 16.0)))
			STALL_WORK.finish_slow("gameplay.fire_at.tracer", part_span, 2000, g)
	part_span = STALL_WORK.begin()
	for entry in flesh_hits.values():
		g._hit_effect(entry.hit, entry.amount, entry.direction)
	STALL_WORK.finish_slow("gameplay.fire_at.flesh_effect", part_span, 2000, g)
	g._in_pellet_volley = false
	g._handling.fired(id, data, g._combat_clock)

## `flesh_hits` junta os chumbos no mesmo corpo (um respingo com o dano somado) até o fim da rajada.
func _fire_pellet_hit(hit: Dictionary, data: Dictionary, origin: Vector3, end: Vector3, shot_from: Vector3, shot_to: Vector3, ray_direction: Vector3, flesh_hits: Dictionary) -> void:
	var amount := CATALOG.distance_damage(int(data.damage), origin.distance_to(end) * 16.0, float(data.get("falloff_start", 0)), float(data.get("max_range", 420)), float(data.get("min_damage_ratio", 1)))
	if data.get("is_flame", false):
		if g._flame_hit_due(hit.collider):
			if g._can_ignite(hit.collider):
				g._ignite_actor(hit.collider as Node3D, g.player)
			g._damage(hit.collider, amount, g.player, true)
			if hit.collider is Node and String(hit.collider.get_meta("gameplay_role", "")) == "vehicle":
				var damage_look: Variant = hit.collider.get("damage_look")
				if is_instance_valid(damage_look) and damage_look.has_method("ignite"): damage_look.ignite(g.player)
	else:
		var part_span := STALL_WORK.begin()
		g.damage_bullet(hit.collider, amount, g.player, shot_from, shot_to, end, data)
		STALL_WORK.finish_slow("gameplay.fire_at.damage", part_span, 2000, hit.collider as Node)
		g.confirm_player_hit(hit.collider, amount)
		part_span = STALL_WORK.begin()
		g._impact_sound(hit.collider, end, float(amount), hit.normal)
		STALL_WORK.finish_slow("gameplay.fire_at.impact_sound", part_span, 2000, g)
		if g._impact_material(hit.collider) == "flesh":
			var key: int = hit.collider.get_instance_id()
			if flesh_hits.has(key): flesh_hits[key].amount += float(amount)
			else: flesh_hits[key] = {"hit": hit, "amount": float(amount), "direction": ray_direction}
		else:
			part_span = STALL_WORK.begin()
			g._hit_effect(hit, float(amount), ray_direction)
			STALL_WORK.finish_slow("gameplay.fire_at.hit_effect", part_span, 2000, hit.collider as Node)

func _report_shot_crime(data: Dictionary) -> void:
	if data.get("is_flame", false):
		# Jato contínuo: a denúncia do disparo acompanha o tempo, não os 20 disparos por segundo.
		if g._flame_crime_clock <= 0.0:
			g._flame_crime_clock = g.FLAME_SHOT_CRIME_INTERVAL
			g.report_observed_crime(4, g.player.global_position, "gunfire")
	else:
		var crime_span := STALL_WORK.begin()
		g.report_observed_crime(1 if data.get("suppressed", false) else 4, g.player.global_position, "suppressed" if data.get("suppressed", false) else "gunfire")
		STALL_WORK.finish_slow("gameplay.fire_at.crime", crime_span, 2000, g)

## Resolve o contato na posição atual, uma vez, no mesmo tempo da pose. Pausa
## congela ambos; troca de arma, morte, garagem e transição cancelam a ação.
func _update_contact() -> void:
	if g._pending_contact.is_empty(): return
	var id: String = g._pending_contact.id
	var current_id: String = g.equipped()
	if current_id.is_empty(): current_id = "fists"
	if not g.attack_allowed() or not g.free_play_ok() or g.player.input_locked or current_id != id:
		g._pending_contact.clear()
		g._clear_melee_action()
		return
	if g._rig_pose.action_age + 0.00001 < float(g._pending_contact.time): return
	var contact: Dictionary = g._pending_contact
	var origin: Vector3 = g.player.global_position + Vector3.UP * 1.05
	var direction: Vector3 = contact.target - origin
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	if id != "grenade":
		if not g._melee_action.is_empty():
			g._melee_action.locked = true
			direction = g._melee_action.direction
		var hit: bool = g.melee(origin, direction, contact.data, id)
		if hit or g._rig_pose.action_age >= float(contact.time) + float(MELEE_CONTROL.profile(id).window):
			g._pending_contact = {}
		return
	g._pending_contact = {}
	if not g.state.consume_ammo(id, 1): return
	if g._weapon_visuals._player_rig(): origin = g.player.combat_palm_position("Right")
	var flat_target: Vector3 = contact.target - origin
	flat_target.y = 0.0
	direction = flat_target.normalized() if flat_target.length_squared() > 0.001 else direction
	var shot := PROJECTILE.new()
	shot.controller = g
	shot.shooter = g.player
	shot.grenade = true
	shot.damage = contact.data.damage
	shot.radius = float(contact.data.blast_radius) / 16.0
	shot.fuse = g.GRENADE_FUSE
	shot.hurt_shooter = true
	var distance := clampf(flat_target.length(), g.GRENADE_MIN_THROW, float(contact.data.get("throw_range", 320.0)) / 16.0)
	shot.velocity = direction * (distance * g.GRENADE_LANDING_SHARE / g.GRENADE_AIR_TIME)
	shot.velocity.y = 5.5
	g.add_child(shot)
	shot.global_position = origin
	g._play_stream(AUDIO.grenade_throw(), origin, 0.0)
	g.weapon_fired.emit(id, origin)
	if not contact.self_defense: g.report_observed_crime(4, g.player.global_position, "explosion")
	g.changed.emit()
