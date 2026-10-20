extends RefCounted
## Arte dos lugares da beira de estrada. A frente de cada lugar é o +z local, virado para a
## estrada (RoadsideLayout); a câmera gira em volta do jogador, então placa importante tem as
## duas faces pintadas e fica alta o bastante para ler de cima.
##
## Passe gráfico de 19/10/2026 (o greybox de 644b67c3 era caixa de cor chapada, sem nome legível,
## em tom pastel que o sol do deserto apagava, e nada aceso à noite):
## - placas e letreiros saem do atlas pintado (tools/roadside_art/build_roadside_atlas.py) com
##   máscara de luz noturna; chapa corrugada e concreto reaproveitam materiais já existentes;
## - a loja do posto e o escritório do ferro-velho são prédios pintados do PaintedFacadeKit
##   (posto-deserto, escritorio-mina), com janela acesa à noite;
## - as carcaças do ferro-velho são as carrocerias da frota comum (RoadsideArt.wreck);
## - uma luz por lugar, pelo LightBudget (RoadsideLamp).
## Tudo que é estático vira uma malha por material, composta uma vez (sob a cortina, por
## PaintedFacadePrewarm → prewarm()) e só instanciada na montagem do lugar.
## Colisões (caixas sólidas) seguem as do greybox: os pontos de interação e os moradores de
## RoadsideLayout ficam fora delas.
const G := preload("res://world/desert/DesertGeometry.gd")
const ART := preload("res://runtime/desert/roadside/RoadsideArt.gd")
const LAMP := preload("res://runtime/desert/roadside/RoadsideLamp.gd")
const LAYOUT := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const SALT_ROAD := preload("res://runtime/desert/roadside/RoadsideSaltRoad.gd")
const KINDS := ["station", "tower", "scrapyard", "food_truck", "salt_works", "weigh_station", "motel"]
## Carcaças: só modelos da frota comum (cena retida e desenhada no pré-aquecimento da frota),
## de carroceria em 3 superfícies (~8 desenhos por carcaça; o sedã tem 15 só na carroceria).
const WRECK_MODELS := ["ranch_single", "courier_van"]
## Tinta de carcaça: escura e suja (as cores limpas da frota liam como carro estacionado).
const WRECK_TINTS := [Color("5e4334"), Color("475257"), Color("7c7563"), Color("4d5640"), Color("6a3226")]
const PAINTED_SHOP := "posto-deserto"
const PAINTED_OFFICE := "escritorio-mina"
const SHOP_SIZE := Vector3(11, 3.8, 6.2)
const SHOP_CENTER := Vector3(0, 0, -4.3)
const OFFICE_SIZE := Vector3(7.5, 3.0, 4.0)
const OFFICE_CENTER := Vector3(10.5, 0, -4)
## Carcaças do ferro-velho: modelo, posição local, giro (yaw, pitch, roll), cor e se tem colisão.
## A última fica pendurada no eletroímã do guindaste, por cima do pátio.
const SCRAP_WRECKS := [
	["ranch_single", Vector3(-9.0, -.32, 6.0), Vector3(PI * .5 + .15, .07, -.05), 4, true],
	["courier_van", Vector3(-8.0, -.28, 1.2), Vector3(PI * .5 + .32, -.04, .08), 2, true],
	["ranch_single", Vector3(-2.2, -.3, -4.2), Vector3(PI * .5 - .12, -.09, .03), 1, true],
	["courier_van", Vector3(3.4, -.3, -5.0), Vector3(PI * .5 - .24, .05, -.1), 0, true],
	["ranch_single", Vector3(-5.5, 4.32, 3.0), Vector3(PI * .5, .05, .08), 3, false],
]
static var _baked: Dictionary = {}

# --- Montagem (chamada por DesertRoadside, um lugar por passo) ---------------------------------

static func station(root: Node3D) -> void:
	ART.instantiate(root, baked("station"))
	_lamp(root, Vector3(0, 4.3, 6), Color("fff0d6"), 16.0, 1.8)
	# Loja pintada e picape abandonada (sobre blocos, ao lado da loja) nos quadros seguintes.
	ART.later(root, [Callable(ART, "painted").bind(root, PAINTED_SHOP, SHOP_SIZE, SHOP_CENTER),
		Callable(ART, "wrecks").bind(root, [["ranch_single", _t(-9.2, -.18, -4.2, .25, 0, .03), WRECK_TINTS[3]]])])

static func tower(root: Node3D) -> void:
	ART.instantiate(root, baked("tower"))
	_lamp(root, Vector3(5.6, 2.25, 1.1), Color("ffe2b0"), 12.0, 1.4)

static func scrapyard(root: Node3D) -> void:
	ART.instantiate(root, baked("scrapyard"))
	_lamp(root, Vector3(0, 4.7, 7.4), Color("ffd9a0"), 16.0, 1.6)
	var wrecks: Array = []
	for entry in SCRAP_WRECKS:
		var at: Vector3 = entry[1]
		var turn: Vector3 = entry[2]
		wrecks.append([entry[0], _t(at.x, at.y, at.z, turn.x, turn.y, turn.z), WRECK_TINTS[entry[3]]])
	ART.later(root, [Callable(ART, "painted").bind(root, PAINTED_OFFICE, OFFICE_SIZE, OFFICE_CENTER), Callable(ART, "wrecks").bind(root, wrecks)])

static func food_truck(root: Node3D) -> void:
	ART.instantiate(root, baked("food_truck"))
	_lamp(root, Vector3(-.15, 2.2, 2.1), Color("ffe0b0"), 12.0, 1.5)

## Estrada do Sal (fase 2, 20/10): arte em RoadsideSaltRoad; carros parados nos quadros seguintes.
static func salt_works(root: Node3D) -> void:
	ART.instantiate(root, baked("salt_works"))
	_walk_in_roofs(root, "salt_works")
	_lamp(root, Vector3(0, 5.3, 32.3), Color("fff0d6"), 18.0, 1.8)

static func weigh_station(root: Node3D) -> void:
	ART.instantiate(root, baked("weigh_station"))
	_walk_in_roofs(root, "weigh_station")
	_lamp(root, Vector3(-4.2, 6.7, 7.2), Color("f4f6ff"), 18.0, 1.7)

static func motel(root: Node3D) -> void:
	ART.instantiate(root, baked("motel"))
	_walk_in_roofs(root, "motel")
	_lamp(root, Vector3(9.3, 2.9, .3), Color("ffd9b0"), 14.0, 1.5)

## Telhados dos cômodos de entrar a pé num nó só, para o coordenador esconder com o jogador dentro.
static func _walk_in_roofs(root: Node3D, kind: String) -> void:
	var node := Node3D.new()
	node.name = "WalkInRoofs"
	root.add_child(node)
	baked(kind)
	ART.instantiate(node, _baked[kind + ":roofs"])
	node.set_meta("walk_in", SALT_ROAD.WALK_IN.get(kind, []))

static func _lamp(root: Node3D, at: Vector3, tint: Color, reach: float, power: float) -> void:
	var lamp := LAMP.new()
	lamp.name = "RoadsideLamp"
	lamp.position = at
	lamp.setup(tint, reach, power)
	root.add_child(lamp)

# --- Composição em cache ---------------------------------------------------------------------

static func baked(kind: String) -> Dictionary:
	if not _baked.has(kind):
		var b := ART.batch()
		match kind:
			"station": _compose_station(b)
			"tower": _compose_tower(b)
			"scrapyard": _compose_scrapyard(b)
			"food_truck": _compose_food_truck(b)
			"salt_works", "weigh_station", "motel":
				var roofs := ART.batch()
				match kind:
					"salt_works": SALT_ROAD.compose_salt_works(b, roofs)
					"weigh_station": SALT_ROAD.compose_weigh_station(b, roofs)
					"motel": SALT_ROAD.compose_motel(b, roofs)
				_baked[kind + ":roofs"] = roofs.bake()
		_baked[kind] = b.bake()
	return _baked[kind]

## Sob a cortina (PaintedFacadePrewarm): compõe os quatro lugares, lê as carrocerias e devolve
## os materiais para desenhar uma vez (atlas novo e cópias de pintura das carcaças).
static func prewarm() -> Array:
	if not LAYOUT.enabled(): return []
	var materials: Array = [ART.atlas(), ART.concrete(), ART.rust_sheet(), ART.white_sheet()]
	for kind in KINDS:
		for pair in baked(kind).meshes + _baked.get(kind + ":roofs", {}).get("meshes", []):
			if pair[1] not in materials: materials.append(pair[1])
	for model in WRECK_MODELS:
		for mat in ART.wreck_materials(model, WRECK_TINTS):
			if mat not in materials: materials.append(mat)
	return materials

# --- Ajudas de composição ---------------------------------------------------------------------

static func _t(x: float, y: float, z: float, yaw := 0.0, pitch := 0.0, roll := 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)), Vector3(x, y, z))

static func _box(b, mat: Material, at: Vector3, size: Vector3, skin := {}, tile := Vector2(2, 2), solid := false) -> void:
	b.box(mat, Transform3D(Basis.IDENTITY, at), size, skin, tile)
	if solid: b.solid(Transform3D(Basis.IDENTITY, at), size)

## Base que leva o y local até a direção a→c.
static func _along(a: Vector3, c: Vector3) -> Basis:
	var dir := (c - a).normalized()
	if dir.dot(Vector3.UP) < -.999: return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, dir))

## Viga quadrada de a até c.
static func _beam(b, mat: Material, a: Vector3, c: Vector3, thickness: float) -> void:
	b.box(mat, Transform3D(_along(a, c), (a + c) * .5), Vector3(thickness, a.distance_to(c), thickness), {"+y": null, "-y": null})

## Cano/cabo de a até c (sem tampas).
static func _pipe(b, mat: Material, a: Vector3, c: Vector3, radius: float, segments := 6) -> void:
	b.cylinder(mat, Transform3D(_along(a, c), (a + c) * .5), radius, a.distance_to(c), segments, -1.0, false)

## Placa de duas faces pintadas (frente e verso do mesmo painel), moldura na cor `frame`.
static func _sign(b, frame: Material, at: Vector3, size: Vector3, panel: String, yaw := 0.0) -> void:
	var rect := ART.uv(panel)
	b.box(frame, _t(at.x, at.y, at.z, yaw), size, {"+z": rect, "-z": rect})

## Caixa acesa: as seis faces no mesmo retângulo do atlas (farol, lâmpada).
static func _lit(b, xf: Transform3D, size: Vector3, panel: String) -> void:
	var rect := ART.uv(panel)
	b.box(b.atlas, xf, size, {"+z": rect, "-z": rect, "+x": rect, "-x": rect, "+y": rect, "-y": rect})

## Pilha de pneus (cilindro preto com aro claro aparecendo no topo).
static func _tires(b, at: Vector3, count: int, rubber: Material, rim: Material) -> void:
	for i in count:
		var y := at.y + .13 + float(i) * .25
		b.cylinder(rubber, _t(at.x + sin(float(i) * 2.1) * .04, y, at.z + cos(float(i) * 1.7) * .04), .38, .24, 12)
	b.cylinder(rim, _t(at.x, at.y + float(count) * .25 + .005, at.z), .2, .01, 10)

## Tambor de óleo com dois aros.
static func _drum(b, at: Vector3, body: Material, ring: Material) -> void:
	b.cylinder(body, _t(at.x, at.y + .45, at.z), .29, .9, 10)
	for y in [.3, .62]: b.cylinder(ring, _t(at.x, at.y + y, at.z), .3, .035, 10, -1.0, false)

## Fardo de carro prensado com a pintura do atlas em todas as faces visíveis.
static func _bale(b, xf: Transform3D, index: int) -> void:
	var rect := ART.uv("bale_%d" % (index % 4))
	b.box(ART.color(Color("2e3032")), xf, Vector3(2.0, 1.05, 3.5), {"+z": rect, "-z": rect, "+x": rect, "-x": rect, "+y": rect, "-y": null})

# --- Posto Sol Poente ------------------------------------------------------------------------

static func _compose_station(b) -> void:
	var concrete := ART.concrete()
	var white := ART.color(Color("e4e1d9"))
	var steel := ART.color(Color("8d9193"))
	var dark := ART.color(Color("2e3032"))
	var red := ART.color(Color("a52a1d"))
	var yellow := ART.color(Color("d49a12"))
	var rubber := ART.color(Color("1c1c1b"))
	var joint := ART.color(Color("5e6366"))
	# Pátio de concreto com juntas de dilatação e manchas de óleo nas bombas.
	_box(b, concrete, Vector3(0, -.18, 5), Vector3(22, .5, 14), {"-y": null}, Vector2(4, 4))
	for x in [-7.0, -3.0, 1.0, 5.0, 9.0]: _box(b, joint, Vector3(x, .072, 5), Vector3(.05, .006, 14), {"-y": null})
	for z in [1.5, 10.5]: _box(b, joint, Vector3(0, .072, z), Vector3(22, .006, .05), {"-y": null})
	for x in [-2.5, 2.5]:
		for side in [-1.0, 1.0]: _box(b, ART.color(Color("3f3b35")), Vector3(x + side * .2, .073, 6 + side * 1.6), Vector3(.9, .004, .7), {"-y": null})
	# Cobertura: telhado de chapa branca, faixa SOL POENTE nos quatro lados e luminárias embaixo.
	for x in [-6.0, 6.0]:
		for z in [3.0, 9.0]:
			_box(b, white, Vector3(x, 2.3, z), Vector3(.4, 4.6, .4), {"-y": null, "+y": null}, Vector2(2, 2), true)
			_box(b, red, Vector3(x, .5, z), Vector3(.52, 1.0, .52), {"-y": null})
	var fascia := ART.uv("fascia")
	var short := ART.uv_span("fascia", 0.0, .64)
	b.box(white, _t(0, 4.95, 6), Vector3(14, .7, 9), {"+z": fascia, "-z": fascia, "+x": short, "-x": short, "+y": ART.white_sheet(), "-y": ART.color(Color("e4e1d9"))}, Vector2(4, 4))
	for x in [-3.5, 3.5]:
		for z in [4.0, 8.0]: b.quad(b.atlas, Vector3(x, 4.585, z), Vector3(1.2, 0, 0), Vector3(0, 0, .45), ART.uv("light"))
	# Ilha das bombas: meio-fio de concreto, pontas zebradas e duas bombas com o painel pintado.
	_box(b, concrete, Vector3(0, .12, 6), Vector3(8.5, .24, 1.4), {"-y": null}, Vector2(2, 2), true)
	for side in [-1.0, 1.0]:
		_box(b, yellow, Vector3(side * 4.4, .13, 6), Vector3(.3, .26, 1.42), {"-y": null})
		b.cylinder(yellow, _t(side * 4.75, .45, 6), .1, .9, 8)
	var pump := ART.uv("pump")
	for x in [-2.5, 2.5]:
		_box(b, white, Vector3(x, 1.09, 6), Vector3(.9, 1.7, .6), {"+z": pump, "-z": pump, "-y": null})
		b.solid(_t(x, 1.0, 6), Vector3(.9, 1.9, .6))
		_box(b, red, Vector3(x, 2.06, 6), Vector3(.98, .25, .68), {"-y": null})
		for side in [-1.0, 1.0]:
			# Mangueira em laço até o bico no coldre do lado da bomba.
			var top := Vector3(x + side * .47, 1.55, 6 + side * .1)
			var low := Vector3(x + side * .62, .55, 6 + side * .32)
			var rest := Vector3(x + side * .5, 1.15, 6 + side * .33)
			_pipe(b, rubber, top, low, .035)
			_pipe(b, rubber, low, rest, .035)
			_box(b, dark, rest + Vector3(0, .05, 0), Vector3(.12, .28, .12))
	# Lixeiras ao lado das bombas.
	for side in [-1.0, 1.0]: b.cylinder(ART.color(Color("3e6b3a")), _t(side * 4.9, .4, 7.3), .24, .8, 10)
	# Loja: prédio pintado (montado na hora, PaintedFacadeKit). Aqui só o letreiro por cima da
	# faixa laranja da pintura, o telhado com caixa-d'água azul e ar-condicionado, e a frente.
	var wall_h := SHOP_SIZE.y
	var sink := _shop_sink(wall_h)
	var front_z := SHOP_CENTER.z + SHOP_SIZE.z * .5
	if PaintedFacadeKit.enabled():
		b.quad(b.atlas, Vector3(0, wall_h * .875 - sink, front_z + .03), Vector3(5.3, 0, 0), Vector3(0, .34, 0), ART.uv("shop_band"))
		b.quad(b.atlas, Vector3(SHOP_CENTER.x - SHOP_SIZE.x * .5 - .03, wall_h * .875 - sink, SHOP_CENTER.z), Vector3(0, 0, 2.9), Vector3(0, .34, 0), ART.uv("shop_band"))
	else:
		_box(b, ART.color(Color("c9b48f")), SHOP_CENTER + Vector3(0, wall_h * .5, 0), SHOP_SIZE, {"-y": null, "+z": ART.uv("shop_band")}, Vector2(2, 2), true)
	var roof_y := wall_h - sink + .12
	b.cylinder(ART.color(Color("2a5f9e")), _t(3.4, roof_y + .5, -5.6), .78, 1.0, 14)
	b.cylinder(ART.color(Color("2a5f9e")), _t(3.4, roof_y + 1.05, -5.6), .55, .1, 14)
	_box(b, ART.color(Color("c6c4bd")), Vector3(-3.0, roof_y + .35, -6.0), Vector3(1.3, .7, .9), {"-y": null})
	b.cylinder(dark, _t(-3.0, roof_y + .71, -6.0), .32, .02, 12)
	# Freezer de gelo e banco na frente da loja.
	_box(b, ART.color(Color("e4e1d9")), Vector3(-4.3, .48, -.75), Vector3(1.4, .96, .7), {"-y": null}, Vector2(2, 2), true)
	_box(b, ART.color(Color("2a5f9e")), Vector3(-4.3, .99, -.75), Vector3(1.42, .06, .72), {"-y": null})
	_box(b, ART.color(Color("6e4e32")), Vector3(2.9, .46, -.65), Vector3(1.8, .08, .45), {"-y": null}, Vector2(2, 2), true)
	for side in [-1.0, 1.0]: _box(b, dark, Vector3(2.9 + side * .8, .21, -.65), Vector3(.06, .42, .4), {"-y": null})
	# Borracharia aberta à direita: chapa enferrujada, teto corrugado, placa no teto.
	var sheet := ART.rust_sheet()
	_box(b, sheet, Vector3(8.6, 2.1, -3.65), Vector3(6.3, 4.2, .2), {"-y": null}, Vector2(3, 4.2), true)
	_box(b, sheet, Vector3(11.65, 2.1, -.6), Vector3(.2, 4.2, 6.1), {"-y": null}, Vector2(3, 4.2), true)
	_box(b, concrete, Vector3(8.6, .04, -.66), Vector3(6.2, .075, 6.05), {"-y": null})
	b.box(sheet, _t(8.6, 4.32, -.6, 0, deg_to_rad(4)), Vector3(7.0, .14, 6.8), {"+x": dark, "-x": dark, "+z": dark, "-z": dark}, Vector2(3, 3))
	for x in [5.65, 11.55]: _box(b, dark, Vector3(x, 2.1, 2.3), Vector3(.25, 4.2, .25), {"-y": null}, Vector2(2, 2), true)
	_box(b, ART.color(Color("a52a1d")), Vector3(8.6, 4.0, 2.35), Vector3(6.2, .45, .25))
	_sign(b, dark, Vector3(8.6, 5.0, 1.9), Vector3(5.2, .93, .1), "garage_sign")
	for x in [6.4, 10.8]: _box(b, dark, Vector3(x, 4.5, 1.9), Vector3(.08, .5, .08))
	b.quad(b.atlas, Vector3(11.77, 2.9, -.6), Vector3(0, 0, -2.6), Vector3(0, .46, 0), ART.uv("garage_sign"))
	# Bancada, painel de ferramentas, pilhas de pneu, tambores, compressor e macaco.
	_box(b, ART.color(Color("6e4e32")), Vector3(10.6, .96, -2.2), Vector3(1.45, .08, 2.45), {"-y": null})
	_box(b, ART.color(Color("5e6366")), Vector3(10.6, .46, -2.2), Vector3(1.35, .92, 2.35), {"-y": null})
	b.solid(_t(10.6, .5, -2.2), Vector3(1.4, 1.0, 2.4))
	_box(b, ART.color(Color("2e3032")), Vector3(9.3, 1.85, -3.53), Vector3(3.0, 1.1, .04))
	var tool_colors := [Color("a52a1d"), Color("d49a12"), Color("8d9193"), Color("2a5f9e"), Color("8d9193"), Color("a52a1d")]
	for i in tool_colors.size():
		_box(b, ART.color(tool_colors[i]), Vector3(8.2 + float(i) * .44, 1.7 + float(i % 2) * .3, -3.5), Vector3(.08, .45, .03))
	var rim := ART.color(Color("8d9193"))
	_tires(b, Vector3(6.35, 0, -2.95), 4, rubber, rim)
	_tires(b, Vector3(7.25, 0, -3.0), 3, rubber, rim)
	b.solid(_t(6.8, .5, -2.95), Vector3(1.85, 1.0, .9))
	_tires(b, Vector3(11.95, 0, 3.4), 3, rubber, rim)
	_drum(b, Vector3(11.05, 0, -3.1), ART.color(Color("2a5f9e")), dark)
	_drum(b, Vector3(10.4, 0, -3.15), ART.color(Color("a52a1d")), dark)
	b.solid(_t(10.7, .45, -3.1), Vector3(1.3, .9, .62))
	b.cylinder(ART.color(Color("a52a1d")), _t(10.95, .42, 1.3, 0, 0, PI * .5), .27, 1.0, 12)
	_box(b, dark, Vector3(10.95, .78, 1.3), Vector3(.5, .3, .35), {"-y": null})
	_box(b, yellow, Vector3(7.0, .12, .4), Vector3(.45, .2, 1.1), {"-y": null})
	_pipe(b, yellow, Vector3(7.0, .2, .9), Vector3(7.0, .85, 1.5), .03)
	# Orelhão laranja na parede da loja.
	b.cylinder(steel, _t(-6.2, 1.2, -.08), .06, 2.4, 8)
	b.shell(ART.color(Color("d9661e")), _t(-6.2, 1.72, .32), Vector3(.52, .62, .55), 12, 5)
	_box(b, steel, Vector3(-6.2, 1.52, -.05), Vector3(.34, .5, .14), {"+z": ART.uv("payphone"), "-y": null})
	b.solid(_t(-6.2, 1.15, .05), Vector3(.5, 2.3, .4))
	# Calibrador de pneu na beira do pátio.
	_box(b, red, Vector3(6.9, .65, 11.0), Vector3(.32, 1.3, .3), {"-y": null}, Vector2(2, 2), true)
	_pipe(b, rubber, Vector3(6.9, 1.1, 11.17), Vector3(6.75, .35, 11.45), .025)
	# Placa alta: duas pernas, a caixa de luz com o logotipo e os preços (as duas faces).
	for side in [-1.0, 1.0]:
		_box(b, ART.color(Color("2e3032")), Vector3(-10 + side * 1.35, 4.1, 10.5), Vector3(.3, 8.2, .3), {"-y": null}, Vector2(2, 2), true)
	_sign(b, ART.color(Color("2e3032")), Vector3(-10, 5.95, 10.5), Vector3(3.0, 4.5, .3), "pylon")
	_box(b, red, Vector3(-10, 8.28, 10.5), Vector3(3.2, .16, .4))
	_box(b, concrete, Vector3(-10, .2, 10.5), Vector3(3.4, .4, .8), {"-y": null})
	# Blocos de concreto sob a picape abandonada (a carcaça entra na montagem).
	for x in [-.7, .7]:
		for z in [-1.4, 1.4]:
			var at := Vector3(-9.2, .14, -4.2) + Basis(Vector3.UP, .25) * Vector3(x, 0, z)
			_box(b, ART.color(Color("8d9193")), at, Vector3(.35, .28, .35), {"-y": null})
	b.solid(_t(-9.2, .9, -4.2, .25), _wreck_size("ranch_single"))

## Quanto o PaintedFacadeKit afunda o prédio para a soleira da porta tocar o chão.
static func _shop_sink(wall_h: float) -> float:
	var lowest := INF
	for opening in PaintedFacadeKit.openings(PAINTED_SHOP, "front"):
		if bool(opening.leaf): lowest = minf(lowest, (1.0 - float(opening.rect[3])) * wall_h)
	return maxf(0.0, lowest - .03) if lowest < INF else 0.0

static func _wreck_size(model: String) -> Vector3:
	var bounds: Array = FLEET.spec(model).get("bounds_size", [1.9, 1.7, 4.8])
	return Vector3(float(bounds[0]), float(bounds[1]), float(bounds[2])) * Vector3(1, .9, 1)

# --- Torre de rádio --------------------------------------------------------------------------

static func _compose_tower(b) -> void:
	var red := ART.color(Color("a52a1d"))
	var white := ART.color(Color("e4e1d9"))
	var steel := ART.color(Color("8d9193"))
	var dark := ART.color(Color("2e3032"))
	var concrete := ART.concrete()
	# Treliça de 24 m em faixas vermelho/branco de 4 m (pintura de balizamento), travessas e X.
	for x in [-2.2, 2.2]:
		for z in [-2.2, 2.2]:
			_box(b, concrete, Vector3(x, .2, z), Vector3(.8, .4, .8), {"-y": null})
			b.solid(_t(x, 12, z), Vector3(.28, 24, .28))
			for band in 6:
				_box(b, red if band % 2 == 0 else white, Vector3(x, float(band) * 4.0 + 2.0, z), Vector3(.26, 4.0, .26), {"-y": null, "+y": null})
	for level in range(1, 7):
		var y := float(level) * 4.0
		for side in [-2.2, 2.2]:
			_box(b, steel, Vector3(0, y, side), Vector3(4.4, .12, .12))
			_box(b, steel, Vector3(side, y, 0), Vector3(.12, .12, 4.4))
	for band in 6:
		var y0 := float(band) * 4.0
		var y1 := y0 + 4.0
		for side in [-2.2, 2.2]:
			_beam(b, steel, Vector3(-2.2, y0, side), Vector3(2.2, y1, side), .07)
			_beam(b, steel, Vector3(2.2, y0, side), Vector3(-2.2, y1, side), .07)
			_beam(b, steel, Vector3(side, y0, -2.2), Vector3(side, y1, 2.2), .07)
			_beam(b, steel, Vector3(side, y0, 2.2), Vector3(side, y1, -2.2), .07)
	# Plataforma com guarda-corpo, mastro, antenas de painel, duas parabólicas e o farol.
	_box(b, ART.color(Color("5e6366")), Vector3(0, 24.1, 0), Vector3(6, .2, 6))
	for side in [-3.0, 3.0]:
		_box(b, steel, Vector3(0, 25.1, side), Vector3(6, .06, .06))
		_box(b, steel, Vector3(side, 25.1, 0), Vector3(.06, .06, 6))
		for k in [-3.0, 0.0, 3.0]:
			_box(b, steel, Vector3(k, 24.65, side), Vector3(.06, .9, .06))
			_box(b, steel, Vector3(side, 24.65, k), Vector3(.06, .9, .06))
	b.cylinder(white, _t(0, 28.2, 0), .12, 8.0, 8)
	b.cylinder(red, _t(0, 30.5, 0), .13, 1.2, 8)
	_lit(b, _t(0, 32.3, 0), Vector3(.3, .3, .3), "beacon")
	for i in 3:
		var angle := TAU * float(i) / 3.0
		_box(b, white, Vector3(cos(angle) * .45, 27.2, sin(angle) * .45), Vector3(.3, 1.6, .12))
	for dish in [[Vector3(2.75, 25.4, 1.1), -PI * .5], [Vector3(-1.1, 25.6, -2.75), 0.0]]:
		var pos: Vector3 = dish[0]
		b.cylinder(white, Transform3D(Basis(Vector3.UP, float(dish[1])) * Basis(Vector3.RIGHT, PI * .5), pos), .7, .28, 14, .42)
		_box(b, steel, pos + Basis(Vector3.UP, float(dish[1])) * Vector3(0, 0, .3), Vector3(.1, .1, .3))
	# Faróis de balizamento a meia altura, nas quinas.
	_lit(b, _t(2.2, 16.1, 2.2), Vector3(.22, .22, .22), "beacon")
	_lit(b, _t(-2.2, 16.1, -2.2), Vector3(.22, .22, .22), "beacon")
	# Escada com gaiola na face da frente (TOWER_LADDER fica a ~1 m dela).
	var galvanized := ART.color(Color("c6c4bd"))
	for side in [-.3, .3]: _box(b, galvanized, Vector3(side, 12.05, 2.5), Vector3(.06, 24.1, .06))
	for i in 69: _box(b, galvanized, Vector3(0, .3 + float(i) * .35, 2.5), Vector3(.6, .035, .035))
	for i in 11:
		var y := 3.0 + float(i) * 2.0
		_box(b, galvanized, Vector3(0, y, 3.25), Vector3(.86, .05, .05))
		for side in [-.43, .43]: _box(b, galvanized, Vector3(side, y, 2.9), Vector3(.05, .05, .7))
	for side in [-.43, .43]: _box(b, galvanized, Vector3(side, 13.0, 3.25), Vector3(.04, 20.0, .04))
	# Casinha do equipamento: chapa branca, porta, placas, ar-condicionado e a ponte de cabos.
	var white_sheet := ART.white_sheet()
	_box(b, concrete, Vector3(5.6, .06, -1), Vector3(4.6, .12, 3.6), {"-y": null})
	_box(b, white_sheet, Vector3(5.6, 1.36, -1), Vector3(4, 2.5, 3), {"-y": null, "+y": null}, Vector2(2.5, 2.5))
	b.solid(_t(5.6, 1.3, -1), Vector3(4, 2.6, 3))
	b.box(white_sheet, _t(5.6, 2.7, -1, 0, deg_to_rad(-3)), Vector3(4.4, .14, 3.5), {"+x": dark, "-x": dark, "+z": dark, "-z": dark}, Vector2(2.5, 2.5))
	_box(b, ART.color(Color("5e6366")), Vector3(5.4, 1.15, .53), Vector3(1.0, 2.1, .06))
	b.quad(b.atlas, Vector3(5.4, 1.45, .565), Vector3(.2, 0, 0), Vector3(0, .2, 0), ART.uv("hazard"))
	b.quad(b.atlas, Vector3(6.85, 1.7, .52), Vector3(.6, 0, 0), Vector3(0, .375, 0), ART.uv("tower_plate"))
	b.quad(b.atlas, Vector3(5.4, 2.4, .54), Vector3(.18, 0, 0), Vector3(0, .07, 0), ART.uv("light"))
	_box(b, ART.color(Color("c6c4bd")), Vector3(7.8, 1.5, -1.3), Vector3(.36, .6, .9), {"-y": null})
	b.cylinder(dark, _t(7.99, 1.5, -1.3, 0, 0, PI * .5), .22, .02, 12)
	_box(b, steel, Vector3(2.9, 2.35, -1.2), Vector3(1.5, .06, .4))
	_box(b, ART.color(Color("2e3032")), Vector3(2.12, 13.2, -1.95), Vector3(.05, 21.6, .05))
	# Cerca de arame: postes a cada 2 m, quatro fios e a farpa no alto (colisão como no greybox).
	var post := ART.color(Color("8d9193"))
	var wire := ART.color(Color("5e6366"))
	var runs := [[Vector3(-8, 0, -7), Vector3(8, 0, -7)], [Vector3(-8, 0, -7), Vector3(-8, 0, 7)], [Vector3(8, 0, -7), Vector3(8, 0, 7)],
		[Vector3(-8, 0, 7), Vector3(-3, 0, 7)], [Vector3(3, 0, 7), Vector3(8, 0, 7)]]
	for run in runs:
		var a: Vector3 = run[0]
		var c: Vector3 = run[1]
		var length := a.distance_to(c)
		var count := maxi(1, roundi(length / 2.0))
		for i in count + 1:
			var p := a.lerp(c, float(i) / float(count))
			b.cylinder(post, _t(p.x, 1.05, p.z), .05, 2.1, 6, -1.0, false)
		for h in [.4, .9, 1.4, 1.95]: _pipe(b, wire, a + Vector3(0, h, 0), c + Vector3(0, h, 0), .012, 4)
		_pipe(b, wire, a + Vector3(0, 2.2, 0), c + Vector3(0, 2.2, 0), .015, 4)
		var mid := (a + c) * .5
		b.solid(_t(mid.x, 1.05, mid.z), Vector3(maxf(absf(c.x - a.x), .1), 2.1, maxf(absf(c.z - a.z), .1)))
	b.quad(b.atlas, Vector3(3.0, 1.3, 7.06), Vector3(.25, 0, 0), Vector3(0, .25, 0), ART.uv("hazard"))
	b.quad(b.atlas, Vector3(3.0, 1.3, 6.94), Vector3(-.25, 0, 0), Vector3(0, .25, 0), ART.uv("hazard"))

# --- Ferro-velho do Nonato -------------------------------------------------------------------

static func _compose_scrapyard(b) -> void:
	var dark := ART.color(Color("2e3032"))
	var rust := ART.rust_sheet()
	var white_sheet := ART.white_sheet()
	var yellow := ART.color(Color("d49a12"))
	var ochre := ART.color(Color("b07e10"))
	var concrete := ART.concrete()
	var rubber := ART.color(Color("1c1c1b"))
	var rim := ART.color(Color("8d9193"))
	# Cerca de chapa: painéis de 3 m alternando chapa enferrujada e chapa clara, alturas
	# desencontradas e um poste em cada emenda. Colisão: uma caixa por trecho, como no greybox.
	var runs := [[Vector3(-15, 0, -12), Vector3(15, 0, -12)], [Vector3(-15, 0, -12), Vector3(-15, 0, 8)], [Vector3(15, 0, -12), Vector3(15, 0, 8)],
		[Vector3(-15, 0, 8), Vector3(-4, 0, 8)], [Vector3(4, 0, 8), Vector3(15, 0, 8)]]
	var panel := 0
	for run in runs:
		var a: Vector3 = run[0]
		var c: Vector3 = run[1]
		var length := a.distance_to(c)
		var count := maxi(1, roundi(length / 3.0))
		var along := (c - a) / float(count)
		var yaw := atan2(along.x, along.z) - PI * .5
		for i in count:
			var h := 2.45 + float((panel * 7) % 5) * .08
			var mid := a + along * (float(i) + .5)
			var mat: Material = white_sheet if panel % 4 == 1 else rust
			b.box(mat, _t(mid.x, h * .5, mid.z, yaw, 0, float((panel * 3) % 5 - 2) * .006), Vector3(along.length() + .04, h, .05), {"-y": null, "+y": dark, "+x": dark, "-x": dark}, Vector2(3, 2.6))
			var p := a + along * float(i)
			_box(b, dark, Vector3(p.x, 1.4, p.z), Vector3(.12, 2.8, .12), {"-y": null})
			panel += 1
		_box(b, dark, Vector3(c.x, 1.4, c.z), Vector3(.12, 2.8, .12), {"-y": null})
		var center := (a + c) * .5
		b.solid(_t(center.x, 1.3, center.z), Vector3(maxf(absf(c.x - a.x), .2), 2.6, maxf(absf(c.z - a.z), .2)))
	# Portal do portão com o letreiro (duas faces, lâmpadas acesas à noite) e as folhas abertas.
	for side in [-1.0, 1.0]:
		_box(b, dark, Vector3(side * 4.3, 2.6, 8), Vector3(.3, 5.2, .3), {"-y": null}, Vector2(2, 2), true)
		b.box(rust, _t(side * 4.25, 1.3, 6.05), Vector3(.06, 2.4, 3.9), {"+y": dark, "-y": null}, Vector2(3, 2.6))
		b.solid(_t(side * 4.25, 1.3, 6.05), Vector3(.1, 2.4, 3.9))
	_box(b, dark, Vector3(0, 5.1, 8), Vector3(9.0, .3, .3))
	_sign(b, dark, Vector3(0, 4.05, 8), Vector3(6.4, 1.6, .12), "scrap_sign")
	# Chão de asfalto velho dentro da cerca (vazio de areia lia como pátio abandonado). A laje
	# desce meio metro para não abrir fresta onde o terreno cai.
	_box(b, ART.asphalt(), Vector3(0, -.23, -2), Vector3(29.7, .54, 19.7), {"-y": null})
	# Pátio de venda: laje com a balança de chapa e faixa amarela, placa no poste.
	_box(b, concrete, Vector3(0, .06, 3), Vector3(6, .08, 7), {"-y": null}, Vector2(4, 4))
	_box(b, ART.color(Color("5e6366")), Vector3(0, .102, 3), Vector3(3.2, .01, 5.2), {"-y": null})
	for side in [-1.0, 1.0]:
		_box(b, yellow, Vector3(side * 2.85, .103, 3), Vector3(.14, .006, 6.8), {"-y": null})
		_box(b, yellow, Vector3(0, .103, 3 + side * 3.35), Vector3(5.8, .006, .14), {"-y": null})
	_box(b, dark, Vector3(-3.4, .9, 6.9), Vector3(.1, 1.8, .1), {"-y": null})
	_sign(b, dark, Vector3(-3.4, 1.95, 6.9), Vector3(1.2, .6, .06), "bay_sign")
	# Fardos de carro prensado em pilhas desalinhadas.
	var bale := 0
	for column in [[-11.0, 3], [-8.6, 3], [-6.2, 2], [4.0, 2], [6.4, 2], [8.8, 1]]:
		var x: float = column[0]
		var high: int = column[1]
		for level in high:
			var jitter := float((bale * 5) % 7 - 3)
			_bale(b, _t(x + jitter * .03, .53 + float(level) * 1.07, -9.5 + jitter * .05, jitter * .025), bale)
			bale += 1
		b.solid(_t(x, float(high) * 1.07 * .5, -9.5), Vector3(2.1, float(high) * 1.07, 3.7))
	# Monte de sucata no fundo, entre as pilhas.
	for i in 6:
		var a := float(i) * 1.37
		_bale(b, _t(-2.4 + float(i % 3) * 1.6, .35 + float(i / 3) * .55, -10.4 + float(i % 2) * .5, a, sin(a) * .35, cos(a) * .25) * Transform3D().scaled(Vector3(.7, .6, .6)), bale + i)
	b.solid(_t(-.8, .6, -10.3), Vector3(5.2, 1.2, 2.4))
	# Prensa: base, câmara amarela, pistões, cabine e um fardo saindo.
	_box(b, ART.color(Color("4a5248")), Vector3(-8, 1.1, -3), Vector3(5.5, 2.2, 4), {"-y": null})
	_box(b, ochre, Vector3(-8.6, 2.9, -3), Vector3(3.4, 1.4, 3.7), {"-y": null})
	for side in [-1.0, 1.0]: b.cylinder(ART.color(Color("c6c4bd")), _t(-6.5, 3.4, -3 + side * 1.2), .16, 2.0, 10)
	_box(b, dark, Vector3(-6.5, 4.45, -3), Vector3(.5, .2, 3.0))
	b.solid(_t(-8, 1.6, -3), Vector3(5.5, 3.2, 4))
	b.quad(b.atlas, Vector3(-8, 1.4, -.99), Vector3(.35, 0, 0), Vector3(0, .35, 0), ART.uv("hazard"))
	_bale(b, _t(-12.6, .53, -3.0, PI * .5), 2)
	b.solid(_t(-12.6, .53, -3.0), Vector3(3.5, 1.05, 2.0))
	# Guindaste: torre amarela, cabine, lança com contrapeso, cabo e o eletroímã (a carcaça
	# pendurada entra na montagem).
	_box(b, ochre, Vector3(-12, 5, 3), Vector3(.7, 10, .7), {"-y": null}, Vector2(2, 2), true)
	_box(b, ochre, Vector3(-12, 1.0, 3), Vector3(2.0, 2.0, 2.2), {"-y": null}, Vector2(2, 2), true)
	_box(b, ART.color(Color("2e3032")), Vector3(-11.0, 1.35, 3), Vector3(.04, .8, 1.6))
	_box(b, ochre, Vector3(-8.25, 9.9, 3), Vector3(8.5, .5, .5))
	_box(b, ochre, Vector3(-13.6, 9.9, 3), Vector3(2.3, .45, .45))
	_box(b, concrete, Vector3(-14.3, 9.4, 3), Vector3(1.0, 1.2, 1.2))
	_beam(b, ochre, Vector3(-12, 10.1, 3), Vector3(-7, 12.0, 3), .12)
	_beam(b, ochre, Vector3(-7, 12.0, 3), Vector3(-4.3, 10.1, 3), .1)
	_pipe(b, rubber, Vector3(-5.5, 9.65, 3), Vector3(-5.5, 6.6, 3), .03)
	b.cylinder(dark, _t(-5.5, 6.42, 3), .8, .35, 16)
	for entry in SCRAP_WRECKS:
		if not entry[4]: continue
		var at: Vector3 = entry[1]
		var size := _wreck_size(entry[0])
		b.solid(_t(at.x, size.y * .5, at.z, float(entry[2].x)), size)
	# Escritório: contêiner pintado (montado na hora). Aqui a placa no teto e a mesinha do Nonato.
	var office_front := OFFICE_CENTER.z + OFFICE_SIZE.z * .5
	if not PaintedFacadeKit.enabled():
		_box(b, ART.color(Color("b8a98c")), OFFICE_CENTER + Vector3(0, OFFICE_SIZE.y * .5, 0), OFFICE_SIZE, {"-y": null}, Vector2(2, 2), true)
	_sign(b, dark, Vector3(OFFICE_CENTER.x, OFFICE_SIZE.y + .2, office_front - .3), Vector3(2.8, .52, .06), "office_sign")
	for side in [-1.0, 1.0]: _box(b, dark, Vector3(OFFICE_CENTER.x + side * 1.2, OFFICE_SIZE.y - .2, office_front - .3), Vector3(.06, .5, .06))
	_box(b, ART.color(Color("e4e1d9")), Vector3(7.2, .7, -1.2), Vector3(.75, .04, .75), {"-y": null})
	for x in [-.32, .32]:
		for z in [-.32, .32]: _box(b, ART.color(Color("e4e1d9")), Vector3(7.2 + x, .34, -1.2 + z), Vector3(.04, .68, .04))
	# Entulho: pneus, rodas, tambores, motores e portas encostadas na cerca.
	for spot in [Vector3(-13.6, 0, -6.2), Vector3(-12.8, 0, -7.0), Vector3(-13.7, 0, -7.6)]: _tires(b, spot, 3 + int(spot.z) % 2, rubber, rim)
	b.solid(_t(-13.3, .5, -6.9), Vector3(1.9, 1.0, 2.4))
	for i in 5: b.cylinder(rim, _t(12.2 + float(i % 2) * .5, .06 + float(i) * .09, -.6 + float(i % 3) * .3), .3, .08, 12)
	var drums := [[Vector3(13.6, 0, 1.0), Color("8e4a2c")], [Vector3(14.2, 0, 1.6), Color("2a5f9e")], [Vector3(13.6, 0, 2.2), Color("8e4a2c")], [Vector3(14.2, 0, .4), Color("6f7a52")]]
	for drum in drums: _drum(b, drum[0], ART.color(drum[1]), dark)
	b.solid(_t(13.9, .45, 1.3), Vector3(1.4, .9, 2.6))
	_box(b, ART.color(Color("6e4e32")), Vector3(12.6, .07, 4.6), Vector3(1.2, .14, 1.9), {"-y": null})
	for i in 2:
		var engine := Vector3(12.6, .14, 4.15 + float(i) * .95)
		_box(b, ART.color(Color("5e6366")), engine + Vector3(0, .3, 0), Vector3(.75, .6, .55), {"-y": null})
		_box(b, ART.color(Color("2e3032")), engine + Vector3(0, .66, 0), Vector3(.5, .12, .5), {"-y": null})
		b.cylinder(rim, _t(engine.x + .4, engine.y + .32, engine.z, 0, 0, PI * .5), .16, .06, 10)
	b.solid(_t(12.6, .45, 4.6), Vector3(1.2, .9, 1.9))
	var doors := [Color("8e4a2c"), Color("4b6176"), Color("c6c4bd"), Color("6f7a52"), Color("8e4a2c")]
	for i in doors.size():
		b.box(ART.color(doors[i]), _t(14.55 - float(i) * .12, .62, 5.6 + float(i) * .55, PI * .5, 0, -.22), Vector3(1.1, 1.2, .06), {"-y": null})

# --- Lanche da Reta --------------------------------------------------------------------------

static func _compose_food_truck(b) -> void:
	var red := ART.color(Color("a52a1d"))
	var roof := ART.color(Color("e4e1d9"))
	var dark := ART.color(Color("2e3032"))
	var rubber := ART.color(Color("1c1c1b"))
	var steel := ART.color(Color("c6c4bd"))
	# Furgão-lanchonete: baú com as laterais pintadas, cabine com a frente pintada, chassi e rodas.
	_box(b, dark, Vector3(.85, .62, 0), Vector3(7.7, .3, 1.9), {"-y": null})
	b.box(red, _t(0, 1.78, 0), Vector3(6, 2.45, 2.4), {"+z": ART.uv("truck_window"), "-z": ART.uv("truck_plain"), "-x": ART.uv("truck_back"), "+y": roof, "-y": null})
	b.solid(_t(0, 1.6, 0), Vector3(6, 2.8, 2.4))
	b.box(red, _t(3.95, 1.46, 0), Vector3(1.9, 1.8, 2.3), {"+x": ART.uv("truck_front"), "+y": roof, "-y": null})
	b.solid(_t(3.9, 1.25, 0), Vector3(1.9, 2.1, 2.3))
	for side in [-1.0, 1.0]:
		b.quad(ART.color(Color("2a3a42")), Vector3(4.2, 1.85, side * 1.152), Vector3(.45 * side, 0, 0), Vector3(0, .35, 0), Rect2())
		_box(b, dark, Vector3(4.95, 1.75, side * 1.25), Vector3(.06, .3, .16))
	_box(b, steel, Vector3(4.95, .62, 0), Vector3(.18, .26, 2.3), {"-y": null})
	_box(b, steel, Vector3(-3.05, .62, 0), Vector3(.14, .22, 2.2), {"-y": null})
	for x in [-1.8, 3.9]:
		for side in [-1.0, 1.0]:
			var at := Vector3(x, .42, side * 1.0)
			b.cylinder(rubber, Transform3D(Basis(Vector3.RIGHT, PI * .5), at), .42, .3, 14)
			b.cylinder(steel, Transform3D(Basis(Vector3.RIGHT, PI * .5), at + Vector3(0, 0, side * .155)), .2, .02, 10)
	# Janela de atendimento: aba levantada (embaixo acende à noite), escoras, balcão e temperos.
	var flap := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-20)), Vector3(-.18, 2.36, 1.2) + Vector3(0, .17, .47))
	b.box(red, flap, Vector3(3.4, .05, 1.0), {"-y": ART.uv("light")})
	for side in [-1.0, 1.0]: _pipe(b, steel, Vector3(-.18 + side * 1.5, 1.55, 1.22), flap * Vector3(side * 1.5, -.03, .45), .02)
	_box(b, steel, Vector3(-.18, 1.345, 1.45), Vector3(3.4, .07, .5), {"-y": null})
	for side in [-1.0, 1.0]: _beam(b, steel, Vector3(-.18 + side * 1.4, 1.0, 1.21), Vector3(-.18 + side * 1.4, 1.32, 1.62), .04)
	for item in [[-1.2, Color("a52a1d")], [-1.05, Color("d49a12")], [.9, Color("e4e1d9")]]:
		b.cylinder(ART.color(item[1]), _t(float(item[0]), 1.47, 1.5), .045, .2, 8)
	# Letreiro de teto (duas faces, aceso à noite), ar-condicionado e chaminé.
	_sign(b, dark, Vector3(-.2, 3.5, 0), Vector3(3.4, .7, .08), "truck_sign")
	for x in [-1.6, 1.2]: _box(b, dark, Vector3(x, 3.1, 0), Vector3(.06, .3, .06))
	_box(b, ART.color(Color("c6c4bd")), Vector3(-2.1, 3.17, -.55), Vector3(1.0, .34, .8), {"-y": null})
	b.cylinder(steel, _t(2.2, 3.3, -.6), .14, .6, 10)
	# Botijão, gerador e isopor atrás do furgão.
	b.cylinder(ART.color(Color("4b6176")), _t(-3.35, .32, -.7), .18, .55, 12)
	b.cylinder(ART.color(Color("4b6176")), _t(-3.35, .64, -.7), .1, .1, 10)
	_box(b, ART.color(Color("d49a12")), Vector3(-3.45, .28, .45), Vector3(.7, .55, .5), {"-y": null}, Vector2(2, 2), true)
	_box(b, ART.color(Color("e4e1d9")), Vector3(-3.3, .2, 1.55), Vector3(.6, .4, .42), {"-y": null})
	# Mesas de plástico com cadeiras e guarda-sol.
	var tables := [[Vector3(-2.6, 0, 4.6), Color("a52a1d"), Color("d49a12")], [Vector3(1.6, 0, 4.6), Color("e4e1d9"), Color("a52a1d")]]
	for table in tables:
		var at: Vector3 = table[0]
		var plastic := ART.color(table[1])
		_box(b, plastic, at + Vector3(0, .72, 0), Vector3(.8, .04, .8))
		for x in [-.34, .34]:
			for z in [-.34, .34]: _box(b, plastic, at + Vector3(x, .35, z), Vector3(.04, .7, .04))
		b.solid(_t(at.x, .37, at.z), Vector3(.8, .74, .8))
		for side in [-1.0, 1.0]:
			var seat := at + Vector3(side * .75, 0, 0)
			_box(b, plastic, seat + Vector3(0, .45, 0), Vector3(.44, .04, .44))
			_box(b, plastic, seat + Vector3(side * .2, .7, 0), Vector3(.04, .48, .44))
			for x in [-.18, .18]:
				for z in [-.18, .18]: _box(b, plastic, seat + Vector3(x, .22, z), Vector3(.035, .44, .035))
		b.cylinder(steel, _t(at.x, 1.2, at.z), .025, 2.4, 6)
		b.cylinder(ART.color(table[2]), _t(at.x, 2.3, at.z), 1.25, .42, 10, .04)
	# Cavalete do cardápio.
	for side in [-1.0, 1.0]:
		b.box(ART.color(Color("6e4e32")), _t(2.7, .48, 2.3 + side * .12, 0, side * -.2), Vector3(.62, .95, .04), {"+z": ART.uv("menu") if side > 0 else ART.color(Color("6e4e32")), "-z": ART.uv("menu") if side < 0 else ART.color(Color("6e4e32"))})
	# Lixeira e o varal de lâmpadas entre o furgão e dois postes de madeira.
	b.cylinder(ART.color(Color("3e6b3a")), _t(3.6, .45, 3.2), .3, .9, 12)
	b.solid(_t(3.6, .45, 3.2), Vector3(.6, .9, .6))
	var wood := ART.color(Color("6e4e32"))
	var poles := [Vector3(-3.7, 0, 5.7), Vector3(3.9, 0, 5.7)]
	for pole in poles: b.cylinder(wood, _t(pole.x, 1.35, pole.z), .06, 2.7, 8)
	var strings := [[Vector3(-2.8, 2.95, 1.15), poles[0] + Vector3(0, 2.65, 0)], [Vector3(2.8, 2.95, 1.15), poles[1] + Vector3(0, 2.65, 0)],
		[poles[0] + Vector3(0, 2.65, 0), poles[1] + Vector3(0, 2.65, 0)]]
	var wire := ART.color(Color("1c1c1b"))
	for span in strings:
		var a: Vector3 = span[0]
		var c: Vector3 = span[1]
		var steps := maxi(4, roundi(a.distance_to(c) / .6))
		var previous := a
		for i in range(1, steps + 1):
			var t := float(i) / float(steps)
			var point := a.lerp(c, t) + Vector3(0, -.45 * 4.0 * t * (1.0 - t), 0)
			_pipe(b, wire, previous, point, .008, 3)
			if i < steps: b.box(b.atlas, _t(point.x, point.y - .07, point.z), Vector3(.09, .11, .09), {"+z": ART.uv("light"), "-z": ART.uv("light"), "+x": ART.uv("light"), "-x": ART.uv("light"), "+y": null, "-y": ART.uv("light")})
			previous = point
