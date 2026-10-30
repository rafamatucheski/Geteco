extends Node3D
## Corte de membros no golpe letal forte de katana ou machado (pedido do jogador, 29/10: "bate com a
## espada ou machado e não corta os pedaços da pessoa").
##
## Por que foi refeito: a versão de 07/10 só valia para a katana e só para o corpo procedural do kit.
## No corpo Meshy (a maioria dos pedestres da cidade) as juntas `right_upper_arm` etc. são nós SEM
## malha que só guiam o esqueleto: o corte duplicava um nó vazio e escondia outro nó vazio, e nada
## mudava na tela. O machado nem chamava o corte.
##
## Como fica:
## - No golpe letal e em corpos recentes, só com katana/machado e golpe forte (`is_strong_cut`).
##   Protegidos (Maciota, mecânico) e o jogador nunca. Cada membro só pode sair uma vez.
## - O membro é o mais próximo do ponto do golpe (`cut_point`, altura e lado de cada golpe do combo):
##   cabeça, braço ou perna.
## - Corpo procedural: as malhas da junta (e filhas) são copiadas para o pedaço e a junta some do corpo.
## - Corpo Meshy (malha com skin): o osso do corte vai a escala ~0 no cadáver (o membro colapsa no
##   ponto do corte) e o pedaço é a MESMA malha com um esqueleto próprio em que só a cadeia do membro
##   tem pose; os outros ossos colapsam no mesmo ponto do corte, então os vértices de peso misto fecham
##   o coto em vez de esticar até o quadril.
## - Pedaços são RigidBody3D de um pool fixo (MAX_PARTS), montado uma vez no `_ready` e estacionado
##   desligado (fora do espaço de física). Passando do limite, o mais antigo volta ao pool.
## - Nenhum material novo por pedaço: as malhas e materiais são os do próprio corpo (já compilados); o
##   disco do corte usa um único material estático, pré-aquecido em `CombatEffectsPrewarm`. Sem
##   `transparency` no sumiço (trocaria para a variante com alfa e compilaria shader no jogo): o pedaço
##   afunda no chão e é estacionado.
## - Sangue só pelas APIs do `CombatEffects` (`blood`, `stain`).
## GETECO_MELEE_DISMEMBER=0 desliga o corte (A/B no mesmo export).
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const MAX_PARTS := 6
const MAX_RECENT_BODIES := 24
const RECENT_BODY_MS := 30000
## Malhas por pedaço procedural: braço = braço+antebraço (a mão vem no antebraço); perna = coxa+canela+pé.
const MAX_MESHES := 6
const LIFE := 10.0
const SINK_SECONDS := 1.2
const BLEED_SECONDS := 2.4
## Espada e escudo do gelo entra junto (pedido de 30/10: "o desmembramento tem que acontecer com espada também").
const SEVER_WEAPONS := ["katana", "axe", "sword_shield"]
## Golpe cheio da katana (45) e do machado (52) passa; dano reduzido (variante fraca, golpe de raspão)
## não. O golpe pesado que fecha o combo e o RAGE passam sempre.
const STRONG_DAMAGE := 40.0
## Escala dos ossos colapsados. Zero exato deixa base não inversível (BoneAttachment3D do chapéu).
const COLLAPSED := 0.001
## Parâmetros de instância que dão cor ao corpo: kit procedural (`CivilianModel._apply_colors`) e Meshy
## (`MeshyBodyRig._apply_material`). Copiados para o pedaço manter a roupa/pele do dono.
const INSTANCE_KEYS := ["skin_color", "hair_color", "top_color", "inner_color", "bottom_color", "shoe_color",
	"accent_color", "hue_shift", "brightness", "tone"]
## Junta do corpo → tipo, junta da ponta (meio do membro para escolher o mais próximo) e osso Mixamo.
## O lado −X do kit (`left_`) é o "Right" do Mixamo (`MeshyBodyRig.side_names`).
const LIMBS := {
	"Head": {"kind": "head", "end": "", "bone": "Head"},
	"left_upper_arm": {"kind": "arm", "end": "LeftForearm", "bone": "RightArm"},
	"right_upper_arm": {"kind": "arm", "end": "RightForearm", "bone": "LeftArm"},
	"left_upper_leg": {"kind": "leg", "end": "left_lower_leg", "bone": "RightUpLeg"},
	"right_upper_leg": {"kind": "leg", "end": "right_lower_leg", "bone": "LeftUpLeg"},
	# Corte ao meio (30/10: "cortar no meio o boneco"): a junta do peito leva cabeça e braços junto; no
	# Meshy o osso Spine1 colapsa e o pedaço é a metade de cima. O centro de escolha fica na cintura.
	"Spine": {"kind": "torso", "end": "", "bone": "Spine1"},
}
## Altura (m acima dos pés da vítima) e deslocamento para a direita do jogador de cada golpe do combo.
## Katana: `KATANA_ATTACKS` (de cima para baixo, potente na horizontal, baixo nas pernas).
## Machado: `MeleeMoveset.moves("axe")` (diagonal do ombro, horizontal, pesado de cima na cabeça).
const CUT_PROFILES := {
	"katana": [Vector2(1.58, 0.06), Vector2(1.25, -0.20), Vector2(0.55, 0.12)],
	"axe": [Vector2(1.38, 0.22), Vector2(1.22, -0.22), Vector2(1.62, 0.0)],
	# Espada e escudo (`SHIELD_ATTACKS`): de cima na cabeça, cruzado na cintura, pesado no ombro.
	"sword_shield": [Vector2(1.62, 0.04), Vector2(1.02, -0.18), Vector2(1.38, 0.24)],
}
## Membros da versão de 07/10 por golpe do combo (`sever_defeated`, mantido para quem já usa).
const LEGACY_LIMBS := ["right_upper_arm", "left_upper_leg", "left_upper_arm"]
const BONE_PREFIXES := ["mixamorig_", "mixamorig:"]

static var enabled := OS.get_environment("GETECO_MELEE_DISMEMBER") != "0"
static var _cap_material: StandardMaterial3D
static var _cap_meshes: Dictionary = {}
static var _shapes: Dictionary = {}

var effects: Node3D
signal part_landed(point: Vector3)
var _slots: Array[Dictionary] = []
## Sem colliders novos nos mortos e sem varrer todos os NPCs a cada frame.
var _recent_bodies: Array[Dictionary] = []
## Ordem de uso dos slots ativos (o primeiro é o mais antigo, reciclado quando o pool enche).
var _order: Array[int] = []

func _ready() -> void:
	_ensure_resources()
	for index in MAX_PARTS: _slots.append(_build_slot(index))
	set_physics_process(false)

static func _ensure_resources() -> void:
	if _cap_material == null:
		_cap_material = StandardMaterial3D.new()
		_cap_material.albedo_color = Color("671421")
		_cap_material.roughness = 0.7
	if _cap_meshes.is_empty():
		for kind in ["arm", "leg", "head", "torso"]:
			var radius: float = {"arm": 0.054, "leg": 0.074, "head": 0.06, "torso": 0.15}[kind]
			var shape := CylinderMesh.new()
			shape.top_radius = radius
			shape.bottom_radius = radius
			shape.height = 0.012
			shape.radial_segments = 8
			shape.rings = 1
			_cap_meshes[kind] = shape
	if _shapes.is_empty():
		var arm := CapsuleShape3D.new(); arm.radius = 0.06; arm.height = 0.62
		var leg := CapsuleShape3D.new(); leg.radius = 0.08; leg.height = 0.86
		var head := SphereShape3D.new(); head.radius = 0.11
		var torso := CapsuleShape3D.new(); torso.radius = 0.17; torso.height = 0.8
		_shapes = {"arm": arm, "leg": leg, "head": head, "torso": torso}

## Disco do corte com o material do jogo, para o pré-aquecimento desenhar antes da cortina sair.
static func prewarm_cap() -> MeshInstance3D:
	_ensure_resources()
	var cap := MeshInstance3D.new()
	cap.name = "CutSurfacePrewarm"
	cap.mesh = _cap_meshes.arm
	cap.material_override = _cap_material
	cap.scale = Vector3.ONE * 4.0
	return cap

func _build_slot(index: int) -> Dictionary:
	var body := RigidBody3D.new()
	body.name = "SeveredPart%d" % index
	body.mass = 3.0
	body.angular_damp = 1.2
	body.linear_damp = 0.1
	# Não empurra nem é empurrado por gente e carros; só cai no mundo (camada 1, a mesma do raio antigo).
	body.collision_layer = 0
	body.collision_mask = 1
	body.continuous_cd = false
	body.contact_monitor = true
	body.max_contacts_reported = 1
	body.body_entered.connect(_on_part_contact.bind(index))
	var shape := CollisionShape3D.new()
	shape.shape = _shapes.arm
	body.add_child(shape)
	var meshes: Array[MeshInstance3D] = []
	for i in MAX_MESHES:
		var part := MeshInstance3D.new()
		part.name = "Piece%d" % i
		part.visible = false
		body.add_child(part)
		meshes.append(part)
	var skeleton := Skeleton3D.new()
	skeleton.name = "SkinSkeleton"
	skeleton.visible = false
	body.add_child(skeleton)
	var skin_mesh := MeshInstance3D.new()
	skin_mesh.name = "SkinPiece"
	skeleton.add_child(skin_mesh)
	var cap := MeshInstance3D.new()
	cap.name = "CutSurface"
	cap.material_override = _cap_material
	body.add_child(cap)
	var stump := MeshInstance3D.new()
	stump.name = "StumpSurface"
	stump.material_override = _cap_material
	stump.top_level = true
	stump.visible = false
	add_child(body)
	add_child(stump)
	var slot := {"body": body, "shape": shape, "meshes": meshes, "skeleton": skeleton, "skin_mesh": skin_mesh,
		"cap": cap, "stump": stump, "active": false, "age": 0.0, "sunk": false, "bleed_next": 0.0,
		"actor": null, "joint": null, "source_skeleton": null, "bone": -1, "direction": Vector3.ZERO,
		"landed": false}
	_park(slot)
	return slot

## Estaciona: fora do espaço de física (PROCESS_MODE_DISABLED remove o corpo), invisível e sem malha.
func _park(slot: Dictionary) -> void:
	var body := slot.body as RigidBody3D
	body.process_mode = Node.PROCESS_MODE_DISABLED
	body.freeze = true
	body.visible = false
	for part: MeshInstance3D in slot.meshes:
		part.visible = false
		part.mesh = null
	var skin_mesh := slot.skin_mesh as MeshInstance3D
	skin_mesh.mesh = null
	skin_mesh.skin = null
	(slot.skeleton as Skeleton3D).visible = false
	(slot.stump as MeshInstance3D).visible = false
	slot.active = false
	slot.actor = null
	slot.joint = null
	slot.source_skeleton = null

## Golpe forte de lâmina pesada: katana/machado, com dano cheio, golpe pesado do combo ou RAGE.
static func is_strong_cut(weapon_id: String, damage: float, heavy: bool) -> bool:
	if not weapon_id in SEVER_WEAPONS: return false
	return heavy or damage >= STRONG_DAMAGE

## Ponto do golpe no corpo da vítima: altura do golpe do combo e lado do arco, na frente do jogador.
static func cut_point(actor: Node3D, weapon_id: String, combo: int, direction: Vector3) -> Vector3:
	var profiles: Array = CUT_PROFILES.get(weapon_id, [Vector2(1.25, 0.0)])
	var profile: Vector2 = profiles[posmod(combo, profiles.size())]
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	var right := flat.cross(Vector3.UP)
	return actor.global_position + Vector3.UP * profile.x + right * profile.y

## Chamado por `Gameplay._melee` logo depois do dano. Devolve true se cortou.
func try_sever(actor: Node3D, weapon_id: String, damage: float, heavy: bool, impact: Vector3, direction: Vector3) -> bool:
	register_defeated(actor)
	if not enabled or not is_strong_cut(weapon_id, damage, heavy): return false
	if not _eligible(actor): return false
	var joint := _nearest_joint(actor, impact)
	if joint == null: return false
	return _sever_joint(actor, joint, direction)

## API de 07/10 (testes da katana): membro fixo por golpe do combo.
func sever_defeated(actor: Node3D, direction: Vector3, combo: int) -> bool:
	if not enabled or not _eligible(actor): return false
	var joint := _visible_joint(actor, LEGACY_LIMBS[posmod(combo, LEGACY_LIMBS.size())])
	if joint == null: return false
	return _sever_joint(actor, joint, direction)

func _eligible(actor: Node3D) -> bool:
	if not is_instance_valid(actor) or PROTECTION.is_protected(actor) or actor.get("is_player") == true: return false
	if actor.get("dead") != true or not actor.has_method("receive_damage"): return false
	return _removed_limbs(actor).size() < LIMBS.size()

func can_sever(actor: Node3D) -> bool:
	return enabled and _eligible(actor)

static func _removed_limbs(actor: Node3D) -> Array:
	return actor.get_meta("melee_removed_limbs", []) as Array

## Chamado após uma morte de combate; não aplica dano nem reemite morte/recompensa/crime.
func register_defeated(actor: Node3D) -> void:
	if not _eligible(actor): return
	var now := Time.get_ticks_msec()
	for entry in _recent_bodies:
		if entry.actor.get_ref() == actor: return # Bater no corpo não renova sua vida.
	if _recent_bodies.size() >= MAX_RECENT_BODIES: _recent_bodies.pop_front()
	_recent_bodies.append({"actor": weakref(actor), "expires": now + RECENT_BODY_MS})

func candidates_near(origin: Vector3, reach: float) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not enabled: return result
	var now := Time.get_ticks_msec()
	for i in range(_recent_bodies.size() - 1, -1, -1):
		var entry := _recent_bodies[i]
		var actor: Node3D = entry.actor.get_ref() as Node3D
		if not is_instance_valid(actor) or int(entry.expires) < now or not actor.is_inside_tree():
			_recent_bodies.remove_at(i)
			continue
		if not _eligible(actor): continue
		# A posição da raiz fica nos pés depois da queda. A junta visível é a referência real.
		var point := closest_cut_point(actor, origin)
		if point.is_finite() and point.distance_squared_to(origin) <= reach * reach:
			result.append(actor)
	return result

func closest_cut_point(actor: Node3D, impact: Vector3) -> Vector3:
	if not _eligible(actor): return Vector3.INF
	var joint := _nearest_joint(actor, impact)
	return _joint_center(joint) if joint != null else Vector3.INF

func _visible_joint(actor: Node3D, joint_name: String) -> Node3D:
	if joint_name in _removed_limbs(actor): return null
	# Alguns policiais mantêm um corpo antigo escondido ao lado do rig civil atual.
	for candidate in actor.find_children(joint_name, "MeshInstance3D", true, false):
		if (candidate as Node3D).is_visible_in_tree(): return candidate
	return null

## Junta cujo centro (meio do membro, centro da cabeça) fica mais perto do ponto do golpe.
func _nearest_joint(actor: Node3D, impact: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for joint_name: String in LIMBS:
		var joint := _visible_joint(actor, joint_name)
		if joint == null: continue
		var center := _joint_center(joint)
		var distance := center.distance_squared_to(impact)
		if distance < best_distance:
			best_distance = distance
			best = joint
	return best

static func _joint_center(joint: Node3D) -> Vector3:
	var info: Dictionary = LIMBS.get(String(joint.name), {})
	if info.get("kind", "") == "head": return joint.global_position + joint.global_basis.y.normalized() * 0.12
	if info.get("kind", "") == "torso": return joint.global_position
	var tip := joint.get_node_or_null(NodePath(String(info.get("end", "")))) as Node3D
	if tip == null: return joint.global_position - joint.global_basis.y.normalized() * 0.3
	return (joint.global_position + tip.global_position) * 0.5

## Modelo do corpo (CivilianModel) dono da junta: o primeiro ancestral com a propriedade `skeleton`.
static func _body_model(joint: Node3D, actor: Node3D) -> Node:
	var node: Node = joint.get_parent()
	while node != null and node != actor:
		if "skeleton" in node and "mesh_node" in node: return node
		node = node.get_parent()
	return null

func _sever_joint(actor: Node3D, joint: Node3D, direction: Vector3) -> bool:
	var began := STALL_WORK.begin()
	var done := _stall_sever(actor, joint, direction)
	STALL_WORK.finish_slow("combat.melee_dismember", began, 2000, self)
	return done

func _stall_sever(actor: Node3D, joint: Node3D, direction: Vector3) -> bool:
	if not _eligible(actor) or String(joint.name) in _removed_limbs(actor): return false
	var info: Dictionary = LIMBS.get(String(joint.name), {"kind": "arm", "end": "", "bone": ""})
	var kind: String = info.kind
	var model := _body_model(joint, actor)
	var skeleton: Skeleton3D = model.get("skeleton") if model != null else null
	var skin_source: MeshInstance3D = model.get("mesh_node") if model != null else null
	var joint_mesh := joint as MeshInstance3D
	var skinned := (joint_mesh == null or joint_mesh.mesh == null) and is_instance_valid(skeleton) and is_instance_valid(skin_source) and skin_source.mesh != null
	var bone := -1
	if skinned:
		bone = _find_bone(skeleton, String(info.bone))
		if bone < 0: return false
	elif _visible_meshes(joint).is_empty():
		return false # Rig especial sem malha nem esqueleto conhecido: fica a morte autorada.
	actor.set_meta("katana_severed", true)
	var removed := _removed_limbs(actor).duplicate()
	removed.append(String(joint.name))
	actor.set_meta("melee_removed_limbs", removed)
	var slot := _take_slot()
	var body := slot.body as RigidBody3D
	var cut_origin := joint.global_position
	if skinned: cut_origin = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	var body_transform := Transform3D(joint.global_basis.orthonormalized(), cut_origin)
	body.global_transform = body_transform
	body.reset_physics_interpolation()
	var shape := slot.shape as CollisionShape3D
	shape.shape = _shapes[kind]
	# A metade de cima do corpo fica acima do corte (+Y da junta); os membros pendem abaixo dele.
	if kind == "head": shape.position = Vector3(0, 0.13, 0)
	elif kind == "torso": shape.position = Vector3(0, 0.32, 0)
	else: shape.position = Vector3(0, -float((_shapes[kind] as CapsuleShape3D).height) * 0.45, 0)
	var cap := slot.cap as MeshInstance3D
	cap.mesh = _cap_meshes[kind]
	cap.transform = Transform3D.IDENTITY
	if skinned: _fill_skinned(slot, skeleton, skin_source, bone, cut_origin, body_transform)
	else: _fill_procedural(slot, joint, body_transform)
	# O corpo perde o membro: a junta some (procedural; no Meshy ela não tem malha e só guia o osso).
	joint.hide()
	if skinned: skeleton.set_bone_pose_scale(bone, Vector3.ONE * COLLAPSED)
	var stump := slot.stump as MeshInstance3D
	stump.mesh = _cap_meshes[kind]
	stump.global_transform = body_transform
	stump.visible = true
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	body.visible = true
	body.freeze = false
	body.process_mode = Node.PROCESS_MODE_INHERIT
	var lift := 1.4 if kind == "head" else 2.1
	body.linear_velocity = flat * 2.4 + Vector3.UP * lift
	body.angular_velocity = flat.cross(Vector3.UP) * -6.0 + Vector3.UP * 1.5
	slot.active = true
	slot.age = 0.0
	slot.sunk = false
	slot.landed = false
	slot.bleed_next = 0.4
	slot.actor = weakref(actor)
	slot.joint = weakref(joint)
	slot.source_skeleton = weakref(skeleton) if skinned else null
	slot.bone = bone
	slot.direction = flat
	if is_instance_valid(effects):
		effects.blood(cut_origin, flat, 75.0)
		effects.stain(actor.global_position, 0.7)
	set_physics_process(true)
	return true

## Um único contato de queda por peça; o consumidor usa o pool de áudio existente.
func _on_part_contact(_other: Node, index: int) -> void:
	if index < 0 or index >= _slots.size(): return
	var slot := _slots[index]
	if not slot.active or slot.landed or slot.sunk: return
	slot.landed = true
	part_landed.emit((slot.body as RigidBody3D).global_position)

static func _find_bone(skeleton: Skeleton3D, short_name: String) -> int:
	for prefix: String in BONE_PREFIXES:
		var index := skeleton.find_bone(prefix + short_name)
		if index >= 0: return index
	return skeleton.find_bone(short_name)

static func _visible_meshes(joint: Node3D) -> Array[MeshInstance3D]:
	var list: Array[MeshInstance3D] = []
	var candidates: Array = [joint]
	candidates.append_array(joint.find_children("*", "MeshInstance3D", true, false))
	for node in candidates:
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null or not mesh_node.visible: continue
		list.append(mesh_node)
		if list.size() >= MAX_MESHES: break
	return list

func _fill_procedural(slot: Dictionary, joint: Node3D, body_transform: Transform3D) -> void:
	var inverse := body_transform.affine_inverse()
	var sources := _visible_meshes(joint)
	var meshes: Array[MeshInstance3D] = slot.meshes
	for i in meshes.size():
		var part := meshes[i]
		if i >= sources.size():
			part.visible = false
			part.mesh = null
			continue
		var source := sources[i]
		part.mesh = source.mesh
		part.material_override = source.material_override
		part.cast_shadow = source.cast_shadow
		for surface in source.get_surface_override_material_count():
			part.set_surface_override_material(surface, source.get_surface_override_material(surface))
		_copy_instance_parameters(source, part)
		part.transform = inverse * source.global_transform
		part.visible = true

func _fill_skinned(slot: Dictionary, source_skeleton: Skeleton3D, source_mesh: MeshInstance3D, cut_bone: int, cut_origin: Vector3, body_transform: Transform3D) -> void:
	var skeleton := slot.skeleton as Skeleton3D
	var skin_mesh := slot.skin_mesh as MeshInstance3D
	skin_mesh.mesh = null
	skin_mesh.skin = null
	var count := source_skeleton.get_bone_count()
	# Esqueleto do pedaço: todos os ossos na raiz, com a pose global do cadáver. Sem hierarquia, colapsar o
	# resto do corpo não arrasta o membro junto.
	if skeleton.get_bone_count() != count:
		skeleton.clear_bones()
		for i in count: skeleton.add_bone(source_skeleton.get_bone_name(i))
	else:
		for i in count: skeleton.set_bone_name(i, source_skeleton.get_bone_name(i))
	skeleton.global_transform = source_skeleton.global_transform
	var local_origin := source_skeleton.global_transform.affine_inverse() * cut_origin
	var collapsed_rotation := Quaternion.IDENTITY
	for i in count:
		if _descends_from(source_skeleton, i, cut_bone):
			var pose := source_skeleton.get_bone_global_pose(i)
			skeleton.set_bone_pose_position(i, pose.origin)
			skeleton.set_bone_pose_rotation(i, pose.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_scale(i, pose.basis.get_scale())
		else:
			skeleton.set_bone_pose_position(i, local_origin)
			skeleton.set_bone_pose_rotation(i, collapsed_rotation)
			skeleton.set_bone_pose_scale(i, Vector3.ONE * COLLAPSED)
	skin_mesh.transform = source_skeleton.global_transform.affine_inverse() * source_mesh.global_transform
	skin_mesh.skeleton = NodePath("..")
	skin_mesh.mesh = source_mesh.mesh
	skin_mesh.skin = source_mesh.skin
	skin_mesh.cast_shadow = source_mesh.cast_shadow
	skin_mesh.material_override = source_mesh.material_override
	for surface in source_mesh.get_surface_override_material_count():
		skin_mesh.set_surface_override_material(surface, source_mesh.get_surface_override_material(surface))
	for shape in source_mesh.get_blend_shape_count():
		skin_mesh.set_blend_shape_value(shape, source_mesh.get_blend_shape_value(shape))
	_copy_instance_parameters(source_mesh, skin_mesh)
	skeleton.visible = true
	var cap := slot.cap as MeshInstance3D
	cap.transform = Transform3D(Basis.IDENTITY, body_transform.affine_inverse() * cut_origin)

static func _descends_from(skeleton: Skeleton3D, bone: int, ancestor: int) -> bool:
	var current := bone
	while current >= 0:
		if current == ancestor: return true
		current = skeleton.get_bone_parent(current)
	return false

static func _copy_instance_parameters(source: GeometryInstance3D, target: GeometryInstance3D) -> void:
	for key: String in INSTANCE_KEYS:
		var value: Variant = source.get_instance_shader_parameter(key)
		if value != null: target.set_instance_shader_parameter(key, value)

## Slot livre, ou o mais antigo fora da tela antes de reciclar uma peça ainda visível.
func _take_slot() -> Dictionary:
	for index in _slots.size():
		if not _slots[index].active:
			_order.append(index)
			return _slots[index]
	var recycle := 0
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera):
		var viewport_rect := get_viewport().get_visible_rect().grow(64.0)
		for order_index in _order.size():
			var body := _slots[_order[order_index]].body as RigidBody3D
			if camera.is_position_behind(body.global_position) or not viewport_rect.has_point(camera.unproject_position(body.global_position)):
				recycle = order_index
				break
	var oldest: int = _order[recycle]
	_order.remove_at(recycle)
	_park(_slots[oldest])
	_order.append(oldest)
	return _slots[oldest]

func _physics_process(delta: float) -> void:
	var any := false
	for index in _slots.size():
		var slot := _slots[index]
		if not slot.active: continue
		slot.age = float(slot.age) + delta
		var body := slot.body as RigidBody3D
		if float(slot.age) >= LIFE:
			_park(slot)
			_order.erase(index)
			continue
		any = true
		if float(slot.age) >= LIFE - SINK_SECONDS:
			# Some afundando no chão: sem `transparency`, que trocaria a variante do shader do corpo.
			if not slot.sunk:
				slot.sunk = true
				body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				body.freeze = true
			body.global_position += Vector3.DOWN * (0.3 / SINK_SECONDS) * delta
		_follow_stump(slot)
		if float(slot.age) <= BLEED_SECONDS and float(slot.age) >= float(slot.bleed_next) and is_instance_valid(effects):
			slot.bleed_next = float(slot.bleed_next) + 0.4
			var stump := slot.stump as MeshInstance3D
			if stump.visible: effects.blood(stump.global_position, slot.direction, 18.0 * (1.0 - float(slot.age) / BLEED_SECONDS))
	if not any: set_physics_process(false)

## Disco do coto acompanha o cadáver caindo (osso do corte no Meshy, junta no procedural).
func _follow_stump(slot: Dictionary) -> void:
	var stump := slot.stump as MeshInstance3D
	var actor: Object = slot.actor.get_ref() if slot.actor != null else null
	var joint: Node3D = slot.joint.get_ref() if slot.joint != null else null
	if not is_instance_valid(actor) or not is_instance_valid(joint) or not (actor as Node3D).is_inside_tree():
		stump.visible = false
		return
	var origin := joint.global_position
	var skeleton: Skeleton3D = slot.source_skeleton.get_ref() if slot.source_skeleton != null else null
	if is_instance_valid(skeleton) and int(slot.bone) >= 0:
		origin = skeleton.global_transform * skeleton.get_bone_global_pose(int(slot.bone)).origin
	stump.global_transform = Transform3D(joint.global_basis.orthonormalized(), origin)

func clear() -> void:
	for slot in _slots:
		if slot.active: _park(slot)
	_order.clear()
	_recent_bodies.clear()
	set_physics_process(false)

func part_count() -> int:
	var count := 0
	for slot in _slots:
		if slot.active: count += 1
	return count

## Nós do pool (fixo): o teste confere que cortar não cria nós novos.
func pool_size() -> int:
	return _slots.size()
