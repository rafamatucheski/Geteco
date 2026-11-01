extends RefCounted
## Partida de uma viatura de despacho: soltar a ocorrência, esperar a equipe a pé, planejar a rota de
## saída, fuga de travamento, aposentadoria à vista como último recurso e remoção longe e fora da
## vista. Separado de DispatchUnit.gd em 01/11 só para o dono caber na leitura. O estado
## (_departure_*, _stranded, stranded_age, stranded, _escape_retry, _retirement) continua em
## DispatchUnit, porque testes e DispatchController leem esses campos lá; o dono mantém cada função
## antiga como delegação de uma linha com a mesma assinatura. Tudo estático: a unidade é RefCounted, e
## um auxiliar com `var g` guardado faria ciclo de referência que nunca é liberado. Cada função recebe
## a unidade em `g` (RefCounted, e não o script do dono, para não criar preload cíclico) e passa por
## `g.` até nas chamadas entre funções deste arquivo.

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")

static func _begin_departure(g: RefCounted) -> void:
	g.stop_planner.reset()
	if is_instance_valid(g.vehicle): g.vehicle.set_meta("dispatch_needs_room",true)
	if g.is_police() and g.driver != null: g._calm_driving()
	if g.is_police() and g.crew_remaining <= 0 and g.officers.is_empty():
		g._police_crew_depleted()
		return
	g._release_incident()
	g._set_siren(false)
	g._departure_clock = 0.0
	g._stranded = 0.0
	g.stranded_age = 0.0
	g.stranded = false
	if is_instance_valid(g.crew):
		# Equipe ainda a pé: cancelamento. Volta à viatura e a viatura só parte com ela.
		g.crew.mode = "return"
		g.crew.age = 0.0
		if g.state != "working": g._set_state("working")
		return
	if not g.officers.is_empty():
		g._begin_recall(false)
		return
	g._set_state("departing")
	g.driver.hold(false)
	# Redirecionamento com o veículo em jogo: recuperação física (para e volta à
	# faixa com curva validada), nunca descarte que o deixe atravessado.
	g.driver.cancel_overtaking("departure")
	g._plan_departure()

static func _plan_departure(g: RefCounted) -> void:
	var player_position: Vector3 = g.controller.player_position()
	var heading: Vector3 = -g.vehicle.global_basis.z
	var traced := TRACE.begin()
	var result: Dictionary = g.controller.router.plan_departure(g.vehicle.global_position, player_position, RULES.RECYCLE_DISTANCE + 25.0, heading)
	TRACE.end("router.plan_departure", traced)
	if result.ok:
		var departure: Curve3D = g.stop_planner.departure_curve(g.vehicle,result.curve)
		g.driver.set_route(departure)
		if departure==null: g.controller.emit_dispatch_event("departure_merge_blocked",{"unit":g})
		g._stranded = 0.0
	else:
		g.driver.set_route(null)
		g._stranded += 1.0
		g.controller.emit_dispatch_event("departure_blocked", {"unit": g, "reason": result.reason})

static func _tick_departing(g: RefCounted, delta: float) -> void:
	g._departure_clock += delta
	g.driver.hold(g.driver.route == null)
	g.driver.tick(delta)
	if g._departure_origin==Vector3.INF: g._departure_origin=g.vehicle.global_position
	var departure_progress: float = g.vehicle.global_position.distance_to(g._departure_origin)
	if departure_progress>g._departure_best+3:
		g._departure_best=departure_progress
		g._departure_anchor=g.vehicle.global_position
		g._departure_stall=0
		g._retirement=0
		g.vehicle.fade_traffic_retirement(0)
	elif absf(g.vehicle.speed)<.6: g._departure_stall+=delta
	g._escape_retry-=delta
	if g._departure_stall>6 and g._escape_retry<=0 and g.driver.route!=null and not g.driver.pending_recovery():
		g._escape_retry=2
		var escape: Curve3D=preload("res://gameplay/TrafficEscapePlanner.gd").plan(g.vehicle,g.driver.route)
		if escape!=null:
			g.driver.discard_overtaking("departure_escape")
			g.driver.set_route(escape)
			g.vehicle.set_meta("dispatch_escape_active",true)
			g.controller.emit_dispatch_event("departure_escape",{"unit":g})
	if g.vehicle.get_meta("dispatch_escape_active",false) and g.driver.route!=null and g.driver.offset>=float(g.driver.route.get_meta("traffic_escape_until",0)):
		g.vehicle.remove_meta("dispatch_escape_active")
	# Uma resposta partindo e desocupada pode ser aposentada à vista como último recurso,
	# como pedido: o casco sólido fica até o fim do fade curto.
	if g._departure_stall>=28 or g._departure_clock>=45:
		g._retirement+=delta
		g.driver.hold(true)
		g.vehicle.fade_traffic_retirement(minf(1,g._retirement))
		if g._retirement>=1:
			g.finish("departure_escape_removed")
			return
	var unseen: bool = g.controller.is_unseen(g.vehicle.global_position)
	var distance: float = g.controller.distance_to_player(g.vehicle.global_position)
	if unseen and distance > RULES.RECYCLE_DISTANCE:
		g.finish("left")
		return
	# Partida travada por recuperação física que não sai (faixa contrária, motor bloqueado,
	# rota nula): sem isto a viatura ocuparia a vaga de unidade até `departure_timeout`.
	# A recuperação continua enquanto ela existir; só a REMOÇÃO IMEDIATA acontece, e
	# apenas fora da vista, para não sumir na frente do jogador.
	if g._recovery_blocked(): g.stranded_age += delta
	else: g.stranded_age = 0.0
	g.stranded = g.stranded_age >= RULES.STRANDED_SLOT_SECONDS
	if g.stranded_age >= RULES.STRANDED_REMOVAL_SECONDS and unseen and distance > 25.0:
		g.controller.emit_dispatch_event("recovery_stranded", {"unit": g, "status": g.driver.stop_status(), "reason": g.driver.overtake.unresolved_reason if g.driver.overtake.unresolved else g.driver.overtake.last_reason, "needs": g.driver.overtake.exit_condition()})
		g.finish("recovery_stranded")
		return
	if g.driver.route == null or g.driver.at_route_end():
		g._stranded += delta
		if g._stranded >= 3.0:
			g._stranded = 0.0
			g._plan_departure()
	if g._departure_clock > 180.0 and distance > 25.0 and unseen:
		g.finish("departure_timeout")
