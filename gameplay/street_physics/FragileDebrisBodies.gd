extends RefCounted
## Corpo rígido do destroço (camadas, amortecimento, carência do carro que lançou, chute por contato,
## limite MAX_DEBRIS), materiais físicos e de instância, formas de colisão, AABB local e o lixo que
## espalha depois. Separado de FragileProps3D.gd em 01/11 só para o dono caber na leitura. Tudo estático,
## como o dono: as constantes, as static var (_debris, _physical_materials, _instance_materials,
## _hitter, _hit_sound) e as demais funções continuam em FragileProps3D, que mantém cada função antiga
## como delegação de uma linha com a mesma assinatura. Este arquivo não dá preload no dono (seria
## ciclo): cada função que precisa dele recebe o script do dono em `g` e usa tudo dele por `g.`.

static func _physics_material(g: GDScript, soft: bool) -> PhysicsMaterial:
	if not g._physical_materials.has(soft):
		var material := PhysicsMaterial.new()
		# Duro: quique quase nulo (metal e madeira amassam). Fofo: escorrega menos e quica um pouco.
		material.friction = 0.6 if soft else 0.9
		material.bounce = 0.18 if soft else 0.06
		g._physical_materials[soft] = material
	return g._physical_materials[soft]

## Carro encostou num destroço solto: em vez de o para-choque cinemático levá-lo colado, o objeto é
## lançado para fora do caminho, para o lado em que está, com a transferência de momento pela massa
## (saco quase na velocidade do carro, tambor bem menos) e giro sorteado. O carro fica de fora por
## KICK_GRACE para o objeto se afastar; se ainda encostar depois, chuta de novo.
static func _kick_debris(g: GDScript, body: RigidBody3D, other: Node, soft: bool, director: Node) -> void:
	if not is_instance_valid(body) or not other is CharacterBody3D or other.get("horizontal_velocity") == null: return
	var car := other as CharacterBody3D
	var planar := Vector3(car.velocity.x, 0, car.velocity.z)
	var speed := planar.length()
	# Carro parado ou manobrando: a física empurra devagar, sem chute.
	if speed < 1.2: return
	var now := Time.get_ticks_msec()
	if now - int(body.get_meta("street_kick_msec", -100000)) < g.KICK_COOLDOWN_MS: return
	body.set_meta("street_kick_msec", now)
	var forward := planar / speed
	var across := Vector3.UP.cross(forward)
	var side := signf(across.dot(body.global_position - car.global_position))
	var transfer: float = (1.0 + g.RESTITUTION) * g.CAR_MASS / (g.CAR_MASS + body.mass)
	var horizontal := minf(speed * transfer * randf_range(0.9, 1.1), 16.0)
	var out: Vector3 = g._deflect(forward * horizontal, side, randf_range(0.45, 0.9))
	out.y = randf_range(1.0, 2.4) if soft else randf_range(0.3, 1.0)
	body.linear_velocity = out
	var weight := clampf(sqrt(30.0 / body.mass), 0.3, 1.0)
	body.angular_velocity = g._random_spin(clampf(speed * (0.6 if soft else 0.3), 2.0, 9.0) * weight)
	body.add_collision_exception_with(car)
	body.get_tree().create_timer(g.KICK_GRACE, false, true).timeout.connect(func():
		if is_instance_valid(body) and is_instance_valid(car): body.remove_collision_exception_with(car))
	if is_instance_valid(director) and director.has_method("play_prop_hit"):
		director.play_prop_hit(body.global_position, str(body.get_meta("street_sound", "bag" if soft else "wood")), clampf(speed * 0.5, 1.0, 8.0))

static func _debris_body(g: GDScript, director: Node, origin: Vector3, mass: float, soft := false) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "StreetDebris"
	body.mass = mass
	body.collision_layer = g.DEBRIS_LAYER
	# Só o mundo no começo: o objeto nasce encostado no carro que o acertou e
	# colidir com ele no primeiro quadro o expulsaria com impulso absurdo.
	body.collision_mask = 1
	body.continuous_cd = true
	# Amortecimento de objeto pesado arrastando no chão: com 0,05/0,4 deslizava e
	# girava longe depois do choque. O fofo freia no ar (arrasto do saco) mas rola solto.
	body.gravity_scale = 1.0 if soft else g.DEBRIS_GRAVITY
	body.linear_damp = 0.8 if soft else 0.3
	body.angular_damp = 0.5 if soft else 1.5
	body.physics_material_override = g._physics_material(soft)
	director.add_child(body)
	body.global_position = origin
	var tree: SceneTree = director.get_tree()
	# O carro que lançou o objeto fica de fora por HITTER_GRACE: antes, quando a colisão com carros
	# ligava aos 0,35 s, o carro (mais rápido que o objeto) já estava em cima dele e o empurrava colado.
	var hitter: Node = g._hitter.get_ref() if g._hitter != null else null
	if is_instance_valid(hitter) and hitter is PhysicsBody3D:
		body.add_collision_exception_with(hitter)
		tree.create_timer(g.HITTER_GRACE, false, true).timeout.connect(func():
			if is_instance_valid(body) and is_instance_valid(hitter): body.remove_collision_exception_with(hitter))
	if mass <= g.KICK_MAX_MASS:
		# Carro que encostar depois (o mesmo ou outro) chuta o objeto para o lado em vez de levá-lo
		# no para-choque. Só sinal de contato: até MAX_DEBRIS corpos, nada por quadro.
		body.contact_monitor = true
		body.max_contacts_reported = 2
		body.body_entered.connect(func(other: Node): g._kick_debris(body, other, soft, director))
	if not g._hit_sound.is_empty(): body.set_meta("street_sound", g._hit_sound)
	# Depois de se afastar, carro que passar por cima empurra o destroço.
	tree.create_timer(0.35, false, true).timeout.connect(func():
		if is_instance_valid(body): body.collision_mask = 1 | 4 | g.DEBRIS_LAYER)
	preload("res://gameplay/DestroyedFade3D.gd").schedule(body, g.DEBRIS_LIFETIME, true)
	var alive := []
	for ref in g._debris:
		if is_instance_valid(ref.get_ref()): alive.append(ref)
	alive.append(weakref(body))
	while alive.size() > g.MAX_DEBRIS:
		var oldest = alive.pop_front().get_ref()
		if is_instance_valid(oldest): preload("res://gameplay/DestroyedFade3D.gd").fade(oldest, true)
	g._debris = alive
	return body

static func _instance_material(g: GDScript, item: Dictionary) -> Material:
	var visual: Variant = item.visual.get_ref() if item.has("visual") else null
	if not is_instance_valid(visual): return null
	var source: Material = visual.material_override
	var multimesh: MultiMesh = item.multimesh
	if not source is StandardMaterial3D or not multimesh.use_colors: return source
	var color := multimesh.get_instance_color(int(item.index))
	var key := "%d:%s" % [source.get_instance_id(), color.to_html()]
	if not g._instance_materials.has(key):
		if g._instance_materials.size() > 64: g._instance_materials.clear()
		var tinted := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
		tinted.albedo_color = source.albedo_color * color
		g._instance_materials[key] = tinted
	return g._instance_materials[key]

static func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	return material

static func _add_box_shape(body: RigidBody3D, box: AABB) -> void:
	var shape := CollisionShape3D.new()
	var geometry := BoxShape3D.new()
	geometry.size = box.size.max(Vector3.ONE * 0.08)
	shape.shape = geometry
	shape.position = box.get_center()
	body.add_child(shape)

static func _add_cylinder_shape(body: RigidBody3D, radius: float, height: float, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var geometry := CylinderShape3D.new()
	geometry.radius = radius
	geometry.height = height
	shape.shape = geometry
	shape.position = at
	body.add_child(shape)

static func _local_aabb(g: GDScript, root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = root.transform * g._relative(root, mesh) * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result if not first else AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.0, 0.6))

## Transformação de `node` relativa a `ancestor` sem depender de estar na árvore.
static func _relative(ancestor: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D: xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform

static func _spill_later(director: Node, body: RigidBody3D, flat: Vector3, delay: float) -> void:
	director.get_tree().create_timer(delay, false, true).timeout.connect(func():
		if not is_instance_valid(body): return
		var at := body.global_position
		# Lixo vai no piso sob a lata, não no ar onde ela estiver quicando.
		var local_query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 4.0, 1)
		var local_hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(local_query)
		director.spawn_litter(Vector3(at.x, local_hit.position.y if not local_hit.is_empty() else at.y - 0.3, at.z), flat)
		director.play_prop_hit(at, "can", 1.5))
