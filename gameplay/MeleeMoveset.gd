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
## da anterior; "path": "line" faz as mãos irem em linha reta no trecho que
## termina na chave. Mãos livres (socos): "r"/"l" posição da palma, "rr"/"lr"
## rotação do punho em torno do antebraço, "rp"/"lp" polo do cotovelo. Armas de duas mãos:
## "r" palma direita, "d" direção da cabeça da arma, "k" normal do plano do
## golpe (com pegada de duas mãos a arma não rola no punho: gira nesse plano, e o
## fio do machado fica em d × k, sempre à frente no golpe). Corpo: "torso" (giro do peito,
## positivo leva o ombro direito à frente), "hip" (giro do quadril), "lean"
## (inclinação para a frente), "dip" (agachamento, m) e "step" (peso à frente, m).
## A primeira chave implícita é a pose em que o golpe começou; a última, a guarda
## ou o carregamento atual (que segue o passo).

## Janela de encadeamento: apertar de novo antes disto continua a sequência.
const CHAIN := {"fists": 0.62, "knuckles": 0.66, "bat": 0.98, "axe": 1.08}
## Socos: soqueira é a mesma coreografia, um pouco mais pesada (contato 0,16 s).
const PUNCH_SCALE := {"fists": 1.0, "knuckles": 0.16 / 0.14}
const SWING_SCALE := {"bat": 1.0, "axe": 0.38 / 0.36}
## Guarda dos punhos: mãos à altura do queixo, cotovelos fechados, punho
## semivertical (palma para dentro). Rotação do punho em torno do antebraço, com o
## pulso reto (`Actor`): 0 = palma para baixo (impacto do direto); positivo vira a
## palma para dentro (guarda, uppercut); o lado esquerdo é espelhado no Actor.
## Negativo mostraria os dedos para fora com o polegar esticado do modelo (que não
## tem ossos de dedo): lia como "joinha", não como punho.
const GUARD_RIGHT := Vector3(0.12, 1.09, -0.26)
const GUARD_LEFT := Vector3(-0.10, 1.11, -0.29)
const GUARD_ROLL := 0.6
const POLE_RIGHT := Vector3(0.65, -1.5, -0.5)
const POLE_LEFT := Vector3(-0.65, -1.5, -0.5)

## Jab (esq.), direto (dir.), gancho (esq.) e uppercut (dir., o pesado).
## Contato em 0,14 s em todas. Jab e direto saem em LINHA RETA da guarda ao alvo
## ("path": "line") e voltam pelo mesmo caminho, girando o punho de semivertical
## para palma para baixo no impacto; só gancho e uppercut fazem arco.
const PUNCHES := [
	{"side": "left", "end": 0.36, "keys": [
		{"t": 0.04, "ease": "out", "path": "line", "l": Vector3(-0.105, 1.10, -0.27), "torso": 0.08, "hip": 0.02, "dip": 0.015, "lean": 0.02},
		{"t": 0.14, "ease": "in", "path": "line", "l": Vector3(-0.04, 1.14, -0.50), "lr": 0.0, "torso": -0.42, "hip": -0.16, "lean": 0.10, "step": 0.05, "dip": 0.02},
		{"t": 0.18, "ease": "out", "path": "line", "l": Vector3(-0.042, 1.138, -0.485), "torso": -0.40, "hip": -0.16},
	]},
	{"side": "right", "end": 0.40, "keys": [
		{"t": 0.05, "ease": "out", "path": "line", "r": Vector3(0.13, 1.08, -0.23), "torso": -0.24, "hip": -0.12, "dip": 0.025, "lean": 0.03},
		{"t": 0.14, "ease": "in", "path": "line", "r": Vector3(0.03, 1.14, -0.51), "rr": 0.0, "torso": 0.56, "hip": 0.30, "lean": 0.14, "step": 0.07, "dip": 0.03},
		{"t": 0.19, "ease": "out", "path": "line", "r": Vector3(0.032, 1.138, -0.495), "torso": 0.54, "hip": 0.30},
	]},
	{"side": "left", "end": 0.44, "keys": [
		# O gancho abre o cotovelo para fora e para cima e varre à altura do queixo.
		{"t": 0.05, "ease": "out", "l": Vector3(-0.24, 1.12, -0.22), "lr": 0.6, "lp": Vector3(-1.3, -0.4, 0.2), "torso": 0.30, "hip": 0.14, "dip": 0.035},
		{"t": 0.10, "ease": "in", "l": Vector3(-0.20, 1.15, -0.40), "lr": 0.3, "lp": Vector3(-1.5, 0.0, 0.3), "torso": -0.10, "hip": -0.12},
		{"t": 0.14, "ease": "in", "l": Vector3(-0.01, 1.15, -0.40), "lr": 0.0, "torso": -0.66, "hip": -0.32, "lean": 0.08, "step": 0.04},
		{"t": 0.20, "ease": "out", "l": Vector3(0.02, 1.12, -0.35), "torso": -0.72, "hip": -0.34},
	]},
	{"side": "right", "end": 0.50, "heavy": true, "keys": [
		# Afunda os joelhos, o punho cai à altura do peito e sobe com o corpo; a esquerda
		# volta logo à guarda (vinda do gancho, passava pela frente do queixo).
		{"t": 0.06, "ease": "out", "r": Vector3(0.14, 0.96, -0.22), "rr": 1.3, "l": GUARD_LEFT, "rp": Vector3(0.35, -1.5, -0.9), "torso": -0.32, "hip": -0.16, "dip": 0.075, "lean": 0.14},
		{"t": 0.14, "ease": "in", "r": Vector3(0.09, 1.13, -0.43), "rr": 1.45, "torso": 0.36, "hip": 0.26, "dip": -0.005, "lean": -0.05, "step": 0.05},
		{"t": 0.21, "ease": "out", "r": Vector3(0.09, 1.15, -0.40), "lean": -0.08, "torso": 0.40},
	]},
]

## Taco/machado: forehand, backhand e golpe por cima (o pesado). Contato em 0,36 s.
const SWINGS := [
	{"end": 0.88, "keys": [
		{"t": 0.24, "ease": "inout", "r": Vector3(0.23, 1.17, -0.05), "d": Vector3(0.42, 0.55, 0.72), "k": Vector3(0, -1, 0), "torso": -0.62, "hip": -0.26, "dip": 0.025, "step": -0.025},
		{"t": 0.26, "ease": "in", "r": Vector3(0.21, 1.12, -0.15), "d": Vector3(0.55, 0.5, 0.55), "k": Vector3(0, -1, 0), "torso": -0.18, "hip": 0.18, "dip": 0.04, "step": 0.03},
		{"t": 0.36, "ease": "swing", "r": Vector3(0.05, 1.06, -0.35), "d": Vector3(0.1, 0.0, -1), "k": Vector3(0, -1, 0), "torso": 0.32, "hip": 0.36, "lean": 0.10, "step": 0.07, "dip": 0.04},
		{"t": 0.47, "ease": "out", "r": Vector3(-0.15, 1.08, -0.27), "d": Vector3(-0.6, 0.6, 0.5), "k": Vector3(0, -1, 0), "torso": 0.70, "hip": 0.40, "lean": 0.06},
		# Enrola ao lado do ombro esquerdo, afastado da cabeça: rente a ela, a volta
		# pela frente obrigava a correção de colisão a girar o machado 55°/quadro.
		{"t": 0.57, "ease": "out", "r": Vector3(-0.21, 1.10, -0.22), "d": Vector3(-0.70, 0.45, 0.45), "k": Vector3(0, -1, 0), "torso": 0.55, "hip": 0.30, "lean": 0.02, "step": 0.03},
		# Volta por baixo, como pêndulo: do ombro esquerdo a arma desce pela esquerda,
		# passa apontando para a frente na altura do peito e sobe pela direita até o
		# ombro. Em pé na frente do peito (versão anterior) ela tampava o rosto; direto
		# do ombro esquerdo ao direito a mão de apoio passava rente ao ombro e o cabo do
		# machado entrava no antebraço.
		{"t": 0.65, "ease": "inout", "r": Vector3(-0.04, 0.92, -0.32), "d": Vector3(-0.3, -0.6, -0.75), "k": Vector3(0.1, -0.6, 0.8), "torso": 0.35, "hip": 0.20, "lean": 0.04, "step": 0.03},
		{"t": 0.73, "ease": "inout", "r": Vector3(0.12, 1.00, -0.30), "d": Vector3(0.5, 0.1, -0.85), "k": Vector3(0.7, -0.47, 0.36), "torso": 0.15, "hip": 0.10, "lean": 0.02, "step": 0.02},
	]},
	{"end": 0.80, "keys": [
		# Vindo do forehand (arma à frente, à direita), passa pela frente e à esquerda
		# antes de subir ao ombro esquerdo: em linha reta o cabo cruzava o antebraço
		# direito, e por cima passaria na frente do rosto.
		{"t": 0.12, "ease": "inout", "r": Vector3(-0.05, 1.02, -0.30), "d": Vector3(-0.55, 0.05, -0.83), "k": Vector3(0, -1, 0), "torso": 0.25, "hip": 0.10},
		{"t": 0.24, "ease": "inout", "r": Vector3(-0.15, 1.13, -0.08), "d": Vector3(-0.45, 0.55, 0.7), "k": Vector3(0, -1, 0), "torso": 0.50, "hip": 0.20, "dip": 0.025, "step": -0.02},
		{"t": 0.26, "ease": "in", "r": Vector3(-0.15, 1.10, -0.22), "d": Vector3(-0.55, 0.5, 0.55), "k": Vector3(0, -1, 0), "torso": 0.14, "hip": -0.10, "dip": 0.04, "step": 0.03},
		{"t": 0.36, "ease": "swing", "r": Vector3(0.04, 1.06, -0.36), "d": Vector3(-0.1, 0.0, -1), "k": Vector3(0, -1, 0), "torso": -0.28, "hip": -0.30, "lean": 0.10, "step": 0.06, "dip": 0.04},
		{"t": 0.47, "ease": "out", "r": Vector3(0.22, 1.07, -0.22), "d": Vector3(0.75, 0.35, 0.55), "k": Vector3(0, -1, 0), "torso": -0.55, "hip": -0.34, "lean": 0.05},
		{"t": 0.57, "ease": "out", "r": Vector3(0.21, 1.14, -0.10), "d": Vector3(0.4, 0.6, 0.7), "k": Vector3(0, -1, 0), "torso": -0.40, "hip": -0.22, "lean": 0.02},
	]},
	{"end": 0.88, "heavy": true, "keys": [
		# Machadada pesada: mãos sobem até o ombro direito, ao lado da orelha (não à
		# frente da testa: ali os dois antebraços tampavam o rosto), a lâmina para trás
		# e para cima, e desce quase na vertical com o peso do corpo.
		{"t": 0.24, "ease": "inout", "r": Vector3(0.22, 1.16, -0.04), "d": Vector3(0.25, 0.85, 0.45), "k": Vector3(0.97, -0.25, 0), "torso": -0.30, "hip": -0.12, "lean": -0.08, "step": -0.03, "rp": Vector3(0.9, -1.2, -0.3), "lp": Vector3(-0.9, -1.2, -0.3)},
		{"t": 0.30, "ease": "in", "r": Vector3(0.18, 1.18, -0.16), "d": Vector3(0.3, 0.95, -0.1), "k": Vector3(0.97, -0.25, 0), "lean": 0.06, "dip": 0.02},
		{"t": 0.36, "ease": "in", "r": Vector3(0.03, 1.00, -0.42), "d": Vector3(0, -0.35, -1), "k": Vector3(1, 0, 0), "torso": 0.10, "hip": 0.10, "lean": 0.28, "dip": 0.07, "step": 0.08, "rp": Vector3(1.1, -1.5, -1.35), "lp": Vector3(-1.1, -1.5, -1.35)},
		{"t": 0.47, "ease": "out", "r": Vector3(0.02, 0.88, -0.37), "d": Vector3(0, -0.8, -0.6), "k": Vector3(1, 0, 0), "lean": 0.30, "dip": 0.08},
		# Ergue a arma à frente antes de devolvê-la ao ombro: de "apontando para o
		# chão" direto a "sobre o ombro" são direções quase opostas, e a
		# interpolação girava a arma pelo lado errado.
		{"t": 0.66, "ease": "inout", "r": Vector3(0.13, 1.06, -0.27), "d": Vector3(0.30, 0.92, -0.25), "k": Vector3(1, 0, 0), "torso": 0.0, "hip": 0.0, "lean": 0.06, "dip": 0.03, "step": 0.03},
	]},
]
## Machado: a primeira vira um corte diagonal de cima para baixo.
const AXE_DIAGONAL := {"end": 0.88, "keys": [
	{"t": 0.22, "ease": "inout", "r": Vector3(0.23, 1.15, -0.05), "d": Vector3(0.42, 0.74, 0.52), "k": Vector3(0.85, -0.5, 0), "torso": -0.58, "hip": -0.24, "lean": -0.04, "dip": 0.02, "step": -0.025},
	{"t": 0.29, "ease": "in", "r": Vector3(0.21, 1.16, -0.18), "d": Vector3(0.55, 0.80, -0.25), "k": Vector3(0.85, -0.5, 0), "torso": -0.20, "hip": 0.16, "lean": 0.06, "dip": 0.04, "step": 0.03},
	{"t": 0.36, "ease": "in", "r": Vector3(0.04, 1.02, -0.37), "d": Vector3(-0.2, -0.3, -1), "k": Vector3(0.85, -0.5, 0), "torso": 0.30, "hip": 0.34, "lean": 0.18, "step": 0.07, "dip": 0.06},
	# O follow-through segue no plano do corte, descendo pela frente da perna esquerda
	# (por trás dela o cabo encostava no antebraço esquerdo);
	# a volta é pela frente (pela esquerda a lâmina cruzaria o eixo do plano).
	{"t": 0.50, "ease": "out", "r": Vector3(-0.12, 0.88, -0.29), "d": Vector3(-0.50, -0.80, -0.10), "k": Vector3(0.85, -0.5, 0), "torso": 0.62, "hip": 0.38, "lean": 0.16, "dip": 0.06},
	{"t": 0.59, "ease": "inout", "r": Vector3(-0.02, 0.98, -0.34), "d": Vector3(-0.2, -0.1, -1), "k": Vector3(0.92, -0.4, 0), "torso": 0.40, "hip": 0.25, "lean": 0.10, "dip": 0.05, "step": 0.04},
	{"t": 0.67, "ease": "inout", "r": Vector3(0.13, 1.06, -0.27), "d": Vector3(0.30, 0.92, -0.25), "k": Vector3(1, 0, 0), "torso": 0.15, "hip": 0.10, "lean": 0.05, "dip": 0.03, "step": 0.03},
	# Volta pelo lado direito do peito (bem à frente do rosto, a arma em pé tampava a
	# cara). Em pé à direita da cabeça antes de deitar no ombro: num trecho só a mão de
	# apoio (12 cm adiante no cabo) varria o arco inteiro e o antebraço saltava.
	{"t": 0.76, "ease": "inout", "r": Vector3(0.16, 1.04, -0.23), "d": Vector3(0.35, 0.93, 0.05), "k": Vector3(1, 0, 0), "torso": 0.06, "hip": 0.04, "lean": 0.02, "dip": 0.01, "step": 0.01},
]}

## Taco: o golpe pesado é o corte diagonal do ombro direito. Na pancada por cima as
## mãos subiam à frente da testa e o antebraço esquerdo passava na frente do queixo.
const BAT_HEAVY := {"end": 0.88, "heavy": true, "keys": AXE_DIAGONAL["keys"]}

static func moves(id: String) -> Array:
	if id in ["fists", "knuckles"]: return PUNCHES
	if id == "axe": return [AXE_DIAGONAL, SWINGS[0], SWINGS[2]]
	if id == "bat": return [SWINGS[0], SWINGS[1], BAT_HEAVY]
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
		full.erase("path") # caminho vale só para o trecho que termina na chave
		for channel in key: full[channel] = key[channel]
		full.t = float(key.t) * k
		keys.append(full)
		previous = full
	var last := rest.duplicate()
	last.t = float(move.end) * k
	last.ease = "inout"
	# Socos voltam à guarda pelo mesmo caminho reto.
	if String(move.get("side", "")) != "": last.path = "line"
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
		if channel in ["t", "ease", "path"]: continue
		var value_a = a[channel]
		var value_b = b.get(channel, value_a)
		if value_a is Vector3 and channel in ["r", "l"] and String(b.get("path", "")) == "line":
			out[channel] = (value_a as Vector3).lerp(value_b, eased)
		elif value_a is Vector3 and channel in ["r", "l"]:
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
static func swing_basis(id: String, head: Vector3, plane: Vector3, previous_x: Vector3 = Vector3.ZERO, max_roll: float = INF) -> Basis:
	var z := -head.normalized()
	var x := plane - z * plane.dot(z)
	var held := previous_x - z * previous_x.dot(z)
	if held.length_squared() > 0.0001:
		held = held.normalized()
		# Direção da arma quase paralela à normal do plano: a rolagem autorada fica
		# indefinida; vale a do quadro anterior. Fora disso a rolagem segue a autorada,
		# mas gira no máximo `max_roll` por quadro em torno do cabo: o caminho autorado
		# do machado pede meia-volta da lâmina na recuperação, que saía num quadro só.
		var trust := smoothstep(0.2, 0.5, x.length())
		var wanted := x.normalized() if x.length_squared() > 0.000001 else held
		var turn := held.signed_angle_to(wanted, z) * trust
		x = held.rotated(z, clampf(turn, -max_roll, max_roll))
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
		# Aceleração suave (velocidade 0,5→1,5× a média): golpe de taco, cuja palma de
		# apoio não acompanha o pico de 2,35× do "in" no contato (saía 4 cm do cabo).
		"swing": return u * u * 0.5 + u * 0.5
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
