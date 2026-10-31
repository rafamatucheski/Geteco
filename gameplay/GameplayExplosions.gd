extends RefCounted
## Explosões do Gameplay (dano em área, cadeia de detonações reentrantes fatiada por quadro), separadas
## em 31/10 para o Gameplay.gd caber na leitura. A fila, a profundidade e a época continuam no Gameplay
## (as cinco variáveis ficam junto dos campos que o Gameplay já declara); cada função antiga dele virou
## delegação de uma linha, então a ordem das chamadas é a mesma.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem algumas delas numa
## subclasse do Gameplay (_play_stream, _kick_camera, _hit_effect...) e o despacho tem de continuar igual.

const BLAST_QUERY := preload("res://gameplay/BlastQuery.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func explode(point: Vector3, radius: float, amount: float, source: Node3D, hurt_source: bool = true) -> void:
	# Explosives launched outside cannot cross the safe-zone boundary through a transition.
	if source == g.player and not g.state.weapons_allowed(): return
	var crusher: Node3D
	var damage_source := source
	var crushed := is_instance_valid(source) and source.has_meta("heavy_crush_ratio")
	if crushed:
		if source.get_meta("heavy_crush_exploded",false): return
		# Shared by destroyed listeners and Vehicle.crush's fallback. Mark first
		# so chained destruction cannot trigger the same wreck twice.
		source.set_meta("heavy_crush_exploded",true)
		if not g.state.weapons_allowed(): return
		var owner_ref: Variant = source.get_meta("heavy_crush_source",null)
		if owner_ref is WeakRef: crusher = owner_ref.get_ref() as Node3D
		if is_instance_valid(crusher):
			damage_source = g.player if crusher.has_method("is_player_damage_source") and crusher.is_player_damage_source() else crusher
	# Vehicle.destroyed pode reentrar enquanto a explosão atual ainda percorre
	# vítimas. Capture autoria/agressor agora; não releia o motorista depois.
	if g._explosion_depth > 0:
		g._chain_explosions.append({
			"point": point, "radius": radius, "amount": amount, "hurt_source": hurt_source,
			"source": weakref(source) if is_instance_valid(source) else null,
			"damage_source": weakref(damage_source) if is_instance_valid(damage_source) else null,
			"crusher": weakref(crusher) if is_instance_valid(crusher) else null,
			"frame": Engine.get_process_frames(), "context": g._active_explosion_context,
		})
		return
	g._run_explosion(point, radius, amount, source, hurt_source, crusher, damage_source)

func _run_explosion(point: Vector3, radius: float, amount: float, source: Node3D, hurt_source: bool, crusher: Node3D, damage_source: Node3D, context: Dictionary = {}) -> void:
	var previous_context: Dictionary = g._active_explosion_context
	# Snapshot imutável herdado pelos filhos. Um reset no meio do dano não
	# transfere explosões da cadeia antiga para o contexto recém-restaurado.
	g._active_explosion_context = context if not context.is_empty() else g._capture_explosion_context()
	g._explosion_depth += 1
	g._detonate_explosion(point, radius, amount, source, hurt_source, crusher, damage_source)
	g._explosion_depth -= 1
	g._active_explosion_context = previous_context

func _capture_explosion_context() -> Dictionary:
	var session: Variant = g.world.get("session") if is_instance_valid(g.world) else null
	return {
		"epoch": g._explosion_epoch, "state": weakref(g.state) if g.state != null else null,
		"region": g.state.get("region_id") if g.state != null else null,
		"place": g.state.get("place_id") if g.state != null else null,
		"session": weakref(session) if is_instance_valid(session) else null,
		"transition": session.get("transition_generation") if is_instance_valid(session) else null,
	}

func _detonate_explosion(point: Vector3, radius: float, amount: float, source: Node3D, hurt_source: bool, crusher: Node3D, damage_source: Node3D) -> void:
	var traced: int = Time.get_ticks_usec() if g.get_meta("trace_explosion",false) else 0
	g._sound("explosion", point, g.EXPLOSION_VOLUME_DB)
	# Cauda: o estrondo sozinho acabava seco; o rumor e os estilhaços caindo vêm por baixo dele.
	g._firefly_sound("weapons_fire", "explosion_tail", point, g.EXPLOSION_VOLUME_DB - 3.0, g.HEARING_EXPLOSION * 1.4, 0.05)
	traced = g._trace_explosion_cost("audio",traced)
	if g.emergency != null: g.emergency.ignite(point, damage_source, 1.0)
	traced = g._trace_explosion_cost("ground_fire",traced)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = point
	query.collision_mask = 6
	var seen: Dictionary = {}
	for result in BLAST_QUERY.intersect_bodies(g.get_world_3d().direct_space_state,query):
		var actor: Node3D = result.collider
		if is_instance_valid(crusher) and (actor == crusher or crusher.is_ancestor_of(actor)): continue
		if not hurt_source and (actor == source or actor.get_parent() == source): continue
		if seen.has(actor.get_instance_id()): continue
		seen[actor.get_instance_id()] = true
		var target := actor.global_position + Vector3.UP
		var ray := PhysicsRayQueryParameters3D.create(point, target, 1)
		if not g.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var falloff := clampf(1.0 - point.distance_to(target) / radius, 0, 1)
		g._damage(actor, amount * falloff, damage_source)
		g._hit_effect({"collider": actor, "position": target, "normal": Vector3.UP}, amount * falloff, (target - point).normalized())
	traced = g._trace_explosion_cost("damage",traced)
	if is_instance_valid(g.effects): g.effects.explosion(point, radius)
	traced = g._trace_explosion_cost("particles",traced)
	if is_instance_valid(g.player) and not (is_instance_valid(crusher) and damage_source == g.player): g._kick_camera(0.28 * clampf(1.0 - g.player.global_position.distance_to(point) / (radius * 4.0), 0.0, 1.0))
	# Um único evento por detonação admitida. A origem e a autoria são as mesmas
	# usadas pelo dano; `null` continua desconhecido e nunca vira jogador por inferência.
	g.explosion_occurred.emit(point, radius, damage_source)
	g._trace_explosion_cost("listeners",traced)

func _advance_chain_explosions() -> void:
	if g._chain_explosions.is_empty(): return
	if not g.is_inside_tree() or g.is_queued_for_deletion() or g.state == null or not g.enabled or g.health <= 0:
		g._clear_chain_explosions()
		return
	# Pausar conserva a cadeia; nenhum tempo de pausa consome ou executa eventos.
	if g.get_tree().paused: return
	if not g.state.weapons_allowed() or not is_instance_valid(g.world) or g.world.is_queued_for_deletion():
		g._clear_chain_explosions()
		return
	var session: Variant = g.world.get("session")
	if is_instance_valid(session):
		if session.get("ready_for_play") == false or (session.has_method("is_transition_blocked") and session.is_transition_blocked()):
			g._clear_chain_explosions()
			return
		if session.get("modal") == true: return
	var frame := Engine.get_process_frames()
	# Vários passos de física de recuperação não renovam o orçamento do quadro.
	if g._chain_pump_frame == frame: return
	g._chain_pump_frame = frame
	var began := Time.get_ticks_usec()
	var detonated := 0
	while not g._chain_explosions.is_empty() and detonated < g.CHAIN_EXPLOSIONS_PER_FRAME:
		if Time.get_ticks_usec() - began >= g.CHAIN_EXPLOSION_BUDGET_USEC: break
		var pending: Dictionary = g._chain_explosions[0]
		# Inclui filhos gerados pelo próprio pump: nunca detonam no mesmo quadro.
		if int(pending.frame) >= frame: break
		g._chain_explosions.pop_front()
		if not g._chain_explosion_context_matches(pending.context, session): continue
		# A fonte pode ter sido descarregada; a explosão admitida continua com
		# autoria desconhecida, sem manter o veículo/cadáver vivo artificialmente.
		g._run_explosion(pending.point, pending.radius, pending.amount,
			g._explosion_node(pending.source), pending.hurt_source,
			g._explosion_node(pending.crusher), g._explosion_node(pending.damage_source), pending.context)
		detonated += 1
		# Uma vítima ou um listener pode iniciar morte/resgate/transição agora.
		if not g.is_inside_tree() or g.is_queued_for_deletion() or not is_instance_valid(g.world) or g.world.is_queued_for_deletion():
			g._clear_chain_explosions()
			break
		if g.health <= 0 or not g.enabled or g.state == null or not g.state.weapons_allowed():
			g._clear_chain_explosions()
			break
		session = g.world.get("session")
		if is_instance_valid(session):
			if session.get("ready_for_play") == false or (session.has_method("is_transition_blocked") and session.is_transition_blocked()):
				g._clear_chain_explosions()
				break
			if session.get("modal") == true: break
		if g.get_tree().paused: break

func _chain_explosion_context_matches(context: Dictionary, session: Variant) -> bool:
	if int(context.epoch) != g._explosion_epoch or context.state == null or context.state.get_ref() != g.state: return false
	if context.region != g.state.get("region_id") or context.place != g.state.get("place_id"): return false
	if context.session == null: return not is_instance_valid(session)
	return is_instance_valid(session) and context.session.get_ref() == session \
		and context.transition == session.get("transition_generation")

func _clear_chain_explosions() -> void:
	g._chain_explosions.clear()
	g._explosion_epoch += 1
	# Não zera _explosion_depth: limpeza também pode ocorrer dentro do dano
	# de uma detonação em andamento, cujos próximos filhos ainda são reentrantes.

func _trace_explosion_cost(stage: String, started: int) -> int:
	if started == 0: return 0
	var ended := Time.get_ticks_usec()
	print("EXPLOSION_STAGE ",stage," ms=",float(ended-started)/1000.0)
	return Time.get_ticks_usec()
