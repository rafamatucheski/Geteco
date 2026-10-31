extends RefCounted
## Resposta limitada: no máximo duas barreiras físicas, uma tentativa de colocação a cada
## 18 segundos e três candidatos checados. Todas as posições vêm do grafo de vias.
const BLOCK := preload("res://gameplay/police_response/ground/PoliceRoadblock.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")
const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")
const PATH := preload("res://gameplay/dispatch/PursuitPath.gd")
const RADIO := preload("res://gameplay/dispatch/PursuitRadio.gd")
const MAX_AGE := 75.0
var controller: Node3D
var blocks: Array[Node3D] = []
var placement_clock := 10.0
var sample_clock := 0.0

func configure(owner: Node3D) -> void:
	controller = owner

func clear() -> void:
	for block in blocks:
		if is_instance_valid(block): block.queue_free()
	blocks.clear()
	placement_clock = 10.0

func tick(delta: float) -> void:
	var gameplay: Node3D = controller.gameplay
	var exterior: bool = controller.player_position_override == Vector3.INF and gameplay.state.weapons_allowed()
	var minimum_stars := PURSUIT.ROADBLOCK_MIN_STARS if PURSUIT.enabled else 4
	var pursuit: bool = gameplay.stars >= minimum_stars and gameplay.last_known_valid and exterior
	var surrendered: bool = gameplay.has_method("police_surrendering") and gameplay.police_surrendering()
	var target: Node3D = gameplay.pursuit_target() if pursuit and not surrendered else null
	var car: CharacterBody3D = target as CharacterBody3D if is_instance_valid(target) and "horizontal_velocity" in target else null
	sample_clock -= delta
	var sample := sample_clock <= 0.0
	if sample: sample_clock = .10
	for block in blocks.duplicate():
		if not is_instance_valid(block):
			blocks.erase(block)
			continue
		block.age += delta
		if not pursuit or surrendered or block.age >= MAX_AGE: block.set_armed(false)
		if (not pursuit or block.age >= MAX_AGE) and controller.is_unseen(block.global_position):
			blocks.erase(block)
			block.queue_free()
			continue
		if sample:
			if block.sample_target(car,pursuit and not surrendered and block.age < MAX_AGE):
				controller.emit_dispatch_event("tires_punctured",{"point":block.global_position})
	placement_clock = maxf(0.0,placement_clock-delta)
	var limit := 2 if gameplay.stars >= 5 else 1
	if not pursuit or surrendered or blocks.size() >= limit or placement_clock > 0.0: return
	placement_clock = 18.0
	var traced := TRACE.begin()
	var placed: Node3D = null
	# Carro em fuga à vista: o bloqueio vai no caminho previsto dele, 70-150 m à frente.
	if PURSUIT.enabled and car != null and gameplay.contact_age <= 1.0 and car.horizontal_velocity.length() > 8.0:
		placed = try_place_ahead(car.global_position, car.horizontal_velocity)
	if placed == null: placed = try_place(gameplay.last_known)
	if placed != null and PURSUIT.enabled:
		controller.announce("roadblock", RADIO.place(controller.router, placed.global_position))
	TRACE.end("roadblock.try_place", traced)

## Bloqueio no caminho provável do alvo (PursuitPath), fora da vista e numa rua larga o bastante.
## Os mesmos critérios de `try_place`, com a posição tirada da previsão em vez da última posição.
func try_place_ahead(position: Vector3, velocity: Vector3) -> Node3D:
	if controller.player_position_override != Vector3.INF or not controller.gameplay.state.weapons_allowed(): return null
	var prediction: Dictionary = PATH.predict(controller.routes, controller.router, position, velocity, PURSUIT.ROADBLOCK_AHEAD_MAX + 10.0)
	var distance := PURSUIT.ROADBLOCK_AHEAD_MIN
	var checked := 0
	while distance <= PURSUIT.ROADBLOCK_AHEAD_MAX and checked < 3:
		var sample: Dictionary = PATH.sample(prediction, distance)
		distance += PURSUIT.ROADBLOCK_AHEAD_STEP
		if sample.is_empty(): break
		var hit: Dictionary = controller.router.nearest_edge(sample.point, true, sample.heading)
		if hit.is_empty() or float(hit.distance) > 6.0: continue
		var edge: Dictionary = hit.edge
		var direction: Vector3 = (controller.routes.vertices[edge.to] - controller.routes.vertices[edge.from]).normalized()
		var yaw := atan2(-direction.x, -direction.z)
		var point: Vector3 = hit.closest - controller.routes._lane_offset(direction, edge)
		var width := clampf(float(edge.width) - .45, 6.0, 14.0)
		if float(edge.width) < 6.4 or controller.is_visible_to_player(point): continue
		var near_existing := false
		for other in blocks:
			if other.global_position.distance_to(point) < 35.0: near_existing = true
		if near_existing: continue
		checked += 1
		if not controller._space_clear(Vector3(width,1.15,2.0),point,yaw,controller.no_exclusions): continue
		var block := BLOCK.new()
		block.name = "PoliceRoadblock"
		controller.add_child(block)
		block.global_position = point+Vector3.UP*.025
		block.rotation.y = yaw
		block.build(width)
		blocks.append(block)
		controller.count_pursuit("roadblock_ahead")
		controller.emit_dispatch_event("roadblock_deployed",{"point":point,"width":width,"ahead":true})
		return block
	return null

func try_place(anchor: Vector3) -> Node3D:
	if controller.player_position_override != Vector3.INF or not controller.gameplay.state.weapons_allowed(): return null
	var candidates: Array = controller.router.spawn_candidates(anchor,38.0,95.0,14.0)
	var checked := 0
	for candidate in candidates:
		var edge: Dictionary = candidate.edge
		var yaw: float = candidate.yaw
		var direction := Vector3(-sin(yaw),0,-cos(yaw))
		var point: Vector3 = candidate.point-controller.routes._lane_offset(direction,edge)
		var width := clampf(float(edge.width)-.45,6.0,14.0)
		if float(edge.width) < 6.4 or controller.is_visible_to_player(point): continue
		var near_existing := false
		for other in blocks:
			if other.global_position.distance_to(point) < 35.0: near_existing = true
		if near_existing: continue
		checked += 1
		if checked > 3: break
		# A folga é checada sobre a formação completa, incluindo a faixa.
		if not controller._space_clear(Vector3(width,1.15,2.0),point,yaw,controller.no_exclusions): continue
		var plan: Dictionary = controller.router.plan(anchor,candidate.point)
		if not plan.ok or plan.length > 180.0: continue
		var block := BLOCK.new()
		block.name = "PoliceRoadblock"
		controller.add_child(block)
		block.global_position = point+Vector3.UP*.025
		block.rotation.y = yaw
		block.build(width)
		blocks.append(block)
		controller.emit_dispatch_event("roadblock_deployed",{"point":point,"width":width})
		return block
	return null
