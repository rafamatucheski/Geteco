extends RefCounted
## Katana na mão do Dante fora dos clipes do Mixamo: como ele a carrega parado, andando e correndo, e os
## cortes procedurais de reserva (só quando falta a biblioteca da greatsword).
##
## Carregar (pedido de 19/10/2026: "segura e corre como se estivesse segurando um graveto para frente"):
## fora do golpe a lâmina fica sempre para cima, nunca apontada para a frente.
## - Parado: as duas mãos no cabo, à direita do peito, lâmina em pé ao lado do rosto (hassō baixo), com o
##   tronco um pouco de lado e a respiração.
## - Andando: só a direita; punho à frente do peito com o cotovelo junto ao corpo, lâmina para cima e um
##   pouco para fora do ombro direito. A esquerda solta e balança com o passo.
## - Correndo: a lâmina vai para trás e para fora por cima do ombro, a mão acompanha o vaivém do braço e o
##   tronco inclina para a frente.
## - Em guarda (mirando, logo depois de um golpe ou no RAGE): anda com as duas mãos no cabo; correr solta a
##   esquerda de novo.
## A ponta tem inércia: arrancar a deita para trás, frear a joga um pouco à frente e virar a deixa para
## fora da curva, sempre voltando com mola.
##
## Carregar usa o espaço V2 do Actor (+X direita, −Z frente, Y para cima), medido no esqueleto do Dante
## (tools/capture_katana_locomotion.gd): ombro direito em (0,18; 1,35; 0,02), palma alcança ~0,47 m do
## ombro, centro da cabeça em ~(0; 1,56; −0,05) com raio de 0,14 m (cabelo).
## Cortes de reserva: two-handed vertical, diagonal and rising cuts, with controlled recovery.
## Reference: https://www.auskf.org/department/iaido/iaido-judging-points
## Their keys use V1 rig coordinates; hands are converted to Dante's current scale.
const MOVES = preload("res://gameplay/MeleeMoveset.gd")
const V1_TO_V2 := 1.03 / 0.82
const CONTACT := [0.32, 0.32, 0.32]
const CUTS := [
	{"end":0.76,"keys":[
		{"t":0.21,"r":Vector3(0.02,1.36,-0.20),"d":Vector3(0,0.9,0.3),"k":Vector3.RIGHT,"hip":-0.08,"dip":0.02,"ease":"inout"},
		{"t":0.32,"r":Vector3(0.02,1.02,-0.40),"d":Vector3(0,0.05,-1),"hip":0.12,"lean":0.10,"step":0.045,"ease":"in"},
		{"t":0.46,"r":Vector3(0.02,0.82,-0.33),"d":Vector3(0,-0.32,-0.95),"dip":0.035,"ease":"out"}
	]},
	{"end":0.76,"keys":[
		{"t":0.21,"r":Vector3(0.13,1.29,-0.22),"d":Vector3(0.6,0.8,0.05),"k":Vector3(0.8,-0.6,0),"torso":-0.30,"hip":-0.16,"dip":0.02,"ease":"inout"},
		{"t":0.32,"r":Vector3(0.02,1.02,-0.40),"d":Vector3(-0.12,0.05,-1),"torso":0.16,"hip":0.20,"lean":0.09,"step":0.045,"ease":"in"},
		{"t":0.46,"r":Vector3(-0.12,0.84,-0.32),"d":Vector3(-0.65,-0.55,-0.5),"torso":0.32,"hip":0.22,"dip":0.025,"ease":"out"},
	]},
	{"end":0.76,"keys":[
		{"t":0.21,"r":Vector3(0.17,0.79,-0.26),"d":Vector3(0.45,-0.72,-0.5),"k":Vector3(1,0,0),"torso":-0.22,"hip":-0.15,"dip":0.03,"ease":"inout"},
		{"t":0.32,"r":Vector3(0.04,1.00,-0.40),"d":Vector3(0,0.15,-1),"k":Vector3(1,0,0),"torso":0.15,"hip":0.18,"step":0.04,"lean":0.07,"ease":"in"},
		{"t":0.46,"r":Vector3(-0.10,1.18,-0.29),"d":Vector3(-0.6,0.7,-0.3),"k":Vector3(1,0,0),"torso":0.32,"ease":"out"},
	]},
]

## Poses de carregar: palma direita, direção da lâmina (do cabo à ponta), giro do tronco e polos dos
## cotovelos. Parado/em guarda as mãos ficam perto do meio: com a direita mais à direita a palma esquerda
## passava do alcance (0,51 m do ombro esquerdo) e o solver puxava a espada para o centro.
## A câmera do jogo fica atrás e acima (45°): lâmina deitada para trás aponta para ela e some. Medido no
## jogo: correndo com a ponta 45° para trás só ~19% do comprimento aparecia na tela. Por isso a lâmina
## inclina mais para FORA (à direita do Dante) do que para trás; de trás ela fica uma diagonal ao lado da
## cabeça (≥ ~50% do comprimento na tela em todos os estados).
const GUARD_HAND := Vector3(0.10, 1.24, -0.25)
const GUARD_BLADE := Vector3(0.20, 1.0, 0.12)
const GUARD_TORSO := -0.18
const WALK_HAND := Vector3(0.24, 1.08, -0.20)
const WALK_BLADE := Vector3(0.36, 1.0, 0.18)
const RUN_HAND := Vector3(0.25, 1.05, -0.18)
const RUN_BLADE := Vector3(0.50, 0.95, 0.40)
## Fio para a frente (no carregar, o dorso da lâmina fica do lado do ombro).
const EDGE := Vector3(0, 0, -1)
const GUARD_RIGHT_POLE := Vector3(0.8, -1.5, 0.0)
const GUARD_LEFT_POLE := Vector3(-0.5, -1.5, -0.5)
const CARRY_RIGHT_POLE := Vector3(0.6, -1.5, 0.5)
## Mão esquerda no cabo: 14 cm atrás da direita, junto ao pomo.
const SUPPORT := Vector3(0, 0, 0.14)
## Depois de um golpe, ainda anda em guarda por este tempo (s).
const READY_SECONDS := 2.5
## Inércia da ponta: inclinação (rad) por m/s² da velocidade suavizada, teto e mola.
const LAG_PER_ACCEL := 0.012
const LAG_MAX := 0.22
const LAG_STIFFNESS := 120.0
const LAG_DAMPING := 14.0
## Nas curvas: rolagem (rad) por rad/s de giro do corpo, e teto. O corpo gira a até ~40 rad/s no
## primeiro quadro de uma meia-volta (Actor: lerp_angle a 14/s), daí o teto baixo.
const TURN_LAG_PER_RATE := 0.012
const TURN_LAG_MAX := 0.15

var _move := 0.0
var _run := 0.0
var _hands := 1.0
var _clock := 0.0
var _smooth_speed := 0.0
var _lag := 0.0
var _lag_velocity := 0.0
var _yaw := NAN
var _turn_lag := 0.0
var _turn_lag_velocity := 0.0

## `speed` é a velocidade real no chão (m/s); `body_bob` o sobe-e-desce do quadril (Actor.combat_rig_info);
## `yaw` o rumo do corpo (Actor.visual.rotation.y); `ready` pede as duas mãos andando. `combo`/`age` só
## valem para os cortes de reserva.
func update(delta: float, speed: float, phase: float, body_bob: float, yaw: float, ready: bool, combo: int, age: float) -> Dictionary:
	var moving := speed > 0.12
	# Mesmas taxas do Actor (LOCOMOTION_BLEND_RATE, RUN_BLEND_RATE): a pose muda junto com a passada.
	_move = move_toward(_move, 1.0 if moving else 0.0, delta * 7.0)
	_run = move_toward(_run, smoothstep(3.8, 6.0, speed) if moving else 0.0, delta * 4.5)
	_hands = move_toward(_hands, (1.0 - _run) if ready else (1.0 - _move), delta * 6.0)
	_clock += delta
	var previous_speed := _smooth_speed
	_smooth_speed = lerpf(_smooth_speed, speed, 1.0 - exp(-6.0 * delta))
	var accel := (_smooth_speed - previous_speed) / maxf(delta, 0.0001)
	var lag_target := clampf(accel * LAG_PER_ACCEL, -LAG_MAX, LAG_MAX)
	_lag_velocity += (LAG_STIFFNESS * (lag_target - _lag) - LAG_DAMPING * _lag_velocity) * delta
	_lag += _lag_velocity * delta
	# Virando à esquerda (yaw crescendo) a ponta fica à direita, por fora da curva.
	var turn_rate := wrapf(yaw - _yaw, -PI, PI) / maxf(delta, 0.0001) if not is_nan(_yaw) else 0.0
	_yaw = yaw
	var turn_target := clampf(turn_rate * TURN_LAG_PER_RATE, -TURN_LAG_MAX, TURN_LAG_MAX)
	_turn_lag_velocity += (LAG_STIFFNESS * (turn_target - _turn_lag) - LAG_DAMPING * _turn_lag_velocity) * delta
	_turn_lag += _turn_lag_velocity * delta

	var carry_hand := WALK_HAND.lerp(RUN_HAND, _run)
	var carry_blade := WALK_BLADE.normalized().slerp(RUN_BLADE.normalized(), _run)
	var hand := GUARD_HAND.lerp(carry_hand, 1.0 - _hands)
	var blade := GUARD_BLADE.normalized().slerp(carry_blade, 1.0 - _hands)
	# Vaivém do passo: a mão direita vai à frente quando a esquerda (solta, no clipe) vai para trás; com as
	# duas mãos no cabo só sobra o sobe-e-desce. A lâmina balança em torno do punho, com atraso.
	var arm_swing := cos(phase * TAU + PI * 0.175 * _run) * _move
	var one_hand := 1.0 - _hands
	hand.z -= arm_swing * lerpf(0.025, 0.05, _run) * one_hand
	hand.y += body_bob + sin(phase * TAU * 2.0) * lerpf(0.006, 0.014, _run) * _move
	var sway_pitch := sin(phase * TAU * 2.0 - 0.35) * lerpf(0.03, 0.06, _run) * _move
	var sway_roll := sin(phase * TAU) * lerpf(0.02, 0.035, _run) * _move
	# Parado: respiração e um vaivém lento da ponta.
	var still := 1.0 - _move
	var breath := sin(_clock * 1.65)
	hand.y += breath * 0.006 * still
	sway_pitch += sin(_clock * 0.7) * 0.02 * still
	blade = Basis(Vector3.RIGHT, sway_pitch + _lag) * Basis(Vector3.FORWARD, sway_roll + _turn_lag) * blade
	var torso := GUARD_TORSO * _hands * (1.0 - _move * 0.5) + arm_swing * lerpf(0.05, 0.08, _run) * one_hand
	var lean := _move * 0.04 + _run * 0.08 + breath * 0.008 * still

	var active := combo >= 0 and age < 0.76
	var basis: Basis
	var hip := 0.0
	var dip := 0.0
	var step := 0.0
	if active:
		# Corte de reserva: duas mãos de uma vez, partindo do carregar atual e voltando para ele.
		_hands = 1.0
		var rest := {"r":hand / V1_TO_V2,"d":blade,"k":EDGE,"torso":torso,"hip":0.0,"lean":lean,"dip":0.0,"step":0.0}
		var channels: Dictionary = MOVES.sample("katana",CUTS[combo%3],age,rest,rest)
		basis = MOVES.swing_basis("katana",channels.d,channels.k)
		hand = channels.r * V1_TO_V2
		torso = channels.torso
		lean = channels.lean
		hip = channels.hip
		dip = channels.dip
		step = channels.step
	else:
		basis = MOVES.swing_basis("katana",blade,EDGE)
	var palm_basis := basis * Basis(Vector3.RIGHT, PI * 0.5)
	var right_pole := GUARD_RIGHT_POLE.lerp(CARRY_RIGHT_POLE, 1.0 - _hands)
	# A esquerda entra e sai do cabo misturando com o braço do clipe (left_weight); só trava no cabo
	# (support_locked, que ignora a mistura) com as duas mãos inteiras.
	return {"visible":true,"armed":true,"basis":basis,"right":hand,"left":hand+basis*SUPPORT,
		"right_basis":palm_basis,"left_basis":palm_basis,"grip_solver":true,"forearm_twist_share":0.65,"arm_rate":30.0 if active else 18.0,
		"gun_origin":hand-basis*Vector3(0,0,0.04),"weapon_scale":1.0,"right_solve":true,"left_solve":_hands > 0.001,
		"right_grip":true,"left_grip":_hands > 0.5,"grip_as_fist":true,"support_locked":_hands >= 0.999,"support_weight":_hands,
		"left_weight":_hands,"support_point":Vector3(0,0,0.18),"long_weapon":true,
		"right_pole":right_pole,"left_pole":GUARD_LEFT_POLE,
		"torso_yaw":torso,"hip_yaw":hip,"lean":lean,
		"dip":dip,"step":step,"melee_action":active}
