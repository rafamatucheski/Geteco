extends RefCounted
## Pegada por arma do WeaponRigPose: punhos (soco e soqueira), faca, granada, taco/machado, quais
## braços saem da locomoção, punho fechado e rotação do pulso. Separado em 01/11 (Onda 3 de
## docs/plano-divisao-arquivos-grandes-20261101.md) só para o update do rig caber na leitura; a
## ordem das contas é a mesma do corpo antigo. Estático e sem estado (o rig é RefCounted: guardar
## `var g` faria ciclo de referência); a etapa recebe o rig em `g` (RefCounted, para não criar
## preload cíclico), copia o que lê para locais tipadas e devolve pelos campos `_f_*` do quadro.
## Roda por quadro e por personagem armado: nenhuma alocação nova aqui.

const DATA = preload("res://gameplay/WeaponPoseData.gd")

## Etapa 4 do update: pegada específica de cada arma por cima da pose-base de `weapon_carry`.
static func hand_grips(g: RefCounted, id: String, sprinting: bool, rig: Dictionary) -> void:
	var run: float = g._f_run
	var arm_swing: float = g._f_arm_swing
	var body_offset: Vector3 = g._f_body_offset
	var in_move: bool = g._f_in_move
	var engaged: bool = g._f_engaged
	var melee_pose: Dictionary = g._f_melee_pose
	var melee_support_active: bool = g._f_melee_support_active
	var punch: Dictionary = g._f_punch
	var hand: Vector3 = g._f_hand
	var support: Vector3 = g._f_support
	var gun_basis: Basis = g._f_gun_basis
	var offhand_basis: Basis = g._f_offhand_basis
	var left_target: Vector3 = g._f_left_target
	var action_age: float = g.action_age
	var melee_support_weight: float = g.melee_support_weight
	# Quais braços saem da locomoção. O que não é resolvido aqui continua com o
	# braço do clipe importado (Walking/Running), como o braço livre na V1.
	var right_solve := id != "fists"
	var left_solve := support != Vector3.ZERO
	var right_fist := false
	var left_fist := false
	var right_free := 0.0
	var left_free := 0.0
	var visible := id != "fists"
	# Rotação do punho com pulso reto (Actor); nula = mão segue a base pedida.
	var wrist_right: Variant = null
	var wrist_left: Variant = null
	if id == "fists":
		# Guarda estável e golpes da sequência de `MeleeMoveset`; o polo do
		# cotovelo só muda onde a chave pede (gancho, uppercut).
		if g._guard_weight > 0.0:
			# O punho volta firme à guarda, sem herdar a inclinação de arma baixa.
			right_solve = true
			left_solve = true
			var pose: Dictionary = punch if in_move else g._punch_rest()
			hand = pose.r + body_offset
			left_target = pose.l + body_offset
			gun_basis = g._basis(pose.rb)
			offhand_basis = g._basis(pose.lb)
			wrist_right = float(pose.rr)
			wrist_left = float(pose.lr)
			right_fist = true
			left_fist = true
	elif id == "knuckles":
		if in_move or engaged:
			var pose: Dictionary = punch if in_move else g._punch_rest()
			hand = pose.r + body_offset
			left_target = pose.l + body_offset
			gun_basis = g._basis(pose.rb)
			offhand_basis = g._basis(pose.lb)
			wrist_right = float(pose.rr)
			wrist_left = float(pose.lr)
		else:
			var pose := _knuckle_pose(g.knuckle_variant, 10.0, false, arm_swing, run)
			hand = pose.right
			left_target = pose.left
			gun_basis = pose.right_basis
			offhand_basis = pose.left_basis
		left_solve = true
		right_fist = true
		left_fist = true
	elif id == "knife":
		if engaged:
			hand = Vector3(0.21, 1.0, -0.20)
			left_target = Vector3(-0.16, 1.02, -0.24)
			left_solve = true
			left_fist = true
		else:
			# A faca carregada pende ao lado da coxa, com pouco vaivém do passo.
			hand = Vector3(0.21, 0.66 if sprinting else 0.68, -0.11 - arm_swing * 0.12)
		if action_age < 0.32:
			var thrust := sin(action_age / 0.32 * PI)
			var variant := maxi(g.knife_variant, 0)
			hand += [Vector3(-0.035, 0.015, -0.23), Vector3(-0.12, 0.09, -0.16), Vector3(-0.055, -0.07, -0.20)][variant] * thrust
			gun_basis = Basis(Vector3.UP, thrust * (0.45 if variant == 1 else 0.08)) * Basis(Vector3.FORWARD, thrust * (0.25 if variant == 2 else 0.05)) * gun_basis
	elif id == "grenade":
		var ready := Vector3(0.24, 0.72, -0.10 - arm_swing * 0.07) + body_offset
		# Prepara pelo lado direito, acelera à altura do ombro e termina
		# à frente do corpo. A mão fica afastada do rosto durante o arco.
		var cocked := Vector3(0.36, 1.16, 0.08) + body_offset
		var released := Vector3(0.30, 1.19, -0.38) + body_offset
		var follow := Vector3(0.23, 0.89, -0.43) + body_offset
		hand = ready
		if action_age < 0.08: hand = ready.lerp(cocked, smoothstep(0.0, 0.08, action_age))
		elif action_age < DATA.GRENADE_RELEASE: hand = cocked.lerp(released, smoothstep(0.08, DATA.GRENADE_RELEASE, action_age))
		elif action_age < 0.38: hand = released.lerp(follow, smoothstep(DATA.GRENADE_RELEASE, 0.38, action_age))
		elif action_age < DATA.GRENADE_RECOVERY: hand = follow.lerp(ready, smoothstep(0.38, DATA.GRENADE_RECOVERY, action_age))
		gun_basis = Basis(Vector3.RIGHT, -0.20)
		visible = action_age < DATA.GRENADE_RELEASE or (action_age >= DATA.GRENADE_RECOVERY and bool(rig.get("loaded", true)))
		right_free = smoothstep(0.45, DATA.GRENADE_RECOVERY, action_age)
	if id in ["axe", "bat"]:
		hand = melee_pose.hand
		gun_basis = melee_pose.basis
		left_target = hand + gun_basis * support
		left_solve = melee_support_weight > 0.0
		if not melee_support_active: support = Vector3.ZERO
	g._f_right_solve = right_solve
	g._f_left_solve = left_solve
	g._f_right_fist = right_fist
	g._f_left_fist = left_fist
	g._f_right_free = right_free
	g._f_left_free = left_free
	g._f_visible = visible
	g._f_wrist_right = wrist_right
	g._f_wrist_left = wrist_left
	g._f_hand = hand
	g._f_left_target = left_target
	g._f_gun_basis = gun_basis
	g._f_offhand_basis = offhand_basis
	g._f_support = support

## V1 `MeshyKnucklePose.sample`: um punho golpeia enquanto o outro guarda.
## Quatro variações: direto de esquerda, direto de direita, gancho e subida.
static func _knuckle_pose(variant: int, age: float, engaged: bool, swing: float, sprint: float) -> Dictionary:
	var right := Vector3(0.14, 1.03, -0.25)
	var left := Vector3(-0.14, 1.06, -0.25)
	var right_basis := Basis.IDENTITY
	var left_basis := Basis.IDENTITY
	if not engaged and age >= DATA.KNUCKLE_DURATION:
		# Corrida de punhos fechados: cotovelo dobrado ao lado do corpo e bombeio
		# para frente e para trás, com o punho inclinando no mesmo sentido. Antes as
		# duas mãos ficavam paradas à frente do quadril (±12 cm) e o Dante corria de
		# braços duros (feedback de 25/09/2026).
		# A mão sobe à frente e desce até o quadril atrás, como numa corrida real; antes
		# ela ia para trás na altura do peito e o cotovelo subia aberto ("asa").
		var height := lerpf(0.74, 0.80, sprint)
		var pump := lerpf(0.26, 0.36, sprint)
		var right_swing := -swing
		var left_swing := swing
		right = Vector3(0.18, height + maxf(0.0, right_swing) * 0.22, -0.06 - right_swing * pump * (1.0 if right_swing > 0.0 else 0.45))
		left = Vector3(-0.18, height + maxf(0.0, left_swing) * 0.22, -0.06 - left_swing * pump * (1.0 if left_swing > 0.0 else 0.45))
		right_basis = Basis(Vector3.RIGHT, swing * 0.55)
		left_basis = Basis(Vector3.RIGHT, -swing * 0.55)
	elif age < DATA.KNUCKLE_DURATION:
		var reach := smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.14, DATA.KNUCKLE_DURATION, age))
		var turn := reach * PI * 0.45
		match posmod(variant, 4):
			0:
				left = left.lerp(Vector3(-0.04, 1.08, -0.41), reach)
				left_basis = Basis(Vector3.BACK, -turn)
			1:
				right = right.lerp(Vector3(0.035, 1.06, -0.41), reach)
				right_basis = Basis(Vector3.BACK, turn)
			2:
				# O gancho abre para fora antes de cruzar à frente do peito.
				var opening := sin(clampf(age / 0.15, 0, 1) * PI) * 0.10 if age < 0.15 else 0.0
				left = left.lerp(Vector3(0.03, 1.055, -0.35), reach)
				left.x -= opening
				left_basis = Basis(Vector3.UP, -0.55 * reach) * Basis(Vector3.BACK, -turn)
			3:
				# Arco curto de baixo para cima, com o punho à frente da jaqueta.
				var load_offset := sin(clampf(age / 0.12, 0, 1) * PI) * 0.09 if age < 0.12 else 0.0
				right = right.lerp(Vector3(0.045, 1.16, -0.34), reach)
				right.y -= load_offset
				right_basis = Basis(Vector3.RIGHT, -0.45 * reach) * Basis(Vector3.BACK, 0.35 * reach)
	return {"right": right, "left": left, "right_basis": right_basis, "left_basis": left_basis}
