extends RefCounted
## Objeto leve que vira corpo rígido (lançamento e giro pela massa, desvio para o lado, sacos soltos,
## fratura, lixeira com tampa) e as contas de lançamento usadas também pelos testes. Separado de
## FragileProps3D.gd em 01/11 só para o dono caber na leitura. Tudo estático, como o dono: as tabelas
## (MASSES, SOFT_KINDS), as constantes do choque, as static var (_hitter, _hitter_side) e as demais
## funções continuam em FragileProps3D, que mantém cada função antiga como delegação de uma linha com a
## mesma assinatura (`fragile.launch_velocity`, `fragile.launch_spin` nos testes não mudam). Este arquivo
## não dá preload no dono (seria ciclo): cada função que precisa dele recebe o script do dono em `g`
## e usa tudo dele por `g.`, inclusive as chamadas entre funções deste arquivo.

## Objeto leve vira corpo rígido: sai com a velocidade que o para-choque
## transfere, bate em parede/meio-fio/carro de verdade e para onde a física
## deixar. Antes era um arco em tween com distância fixa, que atravessava
## prédio e carro e pousava sempre igual.
static func _tumble(g: GDScript, item: Dictionary, flat: Vector3, speed: float, director: Node) -> void:
	var base: Transform3D = g._base(item)
	var mesh: Mesh = null
	var node_copy: Node3D = null
	if item.has("multimesh"):
		g._disable_collision(item)
		mesh = item.multimesh.mesh
		# Escala zero some com a instância original; a cópia física assume.
		var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), base.origin)
		item.multimesh.set_instance_transform(item.index, hidden)
		for extra in item.extra: extra.multimesh.set_instance_transform(extra.index, hidden)
		# A instância é local ao chunk; o destroço vive no mundo.
		var chunk = item.chunk.get_ref()
		if is_instance_valid(chunk): base = chunk.global_transform * base
	else:
		g._disable_collision(item)
		var root = item.root.get_ref()
		if is_instance_valid(root):
			node_copy = root.duplicate(0)
			node_copy.set_script(null)
			for body in node_copy.find_children("*", "CollisionObject3D", true, false): body.free()
			root.visible = false
	# Impulso pela massa do objeto (launch_velocity): antes todo objeto saía a
	# 0,95–1,3x a velocidade do carro e até 4 m/s para cima, a caçamba de 100 kg
	# igual à lata, e voava como papel (playtest de 29/10).
	var side := Vector3.UP.cross(flat).normalized()
	var launch: Vector3 = g.launch_velocity(str(item.kind), speed, flat, randf_range(0.85, 1.05), randf_range(-0.12, 0.12))
	var spin: Vector3 = g.launch_spin(str(item.kind), launch, side, randf_range(-1.0, 1.0))
	var is_rock: bool = item.kind in ["desert_rock", "desert_stone", "desert_gravel"]
	if is_rock:
		# Pedra solta recebe impulso do para-choque; a subida deixa a quebra legível.
		# Limites evitam transformar um toque lento em explosão ou lançar além do streaming.
		launch = flat * clampf(speed * .65, .6, 16.0) + Vector3.UP * clampf(speed * .28, .35, 6.0)
		spin = side * clampf(speed * .65, 1.0, 12.0) + Vector3.UP * randf_range(-3.0, 3.0)
	if item.kind in ["desert_tree", "desert_shrub", "desert_grass"]:
		# Árvore cede e tomba onde estava: com a velocidade cheia do carro ela saía voando longe.
		launch = flat * minf(speed * 0.15, 2.5) + Vector3.UP * 0.3
		spin = side * clampf(speed * 0.25, 1.0, 2.5)
	var soft: bool = item.kind in g.SOFT_KINDS
	if g._hitter != null and not is_rock and not item.kind in ["desert_tree", "desert_shrub", "desert_grass"]:
		# Playtest 30/10 ("os lixos são arrastados... ficam coladas"): o objeto sai no máximo na
		# velocidade do carro (contrato do launch_velocity), então reto para a frente o carro o
		# alcançava, e quando a colisão com o carro ligava (0,35 s) o para-choque cinemático o
		# empurrava colado. Agora sai desviado para o lado em que estava (20°–46°, sorteado por
		# objeto): o carro passa e ele fica para trás, rolando para fora do caminho.
		launch = g._deflect(launch, g._hitter_side, randf_range(0.35, 0.8))
	if soft:
		# Saco, papelão, rede: leve e fofo, sobe um pouco e rola girando para qualquer lado.
		# Subida pela força do choque: empurrado devagar só rola, não pula (sobe no máximo ~0,3 m).
		launch.y = maxf(launch.y, randf_range(1.0, 2.4) * clampf(speed / 10.0, 0.25, 1.0))
		spin = g._random_spin(clampf(speed * 0.5, 2.0, 7.0))
	elif not is_rock:
		# Caixote, lata, tambor: giro do tombo com um pouco de eixo sorteado, cada um de um jeito.
		spin += g._random_spin(clampf(speed * 0.15, 0.4, 2.5)) * clampf(sqrt(30.0 / float(g.MASSES.get(item.kind, 15.0))), 0.3, 1.0)
	if mesh != null and not g._junk_pieces(item.kind).is_empty():
		# Pilha de sacos: cada saco vira um destroço próprio, com rumo, subida e giro próprios.
		var pieces: Array = g._junk_pieces(item.kind)
		var tint: Material = g._instance_material(item)
		for index in pieces.size():
			var bag: RigidBody3D = g._debris_body(director, base.origin, maxf(1.0, float(g.MASSES.get(item.kind, 20.0)) * absf(base.basis.determinant()) / pieces.size()), true)
			var visual := MeshInstance3D.new()
			visual.mesh = pieces[index]
			visual.material_override = tint
			visual.transform = Transform3D(base.basis, Vector3.ZERO)
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bag.add_child(visual)
			g._add_box_shape(bag, visual.transform * visual.mesh.get_aabb())
			var own: Vector3 = g._deflect(launch, 1.0, randf_range(-0.45, 0.45)) * randf_range(0.7, 1.08)
			own.y = randf_range(0.8, 2.4) * clampf(speed / 10.0, 0.25, 1.0)
			bag.linear_velocity = own
			bag.angular_velocity = g._random_spin(clampf(speed * 0.5, 2.0, 7.0))
		return
	if mesh != null and mesh.has_meta("street_fracture_meshes"):
		# A mesma fratura espacial das pedras bege, com cacos de origem compartilhados.
		# Escala, cores de vértice e tinta da instância sobrevivem à passagem para o MultiMesh.
		var shards: Array = mesh.get_meta("street_fracture_meshes")
		var material: Material = g._instance_material(item)
		for index in shards.size():
			var fragment: RigidBody3D = g._debris_body(director, base.origin, maxf(.05, float(g.MASSES.get(item.kind, 1.0)) * absf(base.basis.determinant()) / shards.size()))
			var visual := MeshInstance3D.new()
			visual.mesh = shards[index]
			visual.material_override = material
			visual.transform = Transform3D(base.basis, Vector3.ZERO)
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fragment.add_child(visual)
			g._add_box_shape(fragment, visual.transform * visual.mesh.get_aabb())
			var spread := clampf(speed * .16, .15, 4.0) if is_rock else .35
			fragment.linear_velocity = launch + side * (float(index) - float(shards.size() - 1) * .5) * spread
			if is_rock: fragment.linear_velocity.y *= .8 + float(index) * .2
			fragment.angular_velocity = spin * (.6 + float(index) * .3)
		return
	if item.kind == "trash_can":
		g._break_trash_can(base, launch, spin, director)
		return
	if (speed >= g.FALL_SPEED and item.kind in ["bench_seat","planter","pallet"]) or (speed >= 10.0 and item.kind in ["desert_rock", "desert_tree", "lamp", "signal_pole", "stop_sign", "phone_booth"]):
		var source := node_copy
		if source != null: source.transform = Transform3D(base.basis, Vector3.ZERO)
		if source == null:
			source = MeshInstance3D.new()
			source.mesh = mesh
		source.transform = Transform3D(base.basis, Vector3.ZERO)
		var shards := preload("res://gameplay/street_physics/PropFracture3D.gd").split(source, 1 if item.kind == "desert_tree" or g.spec(item).family == "post" else 0)
		if not shards.is_empty():
			for index in shards.size():
				var fragment: RigidBody3D = g._debris_body(director, base.origin, float(g.MASSES.get(item.kind, 15.0)) / shards.size())
				fragment.add_child(shards[index])
				g._add_box_shape(fragment, shards[index].get_aabb())
				fragment.linear_velocity = launch + side * (float(index) - 1.0) * minf(speed * .1, 0.6 if item.kind == "desert_tree" else 3.0)
				fragment.angular_velocity = spin * (0.6 + float(index) * .3)
			source.free()
			return
		if node_copy == null: source.free()
	var piece: RigidBody3D = g._debris_body(director, base.origin, g.MASSES.get(item.kind, 15.0), soft)
	if mesh != null:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = g._instance_material(item)
		visual.transform = Transform3D(base.basis, Vector3.ZERO)
		piece.add_child(visual)
		g._add_box_shape(piece, visual.transform * mesh.get_aabb())
	elif node_copy != null:
		piece.add_child(node_copy)
		node_copy.transform = Transform3D(base.basis, Vector3.ZERO)
		if node_copy is MeshInstance3D:
			g._add_box_shape(piece, node_copy.transform * node_copy.get_aabb())
		else:
			g._add_box_shape(piece, g._local_aabb(node_copy))
	piece.linear_velocity = launch
	piece.angular_velocity = spin
	if item.kind == "news_box": director.spawn_glass(base.origin, flat)
	if item.kind == "mailbox": g._spill_later(director, piece, flat, 0.5)

## Lixeira: o corpo amassa e voa, a tampa solta e sai por conta própria, e o
## lixo espalha onde o corpo parar de rolar (não num ponto pré-calculado).
static func _break_trash_can(g: GDScript, base: Transform3D, launch: Vector3, spin: Vector3, director: Node) -> void:
	var can: RigidBody3D = g._debris_body(director, base.origin, g.MASSES.trash_can)
	var shell_visual := MeshInstance3D.new()
	# Com a lata do Blender, o destroço usa o corpo e a tampa dela (origem no chão e no
	# centro da tampa, respectivamente); senão, os cilindros antigos.
	var kit := preload("res://world/city_look/CityPropKit.gd")
	var modeled: bool = kit.blender_props_enabled
	if modeled:
		shell_visual.mesh = kit.blender_mesh("trash_can", "TrashCanBody")
	else:
		var shell := CylinderMesh.new()
		shell.top_radius = 0.29
		shell.bottom_radius = 0.26
		shell.height = 0.82
		shell.radial_segments = 7
		shell.rings = 1
		shell.material = g._flat_material(Color("2f5a43"))
		shell_visual.mesh = shell
	# Amassado do para-choque: achata no sentido do choque.
	var dent := Vector3(launch.x, 0, launch.z).normalized()
	if dent.length_squared() < 0.01: dent = Vector3.FORWARD
	shell_visual.transform = Transform3D(Basis.looking_at(dent, Vector3.UP).scaled(Vector3(1.0, 1.0, randf_range(0.72, 0.86))), Vector3.ZERO if modeled else Vector3.UP * 0.41)
	can.add_child(shell_visual)
	g._add_cylinder_shape(can, 0.27, 0.82, Vector3.UP * 0.41)
	can.linear_velocity = launch
	can.angular_velocity = spin
	var lid: RigidBody3D = g._debris_body(director, base.origin + Vector3.UP * 0.88, g.LID_MASS)
	var lid_visual := MeshInstance3D.new()
	if modeled:
		lid_visual.mesh = kit.blender_mesh("trash_can", "TrashCanLid")
	else:
		var lid_mesh := CylinderMesh.new()
		lid_mesh.top_radius = 0.22
		lid_mesh.bottom_radius = 0.31
		lid_mesh.height = 0.08
		lid_mesh.radial_segments = 7
		lid_mesh.rings = 1
		lid_mesh.material = g._flat_material(Color("1f3a2c"))
		lid_visual.mesh = lid_mesh
	lid.add_child(lid_visual)
	g._add_cylinder_shape(lid, 0.3, 0.08, Vector3.ZERO)
	# Tampa solta do alto: sai um pouco à frente e salta pouco (subia até 3,5 m/s e
	# girava a 15 rad/s, como folha de papel).
	lid.linear_velocity = launch * randf_range(0.8, 1.0) + Vector3(randf_range(-0.6, 0.6), randf_range(0.4, 1.2), randf_range(-0.6, 0.6))
	lid.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
	# Parte cai no choque (boca aberta); o resto onde a lata parar.
	director.spawn_litter(base.origin, dent)
	g._spill_later(director, can, dent, 0.8)

## Velocidade de saída do objeto `kind` acertado a `speed` m/s no sentido `flat`.
## `jitter` (≈0,85–1,05) e `lateral` (≈±0,12) vêm do chamador para o teste ser determinístico.
static func launch_velocity(g: GDScript, kind: String, speed: float, flat: Vector3, jitter := 1.0, lateral := 0.0) -> Vector3:
	var mass := float(g.MASSES.get(kind, 15.0))
	var transfer: float = (1.0 + g.RESTITUTION) * g.CAR_MASS / (g.CAR_MASS + mass) * g.GLANCE
	var horizontal := minf(speed * transfer * jitter, minf(g.IMPULSE_CAP / mass, g.MAX_LAUNCH))
	var side := Vector3.UP.cross(flat).normalized()
	var lift := clampf(horizontal * 0.08, 0.2, g.MAX_LIFT)
	return flat * horizontal + side * horizontal * lateral + Vector3.UP * lift

## Giro de tombo: proporcional ao que o objeto andou e menor quanto mais pesado
## (antes até 22 rad/s em qualquer objeto, a lata rodopiava como folha).
static func launch_spin(g: GDScript, kind: String, launch: Vector3, side: Vector3, yaw := 0.0) -> Vector3:
	var mass := float(g.MASSES.get(kind, 15.0))
	var horizontal := Vector2(launch.x, launch.z).length()
	var weight := clampf(sqrt(30.0 / mass), 0.35, 1.0)
	return side * clampf(horizontal * 0.5, 0.4, 7.0) * weight + Vector3.UP * yaw * 2.0 * weight

## Gira o rumo horizontal de `velocity` em torno do eixo vertical, para o lado `side` (+1 é o lado
## UP×rumo); lado 0 sorteia. A subida não muda.
static func _deflect(velocity: Vector3, side: float, angle: float) -> Vector3:
	if side == 0.0: side = 1.0 if randf() < 0.5 else -1.0
	var horizontal := Basis(Vector3.UP, angle * signf(side)) * Vector3(velocity.x, 0, velocity.z)
	return Vector3(horizontal.x, velocity.y, horizontal.z)

static func _random_spin(magnitude: float) -> Vector3:
	var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	if axis.length_squared() < 0.01: axis = Vector3.RIGHT
	return axis.normalized() * magnitude * randf_range(0.6, 1.0)

static func _junk_pieces(kind: String) -> Array:
	var junk := preload("res://world/city_look/StreetJunkKit.gd")
	return junk.pieces(kind) if junk.PILE_PIECES.has(kind) else []
