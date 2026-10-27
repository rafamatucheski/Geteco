extends Node
## Hidráulica de lowrider: cada canto da carroceria sobe e desce sozinho (frente, traseira,
## esquerda, direita), a carroceria pula e, no pulo alto, leva as rodas junto.
## Só apresentação: a colisão e a física do carro não mudam. Move-se o `visual` do Vehicle e os
## pivôs das rodas recebem a transformação inversa, então portas (dobradiças dentro do visual),
## pintura, amassados e lanternas acompanham a carroceria sem reparentear nada.
## Fica parado (sem _physics_process) enquanto a carroceria está na altura assada.
const FIREFLY := preload("res://audio/FireflyBank.gd")
const AIR_DUMP := preload("res://audio/vehicle_fx/air_brake.wav")
## Curso de cada canto acima da altura assada (a mais baixa), em metros.
const MAX_LIFT := .34
## Quanto a suspensão estica antes de a roda sair do chão.
const TRAVEL := .38
const GRAVITY := 9.81
## Mola de cada canto: rígida e pouco amortecida, como bomba de hidráulica (sobe seco, quica ao soltar).
const STIFFNESS := 240.0
const DAMPING := 14.0
## Pulo cheio: ~0,9 m de carroceria, o que tira as rodas do chão.
const HOP_HEIGHT := .95
const HOP_RESTITUTION := .28
## Sequências do "show" dos parados: [segundos, FE, FD, TE, TD, pulo].
const PATTERNS := {
	"front": [[.45,1,1,0,0,0.0],[.45,0,0,0,0,0.0]],
	"rear": [[.45,0,0,1,1,0.0],[.45,0,0,0,0,0.0]],
	"side": [[.5,1,0,1,0,0.0],[.5,0,1,0,1,0.0]],
	"three_wheel": [[.7,1,0,0,1,0.0],[.35,1,0,0,1,0.0],[.7,0,1,1,0,0.0],[.35,0,1,1,0,0.0]],
	"wave": [[.32,1,1,0,0,0.0],[.32,0,1,0,1,0.0],[.32,0,0,1,1,0.0],[.32,1,0,1,0,0.0]],
	"hop": [[.25,0,0,0,0,0.0],[1.15,0,0,0,0,1.0]],
	"hop_small": [[.2,0,0,0,0,0.0],[.85,0,0,0,0,.55]],
	"stance": [[1.0,.55,.55,.55,.55,0.0]],
}
## Cantos na ordem FE (frente esquerda), FD, TE, TD.
var vehicle: CharacterBody3D
var target: Array[float] = [0.0, 0.0, 0.0, 0.0]
var height: Array[float] = [0.0, 0.0, 0.0, 0.0]
var rate: Array[float] = [0.0, 0.0, 0.0, 0.0]
var hop_y := 0.0
var hop_v := 0.0
## Altura extra de passeio (jogador alternou "alto"), somada a todos os cantos.
var stance := 0.0
## Maior altura de pulo desde o último reset (para o desafio do encontro).
var best_hop := 0.0
## Pulos do jogador encadeados no ritmo: apertar logo depois de aterrissar bombeia mais alto.
const CHAIN_WINDOW := .35
var hop_chain := 0
var _landed_msec := -100000
var _visual: Node3D
var _visual_rest := Transform3D.IDENTITY
var _wheel_rest: Dictionary = {}
var _corner_x := .78
var _corner_zf := -1.4
var _corner_zr := 1.4
var _pattern: Array = []
var _pattern_name := ""
var _pattern_step := 0
var _pattern_clock := 0.0
var _pattern_loops := -1
var _held_time := 0.0
var _held_axis := false
var _was_held := false
var _hop_pressed := false
var _rng := RandomNumberGenerator.new()
var _idle_show_clock := 0.0
var _resting := true
var _body := Transform3D.IDENTITY
## Ocupantes que não são filhos do visual (Cobras sentados, NPC do encontro): seguem a carroceria.
var _riders: Dictionary = {}
## Dica de controle uma vez por sessão, na primeira vez que o jogador senta num lowrider.
static var _hint_shown := false

func configure(owner_vehicle: CharacterBody3D) -> void:
	vehicle = owner_vehicle
	name = "LowriderHydraulics"
	_rng.seed = hash(str(owner_vehicle.get_instance_id()))
	_idle_show_clock = _rng.randf_range(3.0, 9.0)

## Transformação atual da carroceria em relação à pose assada (identidade parada).
func body_transform() -> Transform3D:
	return _body

func active() -> bool:
	return not _resting

func captures_input() -> bool:
	return _player_driving() and _held()

static func _held() -> bool:
	return InputMap.has_action("hydraulics") and Input.is_action_pressed("hydraulics")

func add_rider(node: Node3D) -> void:
	if is_instance_valid(node): _riders[node] = node.transform

func remove_rider(node: Node3D) -> void:
	if _riders.has(node):
		if is_instance_valid(node): node.transform = _riders[node]
		_riders.erase(node)

## Alvo por canto (0 a 1). O padrão em curso para.
func set_corners(fl: float, fr: float, rl: float, rr: float) -> void:
	_pattern = []
	_pattern_name = ""
	target = [clampf(fl, 0, 1), clampf(fr, 0, 1), clampf(rl, 0, 1), clampf(rr, 0, 1)]
	_wake()

## Pulo com força de 0 a 1 (1 = HOP_HEIGHT). Só pula com a carroceria perto do chão.
func hop(strength := 1.0) -> bool:
	# Já lançado conta como no ar, mesmo antes do primeiro passo de física; o quique baixo da
	# aterrissagem (< 1,5 m/s) não conta, senão o pulo encadeado nunca pegava a janela.
	if hop_y > .05 or hop_v > 1.5: return false
	var h := HOP_HEIGHT*clampf(strength, 0.0, 1.2)
	hop_v = sqrt(2.0*GRAVITY*h)
	_sound_pump(1.0)
	_wake()
	return true

## Pulo do jogador: o primeiro sai médio; cada um apertado até CHAIN_WINDOW s depois de
## aterrissar sobe mais (como bombear a hidráulica no tempo certo), até 1,15 do pulo cheio.
func player_hop() -> bool:
	if hop_y > .05 or hop_v > 1.5: return false
	var in_time := Time.get_ticks_msec()-_landed_msec <= int(CHAIN_WINDOW*1000.0)
	hop_chain = mini(hop_chain+1, 4) if in_time else 0
	return hop(.62+.13*hop_chain)

func play(pattern: String, loops := -1) -> void:
	if not PATTERNS.has(pattern): return
	_pattern = PATTERNS[pattern]
	_pattern_name = pattern
	_pattern_step = -1
	_pattern_clock = 0.0
	_pattern_loops = loops
	_wake()

func playing() -> String:
	return _pattern_name

func stop() -> void:
	_pattern = []
	_pattern_name = ""
	target = [0.0, 0.0, 0.0, 0.0]
	_wake()

func reset_best_hop() -> void:
	best_hop = 0.0

func _wake() -> void:
	if _resting:
		_resting = false
		_capture_rest()

func _capture_rest() -> void:
	if vehicle == null or not is_instance_valid(vehicle.visual): return
	if _visual == vehicle.visual: return
	_visual = vehicle.visual
	_visual_rest = _visual.transform
	_wheel_rest.clear()
	var xs := 0.0
	var front := []
	var rear := []
	for pivot: Node3D in vehicle.wheels:
		_wheel_rest[pivot] = pivot.position
		xs = maxf(xs, absf(pivot.position.x))
		if pivot.position.z < 0: front.append(pivot.position.z)
		else: rear.append(pivot.position.z)
	if xs > .1: _corner_x = xs
	if not front.is_empty(): _corner_zf = front.min()
	if not rear.is_empty(): _corner_zr = rear.max()

func _player_driving() -> bool:
	return vehicle != null and vehicle.controlled and not vehicle.traffic and not vehicle.external_input and not vehicle.input_locked and vehicle.health > 0

func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle.visual): return
	# Parado na altura assada e sem ninguém mandando: custa só este teste por quadro.
	var player := _player_driving()
	if _resting and not player and not vehicle.traffic: return
	if player:
		if not _hint_shown: _show_hint()
		_player_controls(delta)
	elif vehicle.traffic: _traffic_show(delta)
	if _resting: return
	if vehicle.visual != _visual: _capture_rest()
	_advance_pattern(delta)
	var moving := false
	for i in 4:
		var goal := (minf(1.0, target[i]+stance))*MAX_LIFT
		var accel := (goal-height[i])*STIFFNESS-rate[i]*DAMPING
		var before := rate[i]
		rate[i] += accel*delta
		height[i] += rate[i]*delta
		# Batente: a carroceria não desce abaixo da altura assada.
		if height[i] < 0.0:
			height[i] = 0.0
			if rate[i] < -.6: _sound_slam(absf(rate[i]))
			rate[i] = -rate[i]*.18
		if before <= .2 and rate[i] > 1.4: _sound_pump(.6)
		moving = moving or absf(rate[i]) > .002 or absf(goal-height[i]) > .002
	if hop_y > 0.0 or hop_v > 0.0:
		hop_v -= GRAVITY*delta
		hop_y += hop_v*delta
		best_hop = maxf(best_hop, hop_y)
		if hop_y <= 0.0:
			hop_y = 0.0
			if hop_v < -1.0:
				_sound_slam(absf(hop_v)*.6)
				_landed_msec = Time.get_ticks_msec()
			hop_v = -hop_v*HOP_RESTITUTION if hop_v < -1.2 else 0.0
		moving = true
	_apply()
	if not moving and _pattern.is_empty() and hop_y <= 0.0 and _all_zero():
		_restore()
		_resting = true

func _all_zero() -> bool:
	for i in 4:
		if height[i] > .0005 or target[i] > 0.0: return false
	return stance <= 0.0

## Segurar "hidráulica": W/S levantam frente/traseira, A/D esquerda/direita; Espaço pula.
## Toque rápido sem direção alterna a altura de passeio (baixo/alto).
func _player_controls(delta: float) -> void:
	var held := _held()
	if held:
		_held_time += delta
		var controls := get_node_or_null("/root/GameInput")
		var axis: Vector2 = controls.vehicle_input() if controls != null else Vector2.ZERO
		if axis.length() > .25: _held_axis = true
		var front := maxf(0.0, axis.y)
		var rear := maxf(0.0, -axis.y)
		var left := maxf(0.0, -axis.x)
		var right := maxf(0.0, axis.x)
		_pattern = []
		_pattern_name = ""
		target = [clampf(front+left, 0, 1), clampf(front+right, 0, 1), clampf(rear+left, 0, 1), clampf(rear+right, 0, 1)]
		var jump := Input.is_action_pressed("handbrake")
		if jump and not _hop_pressed: player_hop()
		_hop_pressed = jump
	elif _was_held:
		if _held_time < .25 and not _held_axis:
			stance = 0.0 if stance > 0.0 else .45
			_sound_pump(.8)
		else:
			_sound_dump()
		target = [0.0, 0.0, 0.0, 0.0]
		_held_time = 0.0
		_held_axis = false
		_hop_pressed = false
	_was_held = held
	if held or stance > 0.0: _wake()

func _show_hint() -> void:
	_hint_shown = true
	var scene := get_tree().current_scene
	var session: Variant = scene.get("session") if scene != null else null
	if session == null or not (session as Object).has_method("show_message"): return
	var controls := get_node_or_null("/root/GameInput")
	var hold: String = controls.hint("hydraulics") if controls != null and controls.has_method("hint") else "Ctrl"
	var jump: String = controls.hint("handbrake") if controls != null and controls.has_method("hint") else "Espaço"
	session.show_message(String(TranslationServer.translate("Lowrider: segure %s e use a direção para levantar cada lado; %s pula. Toque rápido em %s deixa o carro alto.")) % [hold, jump, hold])

## Lowrider dos Cobras parado no sinal às vezes dá uma "dançada".
func _traffic_show(delta: float) -> void:
	if absf(vehicle.speed) > .3:
		_idle_show_clock = maxf(_idle_show_clock, 2.0)
		if not _pattern.is_empty() and _pattern_loops < 0: stop()
		return
	_idle_show_clock -= delta
	if _idle_show_clock > 0.0 or not _pattern.is_empty(): return
	_idle_show_clock = _rng.randf_range(6.0, 14.0)
	play(["front", "side", "hop_small", "three_wheel"][_rng.randi_range(0, 3)], 2)

func _advance_pattern(delta: float) -> void:
	if _pattern.is_empty(): return
	_pattern_clock -= delta
	if _pattern_clock > 0.0: return
	_pattern_step += 1
	if _pattern_step >= _pattern.size():
		_pattern_step = 0
		if _pattern_loops > 0: _pattern_loops -= 1
		if _pattern_loops == 0:
			stop()
			return
	var step: Array = _pattern[_pattern_step]
	_pattern_clock = float(step[0])
	var before := target.duplicate()
	target = [float(step[1]), float(step[2]), float(step[3]), float(step[4])]
	if float(step[5]) > 0.0: hop(float(step[5]))
	var rising := false
	var falling := false
	for i in 4:
		rising = rising or target[i] > before[i]+.2
		falling = falling or target[i] < before[i]-.2
	if rising: _sound_pump(.7)
	elif falling: _sound_dump()

## Plano da carroceria pelos quatro cantos: subida média, arfagem e rolagem pequenas.
func _apply() -> void:
	if _visual == null: return
	var fl := height[0]
	var fr := height[1]
	var rl := height[2]
	var rr := height[3]
	var heave := (fl+fr+rl+rr)*.25+hop_y
	var base := maxf(.5, _corner_zr-_corner_zf)
	var pitch := asin(clampf(((fl+fr)-(rl+rr))*.5/base, -.6, .6))
	var roll := asin(clampf(((fl+rl)-(fr+rr))*.5/(2.0*_corner_x), -.6, .6))
	var pivot := Vector3(0, 0, (_corner_zf+_corner_zr)*.5)
	var rotation := Basis(Vector3.RIGHT, pitch)*Basis(Vector3.BACK, -roll)
	_body = Transform3D(Basis.IDENTITY, Vector3(0, heave, 0))*Transform3D(Basis.IDENTITY, pivot)*Transform3D(rotation, Vector3.ZERO)*Transform3D(Basis.IDENTITY, -pivot)
	var full := _body*_visual_rest
	_visual.transform = full
	var inverse := full.affine_inverse()
	var spin := float(vehicle.wheel_spin)
	var burnout := float(vehicle.get("_burnout_wheel_spin"))
	var steer := float(vehicle.steering)
	for pivot_node: Node3D in _wheel_rest:
		if not is_instance_valid(pivot_node): continue
		var rest: Vector3 = _wheel_rest[pivot_node]
		var ground: Vector3 = _visual_rest*rest
		# A roda fica no chão até a suspensão esticar todo o curso; depois sobe com a carroceria.
		var lifted: float = (_body*ground).y-ground.y
		var wheel := ground+Vector3.UP*maxf(0.0, lifted-TRAVEL)
		pivot_node.position = inverse*wheel
		var front: bool = pivot_node.get_meta("front", false)
		var own := Basis.from_euler(Vector3(spin+(0.0 if front else burnout), steer if front else 0.0, 0.0))
		pivot_node.basis = full.basis.inverse()*_visual_rest.basis*own
	for rider: Node3D in _riders:
		if is_instance_valid(rider): rider.transform = _body*_riders[rider]

func _restore() -> void:
	_body = Transform3D.IDENTITY
	if _visual == null: return
	_visual.transform = _visual_rest
	for pivot_node: Node3D in _wheel_rest:
		if is_instance_valid(pivot_node):
			pivot_node.position = _wheel_rest[pivot_node]
			var front: bool = pivot_node.get_meta("front", false)
			pivot_node.rotation = Vector3(float(vehicle.wheel_spin), float(vehicle.steering) if front else 0.0, 0.0)
	for rider: Node3D in _riders:
		if is_instance_valid(rider): rider.transform = _riders[rider]

func _exit_tree() -> void:
	_restore()

# ---------------------------------------------------------------- som
# Placeholders do banco existente (freio de mão grave = bomba, freio a ar = alívio, porta = batente)
# até a hidráulica ganhar sons próprios.

func _sound_pump(level: float) -> void:
	if not vehicle.is_inside_tree(): return
	var now := Time.get_ticks_msec()
	if now-int(get_meta("pump_msec", -10000)) < 220: return
	set_meta("pump_msec", now)
	FIREFLY.play_at(vehicle, FIREFLY.take("vehicle_fx", "handbrake"), vehicle.global_position, -10.0+level*3.0, _rng.randf_range(.62, .72), 30.0, 8.0, &"Vehicles")

func _sound_dump() -> void:
	if not vehicle.is_inside_tree(): return
	var now := Time.get_ticks_msec()
	if now-int(get_meta("dump_msec", -10000)) < 400: return
	set_meta("dump_msec", now)
	FIREFLY.play_at(vehicle, AIR_DUMP, vehicle.global_position, -12.0, _rng.randf_range(1.05, 1.2), 30.0, 8.0, &"Vehicles")

func _sound_slam(speed: float) -> void:
	if not vehicle.is_inside_tree(): return
	var now := Time.get_ticks_msec()
	if now-int(get_meta("slam_msec", -10000)) < 160: return
	set_meta("slam_msec", now)
	FIREFLY.play_at(vehicle, FIREFLY.take("vehicle_fx", "door_close"), vehicle.global_position, clampf(-14.0+speed*2.5, -14.0, -3.0), _rng.randf_range(.55, .68), 32.0, 8.0, &"Vehicles")
