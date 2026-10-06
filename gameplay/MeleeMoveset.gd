extends RefCounted
## Golpes corpo a corpo autorados por quadros-chave, no espaço V1 do Actor
## (+X direita, −Z frente, Y para cima), como o resto de `WeaponRigPose`.
## Só apresentação: dano, alcance e cadência continuam em Gameplay/WeaponCatalog,
## e o contato de todas as variações cai no MESMO instante de
## `WeaponRigPose.MELEE_CONTACT`, que é quando Gameplay aplica o dano.
##
## Linguagem de golpe dos jogos de ação em terceira pessoa (GTA V, RDR2, The Last
## of Us): antecipação curta e desacelerada, golpe acelerando até o contato (a
## velocidade máxima é NO contato, não antes), follow-through que passa do alvo e
## recuperação lenta. O quadril lidera o tronco (cadeia cinética) e o peso vai
## para a frente no contato. Golpes seguidos encadeiam variações (combo), e o
## último da sequência é o golpe pesado.
##
## Cada chave: "t" (s), "ease" do segmento que TERMINA nela ("in" acelera, "out"
## desacelera, "inout"), e canais opcionais — uma chave sem o canal herda o valor
## da anterior. Mãos livres (socos): "r"/"l" posição da palma, "rb"/"lb" Euler da
## palma (ordem de `_basis`), "rp"/"lp" polo do cotovelo. Armas de duas mãos:
## "r" palma direita, "d" direção da cabeça da arma, "k" normal do plano do
## golpe (com pegada de duas mãos a arma não rola no punho: gira nesse plano, e o
## fio do machado fica em d × k, sempre à frente no golpe). Corpo: "torso" (giro do peito,
## positivo leva o ombro direito à frente), "hip" (giro do quadril), "lean"
## (inclinação para a frente), "dip" (agachamento, m) e "step" (peso à frente, m).
## A primeira chave implícita é a pose em que o golpe começou; a última, a guarda
## ou o carregamento atual (que segue o passo).

const TURN := PI * 0.45
## Janela de encadeamento: apertar de novo antes disto continua a sequência.
const CHAIN := {"fists": 0.62, "knuckles": 0.66, "bat": 0.98, "axe": 1.08}
## Socos: soqueira é a mesma coreografia, um pouco mais pesada (contato 0,16 s).
const PUNCH_SCALE := {"fists": 1.0, "knuckles": 0.16 / 0.14}
const SWING_SCALE := {"bat": 1.0, "axe": 0.38 / 0.36}
## Guarda dos punhos: mãos à altura do queixo, cotovelos fechados.
const GUARD_RIGHT := Vector3(0.14, 1.07, -0.22)
const GUARD_LEFT := Vector3(-0.13, 1.10, -0.25)
const POLE_RIGHT := Vector3(0.65, -1.5, -0.5)
const POLE_LEFT := Vector3(-0.65, -1.5, -0.5)

## Jab (esq.), direto (dir.), gancho (esq.) e uppercut (dir., o pesado).
## Contato em 0,14 s em todas.
const PUNCHES := [
	{"side": "left", "end": 0.38, "keys": [
		{"t": 0.045, "ease": "out", "l": Vector3(-0.13, 1.07, -0.20), "r": Vector3(0.11, 1.11, -0.20), "torso": 0.10, "hip": 0.02, "dip": 0.015, "lean": 0.02},
		{"t": 0.14, "ease": "in", "l": Vector3(-0.045, 1.13, -0.49), "lb": Vector3(0, 0, -TURN), "torso": -0.42, "hip": -0.16, "lean": 0.10, "step": 0.05, "dip": 0.02},
		{"t": 0.19, "ease": "out", "l": Vector3(-0.05, 1.12, -0.46), "torso": -0.38, "hip": -0.15},
	]},
	{"side": "right", "end": 0.42, "keys": [
		{"t": 0.05, "ease": "out", "r": Vector3(0.16, 1.05, -0.17), "l": Vector3(-0.10, 1.13, -0.22), "torso": -0.26, "hip": -0.12, "dip": 0.025, "lean": 0.03},
		{"t": 0.14, "ease": "in", "r": Vector3(0.035, 1.12, -0.50), "rb": Vector3(0, 0, TURN), "torso": 0.56, "hip": 0.30, "lean": 0.14, "step": 0.07, "dip": 0.03},
		{"t": 0.20, "ease": "out", "r": Vector3(0.04, 1.11, -0.47), "torso": 0.52, "hip": 0.29},
	]},
	{"side": "left", "end": 0.46, "keys": [
		# O gancho abre o cotovelo para fora antes de cruzar à frente do queixo.
		{"t": 0.05, "ease": "out", "l": Vector3(-0.29, 1.09, -0.21), "lb": Vector3(0, 0.30, 0), "r": Vector3(0.11, 1.12, -0.20), "lp": Vector3(-1.3, -0.6, 0.1), "torso": 0.30, "hip": 0.14, "dip": 0.035},
		{"t": 0.10, "ease": "in", "l": Vector3(-0.21, 1.13, -0.41), "lp": Vector3(-1.45, -0.15, 0.25), "torso": -0.10, "hip": -0.12},
		{"t": 0.14, "ease": "in", "l": Vector3(0.02, 1.13, -0.41), "lb": Vector3(0, -0.55, -TURN), "torso": -0.66, "hip": -0.32, "lean": 0.08, "step": 0.04},
		{"t": 0.21, "ease": "out", "l": Vector3(0.08, 1.11, -0.34), "torso": -0.74, "hip": -0.34},
	]},
	{"side": "right", "end": 0.52, "heavy": true, "keys": [
		# Afunda os joelhos e solta o corpo para cima com o punho.
		{"t": 0.06, "ease": "out", "r": Vector3(0.15, 0.92, -0.20), "rb": Vector3(-0.45, 0, 0.35), "l": Vector3(-0.10, 1.13, -0.22), "rp": Vector3(0.35, -1.5, -0.9), "torso": -0.32, "hip": -0.16, "dip": 0.075, "lean": 0.14},
		{"t": 0.14, "ease": "in", "r": Vector3(0.05, 1.21, -0.39), "torso": 0.36, "hip": 0.26, "dip": -0.005, "lean": -0.05, "step": 0.05},
		{"t": 0.22, "ease": "out", "r": Vector3(0.04, 1.25, -0.33), "lean": -0.08, "torso": 0.40},
	]},
]

## Taco/machado: forehand, backhand e golpe por cima (o pesado). Contato em 0,36 s.
const SWINGS := [
	{"end": 0.80, "keys": [
		{"t": 0.24, "ease": "inout", "r": Vector3(0.20, 1.20, 0.0), "d": Vector3(0.35, 0.55, 0.75), "k": Vector3(0, -1, 0), "torso": -0.62, "hip": -0.26, "dip": 0.025, "step": -0.025},
		{"t": 0.31, "ease": "in", "r": Vector3(0.21, 1.11, -0.17), "d": Vector3(1, 0.15, -0.1), "k": Vector3(0, -1, 0), "torso": -0.18, "hip": 0.18, "dip": 0.04, "step": 0.03},
		{"t": 0.36, "ease": "in", "r": Vector3(0.05, 1.06, -0.35), "d": Vector3(0.1, 0.0, -1), "k": Vector3(0, -1, 0), "torso": 0.32, "hip": 0.36, "lean": 0.10, "step": 0.07, "dip": 0.04},
		{"t": 0.47, "ease": "out", "r": Vector3(-0.15, 1.08, -0.27), "d": Vector3(-1, 0.1, 0.15), "k": Vector3(0, -1, 0), "torso": 0.70, "hip": 0.40, "lean": 0.06},
		{"t": 0.57, "ease": "out", "r": Vector3(-0.17, 1.15, -0.16), "d": Vector3(-0.45, 0.55, 0.7), "k": Vector3(0, -1, 0), "torso": 0.55, "hip": 0.30, "lean": 0.02, "step": 0.03},
	]},
	{"end": 0.80, "keys": [
		{"t": 0.24, "ease": "inout", "r": Vector3(-0.10, 1.18, -0.12), "d": Vector3(-0.45, 0.55, 0.7), "k": Vector3(0, -1, 0), "torso": 0.50, "hip": 0.20, "dip": 0.025, "step": -0.02},
		{"t": 0.31, "ease": "in", "r": Vector3(-0.13, 1.10, -0.25), "d": Vector3(-1, 0.15, -0.1), "k": Vector3(0, -1, 0), "torso": 0.14, "hip": -0.10, "dip": 0.04, "step": 0.03},
		{"t": 0.36, "ease": "in", "r": Vector3(0.04, 1.06, -0.36), "d": Vector3(-0.1, 0.0, -1), "k": Vector3(0, -1, 0), "torso": -0.28, "hip": -0.30, "lean": 0.10, "step": 0.06, "dip": 0.04},
		{"t": 0.47, "ease": "out", "r": Vector3(0.22, 1.07, -0.22), "d": Vector3(1, 0.1, 0.2), "k": Vector3(0, -1, 0), "torso": -0.55, "hip": -0.34, "lean": 0.05},
		{"t": 0.57, "ease": "out", "r": Vector3(0.21, 1.14, -0.10), "d": Vector3(0.4, 0.6, 0.7), "k": Vector3(0, -1, 0), "torso": -0.40, "hip": -0.22, "lean": 0.02},
	]},
	{"end": 0.88, "heavy": true, "keys": [
		# Arqueia para trás com a arma caída atrás da cabeça e despeja o peso no golpe.
		# Mãos acima e um pouco à frente da testa: atrás da cabeça a mão de apoio
		# (mais adiante no cabo) saía do alcance do braço esquerdo.
		{"t": 0.24, "ease": "inout", "r": Vector3(0.07, 1.27, -0.16), "d": Vector3(0.05, 0.62, 0.78), "k": Vector3(1, 0, 0), "torso": -0.16, "hip": -0.06, "lean": -0.10, "step": -0.03, "rp": Vector3(1.2, 0.1, -0.6), "lp": Vector3(-1.2, 0.1, -0.6)},
		{"t": 0.30, "ease": "in", "r": Vector3(0.05, 1.25, -0.24), "d": Vector3(0, 1, -0.1), "k": Vector3(1, 0, 0), "lean": 0.06, "dip": 0.02},
		{"t": 0.36, "ease": "in", "r": Vector3(0.03, 1.00, -0.42), "d": Vector3(0, -0.35, -1), "k": Vector3(1, 0, 0), "torso": 0.10, "hip": 0.10, "lean": 0.28, "dip": 0.07, "step": 0.08, "rp": Vector3(1.1, -1.5, -1.35), "lp": Vector3(-1.1, -1.5, -1.35)},
		{"t": 0.47, "ease": "out", "r": Vector3(0.02, 0.88, -0.37), "d": Vector3(0, -0.8, -0.6), "k": Vector3(1, 0, 0), "lean": 0.30, "dip": 0.08},
		# Ergue a arma à frente antes de devolvê-la ao ombro: de "apontando para o
		# chão" direto a "sobre o ombro" são direções quase opostas, e a
		# interpolação girava a arma pelo lado errado.
		{"t": 0.66, "ease": "inout", "r": Vector3(0.08, 1.10, -0.28), "d": Vector3(0.15, 0.95, -0.25), "k": Vector3(1, 0, 0), "torso": 0.0, "hip": 0.0, "lean": 0.06, "dip": 0.03, "step": 0.03},
	]},
]
## Machado: a primeira vira um corte diagonal de cima para baixo.
const AXE_DIAGONAL := {"end": 0.84, "keys": [
	{"t": 0.22, "ease": "inout", "r": Vector3(0.19, 1.27, 0.0), "d": Vector3(0.35, 0.70, 0.62), "k": Vector3(0.85, -0.5, 0), "torso": -0.58, "hip": -0.24, "lean": -0.04, "dip": 0.02, "step": -0.025},
	{"t": 0.29, "ease": "in", "r": Vector3(0.19, 1.22, -0.16), "d": Vector3(0.55, 0.80, -0.25), "k": Vector3(0.85, -0.5, 0), "torso": -0.20, "hip": 0.16, "lean": 0.06, "dip": 0.04, "step": 0.03},
	{"t": 0.36, "ease": "in", "r": Vector3(0.04, 1.02, -0.37), "d": Vector3(-0.2, -0.3, -1), "k": Vector3(0.85, -0.5, 0), "torso": 0.30, "hip": 0.34, "lean": 0.18, "step": 0.07, "dip": 0.06},
	# O follow-through segue no plano do corte, passando pela perna esquerda;
	# a volta é pela frente (pela esquerda a lâmina cruzaria o eixo do plano).
	{"t": 0.50, "ease": "out", "r": Vector3(-0.12, 0.88, -0.27), "d": Vector3(-0.45, -0.75, 0.35), "k": Vector3(0.85, -0.5, 0), "torso": 0.62, "hip": 0.38, "lean": 0.16, "dip": 0.06},
	{"t": 0.59, "ease": "inout", "r": Vector3(-0.02, 0.98, -0.34), "d": Vector3(-0.2, -0.1, -1), "k": Vector3(0.92, -0.4, 0), "torso": 0.40, "hip": 0.25, "lean": 0.10, "dip": 0.05, "step": 0.04},
	{"t": 0.67, "ease": "inout", "r": Vector3(0.03, 1.09, -0.29), "d": Vector3(0.10, 0.95, -0.30), "k": Vector3(1, 0, 0), "torso": 0.15, "hip": 0.10, "lean": 0.05, "dip": 0.03, "step": 0.03},
]}

static func moves(id: String) -> Array:
	if id in ["fists", "knuckles"]: return PUNCHES
	if id == "axe": return [AXE_DIAGONAL, SWINGS[0], SWINGS[2]]
	if id == "bat": return SWINGS
	return []

static func scale(id: String) -> float:
	return float(PUNCH_SCALE.get(id, SWING_SCALE.get(id, 1.0)))

## Avalia a variação `move` no instante `age`. `from` é a pose em que o golpe
## começou e `rest` a pose para onde ele volta (mesmos canais).
static func sample(id: String, move: Dictionary, age: float, from: Dictionary, rest: Dictionary) -> Dictionary:
	var k := scale(id)
	var keys: Array = [from]
	var previous := from
	for key in move.keys:
		var full := previous.duplicate()
		for channel in key: full[channel] = key[channel]
		full.t = float(key.t) * k
		keys.append(full)
		previous = full
	var last := rest.duplicate()
	last.t = float(move.end) * k
	last.ease = "inout"
	keys.append(last)
	keys[0] = from.duplicate()
	keys[0].t = 0.0
	var index := 1
	while index < keys.size() - 1 and age > float(keys[index].t): index += 1
	var a: Dictionary = keys[index - 1]
	var b: Dictionary = keys[index]
	var u := clampf((age - float(a.t)) / maxf(float(b.t) - float(a.t), 0.0001), 0.0, 1.0)
	var eased := _ease(u, String(b.get("ease", "inout")))
	var before: Dictionary = keys[maxi(index - 2, 0)]
	var after: Dictionary = keys[mini(index + 1, keys.size() - 1)]
	var out := {}
	for channel in a:
		if channel in ["t", "ease"]: continue
		var value_a = a[channel]
		var value_b = b.get(channel, value_a)
		if value_a is Vector3 and channel in ["r", "l"]:
			# Spline pelas chaves vizinhas: arco contínuo em vez de linhas retas
			# que param em cada chave.
			out[channel] = _catmull(before.get(channel, value_a), value_a, value_b, after.get(channel, value_b), eased)
		elif value_a is Vector3 and channel in ["d", "k"]:
			# Direção da arma: arco de rotação, não corda (a corda encurta e vira).
			out[channel] = (value_a as Vector3).normalized().slerp((value_b as Vector3).normalized(), eased)
		elif value_a is Vector3:
			out[channel] = (value_a as Vector3).lerp(value_b, eased)
		elif value_a is Basis:
			out[channel] = (value_a as Basis).orthonormalized().slerp((value_b as Basis).orthonormalized(), eased)
		else:
			out[channel] = _catmull_f(float(before.get(channel, value_a)), float(value_a), float(value_b), float(after.get(channel, value_b)), eased)
	return out

## Base da arma longa: −Z do modelo aponta para a cabeça (`head`) e +X fica no
## plano normal ao golpe (`plane`). No machado o fio (+X do modelo) fica em
## head × plane. Antes a rolagem saía do sentido do movimento, que inverte no
## fim do follow-through e girava a arma 180° num quadro.
static func swing_basis(id: String, head: Vector3, plane: Vector3) -> Basis:
	var z := -head.normalized()
	var x := plane - z * plane.dot(z)
	if x.length_squared() < 0.0001: x = Vector3.UP.cross(z) if absf(z.y) < 0.95 else Vector3.RIGHT
	x = x.normalized()
	var basis := Basis(x, z.cross(x), z)
	if id == "axe": basis = basis * Basis(Vector3.BACK, -PI * 0.5)
	return basis

static func _ease(u: float, kind: String) -> float:
	match kind:
		"in": return u * u * u * 0.35 + u * u * 0.65 # acelera até o fim do segmento
		"out": return 1.0 - pow(1.0 - u, 2.4)
		"lin": return u
	return u * u * (3.0 - 2.0 * u)

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	# Tangentes reduzidas (tensão 0,5 → 0,35): curva sem ultrapassar muito as chaves,
	# o que poria a mão para dentro do peito nos arcos fechados.
	var m1 := (p2 - p0) * 0.35
	var m2 := (p3 - p1) * 0.35
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * p1 + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2 + (t3 - t2) * m2

static func _catmull_f(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var m1 := (p2 - p0) * 0.35
	var m2 := (p3 - p1) * 0.35
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * p1 + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2 + (t3 - t2) * m2
