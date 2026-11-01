extends RefCounted
## Dano e crimes do Gameplay: dano em atores e veículos (damage_bullet, _stall_damage), fogo em pessoas,
## dano no jogador (colete, escudo, morte, cura) e a denúncia de cada agressão sem contar o mesmo ataque
## duas vezes (_crime_due, atropelamento, civil morto) com a limpeza dos registros
## por vítima. Separado em 01/11 (Onda 2 de docs/plano-divisao-arquivos-grandes-20261101.md) para o
## Gameplay.gd caber na leitura. O estado (health, armor, _crime_window, _crime_attack, _police_kill_reported,
## _vehicle_contact...) e os sinais (changed, player_wounded, player_died) continuam no Gameplay; _damage,
## com o span gameplay.damage, também. Cada função antiga virou delegação de uma linha com a mesma
## assinatura e os mesmos padrões. A procura em si (register_crime, estrelas) e a denúncia de policial ferido
## ou morto (_report_police_assault/_report_police_killed) foram para gameplay/GameplayPolice.gd (Onda 3).
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem _damage,
## _play_glass_break, report_observed_crime e police_* numa subclasse do Gameplay e o despacho tem de
## continuar igual.

const CRIME_VICTIMS := preload("res://gameplay/police_response/CrimeVictims.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Pessoas que pegam fogo: qualquer corpo vivo que receba dano, exceto o jogador e veículos. Antes só o papel
## "civilian" acendia, e a maioria dos moradores é "urban_routine"/"ambient_worker", além de policiais e seguranças.
func _can_ignite(target: Object) -> bool:
	if not target is CharacterBody3D or target == g.player or PROTECTION.is_protected(target): return false
	var role := String((target as Node).get_meta("gameplay_role", ""))
	return role != "vehicle" and role != "player" and (target as Node).has_method("receive_damage")

func _ignite_actor(actor: Node3D, source: Node) -> void:
	if not is_instance_valid(actor) or actor.get("dead") == true: return
	if not actor.has_method("receive_damage") or actor == g.player: return
	var effect := actor.get_node_or_null("V2Burning")
	if effect == null:
		var active := g.get_tree().get_nodes_in_group("v2_burning_actor").size()
		if active >= 24: return
		effect = preload("res://gameplay/BurningActor.gd").new()
		effect.name = "V2Burning"
		effect.configure(actor, g, source)
		actor.add_child(effect)
		actor.set_meta("v2_burning", true)
		var reactions: Node = g.world.get_node_or_null("CivilianReactionDirector")
		if not is_instance_valid(reactions):
			var production: Node = g.world.get("production")
			reactions = production.get("civilian_reactions") if production != null else null
		if is_instance_valid(reactions) and reactions.has_method("report_assault"):
			reactions.report_assault(actor, source)
	else:
		effect.ignite(source)

## Um golpe do V1 do lança-chamas por alvo a cada 120 ms (o jato V2 é um raio a 20 Hz).
func _flame_hit_due(target: Object) -> bool:
	if not is_instance_valid(target): return false
	var id := target.get_instance_id()
	if g._combat_clock - float(g._flame_hit_at.get(id, -g.FLAME_HIT_COOLDOWN)) < g.FLAME_HIT_COOLDOWN: return false
	g._flame_hit_at[id] = g._combat_clock
	return true

## Crime por ferir alguém, sem contar a mesma agressão duas vezes: chumbos do mesmo tiro (ou golpes da
## mesma explosão) são uma denúncia por vítima; fonte contínua (`continuous`) só denuncia de novo depois
## de CONTINUOUS_CRIME_COOLDOWN. Um golpe discreto novo (bala, faca) sempre denuncia.
func _crime_due(victim: Object, continuous: bool) -> bool:
	var id := victim.get_instance_id()
	if continuous:
		if float(g._crime_window.get(id, -1.0)) > g._combat_clock: return false
		g._crime_window[id] = g._combat_clock + g.CONTINUOUS_CRIME_COOLDOWN
	elif g._in_pellet_volley and int(g._crime_attack.get(id, -1)) == g._attack_serial: return false
	g._crime_attack[id] = g._attack_serial
	return true

## Atropelamento com o veículo do jogador (chamado por `Actor.receive_damage` depois de o `Vehicle`
## bater na vítima). A atribuição continua em `Vehicle.is_player_damage_source()`: tráfego, viaturas de
## despacho (`external_input`) e carros sem o jogador ao volante NUNCA denunciam o jogador.
## Regra: um crime por vítima por contato. Cada chamada renova o contato; só depois de
## VEHICLE_CONTACT_GAP sem contato um novo atropelamento denuncia de novo. O valor (25) é o do V2;
## o V1 denunciava 6 (vítima sobrevive) ou 20 (fatal), uma única vez.
func report_vehicle_assault(victim: Node3D, vehicle: Node) -> void:
	if not is_instance_valid(victim) or not is_instance_valid(vehicle): return
	if not vehicle.has_method("is_player_damage_source") or not vehicle.is_player_damage_source(): return
	var id := victim.get_instance_id()
	var last := float(g._vehicle_contact.get(id, -INF))
	g._vehicle_contact[id] = g._combat_clock
	var new_contact: bool = g._combat_clock - last > g.VEHICLE_CONTACT_GAP
	# Mesma tabela do dano de arma: Cobra e segurança de comboio não viram homicídio de civil.
	# Papel desconhecido continua valendo pessoa aqui: só Actor (pedestre) chega a esta função.
	var victim_class := CRIME_VICTIMS.classify(victim)
	if not CRIME_VICTIMS.reports_crime(victim_class): return
	if victim_class == CRIME_VICTIMS.POLICE:
		if new_contact: g._report_police_assault(victim)
		if victim.get("dead") == true: g._report_police_killed(victim)
		return
	if victim.get("dead") == true:
		g._report_civilian_killed(victim, victim.global_position)
	elif new_contact: g.report_observed_crime(25, victim.global_position, "vehicle_assault", victim)

func _report_civilian_killed(victim: Node3D, crime_point: Vector3 = Vector3.INF) -> void:
	# Same bounded per-victim death ledger as officers; a corpse is not a new crime.
	var id := victim.get_instance_id()
	if g._police_kill_reported.has(id): return
	g._police_kill_reported[id] = true
	# Ver um corpo distante não é ver quem atirou. Impactos de veículo informam o
	# local da colisão; dano de arma precisa identificar a posição de tiro do jogador.
	var observed: Vector3 = g.player.global_position if crime_point == Vector3.INF else crime_point
	g.report_observed_crime(30, observed, "civilian_killed", victim)

## Registros por vítima são inteiros (ids de instância), não referências: mesmo assim expiram por tempo,
## saem quando o ator deixa de existir e são zerados na troca de região.
func _prune_combat_registers() -> void:
	for id in g._crime_window.keys():
		if float(g._crime_window[id]) <= g._combat_clock or not is_instance_id_valid(int(id)): g._crime_window.erase(id)
	for id in g._flame_hit_at.keys():
		if g._combat_clock - float(g._flame_hit_at[id]) > 1.0 or not is_instance_id_valid(int(id)): g._flame_hit_at.erase(id)
	for id in g._vehicle_contact.keys():
		if g._combat_clock - float(g._vehicle_contact[id]) > g.VEHICLE_CONTACT_GAP or not is_instance_id_valid(int(id)): g._vehicle_contact.erase(id)
	for id in g._police_kill_reported.keys():
		if not is_instance_id_valid(int(id)): g._police_kill_reported.erase(id)
	for id in g._pain_next.keys():
		if float(g._pain_next[id]) <= g._combat_clock or not is_instance_id_valid(int(id)): g._pain_next.erase(id)
	for id in g._crime_attack.keys():
		if not is_instance_id_valid(int(id)): g._crime_attack.erase(id)
	if g._crime_attack.size() > 128: g._crime_attack.clear()
	g._recent_impacts = g._recent_impacts.filter(func(entry): return g._combat_clock - float(entry.time) < g.IMPACT_GROUP_SECONDS)

func _clear_combat_registers() -> void:
	g._crime_window.clear()
	g._crime_attack.clear()
	g._flame_hit_at.clear()
	g._vehicle_contact.clear()
	g._police_kill_reported.clear()
	g._recent_impacts.clear()
	g._pain_next.clear()
	g._flame_crime_clock = 0.0

## `weapon`: dados da arma que atirou (PoliceAgent.scale_bullet_damage lê o calibre para o colete).
func damage_bullet(actor: Object, amount: float, source: Node, shot_from := Vector3.INF, shot_to := Vector3.INF, hit_point := Vector3.INF, weapon: Dictionary = {}) -> void:
	# Lataria absorve 85% dos tiros, inclusive cada chumbo de escopeta.
	# Mantém durabilidade, blindagem, colisões, fogo e explosões independentes.
	if is_instance_valid(actor) and actor is Node and actor.get_meta("gameplay_role", "") == "vehicle":
		if actor is Node3D and shot_from.is_finite() and shot_to.is_finite():
			var glass := preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").owner_for(actor,true)
			var broken: Dictionary = glass.shoot(shot_from,shot_to)
			if not broken.is_empty():
				# Rachadura (26/10): lascas de impacto e um estalo baixo; a chuva de cacos e o som cheio só
				# quando o painel cai.
				if broken.get("shattered",true):
					if is_instance_valid(g.effects): g.effects.glass_shatter(broken.point,broken.normal)
					g._play_glass_break(broken.point)
				else:
					if is_instance_valid(g.effects): g.effects.impact(broken.point,broken.normal,"glass",amount)
					g._play_glass_break(broken.point,-9.0,1.25)
			# Bala que passa rente ao centro de uma roda fura aquele pneu (com o estouro dele). O teste vai
			# só 0,9 m além do impacto: tiro na porta não atravessa o carro e fura a roda do outro lado.
			var tire_to := shot_to if not hit_point.is_finite() else hit_point + (shot_to - shot_from).normalized() * .9
			preload("res://gameplay/police_response/ground/TirePuncture.gd").shoot(actor,shot_from,tire_to)
			# Motorista do trânsito sentado: ferido, morto ou sai e foge (TrafficDriverPool).
			preload("res://gameplay/traffic/TrafficDriverPool.gd").bullet_hit(g.world,actor,shot_from,shot_to,source)
		amount *= 0.15
	elif is_instance_valid(actor) and actor.has_method("scale_bullet_damage") and not g._is_invulnerable(actor):
		# Policial: cabeça × colete (PoliceAgent). Jogador, civis e demais NPCs não têm o método e não mudam.
		amount = actor.scale_bullet_damage(amount, hit_point, weapon)
	g._damage(actor, amount, source)

func _stall_damage(actor: Object, amount: float, source: Node, continuous: bool = false) -> void:
	if g._is_invulnerable(actor): return
	if actor == g.player:
		g.damage_player(amount)
	elif is_instance_valid(actor) and actor.has_method("receive_damage"):
		var was_dead: bool = actor.get("dead") == true
		actor.receive_damage(amount, source)
		var role := String(actor.get_meta("gameplay_role", "")) if actor is Node else ""
		var killed: bool = not was_dead and actor.get("dead") == true
		if killed and actor is Node3D: g._death_voice(actor as Node3D)
		if actor is Node3D and role == "civilian" and not killed and source is Node3D:
			var reactions: Node = g.world.get_node_or_null("CivilianReactionDirector") if is_instance_valid(g.world) else null
			if is_instance_valid(reactions): reactions.report_assault(actor, source)
		if actor is Node3D and role in ["civilian", "emergency"]:
			g.emergency.report_injury(actor, actor.get("dead") == true)
		var victim_class := CRIME_VICTIMS.classify(actor)
		if source == g.player and not was_dead and CRIME_VICTIMS.reports_crime(victim_class):
			if victim_class == CRIME_VICTIMS.POLICE:
				if g._crime_due(actor, continuous): g._report_police_assault(actor as Node3D)
				if killed: g._report_police_killed(actor as Node3D)
			elif killed and CRIME_VICTIMS.killing_is_murder(victim_class):
				g._report_civilian_killed(actor as Node3D)
			elif g._crime_due(actor, continuous):
				g.report_observed_crime(12, g.player.global_position, "assault", actor as Node3D)

## `from` é a posição de quem causou o dano (INF se não houver); a morte cai no lado oposto.
func damage_player(amount: float, from := Vector3.INF) -> void:
	g._apply_player_damage(g._shield_blocked(amount, from), true, from)

## Escudo levantado e ataque vindo da frente: sobra só SHIELD_BLOCK_SHARE do dano.
func _shield_blocked(amount: float, from: Vector3) -> float:
	if not g.shield_block or not from.is_finite() or not is_instance_valid(g.player) or not is_finite(amount): return amount
	var toward: Vector3 = from - g.player.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.0001: return amount
	var facing: Vector3 = -g.player.visual.global_basis.z
	facing.y = 0.0
	if facing.normalized().dot(toward.normalized()) < g.SHIELD_BLOCK_CONE: return amount
	g.player.set_meta("shield_block_frame", Engine.get_physics_frames())
	return amount * g.SHIELD_BLOCK_SHARE

func damage_environment(amount: float) -> void:
	# Frio e outros danos ambientais não consomem colete balístico nem geram crime.
	g._apply_player_damage(amount, false)

func _apply_player_damage(amount: float, use_armor: bool, from := Vector3.INF) -> void:
	if g.god_mode: return
	if not is_finite(amount) or amount <= 0 or g.health <= 0 or g.state == null or not g.state.weapons_allowed(): return
	var absorbed: float = minf(g.armor, amount * 0.65) if use_armor else 0.0
	g.armor -= absorbed
	if absorbed > 0.0 and is_instance_valid(g.player): g.player.set_meta("armor_hit_frame", Engine.get_physics_frames())
	var prior_health: float = g.health
	g.health = maxf(0, g.health - (amount - absorbed))
	if use_armor and is_instance_valid(g.rage): g.rage.add_damage(prior_health - g.health + absorbed)
	# Dano ambiental não é ferida aberta, mesmo quando é letal.
	if use_armor: g.player_wounded.emit(g.health <= 0.0)
	if g.health > 0.0:
		g._pain_voice(g.player, amount)
		if use_armor and g.player.has_method("present_hit"): g.player.present_hit()
	g.changed.emit()
	if g.health == 0 and not g._dead_notified:
		if is_instance_valid(g.rage): g.rage.cancel("death")
		g._clear_chain_explosions()
		g._dead_notified = true
		g.player.input_locked = true
		if use_armor and is_instance_valid(g.effects): g.effects.stain(g.player.global_position, 0.8)
		var push: Vector3 = g.player.global_position - from if from.is_finite() else Vector3.ZERO
		if g.player.has_method("on_player_death"): g.player.on_player_death(-1, push)
		g.player_died.emit()

func heal(amount: float) -> bool:
	if amount <= 0 or g.health <= 0 or g.health >= 100: return false
	g.health = minf(100, g.health + amount)
	g.changed.emit()
	return true

func confirm_player_hit(collider: Object, amount: float) -> void:
	if amount <= 0.0 or not is_instance_valid(collider) or g._is_invulnerable(collider): return
	if collider.has_method("receive_damage") or collider.has_method("receive_impact"):
		g.hitmarker_until = g._combat_clock + 0.16
