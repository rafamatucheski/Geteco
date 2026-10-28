extends RefCounted
## Ragdoll do atropelamento: 11 corpos rígidos (pelve, tronco, cabeça, coxas, canelas, braços, antebraços)
## ligados por Generic6DOFJoint3D, que dirigem as MESMAS juntas do `CivilianModel`. Por isso vale igual para o
## corpo procedural do kit e para o corpo do Meshy (o `MeshyBodyRig` copia as juntas para o esqueleto), e o
## levantar animado pode partir da pose final nessas juntas.
##
## Antes (até 19/10) o voo girava o corpo inteiro como uma tábua e, ao levantar, só desfazia o giro. O corpo
## rígido só existe enquanto voa e rola: ao assentar, a pose fica nas juntas e os corpos são liberados.
## GETECO_RAGDOLL=0 volta ao voo antigo.
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Camada própria (bit 10): o carro não colide com o corpo no move_and_slide (máscara 7), mas o corpo rígido
## colide com o carro (camada 4) e com o mundo (camada 1). Assim outro carro ainda empurra o corpo caído.
const LAYER := 1 << 9
const MASK := 1 | 4
## Teto de ragdolls simultâneos; além disso o atropelamento usa o voo antigo (um corpo varrido).
const MAX_ACTIVE := 4
const SETTLE_SPEED := 0.3
const SETTLE_SECONDS := 0.45
const MAX_SECONDS := 5.0
const GRAVITY_SCALE := 1.8
static var enabled := OS.get_environment("GETECO_RAGDOLL") != "0"
static var active := 0
static var _material: PhysicsMaterial

## Limites angulares (radianos) no referencial do osso filho: X lateral (dobra), Y ao longo do osso (torção),
## Z para a frente (abertura), como rotação do filho em relação ao pai. O Godot mede o ângulo com o sinal
## oposto (sonda de 19/10: limite [0; 1,2] bloqueava o lado positivo), então _link inverte os intervalos.
## Joelho e cotovelo só dobram para um lado; o sentido é conferido em
## tests/test_body_ragdoll.gd (pé atrás do joelho, mão à frente do cotovelo).
const LIMITS := {
	"spine": [Vector2(-.5, .7), Vector2(-.45, .45), Vector2(-.4, .4)],
	"neck": [Vector2(-.7, .8), Vector2(-.9, .9), Vector2(-.5, .5)],
	"hip": [Vector2(-1.9, .5), Vector2(-.5, .5), Vector2(-.7, .7)],
	"knee": [Vector2(0.0, 2.4), Vector2(-.08, .08), Vector2(-.08, .08)],
	"shoulder": [Vector2(-2.6, 1.2), Vector2(-.9, .9), Vector2(-1.6, 1.6)],
	"elbow": [Vector2(-2.4, 0.0), Vector2(-.15, .15), Vector2(-.08, .08)],
}

var root: Node3D
var model: Node3D
var parts: Array[Dictionary] = []
var age := 0.0
var settled := false
var _still := 0.0
var _counted := false
var _mesh: MeshInstance3D
var _cull_margin := 0.0
var _initial: Array[Transform3D] = []
var _final: Array[Transform3D] = []
var _last_audio := -1.0


static func find_model(visual: Node) -> Node3D:
	if visual == null: return null
	if visual is Node3D and "thighs" in visual and "forearms" in visual and "pelvis" in visual: return visual
	for child in visual.get_children():
		var found := find_model(child)
		if found != null: return found
	return null

static func available(visual: Node) -> bool:
	if not enabled or active >= MAX_ACTIVE: return false
	var found := find_model(visual)
	return found != null and is_instance_valid(found.pelvis) and is_instance_valid(found.spine) \
		and is_instance_valid(found.head_node) and found.thighs.size() == 2 and found.forearms.size() == 2

## `owner` recebe os corpos (um nó que some junto com o voo). `impact` é a velocidade do carro no plano.
## `shove`: empurrão/arremesso de alguém (roubo de carro, moto), não para-choque: ver `_launch`.
func build(owner: Node, visual: Node, impact: Vector3, source: Node, shove := false) -> bool:
	var began := STALL_WORK.begin()
	model = find_model(visual)
	if model == null: return false
	root = Node3D.new()
	root.name = "Ragdoll"
	root.top_level = true
	owner.add_child(root)
	if _material == null:
		_material = PhysicsMaterial.new()
		_material.friction = .85
		_material.bounce = .05
	var s: float = model.global_basis.get_scale().x
	var pelvis: Node3D = model.pelvis
	var spine: Node3D = model.spine
	var head: Node3D = model.head_node
	var hips: Vector3 = (model.thighs[0].global_position + model.thighs[1].global_position) * .5
	var neck: Vector3 = head.global_position
	var up: Vector3 = (spine.global_position - hips).normalized() if spine.global_position.distance_squared_to(hips) > .0001 else Vector3.UP
	# Pelve e tronco são caixas: deitam chapados em vez de rolar como cápsulas.
	var pelvis_part := _add(pelvis, hips - up * .06 * s, spine.global_position, -1, _box(Vector3(.32, 0, .2) * s), 12.0, "")
	var chest := _add(spine, spine.global_position, neck, pelvis_part, _box(Vector3(.36, 0, .21) * s), 18.0, "spine")
	var head_shape := SphereShape3D.new()
	head_shape.radius = .11 * s
	var head_up: Vector3 = head.global_basis.y.normalized()
	_add(head, neck, neck + head_up * .24 * s, chest, head_shape, 5.0, "neck")
	for i in 2:
		var thigh: Node3D = model.thighs[i]
		var shin: Node3D = model.shins[i]
		var foot: Node3D = model.feet[i]
		var upper: Node3D = model.upper_arms[i]
		var fore: Node3D = model.forearms[i]
		var thigh_part := _add(thigh, thigh.global_position, shin.global_position, pelvis_part, _capsule(.075 * s), 8.0, "hip")
		var ankle: Vector3 = foot.global_position
		_add(shin, shin.global_position, ankle + (ankle - shin.global_position).normalized() * .06 * s, thigh_part, _capsule(.06 * s), 4.5, "knee")
		var upper_part := _add(upper, upper.global_position, fore.global_position, chest, _capsule(.05 * s), 2.5, "shoulder")
		var fore_length: float = (model.arm_lengths[i].y if model.arm_lengths.size() == 2 else model.forearm_len) * s + .08 * s
		_add(fore, fore.global_position, fore.global_position - fore.global_basis.y.normalized() * fore_length, upper_part, _capsule(.045 * s), 1.6, "elbow")
	for part in parts: _initial.append((part.joint as Node3D).transform)
	if shove: _launch_shove(impact)
	else: _launch(impact, source)
	if "mesh_node" in model and model.mesh_node is MeshInstance3D:
		# O voo afasta o corpo da origem do ator, que só acompanha ao assentar.
		_mesh = model.mesh_node
		_cull_margin = _mesh.extra_cull_margin
		_mesh.extra_cull_margin = maxf(_cull_margin, 14.0)
	active += 1
	_counted = true
	STALL_WORK.finish("street.ragdoll.build", began)
	return true

func _capsule(radius: float) -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	return shape

func _box(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape

## Um corpo por segmento, com Y apontando do fim para o começo (como o osso pendurado do CivilianModel).
func _add(joint: Node3D, from: Vector3, to: Vector3, parent: int, shape: Shape3D, mass: float, limits: String) -> int:
	var axis := from - to
	var length := axis.length()
	var y := axis / length if length > .0001 else joint.global_basis.y.normalized()
	# Eixo lateral do MODELO, não da junta: o antebraço do CivilianModel nasce com X invertido (frente = +Y no
	# _bone_basis), e o cotovelo dobrava para trás com o mesmo limite do joelho.
	var x: Vector3 = model.global_basis.x.normalized()
	x = (x - y * x.dot(y))
	if x.length_squared() < .0001: x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var frame := Basis(x, y, x.cross(y))
	var body := RigidBody3D.new()
	body.name = joint.name
	body.mass = mass
	body.gravity_scale = GRAVITY_SCALE
	body.linear_damp = .05
	# Mole: com 1,6 o corpo tombava inteiro como tábua a 9 m/s (captura de 19/10).
	body.angular_damp = .7
	body.physics_material_override = _material
	body.collision_layer = LAYER
	body.collision_mask = MASK
	body.continuous_cd = true
	if shape is CapsuleShape3D:
		(shape as CapsuleShape3D).height = maxf(length, (shape as CapsuleShape3D).radius * 2.0 + .01)
	elif shape is BoxShape3D:
		(shape as BoxShape3D).size.y = maxf(length, .06)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)
	body.global_transform = Transform3D(frame, (from + to) * .5)
	var offset: Transform3D = body.global_transform.affine_inverse() * joint.global_transform
	# Sinal da dobra permitida (Y do osso inclinado para +Z do pai no joelho, para -Z no cotovelo).
	var hinge_sign := 1.0 if limits == "knee" else (-1.0 if limits == "elbow" else 0.0)
	parts.append({"joint": joint, "body": body, "offset": offset, "parent": parent, "hinge": hinge_sign})
	if parent >= 0: _link(parts[parent].body, body, from, frame, limits)
	return parts.size() - 1

func _link(a: RigidBody3D, b: RigidBody3D, at: Vector3, frame: Basis, limits: String) -> void:
	if limits == "knee" or limits == "elbow":
		# Dobradiça: o Generic6DOF do GodotPhysics cedia ~25° no joelho mesmo a 10 m/s. Eixo Z da dobradiça =
		# lateral do modelo, o mesmo X do limite em LIMITS.
		var hinge := HingeJoint3D.new()
		root.add_child(hinge)
		hinge.global_transform = Transform3D(Basis(frame.y.cross(frame.x), frame.y, frame.x), at)
		var bend: Vector2 = LIMITS[limits][0]
		hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -bend.y)
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, -bend.x)
		# Correção mais rápida do limite (padrão 0,3): a 24 m/s o joelho do Meshy cedia ~44° no impacto.
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_BIAS, .6)
		hinge.node_a = hinge.get_path_to(a)
		hinge.node_b = hinge.get_path_to(b)
		return
	var link := Generic6DOFJoint3D.new()
	root.add_child(link)
	link.global_transform = Transform3D(frame, at)
	var axes: Array = LIMITS[limits]
	for i in 3:
		var range_axis: Vector2 = axes[i]
		var key: String = ["x", "y", "z"][i]
		link.set("angular_limit_%s/lower_angle" % key, -range_axis.y)
		link.set("angular_limit_%s/upper_angle" % key, -range_axis.x)
		link.set("angular_limit_%s/damping" % key, 1.0)
		link.set("angular_limit_%s/erp" % key, .8)
	link.node_a = link.get_path_to(a)
	link.node_b = link.get_path_to(b)

## Pernas varridas pelo para-choque e cabeça para trás: o corpo gira por cima do capô. O giro é de corpo
## rígido (v = v_pelve + ω × r em cada parte); velocidades soltas por parte puxavam as juntas e, a 24 m/s,
## hiperestendiam o joelho (teste de 19/10).
func _launch(impact: Vector3, _source: Node) -> void:
	var flat := Vector3(impact.x, 0, impact.z)
	var speed := minf(flat.length(), 37.5)
	var heading := flat.normalized() if speed > .01 else Vector3.BACK
	var carry := heading * minf(speed * .75, 18.0) + Vector3.UP * clampf(speed * .55, 1.2, 9.0)
	var spin := heading.cross(Vector3.UP) * clampf(speed * .3, 0.0, 8.0) + Vector3.UP * randf_range(-1.2, 1.2)
	var center: Vector3 = (parts[0].body as Node3D).global_position
	for part in parts:
		var body: RigidBody3D = part.body
		part.last = body.global_position
		# Dobra moderada sobre o giro de corpo rígido: pernas varridas pelo para-choque, tronco e cabeça atrasados.
		var joint_name := String((part.joint as Node).name)
		var sweep := .3 if joint_name.contains("leg") else (-.12 if part == parts[1] or part == parts[2] else 0.0)
		body.linear_velocity = carry + spin.cross(body.global_position - center) + heading * speed * sweep
		body.angular_velocity = spin

## Arremesso pela gola (roubo): o tronco vai na frente e as pernas ficam para trás, então a pessoa
## tropeça e cai de frente ou de lado, em vez de girar por cima de um capô. Velocidade baixa e quase
## sem subida: é um puxão de braço, não uma batida (vídeos de roubo de carro: a vítima dá 1–2 passos
## tropeçando e cai a ~1,5–2,5 m da porta).
func _launch_shove(impact: Vector3) -> void:
	var flat := Vector3(impact.x, 0, impact.z)
	var speed := minf(flat.length(), 6.0)
	var heading := flat.normalized() if speed > .01 else Vector3.BACK
	var carry := heading * speed + Vector3.UP * .5
	# UP × rumo: a cabeça anda no rumo mais rápido que os pés (queda para a frente); um pouco de giro
	# em torno do eixo vertical deixa cada queda diferente (de lado, de frente, meio de costas).
	var spin := Vector3.UP.cross(heading) * speed * .55 + Vector3.UP * randf_range(-1.6, 1.6)
	var center: Vector3 = (parts[0].body as Node3D).global_position
	for part in parts:
		var body: RigidBody3D = part.body
		part.last = body.global_position
		var joint_name := String((part.joint as Node).name)
		var trail := -.35 if joint_name.contains("lower_leg") or joint_name.contains("Foot") else (-.18 if joint_name.contains("leg") else 0.0)
		body.linear_velocity = carry + spin.cross(body.global_position - center) + heading * speed * trail
		body.angular_velocity = spin

func set_frozen(frozen: bool) -> void:
	for part in parts:
		if is_instance_valid(part.body): (part.body as RigidBody3D).freeze = frozen

## Passo físico: devolve true quando o corpo parou (ou passou do tempo máximo).
func step(delta: float, audio: Callable) -> bool:
	if settled: return true
	age += delta
	var fastest := 0.0
	for part in parts:
		var body: RigidBody3D = part.body
		if not is_instance_valid(body): continue
		fastest = maxf(fastest, body.linear_velocity.length())
	_still = _still + delta if fastest < SETTLE_SPEED and age > .5 else 0.0
	if fastest > 3.0: _sweep()
	for part in parts:
		if is_instance_valid(part.body): part.last = (part.body as Node3D).global_position
	_ground_audio(audio)
	return _still >= SETTLE_SECONDS or age >= MAX_SECONDS

## CCD manual: o continuous_cd do GodotPhysics deixou o corpo atravessar uma parede de 15 cm a 30 m/s
## (teste de 19/10). Um raio por parte entre o passo anterior e o atual; se algum centro cruzou um sólido,
## o ragdoll INTEIRO volta pela mesma correção (mover uma parte só esticaria as juntas) e perde a
## velocidade contra a superfície.
func _sweep() -> void:
	var space := (parts[0].body as Node3D).get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var correction := Vector3.ZERO
	var normal := Vector3.ZERO
	for part in parts:
		var body: RigidBody3D = part.body
		if not is_instance_valid(body): continue
		var now := body.global_position
		var before: Vector3 = part.last
		if before.distance_squared_to(now) < .0064: continue
		var probe := PhysicsRayQueryParameters3D.create(before, now, MASK, exclude)
		var hit := space.intersect_ray(probe)
		if hit.is_empty(): continue
		var back: Vector3 = hit.position + hit.normal * .1 - now
		if back.length_squared() > correction.length_squared():
			correction = back
			normal = hit.normal
	if correction == Vector3.ZERO: return
	for part in parts:
		var body: RigidBody3D = part.body
		if not is_instance_valid(body): continue
		body.global_position += correction
		var into := body.linear_velocity.dot(normal)
		if into < 0.0: body.linear_velocity -= normal * into * 1.2

## Pancada no chão pela queda do tronco: uma por vez, sem contato monitorado por corpo.
func _ground_audio(audio: Callable) -> void:
	if not audio.is_valid() or age - _last_audio < .3 or parts.size() < 2: return
	for index in 2:
		var body: RigidBody3D = parts[index].body
		if not is_instance_valid(body): continue
		var falling := -body.linear_velocity.y
		if falling < 2.0: continue
		var space := body.get_world_3d().direct_space_state
		var probe := PhysicsRayQueryParameters3D.create(body.global_position, body.global_position + Vector3.DOWN * .32, 1)
		if space.intersect_ray(probe).is_empty(): continue
		_last_audio = age
		audio.call(body.global_position, falling)
		return

## Escreve as juntas a partir dos corpos (interpolados no quadro de vídeo). Pais antes dos filhos.
func present(interpolated := true) -> void:
	for part in parts:
		var body: RigidBody3D = part.body
		var joint: Node3D = part.joint
		if not is_instance_valid(body) or not is_instance_valid(joint): continue
		var pose: Transform3D = body.get_global_transform_interpolated() if interpolated else body.global_transform
		joint.global_transform = pose * (part.offset as Transform3D)
		if part.hinge != 0.0: _clamp_hinge(joint, part.hinge)

## Trava visual do joelho/cotovelo: o que o solver ainda deixar passar do limite não aparece na pose.
static func _clamp_hinge(joint: Node3D, hinge_sign: float) -> void:
	var local := joint.transform
	var rotation := local.basis.get_rotation_quaternion()
	var bone := rotation * Vector3.UP
	if bone.z * hinge_sign >= 0.0: return
	var allowed := Vector3(bone.x, bone.y, 0.0)
	if allowed.length_squared() < .0001: allowed = Vector3.UP
	var corrected := Quaternion(bone, allowed.normalized()) * rotation
	joint.transform = Transform3D(Basis(corrected) * Basis.from_scale(local.basis.get_scale()), local.origin)

## Corpo parado: a origem do ator vai para o chão sob a pelve, a pose fica nas juntas e os corpos somem.
func settle(actor: Node3D) -> void:
	if settled: return
	settled = true
	var pelvis: RigidBody3D = parts[0].body
	var point := pelvis.global_position
	var lowest := point.y
	for part in parts:
		if is_instance_valid(part.body): lowest = minf(lowest, (part.body as Node3D).global_position.y)
	var ground := lowest - .08
	var probe := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .4, point + Vector3.DOWN * 2.5, 1)
	var hit := pelvis.get_world_3d().direct_space_state.intersect_ray(probe)
	if not hit.is_empty(): ground = hit.position.y
	actor.global_position = Vector3(point.x, ground + .04, point.z)
	if "last_position" in actor: actor.set("last_position", actor.global_position)
	actor.reset_physics_interpolation()
	present(false)
	_final.clear()
	for part in parts: _final.append((part.joint as Node3D).transform)
	dispose()

## Levantar provisório (até o clipe do Mixamo): das juntas deitadas de volta à pose de pé capturada.
func blend_to_initial(weight: float) -> void:
	if _final.size() != parts.size(): return
	for index in parts.size():
		var joint: Node3D = parts[index].joint
		if not is_instance_valid(joint): continue
		var from: Transform3D = _final[index]
		var to: Transform3D = _initial[index]
		var rotation := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), weight)
		joint.transform = Transform3D(Basis(rotation) * Basis.from_scale(to.basis.get_scale()), from.origin.lerp(to.origin, weight))

func restore_initial() -> void:
	for index in mini(parts.size(), _initial.size()):
		var joint: Node3D = parts[index].joint
		if is_instance_valid(joint): joint.transform = _initial[index]

func dispose() -> void:
	if _counted:
		_counted = false
		active = maxi(0, active - 1)
	if is_instance_valid(_mesh): _mesh.extra_cull_margin = _cull_margin
	for part in parts: part.body = null
	if is_instance_valid(root):
		root.queue_free()
		root = null
