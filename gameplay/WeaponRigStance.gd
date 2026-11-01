extends RefCounted
## Tronco e postura da arma do WeaponRigPose: giro do tronco, ombros, pose-base de carregar/mirar,
## bolso da coronha e alcance do apoio. Separado em 01/11 (Onda 3 de
## docs/plano-divisao-arquivos-grandes-20261101.md) só para o update do rig caber na leitura; a
## ordem das contas é a mesma do corpo antigo. Tudo estático e sem estado: o rig é RefCounted, e um
## auxiliar com `var g` guardado faria ciclo de referência. As etapas recebem o rig em `g`
## (RefCounted, não o script do dono, para não criar preload cíclico), copiam para locais tipadas o
## que leem dele (campos `_f_*` do quadro em curso, action_age, _stance_yaw...) e devolvem por
## `g.` no fim: roda por quadro e por personagem armado, então nenhuma alocação nova aqui.

const DATA = preload("res://gameplay/WeaponPoseData.gd")
const MOVES = preload("res://gameplay/MeleeMoveset.gd")

## Etapa 2 do update: giro do tronco (postura de ombro, golpe, guarda de punhos, faca) e os dois
## ombros já girados. Lê o que `_advance` deixou em `_f_*` e devolve ombros, golpe de punho e
## `shouldered` pelo mesmo caminho.
static func torso(g: RefCounted, id: String, delta: float) -> void:
	var engaged: bool = g._f_engaged
	var in_move: bool = g._f_in_move
	var melee_pose: Dictionary = g._f_melee_pose
	var body_offset: Vector3 = g._f_body_offset
	var action_age: float = g.action_age
	var _stance_yaw: float = g._stance_yaw
	# Postura de ombro: fuzil apoiado gira o tronco para a coronha encostar no
	# ombro de tiro e o braço de apoio alcançar o guarda-mão.
	var shouldered := DATA.STOCK_ENDS.has(id) or id == "rpg"
	var stance := -0.60 if (shouldered or id == "flamethrower") and engaged else 0.0
	# Fuzil na mira: tronco de lado (~43°), como atirador de verdade. A −0,60 a mão de
	# apoio não alcançava o guarda-mão com a coronha no ombro (pedia 0,46–0,50 m para
	# um braço de ~0,47 m) e o solver puxava a arma para dentro do peito.
	if id in DATA.LONG_GUNS and engaged: stance = DATA.STOCK_STANCE
	# Prontidão baixa com o mesmo giro da mira: a −0,30 o guarda-mão (cano para baixo e
	# para dentro) ficava fora do alcance do braço esquerdo e a mão deslizava até o
	# carregador, encostada na direita. Mesmo giro também evita girar o tronco ao mirar.
	if id in DATA.LONG_GUNS and not engaged: stance = DATA.STOCK_STANCE
	# Lança-foguetes sempre no ombro: de frente o braço esquerdo não alcança o tubo.
	if id == "rpg": stance = -0.60
	if not melee_pose.is_empty(): stance = float(melee_pose.torso)
	var punch: Dictionary = {}
	if id in ["fists", "knuckles"]:
		var rest: Dictionary = g._punch_rest()
		if in_move:
			punch = MOVES.sample(id, g._move, action_age, g._melee_from if not g._melee_from.is_empty() else rest, rest)
			g._remember(id, punch)
			stance = float(punch.torso)
		else:
			g._remember(id, rest)
			stance = -0.12 * g._guard_weight
	if id == "knife":
		var attack_weight := smoothstep(0.0, 0.12, action_age) * (1.0 - smoothstep(0.16, 0.38, action_age))
		stance = -0.12 + attack_weight * 0.30
	# No golpe a curva já é suave; filtrar o tronco atrasava o giro em relação ao braço.
	if in_move: _stance_yaw = stance
	else: _stance_yaw = lerpf(_stance_yaw, stance, 1.0 - exp(-12.0 * delta))
	var right_shoulder := _shoulder("Right", _stance_yaw) + body_offset
	var left_shoulder := _shoulder("Left", _stance_yaw) + body_offset
	g._stance_yaw = _stance_yaw
	g._f_shouldered = shouldered
	g._f_punch = punch
	g._f_right_shoulder = right_shoulder
	g._f_left_shoulder = left_shoulder

## Etapa 3 do update: pose-base da arma (carregar, mira, prontidão baixa, saque, recuo), base da
## arma e alvo da mão de apoio antes da pegada específica de cada arma.
static func weapon_carry(g: RefCounted, id: String, delta: float, sprinting: bool) -> void:
	var p: Array = g._f_profile
	var engaged: bool = g._f_engaged
	var run: float = g._f_run
	var arm_swing: float = g._f_arm_swing
	var body_offset: Vector3 = g._f_body_offset
	var shouldered: bool = g._f_shouldered
	var right_shoulder: Vector3 = g._f_right_shoulder
	var equip_blend: float = g.equip_blend
	var recoil: float = g.recoil
	var action_age: float = g.action_age
	var _carry_yaw: float = g._carry_yaw
	var _carry_pitch: float = g._carry_pitch
	var hand: Vector3 = p[0]
	var support: Vector3 = DATA.SUPPORT_GRIPS.get(id, Vector3.ZERO) - DATA.GRIPS.get(id, Vector3.ZERO) if DATA.SUPPORT_GRIPS.has(id) else Vector3.ZERO
	if id == "axe": support = DATA.SUPPORT_GRIPS.axe - DATA.GRIPS.axe
	# Pistola/magnum no coldre pendem de uma mão; a outra só sobe para firmar
	# a empunhadura quando o jogador mira ou atira.
	if id in DATA.HANDGUNS and not engaged: support = Vector3.ZERO
	var pitch := 0.0
	if not engaged:
		hand.y -= 0.12 if not sprinting else 0.20
		hand.z += 0.07
		if id == "hunting_rifle": hand.z -= 0.10
		pitch -= 0.30 if not sprinting else 0.65
	var long_gun := id in DATA.LONG_GUNS or id in ["rpg", "flamethrower"]
	var carry_yaw := 0.0
	if long_gun:
		if not engaged:
			hand = Vector3(0.19 if id == "flamethrower" else 0.16, 0.97, -0.20)
			pitch = 0.45 if sprinting else 0.25
			carry_yaw = 0.65
			if id == "rpg":
				# Lança-foguetes descansando no ombro como na mira (antes atravessado na
				# diagonal, com a traseira passando pelo braço direito). Cano para cima,
				# a traseira afundava no ombro.
				carry_yaw = 0.0
				pitch = -0.04
			if id in DATA.LONG_GUNS:
				# Prontidão baixa: coronha no ombro e cano para baixo e para dentro
				# (o giro é em torno da coronha; ver `_stock_pocket`).
				# Correndo: cano mais baixo e menos atravessado (medido: a 0,55/−0,70 o corpo
				# da arma encostava 4–5 cm no peito e o carregador no quadril).
				carry_yaw = lerpf(0.55, 0.20, run)
				pitch = -0.85 if sprinting else -0.55
		else:
			hand = Vector3(0.23, 1.02, 0.015)
			if DATA.STOCK_ENDS.has(id):
				hand = right_shoulder - (DATA.STOCK_ENDS[id] - DATA.GRIPS[id]) + Vector3(0.065, 0.090, -0.075)
				if id in DATA.LONG_GUNS: hand.y -= 0.14
			if id == "flamethrower": hand = Vector3(0.14, 1.00, -0.24)
			if id == "rpg": hand = right_shoulder + Vector3(0.065, 0.050, -0.18)
		if id == "rpg" and not engaged: hand.x += 0.04
		if not (engaged and shouldered): hand.y += body_offset.y
	if id in DATA.HANDGUNS and engaged:
		hand = Vector3(0.035, 1.09, -0.32)
	elif id in DATA.HANDGUNS:
		# Carregar baixo com uma mão também na corrida: erguer o cano no sprint
		# fazia a pistola parecer um adereço solto abaixo da luva.
		pitch = lerpf(-0.75, -0.88, run)
		carry_yaw = lerpf(0.0, 0.08, run)
	if id == "flamethrower" and not engaged:
		hand = Vector3(0.14, 0.99, -0.28)
		pitch = 0.18 if sprinting else -0.08
		carry_yaw = 0.30
	_carry_yaw = lerpf(_carry_yaw, carry_yaw, 1.0 - exp(-14.0 * delta))
	hand.y -= (1.0 - equip_blend) * 0.16
	pitch -= (1.0 - equip_blend) * 0.45
	_carry_pitch = lerpf(_carry_pitch, pitch, 1.0 - exp(-14.0 * delta))
	pitch = _carry_pitch + recoil
	hand.z += recoil * 0.22
	var gun_basis := Basis(Vector3.UP, _carry_yaw) * Basis(Vector3.RIGHT, pitch)
	var offhand_basis := gun_basis
	var left_target := Vector3(-0.215, 0.655 if not sprinting else 0.82, -0.055 + arm_swing * (0.30 if sprinting else 0.25))
	var pump := 0.0
	if id == "shotgun" and action_age > 0.10 and action_age < 0.48:
		# O movimento da telha acompanha o disparo, não fica em loop ao andar.
		pump = sin((action_age - 0.10) / 0.38 * PI) * 0.08
	if support != Vector3.ZERO:
		left_target = hand + gun_basis * (support + Vector3(0, 0, pump))
	g._carry_yaw = _carry_yaw
	g._carry_pitch = _carry_pitch
	g._f_hand = hand
	g._f_support = support
	g._f_long_gun = long_gun
	g._f_gun_basis = gun_basis
	g._f_offhand_basis = offhand_basis
	g._f_left_target = left_target
	g._f_pump = pump

## Ombro (origem do osso Arm) no espaço V1 do Actor, depois da protração da
## clavícula e do giro de postura que `Actor._apply_combat_weapon_pose` aplica.
static func _shoulder(side: String, yaw: float) -> Vector3:
	var clavicle: Vector3 = DATA.SK_CLAVICLE[side]
	var arm: Vector3 = clavicle + Basis(Vector3.UP, 0.20 if side == "Right" else -0.20) * (DATA.SK_ARM[side] - clavicle)
	arm = DATA.SK_SPINE + Basis(Vector3.UP, yaw) * (arm - DATA.SK_SPINE)
	return Vector3(-arm.x, arm.y, -arm.z) * DATA.SKELETON_SCALE / DATA.V1_TO_V2

## Bolso do ombro direito (onde a coronha encosta), no espaço V1 do Actor: à frente
## da articulação na direção do peito girado, um pouco para dentro e para baixo.
## Com a arma inclinada (cano baixo, arma girada na recarga) o bico da coronha gira
## para trás, para dentro do peito: o bolso avança na proporção da inclinação.
static func _stock_pocket(yaw: float, gun_basis: Basis = Basis.IDENTITY, id := "", low_ready := 0.0) -> Vector3:
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var tilt := sqrt(maxf(0.0, 1.0 - pow(clampf((gun_basis * Vector3.UP).normalized().y, -1.0, 1.0), 2.0)))
	var shift: Vector3 = (DATA.STOCK_POCKET_SHIFT.get(id, Vector3.ZERO) as Vector3).lerp(DATA.STOCK_POCKET_SHIFT_READY.get(id, Vector3.ZERO), low_ready)
	var pocket: Vector3 = DATA.STOCK_POCKET + shift
	return _shoulder("Right", yaw) + forward * (pocket.z + DATA.STOCK_TOE * tilt) + right * pocket.x + Vector3(0, pocket.y, 0)

## Ponto de apoio da mão esquerda (espaço do modelo, relativo à empunhadura) que o
## braço esquerdo alcança: desliza do guarda-mão em direção ao receptor até caber.
static func _reachable_support(id: String, hand: Vector3, basis: Basis, left_shoulder: Vector3) -> Vector3:
	var support: Vector3 = DATA.SUPPORT_GRIPS[id] - DATA.GRIPS[id]
	var back := support
	back.z = maxf(support.z, float(DATA.SUPPORT_MIN_REACH_Z_BY_ID.get(id, DATA.SUPPORT_MIN_REACH_Z)))
	if left_shoulder.distance_to(hand + basis * support) <= DATA.LEFT_PALM_REACH: return support
	var low := 0.0
	var high := 1.0
	for i in 10:
		var mid := (low + high) * 0.5
		if left_shoulder.distance_to(hand + basis * support.lerp(back, mid)) > DATA.LEFT_PALM_REACH: low = mid
		else: high = mid
	return support.lerp(back, high)
