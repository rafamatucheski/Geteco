extends "res://tests/tank_control/test_heavy_impacts.gd"
## Playtest 29/10 no porto: "tem um poste cinza que é impossível, ele não cai; algumas árvores
## também não derrubam". Cobre os três casos achados no código:
## - poste cinza da Vila Cobra (HarborAreaDressing3D._lamp) fora do FragileProps3D;
## - árvore de calçada (CityChunkDressing) que tombava deixando o tronco sólido de pé;
## - pinheiro da mata (FishingWoodland/HarborCoastWoodland) sem registro nenhum.
## Exige janela: sem renderer real a MultiMesh devolve as instâncias na origem.
const DRESSING := preload("res://world/urban_detail/HarborAreaDressing3D.gd")
const CITY := preload("res://world/city_look/CityChunkDressing.gd")
const WOODLAND := preload("res://world/places/fishing/FishingWoodland.gd")
const RECOVERY := preload("res://gameplay/street_physics/LampRecovery3D.gd")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("test_harbor_unbreakable_props exige renderer real (MultiMesh)")
		quit(2)
		return
	world = Node3D.new(); root.add_child(world)
	street = Street.new(); world.add_child(street)
	await _cobra_lamp()
	await _street_tree_trunks()
	await _woodland_tree()
	world.free()
	print("HARBOR_UNBREAKABLE_PROPS checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func _cobra_lamp() -> void:
	FRAGILE.cells.clear()
	var chunk := Node3D.new(); chunk.name = "Chunk_test"; world.add_child(chunk)
	var dressing := DRESSING.new(); dressing.configure("cobra")
	dressing.position = Vector3(40, 0, 40)
	chunk.add_child(dressing)
	await physics_frame
	var lamps: Array = []
	for rows in FRAGILE.cells.values():
		for item in rows:
			if item.kind == "lamp" and str(item.root.get_ref().name).begins_with("HarborLampCobra"): lamps.append(item)
	check(lamps.size() == 6, "cobra: os 6 postes cinza registrados (achou %d)" % lamps.size())
	if lamps.is_empty(): return
	# A passada noturna do chunk acha a cabeça pelo prefixo e liga a mancha de luz ao poste.
	CITY._night_pass(chunk, {"lamps": []})
	var item: Dictionary = lamps[0]
	check(not item.get("pool", {}).is_empty(), "cobra: mancha de luz ligada ao poste")
	var collider: CollisionShape3D = item.colliders[0].get_ref() if not item.colliders.is_empty() else null
	check(collider != null and collider.get_parent().name == "AuthoredDressingSolids", "cobra: colisor do poste é a caixa do corpo comum")
	var point: Vector3 = item.point
	# Devagar (3,5 m/s, manobra) o poste segura o carro; a 5,5 m/s (~20 km/h) tomba.
	for speed in [3.5, 5.5]:
		var vehicle := car(1200, Vector3(2, 1.4, 4), point + Vector3(0, .04, 3.8))
		await physics_frame
		street._hit_props(vehicle, Vector3(0, 0, -speed), Vector3(0, 0, -3))
		if speed < 4.0:
			check(item.state == "standing" and collider != null and not collider.disabled, "cobra: %.1f m/s deixa o poste de pé" % speed)
		else:
			check(item.state == "down", "cobra: %.1f m/s derruba o poste cinza" % speed)
			check(collider != null and collider.disabled, "cobra: poste caído solta o carro")
			var others: int = lamps.slice(1).filter(func(other): return other.state == "standing").size()
			check(others == lamps.size() - 1, "cobra: só o poste atingido cai")
		vehicle.free()
	RECOVERY.restore(item)
	check(item.state == "standing" and collider != null and not collider.disabled, "cobra: poste recuperado volta a ter colisão")
	chunk.free()
	FRAGILE.cells.clear()

func _street_tree_trunks() -> void:
	var chunk := Node3D.new(); world.add_child(chunk)
	var points := [Vector3(80, 0, 20), Vector3(86, 0, 20), Vector3(92, 0, 20)]
	CITY._flush(chunk, {"street_tree": [Transform3D(Basis.IDENTITY, points[0]), Transform3D(Basis.IDENTITY, points[1])],
		"street_tree_b": [Transform3D(Basis.IDENTITY, points[2])]})
	var trunks := chunk.get_node("CityStreetTreeTrunks")
	var items: Array = FRAGILE.query(Vector3(86, 0, 20), 12).filter(func(item): return item.kind == "harbor_tree")
	check(items.size() == 3, "calçada: 3 árvores registradas")
	for item in items:
		var shape: CollisionShape3D = item.colliders[0].get_ref() if not item.get("colliders", []).is_empty() else null
		var expected: Vector3 = trunks.to_global(shape.position) if shape != null else Vector3.INF
		check(shape != null and Vector2(expected.x, expected.z).distance_to(Vector2(item.point.x, item.point.z)) < .01,
			"calçada: árvore em %s leva o próprio tronco" % str(item.point))
	var last: Array = items.filter(func(item): return item.point.is_equal_approx(points[2]))
	if not last.is_empty():
		check(FRAGILE.hit(last[0], 5.0, Vector3.FORWARD, street), "calçada: árvore cede a 5 m/s")
		check(last[0].colliders[0].get_ref().disabled, "calçada: tronco da árvore caída não segura o carro")
		check(not trunks.get_child(0).disabled and not trunks.get_child(1).disabled, "calçada: troncos vizinhos continuam sólidos")
	chunk.free()
	FRAGILE.cells.clear()

func _woodland_tree() -> void:
	var node := Node3D.new(); world.add_child(node)
	var body := StaticBody3D.new(); node.add_child(body)
	var tree := {"point": Vector3(140, 0, 60), "height": 10.0, "radius": .3, "crown": 6.0, "variant": 1, "yaw": .4}
	var batches := {}
	WOODLAND._put(batches, "trunk", tree.point, Vector3(tree.radius / .04, tree.height, tree.radius / .04), tree.yaw)
	WOODLAND._put(batches, "crown_1", tree.point + Vector3.UP * tree.height * .7, Vector3(tree.crown, tree.height * .54, tree.crown * .94), tree.yaw)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new(); shape.radius = tree.radius; shape.height = tree.height * .67
	collision.shape = shape
	collision.position = tree.point + Vector3.UP * shape.height * .5
	body.add_child(collision)
	var entries: Array[Dictionary] = [WOODLAND.tree_entry(batches, tree, collision)]
	var displays := {}
	for key in batches:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = BoxMesh.new()
		multimesh.instance_count = batches[key].size()
		for index in batches[key].size(): multimesh.set_instance_transform(index, batches[key][index])
		var display := MultiMeshInstance3D.new(); display.multimesh = multimesh
		node.add_child(display)
		displays[key] = display
	WOODLAND.register_fragile_trees(node, entries, displays)
	var items: Array = FRAGILE.query(tree.point, 2).filter(func(item): return item.kind == "woodland_tree")
	check(items.size() == 1, "mata: pinheiro registrado")
	if items.is_empty(): return
	var item: Dictionary = items[0]
	for speed in [4.0, 6.0]:
		var vehicle := car(1200, Vector3(2, 1.4, 4), tree.point + Vector3(0, .04, 3.8))
		await physics_frame
		street._hit_props(vehicle, Vector3(0, 0, -speed), Vector3(0, 0, -3))
		if speed < 5.0: check(item.state == "standing" and not collision.disabled, "mata: %.1f m/s não derruba o pinheiro" % speed)
		else: check(item.state == "down" and collision.disabled, "mata: %.1f m/s derruba o pinheiro e solta o carro" % speed)
		vehicle.free()
	for frame in 65: await physics_frame
	var trunk: Transform3D = displays.trunk.multimesh.get_instance_transform(0)
	var crown: Transform3D = displays.crown_1.multimesh.get_instance_transform(0)
	check(trunk.origin.is_equal_approx(tree.point), "mata: tomba na base")
	check(absf(trunk.basis.y.normalized().y) < .1, "mata: pinheiro deitado")
	check(crown.is_equal_approx(trunk * entries[0].offset), "mata: copa acompanha o tronco")
	FRAGILE._fade_post(item)
	check(displays.trunk.multimesh.get_instance_transform(0).is_equal_approx(trunk), "mata: caído fica no chão sem passe alfa")
	node.free()
	FRAGILE.cells.clear()
