extends "res://scripts/Actor.gd"
## Every route edge stays on open floor; Actor supplies swept CharacterBody physics.
var market: Node3D
var customer_index := 0
var stage := "browse"
var wait_time := 2.0
var route_points: Array[Vector3] = []
var route_index := 0
var goods: Node3D
var completed_purchases := 0
var shopping_model: Node3D
var browse_count := 0

func _ready() -> void:
	identity = 9200+customer_index*19
	controlled_automatically = true
	speed = 1.2
	super._ready()
	shopping_model = visual.get_child(0)
	# A cesta portátil e os produtos são filhos do visual do corpo, nunca do mundo.
	var basket := preload("res://world/places/supermarket/MarketGeometry.gd").new()
	visual.add_child(basket)
	# O Actor gira o modelo civil em PI: a frente dele é -Z visual.
	basket.rotation.y = PI
	for side in [-1,1]:
		basket.box("BasketSide",Vector3(side*.25,.93,.38),Vector3(.035,.22,.34),"bf9040")
		basket.box("BasketEnd",Vector3(0,.93,.38+side*.17),Vector3(.50,.22,.025),"bf9040")
		basket.box("Handle",Vector3(side*.22,1.1,.38),Vector3(.022,.14,.022),"303e39")
	basket.box("BasketBase",Vector3(0,.82,.38),Vector3(.5,.025,.34),"956c36")
	goods = basket.box("Groceries",Vector3(0,.99,.38),Vector3(.24,.24,.18),"b3553c")
	goods.hide()
	if shopping_model.get("activity") != null: shopping_model.activity = "carry"
	shopping_model.hand_provider = func() -> Array:
		if dead: return [null, null]
		var targets: Array = [basket.to_global(Vector3(-.22,1.1,.38)),basket.to_global(Vector3(.22,1.1,.38))]
		if stage == "browse" and route_index >= route_points.size() and wait_time > 0 and not market.threatened():
			targets[1] = market.to_global(position+Vector3(.65,1.1,0))
		return targets
	wait_time = 1.5+customer_index
	_set_route([Vector3(position.x,0,-1.5+customer_index*.6)])

func _set_route(points: Array) -> void:
	route_points.clear()
	for point in points: route_points.append(point)
	route_index = 0

func _physics_process(delta: float) -> void:
	if dead:
		if market.checkout_owner == self: market.checkout_owner = null
		if is_instance_valid(goods): goods.hide()
		super._physics_process(delta)
		return
	if not market.active: return
	if market.threatened():
		automatic_direction = Vector3.ZERO
		if market.checkout_owner == self: market.checkout_owner = null
		if shopping_model.get("activity") != null: shopping_model.activity = "talk"
		super._physics_process(delta)
		return
	if shopping_model.get("activity") != null: shopping_model.activity = "carry"
	automatic_direction = Vector3.ZERO
	if route_index < route_points.size():
		var direction: Vector3 = route_points[route_index]-position
		direction.y = 0
		if direction.length() < .15:
			route_index += 1
		else: automatic_direction = direction.normalized()
	else:
		wait_time -= delta
		if wait_time <= 0: _advance()
	super._physics_process(delta)

func _advance() -> void:
	if shopping_model.get("hand_targets") != null: shopping_model.hand_targets = [null,null]
	var lane := -6.35+customer_index*3.2
	match stage:
		"browse":
			goods.show()
			browse_count += 1
			if browse_count < 2:
				_set_route([Vector3(lane,0,1.0)])
				wait_time = 2.8+customer_index*.3
			else:
				stage = "wait_checkout"
				_set_route([Vector3(lane,0,2.65)])
		"wait_checkout":
			if is_instance_valid(market.checkout_owner) and market.checkout_owner != self: return
			market.checkout_owner = self
			stage = "checkout"
			_set_route([Vector3(lane,0,2.65),Vector3(4.15,0,2.65),Vector3(4.15,0,4.5)])
			wait_time = 3.5
		"checkout":
			completed_purchases += 1
			stage = "exit"
			_set_route([Vector3(4.15,0,6.1),Vector3(.55,0,6.1),Vector3(.55,0,6.7)])
			wait_time = 1.0
		"exit":
			if market.checkout_owner == self: market.checkout_owner = null
			stage = "away"
			hide()
			collision_layer = 0
			collision_mask = 1
			wait_time = 6.0+customer_index*1.7
		"away":
			# Reaproveita o corpo só na porta, e espera se o jogador a estiver ocupando.
			if market.session.world.player.global_position.distance_to(global_position) < 1.2: return
			show()
			collision_layer = 2
			collision_mask = 7
			goods.hide()
			stage = "return"
			_set_route([Vector3(.55,0,6.1),Vector3(2.7,0,6.1),Vector3(2.7,0,2.65),Vector3(lane,0,2.65),Vector3(lane,0,-2.4)])
		"return":
			stage = "browse"
			browse_count = 0
			wait_time = 3.0
