extends RefCounted
## Acabamento da cidade do deserto, da vila Santa Lua e do pátio da oficina do Digo (20/10/2026).
## A captura de 20/10 mostrou a rua principal com só o ponto de ônibus e postes: os prédios ficam a
## 25–40 m da pista e o meio era areia e pedra. Aqui entra o que costura o lugar: calçada com meio-fio,
## pátio com vagas na frente da lanchonete e do mercado, mobiliário de rua, quintais das casas, a praça
## da vila e o pátio da oficina. Mesmo contrato da beira de estrada (RoadsideBuild): malha por material
## composta uma vez sob a cortina, caixas sólidas, materiais com relevo (RoadsideArt.detail).
## Coordenadas: cada conjunto tem uma âncora (RoadsideLayout.DRESSINGS) com giro 0, então o ponto local
## é o ponto do mundo menos a âncora.
const ART := preload("res://runtime/desert/roadside/RoadsideArt.gd")
const SR := preload("res://runtime/desert/roadside/RoadsideSaltRoad.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const STREET_ANCHOR := Vector3(-200,0,-540)
const HOMES_ANCHOR := Vector3(-242,0,-708)
const VILLAGE_ANCHOR := Vector3(-528,0,-482)
const WORKSHOP_ANCHOR := Vector3(-140,0,-615)

static func _bench(b, at: Vector3, yaw: float) -> void:
	var wood := ART.detail("planks", Color("7a5a3a"), .8)
	var steel := ART.detail("metal", Color("3a3e40"), .5)
	var basis := Basis(Vector3.UP, yaw)
	b.box(wood, Transform3D(basis, at + Vector3(0, .45, 0)), Vector3(1.8, .06, .42), {}, Vector2(1.2, 1.2))
	b.box(wood, Transform3D(basis, at + basis * Vector3(0, .75, -.2)), Vector3(1.8, .3, .05), {}, Vector2(1.2, 1.2))
	for x in [-.75, .75]: b.box(steel, Transform3D(basis, at + basis * Vector3(x, .3, -.05)), Vector3(.06, .6, .45), {"-y": null})
	b.solid(Transform3D(basis, at + Vector3(0, .45, 0)), Vector3(1.8, .9, .5))

static func _planter(b, at: Vector3, tree := false) -> void:
	SR._box(b, ART.detail("plaster", Color("c9b89c")), at + Vector3(0, .3, 0), Vector3(1.1, .6, 1.1), {"-y": null}, Vector2(1.2, 1.2), true)
	SR._box(b, ART.detail("gravel", Color("6a5038")), at + Vector3(0, .61, 0), Vector3(.95, .02, .95), {"-y": null})
	if tree:
		var trunk := ART.detail("planks", Color("6a5038"), .9)
		SR._pipe(b, trunk, at + Vector3(0, .6, 0), at + Vector3(.1, 3.2, 0), .1, 6)
		for k in 5:
			var ang := TAU * float(k) / 5.0
			b.cylinder(ART.color(Color("6f8a45")), SR._t(at.x + cos(ang) * .7, 3.3 + float(k % 2) * .3, at.z + sin(ang) * .7), .75, .5, 7, .2)
	else:
		for k in 3: b.cylinder(ART.color(Color("5f7a3a")), SR._t(at.x - .25 + float(k) * .25, .85, at.z + float(k % 2) * .15), .12, .5, 6, .04)

static func _bin(b, at: Vector3) -> void:
	b.cylinder(ART.detail("metal", Color("3e6b3a"), .5), SR._t(at.x, .45, at.z), .28, .9, 12)
	b.solid(SR._t(at.x, .45, at.z), Vector3(.56, .9, .56))

static func _clothesline(b, a: Vector3, c: Vector3) -> void:
	var post := ART.detail("planks", Color("6e4e32"), .9)
	for p in [a, c]: SR._box(b, post, p + Vector3(0, 1.1, 0), Vector3(.08, 2.2, .08), {"-y": null})
	SR._pipe(b, ART.color(Color("d8d4c8")), a + Vector3(0, 2.0, 0), c + Vector3(0, 2.0, 0), .008, 3)
	var colors := [Color("c63a2a"), Color("2a5f9e"), Color("e4e1d9"), Color("d49a12"), Color("3e6b3a"), Color("8a5a9a")]
	var count := maxi(2, int(a.distance_to(c) / .7))
	for i in count:
		var p := a.lerp(c, (float(i) + .5) / float(count)) + Vector3(0, 1.62, 0)
		var dir := (c - a).normalized()
		b.box(ART.color(colors[(i * 7 + int(a.x)) % colors.size()]), Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) - PI * .5), p), Vector3(.5 + float(i % 3) * .1, .7 - float(i % 2) * .2, .02))

static func _water_tank(b, at: Vector3, height: float) -> void:
	var steel := ART.detail("metal", Color("6c7276"), .55)
	for x in [-.6, .6]:
		for z in [-.6, .6]: SR._box(b, steel, at + Vector3(x, height * .5, z), Vector3(.1, height, .1), {"-y": null})
	SR._box(b, steel, at + Vector3(0, height, 0), Vector3(1.5, .1, 1.5))
	b.cylinder(ART.detail("metal", Color("2a5f9e"), .4), SR._t(at.x, height + .55, at.z), .65, 1.0, 14)
	b.cylinder(ART.detail("metal", Color("2a5f9e"), .4), SR._t(at.x, height + 1.1, at.z), .45, .1, 14)
	b.solid(SR._t(at.x, height * .5, at.z), Vector3(1.4, height, 1.4))

static func _parking_lines(b, at: Vector3, count: int, spacing: float, depth: float) -> void:
	var paint := ART.color(Color("e4e1d9"))
	for k in count + 1: SR._box(b, paint, at + Vector3(float(k) * spacing, .1, depth * .5), Vector3(.12, .01, depth), {"-y": null})

# --- Rua principal ----------------------------------------------------------------------------------

static func compose_town_street(b, _roofs) -> void:
	var walk := ART.detail("pool_tile", Color("bdb3a2"), .85)
	var curb := ART.detail("gravel", Color("9a9284"))
	var pavers := ART.detail("pool_tile", Color("b49a7c"), .8)
	# Calçadas com meio-fio dos dois lados, de x -360 a -40, com as aberturas do lado sul (acesso do
	# banco em x -210, ponto de ônibus em -190..-180, rua do Digo em -110).
	for side in [1.0, -1.0]:
		var spans: Array = [[-160.0, 160.0]] if side > 0.0 else [[-160.0, -15.0], [-10.0, 0.0], [20.0, 84.0], [96.0, 160.0]]
		for span in spans:
			var x0: float = span[0]
			var x1: float = span[1]
			var mid := (x0 + x1) * .5
			var width := x1 - x0
			SR._box(b, walk, Vector3(mid, .07, side * 6.0), Vector3(width, .14, 3.0), {"-y": null}, Vector2(1.5, 1.5))
			SR._box(b, curb, Vector3(mid, .08, side * 4.62), Vector3(width, .16, .24), {"-y": null}, Vector2(1.5, 1.5))
	# Pátio de lajotas entre a calçada norte e a frente da lanchonete e do mercado, com vagas.
	SR._box(b, pavers, Vector3(-35, .05, 12.5), Vector3(100, .1, 9.5), {"-y": null}, Vector2(1.2, 1.2))
	_parking_lines(b, Vector3(-66, 0, 8.6), 4, 3.0, 4.6)
	_parking_lines(b, Vector3(-27, 0, 8.6), 4, 3.0, 4.6)
	# Mobiliário: bancos, floreiras, lixeiras, orelhão e jornaleiro na calçada norte; árvores em
	# floreira na calçada sul (fora das aberturas).
	for x in [-140.0, -95.0, -40.0, 5.0, 60.0, 115.0]:
		_bench(b, Vector3(x, .14, 6.9), PI)
		_planter(b, Vector3(x + 3.0, .14, 6.8))
		_bin(b, Vector3(x - 2.4, .14, 6.9))
	for x in [-130.0, -75.0, -30.0, 45.0, 110.0, 150.0]: _planter(b, Vector3(x, .14, -6.6), true)
	var orange := ART.detail("metal", Color("d9661e"), .5)
	b.cylinder(ART.detail("metal", Color("8d9193"), .5), SR._t(-12.0, 1.34, 7.2), .06, 2.4, 8)
	b.shell(orange, SR._t(-12.0, 1.86, 7.0), Vector3(.52, .62, .55), 12, 5)
	SR._box(b, ART.detail("metal", Color("2a5f9e"), .45), Vector3(-9.0, .74, 7.1), Vector3(.6, 1.2, .5), {"-y": null}, Vector2(.6, 1.2), true)
	SR._box(b, ART.color(Color("e8e4da")), Vector3(-9.0, 1.1, 6.84), Vector3(.5, .3, .02))
	# Placa alta do Rádio Sol na entrada leste e faixa do Pneus Veloz na oeste.
	SR._post_sign(b, ART.color(Color("2e3032")), Vector3(150.0, 4.2, 10.5), Vector3(6.4, 1.0, .12), "banner_radio", 5.0)
	SR._post_sign(b, ART.color(Color("2e3032")), Vector3(-150.0, 4.2, -10.5), Vector3(6.4, 1.0, .12), "banner_tire", 5.0)

# --- Casas (duas fileiras ao sul) ------------------------------------------------------------------

static func compose_homes_yards(b, _roofs) -> void:
	var post := ART.detail("planks", Color("7a5a3a"), .85)
	var soil := ART.detail("gravel", Color("7a6248"))
	var green := ART.color(Color("5f7a3a"))
	for i in 10:
		var home := Vector3(-300.0 + float(i % 5) * 29.0, 0, -690.0 - float(floori(i / 5.0)) * 37.0) - HOMES_ANCHOR
		var half := (14.0 + float(i % 3) * 2.0) * .5
		var back := home.z - 5.5
		# Cerca de tábuas no quintal dos fundos (fundo e dois lados), com um vão de portão.
		var depth := 7.0
		var rails := [[Vector3(home.x - half - .4, 0, back - depth), Vector3(home.x + half + .4, 0, back - depth)],
			[Vector3(home.x - half - .4, 0, back - depth), Vector3(home.x - half - .4, 0, back - .2)],
			[Vector3(home.x + half + .4, 0, back - depth), Vector3(home.x + half + .4, 0, back - 2.0)]]
		for run in rails:
			var a: Vector3 = run[0]
			var c: Vector3 = run[1]
			var count := maxi(1, roundi(a.distance_to(c) / 1.6))
			for k in count + 1: SR._box(b, post, a.lerp(c, float(k) / float(count)) + Vector3(0, .65, 0), Vector3(.1, 1.3, .1), {"-y": null})
			for h in [.45, 1.0]:
				var mid := (a + c) * .5
				SR._box(b, post, mid + Vector3(0, h, 0), Vector3(maxf(absf(c.x - a.x), .05), .12, maxf(absf(c.z - a.z), .05)), {}, Vector2(1.2, 1.2))
			var center := (a + c) * .5
			b.solid(SR._t(center.x, .65, center.z), Vector3(maxf(absf(c.x - a.x), .12), 1.3, maxf(absf(c.z - a.z), .12)))
		# Varal, caixa-d'água, horta e vasos.
		_clothesline(b, Vector3(home.x - half + 1.5, 0, back - 4.5), Vector3(home.x - 1.0, 0, back - 4.5))
		_water_tank(b, Vector3(home.x + half - 1.2, 0, back - 5.6), 2.8 + float(i % 2) * .6)
		SR._box(b, soil, Vector3(home.x + 2.5, .1, back - 2.6), Vector3(3.0, .2, 1.4), {"-y": null}, Vector2(1.2, 1.2))
		for k in 6: b.cylinder(green, SR._t(home.x + 1.3 + float(k) * .48, .35, back - 2.6 + float(k % 2) * .3), .14, .35, 6, .03)
		b.cylinder(ART.detail("plaster", Color("b5654a")), SR._t(home.x - half + 1.0, .25, home.z + 6.2), .25, .5, 10, .3)
		b.cylinder(green, SR._t(home.x - half + 1.0, .7, home.z + 6.2), .3, .5, 7, .05)
		# Antena parabólica no telhado.
		var roof_h := 3.0 + float(i % 2) * .5
		b.cylinder(ART.detail("metal", Color("d8d4c8"), .4), Transform3D(Basis(Vector3.RIGHT, PI * .5 - .5), home + Vector3(half - 1.5, roof_h + .6, -2.0)), .45, .18, 12, .3)
		SR._box(b, ART.color(Color("8d9193")), home + Vector3(half - 1.5, roof_h + .25, -2.0), Vector3(.06, .5, .06), {"-y": null})

# --- Praça da vila Santa Lua -------------------------------------------------------------------------

static func compose_village_square(b, _roofs) -> void:
	var stone := ART.detail("gravel", Color("b8ad98"))
	var wood := ART.detail("planks", Color("6e4e32"), .85)
	var dark := ART.color(Color("2e3032"))
	var clay := ART.detail("clay_tile", Color("b4583e"), .8)
	SR._box(b, stone, Vector3(0, .04, -7), Vector3(14, .08, 14), {"-y": null}, Vector2(2, 2))
	# Poço com mureta de pedra, dois esteios, sarilho e telhadinho de barro.
	b.cylinder(stone, SR._t(0, .4, -7), 1.1, .8, 16)
	b.cylinder(ART.color(Color("1a1c1c")), SR._t(0, .81, -7), .85, .02, 16)
	b.solid(SR._t(0, .4, -7), Vector3(2.2, .8, 2.2))
	for x in [-1.0, 1.0]: SR._box(b, wood, Vector3(x, 1.3, -7), Vector3(.14, 2.6, .14), {"-y": null})
	b.cylinder(wood, Transform3D(Basis(Vector3.FORWARD, PI * .5), Vector3(0, 1.8, -7)), .1, 2.0, 8)
	SR._pipe(b, ART.color(Color("8d7a5a")), Vector3(0, 1.75, -7), Vector3(0, 1.1, -7), .01, 3)
	b.cylinder(ART.detail("metal", Color("8d9193"), .5), SR._t(0, 1.0, -7), .15, .25, 10, .18)
	for side in [-1.0, 1.0]:
		b.box(clay, Transform3D(Basis(Vector3.FORWARD, side * deg_to_rad(-28)), Vector3(side * .55, 2.85, -7)), Vector3(1.3, .08, 1.5), {}, Vector2(1.6, 1.6))
	# Duas barracas de feira com toldo de lona, mesa e caixotes de frutas e verduras.
	var produce := [Color("d9661e"), Color("c63a2a"), Color("6f8a45"), Color("e8c040"), Color("8a5a9a")]
	for stall in [[Vector3(0, 0, -17), Color("c63a2a")], [Vector3(0, 0, 3.5), Color("2a5f9e")]]:
		var at: Vector3 = stall[0]
		for x in [-1.4, 1.4]:
			for z in [-.8, .8]: SR._box(b, wood, at + Vector3(x, 1.1, z), Vector3(.08, 2.2, .08), {"-y": null})
		b.box(ART.detail("plaster", stall[1]), SR._t(at.x, 2.25, at.z, 0, .12), Vector3(3.2, .05, 2.0))
		SR._box(b, wood, at + Vector3(0, .8, 0), Vector3(2.8, .06, 1.4), {}, Vector2(1.2, 1.2))
		b.solid(SR._t(at.x, .4, at.z), Vector3(2.8, .8, 1.4))
		for k in 4:
			var crate := at + Vector3(-1.05 + float(k) * .7, .9, 0)
			SR._box(b, ART.detail("crate", Color("b08a5a"), .85), crate, Vector3(.6, .2, .45), {"-y": null}, Vector2(.6, .2))
			b.cylinder(ART.color(produce[(k + int(at.z)) % produce.size()]), SR._t(crate.x, 1.06, crate.z), .26, .14, 8, .12)
	# Carroça de madeira encostada perto da barraca do norte.
	var cart := Vector3(4.5, 0, -18.5)
	SR._box(b, wood, cart + Vector3(0, .8, 0), Vector3(1.4, .5, 2.2), {"-y": null}, Vector2(1.2, 1.2))
	for side in [-1.0, 1.0]: b.cylinder(wood, Transform3D(Basis(Vector3.FORWARD, PI * .5), cart + Vector3(side * .8, .55, .2)), .55, .1, 12)
	SR._beam(b, wood, cart + Vector3(-.3, .75, 1.1), cart + Vector3(-.3, .2, 2.6), .07)
	SR._beam(b, wood, cart + Vector3(.3, .75, 1.1), cart + Vector3(.3, .2, 2.6), .07)
	b.solid(SR._t(cart.x, .7, cart.z), Vector3(1.6, 1.4, 2.4))
	# Varais atrás das casas do oeste, caixa-d'água comunitária e o cordão de lâmpadas da praça.
	_clothesline(b, Vector3(-30, 0, -24), Vector3(-30, 0, -15))
	_clothesline(b, Vector3(30, 0, 1), Vector3(30, 0, 10))
	_water_tank(b, Vector3(-12, 0, -24), 4.5)
	var poles := [Vector3(-8, 0, -14), Vector3(8, 0, -14), Vector3(8, 0, 0), Vector3(-8, 0, 0)]
	for pole in poles: SR._box(b, wood, pole + Vector3(0, 1.8, 0), Vector3(.12, 3.6, .12), {"-y": null}, Vector2(2, 2), true)
	for k in poles.size():
		var a: Vector3 = poles[k] + Vector3(0, 3.5, 0)
		var c: Vector3 = poles[(k + 1) % poles.size()] + Vector3(0, 3.5, 0)
		var steps := maxi(4, roundi(a.distance_to(c) / 1.4))
		var previous := a
		for i in range(1, steps + 1):
			var t := float(i) / float(steps)
			var point := a.lerp(c, t) + Vector3(0, -.6 * 4.0 * t * (1.0 - t), 0)
			SR._pipe(b, dark, previous, point, .008, 3)
			if i < steps: b.box(b.atlas, SR._t(point.x, point.y - .07, point.z), Vector3(.09, .11, .09), {"+z": ART.uv("light"), "-z": ART.uv("light"), "+x": ART.uv("light"), "-x": ART.uv("light"), "+y": null, "-y": ART.uv("light")})
			previous = point

# --- Pátio da oficina do Digo --------------------------------------------------------------------------
## O prédio vai de x -12,5 a 12,5 e de z -9 a 9 (frente +z). A frente fica livre (x ±6): é por ali que
## o carro entra e sai (DesertLayout.place_definitions, vehicle_exit e vehicle_return).

static func compose_workshop_yard(b, _roofs) -> void:
	var rubber := ART.color(Color("1c1c1b"))
	var rim := ART.detail("metal", Color("8d9193"), .4)
	var steel := ART.detail("metal", Color("5e6366"), .5)
	var red := ART.detail("metal", Color("a52a1d"), .5)
	var wood := ART.detail("planks", Color("7a5a3a"), .85)
	var dark := ART.color(Color("2e3032"))
	SR._box(b, ART.detail("gravel", Color("8c8070")), Vector3(-17, .03, 1), Vector3(9, .06, 18), {"-y": null}, Vector2(2.5, 2.5))
	SR._box(b, ART.detail("gravel", Color("8c8070")), Vector3(17, .03, 1), Vector3(9, .06, 18), {"-y": null}, Vector2(2.5, 2.5))
	# Lado oeste: pilhas de pneus, tambores, motor no cavalete, bancada e a carcaça nos blocos.
	for spot in [Vector3(-14.5, 0, 8.0), Vector3(-15.4, 0, 7.4), Vector3(-14.8, 0, 6.5), Vector3(-19.5, 0, -6.0)]:
		for k in 3 + int(absf(spot.x)) % 2: b.cylinder(rubber, SR._t(spot.x + float(k % 2) * .05, .13 + float(k) * .25, spot.z), .38, .24, 12)
		b.cylinder(rim, SR._t(spot.x, .9, spot.z), .2, .01, 10)
	b.solid(SR._t(-14.9, .5, 7.3), Vector3(1.9, 1.0, 2.3))
	for k in 4:
		var drum := Vector3(-19.8 + float(k % 2) * .62, 0, 2.0 + float(k / 2) * .62)
		b.cylinder(ART.detail("metal", [Color("2a5f9e"), Color("8e4a2c"), Color("3e6b3a"), Color("8e4a2c")][k], .5), SR._t(drum.x, .45, drum.z), .29, .9, 12)
	b.solid(SR._t(-19.5, .45, 2.3), Vector3(1.3, .9, 1.3))
	var stand := Vector3(-16.0, 0, 3.0)
	SR._box(b, red, stand + Vector3(0, .45, 0), Vector3(.5, .9, .5), {"-y": null})
	SR._box(b, steel, stand + Vector3(0, 1.15, 0), Vector3(.8, .55, .65))
	SR._box(b, dark, stand + Vector3(0, 1.5, 0), Vector3(.55, .15, .55))
	b.solid(SR._t(stand.x, .7, stand.z), Vector3(.8, 1.4, .7))
	SR._box(b, wood, Vector3(-20.5, .95, -2.5), Vector3(.8, .08, 2.6), {}, Vector2(1.2, 1.2))
	SR._box(b, steel, Vector3(-20.5, .46, -2.5), Vector3(.7, .92, 2.5), {"-y": null}, Vector2(.7, .92), true)
	for k in 5: SR._box(b, ART.color([Color("a52a1d"), Color("d49a12"), Color("8d9193"), Color("2a5f9e"), Color("3e6b3a")][k]), Vector3(-20.4, 1.08, -3.5 + float(k) * .45), Vector3(.25, .18, .2))
	for x in [-.7, .7]:
		for z in [-1.4, 1.4]: SR._box(b, ART.detail("gravel", Color("8d9193")), Vector3(-16.5 + x, .14, -4.5 + z), Vector3(.35, .28, .35), {"-y": null})
	# Lado leste: compressor, cavaletes, portas e capôs encostados (os carros de cliente estacionam aqui).
	b.cylinder(red, SR._t(13.6, .42, -6.5, 0, 0, PI * .5), .3, 1.2, 12)
	SR._box(b, dark, Vector3(13.6, .85, -6.5), Vector3(.6, .35, .4), {"-y": null})
	b.solid(SR._t(13.6, .5, -6.5), Vector3(1.3, 1.0, .7))
	var doors := [Color("8e4a2c"), Color("4b6176"), Color("c6c4bd"), Color("6f7a52")]
	for k in doors.size():
		b.box(ART.detail("metal", doors[k], .5), SR._t(20.6 - float(k) * .1, .62, -6.5 + float(k) * .6, PI * .5, 0, -.2), Vector3(1.1, 1.2, .06), {"-y": null})
	b.solid(SR._t(20.4, .6, -5.6), Vector3(.6, 1.2, 2.6))
	SR._post_sign(b, dark, Vector3(17.0, 2.2, 9.6), Vector3(4.6, .7, .1), "banner_tire", 2.8)
