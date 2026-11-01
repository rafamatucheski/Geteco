extends RefCounted
## Pose do Actor sentado: moto com guidão (`pose_vehicle`), motorista de carro/caminhão/ônibus
## (`pose_seated_base`, `pose_seated_limbs`, inclinação e olhar) e a volta ao mundo de pé
## (`release_seated`). Separado em 01/11 (Onda 3 de docs/plano-divisao-arquivos-grandes-20261101.md)
## só para o Actor.gd caber na leitura. Não tem estado próprio: `seated`, a pose parada e os pés de
## repouso continuam no Actor (lidos por VehicleInterior, BlitzSet, JessicaRuntime e testes), que mantém
## cada função antiga como delegação de uma linha com a mesma assinatura.
## `g` fica como CharacterBody3D, e não como o script do Actor, para não criar preload cíclico. O IK
## (perna, braço, pegada) e a pose capturada continuam sendo chamados por `g.`: subclasses e testes os
## chamam no Actor e o despacho fica o mesmo. Nenhuma subclasse sobrescreve estas funções (conferido
## em 01/11), então pose_vehicle chama _fit_motorcycle_reach direto.

var g: CharacterBody3D

func _init(host: CharacterBody3D) -> void:
	g = host
	sync_refs()

## Cópias tipadas de referências do Actor, lidas a cada osso sem passar pelo `g.` dinâmico. O dono as
## atualiza por `_sync_pose_refs` em todo `visual =`/`skeleton =`/`_combat_bones =`... (inclusive os de
## testes e de quem troca o visual de fora); mudar o conteúdo do dicionário/array não precisa de aviso.
var visual: Node3D
var skeleton: Skeleton3D
var _combat_bones: Dictionary = {}
var _combat_rests: Array[Transform3D] = []
var _combat_skin: MeshInstance3D

func sync_refs() -> void:
	visual = g.visual
	skeleton = g.skeleton
	_combat_bones = g._combat_bones
	_combat_rests = g._combat_rests
	_combat_skin = g._combat_skin

func pose_vehicle(sitting: float, stepping: float = 0.0, side: int = -1, reach: float = 1.0, handlebars: Dictionary = {}) -> void:
	g._apply_pose(g._idle_pose)
	if handlebars.has("Left") and handlebars.has("Right"):
		var center: Vector3 = visual.to_local((handlebars.Left.origin + handlebars.Right.origin) * .5)
		if g.hips >= 0:
			# Inclina a partir da cintura em vez de esticar os ossos do braço até uma barra distante.
			var toward := Vector3(center.x, 0, center.z).normalized()
			var lean_mult = handlebars.get("lean_multiplier", 1.8)
			var lean_min = handlebars.get("lean_min", 0.5)
			var lean := clampf(Vector2(center.x, center.z).length() * lean_mult, lean_min, 1.3)
			var bar_axis: Vector3 = visual.global_basis.orthonormalized().inverse() * (handlebars.Right.basis.y as Vector3)
			var turn := atan2(-bar_axis.z, bar_axis.x)
			var forward_lean := visual.global_basis.orthonormalized() * Basis(Vector3.UP.cross(toward), lean) * Basis(Vector3.UP, turn) * visual.global_basis.orthonormalized().inverse()
			var local_lean := skeleton.global_basis.orthonormalized().inverse() * forward_lean * skeleton.global_basis.orthonormalized()
			g._set_combat_bone_rotation(g.hips, local_lean * skeleton.get_bone_global_pose(g.hips).basis)
			_fit_motorcycle_reach(handlebars)
	for limb in ["Left", "Right"]:
		var sign_side := -1.0 if limb == "Left" else 1.0
		var target: Vector3 = (g._idle_feet[limb] as Vector3).lerp(Vector3(sign_side * 0.15, 0.50, -0.38), sitting)
		if (limb == "Left") == (side < 0): target += Vector3(sign_side * 0.22, 0.48, -0.04) * stepping
		g._solve_leg(limb, visual.to_global(target))
		var hand := Vector3(sign_side * 0.23, lerpf(0.86, 1.05, sitting), -0.28)
		var palm_basis := Basis.IDENTITY
		if handlebars.has(limb):
			var hold: Transform3D = handlebars[limb]
			hand = visual.to_local(hold.origin)
			palm_basis = visual.global_basis.orthonormalized().inverse() * hold.basis
		g._solve_combat_arm(limb, hand, palm_basis, not handlebars.is_empty(), sign_side)
	g._set_combat_grips(not handlebars.is_empty(), not handlebars.is_empty())
	if reach < 1.0: g._apply_blend(g._idle_pose, g._capture_pose(), clampf(reach, 0.0, 1.0))

func _fit_motorcycle_reach(handlebars: Dictionary) -> void:
	var shift := Vector3.ZERO
	for limb in ["Left", "Right"]:
		var hold: Transform3D = handlebars[limb]
		var roll := .358 if limb == "Right" else -.392
		var hand_basis := hold.basis * Basis(Vector3.RIGHT, -PI * .5) * Basis(Vector3.UP, -roll)
		var wrist := hold.origin - hand_basis * Vector3(0, .065, 0) * skeleton.global_basis.get_scale().x
		var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(_combat_bones[limb + "Arm"]).origin)
		var length: float = (_combat_rests[_combat_bones[limb + "ForeArm"]].origin.length() + _combat_rests[_combat_bones[limb + "Hand"]].origin.length() - .045) * skeleton.global_basis.get_scale().x
		var offset := wrist - shoulder
		var correction := offset.normalized() * maxf(0.0, offset.length() - length)
		if correction.length_squared() > shift.length_squared(): shift = correction
	# A mão de fora percorre mais ao esterçar. Desliza no selim
	# até 28 cm em vez de esticar o braço; o IK das pernas mantém os dois alvos dos pés.
	shift = shift.limit_length(.28)
	var parent := skeleton.get_bone_parent(g.hips)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local_shift := parent_basis.inverse() * skeleton.global_basis.inverse() * shift
	skeleton.set_bone_pose_position(g.hips, skeleton.get_bone_pose_position(g.hips) + local_shift)


## Repouso reclinado. `recline` em rad, positivo = encosto para trás. Devolve o centro do
## quadril no espaço do próprio Actor, para o chamador posicionar o corpo no banco.
func pose_seated_base(recline: float) -> Vector3:
	g.seated = true
	if not is_instance_valid(skeleton) or g._idle_pose.is_empty(): return Vector3(0, 0.77, 0)
	g._apply_pose(g._idle_pose)
	if g.hips >= 0 and absf(recline) > 0.001:
		# Gira só o tronco a partir do quadril: o eixo vem do visual (o modelo é girado 180°).
		var visual_basis := visual.global_basis.orthonormalized()
		var skeleton_basis := skeleton.global_basis.orthonormalized()
		var turn := skeleton_basis.inverse() * (visual_basis * Basis(Vector3.RIGHT, recline) * visual_basis.inverse()) * skeleton_basis
		g._set_combat_bone_rotation(g.hips, turn * skeleton.get_bone_global_pose(g.hips).basis)
	var left := skeleton.to_global(skeleton.get_bone_global_pose(_combat_bones["LeftUpLeg"]).origin)
	var right := skeleton.to_global(skeleton.get_bone_global_pose(_combat_bones["RightUpLeg"]).origin)
	return g.to_local((left + right) * 0.5)

## `feet`: pé (tornozelo) por lado, no espaço do Actor (metros, sem a escala do visual).
## `hands`: Transform3D da palma por lado, também no espaço do Actor (mesma convenção da
## empunhadura do guidão da moto: Y ao longo do que se agarra, Z para trás). Lado sem mão
## fica solto.
func pose_seated_limbs(feet: Dictionary, hands: Dictionary) -> void:
	if not is_instance_valid(skeleton) or _combat_bones.is_empty(): return
	# O polo do cotovelo vem do quadro anterior; sem isto a primeira solução ficava presa
	# ao último gesto de combate e o braço não chegava à mão.
	g._elbow_previous.clear()
	g._twist_previous.clear()
	g._grip_fingers.clear()
	g._pose_delta = 1.0
	for limb in ["Left", "Right"]:
		var sign_side := -1.0 if limb == "Left" else 1.0
		if feet.has(limb): g._solve_leg(limb, g.to_global(feet[limb]))
		if hands.has(limb):
			var hold: Transform3D = hands[limb]
			# `_solve_combat_arm` espera o alvo no espaço do visual (que pode estar escalado).
			g._solve_combat_arm(limb, visual.to_local(g.to_global(hold.origin)), hold.basis, true, sign_side)
	# Mão fechada no que segura: o blend shape vai direto, sem o move_toward do quadro.
	if is_instance_valid(_combat_skin) and _combat_skin.get_blend_shape_count() >= 2:
		_combat_skin.set_blend_shape_value(0, 1.0 if hands.has("Right") else 0.18)
		_combat_skin.set_blend_shape_value(1, 1.0 if hands.has("Left") else 0.18)
	g._pose_delta = 1.0 / 60.0

## Moto parada: o pé esquerdo sai da pedaleira e apoia no chão ao lado (`weight` 0–1), como o piloto faz
## ao parar no sinal; `ground_y` é a altura do chão no mundo. Depois de `pose_vehicle` com o guidão.
func pose_motorcycle_foot(weight: float, ground_y: float) -> void:
	if weight <= .01 or not is_instance_valid(skeleton) or not _combat_bones.has("LeftFoot"): return
	var foot: int = _combat_bones["LeftFoot"]
	var current := skeleton.to_global(skeleton.get_bone_global_pose(foot).origin)
	var planted := visual.to_global(Vector3(-.36, 0.0, -.10))
	planted.y = ground_y + .09
	g._solve_leg("Left", current.lerp(planted, smoothstep(0.0, 1.0, weight)))

## Motorista: tronco inclinado de lado (rad; positivo = para a direita do corpo), aplicado entre a base
## reclinada e o IK dos braços, para as mãos continuarem no volante.
func pose_driver_lean(lean: float) -> void:
	if not is_instance_valid(skeleton) or absf(lean) < .0005: return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * visual.global_basis.orthonormalized()
	var axis := (to_skeleton * Vector3.BACK).normalized()
	for entry in [["Spine01", .6], ["Spine02", .4]]:
		var bone: int = _combat_bones.get(entry[0], -1)
		if bone >= 0: g._set_combat_bone_rotation(bone, Basis(axis, -lean * float(entry[1])) * skeleton.get_bone_global_pose(bone).basis)

## Motorista: cabeça girada (rad; positivo = para a esquerda), depois do IK dos braços.
func pose_driver_look(look: float) -> void:
	if not is_instance_valid(skeleton) or absf(look) < .001: return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * visual.global_basis.orthonormalized()
	var axis := (to_skeleton * Vector3.UP).normalized()
	for entry in [["neck", .4], ["Head", .6]]:
		var bone: int = _combat_bones.get(entry[0], -1)
		if bone >= 0: g._set_combat_bone_rotation(bone, Basis(axis, look * float(entry[1])) * skeleton.get_bone_global_pose(bone).basis)

## Volta o corpo ao mundo de pé. Chamado por `teleport`: todo caminho de saída do veículo
## (porta, salto, resgate, morte) passa por lá.
func release_seated(keep_yaw := false) -> void:
	if not g.seated: return
	g.seated = false
	# `keep_yaw`: a animação de saída gira o visual por conta própria; a guinada do veículo
	# passa do corpo (que estava preso à base do carro) para o visual, sem o corpo girar duas vezes.
	var yaw := g.global_rotation.y
	g.global_basis = Basis.IDENTITY
	visual.rotation = Vector3(0, yaw, 0) if keep_yaw else Vector3.ZERO
	visual.scale = Vector3.ONE
	visual.position = Vector3.ZERO
	g.remove_meta("seated_state")
	if is_instance_valid(_combat_skin) and _combat_skin.get_blend_shape_count() >= 2:
		_combat_skin.set_blend_shape_value(0, 0.0)
		_combat_skin.set_blend_shape_value(1, 0.0)
	if g.is_inside_tree(): g.reset_physics_interpolation()
