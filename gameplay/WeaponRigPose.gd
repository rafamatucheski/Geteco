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
const MOVES = preload("res://gameplay/MeleeMoveset.gd")
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
const GRENADE_RECOVERY := 0.70
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
## Hit-stop (congelamento curto do golpe no impacto) por arma, em segundos. É o
## que dá peso ao contato nos jogos de ação: o braço "trava" no alvo por 3–5
## quadros antes do follow-through. Golpe pesado (fim da sequência) segura mais.
const HIT_STOP := {"fists": 0.045, "knuckles": 0.055, "knife": 0.04, "bat": 0.075, "axe": 0.085}
const HEAVY_HIT_STOP := 0.035
## Velocidade angular máxima das articulações do braço (rad/s) durante o golpe.
## O padrão do Actor (18) é o da prontidão; um direto real passa de 25 no cotovelo.
const STRIKE_ARM_RATE := 30.0
## Fração do curso do ferrolho/telha gasta puxando; o resto é o retorno da mola.
const RACK_PULL := 0.72
## Parte da torção da pegada de taco/machado que o antebraço assume (o resto fica
## no pulso); ver `Actor._solve_combat_arm`.
const FOREARM_SHARE := 0.8
## Rolagem máxima da arma em torno do próprio cabo (rad/s; ver `MeleeMoveset.swing_basis`).
const BLADE_ROLL_RATE := 20.0
## Cabeça do Dante no espaço V1 do Actor, medida nos ossos realizados (Head + 40%
## até head_end) com a guarda parada; inclinar 0,1 rad para trás leva a cabeça
## ~6 cm para trás (coeficiente medido, não o braço de alavanca geométrico). A malha
## da cabeça com cabelo/barba cabe em 0,14 m = 0,111 V1. Folga mínima garantida =
## HEAD_CLEARANCE + CLEAR_SOFT/2 (0,166 V1, 5,5 cm de margem além do raio) porque,
## perto do limite de alcance, a mão real fica 3–4 cm atrás do alvo.
const HEAD_CENTER := Vector3(0.0, 1.243, -0.065)
## Carregar no ombro (V1): punho à frente do peito, à direita; a cabeça da arma vai
## para trás por cima do ombro direito, por fora da cabeça do Dante.
const CARRY_HAND := Vector3(0.20, 0.90, -0.15)
const CARRY_HEAD := Vector3(0.25, 0.82, 0.5)
const CARRY_POLE := Vector3(0.9, -1.5, 0.3)
## Fuzil apoiado: giro do tronco na mira, bolso da coronha relativo ao ombro (x para
## fora, y para cima, z para a frente do peito; espaço V1) e alcance da palma esquerda
## a partir do ombro (0,41 m no V2, medido: pedindo 0,44 o IK ficava 2–3 cm curto). O
## apoio não recua além de z = −0,03 da empunhadura (frente do encaixe do carregador).
const STOCK_STANCE := -0.75
## Fração do saque a partir da qual a arma longa aparece na mão.
const EQUIP_SHOW := 0.6
const EQUIP_SHOW_HANDGUN := 0.15
const STOCK_POCKET := Vector3(-0.02, -0.025, 0.06)
const LEFT_PALM_REACH := 0.41 / (1.03 / 0.82)
const SUPPORT_MIN_REACH_Z := -0.03
## Rifle de caça: o receptor tem ferrolho e luneta logo à frente da empunhadura; a mão
## deslizando até ali enfiava os dedos neles (4,5 cm). Para no início do guarda-mão.
const SUPPORT_MIN_REACH_Z_BY_ID := {"hunting_rifle": -0.14}
## Avanço do bolso por seno da inclinação da arma (altura do bico da coronha, V1).
const STOCK_TOE := 0.08
## Rifle de caça: coronha curta (15,5 cm da empunhadura ao fim) e sem empunhadura de
## pistola; a base da coronha encostava 4–5 cm no antebraço direito logo atrás do pulso.
## Medido em 2026-10-06: bolso 3 cm mais baixo na mira e na recarga, 3 cm mais alto
## com a arma baixa (a ponta da coronha sai de cima do antebraço).
const STOCK_POCKET_SHIFT := {"hunting_rifle": Vector3(0, -0.03, 0)}
const STOCK_POCKET_SHIFT_READY := {"hunting_rifle": Vector3(0, 0.03, 0)}
const STOCK_ELBOW := Vector3(1.4, -1.2, 0.3)
const RELOAD_LEFT_POLE := Vector3(-0.2, -1.5, 1.0)
## Mão direita no lança-foguetes apoiado (V1): tubo com o fundo no topo do ombro
## (y 1,44 no V2) e a lateral por fora da cabeça (x ≤ 0,12 no V2).
const RPG_SHOULDER := Vector3(0.145, 1.115, -0.26)
## Boca do tubo do lança-foguetes no espaço do modelo (eixo 8 cm acima das empunhaduras;
## a ogiva encaixada vai de z −0,31 a −0,49).
const RPG_MUZZLE := Vector3(0.0, 0.08, -0.31)
## Foguete na recarga: a mão esquerda o pega no cinto em RPG_ROCKET_GRAB e o encaixa
## entre RPG_ROCKET_SEAT.x e .y (fração da recarga); o centro da ogiva fica 9 cm à
## frente da boca quando encaixado (`ArsenalWeapon3D`, "LoadedRocket").
const RPG_ROCKET_GRAB := 0.27
const RPG_ROCKET_SEAT := Vector2(0.50, 0.62)
const RPG_ROCKET_CENTER := 0.09
const RPG_POLE := Vector3(0.4, -1.5, -0.2)
## Submetralhadora na recarga rolada como AK/M4: coronha curta, o receptor fica rente
## ao peito, e a −0,38 o topo dele entrava 5 cm na jaqueta andando (medido: −0,60 → 3 cm).
const SMG_RELOAD_ROLL := -0.60
const KNUCKLE_RUN_POLE := Vector3(0.45, -1.5, 0.9)
const HEAD_ABOVE_SPINE := 0.6
const HEAD_CLEARANCE := 0.146
## Carregando parado: só a cabeça com cabelo (+2 cm de margem com a faixa suave).
## Com a margem do golpe a arma saía do ombro e atravessava o peito.
const HEAD_CLEARANCE_CARRY := 0.111
const CLEAR_SOFT := 0.04
const WEAPON_RADIUS := {"bat": 0.036, "axe": 0.048}

var weapon_id := ""
var action_age := 10.0
var _attacked_id := ""
var recoil := 0.0
var equip_blend := 1.0
var punch_left := false
var knife_variant := -1
var knuckle_variant := -1
var melee_support_weight := 0.0
## Posição na sequência de golpes (combo) e a variação em curso (`MeleeMoveset`).
var combo_step := 0
var hit_stop := 0.0
var _move: Dictionary = {}
var _melee_from: Dictionary = {}
var _melee_now: Dictionary = {}
var _melee_now_id := ""
var _clear_blend := 0.0
var _carry_support := 0.0
## 1 = fuzil na prontidão baixa, 0 = mirando/recarregando (bolso da coronha, suavizado).
var _low_ready := 0.0
## Eixo de rolagem da arma no quadro anterior (ver `MeleeMoveset.swing_basis`).
var _swing_x := Vector3.ZERO
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
## Mala de mão na mão esquerda: o braço esquerdo fica no carregamento (não vai ao apoio da
## pistola, à munição nem ao soco) e só o direito trabalha. Ver `_bag_carry_hand`.
var bag_carry := false
var _bag_weight := 0.0
## Orientação da palma que segura a alça: mão pendurada, dedos fechados em volta da alça
## (escolhida entre 8 candidatas em captura, 2026-09-29; as outras deixavam a palma
## aberta para cima ou os dedos apontando para o chão).
static var bag_palm_basis := Basis(Vector3.BACK, PI * 0.5)

## Soco, soqueira, taco e machado seguem a sequência de `MeleeMoveset` (combo):
## golpes seguidos dentro da janela avançam a variação, e o golpe parte da pose
## em que o anterior estava. A faca mantém o contador de variações da V1
## (`PlayerCombatPose.on_attack`).
func attack(id: String, recoil_multiplier: float = 1.0) -> void:
	var chain := MOVES.moves(id)
	if not chain.is_empty():
		# Apertar de novo dentro da janela encadeia a próxima variação; parado,
		# a sequência recomeça do primeiro golpe.
		var chained := _attacked_id == id and action_age < float(MOVES.CHAIN.get(id, 0.6))
		combo_step = (combo_step + 1) % chain.size() if chained else 0
		# Com a mala na mão esquerda só a direita soca.
		if bag_carry and String(chain[combo_step].get("side", "")) == "left": combo_step = (combo_step + 1) % chain.size()
		_move = chain[combo_step]
		_melee_from = _melee_now.duplicate() if _melee_now_id == id else {}
		hit_stop = 0.0
	_attacked_id = id
	var profile: Array = DATA.PROFILES.get(id, DATA.PROFILES.pistol)
	recoil = minf(recoil + float(profile[2]) * recoil_multiplier, float(profile[2]) * 1.6 * recoil_multiplier)
	action_age = 0.0
	if id == "knife": knife_variant = (knife_variant + 1) % 3
	if id == "knuckles": knuckle_variant = (knuckle_variant + 1) % 4
	if id in ["fists", "knuckles"]: punch_left = String(_move.get("side", "right")) == "left"

## Contato confirmado num alvo (Gameplay): segura o golpe no impacto.
func impact(id: String) -> void:
	hit_stop = float(HIT_STOP.get(id, 0.0)) + (HEAVY_HIT_STOP if heavy_attack() else 0.0)

## O golpe em curso é o pesado que fecha a sequência.
func heavy_attack() -> bool:
	return bool(_move.get("heavy", false)) and action_age < float(_move.get("end", 0.0)) * MOVES.scale(_attacked_id)

## Janela para o próximo aperto continuar a sequência (ferramentas de captura).
func chain_window(id: String) -> float:
	return float(MOVES.CHAIN.get(id, 0.30))

func reset() -> void:
	weapon_id = ""
	action_age = 10.0
	_attacked_id = ""
	recoil = 0.0
	equip_blend = 1.0
	melee_support_weight = 0.0
	combo_step = 0
	hit_stop = 0.0
	_move = {}
	_melee_from = {}
	_melee_now = {}
	_melee_now_id = ""
	_clear_blend = 0.0
	_carry_support = 0.0
	_low_ready = 0.0
	_swing_x = Vector3.ZERO
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
	# Hit-stop: o golpe para no impacto; o resto do corpo (passo, respiração) segue.
	var stopped := hit_stop > 0.0
	if stopped: hit_stop = maxf(0.0, hit_stop - delta)
	else: action_age += delta
	recoil *= exp(-float(p[3]) * delta)
	# Pesos suavizados de andar/correr com as mesmas taxas do Player V1.
	_move_weight = move_toward(_move_weight, 1.0 if moving else 0.0, delta * 7.0)
	_sprint_weight = move_toward(_sprint_weight, 1.0 if moving and sprinting else 0.0, delta * 4.5)
	var run := _sprint_weight
	var walk_clock := phase * TAU
	var arm_swing := cos(walk_clock + PI * 0.175 * run) * lerpf(0.32, 0.55, run) * _move_weight
	var body_offset := Vector3(0, float(rig.get("body_bob", 0.0)) / V1_TO_V2, 0)
	var move_end := float(_move.get("end", 0.0)) * MOVES.scale(id) if _attacked_id == id else 0.0
	var in_move := not MOVES.moves(id).is_empty() and action_age < move_end
	var engaged := aiming or action_age < (0.90 if id == "fists" else 0.45) or in_move
	# Armas de duas mãos já são negadas com a mala; o resto usa uma mão só.
	bag_carry = bool(rig.get("bag_carry", false)) and id not in LONG_GUNS and id not in ["axe", "bat", "rpg", "flamethrower", "sawed_off"]
	_bag_weight = move_toward(_bag_weight, 1.0 if bag_carry else 0.0, delta * 8.0)
	# A guarda sobe de uma vez quando o golpe sai: subir em 0,12 s comia a antecipação.
	_guard_weight = move_toward(_guard_weight, 1.0 if engaged else 0.0, delta * (4.0 if id == "fists" and not engaged else (24.0 if in_move else 8.0)))

	var melee_pose: Dictionary = {}
	var swing: Dictionary = {}
	if id in ["axe", "bat"]:
		# Fora do golpe: apoiado no ombro direito, só a mão direita, com o balanço do passo.
		melee_pose = _shoulder_carry(id, walk_clock, _move_weight, run, body_offset)
		var rest := _swing_rest(id, melee_pose)
		if in_move:
			swing = MOVES.sample(id, _move, action_age, _melee_from if not _melee_from.is_empty() else rest, rest)
			var swing_basis := MOVES.swing_basis(id, swing.d, swing.k, _swing_x, BLADE_ROLL_RATE * delta)
			_swing_x = (swing_basis * (Basis(Vector3.BACK, PI * 0.5) if id == "axe" else Basis.IDENTITY)).x
			melee_pose = {"hand": swing.r, "basis": swing_basis, "support_weight": 1.0, "torso": swing.torso}
			_remember(id, swing)
		else:
			_remember(id, rest)
			_swing_x = (melee_pose.basis as Basis * (Basis(Vector3.BACK, PI * 0.5) if id == "axe" else Basis.IDENTITY)).x
		# Margem do golpe só em movimento (atraso do IK); carregando, a pose de ombro
		# da V1 fica quase intacta. Transição suave entre as duas.
		_clear_blend = move_toward(_clear_blend, 1.0 if in_move else 0.0, delta * 3.0)
		var cleared := _clear_head(id, melee_pose.hand, melee_pose.basis, swing, body_offset, lerpf(HEAD_CLEARANCE_CARRY, HEAD_CLEARANCE, _clear_blend))
		melee_pose.hand = cleared.hand
		melee_pose.basis = cleared.basis
	melee_support_weight = float(melee_pose.support_weight) if not melee_pose.is_empty() else 0.0
	if id in ["axe", "bat"]:
		# A mão esquerda vem ao cabo quando o golpe sai (a preparação dura 0,24 s) e
		# volta a balançar com o passo no carregar.
		_carry_support = move_toward(_carry_support, 1.0 if in_move else 0.0, delta * (9.0 if in_move else 4.0))
		melee_support_weight = _carry_support
	var melee_support_active := melee_support_weight > 0.995
	# Postura de ombro: fuzil apoiado gira o tronco para a coronha encostar no
	# ombro de tiro e o braço de apoio alcançar o guarda-mão.
	var shouldered := DATA.STOCK_ENDS.has(id) or id == "rpg"
	var stance := -0.60 if (shouldered or id == "flamethrower") and engaged else 0.0
	# Fuzil na mira: tronco de lado (~43°), como atirador de verdade. A −0,60 a mão de
	# apoio não alcançava o guarda-mão com a coronha no ombro (pedia 0,46–0,50 m para
	# um braço de ~0,47 m) e o solver puxava a arma para dentro do peito.
	if id in LONG_GUNS and engaged: stance = STOCK_STANCE
	# Prontidão baixa com o mesmo giro da mira: a −0,30 o guarda-mão (cano para baixo e
	# para dentro) ficava fora do alcance do braço esquerdo e a mão deslizava até o
	# carregador, encostada na direita. Mesmo giro também evita girar o tronco ao mirar.
	if id in LONG_GUNS and not engaged: stance = STOCK_STANCE
	# Lança-foguetes sempre no ombro: de frente o braço esquerdo não alcança o tubo.
	if id == "rpg": stance = -0.60
	if not melee_pose.is_empty(): stance = float(melee_pose.torso)
	var punch: Dictionary = {}
	if id in ["fists", "knuckles"]:
		var rest := _punch_rest()
		if in_move:
			punch = MOVES.sample(id, _move, action_age, _melee_from if not _melee_from.is_empty() else rest, rest)
			_remember(id, punch)
			stance = float(punch.torso)
		else:
			_remember(id, rest)
			stance = -0.12 * _guard_weight
	if id == "knife":
		var attack_weight := smoothstep(0.0, 0.12, action_age) * (1.0 - smoothstep(0.16, 0.38, action_age))
		stance = -0.12 + attack_weight * 0.30
	# No golpe a curva já é suave; filtrar o tronco atrasava o giro em relação ao braço.
	if in_move: _stance_yaw = stance
	else: _stance_yaw = lerpf(_stance_yaw, stance, 1.0 - exp(-12.0 * delta))
	var right_shoulder := _shoulder("Right", _stance_yaw) + body_offset
	var left_shoulder := _shoulder("Left", _stance_yaw) + body_offset

	var hand: Vector3 = p[0]
	var support: Vector3 = DATA.SUPPORT_GRIPS.get(id, Vector3.ZERO) - DATA.GRIPS.get(id, Vector3.ZERO) if DATA.SUPPORT_GRIPS.has(id) else Vector3.ZERO
	if id == "axe": support = DATA.SUPPORT_GRIPS.axe - DATA.GRIPS.axe
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
			if id == "rpg":
				# Lança-foguetes descansando no ombro como na mira (antes atravessado na
				# diagonal, com a traseira passando pelo braço direito). Cano para cima,
				# a traseira afundava no ombro.
				carry_yaw = 0.0
				pitch = -0.04
			if id in LONG_GUNS:
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
	# Rotação do punho com pulso reto (Actor); nula = mão segue a base pedida.
	var wrist_right: Variant = null
	var wrist_left: Variant = null
	if id == "fists":
		# Guarda estável e golpes da sequência de `MeleeMoveset`; o polo do
		# cotovelo só muda onde a chave pede (gancho, uppercut).
		if _guard_weight > 0.0:
			# O punho volta firme à guarda, sem herdar a inclinação de arma baixa.
			right_solve = true
			left_solve = true
			var pose: Dictionary = punch if in_move else _punch_rest()
			hand = pose.r + body_offset
			left_target = pose.l + body_offset
			gun_basis = _basis(pose.rb)
			offhand_basis = _basis(pose.lb)
			wrist_right = float(pose.rr)
			wrist_left = float(pose.lr)
			right_fist = true
			left_fist = true
	elif id == "knuckles":
		if in_move or engaged:
			var pose: Dictionary = punch if in_move else _punch_rest()
			hand = pose.r + body_offset
			left_target = pose.l + body_offset
			gun_basis = _basis(pose.rb)
			offhand_basis = _basis(pose.lb)
			wrist_right = float(pose.rr)
			wrist_left = float(pose.lr)
		else:
			var pose := _knuckle_pose(knuckle_variant, 10.0, false, arm_swing, run)
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
		var ready := Vector3(0.24, 0.72, -0.10 - arm_swing * 0.07) + body_offset
		# Arremesso pela frente, abaixo do ombro e pelo lado direito.
		# O alvo alto junto ao rosto elevava/torcia a manga contra a cabeça.
		var cocked := Vector3(0.34, 0.94, -0.14) + body_offset
		var released := Vector3(0.27, 0.99, -0.43) + body_offset
		var follow := Vector3(0.25, 0.79, -0.35) + body_offset
		hand = ready
		if action_age < 0.08: hand = ready.lerp(cocked, smoothstep(0.0, 0.08, action_age))
		elif action_age < GRENADE_RELEASE: hand = cocked.lerp(released, smoothstep(0.08, GRENADE_RELEASE, action_age))
		elif action_age < 0.38: hand = released.lerp(follow, smoothstep(GRENADE_RELEASE, 0.38, action_age))
		elif action_age < GRENADE_RECOVERY: hand = follow.lerp(ready, smoothstep(0.38, GRENADE_RECOVERY, action_age))
		gun_basis = Basis(Vector3.RIGHT, -0.20)
		visible = action_age < GRENADE_RELEASE or (action_age >= GRENADE_RECOVERY and bool(rig.get("loaded", true)))
		right_free = smoothstep(0.45, GRENADE_RECOVERY, action_age)
	if id in ["axe", "bat"]:
		hand = melee_pose.hand
		gun_basis = melee_pose.basis
		left_target = hand + gun_basis * support
		left_solve = melee_support_weight > 0.0
		if not melee_support_active: support = Vector3.ZERO

	_low_ready = move_toward(_low_ready, 1.0 if not engaged and not reloading else 0.0, delta * 6.0)
	var reload_pump := 0.0
	var reload_kick := Vector3.ZERO
	# Fuzil apoiado: coronha (espaço do modelo, relativa à empunhadura) presa ao bolso
	# do ombro depois da suavização da base; INF = arma não apoiada.
	var stock_pin := Vector3.INF
	var stock_extra := Vector3.ZERO
	if reloading:
		var pose := reload_targets(id, reload_progress)
		reload_kick = pose.kick
		var weight: float = pose.weight
		# Poses de recarga em altura de pé: seguem a altura do corpo (andando agachado).
		hand = hand.lerp(pose.hand + body_offset, weight)
		# Entre o ombro e a pose de recarga o tubo do lança-foguetes varria o braço
		# direito (5 cm dentro): a transição passa à frente, em arco.
		if id == "rpg": hand += Vector3(0.0, 0.10, -0.22) * sin(PI * weight)
		left_target = left_target.lerp(pose.left + body_offset, weight)
		gun_basis = gun_basis.slerp(pose.basis, weight)
		reload_pump = pose.pump
		# A mão de apoio larga o guarda-mão para buscar munição.
		support = Vector3.ZERO
		left_solve = true
	if id in FIREARMS:
		# O ombro importado é mais estreito e a manga mais grossa que o boneco
		# procedural: estender à frente em vez de erguer o cotovelo.
		if id in HANDGUNS and not reloading:
			# Mira acompanha a altura do corpo: andando de lado o clipe agacha 22 cm e a
			# pistola numa altura fixa subia até a frente do rosto.
			if engaged: hand = Vector3(0.035, 1.08, -0.375) + body_offset
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
				hand = Vector3(0.055, 1.04 if engaged else 0.95, -0.36) + body_offset
				left_target = hand + gun_basis * support
			elif id == "flamethrower" and not reloading:
				hand = Vector3(0.09, 0.96 if engaged else 0.90, -0.28) + body_offset
				left_target = hand + gun_basis * support
			elif id == "rpg" and not reloading:
				# Tubo em cima do ombro direito, por fora da cabeça: o eixo do tubo fica
				# 8 cm (modelo) acima das empunhaduras e o raio é ~4 cm; com a mão em
				# x = 0,06 o tubo passava pelo queixo e pelo lado do pescoço.
				hand = RPG_SHOULDER + body_offset
				left_target = hand + gun_basis * support
			if reloading and left_target.z > -0.16: left_target.x = minf(left_target.x, -0.24)
			if reloading and id != "rpg":
				var reload_hand := (Vector3(0.06, 0.96, -0.34) if id in HANDGUNS else Vector3(0.0, 0.98, -0.36)) + body_offset
				if left_target.z < -0.16: left_target += reload_hand - hand
				hand = reload_hand
				# Tranco do encaixe/ferrolho: a arma pula na mão e a mão de apoio vai junto.
				hand += reload_kick
				if left_target.z < -0.16: left_target += reload_kick
				if id in LONG_GUNS:
					# A coronha fica no ombro e a arma inclina em torno dela. Com a mão no
					# meio do peito e o cano para dentro, a coronha entrava 10–14 cm no
					# lado direito do tronco.
					stock_pin = DATA.STOCK_ENDS[id] - DATA.GRIPS[id]
					stock_extra = reload_kick
					var shouldered_hand: Vector3 = _stock_pocket(_stance_yaw, gun_basis, id, _low_ready) + body_offset - gun_basis * stock_pin + stock_extra
					if left_target.z < -0.16: left_target += shouldered_hand - hand
					hand = shouldered_hand

	if id in LONG_GUNS and not reloading:
		# Coronha apoiada no ombro (mira e prontidão baixa): a arma gira em torno dela,
		# não da mão. Girando em torno da mão, o cano baixo levantava a coronha por
		# cima do ombro e ela saía nas costas; na mira a mão de apoio não alcançava o
		# guarda-mão e o solver bilateral puxava a arma 13–28 cm para dentro do peito.
		stock_pin = DATA.STOCK_ENDS[id] - DATA.GRIPS[id] - Vector3(0, 0, recoil * 0.05)
		# No saque a arma inclina em torno da coronha (pitch em `equip_blend`); descer a
		# arma inteira 16 cm enfiava a coronha no peito, abaixo do ombro.
		stock_extra = Vector3.ZERO
		hand = _stock_pocket(_stance_yaw, gun_basis, id, _low_ready) + body_offset - gun_basis * stock_pin + stock_extra
		support = _reachable_support(id, hand, gun_basis, left_shoulder)
		left_target = hand + gun_basis * (support + Vector3(0, 0, pump))
	var carry_left_basis := bag_palm_basis
	if bag_carry:
		# Mão da mala: sem apoio na arma, sem guarda de soco, sem ir buscar munição.
		support = Vector3.ZERO
		left_solve = true
		left_fist = false
		left_free = 0.0
		left_target = _bag_carry_hand(arm_swing, run, body_offset)
		wrist_left = null
		offhand_basis = carry_left_basis
	# Durante o golpe a curva autorada já é a velocidade da arma: o limite de
	# 18 rad/s da prontidão freava o taco antes do contato.
	var basis_rate := 70.0 if in_move else 18.0
	_display_basis = _follow_basis(_display_basis, gun_basis, delta, basis_rate)
	_offhand_basis = _follow_basis(_offhand_basis, offhand_basis, delta, basis_rate)
	gun_basis = _display_basis
	offhand_basis = _offhand_basis
	var blend := 1.0 - exp(-22.0 * delta)
	if stock_pin != Vector3.INF:
		# A mão sai da base JÁ suavizada: suavizando posição e rotação separadas, a
		# coronha entrava 3–5 cm no ombro ao subir da prontidão baixa para a mira.
		var pinned := _stock_pocket(_stance_yaw, gun_basis, id, _low_ready) + body_offset - gun_basis * stock_pin + stock_extra
		if not reloading or left_target.z < -0.16: left_target += pinned - hand
		hand = pinned
		blend = 1.0
	# A curva do soco já tem aceleração e parada; outro filtro deixava a
	# recuperação arrastada e o braço atrasado em relação ao tronco.
	if id == "fists" and action_age < 0.90: blend = 1.0
	if in_move: blend = 1.0
	# O passo já vem suavizado; filtrar de novo as mãos livres atrasava os
	# braços em relação ao pé oposto.
	if id in ["fists", "knuckles"] and not engaged and not reloading and equip_blend >= 1.0: blend = 1.0
	var hand_target := _right.lerp(hand, blend)
	_right = _right.move_toward(hand_target, delta * 1.4) if id in ["axe", "bat"] and not in_move and equip_blend < 1.0 else hand_target
	if stopped and in_move:
		# Tremor curto do impacto, só enquanto o golpe está travado no alvo.
		var shake := Vector3(sin(hit_stop * 310.0), cos(hit_stop * 270.0), 0.0) * 0.006
		_right += shake
		if id in ["fists", "knuckles"]: _left += shake
	_left = _left.lerp(left_target, blend)
	if id in ["axe", "bat"] and melee_support_weight == 0.0 and equip_blend >= 1.0: _left = left_target
	if id in HANDGUNS and (engaged or reloading or equip_blend < 1.0):
		# Vindo de uma recarga de fuzil, a pistola não pode atravessar o peito
		# no primeiro quadro após equipar.
		_right.x = clampf(_right.x, -0.03, 0.08)
		_right.y = maxf(_right.y, 0.94 + minf(body_offset.y, 0.0))
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
	if bag_carry: left_grip = true # dedos fechados na alça
	elif id in ["axe", "bat"]: left_grip = melee_support_active
	elif id in HANDGUNS: left_grip = engaged or reloading
	elif id not in ["fists", "knuckles", "knife", "grenade"]: left_grip = not reloading and DATA.SUPPORT_GRIPS.has(id)
	var right_grip := id != "fists" and not right_fist and not (id == "grenade" and not visible)
	_right_solve_weight = move_toward(_right_solve_weight, 1.0 if right_solve else 0.0, delta * 10.0)
	_left_solve_weight = move_toward(_left_solve_weight, 1.0 if left_solve or left_grip else 0.0, delta * 10.0)
	var cross := Basis(Vector3.RIGHT, PI * 0.5)
	var right_basis := gun_basis * (cross if id in CROSS_GRIP else Basis.IDENTITY)
	var left_basis := offhand_basis if id in ["fists", "knuckles"] or bag_carry else gun_basis * (cross if id in CROSS_GRIP or id in CROSS_GRIP_LEFT else Basis.IDENTITY)
	# Soqueira: a fileira de anéis segue o eixo Y da palma calibrada nos dois punhos.
	var model_basis := gun_basis * Basis(Vector3.BACK, PI * 0.5) if id == "knuckles" else gun_basis
	var scale := V1_TO_V2
	var grip: Vector3 = DATA.GRIPS.get(id, Vector3.ZERO)
	var body: Dictionary = punch if not punch.is_empty() else swing
	# Carregando no ombro: cotovelo direito pendendo ao lado do corpo. O polo de arma
	# longa (para fora e para a frente, pensado para fuzil apontado) abria o cotovelo
	# na altura do ombro e o cabo passava por baixo do braço.
	if body.is_empty() and id in ["axe", "bat"]: body = {"rp": CARRY_POLE}
	# Lança-foguetes: cotovelo direito para baixo, sob o tubo. Aberto para fora (polo de
	# arma longa) o tubo passava pelo cotovelo ao voltar da recarga para o ombro.
	if id == "rpg": body = {"rp": RPG_POLE}
	# Soqueira sem golpe nem guarda: cotovelos junto ao corpo, para baixo e para trás.
	if id == "knuckles" and not in_move and not engaged: body = {"rp": KNUCKLE_RUN_POLE, "lp": Vector3(-KNUCKLE_RUN_POLE.x, KNUCKLE_RUN_POLE.y, KNUCKLE_RUN_POLE.z)}
	if stock_pin != Vector3.INF: body = {"rp": STOCK_ELBOW}
	if reloading and id in LONG_GUNS:
		# Mão esquerda buscando cartucho/ferrolho junto ao receptor: com o polo de arma
		# longa o cotovelo esquerdo subia acima da mão ("braço de baixo para cima").
		body = body.duplicate()
		body["lp"] = RELOAD_LEFT_POLE
	# Arma longa aparece na mão quando o braço chega (~0,1 s de saque, como tirá-la das
	# costas): antes, presa à mão que ainda vinha da arma anterior, ela atravessava o
	# tronco 5–9 cm nos primeiros quadros (medido em 2026-10-06).
	if id in LONG_GUNS or id in ["rpg", "flamethrower"]: visible = visible and equip_blend >= EQUIP_SHOW
	# Pistola/magnum/cano serrado: 2 quadros de saque; no primeiro a mão ainda era o
	# punho fechado da arma anterior e a pistola aparecia dentro dela.
	if id in HANDGUNS or id == "sawed_off": visible = visible and equip_blend >= EQUIP_SHOW_HANDGUN
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
		# Punhos em guarda contam como armados: a coluna volta à postura e só recebe o
		# giro. Sem isso o clipe de andar de lado mirando dobrava o tronco para a frente e a
		# cabeça descia abaixo dos punhos.
		"armed": id != "fists" or (engaged and _guard_weight > 0.0),
		"bag_carry": bag_carry,
		"visible": visible, "engaged": engaged, "torso_yaw": _stance_yaw,
		# Corpo no golpe (Actor): quadril lidera o tronco, peso à frente, joelhos.
		"hip_yaw": float(body.get("hip", _stance_yaw * 0.35)),
		"lean": float(body.get("lean", 0.0)),
		"dip": float(body.get("dip", 0.0)) * scale,
		"step": float(body.get("step", 0.0)) * scale,
		"arm_rate": STRIKE_ARM_RATE if in_move else 18.0,
		"right_pole": body.get("rp", null), "left_pole": body.get("lp", null),
		"melee_action": in_move,
		# Fração do giro do tronco que a cabeça devolve (fuzil, lança-foguetes e
		# lança-chamas), proporcional ao giro: contínua ao subir/baixar a arma.
		"head_counter": minf(0.85, 0.85 * absf(_stance_yaw) / absf(STOCK_STANCE)) if shouldered or id == "flamethrower" else 0.0,
		"swing_trail": in_move and id in ["axe", "bat"] and action_age > float(MOVES.SWING_SCALE.get(id, 1.0)) * 0.26 and action_age < float(MOVES.SWING_SCALE.get(id, 1.0)) * 0.47,
		"combo_step": combo_step,
		"right_wrist_roll": wrist_right, "left_wrist_roll": wrist_left,
		"grip_as_fist": id in ["axe", "bat"],
		"forearm_twist_share": FOREARM_SHARE if id in ["axe", "bat"] else 0.0,
		"grip_solver": id in ["axe", "bat"],
		"pump": pump_stroke,
		"slide": clampf(recoil / maxf(float(p[2]), 0.001), 0.0, 1.0),
	}

## Palma esquerda com a mala: braço quase reto ao lado da coxa, com pouquíssimo vaivém
## (a mala pesa) e um leve recuo na corrida. Espaço da V1, como as outras poses.
func _bag_carry_hand(arm_swing: float, run: float, body_offset: Vector3) -> Vector3:
	var hand := Vector3(-0.245 - 0.02 * run, 0.60 + 0.05 * run, -0.03 + arm_swing * 0.05)
	return hand + body_offset * 0.5

func _follow_basis(current: Basis, target: Basis, delta: float, rate: float = 18.0) -> Basis:
	var a := current.orthonormalized().get_rotation_quaternion()
	var b := target.orthonormalized().get_rotation_quaternion()
	var angle := a.angle_to(b)
	return Basis(a.slerp(b, minf(1.0, delta * rate / maxf(angle, 0.0001))))

## Restrição de colisão do taco/machado com a cabeça, por cima da pose autorada
## (carregar, golpes e transições). Se o eixo da arma (cabo à ponta) chega a menos
## de HEAD_CLEARANCE do centro da cabeça, a arma gira em torno da mão o mínimo
## para passar por fora; se o ponto mais próximo é a própria mão, a mão é afastada.
## A cabeça segue inclinação, passo e agachamento do golpe e o balanço do passo.
## Medido em 2026-10-06: a pose de ombro da V1 já encostava (taco 0,6 cm de folga,
## machado 0,7 cm dentro) e as preparações passavam até 11 cm por dentro.
func _clear_head(id: String, hand: Vector3, basis: Basis, body: Dictionary, body_offset: Vector3, head_clearance: float) -> Dictionary:
	var lean := float(body.get("lean", 0.0))
	var head := HEAD_CENTER + body_offset + Vector3(0, -float(body.get("dip", 0.0)) - HEAD_ABOVE_SPINE * (1.0 - cos(lean)), -float(body.get("step", 0.0)) - HEAD_ABOVE_SPINE * sin(lean))
	var clearance: float = head_clearance + float(WEAPON_RADIUS.get(id, 0.04))
	var grip: Vector3 = DATA.GRIPS.get(id, Vector3.ZERO)
	for iteration in 3:
		var near := hand + basis * (Vector3(0, 0, 0.17) - grip)
		var far := hand + basis * (Vector3(0, 0, -0.50) - grip)
		var closest := Geometry3D.get_closest_point_to_segment(head, near, far)
		var away := closest - head
		# Correção suave (contínua na posição e na velocidade): começa CLEAR_SOFT
		# antes do limite e garante folga ≥ clearance + CLEAR_SOFT/2. Um degrau
		# liga/desliga girava a arma 50°/quadro na entrada da zona.
		var depth := (clearance + CLEAR_SOFT - away.length()) / CLEAR_SOFT
		if depth <= 0.0: break
		var deficit := CLEAR_SOFT * (depth * depth * 0.5 if depth < 1.0 else depth - 0.5)
		var push := away.normalized() if away.length_squared() > 0.000001 else Vector3.RIGHT
		var lever := closest - hand
		# Ponto perto da mão: afasta a mão; longe: gira a arma em torno dela. Mistura
		# contínua — escolher um ou outro por limiar alternava entre quadros e o
		# antebraço de apoio saltava 38°.
		var move_hand := 1.0 - smoothstep(0.04, 0.10, lever.length())
		hand += push * deficit * move_hand
		var axis := lever.cross(push)
		if axis.length_squared() > 0.000001 and move_hand < 1.0:
			basis = Basis(axis.normalized(), atan2(deficit * (1.0 - move_hand), lever.length())) * basis
	return {"hand": hand, "basis": basis.orthonormalized()}

## Guarda de punhos (soco e soqueira) nos canais de `MeleeMoveset`.
func _punch_rest() -> Dictionary:
	return {"r": MOVES.GUARD_RIGHT, "l": MOVES.GUARD_LEFT, "rb": Vector3.ZERO, "lb": Vector3.ZERO,
		"rr": MOVES.GUARD_ROLL, "lr": MOVES.GUARD_ROLL,
		"rp": MOVES.POLE_RIGHT, "lp": MOVES.POLE_LEFT,
		"torso": -0.12, "hip": -0.04, "lean": 0.0, "dip": 0.0, "step": 0.0}

## Carregamento no ombro convertido para os canais de golpe: direção da cabeça
## e normal do plano saem da própria base (inversa de `swing_basis`).
func _swing_rest(id: String, carry: Dictionary) -> Dictionary:
	var basis: Basis = carry.basis
	if id == "axe": basis = basis * Basis(Vector3.BACK, PI * 0.5)
	return {"r": carry.hand, "d": -basis.z, "k": basis.x,
		"rp": Vector3(1.10, -1.5, -1.35), "lp": Vector3(-1.10, -1.5, -1.35),
		"torso": float(carry.torso), "hip": float(carry.torso) * 0.35, "lean": 0.0, "dip": 0.0, "step": 0.0}

## Última pose de golpe/guarda: um golpe novo parte dela, sem salto no encadeamento.
func _remember(id: String, channels: Dictionary) -> void:
	_melee_now = channels
	_melee_now_id = id

## Ombro (origem do osso Arm) no espaço V1 do Actor, depois da protração da
## clavícula e do giro de postura que `Actor._apply_combat_weapon_pose` aplica.
func _shoulder(side: String, yaw: float) -> Vector3:
	var clavicle: Vector3 = SK_CLAVICLE[side]
	var arm: Vector3 = clavicle + Basis(Vector3.UP, 0.20 if side == "Right" else -0.20) * (SK_ARM[side] - clavicle)
	arm = SK_SPINE + Basis(Vector3.UP, yaw) * (arm - SK_SPINE)
	return Vector3(-arm.x, arm.y, -arm.z) * SKELETON_SCALE / V1_TO_V2

## Bolso do ombro direito (onde a coronha encosta), no espaço V1 do Actor: à frente
## da articulação na direção do peito girado, um pouco para dentro e para baixo.
## Com a arma inclinada (cano baixo, arma girada na recarga) o bico da coronha gira
## para trás, para dentro do peito: o bolso avança na proporção da inclinação.
func _stock_pocket(yaw: float, gun_basis: Basis = Basis.IDENTITY, id := "", low_ready := 0.0) -> Vector3:
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var tilt := sqrt(maxf(0.0, 1.0 - pow(clampf((gun_basis * Vector3.UP).normalized().y, -1.0, 1.0), 2.0)))
	var shift: Vector3 = (STOCK_POCKET_SHIFT.get(id, Vector3.ZERO) as Vector3).lerp(STOCK_POCKET_SHIFT_READY.get(id, Vector3.ZERO), low_ready)
	var pocket: Vector3 = STOCK_POCKET + shift
	return _shoulder("Right", yaw) + forward * (pocket.z + STOCK_TOE * tilt) + right * pocket.x + Vector3(0, pocket.y, 0)

## Ponto de apoio da mão esquerda (espaço do modelo, relativo à empunhadura) que o
## braço esquerdo alcança: desliza do guarda-mão em direção ao receptor até caber.
func _reachable_support(id: String, hand: Vector3, basis: Basis, left_shoulder: Vector3) -> Vector3:
	var support: Vector3 = DATA.SUPPORT_GRIPS[id] - DATA.GRIPS[id]
	var back := support
	back.z = maxf(support.z, float(SUPPORT_MIN_REACH_Z_BY_ID.get(id, SUPPORT_MIN_REACH_Z)))
	if left_shoulder.distance_to(hand + basis * support) <= LEFT_PALM_REACH: return support
	var low := 0.0
	var high := 1.0
	for i in 10:
		var mid := (low + high) * 0.5
		if left_shoulder.distance_to(hand + basis * support.lerp(back, mid)) > LEFT_PALM_REACH: low = mid
		else: high = mid
	return support.lerp(back, high)

## Carregar de taco/machado: mão direita à frente do peito, à direita, e a arma
## deitada sobre o ombro direito com a cabeça para trás, como o GTA carrega o taco.
## A pose de ombro da V1 segurava com as duas mãos cruzando os braços na frente do
## peito, e o cabo entrava 5–6 cm no tronco (medido em 2026-10-06).
func _shoulder_carry(id: String, gait_phase: float, movement: float, running: float, body_offset: Vector3) -> Dictionary:
	var hand := CARRY_HAND
	var basis := MOVES.swing_basis(id, CARRY_HEAD, Vector3.RIGHT)
	if movement > 0.0:
		# Balança em torno do ombro com o passo, como a arma pesada da V1.
		var sway := _basis(Vector3(sin(gait_phase * 2.0 - 0.35) * lerpf(0.035, 0.065, running), cos(gait_phase) * lerpf(0.018, 0.035, running), sin(gait_phase) * lerpf(0.015, 0.030, running)) * movement)
		hand = MELEE_SHOULDER + sway * (hand - MELEE_SHOULDER)
		basis = sway * basis
	return {"hand": hand + body_offset, "basis": basis, "support_weight": 0.0, "torso": 0.0}

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
	var accents := {"roll": 0.0, "pitch": 0.0, "kick": Vector3.ZERO, "left": Vector3.ZERO}
	match id:
		"pistol":
			var magazine_well := Vector3(-0.01, 0.89, -0.22)
			var waist_magazine := Vector3(-0.16, 0.78, -0.02)
			var fetch := smoothstep(0.09, 0.22, t) * (1.0 - smoothstep(0.30, 0.47, t))
			left = magazine_well.lerp(waist_magazine, fetch)
			var rack := smoothstep(0.56, 0.65, t) * (1.0 - smoothstep(0.80, 0.89, t))
			left = left.lerp(Vector3(0.06, 0.98, -0.25 + _rack(t, 0.66, 0.81) * 0.07), rack)
			accents = _magazine_accents(t, 0.09, 0.45, 0.66 + 0.15 * RACK_PULL)
		"smg", "ak47", "m4a1":
			var fetch := smoothstep(0.09, 0.22, t) * (1.0 - smoothstep(0.30, 0.47, t))
			left = insert.lerp(belt, fetch)
			var rack := smoothstep(0.56, 0.65, t) * (1.0 - smoothstep(0.80, 0.89, t))
			left = left.lerp(Vector3(0.07, 0.96, -0.20 + _rack(t, 0.66, 0.81) * 0.09), rack)
			accents = _magazine_accents(t, 0.09, 0.45, 0.66 + 0.15 * RACK_PULL)
			if id in ["ak47", "m4a1"]:
				hand.x = 0.09
				tilt.z = -0.52
			if id == "smg": tilt.z = SMG_RELOAD_ROLL
		"magnum":
			# Revólver, não escopeta: antes caía no caso da 12 e ia duas vezes ao cinto
			# como quem enfia cartucho no tubo. Aqui: tambor para a esquerda, cano para
			# cima para ejetar, UMA ida ao cinto pelo carregador rápido, cano para baixo
			# para encaixar, fecha. A abertura do tambor é de `Gameplay._update_weapon_parts`.
			var eject := smoothstep(0.08, 0.20, t) * (1.0 - smoothstep(0.30, 0.40, t))
			var engine_load_value := smoothstep(0.52, 0.62, t) * (1.0 - smoothstep(0.78, 0.88, t))
			# No encaixe o revólver vem para junto do peito, quase na horizontal: cano
			# para baixo e à frente com as duas mãos lia como arma longa.
			hand = Vector3(0.06, 0.92, -0.17).lerp(Vector3(0.02, 0.97, -0.08), engine_load_value)
			tilt = Vector3(0.85 * eject - 0.12 * engine_load_value, -0.10, -0.80 * smoothstep(0.04, 0.14, t) * (1.0 - smoothstep(0.80, 0.92, t)))
			# Palma no tambor aberto (lado esquerdo do receptor), em espaço da arma.
			var cylinder := hand + Basis.from_euler(tilt) * Vector3(-0.075, 0.06, -0.03)
			var fetch := smoothstep(0.32, 0.44, t) * (1.0 - smoothstep(0.46, 0.58, t))
			left = cylinder.lerp(belt, fetch)
			# Fecha o tambor com um golpe de pulso (o "flick" de cinema), no mesmo
			# instante em que `Gameplay._update_weapon_parts` recolhe o tambor.
			var flick := _pulse(t, 0.80, 0.08)
			accents = {"roll": 0.30 * flick, "pitch": 0.06 * flick, "kick": Vector3(0.012, 0.01, 0) * flick, "left": Vector3.ZERO}
		"shotgun", "sawed_off", "hunting_rifle":
			hand = Vector3(0.10, 0.87, -0.15)
			tilt = Vector3(0.05, -0.12, -0.62)
			insert = Vector3(-0.035, 0.84, -0.20)
			var load_motion := maxf(_stroke(t, 0.12, 0.35), _stroke(t, 0.39, 0.66))
			left = insert.lerp(belt, load_motion)
			if id == "shotgun":
				pump = _rack(t, 0.77, 0.94) * 0.09
				# Telha volta à frente com estalo: a arma pula para a frente.
				var slam := _pulse(t, 0.77 + 0.17 * RACK_PULL, 0.06)
				accents = {"roll": 0.0, "pitch": 0.07 * slam, "kick": Vector3(0, 0.008, -0.018) * slam, "left": Vector3.ZERO}
				var grab := smoothstep(0.68, 0.77, t)
				var basis := Basis.from_euler(tilt)
				left = left.lerp(hand + basis * (DATA.SUPPORT_GRIPS.shotgun - DATA.GRIPS.shotgun + Vector3(0, 0, pump)), grab)
			elif id == "hunting_rifle":
				hand = Vector3(0.15, 0.87, -0.30)
				left = left.lerp(Vector3(0.06, 0.94, -0.13), smoothstep(0.68, 0.79, t))
		"rpg":
			# Tubo atravessado à frente do peito, boca subindo para a esquerda (ao alcance
			# da mão esquerda, que traz o foguete do cinto e o assenta na boca por cima) e
			# mão direita na empunhadura à altura da cintura. Pose achada por busca com o
			# alcance real dos braços (~0,41 m): inclinado contra o peito (versão
			# anterior) o tubo entrava 5 cm no tronco, e em pé à frente do corpo a mão
			# ficaria a 0,76 m do ombro.
			var stand := Basis(Vector3.UP, 0.9) * Basis(Vector3.RIGHT, 0.7) * Basis(Vector3.BACK, -0.3)
			var rpg_hand := Vector3(0.08, 0.88, -0.14)
			var mouth := rpg_hand + stand * (RPG_MUZZLE - DATA.GRIPS.rpg)
			var axis := stand * Vector3.FORWARD
			var tube := rpg_hand + stand * (DATA.SUPPORT_GRIPS.rpg - DATA.GRIPS.rpg)
			# Linha do tempo do foguete (Gameplay o põe na palma esquerda entre a pega no
			# cinto e o encaixe): solta o tubo, busca no cinto, traz à frente da boca,
			# empurra para dentro e volta ao tubo.
			left = tube.lerp(belt, smoothstep(0.08, 0.24, t))
			left = left.lerp(mouth + axis * 0.22, smoothstep(0.30, 0.48, t))
			left = left.lerp(mouth + axis * RPG_ROCKET_CENTER, smoothstep(RPG_ROCKET_SEAT.x, RPG_ROCKET_SEAT.y, t))
			left = left.lerp(tube, smoothstep(0.66, 0.80, t))
			# Volta ao ombro mais longa que a das outras armas (0,80–1,0): em 0,12 da
			# recarga o tubo subia varrendo o antebraço direito.
			weight = smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.80, 1.0, t))
			return {"hand": rpg_hand, "left": left, "basis": stand, "weight": weight, "pump": 0.0, "kick": Vector3.ZERO}
		"flamethrower":
			tilt = Vector3(-0.18, 0.0, -0.43)
			left = Vector3(-0.06, 0.83, -0.17) + Vector3(sin(t * TAU * 2.0) * 0.035, cos(t * TAU * 2.0) * 0.025, 0)
		"grenade":
			hand = belt.lerp(Vector3(0.18, 0.92, -0.13), smoothstep(0.2, 0.82, t))
			left = Vector3(-0.17, 0.76, -0.05)
	# Manipula a arma à frente da jaqueta; a mão livre mantém o alcance do cinto
	# enquanto os alvos de inserção acompanham o receptor.
	tilt.y = 0.55
	if id in LONG_GUNS:
		# Coronha no ombro (`update`): cano para a frente e um pouco para baixo, girado
		# sobre o próprio eixo para mostrar o encaixe. Virado para dentro (0,55) a
		# arma deitava sobre o peito a partir do ombro.
		tilt.y = 0.06
		tilt.x -= 0.12
	tilt.x += float(accents.pitch)
	tilt.z += float(accents.roll)
	left += accents.left
	var clearance_offset := Vector3(0.10, 0, -0.14)
	hand += clearance_offset
	left += clearance_offset * clampf(left.distance_to(belt) / 0.15, 0.0, 1.0)
	if id == "grenade":
		hand = Vector3(0.25, lerpf(0.72, 0.94, smoothstep(0.2, 0.82, t)), -0.16)
	return {"hand": hand, "left": left, "basis": Basis.from_euler(tilt), "weight": weight, "pump": pump, "kick": (accents.kick as Vector3) * weight}

func _stroke(t: float, start: float, finish: float) -> float:
	return sin(clampf((t - start) / maxf(finish - start, 0.001), 0.0, 1.0) * PI)

## Ferrolho/telha: puxa com a mão (curva suave até RACK_PULL do trecho) e a mola
## devolve de uma vez. O seno simétrico de `_stroke` lia como empurrar devagar.
func _rack(t: float, start: float, finish: float) -> float:
	var x := clampf((t - start) / maxf(finish - start, 0.001), 0.0, 1.0)
	if x <= RACK_PULL: return sin(x / RACK_PULL * PI * 0.5)
	return 1.0 - smoothstep(RACK_PULL, 1.0, x)

## Impulso curto: sobe em 20% da janela e decai em quadrático (tranco, não onda).
func _pulse(t: float, at: float, width: float) -> float:
	var x := (t - at) / maxf(width, 0.001)
	if x < 0.0 or x > 1.0: return 0.0
	return x / 0.2 if x < 0.2 else pow((1.0 - x) / 0.8, 2.0)

## Acentos de recarga com carregador, sobre os MESMOS instantes do áudio:
## soltar o vazio (a arma tomba para o lado para o carregador cair), encaixar o
## novo com um tapa da palma (a arma pula) e o retorno do ferrolho.
func _magazine_accents(t: float, release: float, seat: float, slam: float) -> Dictionary:
	var flick := _pulse(t, release, 0.10)
	var slap := _pulse(t, seat, 0.07)
	var snap := _pulse(t, slam, 0.06)
	return {
		"roll": -0.28 * flick,
		"pitch": 0.10 * flick + 0.12 * slap + 0.05 * snap,
		"kick": Vector3(0, 0.014, 0) * slap + Vector3(0, 0.006, -0.012) * snap + Vector3(-0.01, 0.012, 0) * flick,
		"left": Vector3(0, 0.035, 0) * slap,
	}

func _basis(angles: Vector3) -> Basis:
	return Basis(Vector3.UP, angles.y) * Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.BACK, angles.z)
