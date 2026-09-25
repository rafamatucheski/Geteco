extends RefCounted
## Camada exclusivamente visual entre a lógica de combate e o rig real do Dante.
## Produz alvos de palma em espaço local do Actor; Actor.gd resolve os braços
## depois do clipe de locomoção. Nenhum evento desta classe aplica dano.
##
## Port direto do caminho "skinned" da V1 (`characters/PlayerCombatPose.gd`,
## `scripts/player/MeshyMeleePose.gd`, `MeshyKnucklePose.gd`), que era a versão
## aprovada de como o Dante segura e usa cada arma. A V1 e a V2 carregam o MESMO
## GLB (`dante_grip.glb` == `assets/dante.glb`, mesmo MD5), só em escalas
## diferentes: 0,82 na V1 e 1,03 aqui. Por isso todas as coordenadas abaixo estão
## no espaço da V1 e são multiplicadas por V1_TO_V2 no fim. A tentativa anterior
## reajustava só Y, com um fator diferente em cada pose: a pistola ficava abaixo do
## ombro, o machado alto demais e o taco num arco diferente do machado.

const DATA = preload("res://gameplay/WeaponPoseData.gd")
## Escala do Dante V2 / escala do Dante V1 sobre o mesmo GLB (Actor.gd: 1,03;
## V1 MeshyDanteRig.SCALE: 0,82). Também vale para o modelo da arma: na V1 a arma
## não era escalada junto com o corpo, então relativamente ao Dante ela era esse
## tanto maior do que o modelo cru na V2.
const V1_TO_V2 := 1.03 / 0.82
const HANDGUNS := ["pistol", "magnum"]
const LONG_GUNS := ["smg", "shotgun", "ak47", "m4a1", "hunting_rifle"]
const FIREARMS := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower"]
## V1 `_cross_grip`: o cabo atravessa a palma em vez de ficar na vertical.
const CROSS_GRIP := ["axe", "knife", "bat"]
const CROSS_GRIP_LEFT := ["smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle"]
## Ombro de referência do `MeshyMeleePose` (espaço V1) para o balanço do cabo ao andar.
const MELEE_SHOULDER := Vector3(0.23, 1.18, -0.015)
const GRENADE_RELEASE := 0.20
## Instante de contato nas trajetórias abaixo; Gameplay usa o mesmo relógio.
const MELEE_CONTACT := {"fists": 0.14, "knuckles": 0.16, "knife": 0.18, "bat": 0.36, "axe": 0.38}
## Repouso dos ossos no espaço do esqueleto do `dante.glb` (medido no GLB; o
## modelo é girado 180° dentro do Actor). Com eles o ombro sai da mesma conta
## que a V1 fazia em `sync_shoulders`: clavícula protraída 0,20 rad e tronco
## girado pela postura — independentemente da ordem em que o esqueleto é lido.
const SKELETON_SCALE := 1.03
const SK_SPINE := Vector3(0.003647, 1.28616, -0.0122)
const SK_CLAVICLE := {"Right": Vector3(-0.032291, 1.315796, -0.045289), "Left": Vector3(0.037389, 1.319443, -0.045306)}
const SK_ARM := {"Right": Vector3(-0.176041, 1.315796, -0.051777), "Left": Vector3(0.172361, 1.319443, -0.052288)}
const KNUCKLE_DURATION := 0.32

var weapon_id := ""
var action_age := 10.0
var _attacked_id := ""
var recoil := 0.0
var equip_blend := 1.0
var punch_left := false
var knife_variant := -1
var knuckle_variant := -1
var melee_support_weight := 0.0
var _right := Vector3(0.24, 0.68, -0.02)
var _left := Vector3(-0.24, 0.68, -0.02)
var _carry_pitch := 0.0
var _carry_yaw := 0.0
var _stance_yaw := 0.0
var _move_weight := 0.0
var _sprint_weight := 0.0
var _guard_weight := 0.0
var _right_solve_weight := 0.0
var _left_solve_weight := 0.0
var _display_basis := Basis.IDENTITY
var _offhand_basis := Basis.IDENTITY
var _support_weight := 0.0

## Mesmo contador da V1 (`PlayerCombatPose.on_attack`): cada golpe troca o lado do
## soco e a variação de faca/soqueira, então golpes seguidos não repetem a pose.
func attack(id: String, recoil_multiplier: float = 1.0) -> void:
	_attacked_id = id
	var profile: Array = DATA.PROFILES.get(id, DATA.PROFILES.pistol)
	recoil = minf(recoil + float(profile[2]) * recoil_multiplier, float(profile[2]) * 1.6 * recoil_multiplier)
	action_age = 0.0
	if id == "knife": knife_variant = (knife_variant + 1) % 3
	if id == "knuckles": knuckle_variant = (knuckle_variant + 1) % 4
	if id in ["fists", "knuckles"]: punch_left = not punch_left

func reset() -> void:
	weapon_id = ""
	action_age = 10.0
	_attacked_id = ""
	recoil = 0.0
	equip_blend = 1.0
	melee_support_weight = 0.0
	_guard_weight = 0.0
	_right_solve_weight = 0.0
	_left_solve_weight = 0.0
	_support_weight = 0.0

## `rig` (opcional): "body_bob" (subida do quadril no passo, em metros do Actor)
## e "loaded" (granada ainda na mão).
func update(id: String, delta: float, aiming: bool, reloading: bool, reload_progress: float, moving: bool, sprinting: bool, phase: float, rig: Dictionary = {}) -> Dictionary:
	reloading = reloading and id in FIREARMS
	if id != weapon_id:
		weapon_id = id
		_support_weight = 0.0
		equip_blend = 0.0
		recoil = 0.0
		if action_age != 0.0 or _attacked_id != id: action_age = 10.0
		_carry_yaw = 0.0
		if id in HANDGUNS: _right = Vector3(0.035, 0.96, -0.365)
		elif id == "smg": _right = Vector3(0.02, 0.93, -0.28)
	var p: Array = DATA.PROFILES.get(id, DATA.PROFILES.pistol)
	equip_blend = move_toward(equip_blend, 1.0, delta * 4.5)
	action_age += delta
	recoil *= exp(-float(p[3]) * delta)
	# Pesos suavizados de andar/correr com as mesmas taxas do Player V1.
	_move_weight = move_toward(_move_weight, 1.0 if moving else 0.0, delta * 7.0)
	_sprint_weight = move_toward(_sprint_weight, 1.0 if moving and sprinting else 0.0, delta * 4.5)
	var run := _sprint_weight
	var walk_clock := phase * TAU
	var arm_swing := cos(walk_clock + PI * 0.175 * run) * lerpf(0.32, 0.55, run) * _move_weight
	var body_offset := Vector3(0, float(rig.get("body_bob", 0.0)) / V1_TO_V2, 0)
	var engaged := aiming or action_age < (0.90 if id == "fists" else 0.45)
	_guard_weight = move_toward(_guard_weight, 1.0 if engaged else 0.0, delta * (4.0 if id == "fists" and not engaged else 8.0))

	var melee_pose: Dictionary = {}
	if id in ["axe", "bat"]:
		melee_pose = _shoulder_swing(id, action_age, walk_clock, _move_weight, run, body_offset)
	melee_support_weight = float(melee_pose.support_weight) if not melee_pose.is_empty() else 0.0
	if id in ["axe", "bat"]: melee_support_weight = 1.0
	var melee_support_active := melee_support_weight > 0.995
	# Postura de ombro: fuzil apoiado gira o tronco para a coronha encostar no
	# ombro de tiro e o braço de apoio alcançar o guarda-mão.
	var shouldered := DATA.STOCK_ENDS.has(id) or id == "rpg"
	var stance := -0.60 if (shouldered or id == "flamethrower") and engaged else 0.0
	if id in LONG_GUNS and not engaged: stance = -0.30
	if not melee_pose.is_empty(): stance = float(melee_pose.torso)
	if id in ["fists", "knuckles", "knife"]:
		var attack_weight := smoothstep(0.0, 0.12, action_age) * (1.0 - smoothstep(0.16, 0.38, action_age))
		stance = (-0.12 + (0.38 if punch_left else -0.38) * attack_weight) * _guard_weight
		if id == "knife": stance = -0.12 + attack_weight * 0.30
	_stance_yaw = lerpf(_stance_yaw, stance, 1.0 - exp(-12.0 * delta))
	var right_shoulder := _shoulder("Right", _stance_yaw) + body_offset
	var left_shoulder := _shoulder("Left", _stance_yaw) + body_offset

	var hand: Vector3 = p[0]
	var support: Vector3 = DATA.SUPPORT_GRIPS.get(id, Vector3.ZERO) - DATA.GRIPS.get(id, Vector3.ZERO) if DATA.SUPPORT_GRIPS.has(id) else Vector3.ZERO
	if id == "axe": support = Vector3(0, 0, -0.12)
	# Pistola/magnum no coldre pendem de uma mão; a outra só sobe para firmar
	# a empunhadura quando o jogador mira ou atira.
	if id in HANDGUNS and not engaged: support = Vector3.ZERO
	var pitch := 0.0
	if not engaged:
		hand.y -= 0.12 if not sprinting else 0.20
		hand.z += 0.07
		if id == "hunting_rifle": hand.z -= 0.10
		pitch -= 0.30 if not sprinting else 0.65
	var long_gun := id in ["smg", "shotgun", "ak47", "m4a1", "rpg", "flamethrower", "hunting_rifle"]
	var carry_yaw := 0.0
	if long_gun:
		if not engaged:
			hand = Vector3(0.19 if id == "flamethrower" else 0.16, 0.97, -0.20)
			pitch = 0.45 if sprinting else 0.25
			carry_yaw = 0.65
			if id in LONG_GUNS:
				# Receptor alinhado com a empunhadura e cano levemente baixo, em
				# vez de torcer o fuzil atravessado pelos dois pulsos.
				carry_yaw = 0.18
				pitch = -0.50 if sprinting else -0.40
		else:
			hand = Vector3(0.23, 1.02, 0.015)
			if DATA.STOCK_ENDS.has(id):
				hand = right_shoulder - (DATA.STOCK_ENDS[id] - DATA.GRIPS[id]) + Vector3(0.065, 0.090, -0.075)
				if id in LONG_GUNS: hand.y -= 0.14
			if id == "flamethrower": hand = Vector3(0.14, 1.00, -0.24)
			if id == "rpg": hand = right_shoulder + Vector3(0.065, 0.050, -0.18)
		if id == "rpg" and not engaged: hand.x += 0.04
		if not (engaged and shouldered): hand.y += body_offset.y
	if id in HANDGUNS and engaged:
		hand = Vector3(0.035, 1.09, -0.32)
	elif id in HANDGUNS:
		# Carregar baixo com uma mão também na corrida: erguer o cano no sprint
		# fazia a pistola parecer um adereço solto abaixo da luva.
		pitch = lerpf(-0.75, -0.88, run)
		carry_yaw = lerpf(0.0, 0.08, run)
	if id == "flamethrower" and not engaged:
		hand = Vector3(0.14, 0.99, -0.28)
		pitch = 0.18 if sprinting else -0.08
		carry_yaw = 0.30
	if id == "sawed_off":
		hand = Vector3(0.08, 1.02 if engaged else 0.98, -0.29)
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

	# Quais braços saem da locomoção. O que não é resolvido aqui continua com o
	# braço do clipe importado (Walking/Running), como o braço livre na V1.
	var right_solve := id != "fists"
	var left_solve := support != Vector3.ZERO
	var right_fist := false
	var left_fist := false
	var right_free := 0.0
	var left_free := 0.0
	var visible := id != "fists"
	if id == "fists":
		# Stable guard, alternating reach and recovery. Both elbows keep the
		# same pole through contact; fingers do not select a different IK path.
		var punching := action_age < 0.28
		if _guard_weight > 0.0:
			# O punho volta firme à guarda, sem herdar a inclinação de arma baixa.
			gun_basis = Basis.IDENTITY
			offhand_basis = Basis.IDENTITY
			right_solve = true
			left_solve = true
			var relaxed_right := Vector3(0.15, 1.04, -0.23) + body_offset
			var relaxed_left := Vector3(-0.15, 1.07, -0.26) + body_offset
			hand = relaxed_right
			left_target = relaxed_left
			if punching:
				var jab := smoothstep(0.025, 0.12, action_age) * (1.0 - smoothstep(0.14, 0.28, action_age))
				if punch_left: left_target = left_target.lerp(Vector3(-0.055, 1.09, -0.46) + body_offset, jab)
				else: hand = hand.lerp(Vector3(0.055, 1.09, -0.46) + body_offset, jab)
			right_fist = true
			left_fist = true
	elif id == "knuckles":
		var pose := _knuckle_pose(knuckle_variant, action_age, engaged, arm_swing, run)
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
			var variant := maxi(knife_variant, 0)
			hand += [Vector3(-0.035, 0.015, -0.23), Vector3(-0.12, 0.09, -0.16), Vector3(-0.055, -0.07, -0.20)][variant] * thrust
			gun_basis = Basis(Vector3.UP, thrust * (0.45 if variant == 1 else 0.08)) * Basis(Vector3.FORWARD, thrust * (0.25 if variant == 2 else 0.05)) * gun_basis
	elif id == "grenade":
		var ready := Vector3(0.24, 0.72, -0.10)
		var cocked := Vector3(0.25, 1.18, -0.12)
		var released := Vector3(0.12, 1.13, -0.38)
		var follow := Vector3(0.10, 0.90, -0.37)
		hand = ready
		if action_age < 0.08: hand = ready.lerp(cocked, smoothstep(0.0, 0.08, action_age))
		elif action_age < GRENADE_RELEASE: hand = cocked.lerp(released, smoothstep(0.08, GRENADE_RELEASE, action_age))
		elif action_age < 0.38: hand = released.lerp(follow, smoothstep(GRENADE_RELEASE, 0.38, action_age))
		elif action_age < 0.70: hand = follow.lerp(ready, smoothstep(0.38, 0.70, action_age))
		gun_basis = Basis(Vector3.RIGHT, -0.20)
		visible = action_age < GRENADE_RELEASE or (action_age >= 0.70 and bool(rig.get("loaded", true)))
		right_free = smoothstep(0.45, 0.70, action_age)
	if id in ["axe", "bat"]:
		hand = melee_pose.hand
		gun_basis = melee_pose.basis
		left_target = hand + gun_basis * support
		left_solve = melee_support_weight > 0.0
		if not melee_support_active: support = Vector3.ZERO

	var reload_pump := 0.0
	if reloading:
		var pose := reload_targets(id, reload_progress)
		var weight: float = pose.weight
		hand = hand.lerp(pose.hand, weight)
		left_target = left_target.lerp(pose.left, weight)
		gun_basis = gun_basis.slerp(pose.basis, weight)
		reload_pump = pose.pump
		# A mão de apoio larga o guarda-mão para buscar munição.
		support = Vector3.ZERO
		left_solve = true
	if id in FIREARMS:
		# O ombro importado é mais estreito e a manga mais grossa que o boneco
		# procedural: estender à frente em vez de erguer o cotovelo.
		if id in HANDGUNS and not reloading:
			if engaged: hand = Vector3(0.035, 1.08, -0.375)
			else:
				var relaxed_carry := Vector3(0.23, 0.80, -0.15) + body_offset
				var sprint_carry := Vector3(0.19, 0.70, -0.11 - arm_swing * 0.07) + body_offset
				hand = relaxed_carry.lerp(sprint_carry, run)
			hand.z += recoil * 0.22
			if engaged: left_target = hand + gun_basis * support
		else:
			if id in LONG_GUNS and not engaged and not reloading:
				var carry_height := (right_shoulder.y + left_shoulder.y) * 0.5 - 0.17
				left_target.y += carry_height - hand.y
				hand.y = carry_height
			hand.z -= 0.080
			left_target.z -= 0.080
			if id == "sawed_off" and not reloading:
				hand = Vector3(0.055, 1.04 if engaged else 0.95, -0.36)
				left_target = hand + gun_basis * support
			elif id == "flamethrower" and not reloading:
				hand = Vector3(0.09, 0.96 if engaged else 0.90, -0.28)
				left_target = hand + gun_basis * support
			elif id == "rpg" and not reloading:
				hand = Vector3(0.06 if engaged else 0.02, 1.10 if engaged else 0.97, -0.28)
				left_target = hand + gun_basis * support
			if reloading and left_target.z > -0.16: left_target.x = minf(left_target.x, -0.24)
			if reloading:
				var reload_hand := Vector3(0.06, 0.96, -0.34) if id in HANDGUNS else Vector3(0.0, 0.98, -0.36)
				if left_target.z < -0.16: left_target += reload_hand - hand
				hand = reload_hand

	_display_basis = _follow_basis(_display_basis, gun_basis, delta)
	_offhand_basis = _follow_basis(_offhand_basis, offhand_basis, delta)
	gun_basis = _display_basis
	offhand_basis = _offhand_basis
	var blend := 1.0 - exp(-22.0 * delta)
	# A curva do soco já tem aceleração e parada; outro filtro deixava a
	# recuperação arrastada e o braço atrasado em relação ao tronco.
	if id == "fists" and action_age < 0.90: blend = 1.0
	# O passo já vem suavizado; filtrar de novo as mãos livres atrasava os
	# braços em relação ao pé oposto.
	if id in ["fists", "knuckles"] and not engaged and not reloading and equip_blend >= 1.0: blend = 1.0
	var hand_target := _right.lerp(hand, blend)
	_right = _right.move_toward(hand_target, delta * 1.4) if id in ["axe", "bat"] else hand_target
	_left = _left.lerp(left_target, blend)
	if id in ["axe", "bat"] and melee_support_weight == 0.0 and equip_blend >= 1.0: _left = left_target
	if id in HANDGUNS and (engaged or reloading or equip_blend < 1.0):
		# Vindo de uma recarga de fuzil, a pistola não pode atravessar o peito
		# no primeiro quadro após equipar.
		_right.x = clampf(_right.x, -0.03, 0.08)
		_right.y = maxf(_right.y, 0.94)
		_right.z = minf(_right.z, -0.33)
	var pump_stroke := reload_pump if reloading else pump
	_support_weight = move_toward(_support_weight, 1.0 if support != Vector3.ZERO else 0.0, delta * 6.0)
	if id in ["axe", "bat"]: _support_weight = melee_support_weight
	var support_locked := support != Vector3.ZERO and _support_weight >= 0.999 and equip_blend >= 0.999
	if support != Vector3.ZERO:
		# O apoio sai da mão de tiro já suavizada: filtrar as duas palmas como
		# pontos independentes fazia a mão esquerda deslizar pelo guarda-mão.
		_left = _left.lerp(_right + gun_basis * (support + Vector3(0, 0, pump_stroke)), _support_weight)

	var left_grip := false
	if id in ["axe", "bat"]: left_grip = melee_support_active
	elif id in HANDGUNS: left_grip = engaged or reloading
	elif id not in ["fists", "knuckles", "knife", "grenade"]: left_grip = not reloading and DATA.SUPPORT_GRIPS.has(id)
	var right_grip := id != "fists" and not right_fist and not (id == "grenade" and not visible)
	_right_solve_weight = move_toward(_right_solve_weight, 1.0 if right_solve else 0.0, delta * 10.0)
	_left_solve_weight = move_toward(_left_solve_weight, 1.0 if left_solve or left_grip else 0.0, delta * 10.0)
	var cross := Basis(Vector3.RIGHT, PI * 0.5)
	var right_basis := gun_basis * (cross if id in CROSS_GRIP else Basis.IDENTITY)
	var left_basis := offhand_basis if id == "knuckles" else gun_basis * (cross if id in CROSS_GRIP or id in CROSS_GRIP_LEFT else Basis.IDENTITY)
	# Soqueira: a fileira de anéis segue o eixo Y da palma calibrada nos dois punhos.
	var model_basis := gun_basis * Basis(Vector3.BACK, PI * 0.5) if id == "knuckles" else gun_basis
	var scale := V1_TO_V2
	var grip: Vector3 = DATA.GRIPS.get(id, Vector3.ZERO)
	var right_v2 := _right * scale
	return {
		"right": right_v2, "left": _left * scale,
		"basis": model_basis, "right_basis": right_basis, "left_basis": left_basis,
		"gun_origin": right_v2 - model_basis * grip * scale,
		"weapon_scale": scale,
		"right_grip": right_grip, "left_grip": left_grip,
		"right_solve": _right_solve_weight > 0.0, "left_solve": _left_solve_weight > 0.0,
		"right_weight": minf(_right_solve_weight, _guard_weight) if id == "fists" else _right_solve_weight,
		"left_weight": minf(_left_solve_weight, melee_support_weight) if id in ["axe", "bat"] else (minf(_left_solve_weight, _guard_weight) if id == "fists" else _left_solve_weight),
		"right_fist": right_fist, "left_fist": left_fist,
		"right_free": right_free, "left_free": left_free,
		"support_locked": support_locked,
		"support_weight": _support_weight if support != Vector3.ZERO else 0.0,
		# Ponto do apoio no espaço do modelo da arma (o machado da V1 aproxima as
		# mãos: 12 cm do cabo, não o ponto de `SUPPORT_GRIPS`).
		"support_point": grip + support + Vector3(0, 0, pump_stroke) if support_locked else DATA.SUPPORT_GRIPS.get(id, grip),
		"long_weapon": long_gun or id in ["axe", "bat"],
		"armed": id != "fists",
		"visible": visible, "engaged": engaged, "torso_yaw": _stance_yaw,
		"pump": pump_stroke,
		"slide": clampf(recoil / maxf(float(p[2]), 0.001), 0.0, 1.0),
	}

func _follow_basis(current: Basis, target: Basis, delta: float) -> Basis:
	var a := current.orthonormalized().get_rotation_quaternion()
	var b := target.orthonormalized().get_rotation_quaternion()
	var angle := a.angle_to(b)
	return Basis(a.slerp(b, minf(1.0, delta * 18.0 / maxf(angle, 0.0001))))

## Ombro (origem do osso Arm) no espaço V1 do Actor, depois da protração da
## clavícula e do giro de postura que `Actor._apply_combat_weapon_pose` aplica.
func _shoulder(side: String, yaw: float) -> Vector3:
	var clavicle: Vector3 = SK_CLAVICLE[side]
	var arm: Vector3 = clavicle + Basis(Vector3.UP, 0.20 if side == "Right" else -0.20) * (SK_ARM[side] - clavicle)
	arm = SK_SPINE + Basis(Vector3.UP, yaw) * (arm - SK_SPINE)
	return Vector3(-arm.x, arm.y, -arm.z) * SKELETON_SCALE / V1_TO_V2

## V1 `MeshyMeleePose.shoulder_swing`: carrega atrás do ombro, junta a mão
## livre e varre o contato; o contato fica dentro de uma interpolação contínua,
## nunca num quadro-chave parado.
func _shoulder_swing(id: String, age: float, gait_phase: float, movement: float, running: float, body_offset: Vector3) -> Dictionary:
	var axe := id == "axe"
	var load_end := 0.24 if axe else 0.22
	var follow_end := 0.44 if axe else 0.40
	var return_start := 0.55 if axe else 0.49
	var end := 0.78 if axe else 0.66
	var carry := Vector3(0.08, 1.05, -0.24)
	var loaded := Vector3(0.05, 1.15, -0.25)
	var follow := Vector3(-0.08, 0.87 if axe else 0.98, -0.37)
	var clear := Vector3(0.27, 1.13, -0.32)
	var roll := -PI / 2.0 if axe else 0.0
	var carry_basis := _basis(Vector3(2.82, -0.10, roll))
	var load_basis := _basis(Vector3(1.75, -0.35, roll)) if axe else _basis(Vector3(0.40, -1.65, 0))
	var follow_basis := _basis(Vector3(-0.65, 0.38, roll)) if axe else _basis(Vector3(0.10, 1.15, 0))
	var clear_basis := _basis(Vector3(1.40, -0.65, roll))
	var hand := carry
	var basis := carry_basis
	var torso := 0.0
	if age < load_end:
		var t := smoothstep(0.0, load_end, age)
		hand = carry.lerp(loaded, t)
		basis = carry_basis.slerp(load_basis, t)
		torso = lerpf(0.0, -0.30, t)
	elif age < follow_end:
		var t := smoothstep(load_end, follow_end, age)
		hand = loaded.lerp(follow, t)
		basis = load_basis.slerp(follow_basis, t)
		torso = lerpf(-0.30, 0.38, t)
	elif age < return_start:
		var t := smoothstep(follow_end, return_start, age)
		hand = follow.lerp(clear, t)
		basis = follow_basis.slerp(clear_basis, t)
		torso = lerpf(0.38, 0.12, t)
	elif age < end:
		var t := smoothstep(return_start, end, age)
		hand = clear.lerp(carry, t)
		basis = clear_basis.slerp(carry_basis, t)
		torso = lerpf(0.12, 0.0, t)
	var support_weight := smoothstep(0.0, load_end * 0.75, age) * (1.0 - smoothstep(follow_end, return_start, age))
	# Balança em torno do contato no ombro, não da mão: o cabo mantém o apoio e
	# a cabeça da arma responde com peso a cada passo.
	var carry_weight := (1.0 - smoothstep(0.0, load_end, age)) + smoothstep(return_start, end, age)
	var motion := movement * carry_weight
	if motion > 0.0:
		var sway_pitch := sin(gait_phase * 2.0 - 0.35) * lerpf(0.035, 0.065, running)
		var roll_sway := sin(gait_phase) * lerpf(0.015, 0.030, running)
		var yaw := cos(gait_phase) * lerpf(0.018, 0.035, running)
		var sway := _basis(Vector3(sway_pitch, yaw, roll_sway) * motion)
		hand = MELEE_SHOULDER + sway * (hand - MELEE_SHOULDER) + body_offset * carry_weight
		basis = sway * basis
	return {"hand": hand, "basis": basis, "support_weight": support_weight, "torso": torso}

## V1 `MeshyKnucklePose.sample`: um punho golpeia enquanto o outro guarda.
## Quatro variações: direto de esquerda, direto de direita, gancho e subida.
func _knuckle_pose(variant: int, age: float, engaged: bool, swing: float, sprint: float) -> Dictionary:
	var right := Vector3(0.14, 1.03, -0.25)
	var left := Vector3(-0.14, 1.06, -0.25)
	var right_basis := Basis.IDENTITY
	var left_basis := Basis.IDENTITY
	if not engaged and age >= KNUCKLE_DURATION:
		right = Vector3(0.20, lerpf(0.72, 0.88, sprint), -0.10 - swing * 0.12)
		left = Vector3(-0.20, lerpf(0.72, 0.88, sprint), -0.10 + swing * 0.12)
	elif age < KNUCKLE_DURATION:
		var reach := smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.14, KNUCKLE_DURATION, age))
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

## V1 `PlayerCombatPose.reload_targets`: uma linha de tempo normalizada pelo
## áudio — ergue, manipula e volta à prontidão antes da gravação terminar.
func reload_targets(id: String, progress: float) -> Dictionary:
	var t := clampf(progress, 0.0, 1.0)
	var weight := smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.88, 1.0, t))
	var hand := Vector3(0.14, 0.91, -0.18)
	var tilt := Vector3(0.22, -0.16, -0.38)
	var insert := Vector3(0.02, 0.79, -0.18)
	var belt := Vector3(-0.19, 0.65, 0.03)
	var left := insert
	var pump := 0.0
	match id:
		"pistol":
			var magazine_well := Vector3(-0.01, 0.89, -0.22)
			var waist_magazine := Vector3(-0.16, 0.78, -0.02)
			var fetch := smoothstep(0.09, 0.22, t) * (1.0 - smoothstep(0.30, 0.47, t))
			left = magazine_well.lerp(waist_magazine, fetch)
			var rack := smoothstep(0.56, 0.65, t) * (1.0 - smoothstep(0.80, 0.89, t))
			left = left.lerp(Vector3(0.06, 0.98, -0.25 + _stroke(t, 0.66, 0.81) * 0.07), rack)
		"smg", "ak47", "m4a1":
			var fetch := smoothstep(0.09, 0.22, t) * (1.0 - smoothstep(0.30, 0.47, t))
			left = insert.lerp(belt, fetch)
			var rack := smoothstep(0.56, 0.65, t) * (1.0 - smoothstep(0.80, 0.89, t))
			left = left.lerp(Vector3(0.07, 0.96, -0.20 + _stroke(t, 0.66, 0.81) * 0.09), rack)
			if id in ["ak47", "m4a1"]:
				hand.x = 0.09
				tilt.z = -0.52
		"magnum":
			# Revólver, não escopeta: antes caía no caso da 12 e ia duas vezes ao cinto
			# como quem enfia cartucho no tubo. Aqui: tambor para a esquerda, cano para
			# cima para ejetar, UMA ida ao cinto pelo carregador rápido, cano para baixo
			# para encaixar, fecha. A abertura do tambor é de `Gameplay._update_weapon_parts`.
			var eject := smoothstep(0.08, 0.20, t) * (1.0 - smoothstep(0.30, 0.40, t))
			var load := smoothstep(0.52, 0.62, t) * (1.0 - smoothstep(0.78, 0.88, t))
			# No encaixe o revólver vem para junto do peito, quase na horizontal: cano
			# para baixo e à frente com as duas mãos lia como arma longa.
			hand = Vector3(0.06, 0.92, -0.17).lerp(Vector3(0.02, 0.97, -0.08), load)
			tilt = Vector3(0.85 * eject - 0.12 * load, -0.10, -0.80 * smoothstep(0.04, 0.14, t) * (1.0 - smoothstep(0.80, 0.92, t)))
			# Palma no tambor aberto (lado esquerdo do receptor), em espaço da arma.
			var cylinder := hand + Basis.from_euler(tilt) * Vector3(-0.075, 0.06, -0.03)
			var fetch := smoothstep(0.32, 0.44, t) * (1.0 - smoothstep(0.46, 0.58, t))
			left = cylinder.lerp(belt, fetch)
		"shotgun", "sawed_off", "hunting_rifle":
			hand = Vector3(0.10, 0.87, -0.15)
			tilt = Vector3(0.05, -0.12, -0.62)
			insert = Vector3(-0.035, 0.84, -0.20)
			var load_motion := maxf(_stroke(t, 0.12, 0.35), _stroke(t, 0.39, 0.66))
			left = insert.lerp(belt, load_motion)
			if id == "shotgun":
				pump = _stroke(t, 0.77, 0.94) * 0.09
				var grab := smoothstep(0.68, 0.77, t)
				var basis := Basis.from_euler(tilt)
				left = left.lerp(hand + basis * (DATA.SUPPORT_GRIPS.shotgun - DATA.GRIPS.shotgun + Vector3(0, 0, pump)), grab)
			elif id == "hunting_rifle":
				hand = Vector3(0.15, 0.87, -0.30)
				left = left.lerp(Vector3(0.06, 0.94, -0.13), smoothstep(0.68, 0.79, t))
		"rpg":
			hand = Vector3(0.17, 0.91, -0.07)
			tilt = Vector3(0.58, 0.0, -0.28)
			# Assenta o foguete na boca e devolve a mão de apoio ao tubo, em vez de
			# deixá-la presa na ponta.
			var seat := smoothstep(0.16, 0.42, t) * (1.0 - smoothstep(0.58, 0.78, t))
			var regrip := smoothstep(0.58, 0.78, t)
			left = belt.lerp(Vector3(-0.03, 0.96, -0.26), seat).lerp(Vector3(-0.02, 0.90, -0.14), regrip)
		"flamethrower":
			tilt = Vector3(-0.18, 0.0, -0.43)
			left = Vector3(-0.06, 0.83, -0.17) + Vector3(sin(t * TAU * 2.0) * 0.035, cos(t * TAU * 2.0) * 0.025, 0)
		"grenade":
			hand = belt.lerp(Vector3(0.18, 0.92, -0.13), smoothstep(0.2, 0.82, t))
			left = Vector3(-0.17, 0.76, -0.05)
	# Manipula a arma à frente da jaqueta; a mão livre mantém o alcance do cinto
	# enquanto os alvos de inserção acompanham o receptor.
	tilt.y = 0.55
	var clearance_offset := Vector3(0.10, 0, -0.14)
	hand += clearance_offset
	left += clearance_offset * clampf(left.distance_to(belt) / 0.15, 0.0, 1.0)
	if id == "grenade":
		hand = Vector3(0.25, lerpf(0.72, 0.94, smoothstep(0.2, 0.82, t)), -0.16)
	return {"hand": hand, "left": left, "basis": Basis.from_euler(tilt), "weight": weight, "pump": pump}

func _stroke(t: float, start: float, finish: float) -> float:
	return sin(clampf((t - start) / maxf(finish - start, 0.001), 0.0, 1.0) * PI)

func _basis(angles: Vector3) -> Basis:
	return Basis(Vector3.UP, angles.y) * Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.BACK, angles.z)
