extends RefCounted
## Suspensão distante de uma viatura de despacho: congelar, esconder e tirar da colisão o veículo e
## quem está a pé, reciclar a deixada para trás numa perseguição e retomar só com espaço livre.
## Separado de DispatchUnit.gd em 01/11 só para o dono caber na leitura. O estado (suspended,
## suspended_for, _resume_clear_time, _saved_*, _suspended_bodies) continua em DispatchUnit, porque
## testes e DispatchController leem esses campos lá; o dono mantém cada função antiga como delegação
## de uma linha com a mesma assinatura. Tudo estático: a unidade é RefCounted, e um auxiliar com
## `var g` guardado faria ciclo de referência (unidade -> auxiliar -> unidade) que nunca é liberado.
## Cada função recebe a unidade em `g` (RefCounted, e não o script do dono, para não criar preload
## cíclico) e passa por `g.` até nas chamadas entre funções deste arquivo: um teste que estenda
## DispatchUnit e sobrescreva alguma delas continua sendo despachado igual.

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")

## Distante do jogador o veículo congela, some da vista e sai da colisão para
## não virar obstáculo invisível. Depois de SUSPEND_RECYCLE_SECONDS é liberado.
static func _tick_suspension(g: RefCounted, delta: float) -> bool:
	var distance: float = g.controller.distance_to_player(g.vehicle.global_position)
	if not g.suspended:
		if distance <= RULES.SUSPEND_DISTANCE: return false
		if g._outrun(distance):
			# Deixada para trás numa perseguição: some fora da vista e libera a vaga para uma
			# nova nascer à frente. Congelada, ela segurava a vaga por até 45 s.
			g.controller.recycle_outrun(g)
			return true
		g.suspended = true
		g.suspended_for = 0.0
		g._resume_clear_time = 0.0
		g._saved_layer = g.vehicle.collision_layer
		g._saved_mask = g.vehicle.collision_mask
		g._saved_physics = g.vehicle.is_physics_processing()
		if is_instance_valid(g.vehicle.damage_look): g.vehicle.damage_look.suspend_for_dispatch()
		else:
			g.vehicle.collision_layer = 0
			g.vehicle.collision_mask = 0
		g.vehicle.velocity = Vector3.ZERO
		g.vehicle.speed = 0.0
		g.vehicle.set_physics_process(false)
		g.vehicle.hide()
		g._suspend_bodies()
		g.controller.emit_dispatch_event("unit_suspended", {"unit": g})
		return true
	g.suspended_for += delta
	if g._outrun(distance):
		# Suspensa numa pausa do contato e a perseguição voltou com ela longe: recicla agora,
		# em vez de segurar a vaga até os 45 s.
		g.controller.recycle_outrun(g)
		return true
	var traced := TRACE.begin()
	var resume_clear: bool = distance <= RULES.RESUME_DISTANCE and g.controller.footprint_clear(g.vehicle, g.vehicle.global_position, g.vehicle.rotation.y) and g._bodies_clear()
	TRACE.end("unit.resume_check", traced)
	if resume_clear:
		# Corpos estáticos recém-carregados entram no servidor de física no fim do
		# quadro. Exigir espaço livre por uma janela curta impede retomar sobre um
		# sólido que ainda não apareceu na primeira consulta do streaming.
		g._resume_clear_time += delta
	else:
		g._resume_clear_time = 0.0
	if g._resume_clear_time >= 0.12:
		g.suspended = false
		if is_instance_valid(g.vehicle.damage_look): g.vehicle.damage_look.resume_from_dispatch()
		else:
			g.vehicle.collision_layer = g._saved_layer
			g.vehicle.collision_mask = g._saved_mask
			g.vehicle.set_physics_process(g._saved_physics)
		g.vehicle.show()
		g._resume_bodies()
		g.controller.emit_dispatch_event("unit_resumed", {"unit": g})
		return false
	if g.suspended_for >= RULES.SUSPEND_RECYCLE_SECONDS:
		g.finish("suspended_too_long")
	return true

## Viatura em perseguição ativa (contato recente), sem equipe a pé, longe e fora da vista.
static func _outrun(g: RefCounted, distance: float) -> bool:
	if not PURSUIT.enabled or not g.is_police() or g.state != "enroute" or g.variant == "tank": return false
	if not g.officers.is_empty() or g.controller.gameplay.stars <= 0: return false
	if g.controller.gameplay.contact_age > PURSUIT.RECYCLE_CONTACT_AGE: return false
	# Longe também da última posição conhecida: quem está na área da busca fica (suspensa, como
	# antes). Sem isto, perder o contato longe dela reciclava as viaturas da busca e as novas,
	# que nascem perto dela, eram recicladas de novo (ciclo de criação de veículos).
	# Só na busca (contato perdido): com contato vivo a última posição é o próprio alvo, alguns metros
	# atrás dele, e a viatura deixada para trás ficaria "perto" dela (o laboratório pegou isso).
	if g.controller.gameplay.contact_age > 1.0 and g.controller.gameplay.last_known_valid and g._flat(g.vehicle.global_position, g.controller.gameplay.last_known) <= RULES.SUSPEND_DISTANCE: return false
	return distance > RULES.SUSPEND_DISTANCE and g.controller.is_unseen(g.vehicle.global_position)

## Policiais e socorristas a pé saem da física junto com a viatura: sem camada,
## sem máscara, sem processamento e sem vista.
static func _suspend_bodies(g: RefCounted) -> void:
	g._suspended_bodies.clear()
	var bodies: Array = g.officers.duplicate()
	if g.crew != null: bodies.append(g.crew)
	for body in bodies:
		if not is_instance_valid(body): continue
		var body_state := {"body":body,"layer":body.collision_layer,"mask":body.collision_mask,
			"physics":body.is_physics_processing(),"owner":null}
		g._suspended_bodies[body.get_instance_id()] = body_state
		var motion: Node = body.get_node_or_null("BodyFlight3D")
		if is_instance_valid(motion) and motion.has_method("suspend_for_dispatch"):
			motion.suspend_for_dispatch(body_state)
		body.collision_layer = 0
		body.collision_mask = 0
		body.velocity = Vector3.ZERO
		body.set_physics_process(false)
		body.hide()

## Cada pessoa viva precisa de cápsula livre no ponto onde ficou; senão a
## unidade inteira continua suspensa em vez de sobrepor um sólido novo.
static func _bodies_clear(g: RefCounted) -> bool:
	for body_state in g._suspended_bodies.values():
		# As referências podem ter sido liberadas por um efeito filho enquanto a unidade dormia.
		var body: Variant = body_state.body
		if not is_instance_valid(body) or body.is_queued_for_deletion() or body.dead: continue
		var exclude: Array[RID] = [g.vehicle.get_rid(), body.get_rid()]
		var motion: Node = body_state.owner.get_ref() if body_state.owner != null else null
		if is_instance_valid(motion):
			if not motion.suspension_clear(exclude): return false
		elif int(body_state.layer) != 0 and not g.controller.capsule_clear(body.global_position, exclude): return false
	return true

static func _resume_bodies(g: RefCounted) -> void:
	for body_state in g._suspended_bodies.values():
		var body: Variant = body_state.body
		if not is_instance_valid(body) or body.is_queued_for_deletion(): continue
		var motion: Node = body_state.owner.get_ref() if body_state.owner != null else null
		# A dead actor must release a paused child owner too; it cannot tick itself.
		if is_instance_valid(motion): motion.resume_from_dispatch()
		if body.dead:
			# Preserva o estado de colisão da morte; mantém o cadáver para o agente funerário.
			body.set_physics_process(false)
			body.show()
			continue
		body.collision_layer = int(body_state.layer)
		body.collision_mask = int(body_state.mask)
		body.set_physics_process(bool(body_state.physics))
		body.show()
	g._suspended_bodies.clear()
