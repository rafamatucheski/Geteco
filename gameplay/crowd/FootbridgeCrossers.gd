extends RefCounted
## Pedestres que atravessam as passarelas (`UrbanFootbridge3D`). As rotas comuns
## são de calçada (vai e volta entre dois pontos no chão); aqui cada passarela
## carregada perto do jogador ganha alguns civis num circuito de ida e volta
## chão → escada → tabuleiro → escada → chão. Eles entram em `world.people`,
## então reagem a tiro e somem como os demais; quem sumir é reposto.
const ACTOR := preload("res://scripts/Actor.gd")
const BRIDGE := preload("res://world/urban_detail/UrbanFootbridge3D.gd")
const PER_BRIDGE := 3
const ACTIVE_RADIUS := 90.0
# Passo além do pé da escada: o civil chega andando pela calçada, não brota nela.
const APPROACH := 3.0

var _crossers: Dictionary = {} # instance_id da passarela -> Array de atores

static func route_for(bridge: Node3D) -> PackedVector3Array:
	var half_deck: float = BRIDGE.span_for(bridge.length) * 0.5 + BRIDGE.LANDING
	var foot: float = half_deck + BRIDGE.run_length()
	var local := [
		Vector3(0, 0, foot + APPROACH), Vector3(0, 0, foot + 0.4),
		Vector3(0, BRIDGE.DECK_HEIGHT, half_deck - 0.4), Vector3(0, BRIDGE.DECK_HEIGHT, -half_deck + 0.4),
		Vector3(0, 0, -foot - 0.4), Vector3(0, 0, -foot - APPROACH)]
	# Circuito em palíndromo: o último ponto volta pelo mesmo caminho, nunca
	# cortando a rua em linha reta do fim para o começo.
	var loop := local.duplicate()
	for index in range(local.size() - 2, 0, -1): loop.append(local[index])
	var result := PackedVector3Array()
	for point in loop: result.append(bridge.global_transform * point)
	return result

func update(world: Node, focus: Vector3, region_id: String) -> void:
	var seen := {}
	for bridge in _bridges(world):
		if bridge.global_position.distance_to(focus) > ACTIVE_RADIUS: continue
		var key: int = bridge.get_instance_id()
		seen[key] = true
		var crew: Array = _crossers.get(key, [])
		crew = crew.filter(func(actor): return is_instance_valid(actor) and not actor.dead and actor.route.size() > 2)
		var route := route_for(bridge)
		while crew.size() < PER_BRIDGE:
			crew.append(_spawn(world, route, crew.size(), region_id))
		_crossers[key] = crew
	# Passarela descarregada ou longe: libera seus civis.
	for key in _crossers.keys():
		if seen.has(key): continue
		for actor in _crossers[key]:
			if is_instance_valid(actor):
				world.people.erase(actor)
				actor.queue_free()
		_crossers.erase(key)

func clear(world: Node) -> void:
	for crew in _crossers.values():
		for actor in crew:
			if is_instance_valid(actor):
				world.people.erase(actor)
				actor.queue_free()
	_crossers.clear()

func _bridges(world: Node) -> Array:
	var street: Node = world.get("street")
	if not is_instance_valid(street): return []
	return world.get_tree().get_nodes_in_group(BRIDGE.GROUP).filter(func(node): return node.is_inside_tree() and street.is_ancestor_of(node))

func _spawn(world: Node, route: PackedVector3Array, slot: int, region_id: String) -> Node3D:
	var actor = ACTOR.new()
	actor.identity = randi_range(0, 10000)
	actor.speed = randf_range(1.15, 1.6)
	actor.route = route
	# Espalha os civis pelo circuito: um em cada ponta e um no meio.
	var start: int = [0, 3, 6][slot % 3] % route.size()
	actor.waypoint = (start + 1) % route.size()
	actor.position = route[start] + Vector3.UP * 0.08
	actor.set_meta("region_id", region_id)
	actor.set_meta("footbridge_crosser", true)
	world.add_child(actor)
	world.people.append(actor)
	return actor
