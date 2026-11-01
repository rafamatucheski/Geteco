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
##
## Dividido em 01/11 (Onda 3): constantes em WeaponPoseData; tronco/postura em WeaponRigStance,
## pegada por arma em WeaponRigGrips e recarga em WeaponRigReload, todos estáticos (o rig é
## RefCounted; auxiliar com `var g` faria ciclo de referência). O estado continua aqui, onde Actor,
## Gameplay e os testes o leem (action_age, weapon_id, _right/_left, _stance_yaw...).

const DATA = preload("res://gameplay/WeaponPoseData.gd")
const SAWED = preload("res://gameplay/SawedOffPresentation.gd")
const MOVES = preload("res://gameplay/MeleeMoveset.gd")
const STANCE = preload("res://gameplay/WeaponRigStance.gd")
const GRIPS = preload("res://gameplay/WeaponRigGrips.gd")
const RELOAD = preload("res://gameplay/WeaponRigReload.gd")
## Lidas de fora (PoliceModel, Gameplay, GameplayWeaponVisuals, GameplayCombatSound, testes e capturas) pelo
## script do rig; o valor mora em WeaponPoseData com as outras constantes de pose.
const V1_TO_V2 := DATA.V1_TO_V2
const FIREARMS := DATA.FIREARMS
const GRENADE_RELEASE := DATA.GRENADE_RELEASE
const GRENADE_RECOVERY := DATA.GRENADE_RECOVERY
const MELEE_CONTACT := DATA.MELEE_CONTACT
const HIT_STOP := DATA.HIT_STOP
const STRIKE_ARM_RATE := DATA.STRIKE_ARM_RATE
const RACK_PULL := DATA.RACK_PULL
const HEAD_CLEARANCE_CARRY := DATA.HEAD_CLEARANCE_CARRY
const RPG_ROCKET_GRAB := DATA.RPG_ROCKET_GRAB
const RPG_ROCKET_SEAT := DATA.RPG_ROCKET_SEAT
const RPG_ROCKET_CENTER := DATA.RPG_ROCKET_CENTER
const RPG_ROCKET_SIDE := DATA.RPG_ROCKET_SIDE

var weapon_id := ""
var action_age := 10.0
var _attacked_id := ""
var recoil := 0.0
var equip_blend := 1.0
var punch_left := false
## Chaves de A/B para medição (nunca gravadas): desligam, em tempo de execução, o soco por clipe da UAL e o
## braço da soqueira seguindo o clipe de corrida, para comparar com o comportamento anterior sem trocar arquivos.
static var ab_punch_clip := true
static var ab_follow_clip := true
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
## Quadro em curso do update, passado de uma etapa para a seguinte (as locais do corpo antigo, que
## era uma função só de 476 linhas). Toda etapa grava antes de a seguinte ler, no mesmo quadro: nada
## aqui é estado entre quadros, e o reset não precisa limpar. Campos fixos em vez de dicionário para
## não alocar por quadro.
var _f_profile: Array = []
var _f_stopped := false
var _f_run := 0.0
var _f_arm_swing := 0.0
var _f_body_offset := Vector3.ZERO
var _f_in_move := false
var _f_clip_punch := false
var _f_follow_enabled := false
var _f_engaged := false
var _f_melee_pose: Dictionary = {}
var _f_swing: Dictionary = {}
var _f_melee_support_active := false
var _f_shouldered := false
var _f_punch: Dictionary = {}
var _f_right_shoulder := Vector3.ZERO
var _f_left_shoulder := Vector3.ZERO
var _f_hand := Vector3.ZERO
var _f_support := Vector3.ZERO
var _f_long_gun := false
var _f_gun_basis := Basis.IDENTITY
var _f_offhand_basis := Basis.IDENTITY
var _f_left_target := Vector3.ZERO
var _f_pump := 0.0
var _f_right_solve := false
var _f_left_solve := false
var _f_right_fist := false
var _f_left_fist := false
var _f_right_free := 0.0
var _f_left_free := 0.0
var _f_visible := false
var _f_wrist_right: Variant = null
var _f_wrist_left: Variant = null
var _f_stock_pin := Vector3.INF
var _f_stock_extra := Vector3.ZERO
var _f_reload_pump := 0.0
var _f_pump_stroke := 0.0
var _f_support_locked := false

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
	else:
		# Knife/katana own their poses; never inherit a heavy axe/bat finisher.
		_move = {}
		_melee_from = {}
		combo_step = 0
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
	hit_stop = float(DATA.HIT_STOP.get(id, 0.0)) + (DATA.HEAVY_HIT_STOP if heavy_attack() else 0.0)

## O golpe em curso é o pesado que fecha a sequência.
func heavy_attack() -> bool:
	return bool(_move.get("heavy", false)) and action_age < float(_move.get("end", 0.0)) * MOVES.scale(_attacked_id)

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
## e "loaded" (granada ainda na mão). "action_rate" acelera somente o relógio
## do golpe; não muda blends de locomoção/equipamento nem a pausa de impacto.
func update(id: String, delta: float, aiming: bool, reloading: bool, reload_progress: float, moving: bool, sprinting: bool, phase: float, rig: Dictionary = {}) -> Dictionary:
	reloading = reloading and id in DATA.FIREARMS
	# Etapas na ordem do corpo antigo (separado em 01/11). Cada uma lê dos campos `_f_*` o que as
	# anteriores deixaram neste quadro; as de tronco e pegada estão em WeaponRigStance/WeaponRigGrips.
	_advance(id, delta, aiming, moving, sprinting, phase, rig)
	STANCE.torso(self, id, delta)
	STANCE.weapon_carry(self, id, delta, sprinting)
	GRIPS.hand_grips(self, id, sprinting, rig)
	_firearm_hands(id, delta, reloading, reload_progress)
	_settle_hands(id, delta, reloading)
	return _pose_output(id, delta, reloading, reload_progress)

## Etapa 1 do update: troca de arma, relógios (saque, golpe, hit-stop, recuo), pesos de passo e
## guarda, e o taco/machado no ombro ou no golpe (com a folga da cabeça).
func _advance(id: String, delta: float, aiming: bool, moving: bool, sprinting: bool, phase: float, rig: Dictionary) -> void:
	if id != weapon_id:
		weapon_id = id
		_support_weight = 0.0
		equip_blend = 0.0
		recoil = 0.0
		if action_age != 0.0 or _attacked_id != id: action_age = 10.0
		_carry_yaw = 0.0
		if id in DATA.HANDGUNS: _right = Vector3(0.035, 0.96, -0.365)
		elif id in ["smg", "smg_compact", "smg_tactical"]: _right = Vector3(0.02, 0.93, -0.28)
	var p: Array = DATA.PROFILES.get(id, DATA.PROFILES.pistol)
	equip_blend = move_toward(equip_blend, 1.0, delta * 4.5)
	# Hit-stop: o golpe para no impacto; o resto do corpo (passo, respiração) segue.
	var stopped := hit_stop > 0.0
	if stopped: hit_stop = maxf(0.0, hit_stop - delta)
	else: action_age += delta * maxf(0.0, float(rig.get("action_rate", 1.0)))
	recoil *= exp(-float(p[3]) * delta)
	# Pesos suavizados de andar/correr com as mesmas taxas do Player V1.
	_move_weight = move_toward(_move_weight, 1.0 if moving else 0.0, delta * 7.0)
	_sprint_weight = move_toward(_sprint_weight, 1.0 if moving and sprinting else 0.0, delta * 4.5)
	var run := _sprint_weight
	var walk_clock := phase * TAU
	var arm_swing := cos(walk_clock + PI * 0.175 * run) * lerpf(0.32, 0.55, run) * _move_weight
	var body_offset := Vector3(0, float(rig.get("body_bob", 0.0)) / DATA.V1_TO_V2, 0)
	var move_end := float(_move.get("end", 0.0)) * MOVES.scale(id) if _attacked_id == id else 0.0
	var in_move := not MOVES.moves(id).is_empty() and action_age < move_end
	var clip_punch := bool(rig.get("clip_punch", false)) and id in ["fists", "knuckles"]
	var follow_enabled := ab_follow_clip
	var engaged := aiming or action_age < (0.90 if id == "fists" else 0.45) or in_move
	# Armas de duas mãos já são negadas com a mala; o resto usa uma mão só.
	bag_carry = bool(rig.get("bag_carry", false)) and id not in DATA.LONG_GUNS and id not in ["axe", "bat", "rpg", "flamethrower", "sawed_off"]
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
			var swing_basis := MOVES.swing_basis(id, swing.d, swing.k, _swing_x, DATA.BLADE_ROLL_RATE * delta)
			_swing_x = (swing_basis * (Basis(Vector3.BACK, PI * 0.5) if id == "axe" else Basis.IDENTITY)).x
			melee_pose = {"hand": swing.r, "basis": swing_basis, "support_weight": 1.0, "torso": swing.torso}
			_remember(id, swing)
		else:
			_remember(id, rest)
			_swing_x = (melee_pose.basis as Basis * (Basis(Vector3.BACK, PI * 0.5) if id == "axe" else Basis.IDENTITY)).x
		# Margem do golpe só em movimento (atraso do IK); carregando, a pose de ombro
		# da V1 fica quase intacta. Transição suave entre as duas.
		_clear_blend = move_toward(_clear_blend, 1.0 if in_move else 0.0, delta * 3.0)
		var cleared := _clear_head(id, melee_pose.hand, melee_pose.basis, swing, body_offset, lerpf(DATA.HEAD_CLEARANCE_CARRY, DATA.HEAD_CLEARANCE, _clear_blend))
		melee_pose.hand = cleared.hand
		melee_pose.basis = cleared.basis
	melee_support_weight = float(melee_pose.support_weight) if not melee_pose.is_empty() else 0.0
	if id in ["axe", "bat"]:
		# A mão esquerda vem ao cabo quando o golpe sai (a preparação dura 0,24 s) e
		# volta a balançar com o passo no carregar.
		_carry_support = move_toward(_carry_support, 1.0 if in_move else 0.0, delta * (9.0 if in_move else 4.0))
		melee_support_weight = _carry_support
	var melee_support_active := melee_support_weight > 0.995
	_f_profile = p
	_f_stopped = stopped
	_f_run = run
	_f_arm_swing = arm_swing
	_f_body_offset = body_offset
	_f_in_move = in_move
	_f_clip_punch = clip_punch
	_f_follow_enabled = follow_enabled
	_f_engaged = engaged
	_f_melee_pose = melee_pose
	_f_swing = swing
	_f_melee_support_active = melee_support_active

## Etapa 5 do update: recarga, mãos das armas de fogo, coronha presa ao ombro e a mão da mala.
func _firearm_hands(id: String, delta: float, reloading: bool, reload_progress: float) -> void:
	var hand: Vector3 = _f_hand
	var left_target: Vector3 = _f_left_target
	var gun_basis: Basis = _f_gun_basis
	var offhand_basis: Basis = _f_offhand_basis
	var support: Vector3 = _f_support
	var left_solve: bool = _f_left_solve
	var left_fist: bool = _f_left_fist
	var left_free: float = _f_left_free
	var wrist_left: Variant = _f_wrist_left
	var engaged: bool = _f_engaged
	var body_offset: Vector3 = _f_body_offset
	var arm_swing: float = _f_arm_swing
	var run: float = _f_run
	var right_shoulder: Vector3 = _f_right_shoulder
	var left_shoulder: Vector3 = _f_left_shoulder
	var pump: float = _f_pump
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
	if id in DATA.FIREARMS:
		# O ombro importado é mais estreito e a manga mais grossa que o boneco
		# procedural: estender à frente em vez de erguer o cotovelo.
		if id in DATA.HANDGUNS and not reloading:
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
			if id in DATA.LONG_GUNS and not engaged and not reloading:
				var carry_height := (right_shoulder.y + left_shoulder.y) * 0.5 - 0.17
				left_target.y += carry_height - hand.y
				hand.y = carry_height
			hand.z -= 0.080
			left_target.z -= 0.080
			if id == "flamethrower" and not reloading:
				hand = Vector3(0.09, 0.96 if engaged else 0.90, -0.28) + body_offset
				left_target = hand + gun_basis * support
			elif id == "rpg" and not reloading:
				# Tubo em cima do ombro direito, por fora da cabeça: o eixo do tubo fica
				# 8 cm (modelo) acima das empunhaduras e o raio é ~4 cm; com a mão em
				# x = 0,06 o tubo passava pelo queixo e pelo lado do pescoço.
				hand = DATA.RPG_SHOULDER + body_offset
				left_target = hand + gun_basis * support
			if reloading and left_target.z > -0.16: left_target.x = minf(left_target.x, -0.24)
			if reloading and id != "rpg":
				var reload_hand := (Vector3(0.06, 0.96, -0.34) if id in DATA.HANDGUNS else Vector3(0.0, 0.98, -0.36)) + body_offset
				if left_target.z < -0.16: left_target += reload_hand - hand
				hand = reload_hand
				# Tranco do encaixe/ferrolho: a arma pula na mão e a mão de apoio vai junto.
				hand += reload_kick
				if left_target.z < -0.16: left_target += reload_kick
				if id in DATA.LONG_GUNS:
					# A coronha fica no ombro e a arma inclina em torno dela. Com a mão no
					# meio do peito e o cano para dentro, a coronha entrava 10–14 cm no
					# lado direito do tronco.
					stock_pin = DATA.STOCK_ENDS[id] - DATA.GRIPS[id]
					stock_extra = reload_kick
					var shouldered_hand: Vector3 = _stock_pocket(_stance_yaw, gun_basis, id, _low_ready) + body_offset - gun_basis * stock_pin + stock_extra
					if left_target.z < -0.16: left_target += shouldered_hand - hand
					hand = shouldered_hand

	if id in DATA.LONG_GUNS and not reloading:
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
	_f_hand = hand
	_f_left_target = left_target
	_f_gun_basis = gun_basis
	_f_offhand_basis = offhand_basis
	_f_support = support
	_f_left_solve = left_solve
	_f_left_fist = left_fist
	_f_left_free = left_free
	_f_wrist_left = wrist_left
	_f_stock_pin = stock_pin
	_f_stock_extra = stock_extra
	_f_reload_pump = reload_pump

## Etapa 6 do update: suaviza base e mãos (`_right`/`_left`), tremor do impacto e peso do apoio.
func _settle_hands(id: String, delta: float, reloading: bool) -> void:
	var gun_basis: Basis = _f_gun_basis
	var offhand_basis: Basis = _f_offhand_basis
	var in_move: bool = _f_in_move
	var stock_pin: Vector3 = _f_stock_pin
	var stock_extra: Vector3 = _f_stock_extra
	var hand: Vector3 = _f_hand
	var left_target: Vector3 = _f_left_target
	var engaged: bool = _f_engaged
	var stopped: bool = _f_stopped
	var body_offset: Vector3 = _f_body_offset
	var support: Vector3 = _f_support
	var reload_pump: float = _f_reload_pump
	var pump: float = _f_pump
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
	if id in DATA.HANDGUNS and (engaged or reloading or equip_blend < 1.0):
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
	_f_gun_basis = gun_basis
	_f_offhand_basis = offhand_basis
	_f_pump_stroke = pump_stroke
	_f_support_locked = support_locked

## Etapa 7 do update: pegada dos dedos, pesos do solver, bases das palmas e o dicionário para o Actor.
func _pose_output(id: String, delta: float, reloading: bool, reload_progress: float) -> Dictionary:
	var p: Array = _f_profile
	var engaged: bool = _f_engaged
	var in_move: bool = _f_in_move
	var clip_punch: bool = _f_clip_punch
	var follow_enabled: bool = _f_follow_enabled
	var swing: Dictionary = _f_swing
	var melee_support_active: bool = _f_melee_support_active
	var shouldered: bool = _f_shouldered
	var punch: Dictionary = _f_punch
	var support: Vector3 = _f_support
	var long_gun: bool = _f_long_gun
	var gun_basis: Basis = _f_gun_basis
	var offhand_basis: Basis = _f_offhand_basis
	var right_solve: bool = _f_right_solve
	var left_solve: bool = _f_left_solve
	var right_fist: bool = _f_right_fist
	var left_fist: bool = _f_left_fist
	var right_free: float = _f_right_free
	var left_free: float = _f_left_free
	var visible: bool = _f_visible
	var wrist_right: Variant = _f_wrist_right
	var wrist_left: Variant = _f_wrist_left
	var stock_pin: Vector3 = _f_stock_pin
	var pump_stroke: float = _f_pump_stroke
	var support_locked: bool = _f_support_locked
	var left_grip := false
	if bag_carry: left_grip = true # dedos fechados na alça
	elif id in ["axe", "bat"]: left_grip = melee_support_active
	elif id in DATA.HANDGUNS: left_grip = engaged or reloading
	elif id not in ["fists", "knuckles", "knife", "grenade"]: left_grip = not reloading and DATA.SUPPORT_GRIPS.has(id)
	var right_grip := id != "fists" and not right_fist and not (id == "grenade" and not visible)
	_right_solve_weight = move_toward(_right_solve_weight, 1.0 if right_solve else 0.0, delta * 10.0)
	_left_solve_weight = move_toward(_left_solve_weight, 1.0 if left_solve or left_grip else 0.0, delta * 10.0)
	var cross := Basis(Vector3.RIGHT, PI * 0.5)
	var right_basis := gun_basis * (cross if id in DATA.CROSS_GRIP else Basis.IDENTITY)
	var left_basis := offhand_basis if id in ["fists", "knuckles"] or bag_carry else gun_basis * (cross if id in DATA.CROSS_GRIP or id in DATA.CROSS_GRIP_LEFT else Basis.IDENTITY)
	# Soqueira: a fileira de anéis segue o eixo Y da palma calibrada nos dois punhos.
	var model_basis := gun_basis * Basis(Vector3.BACK, PI * 0.5) if id == "knuckles" else gun_basis
	var scale := DATA.V1_TO_V2
	var grip: Vector3 = DATA.GRIPS.get(id, Vector3.ZERO)
	var body: Dictionary = punch if not punch.is_empty() else swing
	# Carregando no ombro: cotovelo direito pendendo ao lado do corpo. O polo de arma
	# longa (para fora e para a frente, pensado para fuzil apontado) abria o cotovelo
	# na altura do ombro e o cabo passava por baixo do braço.
	if body.is_empty() and id in ["axe", "bat"]: body = {"rp": DATA.CARRY_POLE}
	# Lança-foguetes: cotovelo direito para baixo, sob o tubo. Aberto para fora (polo de
	# arma longa) o tubo passava pelo cotovelo ao voltar da recarga para o ombro.
	if id == "rpg": body = {"rp": DATA.RPG_POLE}
	# Soqueira sem golpe nem guarda: cotovelos junto ao corpo, para baixo e para trás.
	if id == "knuckles" and not in_move and not engaged: body = {"rp": DATA.KNUCKLE_RUN_POLE, "lp": Vector3(-DATA.KNUCKLE_RUN_POLE.x, DATA.KNUCKLE_RUN_POLE.y, DATA.KNUCKLE_RUN_POLE.z)}
	if stock_pin != Vector3.INF: body = {"rp": DATA.STOCK_ELBOW}
	if reloading and id in DATA.LONG_GUNS:
		# Mão esquerda buscando cartucho/ferrolho junto ao receptor: com o polo de arma
		# longa o cotovelo esquerdo subia acima da mão ("braço de baixo para cima").
		body = body.duplicate()
		body["lp"] = DATA.RELOAD_LEFT_POLE
	# Arma longa aparece na mão quando o braço chega (~0,1 s de saque, como tirá-la das
	# costas): antes, presa à mão que ainda vinha da arma anterior, ela atravessava o
	# tronco 5–9 cm nos primeiros quadros (medido em 2026-10-06).
	if id in DATA.LONG_GUNS or id in ["rpg", "flamethrower"]: visible = visible and equip_blend >= float(DATA.EQUIP_SHOW_BY_ID.get(id, DATA.EQUIP_SHOW))
	# Pistola/magnum/cano serrado: 2 quadros de saque; no primeiro a mão ainda era o
	# punho fechado da arma anterior e a pistola aparecia dentro dela.
	if id in DATA.HANDGUNS or id == "sawed_off": visible = visible and equip_blend >= DATA.EQUIP_SHOW_HANDGUN
	var right_v2 := _right * scale
	return {
		"right": right_v2, "left": _left * scale,
		"basis": model_basis, "right_basis": right_basis, "left_basis": left_basis,
		"gun_origin": right_v2 - model_basis * grip * scale,
		"weapon_scale": scale,
		"break_open": SAWED.reload_open(reload_progress) if id == "sawed_off" and reloading else 0.0,
		"right_grip": right_grip, "left_grip": left_grip,
		"right_solve": _right_solve_weight > 0.0, "left_solve": _left_solve_weight > 0.0,
		"right_weight": minf(_right_solve_weight, _guard_weight) if id == "fists" else _right_solve_weight,
		"left_weight": minf(_left_solve_weight, melee_support_weight) if id in ["axe", "bat"] else (minf(_left_solve_weight, _guard_weight) if id == "fists" else _left_solve_weight),
		"right_fist": right_fist, "left_fist": left_fist,
		# Soqueira correndo: os punhos seguem a mão que o clipe de corrida já traz (balanço natural)
		# em vez do bombeio curto de `_knuckle_pose`, que lia como braço duro e "amebado".
		"follow_clip": 1.0 if clip_punch else (_move_weight if follow_enabled and id == "knuckles" and not in_move and not engaged else 0.0),
		# Soco por clipe da UAL: braços e corpo vêm do clipe; o giro procedural de quadril/tronco fica de fora.
		"clip_punch": clip_punch,
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
		"arm_rate": DATA.STRIKE_ARM_RATE if in_move else 18.0,
		"right_pole": body.get("rp", null), "left_pole": body.get("lp", null),
		"melee_action": in_move,
		# Fração do giro do tronco que a cabeça devolve (fuzil, lança-foguetes e
		# lança-chamas), proporcional ao giro: contínua ao subir/baixar a arma.
		"head_counter": minf(0.85, 0.85 * absf(_stance_yaw) / absf(DATA.STOCK_STANCE)) if shouldered or id == "flamethrower" else 0.0,
		"swing_trail": in_move and id in ["axe", "bat"] and action_age > float(MOVES.SWING_SCALE.get(id, 1.0)) * 0.26 and action_age < float(MOVES.SWING_SCALE.get(id, 1.0)) * 0.47,
		"combo_step": combo_step,
		"right_wrist_roll": wrist_right, "left_wrist_roll": wrist_left,
		"grip_as_fist": id in ["axe", "bat"],
		"forearm_twist_share": DATA.FOREARM_SHARE if id in ["axe", "bat"] else 0.0,
		"grip_solver": id in ["axe", "bat"],
		"pump": pump_stroke,
		"slide": (_rack(reload_progress, 0.77, 0.94) if id == "shotgun_auto" else _rack(reload_progress, 0.66, 0.81)) if id in ["pistol", "pistol_suppressed", "smg_compact", "smg_tactical", "shotgun_auto"] and reloading else clampf(recoil / maxf(float(p[2]), 0.001), 0.0, 1.0),
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
	var head := DATA.HEAD_CENTER + body_offset + Vector3(0, -float(body.get("dip", 0.0)) - DATA.HEAD_ABOVE_SPINE * (1.0 - cos(lean)), -float(body.get("step", 0.0)) - DATA.HEAD_ABOVE_SPINE * sin(lean))
	var clearance: float = head_clearance + float(DATA.WEAPON_RADIUS.get(id, 0.04))
	var grip: Vector3 = DATA.GRIPS.get(id, Vector3.ZERO)
	for iteration in 3:
		var near := hand + basis * (Vector3(0, 0, 0.17) - grip)
		var far := hand + basis * (Vector3(0, 0, -0.50) - grip)
		var closest := Geometry3D.get_closest_point_to_segment(head, near, far)
		var away := closest - head
		# Correção suave (contínua na posição e na velocidade): começa CLEAR_SOFT
		# antes do limite e garante folga ≥ clearance + CLEAR_SOFT/2. Um degrau
		# liga/desliga girava a arma 50°/quadro na entrada da zona.
		var depth := (clearance + DATA.CLEAR_SOFT - away.length()) / DATA.CLEAR_SOFT
		if depth <= 0.0: break
		var deficit := DATA.CLEAR_SOFT * (depth * depth * 0.5 if depth < 1.0 else depth - 0.5)
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

## Ombro, bolso da coronha e alcance do apoio moram em WeaponRigStance (documentação lá); as
## delegações ficam para as etapas do update aqui e para a recarga do lança-foguetes.
func _shoulder(side: String, yaw: float) -> Vector3: return STANCE._shoulder(side, yaw)
func _stock_pocket(yaw: float, gun_basis: Basis = Basis.IDENTITY, id := "", low_ready := 0.0) -> Vector3: return STANCE._stock_pocket(yaw, gun_basis, id, low_ready)
func _reachable_support(id: String, hand: Vector3, basis: Basis, left_shoulder: Vector3) -> Vector3: return STANCE._reachable_support(id, hand, basis, left_shoulder)

## Carregar de taco/machado: mão direita à frente do peito, à direita, e a arma
## deitada sobre o ombro direito com a cabeça para trás, como o GTA carrega o taco.
## A pose de ombro da V1 segurava com as duas mãos cruzando os braços na frente do
## peito, e o cabo entrava 5–6 cm no tronco (medido em 2026-10-06).
func _shoulder_carry(id: String, gait_phase: float, movement: float, running: float, body_offset: Vector3) -> Dictionary:
	var hand := DATA.CARRY_HAND
	var basis := MOVES.swing_basis(id, DATA.CARRY_HEAD, Vector3.RIGHT)
	if movement > 0.0:
		# Balança em torno do ombro com o passo, como a arma pesada da V1.
		var sway := _basis(Vector3(sin(gait_phase * 2.0 - 0.35) * lerpf(0.035, 0.065, running), cos(gait_phase) * lerpf(0.018, 0.035, running), sin(gait_phase) * lerpf(0.015, 0.030, running)) * movement)
		hand = DATA.MELEE_SHOULDER + sway * (hand - DATA.MELEE_SHOULDER)
		basis = sway * basis
	return {"hand": hand + body_offset, "basis": basis, "support_weight": 0.0, "torso": 0.0}

## Linha do tempo da recarga e curvas em WeaponRigReload; testes chamam reload_targets e _rack por aqui.
func reload_targets(id: String, progress: float) -> Dictionary: return RELOAD.reload_targets(self, id, progress)
func _rack(t: float, start: float, finish: float) -> float: return RELOAD._rack(t, start, finish)

func _basis(angles: Vector3) -> Basis:
	return Basis(Vector3.UP, angles.y) * Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.BACK, angles.z)
