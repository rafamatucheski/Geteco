extends RefCounted
## Malhas das peças que enchem a calçada (SidewalkFill): árvore de rua e o que o
## térreo põe para fora (mesa de bar, banca de fruta, cavalete, lixeiras da casa,
## paletes da oficina). Mesma convenção do CityPropKit: uma ArrayMesh por tipo, cor
## por vértice, origem no chão, frente (+Z) virada para a rua e X ao longo da
## fachada. Tudo usa o material do kit ou as superfícies de flora que vaso e
## árvore do porto já usam: nenhum shader novo para pré-aquecer.

const KIT := preload("res://world/city_look/CityPropKit.gd")
const WOOD := preload("res://world/urban_detail/StreetTreeWood.gd")

const KINDS := ["cafe_set", "cafe_parasol", "cafe_parasol_b", "produce_stand", "a_frame", "beer_crates", "wheelie_bins", "bike_rack", "pallet_stack", "tire_stack", "drums",
	"food_cart", "ice_freezer", "clothes_rack", "flower_buckets", "gas_cylinders", "door_bench", "motorcycle"]

# Verdes da copa: os do porto (#46583a das árvores autorais) com um pouco mais de
# luz, porque vista de cima a copa inteira fica na sombra da própria folhagem.
const CROWN_GREENS := ["4f6340", "566b45", "48593b", "5c6e46", "4b5e3f"]
const RED_PLASTIC := Color("b0362c")
const WHITE_PLASTIC := Color("d9d6cc")
const CRATE_WOOD := Color("9a7a4f")


static func build(kind: String, t: SurfaceTool) -> void:
	match kind:
		"cafe_set": _cafe_set(t)
		"cafe_parasol": _cafe_parasol(t, Color("c23b2e"))
		"cafe_parasol_b": _cafe_parasol(t, Color("2f7a55"))
		"produce_stand": _produce_stand(t)
		"a_frame": _a_frame(t)
		"beer_crates": _beer_crates(t)
		"wheelie_bins": _wheelie_bins(t)
		"bike_rack": _bike_rack(t)
		"pallet_stack": _pallet_stack(t)
		"tire_stack": _tire_stack(t)
		"drums": _drums(t)
		"food_cart": _food_cart(t)
		"ice_freezer": _ice_freezer(t)
		"clothes_rack": _clothes_rack(t)
		"flower_buckets": _flower_buckets(t)
		"gas_cylinders": _gas_cylinders(t)
		"door_bench": _door_bench(t)
		"motorcycle": _motorcycle(t)


## Camada de um tipo em camadas (CityPropKit.LAYERED).
static func build_layer(kind: String, layer: String, t: SurfaceTool) -> void:
	match kind + ":" + layer:
		"street_tree:bark": _tree_wood(t, 0)
		"street_tree:leaves": _tree_crown(t, 0)
		"street_tree_b:bark": _tree_wood(t, 1)
		"street_tree_b:leaves": _tree_crown(t, 1)
		"pot_plant:stone": _pot(t)
		"pot_plant:leaves": _pot_leaves(t)


# --- Árvore de rua ---

## Tronco das árvores do porto (StreetTreeWood, 3 m) esticado: a copa da árvore de
## calçada fica mais alta para o carro e o pedestre passarem por baixo.
static func _tree_wood(t: SurfaceTool, variant: int) -> void:
	var height := 1.25 if variant == 0 else 1.4
	t.append_from(WOOD.mesh(), 0, Transform3D(Basis(Vector3.UP, 0.7 * variant).scaled(Vector3(0.95, height, 0.95)), Vector3.ZERO))


## Copa em três ou quatro volumes no contorno da StreetTreeCanopy, com os verdes no vértice
## (a camada "leaves" usa cor de vértice sRGB, como o vaso). Normais suaves: com
## facetas a copa lia como pedra.
static func _tree_crown(t: SurfaceTool, variant: int) -> void:
	t.set_smooth_group(0)
	var top := 3.75 if variant == 0 else 4.2
	var lobes := [[Vector3(-.62, 0, .05), 1.15], [Vector3(.55, .22, .12), 1.1], [Vector3(0, .5, -.4), 1.05], [Vector3(.08, -.08, .62), 1.0]]
	if variant == 1: lobes = [[Vector3(-.3, 0, .1), 1.2], [Vector3(.35, .35, -.15), 1.15], [Vector3(-.05, .95, .05), .95]]
	for index in lobes.size():
		var center: Vector3 = Vector3(0, top, 0) + lobes[index][0]
		var radius: float = lobes[index][1]
		var scale := Vector3(radius, radius * 0.86, radius * 0.95)
		var basis := Basis(Vector3.UP, float(index * 2 + variant) * 0.73).scaled(scale)
		var seed := index + variant * 3
		for ring in CROWN_RINGS:
			for side in CROWN_SIDES:
				var a := basis * _crown_point(ring, side, seed) + center
				var b := basis * _crown_point(ring + 1, side, seed) + center
				var c := basis * _crown_point(ring + 1, side + 1, seed) + center
				var d := basis * _crown_point(ring, side + 1, seed) + center
				# Mais escuro embaixo, mais claro no topo; um tom por quadrado.
				var green := Color(CROWN_GREENS[posmod(ring * 3 + side * 7 + seed * 5, CROWN_GREENS.size())])
				var light := 0.12 - float(ring) / float(CROWN_RINGS) * 0.3
				t.set_color(green.lightened(light) if light > 0.0 else green.darkened(-light))
				for vertex in [a, b, c, a, c, d]: t.add_vertex(vertex)


## Contorno irregular da StreetTreeCanopy em grade menor: 7 anéis × 10 lados (140
## triângulos por volume, metade da copa autoral). Vista de cima, a 25 m, não se
## nota a diferença e são umas 20 árvores por chunk.
const CROWN_RINGS := 7
const CROWN_SIDES := 10

static func _crown_point(ring: int, side: int, variant: int) -> Vector3:
	var v := PI * float(ring) / float(CROWN_RINGS)
	var a := TAU * float(posmod(side, CROWN_SIDES)) / float(CROWN_SIDES)
	var phase := float(variant) * 1.3
	var edge := 1.0 + .16 * sin(a * 5 + v * 3 + phase) + .08 * cos(a * 7 - v * 4 + phase)
	var y := cos(v) + .075 * sin(a * 4 + phase) * sin(v)
	return Vector3(sin(v) * cos(a) * edge, y, sin(v) * sin(a) * edge)


# --- Vaso de porta ---

## Vaso redondo de barro: corpo cônico, borda e terra só em cima.
static func _pot(t: SurfaceTool) -> void:
	KIT.cylinder(t, Vector3.ZERO, .24, .5, Color("8c5136"), 10, .32)
	KIT.cylinder(t, Vector3(0, .5, 0), .35, .07, Color("9d6043"), 10)
	KIT.cylinder(t, Vector3(0, .57, 0), .3, .005, Color("2a241e"), 10)


static func _pot_leaves(t: SurfaceTool) -> void:
	var spots := [Vector2(0, 0), Vector2(.17, .08), Vector2(-.15, .12), Vector2(.05, -.17), Vector2(-.12, -.12)]
	for i in spots.size():
		var spot: Vector2 = spots[i]
		var height := .62 - spot.length() * .9
		KIT.blob(t, Vector3(spot.x, .56, spot.y), Vector2(.17, .16), height, Color(KIT.HARBOR_LEAVES[(i + 2) % KIT.HARBOR_LEAVES.size()]), 5, i * 3 + 2, 0.0, .3)


# --- Bar e café ---

## Mesa redonda de plástico com cadeiras de bar; `angles` em radianos em volta.
static func _table(t: SurfaceTool, at: Vector3, angles: Array, chair: Color) -> void:
	KIT.cylinder(t, at, .2, .03, Color("8f9294"), 8)
	KIT.cylinder(t, at, .035, .72, Color("8f9294"), 6)
	KIT.cylinder(t, at + Vector3(0, .72, 0), .4, .03, WHITE_PLASTIC, 12)
	for angle: float in angles:
		_chair(t, at + Vector3(sin(angle), 0, cos(angle)) * .62, angle, chair)


## Cadeira empilhável: assento, encosto do lado de fora e quatro pés.
static func _chair(t: SurfaceTool, at: Vector3, yaw: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	KIT.box(t, at + Vector3(0, .44, 0), Vector3(.42, .04, .42), color, yaw)
	KIT.box(t, at + basis * Vector3(0, .68, .19), Vector3(.42, .44, .04), color, yaw)
	for x in [-.18, .18]:
		for z in [-.18, .18]:
			KIT.box(t, at + basis * Vector3(x, .21, z), Vector3(.035, .42, .035), color.darkened(.12), yaw)


static func _cafe_set(t: SurfaceTool) -> void:
	_table(t, Vector3.ZERO, [PI * .5, -PI * .5, PI], RED_PLASTIC)
	# Engradado vazio encostado na mesa, cara de boteco.
	KIT.box(t, Vector3(.55, .15, -.5), Vector3(.4, .3, .3), Color("c9a634"), .2)


## Mesa com guarda-sol listrado. O guarda-sol é o que se vê de cima: oito gomos
## alternando duas cores, aberto a 2,1 m (gente passa por baixo).
static func _cafe_parasol(t: SurfaceTool, stripe: Color) -> void:
	_table(t, Vector3.ZERO, [PI * .5, -PI * .5], RED_PLASTIC)
	KIT.cylinder(t, Vector3(0, .75, 0), .02, 1.6, Color("cfcfc8"), 5)
	_umbrella(t, Vector3(0, 2.05, 0), 1.25, .4, stripe)


## Copa de guarda-sol: gomos alternando `stripe` e branco, com aba curta.
static func _umbrella(t: SurfaceTool, rim: Vector3, radius: float, rise: float, stripe: Color) -> void:
	var sides := 8
	var apex := rim + Vector3(0, rise, 0)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var p0 := rim + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := rim + Vector3(cos(a1), 0, sin(a1)) * radius
		t.set_color(stripe if i % 2 == 0 else Color("efe9da"))
		# Mesma ordem do topo de cylinder(): normal para cima e para fora.
		t.add_vertex(apex); t.add_vertex(p0); t.add_vertex(p1)
		# Aba curta caída na borda.
		var d0 := p0 + Vector3(0, -radius * .11, 0)
		var d1 := p1 + Vector3(0, -radius * .11, 0)
		# Ordem da parede de cylinder(): normal para fora.
		t.add_vertex(d0); t.add_vertex(d1); t.add_vertex(p0)
		t.add_vertex(d1); t.add_vertex(p1); t.add_vertex(p0)


## Banca de quitanda: cavalete com caixotes inclinados para a rua, cada um com
## uma fruta de cor forte, e caixotes vazios empilhados embaixo.
static func _produce_stand(t: SurfaceTool) -> void:
	for x in [-.75, .75]:
		for z in [-.32, .32]: KIT.box(t, Vector3(x, .36, z), Vector3(.05, .72, .05), Color("5e4a33"))
	KIT.box(t, Vector3(0, .74, 0), Vector3(1.7, .04, .8), Color("7a5f3e"))
	var fruit := [Color("e0862a"), Color("c0392b"), Color("86ad3c"), Color("e3c53a"), Color("7b3f6e"), Color("d9692b")]
	var tilt := Basis(Vector3.RIGHT, 0.22)
	for row in 2:
		for column in 3:
			var center := Vector3(-.55 + column * .55, .9 + row * .16, .16 - row * .34)
			_tilted_box(t, center, Vector3(.5, .14, .32), CRATE_WOOD, tilt)
			_tilted_box(t, center + tilt * Vector3(0, .075, 0), Vector3(.44, .03, .27), fruit[(row * 3 + column) % fruit.size()], tilt)
	for i in 3:
		KIT.box(t, Vector3(-.45 + i * .45, .14, -.05), Vector3(.42, .28, .32), CRATE_WOOD.darkened(.15 * float(i % 2)), .05 * float(i - 1))


static func _tilted_box(t: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis: Basis) -> void:
	var h := size * 0.5
	var corners := []
	for i in 8:
		var local := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		corners.append(center + basis * local)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	t.set_color(color)
	for face in faces:
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[1]]); t.add_vertex(corners[face[2]])
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[2]]); t.add_vertex(corners[face[3]])


## Cavalete de calçada: duas lousas em A com moldura de madeira e riscos de giz.
static func _a_frame(t: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		var basis := Basis(Vector3.RIGHT, -0.24 * side)
		var center := Vector3(0, .45, .11 * side)
		_tilted_box(t, center, Vector3(.58, .92, .03), Color("8a6a44"), basis)
		_tilted_box(t, center + basis * Vector3(0, .02, .018 * side), Vector3(.48, .76, .01), Color("2b302d"), basis)
		for line in 4:
			var y := .22 - line * .12
			var width := .34 - float(line % 2) * .12
			_tilted_box(t, center + basis * Vector3(0, y, .025 * side), Vector3(width, .025, .005), Color("e8e4d6") if line != 0 else Color("e3b54a"), basis)


## Engradados de cerveja empilhados ao lado da porta do bar.
static func _beer_crates(t: SurfaceTool) -> void:
	var colors := [Color("b23a2e"), Color("c9a634"), Color("b23a2e"), Color("2f6b4f")]
	var spots := [Vector3(-.22, 0, 0), Vector3(.22, 0, 0), Vector3(-.22, .3, 0), Vector3(.2, .3, .02)]
	for i in spots.size():
		var at: Vector3 = spots[i]
		var yaw := .06 * float(i % 3 - 1)
		KIT.box(t, at + Vector3(0, .15, 0), Vector3(.42, .29, .31), colors[i], yaw)
		# Gargalos: tampa escura com pontos claros.
		KIT.box(t, at + Vector3(0, .295, 0), Vector3(.36, .01, .25), Color("3b2a1c"), yaw)
	KIT.box(t, Vector3(-.22, .605, 0), Vector3(.36, .01, .25), Color("6b4a2a"))


# --- Casa e escritório ---

## Duas lixeiras de rodinha (orgânico e reciclável), tampa um pouco maior.
static func _wheelie_bins(t: SurfaceTool) -> void:
	var bodies := [Color("3e6b48"), Color("5d6366")]
	for i in 2:
		var x := -.34 + i * .68
		var yaw := .08 * float(i * 2 - 1)
		KIT.box(t, Vector3(x, .5, 0), Vector3(.56, .9, .62), bodies[i], yaw)
		KIT.box(t, Vector3(x, .97, -.02), Vector3(.6, .05, .7), bodies[i].darkened(.25), yaw)
		for side in [-.22, .22]:
			KIT.cylinder(t, Vector3(x + side, .0, -.28), .08, .06, Color("1d1f20"), 6)


## Paraciclo em U ao longo da parede com duas bicicletas presas.
static func _bike_rack(t: SurfaceTool) -> void:
	var steel := Color("8a9396")
	for x in [-.9, 0.0, .9]:
		for side in [-.32, .32]: KIT.box(t, Vector3(x + side, .4, 0), Vector3(.05, .8, .05), steel)
		KIT.box(t, Vector3(x, .8, 0), Vector3(.69, .05, .05), steel)
	_bike(t, Vector3(-.45, 0, .18), Color("2d6fb6"))
	_bike(t, Vector3(.5, 0, -.16), Color("c63a2f"))


## Bicicleta ao longo de X: rodas como anéis de oito barras, quadro em triângulo.
static func _bike(t: SurfaceTool, at: Vector3, color: Color) -> void:
	for wheel_x in [-.52, .52]:
		var hub := at + Vector3(wheel_x, .34, 0)
		for i in 8:
			var angle := TAU * float(i) / 8.0
			var basis := Basis(Vector3.BACK, angle)
			_tilted_box(t, hub + basis * Vector3(0, .32, 0), Vector3(.26, .035, .03), Color("1d1f20"), basis)
	var frame := [[Vector3(-.52, .34, 0), Vector3(0, .38, 0)], [Vector3(0, .38, 0), Vector3(.4, .72, 0)], [Vector3(-.15, .72, 0), Vector3(.4, .72, 0)],
		[Vector3(-.15, .72, 0), Vector3(0, .38, 0)], [Vector3(-.52, .34, 0), Vector3(-.15, .72, 0)], [Vector3(.4, .72, 0), Vector3(.52, .34, 0)]]
	for bar in frame:
		_bar(t, at + bar[0], at + bar[1], .035, color)
	KIT.box(t, at + Vector3(-.17, .8, 0), Vector3(.22, .05, .1), Color("1d1f20"))
	KIT.box(t, at + Vector3(.42, .86, 0), Vector3(.04, .04, .5), Color("3a3f41"))


## Barra quadrada fina de `a` até `b`.
static func _bar(t: SurfaceTool, a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	var direction := b - a
	var length := direction.length()
	if length < 0.001: return
	var basis := Basis(Quaternion(Vector3.UP, direction / length))
	_tilted_box(t, (a + b) * 0.5, Vector3(thickness, length, thickness), color, basis)


# --- Oficina e depósito ---

static func _pallet(t: SurfaceTool, y: float, yaw: float) -> void:
	for x in [-.5, 0.0, .5]: KIT.box(t, Vector3(x, y + .06, 0), Vector3(.12, .11, 1.0), Color("6f5236"), yaw)
	for z in [-.42, -.21, 0.0, .21, .42]: KIT.box(t, Vector3(0, y + .135, z), Vector3(1.2, .03, .14), Color("b39466"), yaw)


static func _pallet_stack(t: SurfaceTool) -> void:
	for i in 4: _pallet(t, i * .15, .05 * float(posmod(i * 3, 5) - 2))


static func _tire_stack(t: SurfaceTool) -> void:
	for stack in [[Vector3(-.36, 0, 0), 4], [Vector3(.38, 0, .05), 2]]:
		for i in int(stack[1]):
			var at: Vector3 = stack[0] + Vector3(.02 * float(i % 2), i * .22, 0)
			KIT.cylinder(t, at, .32, .21, Color("1d1f20"), 10)
			KIT.cylinder(t, at + Vector3(0, .21, 0), .17, .004, Color("0c0d0e"), 10)


static func _drums(t: SurfaceTool) -> void:
	var drums := [[Vector3(-.33, 0, 0), Color("2c5a8a")], [Vector3(.32, 0, -.05), Color("8e3a2a")], [Vector3(0, 0, .25), Color("6d5a3a")]]
	for drum in drums:
		var at: Vector3 = drum[0]
		var color: Color = drum[1]
		KIT.cylinder(t, at, .28, .86, color, 10)
		for y in [.28, .58]: KIT.cylinder(t, at + Vector3(0, y, 0), .29, .03, color.darkened(.25), 10)
		KIT.cylinder(t, at + Vector3(0, .86, 0), .22, .004, color.darkened(.35), 10)


# --- Segunda leva: mais variedade no térreo e no meio-fio ---

## Carrinho de cachorro-quente: caixa inox sobre duas rodas, puxador e guarda-sol.
static func _food_cart(t: SurfaceTool) -> void:
	KIT.box(t, Vector3(0, .62, 0), Vector3(1.3, .5, .65), Color("b9bec0"))
	KIT.box(t, Vector3(0, .9, 0), Vector3(1.36, .06, .7), Color("8d9294"))
	KIT.box(t, Vector3(0, .62, .33), Vector3(1.1, .3, .01), Color("c23b2e"))
	for x in [-.25, .25]: KIT.box(t, Vector3(x, .98, .05), Vector3(.36, .1, .26), Color("d9d6cc"))
	for side in [-.36, .36]:
		var hub := Vector3(-.3, .22, side)
		for i in 8:
			var angle := TAU * float(i) / 8.0
			var basis := Basis(Vector3.BACK, angle)
			_tilted_box(t, hub + basis * Vector3(0, .2, 0), Vector3(.17, .04, .04), Color("1d1f20"), basis)
	KIT.box(t, Vector3(.45, .2, 0), Vector3(.05, .4, .05), Color("6c7274"))
	_bar(t, Vector3(.65, .8, -.25), Vector3(1.0, .85, -.25), .03, Color("6c7274"))
	_bar(t, Vector3(.65, .8, .25), Vector3(1.0, .85, .25), .03, Color("6c7274"))
	KIT.cylinder(t, Vector3(.2, .93, 0), .02, 1.15, Color("cfcfc8"), 5)
	_umbrella(t, Vector3(.2, 2.05, 0), .95, .3, Color("e3b02e"))


## Freezer de sorvete horizontal: caixa branca, tampa de vidro escura e faixa azul.
static func _ice_freezer(t: SurfaceTool) -> void:
	KIT.box(t, Vector3(0, .42, 0), Vector3(1.1, .78, .62), Color("e8ebe9"))
	KIT.box(t, Vector3(0, .82, 0), Vector3(1.04, .03, .56), Color("3a5566"))
	KIT.box(t, Vector3(0, .55, .315), Vector3(1.0, .22, .01), Color("2e6fb0"))
	for x in [-.45, .45]:
		for z in [-.24, .24]: KIT.box(t, Vector3(x, .02, z), Vector3(.06, .04, .06), Color("2a2e30"))


## Arara de roupa na porta da loja: barra com cabides de cores variadas.
static func _clothes_rack(t: SurfaceTool) -> void:
	var steel := Color("8a9396")
	for x in [-.7, .7]:
		KIT.box(t, Vector3(x, .75, 0), Vector3(.04, 1.5, .04), steel)
		KIT.box(t, Vector3(x, .03, 0), Vector3(.06, .06, .5), steel)
	KIT.box(t, Vector3(0, 1.48, 0), Vector3(1.44, .03, .03), steel)
	var cloth := [Color("c0392b"), Color("2e6fb0"), Color("e3c53a"), Color("2f2f33"), Color("d27aa6"), Color("4f8a5b"), Color("e8e4d6"), Color("7b3f6e")]
	for i in 9:
		var x := -.6 + i * .15
		var length := .75 + .2 * float((i * 5) % 3)
		KIT.box(t, Vector3(x, 1.44 - length * .5, 0), Vector3(.05, length, .42), cloth[i % cloth.size()], .06 * float(i % 3 - 1))


## Floricultura: baldes de alumínio com maços de flor de cores fortes.
static func _flower_buckets(t: SurfaceTool) -> void:
	var flowers := [Color("d8354a"), Color("f2c230"), Color("e98bb7"), Color("f2efe6"), Color("8e5bc2"), Color("e8722a")]
	var spots := [Vector3(-.5, 0, .05), Vector3(-.17, 0, -.08), Vector3(.17, 0, .08), Vector3(.5, 0, -.05), Vector3(-.33, 0, .2), Vector3(.33, 0, .22)]
	for i in spots.size():
		var at: Vector3 = spots[i]
		var height := .38 if i < 4 else .26
		KIT.cylinder(t, at, .13, height, Color("a3a9ab"), 8, .16)
		KIT.blob(t, at + Vector3(0, height - .02, 0), Vector2(.17, .16), .3, Color("4c6a3c"), 5, i, 0.0, .3)
		KIT.blob(t, at + Vector3(0, height + .14, 0), Vector2(.15, .14), .18, flowers[i % flowers.size()], 5, i + 7, 0.0, .35)


## Botijões de gás encostados na parede (bar e oficina).
static func _gas_cylinders(t: SurfaceTool) -> void:
	for i in 3:
		var at := Vector3(-.36 + i * .36, 0, .02 * float(i % 2))
		KIT.cylinder(t, at, .16, .06, Color("3d4346"), 8)
		KIT.cylinder(t, at + Vector3(0, .06, 0), .17, .42, Color("4a6f8c") if i != 1 else Color("5d6366"), 10, .15)
		KIT.cylinder(t, at + Vector3(0, .48, 0), .09, .1, Color("2b2f31"), 6)
		KIT.box(t, at + Vector3(0, .6, 0), Vector3(.05, .05, .05), Color("d8a62a"))


## Banco de madeira da porta com um banquinho ao lado.
static func _door_bench(t: SurfaceTool) -> void:
	var wood := Color("8a6a44")
	KIT.box(t, Vector3(-.15, .44, 0), Vector3(1.0, .05, .34), wood)
	for x in [-.58, .28]: KIT.box(t, Vector3(x, .21, 0), Vector3(.05, .42, .3), wood.darkened(.2))
	KIT.cylinder(t, Vector3(.48, 0, .05), .14, .4, Color("4e5458"), 6)
	KIT.cylinder(t, Vector3(.48, .4, .05), .16, .04, Color("b0362c"), 8)


## Moto estacionada no meio-fio, ao longo de X: rodas de anel, tanque, banco e guidão.
static func _motorcycle(t: SurfaceTool) -> void:
	var paint := Color("a8322b")
	for wheel_x in [-.68, .68]:
		var hub := Vector3(wheel_x, .32, 0)
		for i in 10:
			var angle := TAU * float(i) / 10.0
			var basis := Basis(Vector3.BACK, angle)
			_tilted_box(t, hub + basis * Vector3(0, .28, 0), Vector3(.2, .09, .11), Color("1a1b1c"), basis)
		KIT.box(t, hub, Vector3(.12, .12, .08), Color("8a9396"))
	KIT.box(t, Vector3(-.05, .5, 0), Vector3(.7, .32, .22), Color("2b2f31"))
	_tilted_box(t, Vector3(.22, .82, 0), Vector3(.5, .24, .3), paint, Basis(Vector3.BACK, .1))
	KIT.box(t, Vector3(-.3, .85, 0), Vector3(.62, .1, .26), Color("1d1f20"))
	KIT.box(t, Vector3(-.65, .74, 0), Vector3(.3, .08, .24), paint.darkened(.2))
	_bar(t, Vector3(.5, .7, 0), Vector3(.68, .32, 0), .05, Color("8a9396"))
	_bar(t, Vector3(.5, .7, 0), Vector3(.42, 1.02, 0), .04, Color("8a9396"))
	KIT.box(t, Vector3(.42, 1.04, 0), Vector3(.04, .04, .66), Color("2b2f31"))
	KIT.box(t, Vector3(.6, .86, 0), Vector3(.1, .14, .16), Color("e8e4d6"))
	# Descanso lateral: a moto inclina para -Z, longe da rua.
	_bar(t, Vector3(-.05, .3, -.14), Vector3(-.15, .02, -.36), .03, Color("6c7274"))
