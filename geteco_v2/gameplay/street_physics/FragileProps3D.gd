extends RefCounted
## Postes e mobiliário que o carro derruba (porte de StreetLamp/FixedTrafficSignal/
## BreakableProp da V1, grupo "fragile_road_post").
##
## V1: abaixo de 15 px/s nada; 15–35 px/s o poste balança; a partir de 35 px/s
## (2,2 m/s na direção do choque) ele tomba em 0,7 s, apaga, perde a colisão e o
## carro segue em frente. Mesmo limiar aqui, com três famílias:
## - "post": poste de luz, semáforo, placa — tomba girando na base;
## - "light": lixeira, jornaleiro, caixa de correio — voa e rola;
## - "hydrant": hidrante — arranca e vira gêiser por alguns segundos.
## O registro é espacial (células de 8 m) e não depende de corpo físico: a
## mobília do CityLook não tem colisão (não atrapalha pedestre), então a
## detecção é pela varredura do próprio carro (StreetPhysics.vehicle_pre_move).

const CELL := 8.0
const WOBBLE_SPEED := 15.0 / 16.0
const FALL_SPEED := 35.0 / 16.0

## raio de contato, perda de velocidade do carro ao atravessar, dano no carro.
const KINDS := {
	"lamp": {"family": "post", "radius": 0.22, "drag": 0.30, "damage": 8.0, "sound": "metal"},
	"signal_pole": {"family": "post", "radius": 0.25, "drag": 0.35, "damage": 10.0, "sound": "metal"},
	"stop_sign": {"family": "post", "radius": 0.12, "drag": 0.06, "damage": 2.0, "sound": "metal"},
	"hydrant": {"family": "hydrant", "radius": 0.2, "drag": 0.18, "damage": 5.0, "sound": "metal"},
	"trash_can": {"family": "light", "radius": 0.3, "drag": 0.03, "damage": 0.0, "sound": "metal"},
	"news_box": {"family": "light", "radius": 0.45, "drag": 0.05, "damage": 1.0, "sound": "metal"},
	"mailbox": {"family": "light", "radius": 0.3, "drag": 0.06, "damage": 1.0, "sound": "metal"},
	"phone_booth": {"family": "post", "radius": 0.5, "drag": 0.22, "damage": 6.0, "sound": "glass"},
}

static var cells := {}


## Poste com nó próprio (HarborProp3D lamp, StreetLight_*). `pool` é a mancha de
## luz do CityLook (MultiMesh + índice) para apagar junto.
static func register_node(kind: String, root: Node3D, chunk: Node3D, pool: Dictionary = {}) -> void:
	_register({"kind": kind, "root": weakref(root), "chunk": weakref(chunk), "point": root.global_position, "pool": pool, "state": "standing"})


## Mobília em MultiMesh (CityLook): anima a instância.
static func register_instance(kind: String, multimesh: MultiMesh, index: int, chunk: Node3D, extra: Array = []) -> void:
	var xform := multimesh.get_instance_transform(index)
	var point := chunk.global_transform * xform.origin
	_register({"kind": kind, "multimesh": multimesh, "index": index, "extra": extra, "chunk": weakref(chunk), "base": xform, "point": point, "state": "standing"})


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
				if item.state == "standing": result.append(item)
			if list.is_empty(): cells.erase(key)
	return result


static func spec(item: Dictionary) -> Dictionary:
	return KINDS.get(item.kind, KINDS.trash_can)


## Choque do carro. Retorna true se o item cedeu (o carro deve atravessar).
static func hit(item: Dictionary, speed: float, direction: Vector3, director: Node) -> bool:
	if item.state != "standing" or speed < WOBBLE_SPEED: return false
	var flat := Vector3(direction.x, 0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	var family: String = spec(item).family
	director.play_prop_hit(item.point, spec(item).sound, speed)
	if speed < FALL_SPEED and family == "post":
		_wobble(item, flat, director)
		return false
	item.state = "down"
	match family:
		"post": _topple(item, flat, director)
		"hydrant": _burst_hydrant(item, flat, speed, director)
		_: _tumble(item, flat, speed, director)
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
	tween.tween_method(func(a: float): _set_transform(item, Transform3D(Basis(axis, a) * base.basis, base.origin)), 0.0, 0.09, 0.12)
	tween.tween_method(func(a: float): _set_transform(item, Transform3D(Basis(axis, a) * base.basis, base.origin)), 0.09, 0.0, 0.35)


## Tomba girando na base (V1: quad-in em 0,7 s até ~88°) com quique curto.
static func _topple(item: Dictionary, flat: Vector3, director: Node) -> void:
	var base := _base(item)
	var axis := Vector3.UP.cross(flat).normalized()
	_disable_collision(item)
	_kill_light(item)
	var tween: Tween = director.create_tween()
	var rotate := func(a: float): _set_transform(item, Transform3D(Basis(axis, a) * base.basis, base.origin))
	tween.tween_method(rotate, 0.0, PI * 0.49, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): director.play_prop_hit(base.origin + flat * 2.5, "metal", 3.0))
	tween.tween_method(rotate, PI * 0.49, PI * 0.46, 0.08)
	tween.tween_method(rotate, PI * 0.46, PI * 0.49, 0.12)
	if item.kind == "phone_booth": director.spawn_glass(base.origin + Vector3.UP, flat)


## Objeto leve voa na direção do carro, gira e fica caído de lado.
static func _tumble(item: Dictionary, flat: Vector3, speed: float, director: Node) -> void:
	var base := _base(item)
	var travel := clampf(speed * 0.55, 1.2, 9.0)
	var side := Vector3.UP.cross(flat).normalized()
	var land := base.origin + flat * travel + side * randf_range(-0.8, 0.8)
	var peak := clampf(speed * 0.12, 0.4, 2.0)
	var axis := (side + Vector3.UP * randf_range(-0.3, 0.3)).normalized()
	var spins := randf_range(1.5, 3.0) * TAU
	var rest := Basis(side, PI * 0.5) * Basis(Vector3.UP, randf_range(-PI, PI)) * base.basis
	var tween: Tween = director.create_tween()
	tween.tween_method(func(t: float):
		var origin := base.origin.lerp(land, t) + Vector3.UP * (4.0 * peak * t * (1.0 - t))
		var basis := (Basis(axis, spins * t) * base.basis).slerp(rest, smoothstep(0.75, 1.0, t))
		_set_transform(item, Transform3D(basis, origin))
	, 0.0, 1.0, clampf(travel / maxf(speed * 0.6, 1.0), 0.35, 0.9))
	tween.tween_callback(func(): director.play_prop_hit(land, "metal", 1.5))
	if item.kind in ["trash_can"]: director.spawn_litter(land, flat)


## Hidrante arranca voando e deixa um gêiser (V1 não tinha; é o clássico de GTA).
static func _burst_hydrant(item: Dictionary, flat: Vector3, speed: float, director: Node) -> void:
	var base := _base(item)
	_tumble(item, flat, speed * 0.7, director)
	director.spawn_geyser(base.origin)


static func _disable_collision(item: Dictionary) -> void:
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
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override == preload("res://world/city_look/CityLookMaterials.gd").lamp_head():
			mesh.material_override = preload("res://world/city_look/CityLookMaterials.gd").flat(Color("5a5f61"), 0.6)
