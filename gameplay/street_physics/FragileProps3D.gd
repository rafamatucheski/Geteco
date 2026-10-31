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
## fall_speed é a velocidade de APROXIMAÇÃO (componente na direção do poste, StreetPhysics._hit_props),
## não a do velocímetro: num choque a 45° do centro o carro precisa de ~1,4× esse valor.
## Playtest 29/10 ("tudo tá bem difícil de derrubar"): poste 6 → 4,5 m/s (16 km/h) e semáforo
## 8 → 6 m/s (22 km/h). Abaixo de ~4 m/s continua manobra de estacionar: o poste balança e segura
## o carro (test_slow_post_block cobre 0,4/2/4 m/s). Ambos seguem ancorados (16/10): tombam na
## base em qualquer velocidade, nunca saem voando.
## "sound" é o material do som (playtest 30/10, VehicleCrashAudio.PROP_VOICE): pole (chapa de poste e
## placa), can (lata/tambor), bag (saco, papelão, rede), plastic (plástico duro, pneu), wood, glass,
## concrete; "metal" fica só para o que é grande como carro (caçamba, moto) e usa a batida de veículo.
const KINDS := {
	"lamp": {"family": "post", "radius": 0.22, "drag": 0.30, "damage": 8.0, "sound": "pole", "anchored": true, "fall_speed": 4.5},
	"signal_pole": {"family": "post", "radius": 0.25, "drag": 0.35, "damage": 10.0, "sound": "pole", "anchored": true, "fall_speed": 6.0},
	"stop_sign": {"family": "post", "radius": 0.12, "drag": 0.06, "damage": 2.0, "sound": "pole"},
	"hydrant": {"family": "hydrant", "radius": 0.2, "drag": 0.18, "damage": 5.0, "sound": "pole"},
	"trash_can": {"family": "light", "radius": 0.3, "drag": 0.03, "damage": 0.0, "sound": "can"},
	"news_box": {"family": "light", "radius": 0.45, "drag": 0.05, "damage": 1.0, "sound": "pole"},
	"mailbox": {"family": "light", "radius": 0.3, "drag": 0.06, "damage": 1.0, "sound": "pole"},
	"phone_booth": {"family": "post", "radius": 0.5, "drag": 0.22, "damage": 6.0, "sound": "glass"},
	"bench_seat": {"family": "light", "radius": 1.4, "drag": 0.12, "damage": 3.0, "sound": "wood"},
	"dumpster": {"family": "light", "radius": 1.2, "drag": 0.16, "damage": 4.0, "sound": "metal"},
	"trash_bags": {"family": "light", "radius": 0.6, "drag": 0.01, "damage": 0.0, "sound": "bag"},
	"planter": {"family": "light", "radius": 0.78, "drag": 0.18, "damage": 5.0, "sound": "concrete"},
	"barrel": {"family": "light", "radius": 0.37, "drag": 0.04, "damage": 1.0, "sound": "can"},
	"pallet": {"family": "light", "radius": 1.2, "drag": 0.05, "damage": 1.0, "sound": "wood"},
	"desert_rock": {"family": "light", "radius": 1.1, "drag": 0.20, "damage": 7.0, "sound": "concrete"},
	"harbor_tree": {"family": "post", "radius": 0.4, "drag": 0.18, "damage": 5.0, "sound": "wood", "fall_speed": 3.0, "anchored": true},
	"desert_tree": {"family": "light", "radius": 0.4, "drag": 0.10, "damage": 3.0, "sound": "wood"},
	# Pinheiro de 8-13 m da mata (FishingWoodland/HarborCoastWoodland): tronco de 25-39 cm pede mais
	# que a árvore de calçada. Caído fica no chão (keep_fallen): sumir por transparência levaria
	# o material da mata ao passe alfa, pipeline que nenhum pré-aquecimento cobre.
	"woodland_tree": {"family": "post", "radius": 0.45, "drag": 0.25, "damage": 6.0, "sound": "wood", "fall_speed": 5.0, "anchored": true, "keep_fallen": true},
	# Placa de curva/divisa e balizador da serra (MountainTrafficSigns, MountainRoadside3D): mesmos
	# números da stop_sign. Ancorada e caída fica (keep_fallen): o destroço rígido (stop_sign a 16 m/s)
	# e o sumiço por transparência levariam o material da placa ao passe alfa, que nenhum
	# pré-aquecimento cobre (placa da 3ª onda num quadro de 864 ms, DestroyedFade3D). Volta de pé
	# quando a beira de estrada da serra é remontada.
	"mountain_sign": {"family": "post", "radius": 0.12, "drag": 0.06, "damage": 2.0, "sound": "pole", "anchored": true, "keep_fallen": true},
	# Placa de trânsito de beira de rua fora do CityLook (A-32b do Harbor em HarborTrafficSigns, aviso
	# de queda de pedras da passagem norte do deserto). Mesmos números e razões da mountain_sign: a face
	# é alpha scissor, então nada de destroço rígido nem sumiço por transparência; volta de pé quando o
	# trecho é remontado.
	"road_sign": {"family": "post", "radius": 0.12, "drag": 0.06, "damage": 2.0, "sound": "pole", "anchored": true, "keep_fallen": true},
	# Chão povoado do deserto (DesertGroundCover): moita grande e pedra solta.
	"desert_shrub": {"family": "light", "radius": 0.55, "drag": 0.04, "damage": 0.0, "sound": "wood"},
	"desert_stone": {"family": "light", "radius": 0.45, "drag": 0.18, "damage": 2.0, "sound": "concrete"},
	"desert_gravel": {"family": "light", "radius": 0.15, "drag": 0.0, "damage": 0.0, "sound": "concrete"},
	"desert_grass": {"family": "light", "radius": 0.25, "drag": 0.0, "damage": 0.0, "sound": "wood"},
	# Térreo da calçada (SidewalkFill): plástico, madeira e lata que o carro espalha.
	"cafe_set": {"family": "light", "radius": 0.85, "drag": 0.04, "damage": 0.5, "sound": "plastic"},
	"cafe_parasol": {"family": "light", "radius": 0.9, "drag": 0.05, "damage": 0.5, "sound": "wood"},
	"produce_stand": {"family": "light", "radius": 0.9, "drag": 0.05, "damage": 0.5, "sound": "wood"},
	"a_frame": {"family": "light", "radius": 0.35, "drag": 0.01, "damage": 0.0, "sound": "wood"},
	"beer_crates": {"family": "light", "radius": 0.45, "drag": 0.02, "damage": 0.0, "sound": "glass"},
	"pot_plant": {"family": "light", "radius": 0.38, "drag": 0.04, "damage": 0.5, "sound": "concrete"},
	"wheelie_bins": {"family": "light", "radius": 0.7, "drag": 0.03, "damage": 0.0, "sound": "plastic"},
	"bike_rack": {"family": "light", "radius": 1.2, "drag": 0.06, "damage": 1.0, "sound": "pole"},
	"pallet_stack": {"family": "light", "radius": 0.75, "drag": 0.06, "damage": 1.0, "sound": "wood"},
	"tire_stack": {"family": "light", "radius": 0.75, "drag": 0.04, "damage": 0.5, "sound": "plastic"},
	"drums": {"family": "light", "radius": 0.65, "drag": 0.06, "damage": 1.0, "sound": "can"},
	"cafe_parasol_b": {"family": "light", "radius": 0.9, "drag": 0.05, "damage": 0.5, "sound": "wood"},
	"food_cart": {"family": "light", "radius": 0.9, "drag": 0.1, "damage": 2.0, "sound": "pole"},
	"ice_freezer": {"family": "light", "radius": 0.6, "drag": 0.12, "damage": 2.0, "sound": "pole"},
	"clothes_rack": {"family": "light", "radius": 0.8, "drag": 0.02, "damage": 0.0, "sound": "pole"},
	"flower_buckets": {"family": "light", "radius": 0.7, "drag": 0.02, "damage": 0.0, "sound": "can"},
	"gas_cylinders": {"family": "light", "radius": 0.55, "drag": 0.05, "damage": 1.0, "sound": "pole"},
	"door_bench": {"family": "light", "radius": 0.65, "drag": 0.04, "damage": 0.5, "sound": "wood"},
	"motorcycle": {"family": "light", "radius": 1.0, "drag": 0.18, "damage": 4.0, "sound": "metal"},
	# Objetos soltos da rua (StreetJunk, 29/10): saco, papelão, caixote, rede e cadeira cedem quase sem
	# segurar o carro; entulho e caçamba de entulho pesam (seguram e amassam mais).
	"bag_single": {"family": "light", "radius": 0.35, "drag": 0.005, "damage": 0.0, "sound": "bag"},
	"bag_pile": {"family": "light", "radius": 0.75, "drag": 0.02, "damage": 0.0, "sound": "bag"},
	"bag_torn": {"family": "light", "radius": 0.6, "drag": 0.005, "damage": 0.0, "sound": "bag"},
	"cardboard": {"family": "light", "radius": 0.65, "drag": 0.01, "damage": 0.0, "sound": "bag"},
	"refuse_heap": {"family": "light", "radius": 1.05, "drag": 0.05, "damage": 0.5, "sound": "bag"},
	"wood_crates": {"family": "light", "radius": 0.7, "drag": 0.05, "damage": 1.0, "sound": "wood"},
	"fish_crates": {"family": "light", "radius": 0.7, "drag": 0.03, "damage": 0.5, "sound": "plastic"},
	"rusty_barrels": {"family": "light", "radius": 0.72, "drag": 0.08, "damage": 1.5, "sound": "can"},
	"rope_coil": {"family": "light", "radius": 0.55, "drag": 0.03, "damage": 0.0, "sound": "bag"},
	"fishing_net": {"family": "light", "radius": 0.8, "drag": 0.02, "damage": 0.0, "sound": "bag"},
	"loose_tires": {"family": "light", "radius": 0.65, "drag": 0.04, "damage": 0.5, "sound": "plastic"},
	"rubble": {"family": "light", "radius": 0.85, "drag": 0.15, "damage": 2.0, "sound": "concrete"},
	"rubble_skip": {"family": "light", "radius": 1.6, "drag": 0.35, "damage": 8.0, "sound": "metal"},
	"beach_parasol": {"family": "light", "radius": 0.5, "drag": 0.02, "damage": 0.0, "sound": "wood"},
	"beach_parasol_b": {"family": "light", "radius": 0.5, "drag": 0.02, "damage": 0.0, "sound": "wood"},
	"beach_chairs": {"family": "light", "radius": 0.85, "drag": 0.02, "damage": 0.0, "sound": "pole"},
	"plastic_chairs": {"family": "light", "radius": 0.55, "drag": 0.02, "damage": 0.0, "sound": "plastic"},
	"bar_table": {"family": "light", "radius": 1.0, "drag": 0.04, "damage": 0.5, "sound": "plastic"},
}

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
## Altura padrão quando a malha não diz (lote-pivô vazio sem peças, nó sem MeshInstance3D).
const POST_HEIGHT := {"lamp": 6.0, "signal_pole": 5.5, "stop_sign": 2.6, "road_sign": 2.6, "mountain_sign": 2.0,
	"harbor_tree": 5.0, "woodland_tree": 10.0, "phone_booth": 2.4}
## Prazo máximo do tombo simulado; depois disso deita no chão de vez (carro parado em cima por um
## minuto inteiro é raro e não vale um raio por passo para sempre).
const FALL_MAX_SECONDS := 60.0
## Até quanto tempo depois do choque o carro que derrubou ainda pode estar sobre a base.
const HITTER_OVER_BASE_SECONDS := 2.5
static var _fall_serial := 0


## Tomba girando na base, agora com contato (playtest 30/10: "as coisas que a gente bate passam
## pelos carros depois, por dentro, tipo poste. Tem que cair NO carro"). Antes era um tween fixo de
## 0,7 s até ~88° que atravessava o carro do jogador e o do tráfego. Agora cada passo de física:
## gravidade de haste presa na base, e um raio da ponta até a base na camada dos carros. No primeiro
## contato uma bissecção acha o ângulo de toque e o poste para ali, apoiado na lataria (quique
## pequeno e som de chapa no carro). Apoiado, um raio por passo confere se o carro ainda está
## embaixo; quando o carro sai, volta a cair até o chão. Sem RigidBody: só raios e a transformação
## da instância/nó, como o tween fazia. O carro que acertou só conta depois que a base sai de baixo
## dele (enquanto passa por cima da base, o poste "quebrado" passa pela frente sem travar).
static func _topple(item: Dictionary, flat: Vector3, director: Node) -> void:
	var base := _base(item)
	var hitter: Node3D = _hitter.get_ref() if _hitter != null else null
	if is_instance_valid(hitter):
		# Com o carro conhecido, o poste tomba para fora do caminho dele (~37° do rumo, do lado em
		# que estava): reto para a frente, o carro passava por baixo da base e o poste deitava por
		# dentro dele. Ainda cai por cima do capô/para-lama quando o carro avança junto.
		var side := _hitter_side if _hitter_side != 0.0 else (1.0 if randf() < 0.5 else -1.0)
		flat = (flat + Vector3.UP.cross(flat).normalized() * side * 0.75).normalized()
	var axis_world := Vector3.UP.cross(flat).normalized()
	_disable_collision(item)
	_kill_light(item)
	if item.kind == "phone_booth": director.spawn_glass(base.origin + Vector3.UP, flat)
	var chunk = item.chunk.get_ref()
	# A instância de MultiMesh é local ao chunk; os raios vivem no mundo.
	var to_world := Transform3D.IDENTITY
	if item.has("multimesh") and is_instance_valid(chunk): to_world = (chunk as Node3D).global_transform
	var axis_local := (to_world.basis.inverse() * axis_world).normalized() if item.has("multimesh") else axis_world
	var fall := {"item": item, "base": base, "pivot": to_world * base.origin, "axis_local": axis_local, "axis_world": axis_world,
		"length": _post_height(item, base), "angle": 0.0, "omega": clampf(0.6 + float(item.get("fall_impact", 4.0)) * 0.06, 0.8, 2.5),
		"resting": false, "landed": false, "age": 0.0, "bounces": 0,
		"hitter": weakref(hitter) if is_instance_valid(hitter) else null, "world": (director as Node3D).get_world_3d() if director is Node3D else null}
	# Só um número no item (não o próprio `fall`): o dicionário do item não pode se referir a si mesmo.
	_fall_serial += 1
	fall.id = _fall_serial
	item.fall_id = _fall_serial
	item.erase("fall_cancel")
	var tween: Tween = director.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	# Referência fraca: o tween guarda este passo; o passo guardar o tween seria um ciclo.
	var tween_ref: WeakRef = weakref(tween)
	var step := func(_v: float) -> void:
		if bool(fall.get("done", false)): return
		if not _step_fall(fall, director, director.get_physics_process_delta_time()):
			fall.done = true
			fall.erase("item")
			# Fora do passo do próprio tween: matar o tween dentro do callback dele não é seguro.
			var running: Tween = tween_ref.get_ref()
			if running != null and running.is_valid(): running.kill.call_deferred()
	tween.tween_method(step, 0.0, 1.0, FALL_MAX_SECONDS + 5.0)
	var cleanup := director.create_tween()
	cleanup.tween_interval(10.0)
	cleanup.tween_callback(func(): _fade_post(item))


## Altura do poste pela malha (instância principal ou peças irmãs do lote-pivô), em metros reais.
static func _post_height(item: Dictionary, base: Transform3D) -> float:
	var top := 0.0
	if item.has("multimesh"):
		var mesh: Mesh = item.multimesh.mesh
		if mesh != null: top = maxf(top, (base * mesh.get_aabb()).end.y - base.origin.y)
		for extra in item.extra:
			var part: Mesh = extra.multimesh.mesh
			if part != null: top = maxf(top, (base * (extra.offset as Transform3D) * part.get_aabb()).end.y - base.origin.y)
	else:
		var root = item.root.get_ref()
		if is_instance_valid(root):
			# Relativo à raiz, sem a posição dela (a altura do terreno não é altura do poste).
			var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
			if root is MeshInstance3D: meshes.append(root)
			for mesh: MeshInstance3D in meshes:
				if mesh.mesh == null: continue
				var local: Transform3D = Transform3D.IDENTITY if mesh == root else _relative(root, mesh)
				top = maxf(top, (local * mesh.get_aabb()).end.y)
			top *= absf(base.basis.y.length())
	if top < 0.8: top = float(POST_HEIGHT.get(item.kind, 4.0))
	return clampf(top, 0.8, 14.0)


## Um passo do tombo. Devolve false quando acabou (no chão, cancelado ou fora do mundo).
static func _step_fall(fall: Dictionary, director: Node, delta: float) -> bool:
	var item: Dictionary = fall.item
	if int(item.get("fall_id", -1)) != int(fall.id) or str(item.get("state", "")) != "down" or item.get("fall_cancel", false): return false
	var chunk = item.chunk.get_ref()
	if not is_instance_valid(chunk) or not chunk.is_inside_tree(): return false
	if delta <= 0.0: delta = 1.0 / 60.0
	fall.age = float(fall.age) + delta
	var space: PhysicsDirectSpaceState3D = (fall.world as World3D).direct_space_state if fall.world != null else null
	var angle: float = fall.angle
	var omega: float = fall.omega
	if fall.age > FALL_MAX_SECONDS: return _land(fall, director, FALL_REST, 0.0)
	if bool(fall.resting):
		# Apoiado no carro: confere a cada passo se ainda há lataria logo além do ângulo atual.
		if space != null and _post_blocked(fall, space, minf(angle + 0.03, FALL_REST)):
			# Ainda livre no ângulo atual: segue apoiado. Se o carro andou para dentro do poste (ré por
			# baixo dele), não levanta aos saltos: solta e o poste segue caindo por fora do contato.
			if not _post_blocked(fall, space, angle): return true
		fall.resting = false
		omega = 0.0
	var alpha := 1.5 * FALL_GRAVITY / float(fall.length) * sin(maxf(angle, 0.02))
	omega += alpha * delta
	var next := minf(angle + omega * delta, FALL_REST)
	# Já atravessado por um carro (entrou de lado no poste caindo): segue caindo, sem parar dentro dele.
	if space != null and next > angle and _post_blocked(fall, space, next) and not _post_blocked(fall, space, angle):
		# Bissecção entre o último ângulo livre e o que encostou: 5 raios, ~0,3° de erro.
		var contact := _free_angle(fall, space, angle, next)
		var tip_speed := absf(omega) * float(fall.length)
		_apply_fall_angle(fall, contact)
		fall.omega = -omega * 0.12
		if absf(omega) < 0.6 or int(fall.bounces) >= 2:
			fall.omega = 0.0
			fall.resting = true
		fall.bounces = int(fall.bounces) + 1
		if tip_speed > 1.0 and director.has_method("play_prop_hit"):
			var pivot: Vector3 = fall.pivot
			var tip: Vector3 = pivot + _post_direction(fall, contact) * float(fall.length) * 0.8
			# Material do poste batendo na lataria (a fila de contato só aceita um som por fonte por passo).
			director.play_prop_hit(tip, str(spec(item).sound), clampf(tip_speed, 1.5, 10.0))
		return true
	if next >= FALL_REST:
		# No chão: quique curto como o tween antigo (88° → 83° → 88°), depois parado.
		if absf(omega) > 1.2 and int(fall.bounces) < 3:
			if not bool(fall.landed) and director.has_method("play_prop_hit"):
				fall.landed = true
				var pivot: Vector3 = fall.pivot
				director.play_prop_hit(pivot + _post_direction(fall, FALL_REST) * minf(float(fall.length), 2.5), str(spec(item).sound), 3.0)
			fall.bounces = int(fall.bounces) + 1
			fall.omega = -omega * 0.18
			_apply_fall_angle(fall, FALL_REST)
			return true
		return _land(fall, director, FALL_REST, 0.0)
	fall.omega = omega
	_apply_fall_angle(fall, next)
	return true


static func _land(fall: Dictionary, director: Node, angle: float, _omega: float) -> bool:
	_apply_fall_angle(fall, angle)
	if not bool(fall.landed) and director.has_method("play_prop_hit"):
		var pivot: Vector3 = fall.pivot
		director.play_prop_hit(pivot + _post_direction(fall, angle) * minf(float(fall.length), 2.5), str(spec(fall.item).sound), 3.0)
	fall.landed = true
	return false


static func _apply_fall_angle(fall: Dictionary, angle: float) -> void:
	fall.angle = angle
	var base: Transform3D = fall.base
	_set_transform(fall.item, Transform3D(Basis(fall.axis_local, angle) * base.basis, base.origin))


static func _post_direction(fall: Dictionary, angle: float) -> Vector3:
	return Basis(fall.axis_world, angle) * Vector3.UP


## Raio da ponta até a base na camada dos carros. A ponta fica fora do carro quase sempre, então o
## raio entra pela lataria (o lado de dentro de um colisor não conta). O carro que derrubou só vale
## depois que a base saiu de baixo dele.
static func _post_blocked(fall: Dictionary, space: PhysicsDirectSpaceState3D, angle: float) -> bool:
	var pivot: Vector3 = fall.pivot
	var direction := _post_direction(fall, angle)
	var query := PhysicsRayQueryParameters3D.create(pivot + direction * float(fall.length), pivot + direction * 0.35, FALL_VEHICLE_MASK)
	query.collide_with_areas = false
	var exclude: Array[RID] = []
	var hitter: Node3D = fall.hitter.get_ref() if fall.hitter != null else null
	if is_instance_valid(hitter) and hitter is CollisionObject3D:
		# No choque o para-choque ainda está antes da base; logo depois o carro passa por cima dela.
		if _covers_base(fall, space, hitter): exclude.append((hitter as CollisionObject3D).get_rid())
		elif float(fall.age) > HITTER_OVER_BASE_SECONDS: fall.hitter = null
	query.exclude = exclude
	return not space.intersect_ray(query).is_empty()


## A base do poste ainda está sob a planta do carro que o derrubou (ponto a meio metro do chão).
static func _covers_base(fall: Dictionary, space: PhysicsDirectSpaceState3D, vehicle: Node3D) -> bool:
	var point := PhysicsPointQueryParameters3D.new()
	point.position = (fall.pivot as Vector3) + Vector3.UP * 0.5
	point.collision_mask = FALL_VEHICLE_MASK
	point.collide_with_areas = false
	for found in space.intersect_point(point, 4):
		if found.get("collider") == vehicle: return true
	return false


static func _free_angle(fall: Dictionary, space: PhysicsDirectSpaceState3D, free: float, blocked: float) -> float:
	for _iteration in 5:
		var middle := (free + blocked) * 0.5
		if _post_blocked(fall, space, middle): blocked = middle
		else: free = middle
	return free


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
	# Impulso pela massa do objeto (launch_velocity): antes todo objeto saía a
	# 0,95–1,3x a velocidade do carro e até 4 m/s para cima, a caçamba de 100 kg
	# igual à lata, e voava como papel (playtest de 29/10).
	var side := Vector3.UP.cross(flat).normalized()
	var launch := launch_velocity(str(item.kind), speed, flat, randf_range(0.85, 1.05), randf_range(-0.12, 0.12))
	var spin := launch_spin(str(item.kind), launch, side, randf_range(-1.0, 1.0))
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
	var soft: bool = item.kind in SOFT_KINDS
	if _hitter != null and not is_rock and not item.kind in ["desert_tree", "desert_shrub", "desert_grass"]:
		# Playtest 30/10 ("os lixos são arrastados... ficam coladas"): o objeto sai no máximo na
		# velocidade do carro (contrato do launch_velocity), então reto para a frente o carro o
		# alcançava, e quando a colisão com o carro ligava (0,35 s) o para-choque cinemático o
		# empurrava colado. Agora sai desviado para o lado em que estava (20°–46°, sorteado por
		# objeto): o carro passa e ele fica para trás, rolando para fora do caminho.
		launch = _deflect(launch, _hitter_side, randf_range(0.35, 0.8))
	if soft:
		# Saco, papelão, rede: leve e fofo, sobe um pouco e rola girando para qualquer lado.
		# Subida pela força do choque: empurrado devagar só rola, não pula (sobe no máximo ~0,3 m).
		launch.y = maxf(launch.y, randf_range(1.0, 2.4) * clampf(speed / 10.0, 0.25, 1.0))
		spin = _random_spin(clampf(speed * 0.5, 2.0, 7.0))
	elif not is_rock:
		# Caixote, lata, tambor: giro do tombo com um pouco de eixo sorteado, cada um de um jeito.
		spin += _random_spin(clampf(speed * 0.15, 0.4, 2.5)) * clampf(sqrt(30.0 / float(MASSES.get(item.kind, 15.0))), 0.3, 1.0)
	if mesh != null and not _junk_pieces(item.kind).is_empty():
		# Pilha de sacos: cada saco vira um destroço próprio, com rumo, subida e giro próprios.
		var pieces: Array = _junk_pieces(item.kind)
		var tint := _instance_material(item)
		for index in pieces.size():
			var bag := _debris_body(director, base.origin, maxf(1.0, float(MASSES.get(item.kind, 20.0)) * absf(base.basis.determinant()) / pieces.size()), true)
			var visual := MeshInstance3D.new()
			visual.mesh = pieces[index]
			visual.material_override = tint
			visual.transform = Transform3D(base.basis, Vector3.ZERO)
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bag.add_child(visual)
			_add_box_shape(bag, visual.transform * visual.mesh.get_aabb())
			var own := _deflect(launch, 1.0, randf_range(-0.45, 0.45)) * randf_range(0.7, 1.08)
			own.y = randf_range(0.8, 2.4) * clampf(speed / 10.0, 0.25, 1.0)
			bag.linear_velocity = own
			bag.angular_velocity = _random_spin(clampf(speed * 0.5, 2.0, 7.0))
		return
	if mesh != null and mesh.has_meta("street_fracture_meshes"):
		# A mesma fratura espacial das pedras bege, com cacos de origem compartilhados.
		# Escala, cores de vértice e tinta da instância sobrevivem à passagem para o MultiMesh.
		var shards: Array = mesh.get_meta("street_fracture_meshes")
		var material := _instance_material(item)
		for index in shards.size():
			var fragment := _debris_body(director, base.origin, maxf(.05, float(MASSES.get(item.kind, 1.0)) * absf(base.basis.determinant()) / shards.size()))
			var visual := MeshInstance3D.new()
			visual.mesh = shards[index]
			visual.material_override = material
			visual.transform = Transform3D(base.basis, Vector3.ZERO)
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fragment.add_child(visual)
			_add_box_shape(fragment, visual.transform * visual.mesh.get_aabb())
			var spread := clampf(speed * .16, .15, 4.0) if is_rock else .35
			fragment.linear_velocity = launch + side * (float(index) - float(shards.size() - 1) * .5) * spread
			if is_rock: fragment.linear_velocity.y *= .8 + float(index) * .2
			fragment.angular_velocity = spin * (.6 + float(index) * .3)
		return
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
				fragment.linear_velocity = launch + side * (float(index) - 1.0) * minf(speed * .1, 0.6 if item.kind == "desert_tree" else 3.0)
				fragment.angular_velocity = spin * (0.6 + float(index) * .3)
			source.free()
			return
		if node_copy == null: source.free()
	var piece := _debris_body(director, base.origin, MASSES.get(item.kind, 15.0), soft)
	if mesh != null:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = _instance_material(item)
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
		shell.material = _flat_material(Color("2f5a43"))
		shell_visual.mesh = shell
	# Amassado do para-choque: achata no sentido do choque.
	var dent := Vector3(launch.x, 0, launch.z).normalized()
	if dent.length_squared() < 0.01: dent = Vector3.FORWARD
	shell_visual.transform = Transform3D(Basis.looking_at(dent, Vector3.UP).scaled(Vector3(1.0, 1.0, randf_range(0.72, 0.86))), Vector3.ZERO if modeled else Vector3.UP * 0.41)
	can.add_child(shell_visual)
	_add_cylinder_shape(can, 0.27, 0.82, Vector3.UP * 0.41)
	can.linear_velocity = launch
	can.angular_velocity = spin
	var lid := _debris_body(director, base.origin + Vector3.UP * 0.88, LID_MASS)
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
		lid_mesh.material = _flat_material(Color("1f3a2c"))
		lid_visual.mesh = lid_mesh
	lid.add_child(lid_visual)
	_add_cylinder_shape(lid, 0.3, 0.08, Vector3.ZERO)
	# Tampa solta do alto: sai um pouco à frente e salta pouco (subia até 3,5 m/s e
	# girava a 15 rad/s, como folha de papel).
	lid.linear_velocity = launch * randf_range(0.8, 1.0) + Vector3(randf_range(-0.6, 0.6), randf_range(0.4, 1.2), randf_range(-0.6, 0.6))
	lid.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
	# Parte cai no choque (boca aberta); o resto onde a lata parar.
	director.spawn_litter(base.origin, dent)
	_spill_later(director, can, dent, 0.8)


const DEBRIS_LAYER := 8
const MAX_DEBRIS := 18
const DEBRIS_LIFETIME := 10.0
## kg, com o conteúdo (lata com lixo, caçamba de aço, vaso com terra). O carro leva ~1200 kg.
## 29/10: lata 11→28, caçamba 100→320, sacos 5→9, vaso 90→300 e afins; leves demais
## somavam ao lançamento antigo e tudo voava como papel.
const MASSES := {"trash_can": 28.0, "news_box": 45.0, "mailbox": 60.0, "hydrant": 60.0, "bench_seat": 70.0, "dumpster": 320.0, "trash_bags": 9.0, "planter": 300.0, "desert_rock": 180.0, "desert_tree": 35.0, "desert_shrub": 8.0, "desert_stone": 60.0, "lamp": 90.0, "signal_pole": 120.0, "stop_sign": 18.0, "phone_booth": 200.0,
	"cafe_set": 14.0, "cafe_parasol": 18.0, "produce_stand": 40.0, "a_frame": 8.0, "beer_crates": 25.0, "pot_plant": 40.0, "wheelie_bins": 35.0, "bike_rack": 40.0, "pallet_stack": 90.0, "tire_stack": 50.0, "drums": 80.0,
	"cafe_parasol_b": 18.0, "food_cart": 90.0, "ice_freezer": 90.0, "clothes_rack": 15.0, "flower_buckets": 20.0, "gas_cylinders": 60.0, "door_bench": 20.0, "motorcycle": 180.0, "barrel": 40.0, "pallet": 22.0,
	# StreetJunk: a caçamba de entulho cheia (~1,4 t) só escorrega; o monte de entulho pesa como um vaso.
	"bag_single": 6.0, "bag_pile": 24.0, "bag_torn": 5.0, "cardboard": 8.0, "refuse_heap": 45.0, "wood_crates": 40.0, "fish_crates": 25.0, "rusty_barrels": 90.0,
	"rope_coil": 25.0, "fishing_net": 20.0, "loose_tires": 30.0, "rubble": 250.0, "rubble_skip": 1400.0, "beach_parasol": 8.0, "beach_parasol_b": 8.0,
	"beach_chairs": 10.0, "plastic_chairs": 12.0, "bar_table": 18.0}
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


## Velocidade de saída do objeto `kind` acertado a `speed` m/s no sentido `flat`.
## `jitter` (≈0,85–1,05) e `lateral` (≈±0,12) vêm do chamador para o teste ser determinístico.
static func launch_velocity(kind: String, speed: float, flat: Vector3, jitter := 1.0, lateral := 0.0) -> Vector3:
	var mass := float(MASSES.get(kind, 15.0))
	var transfer := (1.0 + RESTITUTION) * CAR_MASS / (CAR_MASS + mass) * GLANCE
	var horizontal := minf(speed * transfer * jitter, minf(IMPULSE_CAP / mass, MAX_LAUNCH))
	var side := Vector3.UP.cross(flat).normalized()
	var lift := clampf(horizontal * 0.08, 0.2, MAX_LIFT)
	return flat * horizontal + side * horizontal * lateral + Vector3.UP * lift


## Giro de tombo: proporcional ao que o objeto andou e menor quanto mais pesado
## (antes até 22 rad/s em qualquer objeto, a lata rodopiava como folha).
static func launch_spin(kind: String, launch: Vector3, side: Vector3, yaw := 0.0) -> Vector3:
	var mass := float(MASSES.get(kind, 15.0))
	var horizontal := Vector2(launch.x, launch.z).length()
	var weight := clampf(sqrt(30.0 / mass), 0.35, 1.0)
	return side * clampf(horizontal * 0.5, 0.4, 7.0) * weight + Vector3.UP * yaw * 2.0 * weight


## Leves e fofos: sobem um pouco, rolam e quicam (saco, papelão, rede, cadeira de plástico).
const SOFT_KINDS := ["trash_bags", "bag_single", "bag_pile", "bag_torn", "cardboard", "fishing_net", "a_frame",
	"plastic_chairs", "beach_chairs", "clothes_rack", "flower_buckets", "cafe_parasol", "cafe_parasol_b", "beach_parasol", "beach_parasol_b"]
## Até esta massa o destroço é chutado pelo carro que encosta nele, em vez de ficar preso no
## para-choque; acima disso (entulho, caçamba) o carro só empurra pela física.
const KICK_MAX_MASS := 100.0
## Quanto tempo o destroço ignora o carro que o lançou / o carro que acabou de chutá-lo.
const HITTER_GRACE := 0.6
const KICK_GRACE := 0.5
const KICK_COOLDOWN_MS := 250
## Material físico duro e fofo, um de cada, retidos (antes um PhysicsMaterial novo por destroço).
static var _physical_materials := {}


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


## Monta as malhas dos sacos soltos e começa a síntese dos sons no carregamento, longe do choque.
static func prewarm() -> void:
	for kind in preload("res://world/city_look/StreetJunkKit.gd").PILE_PIECES: _junk_pieces(kind)
	preload("res://gameplay/street_physics/PropImpactSounds.gd").prewarm()


static func _physics_material(soft: bool) -> PhysicsMaterial:
	if not _physical_materials.has(soft):
		var material := PhysicsMaterial.new()
		# Duro: quique quase nulo (metal e madeira amassam). Fofo: escorrega menos e quica um pouco.
		material.friction = 0.6 if soft else 0.9
		material.bounce = 0.18 if soft else 0.06
		_physical_materials[soft] = material
	return _physical_materials[soft]


## Carro encostou num destroço solto: em vez de o para-choque cinemático levá-lo colado, o objeto é
## lançado para fora do caminho, para o lado em que está, com a transferência de momento pela massa
## (saco quase na velocidade do carro, tambor bem menos) e giro sorteado. O carro fica de fora por
## KICK_GRACE para o objeto se afastar; se ainda encostar depois, chuta de novo.
static func _kick_debris(body: RigidBody3D, other: Node, soft: bool, director: Node) -> void:
	if not is_instance_valid(body) or not other is CharacterBody3D or other.get("horizontal_velocity") == null: return
	var car := other as CharacterBody3D
	var planar := Vector3(car.velocity.x, 0, car.velocity.z)
	var speed := planar.length()
	# Carro parado ou manobrando: a física empurra devagar, sem chute.
	if speed < 1.2: return
	var now := Time.get_ticks_msec()
	if now - int(body.get_meta("street_kick_msec", -100000)) < KICK_COOLDOWN_MS: return
	body.set_meta("street_kick_msec", now)
	var forward := planar / speed
	var across := Vector3.UP.cross(forward)
	var side := signf(across.dot(body.global_position - car.global_position))
	var transfer := (1.0 + RESTITUTION) * CAR_MASS / (CAR_MASS + body.mass)
	var horizontal := minf(speed * transfer * randf_range(0.9, 1.1), 16.0)
	var out := _deflect(forward * horizontal, side, randf_range(0.45, 0.9))
	out.y = randf_range(1.0, 2.4) if soft else randf_range(0.3, 1.0)
	body.linear_velocity = out
	var weight := clampf(sqrt(30.0 / body.mass), 0.3, 1.0)
	body.angular_velocity = _random_spin(clampf(speed * (0.6 if soft else 0.3), 2.0, 9.0) * weight)
	body.add_collision_exception_with(car)
	body.get_tree().create_timer(KICK_GRACE, false, true).timeout.connect(func():
		if is_instance_valid(body) and is_instance_valid(car): body.remove_collision_exception_with(car))
	if is_instance_valid(director) and director.has_method("play_prop_hit"):
		director.play_prop_hit(body.global_position, str(body.get_meta("street_sound", "bag" if soft else "wood")), clampf(speed * 0.5, 1.0, 8.0))


static func _debris_body(director: Node, origin: Vector3, mass: float, soft := false) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "StreetDebris"
	body.mass = mass
	body.collision_layer = DEBRIS_LAYER
	# Só o mundo no começo: o objeto nasce encostado no carro que o acertou e
	# colidir com ele no primeiro quadro o expulsaria com impulso absurdo.
	body.collision_mask = 1
	body.continuous_cd = true
	# Amortecimento de objeto pesado arrastando no chão: com 0,05/0,4 deslizava e
	# girava longe depois do choque. O fofo freia no ar (arrasto do saco) mas rola solto.
	body.gravity_scale = 1.0 if soft else DEBRIS_GRAVITY
	body.linear_damp = 0.8 if soft else 0.3
	body.angular_damp = 0.5 if soft else 1.5
	body.physics_material_override = _physics_material(soft)
	director.add_child(body)
	body.global_position = origin
	var tree: SceneTree = director.get_tree()
	# O carro que lançou o objeto fica de fora por HITTER_GRACE: antes, quando a colisão com carros
	# ligava aos 0,35 s, o carro (mais rápido que o objeto) já estava em cima dele e o empurrava colado.
	var hitter: Node = _hitter.get_ref() if _hitter != null else null
	if is_instance_valid(hitter) and hitter is PhysicsBody3D:
		body.add_collision_exception_with(hitter)
		tree.create_timer(HITTER_GRACE, false, true).timeout.connect(func():
			if is_instance_valid(body) and is_instance_valid(hitter): body.remove_collision_exception_with(hitter))
	if mass <= KICK_MAX_MASS:
		# Carro que encostar depois (o mesmo ou outro) chuta o objeto para o lado em vez de levá-lo
		# no para-choque. Só sinal de contato: até MAX_DEBRIS corpos, nada por quadro.
		body.contact_monitor = true
		body.max_contacts_reported = 2
		body.body_entered.connect(func(other: Node): _kick_debris(body, other, soft, director))
	if not _hit_sound.is_empty(): body.set_meta("street_sound", _hit_sound)
	# Depois de se afastar, carro que passar por cima empurra o destroço.
	tree.create_timer(0.35, false, true).timeout.connect(func():
		if is_instance_valid(body): body.collision_mask = 1 | 4 | DEBRIS_LAYER)
	preload("res://gameplay/DestroyedFade3D.gd").schedule(body, DEBRIS_LIFETIME, true)
	var alive := []
	for ref in _debris:
		if is_instance_valid(ref.get_ref()): alive.append(ref)
	alive.append(weakref(body))
	while alive.size() > MAX_DEBRIS:
		var oldest = alive.pop_front().get_ref()
		if is_instance_valid(oldest): preload("res://gameplay/DestroyedFade3D.gd").fade(oldest, true)
	_debris = alive
	return body


## A cópia física de uma instância de MultiMesh precisa do material e da cor dela. Sem isso a moita
## e a pedra do chão do deserto (cor por instância, vertex_color_use_as_albedo) saíam com o material
## branco padrão quando o carro passava (vídeo do playtest de 19/10). Mesmas opções do material de
## origem, só a cor muda: mesmo shader, nada compila no jogo. Uma cópia por cor, guardada.
static var _instance_materials := {}
static func _instance_material(item: Dictionary) -> Material:
	var visual: Variant = item.visual.get_ref() if item.has("visual") else null
	if not is_instance_valid(visual): return null
	var source: Material = visual.material_override
	var multimesh: MultiMesh = item.multimesh
	if not source is StandardMaterial3D or not multimesh.use_colors: return source
	var color := multimesh.get_instance_color(int(item.index))
	var key := "%d:%s" % [source.get_instance_id(), color.to_html()]
	if not _instance_materials.has(key):
		if _instance_materials.size() > 64: _instance_materials.clear()
		var tinted := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
		tinted.albedo_color = source.albedo_color * color
		_instance_materials[key] = tinted
	return _instance_materials[key]

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
		director.play_prop_hit(at, "can", 1.5))


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
