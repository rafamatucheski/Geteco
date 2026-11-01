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
const KIND_DATA := preload("res://data/catalogs/FragilePropKinds.gd")
## Auxiliares estáticos (01/11, só para este arquivo caber na leitura): constantes, static var e as
## demais funções continuam aqui, e cada função antiga virou delegação de uma linha com a mesma
## assinatura, então quem chama FRAGILE.hit/query/launch_velocity/_kill_light por nome não muda.
const POST_FALL := preload("res://gameplay/street_physics/FragilePostFall.gd")
const TUMBLE := preload("res://gameplay/street_physics/FragileTumble.gd")
const DEBRIS_BODIES := preload("res://gameplay/street_physics/FragileDebrisBodies.gd")
## Este script, passado aos auxiliares para eles lerem e escreverem as static var e chamarem as funções
## daqui (eles não podem dar preload neste arquivo: este dá preload neles e seria ciclo). `load` na
## primeira chamada, quando o script já está no cache; é o mesmo objeto do preload de quem chama.
static var _self_script: GDScript
static func _owner_script() -> GDScript:
	if _self_script == null: _self_script = load("res://gameplay/street_physics/FragileProps3D.gd")
	return _self_script

## Tabela em data/catalogs/FragilePropKinds.gd, reexportada aqui com o mesmo nome.
const KINDS := KIND_DATA.KINDS

static var cells := {}


## Poste com nó próprio (HarborProp3D lamp, StreetLight_*). `pool` é a mancha de
## luz do CityLook (MultiMesh + índice) para apagar junto.
static func register_node(kind: String, root: Node3D, chunk: Node3D, pool: Dictionary = {}, colliders: Array = [], contact_radius := -1.0) -> void:
	# O registro vive com o móvel em cache, não com o chunk descartável.
	# As referências de raiz/colisão são fracas; não mantêm nós liberados vivos.
	var previous: Dictionary = root.get_meta("street_fragile_item", {})
	if not previous.is_empty() and previous.root.get_ref() == root:
		_rebind_node(previous, root, chunk, pool, colliders)
		return
	if root.has_meta("street_fragile_registered") and previous.is_empty(): return
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
	var item := {"kind": kind, "root": weakref(root), "chunk": weakref(chunk), "point": root.global_position, "radius":radius, "pool": pool, "colliders": colliders.map(func(shape): return weakref(shape)), "state": "standing"}
	root.set_meta("street_fragile_item", item)
	_register(item)

static func _rebind_node(item: Dictionary, root: Node3D, chunk: Node3D, pool: Dictionary, colliders: Array) -> void:
	var previous_chunk: Node = item.chunk.get_ref()
	var old_pool: Dictionary = item.get("pool", {})
	var old_key := _key(item.point)
	if cells.has(old_key): cells[old_key].erase(item)
	if cells.has(old_key) and cells[old_key].is_empty(): cells.erase(old_key)
	item.chunk = weakref(chunk)
	# O ponto de um poste derrubado continua sendo a base de sua recuperação.
	if str(item.state) == "standing": item.point = root.global_position
	if not colliders.is_empty(): item.colliders = colliders.map(func(shape): return weakref(shape))
	if not pool.is_empty():
		if item.has("recovery") and is_instance_valid(pool.get("multimesh")):
			var saved: Dictionary = item.recovery
			var replacement: Transform3D = pool.multimesh.get_instance_transform(pool.index)
			for part in saved.parts:
				if part[0] == old_pool.get("multimesh") and part[1] == old_pool.get("index", -1):
					replacement = part[2]
			saved.parts = saved.parts.filter(func(part): return part[0] != old_pool.get("multimesh"))
			saved.parts.append([pool.multimesh, pool.index, replacement])
		item.pool = pool
		if str(item.state) != "standing" and item.kind == "lamp": _kill_light(item)
	_register(item)
	# O timer anterior pertencia ao chunk que saiu. Retomar o prazo sem reviver o poste.
	if previous_chunk != chunk and item.has("recovery") and item.has("recovery_director"):
		var director: Node = item.recovery_director.get_ref()
		if is_instance_valid(director):
			var remaining := maxf(0.0, float(item.get("recovery_due_msec", Time.get_ticks_msec())) - Time.get_ticks_msec()) / 1000.0
			preload("res://gameplay/street_physics/LampRecovery3D.gd").schedule(item, director, remaining)


## Lote-pivô invisível (nunca vai a um MultiMeshInstance3D): uma instância na base de cada adereço
## cujas peças têm a origem no meio (poste e placa da serra). Registrado como instância principal,
## com as peças em `extra`, faz o tombo girar na base sem refazer malha. Malha vazia porque o
## servidor recusa recalcular o AABB de MultiMesh sem malha a cada set_instance_transform.
static var _pivot_mesh: ArrayMesh
static func pivot_batch(bases: Array) -> MultiMesh:
	if _pivot_mesh == null: _pivot_mesh = ArrayMesh.new()
	var pivots := MultiMesh.new()
	pivots.transform_format = MultiMesh.TRANSFORM_3D
	pivots.mesh = _pivot_mesh
	pivots.instance_count = bases.size()
	for i in bases.size(): pivots.set_instance_transform(i, bases[i])
	return pivots


## Mobília em MultiMesh (CityLook): anima a instância.
## Devolve o item para quem precisa acompanhar o estado (luz do poste da serra que caiu).
static func register_instance(kind: String, multimesh: MultiMesh, index: int, chunk: Node3D, extra: Array = [], colliders: Array = [], visual: MultiMeshInstance3D = null, contact_radius := -1.0) -> Dictionary:
	var xform := multimesh.get_instance_transform(index)
	var point := chunk.global_transform * xform.origin
	var item := {"kind": kind, "multimesh": multimesh, "index": index, "extra": extra, "colliders": colliders.map(func(shape): return weakref(shape)), "chunk": weakref(chunk), "base": xform, "point": point, "state": "standing"}
	if visual != null: item.visual = weakref(visual)
	if contact_radius > 0.0: item.radius = contact_radius
	_register(item)
	return item


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
				# O chunk pode sobreviver a um prop apagado no editor ou continuar na
				# árvore enquanto a aposentadoria o esconde. Nenhum dos dois é obstáculo visível.
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


## Carro que está batendo agora (só durante hit): o destroço ignora a colisão com ele no começo e
## sai para o lado dele em que estava, e o poste que tomba reconhece a lataria por baixo.
static var _hitter: WeakRef = null
static var _hitter_side := 0.0
static var _hit_sound := ""


## Choque do carro. Retorna true se o item cedeu (o carro deve atravessar).
## `vehicle` é opcional (testes chamam sem carro): sem ele o destroço sorteia o lado.
static func hit(item: Dictionary, speed: float, direction: Vector3, director: Node, vehicle: Node3D = null) -> bool:
	if item.state != "standing" or speed < WOBBLE_SPEED: return false
	_hitter = weakref(vehicle) if is_instance_valid(vehicle) else null
	_hitter_side = 0.0
	_hit_sound = str(spec(item).sound)
	if is_instance_valid(vehicle):
		var across := Vector3.UP.cross(Vector3(direction.x, 0, direction.z).normalized())
		_hitter_side = signf(across.dot((item.point as Vector3) - vehicle.global_position))
	var yielded := _hit(item, speed, direction, director)
	_hitter = null
	_hit_sound = ""
	return yielded


static func _hit(item: Dictionary, speed: float, direction: Vector3, director: Node) -> bool:
	if item.has("root") and preload("res://gameplay/DamageProtection.gd").is_protected(item.root.get_ref()): return false
	var flat := Vector3(direction.x, 0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	var profile := spec(item)
	var family: String = profile.family
	# Contatos repetidos de para-choque não podem deixar tweens de balanço brigando com a queda.
	var wobble: Tween = item.get("wobble")
	if wobble != null and wobble.is_valid():
		wobble.kill()
		_set_transform(item, _base(item))
	item.erase("wobble")
	# Small cover needs a quiet crunch, rather than a full car-crash sound per twig.
	var sound_speed := speed
	if item.kind in ["desert_shrub", "desert_stone", "desert_gravel", "desert_grass"]:
		sound_speed = clampf(speed * float(item.get("radius", profile.radius)) * .35, .8, 5.0)
	director.play_prop_hit(item.point, profile.sound, sound_speed)
	if speed < float(profile.get("fall_speed", FALL_SPEED)) and family == "post":
		_wobble(item, flat, director)
		return false
	if item.kind == "lamp": preload("res://gameplay/street_physics/LampRecovery3D.gd").capture(item)
	item.state = "down"
	item.fall_impact = speed
	match family:
		"post":
			if speed >= 16.0 and not profile.get("anchored", false):
				_kill_light(item)
				_tumble(item, flat, speed, director)
				if item.kind == "phone_booth": director.spawn_glass(item.point + Vector3.UP, flat)
			else: _topple(item, flat, director)
		"hydrant": _burst_hydrant(item, flat, speed, director)
		_: _tumble(item, flat, speed, director)
	if item.kind == "lamp":
		item.recovery_director = weakref(director)
		item.recovery_due_msec = Time.get_ticks_msec() + int(preload("res://gameplay/street_physics/LampRecovery3D.gd").DELAY * 1000.0)
		preload("res://gameplay/street_physics/LampRecovery3D.gd").schedule(item, director)
	return true


static func _set_transform(item: Dictionary, xform: Transform3D) -> void:
	if item.has("multimesh"):
		item.multimesh.set_instance_transform(item.index, xform)
		# Peças irmãs (lente do semáforo) acompanham a mesma rotação na base.
		for extra in item.extra:
			var local: Transform3D = extra.offset
			extra.multimesh.set_instance_transform(extra.index, xform * local)
		# Poste de energia (HarborUtilityLines): os fios presos nele seguem a ponta no balanço e
		# no tombo, até o chão; sem isto o fio ficaria pendurado no ar onde o poste estava.
		if item.has("wires"): preload("res://world/city_look/HarborUtilityLines.gd").follow(item, xform)
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


## Ângulo de repouso no chão (como a V1: ~88°) e camada dos carros (Vehicle.gd: layer 4).
const FALL_REST := PI * 0.49
const FALL_VEHICLE_MASK := 4
## Gravidade efetiva do tombo: haste presa na base, α = 1,5·g·G/L·sen θ. Com G = 1,6 o poste de
## 6 m deitava em ~0,9 s, perto dos 0,7 s do tween antigo; a árvore de 12 m cai mais devagar.
const FALL_GRAVITY := 9.8 * 1.6
## Tabela em data/catalogs/FragilePropKinds.gd, reexportada aqui com o mesmo nome.
const POST_HEIGHT := KIND_DATA.POST_HEIGHT
## Prazo máximo do tombo simulado; depois disso deita no chão de vez (carro parado em cima por um
## minuto inteiro é raro e não vale um raio por passo para sempre).
const FALL_MAX_SECONDS := 60.0
## Até quanto tempo depois do choque o carro que derrubou ainda pode estar sobre a base.
const HITTER_OVER_BASE_SECONDS := 2.5
static var _fall_serial := 0


## Tombo do poste com contato: corpo em FragilePostFall.gd (delegação de uma linha; mesmo nome e padrões).
static func _topple(item: Dictionary, flat: Vector3, director: Node) -> void: POST_FALL._topple(_owner_script(), item, flat, director)
static func _post_height(item: Dictionary, base: Transform3D) -> float: return POST_FALL._post_height(_owner_script(), item, base)
static func _step_fall(fall: Dictionary, director: Node, delta: float) -> bool: return POST_FALL._step_fall(_owner_script(), fall, director, delta)
static func _land(fall: Dictionary, director: Node, angle: float, _omega: float) -> bool: return POST_FALL._land(_owner_script(), fall, director, angle, _omega)
static func _apply_fall_angle(fall: Dictionary, angle: float) -> void: POST_FALL._apply_fall_angle(_owner_script(), fall, angle)
static func _post_direction(fall: Dictionary, angle: float) -> Vector3: return POST_FALL._post_direction(fall, angle)
static func _post_blocked(fall: Dictionary, space: PhysicsDirectSpaceState3D, angle: float) -> bool: return POST_FALL._post_blocked(_owner_script(), fall, space, angle)
static func _covers_base(fall: Dictionary, space: PhysicsDirectSpaceState3D, vehicle: Node3D) -> bool: return POST_FALL._covers_base(_owner_script(), fall, space, vehicle)
static func _free_angle(fall: Dictionary, space: PhysicsDirectSpaceState3D, free: float, blocked: float) -> float: return POST_FALL._free_angle(_owner_script(), fall, space, free, blocked)
## Objeto leve que vira corpo rígido e lançamento pela massa: corpo em FragileTumble.gd (delegação de uma linha; mesmo nome e padrões).
static func _tumble(item: Dictionary, flat: Vector3, speed: float, director: Node) -> void: TUMBLE._tumble(_owner_script(), item, flat, speed, director)
static func _break_trash_can(base: Transform3D, launch: Vector3, spin: Vector3, director: Node) -> void: TUMBLE._break_trash_can(_owner_script(), base, launch, spin, director)

const DEBRIS_LAYER := 8
const MAX_DEBRIS := 18
const DEBRIS_LIFETIME := 10.0
## Tabela em data/catalogs/FragilePropKinds.gd, reexportada aqui com o mesmo nome.
const MASSES := KIND_DATA.MASSES
const LID_MASS := 2.5
## Choque carro × objeto: conservação de momento com coeficiente de restituição baixo
## (lata amassando quase não devolve energia), contato de raspão (o para-choque não
## pega o centro de massa em cheio) e teto de impulso: o carro empurra no máximo
## IMPULSE_CAP N·s antes de o objeto escorregar de lado ou o carro passar por cima.
const CAR_MASS := 1200.0
const RESTITUTION := 0.15
const GLANCE := 0.8
const IMPULSE_CAP := 2400.0
const MAX_LAUNCH := 12.0
## Subida máxima (m/s): o para-choque pega abaixo do centro de massa, mas um objeto de
## rua não decola; com a gravidade do destroço o pulo fica em poucos centímetros.
const MAX_LIFT := 1.4
## Gravidade extra só do destroço: com 1 g a queda de um objeto de 30 kg em tela lia
## lenta, como coisa leve flutuando. 1,5 g encurta o arco sem mudar o alcance no chão.
const DEBRIS_GRAVITY := 1.5
static var _debris: Array = []


## (continua) Objeto leve que vira corpo rígido e lançamento pela massa: corpo em FragileTumble.gd.
static func launch_velocity(kind: String, speed: float, flat: Vector3, jitter := 1.0, lateral := 0.0) -> Vector3: return TUMBLE.launch_velocity(_owner_script(), kind, speed, flat, jitter, lateral)
static func launch_spin(kind: String, launch: Vector3, side: Vector3, yaw := 0.0) -> Vector3: return TUMBLE.launch_spin(_owner_script(), kind, launch, side, yaw)

## Tabela em data/catalogs/FragilePropKinds.gd, reexportada aqui com o mesmo nome.
const SOFT_KINDS := KIND_DATA.SOFT_KINDS
## Até esta massa o destroço é chutado pelo carro que encosta nele, em vez de ficar preso no
## para-choque; acima disso (entulho, caçamba) o carro só empurra pela física.
const KICK_MAX_MASS := 100.0
## Quanto tempo o destroço ignora o carro que o lançou / o carro que acabou de chutá-lo.
const HITTER_GRACE := 0.6
const KICK_GRACE := 0.5
const KICK_COOLDOWN_MS := 250
## Material físico duro e fofo, um de cada, retidos (antes um PhysicsMaterial novo por destroço).
static var _physical_materials := {}


## (continua) Objeto leve que vira corpo rígido e lançamento pela massa: corpo em FragileTumble.gd.
static func _deflect(velocity: Vector3, side: float, angle: float) -> Vector3: return TUMBLE._deflect(velocity, side, angle)
static func _random_spin(magnitude: float) -> Vector3: return TUMBLE._random_spin(magnitude)
static func _junk_pieces(kind: String) -> Array: return TUMBLE._junk_pieces(kind)

## Monta as malhas dos sacos soltos e começa a síntese dos sons no carregamento, longe do choque.
static func prewarm() -> void:
	for kind in preload("res://world/city_look/StreetJunkKit.gd").PILE_PIECES: _junk_pieces(kind)
	preload("res://gameplay/street_physics/PropImpactSounds.gd").prewarm()


## Corpos de destroço, materiais e formas: corpo em FragileDebrisBodies.gd (delegação de uma linha; mesmo nome e padrões).
static func _physics_material(soft: bool) -> PhysicsMaterial: return DEBRIS_BODIES._physics_material(_owner_script(), soft)
static func _kick_debris(body: RigidBody3D, other: Node, soft: bool, director: Node) -> void: DEBRIS_BODIES._kick_debris(_owner_script(), body, other, soft, director)
static func _debris_body(director: Node, origin: Vector3, mass: float, soft := false) -> RigidBody3D: return DEBRIS_BODIES._debris_body(_owner_script(), director, origin, mass, soft)

## A cópia física de uma instância de MultiMesh precisa do material e da cor dela. Sem isso a moita
## e a pedra do chão do deserto (cor por instância, vertex_color_use_as_albedo) saíam com o material
## branco padrão quando o carro passava (vídeo do playtest de 19/10). Mesmas opções do material de
## origem, só a cor muda: mesmo shader, nada compila no jogo. Uma cópia por cor, guardada.
static var _instance_materials := {}
## (continua) Corpos de destroço, materiais e formas: corpo em FragileDebrisBodies.gd.
static func _instance_material(item: Dictionary) -> Material: return DEBRIS_BODIES._instance_material(_owner_script(), item)
static func _flat_material(color: Color) -> StandardMaterial3D: return DEBRIS_BODIES._flat_material(color)
static func _add_box_shape(body: RigidBody3D, box: AABB) -> void: DEBRIS_BODIES._add_box_shape(body, box)
static func _add_cylinder_shape(body: RigidBody3D, radius: float, height: float, at: Vector3) -> void: DEBRIS_BODIES._add_cylinder_shape(body, radius, height, at)
static func _local_aabb(root: Node3D) -> AABB: return DEBRIS_BODIES._local_aabb(_owner_script(), root)
static func _relative(ancestor: Node3D, node: Node3D) -> Transform3D: return DEBRIS_BODIES._relative(ancestor, node)
static func _spill_later(director: Node, body: RigidBody3D, flat: Vector3, delay: float) -> void: DEBRIS_BODIES._spill_later(director, body, flat, delay)

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
	if spec(item).get("keep_fallen", false): return
	# O tombo simulado para aqui: some (ou é escondido para a recuperação) na pose em que está,
	# inclusive apoiado num carro; continuar escreveria a instância já escondida.
	item.fall_cancel = true
	# Preserva a luminária original e o registro dela para a recuperação atrasada.
	if item.get("kind", "") == "lamp":
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
		if is_instance_valid(root): preload("res://gameplay/DestroyedFade3D.gd").fade(root, true)
		return
	var chunk = item.chunk.get_ref()
	if not is_instance_valid(chunk): return
	# Isola só esta instância caída; fazer fade num MultiMesh esconderia postes intactos.
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
	preload("res://gameplay/DestroyedFade3D.gd").fade(remains, true)
