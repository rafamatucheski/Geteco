extends RefCounted
## Postes e mobiliário que o carro derruba (porte de StreetLamp/FixedTrafficSignal/
## BreakableProp da V1, grupo "fragile_road_post").
##
## Impactos fracos balançam os postes; o limiar de queda depende da fixação.
## Postes de luz e semáforos permanecem presos à base mesmo em alta velocidade.
## Três famílias:
## - "post": poste de luz, semáforo, placa — tomba girando na base;
## - "light": lixeira, jornaleiro, caixa de correio — vira corpo rígido e quebra;
## - "hydrant": hidrante — arranca e vira gêiser por alguns segundos.
## O registro é espacial (células de 8 m) e não depende de corpo físico: a
## mobília do CityLook não tem colisão (não atrapalha pedestre), então a
## detecção é pela varredura do próprio carro (StreetPhysics.vehicle_pre_move).

const CELL := 8.0
const WOBBLE_SPEED := 15.0 / 16.0
const FALL_SPEED := 35.0 / 16.0

## raio de contato, perda de velocidade do carro ao atravessar, dano no carro.
const KINDS := {
	"lamp": {"family": "post", "radius": 0.22, "drag": 0.30, "damage": 8.0, "sound": "metal", "anchored": true, "fall_speed": 6.0},
	"signal_pole": {"family": "post", "radius": 0.25, "drag": 0.35, "damage": 10.0, "sound": "metal", "anchored": true, "fall_speed": 8.0},
	"stop_sign": {"family": "post", "radius": 0.12, "drag": 0.06, "damage": 2.0, "sound": "metal"},
	"hydrant": {"family": "hydrant", "radius": 0.2, "drag": 0.18, "damage": 5.0, "sound": "metal"},
	"trash_can": {"family": "light", "radius": 0.3, "drag": 0.03, "damage": 0.0, "sound": "metal"},
	"news_box": {"family": "light", "radius": 0.45, "drag": 0.05, "damage": 1.0, "sound": "metal"},
	"mailbox": {"family": "light", "radius": 0.3, "drag": 0.06, "damage": 1.0, "sound": "metal"},
	"phone_booth": {"family": "post", "radius": 0.5, "drag": 0.22, "damage": 6.0, "sound": "glass"},
	"bench_seat": {"family": "light", "radius": 1.4, "drag": 0.12, "damage": 3.0, "sound": "wood"},
	"dumpster": {"family": "light", "radius": 1.2, "drag": 0.16, "damage": 4.0, "sound": "metal"},
	"trash_bags": {"family": "light", "radius": 0.6, "drag": 0.01, "damage": 0.0, "sound": "wood"},
	"planter": {"family": "light", "radius": 0.78, "drag": 0.18, "damage": 5.0, "sound": "stone"},
	"barrel": {"family": "light", "radius": 0.37, "drag": 0.04, "damage": 1.0, "sound": "metal"},
	"pallet": {"family": "light", "radius": 1.2, "drag": 0.05, "damage": 1.0, "sound": "wood"},
	"desert_rock": {"family": "light", "radius": 1.1, "drag": 0.20, "damage": 7.0, "sound": "stone"},
	"desert_tree": {"family": "light", "radius": 0.4, "drag": 0.10, "damage": 3.0, "sound": "wood"},
	# Térreo da calçada (SidewalkFill): plástico, madeira e lata que o carro espalha.
	"cafe_set": {"family": "light", "radius": 0.85, "drag": 0.04, "damage": 0.5, "sound": "wood"},
	"cafe_parasol": {"family": "light", "radius": 0.9, "drag": 0.05, "damage": 0.5, "sound": "wood"},
	"produce_stand": {"family": "light", "radius": 0.9, "drag": 0.05, "damage": 0.5, "sound": "wood"},
	"a_frame": {"family": "light", "radius": 0.35, "drag": 0.01, "damage": 0.0, "sound": "wood"},
	"beer_crates": {"family": "light", "radius": 0.45, "drag": 0.02, "damage": 0.0, "sound": "glass"},
	"pot_plant": {"family": "light", "radius": 0.38, "drag": 0.04, "damage": 0.5, "sound": "stone"},
	"wheelie_bins": {"family": "light", "radius": 0.7, "drag": 0.03, "damage": 0.0, "sound": "metal"},
	"bike_rack": {"family": "light", "radius": 1.2, "drag": 0.06, "damage": 1.0, "sound": "metal"},
	"pallet_stack": {"family": "light", "radius": 0.75, "drag": 0.06, "damage": 1.0, "sound": "wood"},
	"tire_stack": {"family": "light", "radius": 0.75, "drag": 0.04, "damage": 0.5, "sound": "wood"},
	"drums": {"family": "light", "radius": 0.65, "drag": 0.06, "damage": 1.0, "sound": "metal"},
	"cafe_parasol_b": {"family": "light", "radius": 0.9, "drag": 0.05, "damage": 0.5, "sound": "wood"},
	"food_cart": {"family": "light", "radius": 0.9, "drag": 0.1, "damage": 2.0, "sound": "metal"},
	"ice_freezer": {"family": "light", "radius": 0.6, "drag": 0.12, "damage": 2.0, "sound": "metal"},
	"clothes_rack": {"family": "light", "radius": 0.8, "drag": 0.02, "damage": 0.0, "sound": "metal"},
	"flower_buckets": {"family": "light", "radius": 0.7, "drag": 0.02, "damage": 0.0, "sound": "metal"},
	"gas_cylinders": {"family": "light", "radius": 0.55, "drag": 0.05, "damage": 1.0, "sound": "metal"},
	"door_bench": {"family": "light", "radius": 0.65, "drag": 0.04, "damage": 0.5, "sound": "wood"},
	"motorcycle": {"family": "light", "radius": 1.0, "drag": 0.18, "damage": 4.0, "sound": "metal"},
}

static var cells := {}


## Poste com nó próprio (HarborProp3D lamp, StreetLight_*). `pool` é a mancha de
## luz do CityLook (MultiMesh + índice) para apagar junto.
static func register_node(kind: String, root: Node3D, chunk: Node3D, pool: Dictionary = {}, colliders: Array = [], contact_radius := -1.0) -> void:
	if root.has_meta("street_fragile_registered"): return
	root.set_meta("street_fragile_registered",true)
	var radius: float = KINDS.get(kind,KINDS.trash_can).radius
	if contact_radius > 0.0: radius = contact_radius
	if kind == "bench_seat":
		var meshes: Array = root.find_children("*","MeshInstance3D",true,false)
		if root is MeshInstance3D: meshes.append(root)
		for mesh in meshes:
			if not mesh.has_meta("bench_envelope"): continue
			var size: Vector3 = mesh.get_meta("bench_envelope")
			radius = maxf(radius,Vector2(size.x*mesh.global_basis.x.length(),size.z*mesh.global_basis.z.length()).length()*.5)
	_register({"kind": kind, "root": weakref(root), "chunk": weakref(chunk), "point": root.global_position, "radius":radius, "pool": pool, "colliders": colliders.map(func(shape): return weakref(shape)), "state": "standing"})


## Mobília em MultiMesh (CityLook): anima a instância.
static func register_instance(kind: String, multimesh: MultiMesh, index: int, chunk: Node3D, extra: Array = [], colliders: Array = [], visual: MultiMeshInstance3D = null) -> void:
	var xform := multimesh.get_instance_transform(index)
	var point := chunk.global_transform * xform.origin
	var item := {"kind": kind, "multimesh": multimesh, "index": index, "extra": extra, "colliders": colliders.map(func(shape): return weakref(shape)), "chunk": weakref(chunk), "base": xform, "point": point, "state": "standing"}
	if visual != null: item.visual = weakref(visual)
	_register(item)


static func _register(item: Dictionary) -> void:
	var key := _key(item.point)
	if not cells.has(key): cells[key] = []
	cells[key].append(item)


static func _key(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.z / CELL))


## Itens em pé perto de `point` (limpa os de chunks descarregados).
static func query(point: Vector3, radius: float) -> Array:
	var result := []
	var low := _key(point - Vector3(radius, 0, radius))
	var high := _key(point + Vector3(radius, 0, radius))
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			var key := Vector2i(x, z)
			if not cells.has(key): continue
			var list: Array = cells[key]
			for index in range(list.size() - 1, -1, -1):
				var item: Dictionary = list[index]
				var chunk = item.chunk.get_ref()
				if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():
					list.remove_at(index)
					continue
				# The chunk can outlive an editor-deleted prop or remain in the
				# tree while retirement hides it. Neither is a visible obstacle.
				if item.has("root"):
					var source = item.root.get_ref()
					if not is_instance_valid(source) or source.is_queued_for_deletion():
						list.remove_at(index)
						continue
					if not source.is_inside_tree() or not source.is_visible_in_tree(): continue
				if item.has("visual"):
					var visual = item.visual.get_ref()
					if not is_instance_valid(visual) or visual.is_queued_for_deletion():
						list.remove_at(index)
						continue
					if not visual.is_inside_tree() or not visual.is_visible_in_tree(): continue
					if visual.multimesh != item.multimesh or item.index >= visual.multimesh.instance_count:
						list.remove_at(index)
						continue
					if visual.multimesh.visible_instance_count >= 0 and item.index >= visual.multimesh.visible_instance_count: continue
				if not chunk.is_inside_tree() or not chunk.is_visible_in_tree(): continue
				if item.state == "standing": result.append(item)
			if list.is_empty(): cells.erase(key)
	return result


static func spec(item: Dictionary) -> Dictionary:
	return KINDS.get(item.kind, KINDS.trash_can)


## Choque do carro. Retorna true se o item cedeu (o carro deve atravessar).
static func hit(item: Dictionary, speed: float, direction: Vector3, director: Node) -> bool:
	if item.state != "standing" or speed < WOBBLE_SPEED: return false
	if item.has("root") and preload("res://gameplay/DamageProtection.gd").is_protected(item.root.get_ref()): return false
	var flat := Vector3(direction.x, 0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	var profile := spec(item)
	var family: String = profile.family
	# Repeated bumper contacts must not leave wobble tweens fighting the fall.
	var wobble: Tween = item.get("wobble")
	if wobble != null and wobble.is_valid():
		wobble.kill()
		_set_transform(item, _base(item))
	item.erase("wobble")
	director.play_prop_hit(item.point, profile.sound, speed)
	if speed < float(profile.get("fall_speed", FALL_SPEED)) and family == "post":
		_wobble(item, flat, director)
		return false
	if item.kind == "lamp": preload("res://gameplay/street_physics/LampRecovery3D.gd").capture(item)
	item.state = "down"
	match family:
		"post":
			if speed >= 16.0 and not profile.get("anchored", false):
				_kill_light(item)
				_tumble(item, flat, speed, director)
				if item.kind == "phone_booth": director.spawn_glass(item.point + Vector3.UP, flat)
			else: _topple(item, flat, director)
		"hydrant": _burst_hydrant(item, flat, speed, director)
		_: _tumble(item, flat, speed, director)
	if item.kind == "lamp": preload("res://gameplay/street_physics/LampRecovery3D.gd").schedule(item, director)
	return true


static func _set_transform(item: Dictionary, xform: Transform3D) -> void:
	if item.has("multimesh"):
		item.multimesh.set_instance_transform(item.index, xform)
		# Peças irmãs (lente do semáforo) acompanham a mesma rotação na base.
		for extra in item.extra:
			var local: Transform3D = extra.offset
			extra.multimesh.set_instance_transform(extra.index, xform * local)
	else:
		var root = item.root.get_ref()
		if is_instance_valid(root): root.global_transform = xform


static func _base(item: Dictionary) -> Transform3D:
	if item.has("multimesh"): return item.base
	var root = item.root.get_ref()
	if not item.has("base_global") and is_instance_valid(root): item.base_global = root.global_transform
	return item.get("base_global", Transform3D.IDENTITY)


static func _wobble(item: Dictionary, flat: Vector3, director: Node) -> void:
	var base := _base(item)
	var axis := Vector3.UP.cross(flat).normalized()
	var tween: Tween = director.create_tween()
	item.wobble = tween
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(func(a: float): _set_transform(item, Transform3D(Basis(axis, a) * base.basis, base.origin)), 0.0, 0.09, 0.12)
	tween.tween_method(func(a: float): _set_transform(item, Transform3D(Basis(axis, a) * base.basis, base.origin)), 0.09, 0.0, 0.35)


## Tomba girando na base (V1: quad-in em 0,7 s até ~88°) com quique curto.
static func _topple(item: Dictionary, flat: Vector3, director: Node) -> void:
	var base := _base(item)
	var axis := Vector3.UP.cross(flat).normalized()
	_disable_collision(item)
	_kill_light(item)
	var tween: Tween = director.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var rotate := func(a: float): _set_transform(item, Transform3D(Basis(axis, a) * base.basis, base.origin))
	tween.tween_method(rotate, 0.0, PI * 0.49, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): director.play_prop_hit(base.origin + flat * 2.5, "metal", 3.0))
	tween.tween_method(rotate, PI * 0.49, PI * 0.46, 0.08)
	tween.tween_method(rotate, PI * 0.46, PI * 0.49, 0.12)
	if item.kind == "phone_booth": director.spawn_glass(base.origin + Vector3.UP, flat)
	var cleanup := director.create_tween()
	cleanup.tween_interval(10.0)
	cleanup.tween_callback(func(): _fade_post(item))


## Objeto leve vira corpo rígido: sai com a velocidade que o para-choque
## transfere, bate em parede/meio-fio/carro de verdade e para onde a física
## deixar. Antes era um arco em tween com distância fixa, que atravessava
## prédio e carro e pousava sempre igual.
static func _tumble(item: Dictionary, flat: Vector3, speed: float, director: Node) -> void:
	var base := _base(item)
	var mesh: Mesh = null
	var node_copy: Node3D = null
	if item.has("multimesh"):
		_disable_collision(item)
		mesh = item.multimesh.mesh
		# Escala zero some com a instância original; a cópia física assume.
		var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), base.origin)
		item.multimesh.set_instance_transform(item.index, hidden)
		for extra in item.extra: extra.multimesh.set_instance_transform(extra.index, hidden)
		# A instância é local ao chunk; o destroço vive no mundo.
		var chunk = item.chunk.get_ref()
		if is_instance_valid(chunk): base = chunk.global_transform * base
	else:
		_disable_collision(item)
		var root = item.root.get_ref()
		if is_instance_valid(root):
			node_copy = root.duplicate(0)
			node_copy.set_script(null)
			for body in node_copy.find_children("*", "CollisionObject3D", true, false): body.free()
			root.visible = false
	# Carro pesa ~100x o objeto: sai a ~(1+e) vezes a velocidade do carro no
	# sentido do choque (e≈0,3 para metal amassando), um pouco para cima porque
	# o para-choque pega abaixo do centro de massa.
	var side := Vector3.UP.cross(flat).normalized()
	var launch := flat * speed * randf_range(0.95, 1.3) + side * speed * randf_range(-0.15, 0.15) + Vector3.UP * clampf(speed * 0.18, 0.5, 4.0)
	launch = launch.limit_length(26.0)
	var spin := side * clampf(speed * 1.6, 2.0, 22.0) + Vector3.UP * randf_range(-4.0, 4.0)
	if item.kind == "trash_can":
		_break_trash_can(base, launch, spin, director)
		return
	if (speed >= FALL_SPEED and item.kind in ["bench_seat","planter","pallet"]) or (speed >= 10.0 and item.kind in ["desert_rock", "desert_tree", "lamp", "signal_pole", "stop_sign", "phone_booth"]):
		var source := node_copy
		if source != null: source.transform = Transform3D(base.basis, Vector3.ZERO)
		if source == null:
			source = MeshInstance3D.new()
			source.mesh = mesh
		source.transform = Transform3D(base.basis, Vector3.ZERO)
		var shards := preload("res://gameplay/street_physics/PropFracture3D.gd").split(source, 1 if item.kind == "desert_tree" or spec(item).family == "post" else 0)
		if not shards.is_empty():
			for index in shards.size():
				var fragment := _debris_body(director, base.origin, float(MASSES.get(item.kind, 15.0)) / shards.size())
				fragment.add_child(shards[index])
				_add_box_shape(fragment, shards[index].get_aabb())
				fragment.linear_velocity = launch + side * (float(index) - 1.0) * minf(speed * .1, 3.0)
				fragment.angular_velocity = spin * (0.6 + float(index) * .3)
			source.free()
			return
		if node_copy == null: source.free()
	var piece := _debris_body(director, base.origin, MASSES.get(item.kind, 15.0))
	if mesh != null:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.transform = Transform3D(base.basis, Vector3.ZERO)
		piece.add_child(visual)
		_add_box_shape(piece, visual.transform * mesh.get_aabb())
	elif node_copy != null:
		piece.add_child(node_copy)
		node_copy.transform = Transform3D(base.basis, Vector3.ZERO)
		if node_copy is MeshInstance3D:
			_add_box_shape(piece, node_copy.transform * node_copy.get_aabb())
		else:
			_add_box_shape(piece, _local_aabb(node_copy))
	piece.linear_velocity = launch
	piece.angular_velocity = spin
	if item.kind == "news_box": director.spawn_glass(base.origin, flat)
	if item.kind == "mailbox": _spill_later(director, piece, flat, 0.5)


## Lixeira: o corpo amassa e voa, a tampa solta e sai por conta própria, e o
## lixo espalha onde o corpo parar de rolar (não num ponto pré-calculado).
static func _break_trash_can(base: Transform3D, launch: Vector3, spin: Vector3, director: Node) -> void:
	var can := _debris_body(director, base.origin, MASSES.trash_can)
	var shell := CylinderMesh.new()
	shell.top_radius = 0.29
	shell.bottom_radius = 0.26
	shell.height = 0.82
	shell.radial_segments = 7
	shell.rings = 1
	shell.material = _flat_material(Color("2f5a43"))
	var shell_visual := MeshInstance3D.new()
	shell_visual.mesh = shell
	# Amassado do para-choque: achata no sentido do choque.
	var dent := Vector3(launch.x, 0, launch.z).normalized()
	if dent.length_squared() < 0.01: dent = Vector3.FORWARD
	shell_visual.transform = Transform3D(Basis.looking_at(dent, Vector3.UP).scaled(Vector3(1.0, 1.0, randf_range(0.72, 0.86))), Vector3.UP * 0.41)
	can.add_child(shell_visual)
	_add_cylinder_shape(can, 0.27, 0.82, Vector3.UP * 0.41)
	can.linear_velocity = launch
	can.angular_velocity = spin
	var lid := _debris_body(director, base.origin + Vector3.UP * 0.88, 1.2)
	var lid_mesh := CylinderMesh.new()
	lid_mesh.top_radius = 0.22
	lid_mesh.bottom_radius = 0.31
	lid_mesh.height = 0.08
	lid_mesh.radial_segments = 7
	lid_mesh.rings = 1
	lid_mesh.material = _flat_material(Color("1f3a2c"))
	var lid_visual := MeshInstance3D.new()
	lid_visual.mesh = lid_mesh
	lid.add_child(lid_visual)
	_add_cylinder_shape(lid, 0.3, 0.08, Vector3.ZERO)
	# Tampa é leve e está no alto: sobe mais e gira solta.
	lid.linear_velocity = launch * randf_range(0.8, 1.15) + Vector3(randf_range(-1, 1), randf_range(1.5, 3.5), randf_range(-1, 1))
	lid.angular_velocity = Vector3(randf_range(-15, 15), randf_range(-10, 10), randf_range(-15, 15))
	# Parte cai no choque (boca aberta); o resto onde a lata parar.
	director.spawn_litter(base.origin, dent)
	_spill_later(director, can, dent, 0.8)


const DEBRIS_LAYER := 8
const MAX_DEBRIS := 18
const DEBRIS_LIFETIME := 10.0
## kg; o carro leva ~1200 kg.
const MASSES := {"trash_can": 11.0, "news_box": 28.0, "mailbox": 45.0, "hydrant": 60.0, "bench_seat": 55.0, "dumpster": 100.0, "trash_bags": 5.0, "planter": 90.0, "desert_rock": 180.0, "desert_tree": 35.0, "lamp": 90.0, "signal_pole": 120.0, "stop_sign": 18.0, "phone_booth": 200.0,
	"cafe_set": 14.0, "cafe_parasol": 18.0, "produce_stand": 30.0, "a_frame": 6.0, "beer_crates": 16.0, "pot_plant": 25.0, "wheelie_bins": 22.0, "bike_rack": 40.0, "pallet_stack": 60.0, "tire_stack": 45.0, "drums": 50.0,
	"cafe_parasol_b": 18.0, "food_cart": 60.0, "ice_freezer": 70.0, "clothes_rack": 12.0, "flower_buckets": 15.0, "gas_cylinders": 45.0, "door_bench": 15.0, "motorcycle": 150.0}
static var _debris: Array = []


static func _debris_body(director: Node, origin: Vector3, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "StreetDebris"
	body.mass = mass
	body.collision_layer = DEBRIS_LAYER
	# Só o mundo no começo: o objeto nasce encostado no carro que o acertou e
	# colidir com ele no primeiro quadro o expulsaria com impulso absurdo.
	body.collision_mask = 1
	body.continuous_cd = true
	body.linear_damp = 0.05
	body.angular_damp = 0.4
	var material := PhysicsMaterial.new()
	material.friction = 0.8
	material.bounce = 0.2
	body.physics_material_override = material
	director.add_child(body)
	body.global_position = origin
	var tree: SceneTree = director.get_tree()
	# Depois de se afastar, carro que passar por cima empurra o destroço.
	tree.create_timer(0.35, false, true).timeout.connect(func():
		if is_instance_valid(body): body.collision_mask = 1 | 4 | DEBRIS_LAYER)
	preload("res://gameplay/DestroyedFade3D.gd").schedule(body, DEBRIS_LIFETIME)
	var alive := []
	for ref in _debris:
		if is_instance_valid(ref.get_ref()): alive.append(ref)
	alive.append(weakref(body))
	while alive.size() > MAX_DEBRIS:
		var oldest = alive.pop_front().get_ref()
		if is_instance_valid(oldest): preload("res://gameplay/DestroyedFade3D.gd").fade(oldest)
	_debris = alive
	return body


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


static func _local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = root.transform * _relative(root, mesh) * mesh.get_aabb()
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
		director.play_prop_hit(at, "metal", 1.5))


## Hidrante arranca voando e deixa um gêiser (V1 não tinha; é o clássico de GTA).
static func _burst_hydrant(item: Dictionary, flat: Vector3, speed: float, director: Node) -> void:
	var base := _base(item)
	_tumble(item, flat, speed * 0.7, director)
	director.spawn_geyser(base.origin)


static func _disable_collision(item: Dictionary) -> void:
	for reference in item.get("colliders",[]):
		var shape = reference.get_ref()
		if is_instance_valid(shape): shape.disabled = true
	if item.has("multimesh"): return
	var root = item.root.get_ref()
	if not is_instance_valid(root): return
	for body in root.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0
		body.collision_mask = 0


static func _kill_light(item: Dictionary) -> void:
	var pool: Dictionary = item.get("pool", {})
	if not pool.is_empty() and is_instance_valid(pool.get("multimesh")):
		# Escala zero some com a mancha de luz desse poste só.
		pool.multimesh.set_instance_transform(pool.index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	if item.has("multimesh"): return
	var root = item.root.get_ref()
	if not is_instance_valid(root): return
	for light in root.find_children("*", "Light3D", true, false):
		light.set_meta("street_destroyed", true)
		light.light_energy = 0.0
		light.visible = false
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override == preload("res://world/city_look/CityLookMaterials.gd").lamp_head():
			mesh.material_override = preload("res://world/city_look/CityLookMaterials.gd").flat(Color("5a5f61"), 0.6)


static func _fade_post(item: Dictionary) -> void:
	# Preserve the original lamp and its registration for delayed recovery.
	if item.kind == "lamp":
		if item.has("multimesh"):
			var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
			item.multimesh.set_instance_transform(item.index, hidden)
			for part in item.extra: part.multimesh.set_instance_transform(part.index, hidden)
		else:
			var source = item.root.get_ref()
			if is_instance_valid(source): source.visible = false
		return
	if not item.has("multimesh"):
		var root = item.root.get_ref()
		if is_instance_valid(root): preload("res://gameplay/DestroyedFade3D.gd").fade(root)
		return
	var chunk = item.chunk.get_ref()
	if not is_instance_valid(chunk): return
	# Isolate just this fallen instance; fading a MultiMesh would hide intact posts.
	var remains := Node3D.new()
	chunk.add_child(remains)
	var parts: Array = [{"multimesh": item.multimesh, "index": item.index}]
	parts.append_array(item.extra)
	for part in parts:
		var batch: MultiMesh = part.multimesh
		var mesh := MeshInstance3D.new()
		mesh.mesh = batch.mesh
		mesh.transform = batch.get_instance_transform(part.index)
		remains.add_child(mesh)
		batch.set_instance_transform(part.index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	preload("res://gameplay/DestroyedFade3D.gd").fade(remains)
