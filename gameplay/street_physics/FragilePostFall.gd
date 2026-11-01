extends RefCounted
## Tombo do poste girando na base, com contato na lataria dos carros (gravidade de haste, raio da ponta à
## base, bissecção do ângulo de toque, apoio e quique). Separado de FragileProps3D.gd em 01/11 só para o
## dono caber na leitura. Tudo estático, como o dono: as constantes (FALL_REST, FALL_GRAVITY...), as
## static var (_hitter, _hitter_side, _fall_serial) e as demais funções continuam em FragileProps3D, que
## mantém cada função antiga como delegação de uma linha com a mesma assinatura. Este arquivo não dá
## preload no dono (o dono dá preload nele e seria ciclo): cada função que precisa dele recebe o
## script do dono em `g` e lê/escreve tudo dele por `g.`, inclusive as chamadas entre funções daqui.

## Tomba girando na base, agora com contato (playtest 30/10: "as coisas que a gente bate passam
## pelos carros depois, por dentro, tipo poste. Tem que cair NO carro"). Antes era um tween fixo de
## 0,7 s até ~88° que atravessava o carro do jogador e o do tráfego. Agora cada passo de física:
## gravidade de haste presa na base, e um raio da ponta até a base na camada dos carros. No primeiro
## contato uma bissecção acha o ângulo de toque e o poste para ali, apoiado na lataria (quique
## pequeno e som de chapa no carro). Apoiado, um raio por passo confere se o carro ainda está
## embaixo; quando o carro sai, volta a cair até o chão. Sem RigidBody: só raios e a transformação
## da instância/nó, como o tween fazia. O carro que acertou só conta depois que a base sai de baixo
## dele (enquanto passa por cima da base, o poste "quebrado" passa pela frente sem travar).
static func _topple(g: GDScript, item: Dictionary, flat: Vector3, director: Node) -> void:
	var base: Transform3D = g._base(item)
	var hitter: Node3D = g._hitter.get_ref() if g._hitter != null else null
	if is_instance_valid(hitter):
		# Com o carro conhecido, o poste tomba para fora do caminho dele (~37° do rumo, do lado em
		# que estava): reto para a frente, o carro passava por baixo da base e o poste deitava por
		# dentro dele. Ainda cai por cima do capô/para-lama quando o carro avança junto.
		var side: float = g._hitter_side if g._hitter_side != 0.0 else (1.0 if randf() < 0.5 else -1.0)
		flat = (flat + Vector3.UP.cross(flat).normalized() * side * 0.75).normalized()
	var axis_world := Vector3.UP.cross(flat).normalized()
	g._disable_collision(item)
	g._kill_light(item)
	if item.kind == "phone_booth": director.spawn_glass(base.origin + Vector3.UP, flat)
	var chunk = item.chunk.get_ref()
	# A instância de MultiMesh é local ao chunk; os raios vivem no mundo.
	var to_world := Transform3D.IDENTITY
	if item.has("multimesh") and is_instance_valid(chunk): to_world = (chunk as Node3D).global_transform
	var axis_local := (to_world.basis.inverse() * axis_world).normalized() if item.has("multimesh") else axis_world
	var fall := {"item": item, "base": base, "pivot": to_world * base.origin, "axis_local": axis_local, "axis_world": axis_world,
		"length": g._post_height(item, base), "angle": 0.0, "omega": clampf(0.6 + float(item.get("fall_impact", 4.0)) * 0.06, 0.8, 2.5),
		"resting": false, "landed": false, "age": 0.0, "bounces": 0,
		"hitter": weakref(hitter) if is_instance_valid(hitter) else null, "world": (director as Node3D).get_world_3d() if director is Node3D else null}
	# Só um número no item (não o próprio `fall`): o dicionário do item não pode se referir a si mesmo.
	g._fall_serial += 1
	fall.id = g._fall_serial
	item.fall_id = g._fall_serial
	item.erase("fall_cancel")
	var tween: Tween = director.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	# Referência fraca: o tween guarda este passo; o passo guardar o tween seria um ciclo.
	var tween_ref: WeakRef = weakref(tween)
	var step := func(_v: float) -> void:
		if bool(fall.get("done", false)): return
		if not g._step_fall(fall, director, director.get_physics_process_delta_time()):
			fall.done = true
			fall.erase("item")
			# Fora do passo do próprio tween: matar o tween dentro do callback dele não é seguro.
			var running: Tween = tween_ref.get_ref()
			if running != null and running.is_valid(): running.kill.call_deferred()
	tween.tween_method(step, 0.0, 1.0, g.FALL_MAX_SECONDS + 5.0)
	var cleanup := director.create_tween()
	cleanup.tween_interval(10.0)
	cleanup.tween_callback(func(): g._fade_post(item))

## Altura do poste pela malha (instância principal ou peças irmãs do lote-pivô), em metros reais.
static func _post_height(g: GDScript, item: Dictionary, base: Transform3D) -> float:
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
				var local: Transform3D = Transform3D.IDENTITY if mesh == root else g._relative(root, mesh)
				top = maxf(top, (local * mesh.get_aabb()).end.y)
			top *= absf(base.basis.y.length())
	if top < 0.8: top = float(g.POST_HEIGHT.get(item.kind, 4.0))
	return clampf(top, 0.8, 14.0)

## Um passo do tombo. Devolve false quando acabou (no chão, cancelado ou fora do mundo).
static func _step_fall(g: GDScript, fall: Dictionary, director: Node, delta: float) -> bool:
	var item: Dictionary = fall.item
	if int(item.get("fall_id", -1)) != int(fall.id) or str(item.get("state", "")) != "down" or item.get("fall_cancel", false): return false
	var chunk = item.chunk.get_ref()
	if not is_instance_valid(chunk) or not chunk.is_inside_tree(): return false
	if delta <= 0.0: delta = 1.0 / 60.0
	fall.age = float(fall.age) + delta
	var space: PhysicsDirectSpaceState3D = (fall.world as World3D).direct_space_state if fall.world != null else null
	var angle: float = fall.angle
	var omega: float = fall.omega
	if fall.age > g.FALL_MAX_SECONDS: return g._land(fall, director, g.FALL_REST, 0.0)
	if bool(fall.resting):
		# Apoiado no carro: confere a cada passo se ainda há lataria logo além do ângulo atual.
		if space != null and g._post_blocked(fall, space, minf(angle + 0.03, g.FALL_REST)):
			# Ainda livre no ângulo atual: segue apoiado. Se o carro andou para dentro do poste (ré por
			# baixo dele), não levanta aos saltos: solta e o poste segue caindo por fora do contato.
			if not g._post_blocked(fall, space, angle): return true
		fall.resting = false
		omega = 0.0
	var alpha: float = 1.5 * g.FALL_GRAVITY / float(fall.length) * sin(maxf(angle, 0.02))
	omega += alpha * delta
	var next := minf(angle + omega * delta, g.FALL_REST)
	# Já atravessado por um carro (entrou de lado no poste caindo): segue caindo, sem parar dentro dele.
	if space != null and next > angle and g._post_blocked(fall, space, next) and not g._post_blocked(fall, space, angle):
		# Bissecção entre o último ângulo livre e o que encostou: 5 raios, ~0,3° de erro.
		var contact: float = g._free_angle(fall, space, angle, next)
		var tip_speed := absf(omega) * float(fall.length)
		g._apply_fall_angle(fall, contact)
		fall.omega = -omega * 0.12
		if absf(omega) < 0.6 or int(fall.bounces) >= 2:
			fall.omega = 0.0
			fall.resting = true
		fall.bounces = int(fall.bounces) + 1
		if tip_speed > 1.0 and director.has_method("play_prop_hit"):
			var pivot: Vector3 = fall.pivot
			var tip: Vector3 = pivot + g._post_direction(fall, contact) * float(fall.length) * 0.8
			# Material do poste batendo na lataria (a fila de contato só aceita um som por fonte por passo).
			director.play_prop_hit(tip, str(g.spec(item).sound), clampf(tip_speed, 1.5, 10.0))
		return true
	if next >= g.FALL_REST:
		# No chão: quique curto como o tween antigo (88° → 83° → 88°), depois parado.
		if absf(omega) > 1.2 and int(fall.bounces) < 3:
			if not bool(fall.landed) and director.has_method("play_prop_hit"):
				fall.landed = true
				var pivot: Vector3 = fall.pivot
				director.play_prop_hit(pivot + g._post_direction(fall, g.FALL_REST) * minf(float(fall.length), 2.5), str(g.spec(item).sound), 3.0)
			fall.bounces = int(fall.bounces) + 1
			fall.omega = -omega * 0.18
			g._apply_fall_angle(fall, g.FALL_REST)
			return true
		return g._land(fall, director, g.FALL_REST, 0.0)
	fall.omega = omega
	g._apply_fall_angle(fall, next)
	return true

static func _land(g: GDScript, fall: Dictionary, director: Node, angle: float, _omega: float) -> bool:
	g._apply_fall_angle(fall, angle)
	if not bool(fall.landed) and director.has_method("play_prop_hit"):
		var pivot: Vector3 = fall.pivot
		director.play_prop_hit(pivot + g._post_direction(fall, angle) * minf(float(fall.length), 2.5), str(g.spec(fall.item).sound), 3.0)
	fall.landed = true
	return false

static func _apply_fall_angle(g: GDScript, fall: Dictionary, angle: float) -> void:
	fall.angle = angle
	var base: Transform3D = fall.base
	g._set_transform(fall.item, Transform3D(Basis(fall.axis_local, angle) * base.basis, base.origin))

static func _post_direction(fall: Dictionary, angle: float) -> Vector3:
	return Basis(fall.axis_world, angle) * Vector3.UP

## Raio da ponta até a base na camada dos carros. A ponta fica fora do carro quase sempre, então o
## raio entra pela lataria (o lado de dentro de um colisor não conta). O carro que derrubou só vale
## depois que a base saiu de baixo dele.
static func _post_blocked(g: GDScript, fall: Dictionary, space: PhysicsDirectSpaceState3D, angle: float) -> bool:
	var pivot: Vector3 = fall.pivot
	var direction: Vector3 = g._post_direction(fall, angle)
	var query := PhysicsRayQueryParameters3D.create(pivot + direction * float(fall.length), pivot + direction * 0.35, g.FALL_VEHICLE_MASK)
	query.collide_with_areas = false
	var exclude: Array[RID] = []
	var hitter: Node3D = fall.hitter.get_ref() if fall.hitter != null else null
	if is_instance_valid(hitter) and hitter is CollisionObject3D:
		# No choque o para-choque ainda está antes da base; logo depois o carro passa por cima dela.
		if g._covers_base(fall, space, hitter): exclude.append((hitter as CollisionObject3D).get_rid())
		elif float(fall.age) > g.HITTER_OVER_BASE_SECONDS: fall.hitter = null
	query.exclude = exclude
	return not space.intersect_ray(query).is_empty()

## A base do poste ainda está sob a planta do carro que o derrubou (ponto a meio metro do chão).
static func _covers_base(g: GDScript, fall: Dictionary, space: PhysicsDirectSpaceState3D, vehicle: Node3D) -> bool:
	var point := PhysicsPointQueryParameters3D.new()
	point.position = (fall.pivot as Vector3) + Vector3.UP * 0.5
	point.collision_mask = g.FALL_VEHICLE_MASK
	point.collide_with_areas = false
	for found in space.intersect_point(point, 4):
		if found.get("collider") == vehicle: return true
	return false

static func _free_angle(g: GDScript, fall: Dictionary, space: PhysicsDirectSpaceState3D, free: float, blocked: float) -> float:
	for _iteration in 5:
		var middle := (free + blocked) * 0.5
		if g._post_blocked(fall, space, middle): blocked = middle
		else: free = middle
	return free
