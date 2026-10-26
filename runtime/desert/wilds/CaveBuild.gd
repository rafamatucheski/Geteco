extends RefCounted
## Cavernas do deserto refeitas (20/10/2026; playtest de 18/10: "deserto vazio, cadê as cavernas").
## A de 18/10 era um anel de pedras com um salão de 7 x 8 m. Agora é um morro de arenito em camadas
## (~22 x 20 m, até ~7 m de altura) com túnel escorado na boca, salão principal com acampamento e um
## salão dos fundos com o achado. Visto de cima, o morro é a "cobertura" (lote roofs): some quando o
## jogador entra (como os cômodos da Estrada do Sal) e fica a borda baixa das paredes, em corte.
## Coordenadas locais, boca em +z. Cada caverna varia pela semente do id (alturas, lado do salão dos
## fundos, posição do acampamento). Composição só de dados (RoadsideArt.Batch), assada uma vez.
const ART := preload("res://runtime/desert/roadside/RoadsideArt.gd")
const SR := preload("res://runtime/desert/roadside/RoadsideSaltRoad.gd")
## Teto da cavidade (colisão) e altura da borda que fica à vista quando o morro some.
const CEILING := 4.4
const RIM_LOW := 1.5
const RIM_HIGH := 2.1
const TUNNEL_TOP := 2.8
## Caverna do Vicente: o salão principal vira garagem (sem vagonete nem acampamento) com o Coyote
## parado de frente para a boca; o túnel tem 2,3 m livres entre os esteios.
const GARAGE_IDS := ["cave_brother"]
const CAR_POINT := Vector3(0, 0, -1.2)
## Godot anda para −z: PI deixa o capô virado para a boca (+z), para sair de frente pelo túnel.
const CAR_YAW := PI
## Cratera do meteoro (26/10, carta do mundo 2.0): a mesma caverna no meio de um anel de rocha
## queimada, com cristais azuis no salão dos fundos e lascas do meteoro no chão escuro em volta.
## Sem mexer no relevo: o anel é de lajes inclinadas e matacões, com abertura na frente da boca
## (largura de um carro). O anel chega a CRATER_OUTER + ~2 m do centro do lugar; a reserva do lugar
## (DesertWilds, "radius") cobre isso.
const CRATER_IDS := ["cave_crater"]
const CRATER_CENTER := Vector2(0, -1)
const CRATER_INNER := 17.0
const CRATER_OUTER := 23.0
## Meia abertura do anel, em radianos, centrada na boca (+z): ~18 m de vão no raio médio.
const CRATER_GAP := .45
## Cantos do morro (células de 2 m); fora disso só pedras soltas.
const HALF_X := 11.0
const BACK_Z := -11.0
const FRONT_Z := 9.0

static func garage(id: String) -> bool:
	return id in GARAGE_IDS

static func crater(id: String) -> bool:
	return id in CRATER_IDS

## Cristal com brilho próprio fraco (emissão no material, sem luz): aparece à noite sem gastar
## LightBudget. Uma instância só, que entra no pré-aquecimento com as outras malhas da caverna.
static var _crystal: StandardMaterial3D
static func crystal() -> Material:
	if _crystal == null:
		_crystal = StandardMaterial3D.new()
		_crystal.albedo_color = Color("7fc4e8")
		_crystal.roughness = .18
		_crystal.metallic = .1
		_crystal.emission_enabled = true
		_crystal.emission = Color("4aa8e0")
		_crystal.emission_energy_multiplier = .7
	return _crystal

## Onde fica a pilha de caixotes do acampamento (a caixa de munição).
static func ammo_point(id: String) -> Vector3:
	return Vector3(-side(id) * 4.4, .3, -2.9)

## world_state.desert_cave_ammo: {id da caverna: dia da lua em que a caixa foi esvaziada}.
static func valid_ammo_state(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 16: return false
	for id in value:
		if not id is String or id.length() > 64: return false
		var day: Variant = value[id]
		if typeof(day) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(day)) or float(day) != floorf(float(day)) or float(day) < 0 or float(day) > 1000000: return false
	return true

static func side(id: String) -> float:
	return 1.0 if absi(hash(id)) % 2 == 0 else -1.0

## Retângulos (x, z) da cavidade: túnel, salão, passagem e salão dos fundos. Também são as áreas
## "dentro" que escondem o morro.
static func cavity(id: String) -> Array:
	var s := side(id)
	return [Rect2(-1.5, 3.5, 3.0, 6.0), Rect2(-5.5, -4.5, 11.0, 8.0), Rect2(s * 4.0 - 1.0, -6.5, 2.0, 2.0), Rect2(s * 4.0 - 2.5, -9.5, 5.0, 3.0)]

static func loot_point(id: String) -> Vector3:
	return Vector3(side(id) * 4.0, .1, -8.0)

static func fire_point(id: String) -> Vector3:
	return Vector3(-side(id) * 2.6, .3, -1.6)

static func _inside(rects: Array, point: Vector2, grow := 0.0) -> bool:
	for rect: Rect2 in rects:
		if rect.grow(grow).has_point(point): return true
	return false

static func _overlaps(rects: Array, cell: Rect2, grow: float) -> bool:
	for rect: Rect2 in rects:
		if rect.grow(grow).intersects(cell): return true
	return false

static func compose(b, roofs, id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(id + ":cave"))
	var rects := cavity(id)
	# Arenito avermelhado e escuro: no claro de antes (c9a27a) os blocos liam como caixotes
	# empilhados (captura de 20/10).
	var tints := [Color("a5714d"), Color("95603f"), Color("b07c55")]
	var rock: Array = tints.map(func(c): return ART.detail("sandstone", c))
	var dark_rock := ART.detail("sandstone", Color("6e4a33"))
	_mass(b, roofs, rects, rock, dark_rock, rng)
	_walls(b, roofs, rects, rock, dark_rock, rng)
	if garage(id): _garage(b, id, rects, dark_rock, rng)
	else: _interior(b, id, rects, dark_rock, rng)
	_outside(b, rock, rng)
	if crater(id): _crater(b, id, rects, rng)

# --- Morro ---------------------------------------------------------------------------------------

## Células de 2 m com altura em cúpula (mais alta no meio, ~2,4 m na borda) e degraus de 0,8 m, que
## leem como camadas erodidas; algumas ganham uma laje de cobertura saliente.
static func _mass(b, roofs, rects: Array, rock: Array, dark_rock: Material, rng: RandomNumberGenerator) -> void:
	var cap := ART.detail("sandstone", Color("7d5238"))
	var x := -HALF_X + 1.0
	while x < HALF_X:
		var z := BACK_Z + 1.0
		while z < FRONT_Z:
			var r := Vector2(x / HALF_X, (z + 1.0) / 10.0).length()
			if r > 1.08 + rng.randf_range(-.05, .08):
				z += 2.0
				continue
			var height := lerpf(7.0, 2.4, pow(clampf(r, 0.0, 1.0), 1.5)) + rng.randf_range(-.4, .4)
			height = maxf(2.4, snappedf(height, .8))
			var tunnel := absf(x) < 2.0 and z > 3.0
			var bottom := TUNNEL_TOP if tunnel else 0.0
			if tunnel: height = maxf(height, TUNNEL_TOP + 1.0)
			var mat: Material = rock[rng.randi() % rock.size()]
			roofs.box(mat, SR._t(x, (bottom + height) * .5, z), Vector3(2.04, height - bottom, 2.04), {"-y": null}, Vector2(8, 8))
			if height >= 5.5 and rng.randf() < .12:
				roofs.box(cap, SR._t(x, height + .15, z), Vector3(2.4, .3, 2.4), {}, Vector2(8, 8))
			if not tunnel and not _overlaps(rects, Rect2(x - 1.0, z - 1.0, 2.0, 2.0), .3):
				b.solid(SR._t(x, height * .5, z), Vector3(2.0, height, 2.0))
			z += 2.0
		x += 2.0

## Paredes da cavidade: a borda de cada retângulo é amostrada a cada 0,8 m para achar as aberturas
## (onde ela dá para outro retângulo: túnel, passagem); cada trecho fechado vira uma laje baixa
## contínua com matacões tortos por cima (antes eram blocos iguais a cada 0,8 m e liam como caixotes).
## A parte baixa (até ~1,5–2,5 m) fica no lote sempre visível; a de cima vai com o morro. A colisão
## vai até o teto.
static func _walls(b, roofs, rects: Array, rock: Array, dark_rock: Material, rng: RandomNumberGenerator) -> void:
	for rect: Rect2 in rects:
		var edges := [
			[rect.position, Vector2(1, 0), Vector2(0, -1), rect.size.x],
			[Vector2(rect.position.x, rect.end.y), Vector2(1, 0), Vector2(0, 1), rect.size.x],
			[rect.position, Vector2(0, 1), Vector2(-1, 0), rect.size.y],
			[Vector2(rect.end.x, rect.position.y), Vector2(0, 1), Vector2(1, 0), rect.size.y],
		]
		for edge in edges:
			var start: Vector2 = edge[0]
			var along: Vector2 = edge[1]
			var outward: Vector2 = edge[2]
			var length: float = edge[3]
			var runs: Array = []
			var run: Array = []
			var steps := maxi(1, int(ceil(length / .8)))
			for k in steps + 1:
				var p: Vector2 = start + along * minf(float(k) * .8, length)
				var open := _inside(rects, p + outward * .3) or (outward == Vector2(0, 1) and p.y >= FRONT_Z)
				if open:
					if run.size() > 0: runs.append(run)
					run = []
				else: run.append(p)
			if run.size() > 0: runs.append(run)
			var yaw := 0.0 if along.x != 0.0 else PI * .5
			for points: Array in runs:
				var first: Vector2 = points[0]
				var last: Vector2 = points[points.size() - 1]
				var span := first.distance_to(last) + .9
				var mid := (first + last) * .5
				var base := mid + outward * .45
				b.box(rock[rng.randi() % rock.size()], SR._t(base.x, RIM_LOW * .5, base.y, yaw), Vector3(span, RIM_LOW, 1.2), {"-y": null}, Vector2(6, 6))
				var upper := mid + outward * .55
				roofs.box(rock[rng.randi() % rock.size()], SR._t(upper.x, (RIM_LOW + CEILING + .3) * .5, upper.y, yaw), Vector3(span + .2, CEILING + .3 - RIM_LOW, 1.3), {"-y": null}, Vector2(8, 8))
				var solid := mid + outward * .5
				b.solid(SR._t(solid.x, CEILING * .5, solid.y, yaw), Vector3(span - .3, CEILING, 1.0))
				var walked := 0.0
				while walked < span - .6:
					var at: Vector2 = first + along * (walked - .2)
					var size := Vector3(rng.randf_range(1.1, 1.9), rng.randf_range(RIM_LOW + .1, RIM_HIGH + .4), rng.randf_range(.8, 1.3))
					var center := at + along * size.x * .5 + outward * (size.z * .5 - rng.randf_range(.05, .25))
					b.box(dark_rock if rng.randf() < .4 else rock[rng.randi() % rock.size()],
						SR._t(center.x, size.y * .45, center.y, yaw + rng.randf_range(-.45, .45), rng.randf_range(-.1, .1), rng.randf_range(-.1, .1)),
						size, {"-y": null}, Vector2(6, 6))
					walked += size.x * rng.randf_range(.7, .95)
	for rect: Rect2 in rects:
		var c := rect.get_center()
		b.solid(SR._t(c.x, CEILING + .2, c.y), Vector3(rect.size.x + 1.0, .4, rect.size.y + 1.0))

# --- Dentro --------------------------------------------------------------------------------------

static func _interior(b, id: String, rects: Array, dark_rock: Material, rng: RandomNumberGenerator) -> void:
	var s := side(id)
	var floor_mat := ART.detail("gravel", Color("86694e"))
	for rect: Rect2 in rects:
		var c := rect.get_center()
		b.box(floor_mat, SR._t(c.x, .02, c.y), Vector3(rect.size.x, .04, rect.size.y), {"-y": null}, Vector2(3, 3))
	var wood := ART.detail("planks", Color("6b5038"))
	var steel := ART.detail("metal", Color("5d5650"), .6)
	var rust := ART.rust_sheet()
	# Túnel escorado: três quadros de madeira e os trilhos de vagonete entrando até o salão.
	for z in [4.6, 6.4, 8.2]:
		for x in [-1.25, 1.25]: SR._box(b, wood, Vector3(x, 1.27, z), Vector3(.22, 2.54, .22), {"-y": null}, Vector2(1, 1), true)
		SR._box(b, wood, Vector3(0, 2.62, z), Vector3(2.9, .26, .26), {}, Vector2(1, 1))
		SR._box(b, wood, Vector3(-.9, 2.3, z), Vector3(.12, .5, .12))
	for x in [-.45, .45]: SR._box(b, steel, Vector3(x, .1, 4.0), Vector3(.07, .08, 10.0))
	for k in 16: SR._box(b, wood, Vector3(0, .05, -.5 + float(k) * .62), Vector3(1.3, .07, .2), {"-y": null}, Vector2(1, 1))
	# Vagonete parado no fim do trilho.
	var cart := Vector3(0, 0, .4)
	SR._box(b, rust, cart + Vector3(0, .62, 0), Vector3(1.1, .6, 1.5), {}, Vector2(1, 1), true)
	SR._box(b, ART.color(Color("2a2420")), cart + Vector3(0, .9, 0), Vector3(.95, .04, 1.35))
	for x in [-.45, .45]:
		for z in [-.5, .5]: b.cylinder(steel, Transform3D(Basis(Vector3.FORWARD, PI * .5), cart + Vector3(x, .2, z)), .16, .1, 10)
	# Acampamento: fogueira de pedras, saco de dormir, caixotes, galões, lampião e picareta.
	var fire := fire_point(id) - Vector3(0, .3, 0)
	for k in 8:
		var angle := float(k) / 8.0 * TAU
		b.box(dark_rock, SR._t(fire.x + cos(angle) * .55, .1, fire.z + sin(angle) * .55, angle), Vector3(.28, .2, .22), {"-y": null}, Vector2(1, 1))
	for k in 3: b.box(ART.color(Color("2a2420")), SR._t(fire.x, .1, fire.z, float(k) * 1.05), Vector3(.7, .1, .1))
	b.box(ART.color(Color("c4562a")), SR._t(fire.x, .07, fire.z), Vector3(.5, .03, .5), {"-y": null})
	var bed := fire + Vector3(-s * 1.5, 0, 1.4)
	SR._box(b, ART.detail("plaster", Color("7a3b2e")), bed + Vector3(0, .07, 0), Vector3(.85, .12, 1.9), {"-y": null}, Vector2(1, 1))
	SR._box(b, ART.detail("plaster", Color("cfc4a8")), bed + Vector3(0, .17, -.75), Vector3(.6, .12, .32), {"-y": null}, Vector2(1, 1))
	var crate := ART.detail("crate", Color("a78a62"))
	var stack := Vector3(-s * 4.4, 0, -3.4)
	SR._box(b, crate, stack + Vector3(0, .35, 0), Vector3(.8, .7, .8), {"-y": null}, Vector2(.8, .8), true)
	SR._box(b, crate, stack + Vector3(.1, 1.0, .05), Vector3(.62, .6, .62), {"-y": null}, Vector2(.8, .8))
	SR._box(b, crate, stack + Vector3(0, .3, 1.0), Vector3(.7, .6, .6), {"-y": null}, Vector2(.8, .8), true)
	for k in 3: b.cylinder(ART.detail("metal", Color("3d6a8a"), .45), SR._t(stack.x + s * .9, .3, stack.z + .2 + float(k) * .45), .18, .6, 10)
	b.cylinder(steel, SR._t(fire.x + s * 1.1, .2, fire.z + .8), .1, .4, 8)
	b.cylinder(ART.color(Color("e8b860")), SR._t(fire.x + s * 1.1, .45, fire.z + .8), .07, .16, 8)
	var pick := Vector3(-s * 5.0, 0, 1.6)
	SR._beam(b, wood, pick + Vector3(0, .05, .5), pick + Vector3(0, 1.05, 0), .06)
	SR._box(b, steel, pick + Vector3(0, 1.08, 0), Vector3(.08, .08, .7))
	# Salão dos fundos: caixote do achado sob um lampião, ossos de bicho e uma tábua com riscos.
	var loot := loot_point(id)
	SR._box(b, ART.detail("crate", Color("7d6243")), loot + Vector3(0, .25, -.6), Vector3(1.0, .7, .7), {"-y": null}, Vector2(.8, .8), true)
	b.cylinder(steel, SR._t(loot.x + .8, .2, loot.z - .7), .1, .32, 8)
	for k in 4: SR._box(b, ART.color(Color("d8cdb1")), Vector3(loot.x - 1.4 + float(k) * .3, .06, loot.z + .5 + float(k % 2) * .25), Vector3(.45, .06, .08))
	SR._box(b, wood, Vector3(loot.x + s * 1.9, .9, loot.z - 1.0), Vector3(.06, 1.4, .9))
	for k in 6: SR._box(b, ART.color(Color("ece6d6")), Vector3(loot.x + s * 1.87, .7 + float(k % 3) * .25, loot.z - 1.3 + float(floori(k / 3.0)) * .4), Vector3(.02, .18, .03))
	# Estalagmites junto às paredes do salão e dos fundos.
	for k in 12:
		var rect: Rect2 = rects[1] if k < 8 else rects[3]
		var edge := rng.randi() % 4
		var u := rng.randf_range(.1, .9)
		var at := Vector2(lerpf(rect.position.x, rect.end.x, u), lerpf(rect.position.y, rect.end.y, u))
		match edge:
			0: at.y = rect.position.y + .5
			1: at.y = rect.end.y - .5
			2: at.x = rect.position.x + .5
			3: at.x = rect.end.x - .5
		if _inside([rects[0]], at, 1.5) or Vector2(fire.x, fire.z).distance_to(at) < 1.6 or Vector2(loot.x, loot.z).distance_to(at) < 1.4: continue
		var tall := rng.randf_range(.4, 1.3)
		b.cylinder(dark_rock, SR._t(at.x, tall * .5, at.y), rng.randf_range(.14, .32), tall, 7, .03)

## Garagem do Vicente: piso, túnel escorado e trilhos como as outras, mas no salão uma bancada de
## ferramentas, pilha de pneus, tambores de óleo, macaco e um quadro de ferramentas; nos fundos, a
## mesa com a lata de café e a foto pregada na pedra.
static func _garage(b, id: String, rects: Array, dark_rock: Material, rng: RandomNumberGenerator) -> void:
	var s := side(id)
	var floor_mat := ART.detail("gravel", Color("86694e"))
	for rect: Rect2 in rects:
		var c := rect.get_center()
		b.box(floor_mat, SR._t(c.x, .02, c.y), Vector3(rect.size.x, .04, rect.size.y), {"-y": null}, Vector2(3, 3))
	var wood := ART.detail("planks", Color("6b5038"))
	var steel := ART.detail("metal", Color("5d5650"), .6)
	for z in [4.6, 6.4, 8.2]:
		for x in [-1.25, 1.25]: SR._box(b, wood, Vector3(x, 1.27, z), Vector3(.22, 2.54, .22), {"-y": null}, Vector2(1, 1), true)
		SR._box(b, wood, Vector3(0, 2.62, z), Vector3(2.9, .26, .26), {}, Vector2(1, 1))
	# Mancha de óleo onde o carro fica e marcas de pneu saindo pelo túnel.
	b.box(ART.color(Color("3a2e24")), SR._t(CAR_POINT.x, .045, CAR_POINT.z + .3), Vector3(1.2, .01, 1.6), {"-y": null})
	for x in [-.8, .8]: b.box(ART.color(Color("5a4636")), SR._t(x, .043, 4.5), Vector3(.25, .01, 9.0), {"-y": null})
	# Bancada e quadro de ferramentas na parede do lado da passagem.
	var bench := Vector3(s * 4.7, 0, -.2)
	SR._box(b, wood, bench + Vector3(0, .9, 0), Vector3(.8, .08, 2.4), {}, Vector2(1, 1), true)
	for z in [-1.0, 1.0]: SR._box(b, steel, bench + Vector3(0, .45, z), Vector3(.7, .9, .08), {"-y": null})
	SR._box(b, ART.detail("metal", Color("8c2f24"), .5), bench + Vector3(0, 1.1, -.6), Vector3(.45, .3, .7))
	SR._box(b, wood, bench + Vector3(s * .38, 1.6, 0), Vector3(.05, 1.0, 2.0))
	for k in 6: SR._box(b, steel, bench + Vector3(s * .34, 1.3 + float(k % 2) * .4, -.8 + float(k) * .32), Vector3(.04, .3, .05))
	# Pneus empilhados e tambores de óleo do outro lado.
	var tires := Vector3(-s * 4.4, 0, -2.8)
	for k in 4: b.cylinder(ART.color(Color("1f1d1b")), Transform3D(Basis.IDENTITY, tires + Vector3(0, .13 + float(k) * .26, 0)), .34, .24, 12)
	for k in 2: b.cylinder(ART.detail("metal", Color("2f4f6e") if k == 0 else Color("7a2e22"), .5), SR._t(tires.x, .45, tires.z + 1.1 + float(k) * .65), .3, .9, 12)
	# Macaco jacaré e caixa de ferramentas no chão perto do carro.
	SR._box(b, ART.detail("metal", Color("b8322a"), .5), Vector3(-1.5, .1, -3.2), Vector3(.35, .18, .9))
	SR._box(b, ART.detail("metal", Color("c43b2b"), .5), Vector3(1.6, .15, -3.4), Vector3(.5, .3, .25))
	# Fundos: mesa com lata de café, banquinho e a foto na pedra.
	var loot := loot_point(id)
	SR._box(b, wood, loot + Vector3(0, .65, -.7), Vector3(1.2, .06, .7), {}, Vector2(1, 1), true)
	for x in [-.5, .5]: SR._box(b, wood, loot + Vector3(x, .32, -.7), Vector3(.06, .62, .6), {"-y": null})
	b.cylinder(ART.detail("metal", Color("b0472f"), .5), SR._t(loot.x - .25, .78, loot.z - .7), .08, .16, 8)
	SR._box(b, ART.color(Color("e8dcc0")), Vector3(loot.x + .2, 1.5, loot.z - 1.42), Vector3(.25, .18, .02))
	b.cylinder(wood, SR._t(loot.x + .6, .25, loot.z + .2), .18, .5, 8)
	for k in 10:
		var rect: Rect2 = rects[1] if k < 6 else rects[3]
		var u := rng.randf_range(.1, .9)
		var at := Vector2(lerpf(rect.position.x, rect.end.x, u), rect.position.y + .5)
		if Vector2(loot.x, loot.z).distance_to(at) < 1.6 or absf(at.x) < 2.6: continue
		var tall := rng.randf_range(.4, 1.1)
		b.cylinder(dark_rock, SR._t(at.x, tall * .5, at.y), rng.randf_range(.14, .3), tall, 7, .03)

# --- Fora ----------------------------------------------------------------------------------------

## Pedras caídas em volta do morro e duas lajes desabadas ao lado da boca.
static func _outside(b, rock: Array, rng: RandomNumberGenerator) -> void:
	for k in 12:
		var angle := rng.randf() * TAU
		var at := Vector2(cos(angle) * (HALF_X + rng.randf_range(.8, 2.6)), -1.0 + sin(angle) * (10.5 + rng.randf_range(.8, 2.6)))
		if at.y > FRONT_Z - 1.0 and absf(at.x) < 4.0: continue
		var size := Vector3(rng.randf_range(.8, 2.2), rng.randf_range(.6, 1.6), rng.randf_range(.8, 2.0))
		b.box(rock[k % rock.size()], SR._t(at.x, size.y * .45, at.y, rng.randf() * TAU, rng.randf_range(-.15, .15)), size, {"-y": null}, Vector2(4, 4))
		b.solid(SR._t(at.x, size.y * .45, at.y), size * .8)
	for s in [-1.0, 1.0]:
		var at := Vector3(s * 3.4, .4, FRONT_Z + .6)
		b.box(rock[0], SR._t(at.x, at.y, at.z, s * .5, 0.0, s * .25), Vector3(2.4, .8, 1.6), {"-y": null}, Vector2(4, 4))
		b.solid(SR._t(at.x, at.y, at.z, s * .5), Vector3(2.0, .8, 1.4))

# --- Cratera -------------------------------------------------------------------------------------

## Anel de lajes inclinadas para fora (a face de dentro desce para o meio, como a borda de uma
## cratera) com matacões queimados por cima; chão escuro entre o morro e o anel; lascas do meteoro
## com cristais espetados; e, no salão dos fundos, cristais grandes em volta do achado.
static func _crater(b, id: String, rects: Array, rng: RandomNumberGenerator) -> void:
	var burnt := [ART.detail("sandstone", Color("4f3a2c")), ART.detail("sandstone", Color("5e4433")), ART.detail("sandstone", Color("3c2d24"))]
	var ash := ART.detail("gravel", Color("4a3a2e"))
	var middle := (CRATER_INNER + CRATER_OUTER) * .5
	# Chão queimado: disco fino abaixo do piso da caverna (0,04), por cima do terreno plano.
	b.cylinder(ash, SR._t(CRATER_CENTER.x, .01, CRATER_CENTER.y), CRATER_INNER + 1.0, .02, 28)
	var segments := 30
	for k in segments:
		var angle := float(k) / float(segments) * TAU
		if absf(angle_difference(angle, PI * .5)) < CRATER_GAP: continue
		var radius := middle + rng.randf_range(-.8, .8)
		var at := CRATER_CENTER + Vector2(cos(angle), sin(angle)) * radius
		# Eixo x da laje na tangente; +z local aponta para o centro (ver yaw).
		var yaw := -angle - PI * .5
		var height := rng.randf_range(1.6, 3.2)
		var length := TAU * radius / float(segments) * 1.25
		var depth := CRATER_OUTER - CRATER_INNER
		b.box(burnt[k % burnt.size()], SR._t(at.x, height * .4, at.y, yaw, -.35 + rng.randf_range(-.08, .08)), Vector3(length, height, depth * .8), {"-y": null}, Vector2(6, 6))
		b.solid(SR._t(at.x, height * .4, at.y, yaw), Vector3(length * .9, height * .8, depth * .6))
		for j in rng.randi_range(1, 2):
			var spot := at + Vector2(cos(angle), sin(angle)) * rng.randf_range(-1.5, 1.8) + Vector2(-sin(angle), cos(angle)) * rng.randf_range(-1.8, 1.8)
			var size := Vector3(rng.randf_range(1.2, 2.4), rng.randf_range(.9, 1.8), rng.randf_range(1.0, 2.0))
			b.box(burnt[rng.randi() % burnt.size()], SR._t(spot.x, height * .7 + size.y * .3, spot.y, rng.randf() * TAU, rng.randf_range(-.25, .25), rng.randf_range(-.2, .2)), size, {"-y": null}, Vector2(4, 4))
	# Lascas do meteoro no chão queimado, longe da boca e do morro.
	for k in 7:
		var angle := rng.randf() * TAU
		if absf(angle_difference(angle, PI * .5)) < CRATER_GAP + .1: continue
		var at := CRATER_CENTER + Vector2(cos(angle), sin(angle)) * rng.randf_range(13.5, CRATER_INNER - 1.0)
		var size := Vector3(rng.randf_range(.9, 1.6), rng.randf_range(.5, .9), rng.randf_range(.8, 1.4))
		b.box(burnt[2], SR._t(at.x, size.y * .4, at.y, rng.randf() * TAU, rng.randf_range(-.2, .2)), size, {"-y": null}, Vector2(3, 3))
		b.solid(SR._t(at.x, size.y * .4, at.y), size * .8)
		_crystals(b, Vector3(at.x, size.y * .6, at.y), 3, .5, rng)
	# Salão dos fundos: cristais grandes junto às paredes, em volta do caixote do achado.
	var hall: Rect2 = rects[3]
	var loot := loot_point(id)
	for k in 5:
		var u := rng.randf_range(.1, .9)
		var at := Vector3(lerpf(hall.position.x, hall.end.x, u), 0, hall.position.y + .45)
		if Vector2(at.x, at.z).distance_to(Vector2(loot.x, loot.z - .6)) < .9: at.x += 1.2 * signf(at.x - loot.x + .01)
		_crystals(b, at, rng.randi_range(4, 6), 1.0, rng)
	for x in [hall.position.x + .45, hall.end.x - .45]:
		_crystals(b, Vector3(x, 0, hall.get_center().y), 4, .8, rng)

## Feixe de prismas sextavados afinando na ponta, inclinados para fora do pé.
static func _crystals(b, base: Vector3, count: int, scale: float, rng: RandomNumberGenerator) -> void:
	for k in count:
		var tall := rng.randf_range(.5, 1.3) * scale
		var lean := rng.randf_range(.15, .55)
		var turn := rng.randf() * TAU
		var basis := Basis.from_euler(Vector3(lean * cos(turn), 0, lean * sin(turn)))
		var center := base + basis * Vector3(0, tall * .5, 0)
		b.cylinder(crystal(), Transform3D(basis, center), rng.randf_range(.07, .14) * scale, tall, 6, .015 * scale)
