extends "res://tests/tank_control/test_heavy_impacts.gd"
## Playtest 29/10 na serra: "as placas não são derrubadas, nada é derrubado". Achados no código:
## - placas de curva/divisa (MountainTrafficSigns) com a colisão no corpo único da célula e fora do
##   FragileProps3D: o poste de 9 cm parava o carro a qualquer velocidade;
## - poste de madeira da beira da estrada (MountainRoadside3D) e balizador âmbar só em MultiMesh,
##   sem registro: o carro atravessava sem reação.
## Cobre de pé abaixo do limiar, tombo na base acima, caído sem passe alfa e volta na remontagem.
## Exige janela: sem renderer real a MultiMesh devolve as instâncias na origem.
const SIGNS := preload("res://world/mountain_detail/MountainTrafficSigns.gd")
const ROADSIDE := preload("res://world/mountain_detail/MountainRoadside3D.gd")
const DELINEATORS := preload("res://world/shared/roads/RoadDelineatorBatches.gd")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("test_mountain_breakable_props exige renderer real (MultiMesh)")
		quit(2)
		return
	world = Node3D.new(); root.add_child(world)
	street = Street.new(); world.add_child(street)
	await _traffic_signs()
	await _roadside_lamp()
	await _delineator()
	world.free()
	print("MOUNTAIN_BREAKABLE_PROPS checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func _ram(item: Dictionary, speed: float) -> void:
	var vehicle := car(1200, Vector3(2, 1.4, 4), item.point + Vector3(0, .04, 3.8))
	await physics_frame
	street._hit_props(vehicle, Vector3(0, 0, -speed), Vector3(0, 0, -3))
	vehicle.free()

func _items(kind: String, point: Vector3, radius := 1.0) -> Array:
	return FRAGILE.query(point, radius).filter(func(item): return item.kind == kind and Vector2(item.point.x, item.point.z).distance_to(Vector2(point.x, point.z)) < .05)

func _sign_records(signs) -> void:
	signs.records.clear()
	for row in [[Vector3(20, 0, 10), "chevron_left", ""], [Vector3(26, 0, 10), "curve_right", ""], [Vector3(32, 0, 10), "destination", "Vila  →"]]:
		signs.records.append({"position": row[0], "basis": Basis(Vector3.UP, .3), "kind": row[1], "road": "test", "text": row[2]})

func _traffic_signs() -> void:
	FRAGILE.cells.clear()
	var holder := Node3D.new(); world.add_child(holder)
	var signs := SIGNS.new()
	_sign_records(signs)
	signs.build(holder)
	await physics_frame
	var chevron: Array = _items("mountain_sign", Vector3(20, 0, 10))
	var curve: Array = _items("mountain_sign", Vector3(26, 0, 10))
	var destination: Array = _items("mountain_sign", Vector3(32, 0, 10))
	check(chevron.size() == 1 and curve.size() == 1 and destination.size() == 1, "placas: chevron, curva e divisa registradas (%d/%d/%d)" % [chevron.size(), curve.size(), destination.size()])
	if chevron.is_empty() or curve.is_empty() or destination.is_empty(): return
	var item: Dictionary = chevron[0]
	var collider: CollisionShape3D = item.colliders[0].get_ref()
	var neighbour: CollisionShape3D = curve[0].colliders[0].get_ref()
	check(collider != null and collider != neighbour and collider.get_parent() == neighbour.get_parent(), "placas: colisor próprio dentro do corpo comum da célula")
	# Abaixo do limiar (FALL_SPEED ≈ 2,2 m/s) a placa balança e segura; a 4 m/s tomba.
	await _ram(item, 1.6)
	check(item.state == "standing" and not collider.disabled, "placas: 1,6 m/s deixa a placa de pé")
	await _ram(item, 4.0)
	check(item.state == "down" and collider.disabled, "placas: 4 m/s derruba a placa e solta o carro")
	check(curve[0].state == "standing" and not neighbour.disabled, "placas: só a placa atingida cai")
	for frame in 65: await physics_frame
	var post_mm: MultiMesh = item.extra[0].multimesh
	var face_mm: MultiMesh = item.extra[1].multimesh
	var post: Transform3D = post_mm.get_instance_transform(item.extra[0].index)
	var face: Transform3D = face_mm.get_instance_transform(item.extra[1].index)
	var pivot: Transform3D = item.multimesh.get_instance_transform(item.index)
	check(pivot.origin.is_equal_approx(Vector3(20, 0, 10)), "placas: tomba na base")
	check(absf(pivot.basis.y.normalized().y) < .1, "placas: placa deitada")
	check(face.is_equal_approx(pivot * item.extra[1].offset) and post.is_equal_approx(pivot * item.extra[0].offset), "placas: poste e placa acompanham o pivô")
	FRAGILE._fade_post(item)
	for frame in 30: await physics_frame
	check(face_mm.get_instance_transform(item.extra[1].index).is_equal_approx(face), "placas: caída fica no chão sem passe alfa")
	# Divisa: nó próprio com rótulo, tomba inteiro.
	var board: Dictionary = destination[0]
	var root_node: Node3D = board.root.get_ref()
	await _ram(board, 4.0)
	for frame in 65: await physics_frame
	var label: Label3D = null
	for child in root_node.get_children():
		if child is Label3D: label = child
	check(board.state == "down" and board.colliders[0].get_ref().disabled, "divisa: derrubada solta o carro")
	check(absf(root_node.global_basis.y.normalized().y) < .1 and label != null and label.global_position.y < 1.0, "divisa: placa e rótulo deitam juntos")
	# Remontagem da serra: a célula velha sai e a nova nasce de pé, sem duplicar.
	for child in holder.get_children(): child.free()
	signs.build(holder)
	await physics_frame
	var rebuilt: Array = _items("mountain_sign", Vector3(20, 0, 10))
	check(rebuilt.size() == 1 and rebuilt[0].state == "standing" and not rebuilt[0].colliders[0].get_ref().disabled, "placas: remontagem traz a placa de pé (achou %d)" % rebuilt.size())
	holder.free()
	FRAGILE.cells.clear()

func _roadside_lamp() -> void:
	FRAGILE.cells.clear()
	var roadside := ROADSIDE.new()
	roadside.controller = RefCounted.new()
	world.add_child(roadside)
	roadside.set_process(false)
	roadside._lamp_points.assign([Vector3(60, 0, 10), Vector3(66, 0, 10)])
	roadside._build_lamps()
	await physics_frame
	var lamps: Array = _items("lamp", Vector3(60, 0, 10))
	check(lamps.size() == 1 and roadside._lamp_items[0] == lamps[0], "poste de madeira: registrado como lamp")
	if lamps.is_empty(): return
	var item: Dictionary = lamps[0]
	await _ram(item, 3.5)
	check(item.state == "standing", "poste de madeira: 3,5 m/s não derruba")
	await _ram(item, 5.5)
	check(item.state == "down", "poste de madeira: 5,5 m/s derruba")
	check(roadside._lamp_items[1].state == "standing", "poste de madeira: vizinho de pé")
	for frame in 65: await physics_frame
	var pivot: Transform3D = item.multimesh.get_instance_transform(item.index)
	var pole: Transform3D = item.extra[0].multimesh.get_instance_transform(item.extra[0].index)
	check(absf(pivot.basis.y.normalized().y) < .1 and pole.is_equal_approx(pivot * item.extra[0].offset), "poste de madeira: tomba na base com as peças")
	# LampRecovery3D devolve o poste depois do prazo, como no porto.
	_restore(item)
	# A leitura da MultiMesh vem do lote do servidor, que leva alguns quadros desenhados para refletir
	# a escrita (lido logo depois, ainda devolvia o poste deitado; 60 quadros depois, de pé).
	for frame in 30: await physics_frame
	check(item.state == "standing" and item.extra[0].multimesh.get_instance_transform(item.extra[0].index).basis.y.normalized().y > .99, "poste de madeira: recuperação levanta o poste")
	roadside.free()
	FRAGILE.cells.clear()

func _restore(item: Dictionary) -> void:
	preload("res://gameplay/street_physics/LampRecovery3D.gd").restore(item)

func _delineator() -> void:
	FRAGILE.cells.clear()
	var holder := Node3D.new(); world.add_child(holder)
	var poses: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, .5), Vector3(90, 0, 10)), Transform3D(Basis.IDENTITY, Vector3(96, 0, 10))]
	ROADSIDE._register_delineators(holder, DELINEATORS.build(holder, poses, "TestDelineator"))
	var items: Array = _items("mountain_sign", Vector3(90, 0, 10))
	check(items.size() == 1, "balizador: registrado")
	if items.is_empty(): return
	var item: Dictionary = items[0]
	await _ram(item, 1.6)
	check(item.state == "standing", "balizador: 1,6 m/s não derruba")
	await _ram(item, 4.0)
	check(item.state == "down", "balizador: 4 m/s derruba")
	check(_items("mountain_sign", Vector3(96, 0, 10)).size() == 1, "balizador: vizinho de pé")
	holder.free()
	FRAGILE.cells.clear()
