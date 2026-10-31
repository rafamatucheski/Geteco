extends SceneTree
const MARKET := preload("res://world/places/supermarket/SupermarketPlace.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var market := MARKET.new()
	market.definition = MARKET.definition_data()
	root.add_child(market)
	var player := Node3D.new()
	root.add_child(player)
	player.position = Vector3(-4.1,0,4.5)
	var session := {"world":{"gameplay":{"health":100,"stars":0},"player":player},"room_npcs":[]}
	market.on_session_entered(session)
	market.on_session_entered(session)
	if market.customers.size()!=4: failures.append("reentry duplicated customers")
	var invalid_positions := {}
	for frame in 9000:
		await physics_frame
		for customer in market.customers:
			# Um retângulo aumentado rejeita falsamente uma cápsula redonda ao lado dos cantos da mobília.
			# Mede a distância círculo-caixa usando o raio real de .30 m do Actor.
			var overlaps := false
			for bounds in market.solid_bounds:
				var closest := Vector2(clampf(customer.position.x,bounds.position.x,bounds.end.x),clampf(customer.position.z,bounds.position.z,bounds.end.z))
				if closest.distance_to(Vector2(customer.position.x,customer.position.z)) < .299: overlaps = true
			if overlaps or absf(customer.position.y) > .3:
				invalid_positions[customer.customer_index] = str(customer.position)
		if frame==300:
			session.world.gameplay.stars = 1
		if frame==360:
			for customer in market.customers:
				if customer.velocity.length()>.05: failures.append("customer keeps shopping during threat")
			session.world.gameplay.stars = 0
	if not invalid_positions.is_empty(): failures.append("customer overlaps fixture: "+str(invalid_positions))
	for customer in market.customers:
		print("CUSTOMER ",customer.customer_index," purchases=",customer.completed_purchases," stage=",customer.stage," point=",customer.position," route=",customer.route_index)
		if customer.completed_purchases<2: failures.append("customer does not complete repeat visits: "+str(customer.customer_index))
	var references: Array[WeakRef] = []
	for customer in market.customers: references.append(weakref(customer))
	market.free()
	await process_frame
	for reference in references:
		if reference.get_ref()!=null: failures.append("customer leaked after market unload")
	player.free()
	print("SUPERMARKET_CUSTOMERS failures=",failures)
	quit(0 if failures.is_empty() else 1)
