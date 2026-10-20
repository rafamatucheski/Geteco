extends RefCounted
## Fachadas e telhados dos prédios antigos da cidade do deserto (banco, lanchonete, mercado, motel
## Horizonte, oficina do Digo), 20/10/2026. As caixas de DesertArchitecture ficam como estão (outra
## sessão mexe nelas); aqui entra por cima, alinhado com as mesmas medidas (DesertLayout.buildings):
## cornija, rodapé encardido, escorridos de chuva, peitoril, calhas, letreiro próprio de cada prédio,
## toldos listrados e o telhado (que é o que a câmera de cima mais vê): platibanda dos fundos, remendos
## de manta, respiros, caixa-d'água, aquecedor solar, antena e claraboia.
## Coordenadas locais do prédio, frente +z (lanchonete e mercado giram PI, como no DesertArchitecture).
const ART := preload("res://runtime/desert/roadside/RoadsideArt.gd")
const SR := preload("res://runtime/desert/roadside/RoadsideSaltRoad.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
## kind do conjunto → id do prédio em DesertLayout.buildings().
const BUILDINGS := {"facade_bank": "desert_bank", "facade_diner": "desert_diner", "facade_market": "desert_market",
	"facade_motel": "desert_motel", "facade_digo": "desert_digo"}

static func building(kind: String) -> Dictionary:
	for data in LAYOUT.buildings():
		if str(data.id) == str(BUILDINGS.get(kind, "")): return data
	return {}

static func compose(b, kind: String) -> void:
	var data := building(kind)
	if data.is_empty(): return
	var size: Vector3 = data.size
	var wall: Color = data.color
	_walls(b, data, size, wall)
	_roof(b, data, size, wall)
	match str(data.kind):
		"bank": _bank(b, size)
		"diner": _diner(b, size)
		"shop": _market(b, size)
		"motel": _motel(b, size)
		"workshop": _digo(b, size)

# --- Paredes -----------------------------------------------------------------------------------------

static func _walls(b, data: Dictionary, size: Vector3, wall: Color) -> void:
	var front := size.z * .5 + .2
	var light := ART.detail("plaster", wall.lightened(.18))
	var grime := ART.detail("plaster", wall.darkened(.32))
	var streak := ART.detail("plaster", wall.darkened(.16))
	var metal := ART.detail("metal", Color("8d9193"), .5)
	var entry := 5.4 if data.kind == "workshop" else 2.4
	# Cornija logo abaixo da platibanda, na frente e nos lados.
	SR._box(b, light, Vector3(0, size.y - .12, front + .06), Vector3(size.x + .5, .22, .14), {"-y": null})
	for side in [-1.0, 1.0]: SR._box(b, light, Vector3(side * (size.x * .5 + .26), size.y - .12, 0), Vector3(.14, .22, size.z + .4), {"-y": null})
	# Rodapé encardido (meio metro de respingo de terra) em volta, aberto na porta.
	var segment := (size.x - entry) * .5
	for side in [-1.0, 1.0]:
		SR._box(b, grime, Vector3(side * (entry * .5 + segment * .5), .26, front + .04), Vector3(segment, .52, .08), {"-y": null}, Vector2(1.5, 1.5))
		SR._box(b, grime, Vector3(side * (size.x * .5 + .24), .26, 0), Vector3(.08, .52, size.z + .4), {"-y": null}, Vector2(1.5, 1.5))
	SR._box(b, grime, Vector3(0, .26, -size.z * .5 - .24), Vector3(size.x + .4, .52, .08), {"-y": null}, Vector2(1.5, 1.5))
	# Escorridos de chuva descendo da platibanda, na frente e nos lados.
	var count := int(size.x / 3.6)
	for k in count:
		var x := -size.x * .5 + 1.2 + float(k) * size.x / float(count)
		if absf(x) < entry * .5 + .4: continue
		var length := .7 + float((k * 7) % 5) * .22
		SR._box(b, streak, Vector3(x, size.y - .3 - length * .5, front + .015), Vector3(.16 + float(k % 3) * .06, length, .02))
	for side in [-1.0, 1.0]:
		for k in int(size.z / 4.0):
			var z := -size.z * .5 + 2.0 + float(k) * 4.0
			var length := .6 + float((k * 5) % 4) * .25
			SR._box(b, streak, Vector3(side * (size.x * .5 + .215), size.y - .3 - length * .5, z), Vector3(.02, length, .18))
	# Fundos: lanchonete e mercado dão a frente para a rua, então é a parede de trás que a câmera vê.
	var back := -size.z * .5 - .2
	for k in count:
		var x := -size.x * .5 + 1.6 + float(k) * size.x / float(count)
		var length := .8 + float((k * 3) % 5) * .2
		SR._box(b, streak, Vector3(x, size.y - .3 - length * .5, back - .015), Vector3(.16 + float(k % 2) * .08, length, .02))
	var service := ART.detail("metal", Color("6c5a44"), .6)
	SR._box(b, light, Vector3(size.x * .2, 1.12, back - .05), Vector3(1.3, 2.24, .1), {"-y": null})
	SR._box(b, service, Vector3(size.x * .2, 1.05, back - .11), Vector3(1.0, 2.05, .04))
	SR._box(b, light, Vector3(size.x * .2, 2.4, back - .3), Vector3(1.6, .08, .6))
	SR._box(b, ART.detail("metal", Color("a8aaa6"), .5), Vector3(-size.x * .3, 1.5, back - .12), Vector3(.5, .7, .2))
	SR._pipe(b, metal, Vector3(-size.x * .3, 1.15, back - .12), Vector3(-size.x * .3, .2, back - .12), .04, 6)
	# Peitoril saliente nas duas janelas da frente (DesertArchitecture: x = ±30 % da largura, y 1,65).
	if data.kind != "workshop":
		for side in [-1.0, 1.0]:
			SR._box(b, light, Vector3(side * size.x * .30, .9, front + .14), Vector3(2.7, .08, .26))
	# Calhas nas quinas da frente, com a curva de saída no chão.
	for side in [-1.0, 1.0]:
		var x: float = side * (size.x * .5 - .1)
		SR._pipe(b, metal, Vector3(x, size.y + .4, front + .1), Vector3(x, .25, front + .1), .06, 8)
		SR._pipe(b, metal, Vector3(x, .25, front + .1), Vector3(x, .08, front + .4), .06, 8)

# --- Telhado ------------------------------------------------------------------------------------------

static func _roof(b, data: Dictionary, size: Vector3, wall: Color) -> void:
	var top := size.y + .24
	var cap := ART.detail("metal", Color("d8d4c8"), .55)
	var patch := ART.detail("gravel", Color("5e5648"))
	var steel := ART.detail("metal", Color("8d9193"), .5)
	var dark := ART.color(Color("2e3032"))
	# Platibanda dos fundos (só havia a da frente e as dos lados) e o rufo claro por cima de todas.
	SR._box(b, ART.detail("plaster", wall), Vector3(0, size.y + .35, -size.z * .5 - .2), Vector3(size.x + .6, .55, .22), {"-y": null}, Vector2(1.5, 1.5))
	SR._box(b, cap, Vector3(0, size.y + .65, size.z * .5 + .2), Vector3(size.x + .7, .06, .3))
	SR._box(b, cap, Vector3(0, size.y + .65, -size.z * .5 - .2), Vector3(size.x + .7, .06, .3))
	for side in [-1.0, 1.0]: SR._box(b, cap, Vector3(side * (size.x * .5 + .1), size.y + .65, 0), Vector3(.3, .06, size.z + .7))
	# Remendos de manta (retângulos mais escuros) espalhados pela laje.
	var seed := int(absf(size.x * 13.0 + size.z * 7.0))
	for k in 4:
		var px := (float((seed + k * 37) % 100) / 100.0 - .5) * (size.x - 4.0)
		var pz := (float((seed + k * 53) % 100) / 100.0 - .5) * (size.z - 4.0)
		SR._box(b, patch, Vector3(px, top + .015, pz), Vector3(1.6 + float(k % 3) * .9, .03, 1.1 + float(k % 2) * .8), {"-y": null}, Vector2(1.5, 1.5))
	# Respiros com chapéu, conduíte correndo pela laje.
	for k in 3:
		var at := Vector3(-size.x * .25 + float(k) * size.x * .22, top, size.z * .12 - float(k % 2) * size.z * .3)
		b.cylinder(steel, SR._t(at.x, at.y + .3, at.z), .1, .6, 8)
		b.cylinder(steel, SR._t(at.x, at.y + .66, at.z), .2, .1, 8, .05)
	SR._pipe(b, dark, Vector3(-size.x * .45, top + .05, -size.z * .4), Vector3(size.x * .45, top + .05, -size.z * .4), .03, 4)
	# Caixa-d'água no apoio, aquecedor solar inclinado e antena parabólica.
	var tank := Vector3(-size.x * .32, top, -size.z * .22)
	for x in [-.55, .55]:
		for z in [-.55, .55]: SR._box(b, steel, tank + Vector3(x, .4, z), Vector3(.08, .8, .08), {"-y": null})
	b.cylinder(ART.detail("metal", Color("2a5f9e"), .4), SR._t(tank.x, tank.y + 1.3, tank.z), .75, 1.0, 14)
	b.cylinder(ART.detail("metal", Color("2a5f9e"), .4), SR._t(tank.x, tank.y + 1.85, tank.z), .5, .1, 14)
	var solar := Vector3(size.x * .05, top, -size.z * .3)
	b.box(ART.detail("metal", Color("1e2c40"), .2), SR._t(solar.x, solar.y + .55, solar.z, 0, deg_to_rad(-25)), Vector3(2.0, .06, 1.2))
	SR._box(b, steel, solar + Vector3(0, .5, -.55), Vector3(2.0, .08, .08))
	b.cylinder(ART.detail("metal", Color("c6c4bd"), .4), Transform3D(Basis(Vector3.FORWARD, PI * .5), solar + Vector3(0, 1.05, -.6)), .2, 1.9, 10)
	b.cylinder(ART.detail("metal", Color("d8d4c8"), .4), Transform3D(Basis(Vector3.RIGHT, PI * .5 - .5), Vector3(size.x * .4, top + .8, size.z * .3)), .5, .18, 12, .32)
	SR._box(b, steel, Vector3(size.x * .4, top + .35, size.z * .3), Vector3(.06, .7, .06), {"-y": null})
	# Claraboia de vidro e alçapão.
	var glass := ART.detail("metal", Color("8fb4bb"), .1)
	SR._box(b, ART.detail("plaster", wall), Vector3(size.x * .18, top + .15, size.z * .05), Vector3(1.6, .3, 1.2), {"-y": null})
	SR._box(b, glass, Vector3(size.x * .18, top + .32, size.z * .05), Vector3(1.4, .04, 1.0))
	SR._box(b, ART.detail("metal", Color("6c7276"), .5), Vector3(-size.x * .1, top + .1, size.z * .25), Vector3(.9, .2, .9), {"-y": null})

# --- Por prédio ---------------------------------------------------------------------------------------

static func _awning(b, at: Vector3, width: float, depth: float, colors: Array) -> void:
	var stripes := maxi(4, int(width / .5))
	var w := width / float(stripes)
	for k in stripes:
		var mat: Material = ART.detail("plaster", colors[k % colors.size()])
		b.box(mat, SR._t(at.x - width * .5 + w * (float(k) + .5), at.y, at.z + depth * .5, 0, deg_to_rad(18)), Vector3(w, .04, depth))
		b.box(mat, SR._t(at.x - width * .5 + w * (float(k) + .5), at.y - .22 - sin(deg_to_rad(18)) * depth * .5 + .04, at.z + depth * cos(deg_to_rad(18)) + .01), Vector3(w, .3, .02))
	for side in [-1.0, 1.0]:
		SR._beam(b, ART.detail("metal", Color("3a3e40"), .5), at + Vector3(side * width * .5, -.05, 0), at + Vector3(side * width * .5, -sin(deg_to_rad(18)) * depth, depth * cos(deg_to_rad(18))), .04)

static func _bank(b, size: Vector3) -> void:
	var front := size.z * .5 + .2
	b.quad(b.atlas, Vector3(-4.6, 2.05, front + .03), Vector3(.9, 0, 0), Vector3(0, .3, 0), ART.uv("bank_plaque"))
	# Caixa eletrônico embutido na parede, ao lado da porta.
	SR._box(b, ART.detail("metal", Color("5a5e62"), .5), Vector3(4.6, 1.05, front + .16), Vector3(.9, 1.8, .3), {"-y": null}, Vector2(.9, 1.8), true)
	b.quad(b.atlas, Vector3(4.6, 1.05, front + .32), Vector3(.36, 0, 0), Vector3(0, .63, 0), ART.uv("atm"))
	SR._box(b, ART.detail("metal", Color("85603d"), .4), Vector3(4.6, 2.0, front + .45), Vector3(1.1, .08, .6))
	# Grades nas janelas e câmeras nas quinas.
	var bar := ART.detail("metal", Color("2e3032"), .5)
	for side in [-1.0, 1.0]:
		for k in 7: SR._box(b, bar, Vector3(side * size.x * .30 - 1.05 + float(k) * .35, 1.65, front + .36), Vector3(.03, 1.3, .03))
		SR._box(b, bar, Vector3(side * size.x * .30, 2.28, front + .36), Vector3(2.3, .04, .04))
		SR._box(b, ART.detail("metal", Color("e4e1d9"), .4), Vector3(side * (size.x * .5 - .3), size.y - .45, front + .2), Vector3(.18, .14, .3))
		SR._box(b, ART.color(Color("1a1c1c")), Vector3(side * (size.x * .5 - .3), size.y - .45, front + .36), Vector3(.08, .08, .02))

static func _diner(b, size: Vector3) -> void:
	var front := size.z * .5 + .2
	# Letreiro de neon no telhado, sobre duas pernas, com as duas faces.
	for side in [-1.0, 1.0]: SR._box(b, ART.detail("metal", Color("3a3e40"), .5), Vector3(side * 2.2, size.y + .9, front - 1.2), Vector3(.12, 1.3, .12), {"-y": null})
	var rect := ART.uv("diner_neon")
	b.box(ART.color(Color("2e3032")), SR._t(0, size.y + 2.3, front - 1.2), Vector3(5.0, 1.9, .12), {"+z": rect, "-z": rect})
	_awning(b, Vector3(0, 2.9, front + .1), 3.4, 1.3, [Color("c63a2a"), Color("f1ede2")])
	b.quad(b.atlas, Vector3(2.4, 1.45, front + .03), Vector3(.32, 0, 0), Vector3(0, .48, 0), ART.uv("menu"))

static func _market(b, size: Vector3) -> void:
	var front := size.z * .5 + .2
	# Pintura de parede no lado −x local, que com o giro PI vira o lado leste: a câmera do jogo só vê
	# as faces leste e sul, a oeste nunca aparece.
	b.quad(b.atlas, Vector3(-size.x * .5 - .23, 1.95, 0), Vector3(0, 0, 3.8), Vector3(0, 1.5, 0), ART.uv("market_wall"))
	_awning(b, Vector3(0, 2.8, front + .1), 3.4, 1.2, [Color("3e6b3a"), Color("f1ede2")])
	# Gaiola de botijões na lateral da frente.
	var cage := Vector3(size.x * .5 - 1.2, 0, front + 1.0)
	var steel := ART.detail("metal", Color("6c7276"), .5)
	for x in [-.6, .6]:
		for z in [-.4, .4]: SR._box(b, steel, cage + Vector3(x, .7, z), Vector3(.05, 1.4, .05), {"-y": null})
	for h in [.1, .7, 1.4]: SR._box(b, steel, cage + Vector3(0, h, .4), Vector3(1.25, .04, .04))
	for k in 3: b.cylinder(ART.detail("metal", Color("2a5f9e"), .45), SR._t(cage.x - .4 + float(k) * .4, .38, cage.z), .16, .7, 10)
	b.solid(SR._t(cage.x, .7, cage.z), Vector3(1.3, 1.4, .9))

static func _motel(b, size: Vector3) -> void:
	var front := size.z * .5 + .2
	for side in [-1.0, 1.0]: SR._box(b, ART.detail("metal", Color("3a3e40"), .5), Vector3(side * 3.0, size.y + .95, -1.0), Vector3(.14, 1.4, .14), {"-y": null})
	var rect := ART.uv("horizonte_sign")
	b.box(ART.color(Color("2e3032")), SR._t(0, size.y + 2.3, -1.0), Vector3(7.0, 1.75, .14), {"+z": rect, "-z": rect})
	# Número de cada quarto em cima da porta e um ar-condicionado de parede entre as portas.
	for i in 6:
		var x := -14.0 + float(i) * 5.5
		b.quad(b.atlas, Vector3(x, 2.42, front + .08), Vector3(.18, 0, 0), Vector3(0, .12, 0), ART.uv_span("room_numbers", float(i) / 6.0, float(i + 1) / 6.0))
		if i < 5:
			SR._box(b, ART.detail("metal", Color("c6c4bd"), .5), Vector3(x + 2.75, 2.1, front + .2), Vector3(.7, .45, .4))
			SR._box(b, ART.color(Color("2e3032")), Vector3(x + 2.75, 2.1, front + .41), Vector3(.6, .3, .02))

static func _digo(b, size: Vector3) -> void:
	# Pintura de parede no lado leste (o oeste a câmera não vê) e exaustores no telhado da oficina.
	b.quad(b.atlas, Vector3(size.x * .5 + .23, 2.4, 0), Vector3(0, 0, -5.4), Vector3(0, 1.8, 0), ART.uv("digo_wall"))
	var top := size.y + .24
	var steel := ART.detail("metal", Color("8d9193"), .45)
	for k in 2:
		var fan := Vector3(-4.0 + float(k) * 8.0, top, -2.5)
		SR._box(b, steel, fan + Vector3(0, .3, 0), Vector3(1.2, .6, 1.2), {"-y": null})
		b.cylinder(ART.color(Color("2e3032")), SR._t(fan.x, fan.y + .62, fan.z), .45, .04, 14)
		for r in 4: SR._box(b, steel, fan + Vector3(0, .66, 0), Vector3(.9, .02, .06) if r % 2 == 0 else Vector3(.06, .02, .9))
