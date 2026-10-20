extends RefCounted
## Lugares da Estrada do Sal (fase 2 do passe de conteúdo do deserto, 20/10/2026): Salinas Estrada do
## Sal, Balança rodoviária e Motel Oásis. Mesmo contrato do RoadsideBuild: frente (+z local) para a
## estrada, uma malha por material composta uma vez (cache em RoadsideBuild.baked) e caixas sólidas
## para a colisão. Cada um tem um cômodo aberto para entrar a pé (escritório da salina, cabine do
## fiscal, recepção e um quarto do motel): paredes com vão de porta, piso, teto e móveis, sem o sistema
## de interiores (não troca de cena nem carrega nada ao entrar).
const ART := preload("res://runtime/desert/roadside/RoadsideArt.gd")
const WALL := .16
const DOOR_W := 1.1
const DOOR_H := 2.15
## Área interna (x, z locais) dos cômodos de cada lugar: com o jogador dentro, o telhado some.
const WALK_IN := {
	"salt_works": [Rect2(11.0, 26.0, 5.0, 4.0)],
	"weigh_station": [Rect2(-2.6, 1.1, 5.2, 3.8)],
	"motel": [Rect2(-15.92, -6.2, 3.64, 5.0), Rect2(7.9, -4.8, 5.2, 4.6)],
}

# --- Ajudas ----------------------------------------------------------------------------------

static func _t(x: float, y: float, z: float, yaw := 0.0, pitch := 0.0, roll := 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)), Vector3(x, y, z))

static func _box(b, mat: Material, at: Vector3, size: Vector3, skin := {}, tile := Vector2(2, 2), solid := false) -> void:
	b.box(mat, Transform3D(Basis.IDENTITY, at), size, skin, tile)
	if solid: b.solid(Transform3D(Basis.IDENTITY, at), size)

static func _along(a: Vector3, c: Vector3) -> Basis:
	var dir := (c - a).normalized()
	if dir.dot(Vector3.UP) < -.999: return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, dir))

static func _pipe(b, mat: Material, a: Vector3, c: Vector3, radius: float, segments := 6) -> void:
	b.cylinder(mat, Transform3D(_along(a, c), (a + c) * .5), radius, a.distance_to(c), segments, -1.0, false)

static func _beam(b, mat: Material, a: Vector3, c: Vector3, thickness: float) -> void:
	b.box(mat, Transform3D(_along(a, c), (a + c) * .5), Vector3(thickness, a.distance_to(c), thickness), {"+y": null, "-y": null})

## Placa de duas faces sobre dois postes.
static func _post_sign(b, frame: Material, at: Vector3, size: Vector3, panel: String, post_h: float) -> void:
	var rect := ART.uv(panel)
	b.box(frame, Transform3D(Basis.IDENTITY, at), size, {"+z": rect, "-z": rect})
	for side in [-1.0, 1.0]:
		var x: float = at.x + side * (size.x * .5 - .25)
		_box(b, frame, Vector3(x, post_h * .5, at.z), Vector3(.18, post_h, .18), {"-y": null}, Vector2(2, 2), true)

## Cômodo de entrar a pé: piso, teto, quatro paredes (a da frente com vão de porta em `door_x`) e as
## caixas sólidas das paredes. `center` no chão; frente = +z local do cômodo.
static func _room(b, roofs, center: Vector3, size: Vector3, wall: Material, inner: Material, floor_mat: Material, roof: Material, door_x := 0.0) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	_box(b, floor_mat, center + Vector3(0, .04, 0), Vector3(w, .08, d), {"-y": null}, Vector2(1.2, 1.2))
	# Telhado em lote separado: some quando o jogador entra (DesertRoadside._walk_in_roofs).
	_box(roofs, roof, center + Vector3(0, h + .08, 0), Vector3(w + .5, .16, d + .5), {}, Vector2(2.5, 2.5))
	# Fundo e laterais: face de fora na cor da parede, de dentro no acabamento interno.
	var back := center + Vector3(0, h * .5, -d * .5 + WALL * .5)
	_box(b, wall, back, Vector3(w, h, WALL), {"+z": inner}, Vector2(2, 2), true)
	for side in [-1.0, 1.0]:
		var at := center + Vector3(side * (w * .5 - WALL * .5), h * .5, 0)
		_box(b, wall, at, Vector3(WALL, h, d), {"-x" if side > 0 else "+x": inner}, Vector2(2, 2), true)
	# Frente: dois panos e a verga por cima do vão.
	var front_z := center.z + d * .5 - WALL * .5
	var left_w := (w * .5 + door_x) - DOOR_W * .5
	var right_w := (w * .5 - door_x) - DOOR_W * .5
	if left_w > .05:
		_box(b, wall, Vector3(center.x - w * .5 + left_w * .5, center.y + h * .5, front_z), Vector3(left_w, h, WALL), {"-z": inner}, Vector2(2, 2), true)
	if right_w > .05:
		_box(b, wall, Vector3(center.x + w * .5 - right_w * .5, center.y + h * .5, front_z), Vector3(right_w, h, WALL), {"-z": inner}, Vector2(2, 2), true)
	_box(b, wall, Vector3(center.x + door_x, center.y + DOOR_H + (h - DOOR_H) * .5, front_z), Vector3(DOOR_W, h - DOOR_H, WALL), {"-z": inner})
	# Rodapé de cimento por fora, beiral sob o telhado e batentes da porta: a parede lisa lia chapada.
	var plinth := ART.detail("gravel", Color("8c8576"))
	var trim := ART.detail("metal", Color("e8e4da"), .6)
	_box(b, plinth, center + Vector3(0, .15, -d * .5 - .02), Vector3(w + .04, .3, .06), {"-y": null})
	for side in [-1.0, 1.0]: _box(b, plinth, center + Vector3(side * (w * .5 + .02), .15, 0), Vector3(.06, .3, d + .04), {"-y": null})
	if left_w > .05: _box(b, plinth, Vector3(center.x - w * .5 + left_w * .5, .15, front_z + WALL * .5 + .02), Vector3(left_w + .02, .3, .06), {"-y": null})
	if right_w > .05: _box(b, plinth, Vector3(center.x + w * .5 - right_w * .5, .15, front_z + WALL * .5 + .02), Vector3(right_w + .02, .3, .06), {"-y": null})
	for side in [-1.0, 1.0]:
		_box(b, trim, Vector3(center.x + door_x + side * (DOOR_W * .5 + .04), DOOR_H * .5, front_z + WALL * .5 + .03), Vector3(.08, DOOR_H, .06), {"-y": null})
	_box(b, trim, Vector3(center.x + door_x, DOOR_H + .04, front_z + WALL * .5 + .03), Vector3(DOOR_W + .16, .08, .06))
	_box(b, trim, center + Vector3(0, h - .06, 0), Vector3(w + .1, .12, d + .1), {"-y": null, "+y": null})

## Janela escura (vidro) colada numa parede de frente +z.
static func _window(b, at: Vector3, w: float, h: float, facing := 1.0) -> void:
	var glass := ART.detail("metal", Color("26343a"), .12)
	var frame := ART.detail("metal", Color("d8d4c8"), .55)
	b.quad(glass, at + Vector3(0, 0, .012 * facing), Vector3(w * .5 * facing, 0, 0), Vector3(0, h * .5, 0), Rect2(0, 0, w * .5, h * .5))
	# Moldura (quatro lados), travessa do meio e peitoril saliente.
	for side in [-1.0, 1.0]:
		_box(b, frame, at + Vector3(side * (w * .5 + .03), 0, .035 * facing), Vector3(.06, h + .12, .07))
		_box(b, frame, at + Vector3(0, side * (h * .5 + .03), .035 * facing), Vector3(w + .12, .06, .07))
	_box(b, frame, at + Vector3(0, 0, .03 * facing), Vector3(.04, h, .05))
	_box(b, frame, at + Vector3(0, -h * .5 - .09, .08 * facing), Vector3(w + .24, .05, .16))

static func _desk(b, at: Vector3, yaw: float, top: Material, legs: Material) -> void:
	var basis := Basis(Vector3.UP, yaw)
	b.box(top, Transform3D(basis, at + Vector3(0, .74, 0)), Vector3(1.3, .05, .65))
	for x in [-.6, .6]:
		for z in [-.28, .28]:
			b.box(legs, Transform3D(basis, at + basis * Vector3(x, .36, z)), Vector3(.05, .72, .05), {"-y": null})
	b.solid(Transform3D(basis, at + Vector3(0, .38, 0)), Vector3(1.3, .76, .65))

static func _chair(b, at: Vector3, yaw: float, mat: Material) -> void:
	var basis := Basis(Vector3.UP, yaw)
	b.box(mat, Transform3D(basis, at + Vector3(0, .46, 0)), Vector3(.45, .06, .45))
	b.box(mat, Transform3D(basis, at + basis * Vector3(0, .75, -.2)), Vector3(.45, .55, .05))
	for x in [-.19, .19]:
		for z in [-.19, .19]:
			b.box(mat, Transform3D(basis, at + basis * Vector3(x, .22, z)), Vector3(.04, .44, .04), {"-y": null})

## Pilha de sacos de sal sobre palete (faces com o carimbo do atlas).
static func _bags(b, at: Vector3, layers: int, yaw := 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var wood := ART.detail("planks", Color("8a6a46"), .85)
	b.box(wood, Transform3D(basis, at + Vector3(0, .07, 0)), Vector3(1.2, .14, 1.0), {"-y": null}, Vector2(1.2, 1.2))
	var bag := ART.uv("salt_bag")
	var raffia := ART.color(Color("e4e0d0"))
	for layer in layers:
		var y := .14 + .19 + float(layer) * .36
		var turn := float(layer % 2) * .04
		b.box(raffia, Transform3D(basis * Basis(Vector3.UP, turn), at + Vector3(0, y, 0)), Vector3(1.16, .36, .96), {"+z": bag, "-z": bag, "+x": bag, "-x": bag, "-y": null})
	b.solid(Transform3D(basis, at + Vector3(0, (.14 + float(layers) * .36) * .5, 0)), Vector3(1.2, .14 + float(layers) * .36, 1.0))

# --- Salinas Estrada do Sal ---------------------------------------------------------------------
## Pátio de ensaque perto da estrada (galpão aberto, escritório, montes de sal, esteira, pá
## carregadeira) e seis tanques de evaporação atrás. A estrada fica em z ≈ +60.

static func compose_salt_works(b, roofs) -> void:
	var salt := ART.detail("salt_crust", Color("f2f0ea"), .95)
	# Salmoura saturada: os tons claros sumiam no branco do sol (captura de 20/10).
	var crust := ART.detail("salt_crust", Color("e2ddd0"), .95)
	var brine_a := ART.detail("brine", Color("b98476"), .3)
	var brine_b := ART.detail("brine", Color("7fa7b0"), .25)
	var berm := ART.detail("gravel", Color("b59b78"))
	var dark := ART.color(Color("2e3032"))
	var steel := ART.color(Color("8d9193"))
	var yellow := ART.detail("metal", Color("d49a12"), .5)
	var rubber := ART.color(Color("1c1c1b"))
	var concrete := ART.concrete()
	var navy := ART.color(Color("1c3a60"))
	# Acesso de cascalho de sal da estrada até o galpão e a placa na entrada.
	_box(b, ART.detail("gravel", Color("d9d2c2")), Vector3(0, .03, 45), Vector3(9, .06, 26), {"-y": null}, Vector2(3, 3))
	_post_sign(b, navy, Vector3(-9, 3.4, 54), Vector3(6.0, 1.5, .14), "salt_sign", 4.2)
	# Galpão de ensaque aberto: piso de concreto, oito colunas, telhado de chapa branca inclinado.
	_box(b, concrete, Vector3(0, -.1, 27), Vector3(19, .3, 11), {"-y": null}, Vector2(4, 4))
	for x in [-9.0, -3.0, 3.0, 9.0]:
		for z in [22.0, 32.0]:
			_box(b, steel, Vector3(x, 2.85, z), Vector3(.25, 5.7, .25), {"-y": null}, Vector2(2, 2), true)
	b.box(ART.white_sheet(), _t(0, 5.85, 27, 0, deg_to_rad(5)), Vector3(20, .14, 12), {"+x": dark, "-x": dark, "+z": dark, "-z": dark}, Vector2(3, 3))
	for z in [22.0, 32.0]: _box(b, steel, Vector3(0, 5.55, z), Vector3(18.4, .22, .22))
	# Paletes de sacos, balança de chão e a costuradeira de saco.
	for spot in [Vector3(-7, 0, 24), Vector3(-5.6, 0, 24), Vector3(-7, 0, 25.4), Vector3(-4.2, 0, 24.2), Vector3(-7.2, 0, 30.4), Vector3(-5.8, 0, 30.5)]:
		_bags(b, spot, 3 + int(absf(spot.x * 7 + spot.z)) % 3, float(int(spot.z) % 3) * .05)
	_box(b, steel, Vector3(-1.5, .08, 28), Vector3(1.4, .1, 1.4), {"-y": null})
	_box(b, dark, Vector3(-1.5, .9, 27.1), Vector3(.5, .7, .3), {"-y": null}, Vector2(2, 2), true)
	_box(b, steel, Vector3(1.6, .55, 28), Vector3(1.0, 1.1, .7), {"-y": null}, Vector2(2, 2), true)
	_pipe(b, steel, Vector3(1.6, 1.1, 28), Vector3(1.6, 2.3, 28), .05)
	# Funil de ensaque alimentado pela esteira que sobe do monte principal.
	b.cylinder(steel, _t(3.8, 3.2, 26.5), .25, 1.6, 10, .9)
	for x in [3.2, 4.4]:
		for z in [25.9, 27.1]: _box(b, steel, Vector3(x, 1.2, z), Vector3(.1, 2.4, .1), {"-y": null})
	b.solid(_t(3.8, 1.6, 26.5), Vector3(1.6, 3.2, 1.6))
	var belt_a := Vector3(4.2, 4.1, 26.0)
	var belt_c := Vector3(15.0, .9, 12.0)
	b.box(ART.color(Color("3a3c3e")), Transform3D(_along(belt_a, belt_c), (belt_a + belt_c) * .5), Vector3(.8, belt_a.distance_to(belt_c), .08), {}, Vector2(2, 2))
	for k in 5:
		var p := belt_a.lerp(belt_c, (float(k) + .5) / 5.0)
		_box(b, steel, Vector3(p.x, p.y * .5 - .05, p.z), Vector3(.12, maxf(p.y - .1, .1), .12), {"-y": null})
	# Montes de sal (cones) e as marcas da pá carregadeira.
	for mound in [[Vector3(16, 0, 9), 5.2, 4.2], [Vector3(7.5, 0, 7.5), 4.0, 3.2], [Vector3(-9, 0, 9.5), 3.6, 2.8], [Vector3(-16, 0, 13), 2.6, 2.0]]:
		var at: Vector3 = mound[0]
		var r: float = mound[1]
		var hgt: float = mound[2]
		b.cylinder(salt, _t(at.x, hgt * .5, at.z), r, hgt, 18, .35)
		b.solid(_t(at.x, hgt * .35, at.z), Vector3(r * 1.25, hgt * .7, r * 1.25))
	_box(b, crust, Vector3(4, .02, 9), Vector3(30, .04, 12), {"-y": null}, Vector2(4, 4))
	# Pá carregadeira amarela parada entre os montes.
	var loader := Vector3(-1.5, 0, 12.5)
	_box(b, yellow, loader + Vector3(0, 1.15, 0), Vector3(2.2, 1.2, 3.6), {"-y": null}, Vector2(2, 2))
	_box(b, yellow, loader + Vector3(0, 2.35, -.6), Vector3(1.6, 1.3, 1.5), {"-y": null})
	b.quad(ART.color(Color("2b3a40")), loader + Vector3(0, 2.5, .16), Vector3(.7, 0, 0), Vector3(0, .5, 0), Rect2())
	_box(b, dark, loader + Vector3(0, .55, 2.6), Vector3(2.5, .9, .8), {"-y": null})
	for side in [-1.0, 1.0]:
		_beam(b, yellow, loader + Vector3(side * .9, 1.3, .9), loader + Vector3(side * .9, .7, 2.3), .2)
		for z in [-1.1, 1.2]:
			b.cylinder(rubber, Transform3D(Basis(Vector3.FORWARD, PI * .5), loader + Vector3(side * 1.2, .6, z)), .6, .5, 14)
	b.solid(_t(loader.x, 1.2, loader.z + .4), Vector3(2.6, 2.4, 4.8))
	# Escritório da salina (entra a pé): mesa do encarregado, cofre do pagamento, rádio, estante.
	var office := Vector3(13.5, 0, 28)
	_room(b, roofs, office, Vector3(5.0, 2.9, 4.0), ART.detail("plaster", Color("d6cfbf")), ART.detail("plaster", Color("efe9da")), ART.detail("planks", Color("9c8a6c"), .8), ART.white_sheet(), -.9)
	_window(b, office + Vector3(1.3, 1.6, 2.0 + .01), 1.5, .9)
	var wood := ART.detail("planks", Color("7a5a3a"), .8)
	_desk(b, office + Vector3(.9, 0, -1.1), 0.0, wood, dark)
	_chair(b, office + Vector3(.9, 0, -.45), PI, ART.color(Color("3b4a5a")))
	_box(b, dark, office + Vector3(.6, .86, -1.25), Vector3(.35, .2, .25))
	_box(b, ART.color(Color("4a4e50")), office + Vector3(-1.9, .4, -1.45), Vector3(.7, .8, .7), {"-y": null}, Vector2(2, 2), true)
	b.cylinder(ART.color(Color("c6c4bd")), Transform3D(Basis(Vector3.RIGHT, PI * .5), office + Vector3(-1.9, .5, -1.08)), .1, .03, 10)
	_box(b, wood, office + Vector3(-2.05, 1.0, .4), Vector3(.4, 2.0, 1.4), {"-y": null}, Vector2(2, 2), true)
	for k in 4:
		_box(b, ART.color([Color("a52a1d"), Color("2a5f9e"), Color("d49a12"), Color("3e6b3a")][k]), office + Vector3(-1.8, .55 + float(k) * .45, .1 + float(k % 2) * .3), Vector3(.12, .3, .5))
	b.cylinder(ART.color(Color("6ea8d0")), _t(office.x + 1.9, .55, office.z + 1.3), .17, 1.1, 10)
	# Tanques de evaporação: seis piscinas rasas entre taludes de terra, três com salmoura (rosada e
	# azulada) e três com a crosta branca pronta para colher.
	var cols := [-30.0, 0.0, 30.0]
	var rows := [-8.0, -28.0]
	var index := 0
	for z in rows:
		for x in cols:
			var surface: Material = [brine_a, crust, brine_b, crust, brine_a, crust][index]
			_box(b, surface, Vector3(x, .18, z), Vector3(29.2, .04, 19.2), {"-y": null}, Vector2(14, 14))
			index += 1
	for z in [2.0, -18.0, -38.0]:
		_box(b, berm, Vector3(0, .3, z), Vector3(91, .6, 1.2), {"-y": null}, Vector2(4, 4), true)
	for x in [-45.0, -15.0, 15.0, 45.0]:
		_box(b, berm, Vector3(x, .3, -18), Vector3(1.2, .6, 41), {"-y": null}, Vector2(4, 4), true)
	# Passarela de tábuas sobre o talude do meio, com corrimão.
	_box(b, wood, Vector3(0, .65, -18), Vector3(60, .08, .9), {"-y": null}, Vector2(1, 1))
	for x in range(-28, 29, 4): _box(b, wood, Vector3(float(x), .95, -18.4), Vector3(.06, .6, .06), {"-y": null})
	_box(b, wood, Vector3(0, 1.25, -18.4), Vector3(60, .05, .05))
	# Casa de bombas na ponta oeste, com a tubulação que corre pelo talude até os tanques.
	_box(b, ART.detail("plaster", Color("c9bfa8")), Vector3(-50, 1.2, -8), Vector3(3, 2.4, 3), {"-y": null}, Vector2(2, 2), true)
	b.quad(b.atlas, Vector3(-48.48, 1.5, -8), Vector3(0, 0, -.3), Vector3(0, .3, 0), ART.uv("hazard"))
	# Tambores de óleo, mangueira enrolada e paletes vazios encostados na casa de bombas.
	for k in 3: b.cylinder(ART.detail("metal", [Color("2a5f9e"), Color("8e4a2c"), Color("3e6b3a")][k], .55), _t(-52.2 + float(k) * .62, .45, -5.9), .29, .9, 12)
	b.solid(_t(-51.6, .45, -5.9), Vector3(1.9, .9, .6))
	b.cylinder(ART.color(Color("2b2b2b")), _t(-47.6, .1, -5.6), .55, .2, 14, .35)
	for k in 3: _box(b, ART.detail("planks", Color("8a6a46"), .85), Vector3(-52.6, .07 + float(k) * .15, -10.4), Vector3(1.2, .14, 1.0), {"-y": null}, Vector2(1.2, 1.2))
	b.box(ART.rust_sheet(), _t(-50, 2.48, -8, 0, deg_to_rad(4)), Vector3(3.4, .1, 3.4), {}, Vector2(3, 3))
	_pipe(b, ART.color(Color("4b6176")), Vector3(-48.4, .5, -8), Vector3(-45, .75, -8), .14)
	_pipe(b, ART.color(Color("4b6176")), Vector3(-45, .75, -8), Vector3(-45, .75, -30), .14)
	_pipe(b, ART.color(Color("4b6176")), Vector3(-45, .75, -30), Vector3(-15, .75, -30), .14)
	# Rodo de puxar sal e carrinho de mão encostados no talude.
	_beam(b, wood, Vector3(14, .4, 3.0), Vector3(12, 2.0, 3.3), .05)
	_box(b, steel, Vector3(14.1, .15, 2.9), Vector3(1.2, .25, .08))
	_box(b, ART.color(Color("3e6b3a")), Vector3(-12, .45, 3.6), Vector3(.8, .4, 1.1), {"-y": null})
	b.cylinder(rubber, Transform3D(Basis(Vector3.FORWARD, PI * .5), Vector3(-12, .2, 4.3)), .2, .1, 10)

# --- Balança rodoviária ---------------------------------------------------------------------------
## Cabine do fiscal (entra a pé), plataforma da balança na faixa de acesso, cancela, placas, cones,
## um baú parado esperando a pesagem e o banheiro químico. A estrada fica em z ≈ +25.

static func compose_weigh_station(b, roofs) -> void:
	var concrete := ART.concrete()
	var steel := ART.color(Color("8d9193"))
	var dark := ART.color(Color("2e3032"))
	var yellow := ART.color(Color("d49a12"))
	var red := ART.color(Color("b52a20"))
	var white := ART.color(Color("e4e1d9"))
	var green := ART.color(Color("1a6a40"))
	# Faixa de acesso com a plataforma de pesagem de 18 m e faixas amarelas.
	_box(b, ART.asphalt(), Vector3(0, -.15, 12), Vector3(34, .4, 9), {"-y": null}, Vector2(4, 4))
	_box(b, steel, Vector3(0, .07, 12), Vector3(18, .06, 3.3), {"-y": null}, Vector2(1, 1))
	for side in [-1.0, 1.0]:
		_box(b, yellow, Vector3(0, .1, 12 + side * 1.75), Vector3(18.4, .01, .18), {"-y": null})
		_box(b, yellow, Vector3(side * 9.25, .1, 12), Vector3(.18, .01, 3.5), {"-y": null})
	for x in [-8.0, -4.0, 0.0, 4.0, 8.0]: _box(b, dark, Vector3(x, .105, 12), Vector3(.05, .01, 3.2), {"-y": null})
	# Cabine do fiscal: janela de frente para a balança, porta no canto, toldo.
	var cabin := Vector3(0, 0, 3.0)
	_room(b, roofs, cabin, Vector3(5.2, 2.8, 3.8), ART.detail("plaster", Color("e0dccf")), ART.detail("plaster", Color("f0ece0")), ART.detail("pool_tile", Color("8f8a80"), .7), ART.white_sheet(), -1.6)
	_window(b, cabin + Vector3(.9, 1.55, 1.9 + .01), 2.4, 1.0)
	_box(b, green, cabin + Vector3(0, 2.95, 2.5), Vector3(5.6, .1, 1.4))
	b.quad(b.atlas, cabin + Vector3(.9, 2.25, 1.92), Vector3(.18, 0, 0), Vector3(0, .07, 0), ART.uv("light"))
	# Dentro: bancada sob a janela com monitor do peso, rádio, garrafa de café, cadeira, arquivo e o
	# quadro de limites na parede do fundo.
	var wood := ART.detail("planks", Color("8a6a46"), .8)
	_box(b, wood, cabin + Vector3(.9, .78, 1.45), Vector3(2.6, .05, .6))
	_box(b, dark, cabin + Vector3(.9, .38, 1.45), Vector3(2.5, .76, .55), {"-y": null})
	b.solid(_t(cabin.x + .9, .4, cabin.z + 1.45), Vector3(2.6, .8, .6))
	_box(b, dark, cabin + Vector3(.5, 1.05, 1.55), Vector3(.5, .4, .1))
	b.quad(b.atlas, cabin + Vector3(.5, 1.05, 1.49), Vector3(-.21, 0, 0), Vector3(0, .16, 0), ART.uv("light"))
	_box(b, ART.color(Color("4a4e50")), cabin + Vector3(1.5, .93, 1.5), Vector3(.35, .25, .22))
	b.cylinder(red, _t(cabin.x + 2.0, .93, cabin.z + 1.5), .07, .3, 8)
	_chair(b, cabin + Vector3(.7, 0, .8), 0.0, ART.color(Color("3b4a5a")))
	_box(b, ART.detail("metal", Color("6c7276"), .5), cabin + Vector3(-2.1, .65, -1.45), Vector3(.6, 1.3, .55), {"-y": null}, Vector2(.6, 1.3), true)
	# Pilha de pneus e cones empilhados atrás da cabine.
	for k in 4: b.cylinder(ART.color(Color("1c1c1b")), _t(-3.6 + float(k % 2) * .05, .13 + float(k) * .25, -.6), .38, .24, 12)
	b.solid(_t(-3.6, .5, -.6), Vector3(.8, 1.0, .8))
	for k in 4: b.cylinder(ART.color(Color("e05a1c")), _t(-4.6, .36 + float(k) * .12, -.4), .18, .72, 8, .04)
	b.quad(b.atlas, cabin + Vector3(.3, 1.7, -1.9 + WALL + .01), Vector3(.35, 0, 0), Vector3(0, .44, 0), ART.uv("weigh_board"))
	b.cylinder(ART.color(Color("c6c4bd")), _t(cabin.x - 1.2, 2.55, cabin.z), .22, .05, 10)
	# Cancela vermelha e branca na saída da balança, PARE e cones.
	_box(b, white, Vector3(10.6, .55, 15.8), Vector3(.5, 1.1, .5), {"-y": null}, Vector2(2, 2), true)
	# O braço atravessa a faixa (os caminhões andam em x pela balança).
	for k in 7:
		_box(b, red if k % 2 == 0 else white, Vector3(10.6, 1.0, 15.3 - float(k) * .95 - .48), Vector3(.12, .12, .95))
	_box(b, dark, Vector3(10.6, 1.3, 15.4), Vector3(.12, 2.6, .12), {"-y": null}, Vector2(2, 2), true)
	var stop := ART.uv("stop_sign")
	b.box(dark, _t(10.6, 2.75, 15.4), Vector3(.8, .8, .04), {"+z": stop, "-z": stop})
	for k in 7:
		var at := Vector3(-13.5 + float(k) * 4.5, 0, 17.0)
		b.cylinder(ART.color(Color("e05a1c")), _t(at.x, .36, at.z), .18, .72, 8, .04)
		_box(b, ART.color(Color("e05a1c")), at + Vector3(0, .02, 0), Vector3(.45, .04, .45), {"-y": null})
		b.cylinder(white, _t(at.x, .45, at.z), .13, .1, 8, -1.0, false)
	_post_sign(b, green, Vector3(-11, 3.4, 20.5), Vector3(5.6, 2.0, .14), "weigh_sign", 4.4)
	# Baú parado esperando a vez, com a carga de caixotes ao lado.
	for k in 4:
		var crate := Vector3(-14.5 + float(k % 2) * 1.25, .5 + float(k / 2) * 1.0, 6.5)
		_box(b, ART.detail("crate", Color("b08a5a"), .85), crate, Vector3(1.2, 1.0, 1.2), {"-y": null}, Vector2(1.2, 1.0))
	b.solid(_t(-13.9, 1.0, 6.5), Vector3(2.5, 2.0, 1.2))
	# Banheiro químico azul e o poste do holofote.
	_box(b, ART.detail("metal", Color("2a5f9e"), .45), Vector3(4.8, 1.15, 1.2), Vector3(1.2, 2.3, 1.2), {"-y": null}, Vector2(1.2, 2.3), true)
	b.cylinder(ART.color(Color("2a5f9e")), _t(4.8, 2.35, 1.2), .62, .12, 10)
	_box(b, steel, Vector3(-4.2, 3.5, 6.5), Vector3(.2, 7.0, .2), {"-y": null}, Vector2(2, 2), true)
	_box(b, dark, Vector3(-4.2, 7.0, 6.9), Vector3(.7, .35, .5))

# --- Motel Oásis -----------------------------------------------------------------------------------
## Bloco de quartos com marquise e portas, recepção (entra a pé), o quarto 1 aberto, estacionamento,
## piscina vazia cercada, máquina de refrigerante, palmeiras e o letreiro de neon. Estrada em z ≈ +24.

static func compose_motel(b, roofs) -> void:
	var stucco := ART.detail("plaster", Color("e8d9c0"))
	var inner := ART.detail("plaster", Color("efe6d4"))
	var teal := ART.detail("plaster", Color("3f9aa8"))
	var dark := ART.color(Color("2e3032"))
	var steel := ART.color(Color("c6c4bd"))
	var white := ART.color(Color("e4e1d9"))
	var tile := ART.detail("pool_tile", Color("4f8fa0"), .3)
	var concrete := ART.concrete()
	var wood := ART.detail("planks", Color("7a5a3a"), .8)
	# Estacionamento de asfalto com as vagas pintadas, calçada sob a marquise.
	_box(b, ART.asphalt(), Vector3(-1, -.15, 8.5), Vector3(38, .4, 15), {"-y": null}, Vector2(4, 4))
	for k in 7: _box(b, white, Vector3(-16.0 + float(k) * 3.4, .06, 6.0), Vector3(.12, .01, 4.6), {"-y": null})
	_box(b, concrete, Vector3(-5, .08, .2), Vector3(22.4, .16, 2.4), {"-y": null}, Vector2(4, 4))
	# Bloco dos quartos 2 a 6: caixa sólida com as frentes pintadas (porta, janela, ar-condicionado).
	var block_c := Vector3(-3.2, 1.5, -3.7)
	var block_size := Vector3(18.2, 3.0, 5.0)
	_box(b, stucco, block_c, block_size, {"-y": null, "+y": null}, Vector2(2.5, 2.5), true)
	var plinth := ART.detail("gravel", Color("8c8576"))
	_box(b, plinth, Vector3(block_c.x, .15, block_c.z + block_size.z * .5 + .03), Vector3(block_size.x, .3, .06), {"-y": null})
	_box(b, plinth, Vector3(block_c.x, .15, block_c.z - block_size.z * .5 - .03), Vector3(block_size.x, .3, .06), {"-y": null})
	for x in [-12.0, 5.7]: _pipe(b, ART.detail("metal", Color("c6c4bd"), .5), Vector3(x, .1, -6.3), Vector3(x, 3.0, -6.3), .05)
	# Lixeiras, máquina de gelo e carrinho da arrumadeira na calçada.
	for k in 2:
		var bin := Vector3(-15.0 + float(k) * 19.0, 0, .9)
		b.cylinder(ART.detail("metal", Color("3e6b3a"), .5), _t(bin.x, .45, bin.z), .28, .9, 12)
		b.solid(_t(bin.x, .45, bin.z), Vector3(.56, .9, .56))
	_box(b, ART.detail("metal", Color("e4e1d9"), .4), Vector3(4.6, .7, -.6), Vector3(.9, 1.4, .7), {"-y": null}, Vector2(.9, 1.4), true)
	b.quad(b.atlas, Vector3(4.6, 1.15, -.24), Vector3(.3, 0, 0), Vector3(0, .1, 0), ART.uv("light"))
	_box(b, ART.detail("metal", Color("c6c4bd"), .5), Vector3(-7.4, .55, .2), Vector3(.6, .7, 1.1), {"-y": null})
	_box(b, ART.color(Color("e8e4da")), Vector3(-7.4, .95, .2), Vector3(.55, .15, 1.0), {"-y": null})
	b.solid(_t(-7.4, .5, .2), Vector3(.6, 1.0, 1.1))
	var door := ART.uv("room_door")
	for k in 5:
		var x := -10.6 + float(k) * 3.64
		b.quad(b.atlas, Vector3(x - .7, 1.07, -1.19), Vector3(.5, 0, 0), Vector3(0, 1.05, 0), door)
		_window(b, Vector3(x + .75, 1.55, -1.2), 1.1, .9)
		_box(b, ART.color(Color("c6c4bd")), Vector3(x + .75, .62, -1.0), Vector3.ONE * .5 * Vector3(1.4, 1.0, .8), {"-y": null})
	# Quarto 1 aberto (entra a pé): cama de casal, criados, abajur, TV na cômoda, cadeira e cortina.
	var room := Vector3(-14.1, 0, -3.7)
	_room(b, roofs, room, Vector3(3.64, 3.0, 5.0), stucco, inner, ART.detail("planks", Color("8a5a48"), .8), ART.white_sheet(), -.6)
	_window(b, room + Vector3(.95, 1.55, 2.5 + .01), .9, .9)
	var bedspread := ART.color(Color("b0473a"))
	_box(b, wood, room + Vector3(.2, .25, -1.25), Vector3(1.7, .5, 2.1), {"-y": null}, Vector2(2, 2), true)
	_box(b, bedspread, room + Vector3(.2, .56, -1.1), Vector3(1.72, .14, 1.8), {"-y": null})
	_box(b, white, room + Vector3(.2, .62, -2.0), Vector3(1.5, .14, .45), {"-y": null})
	_box(b, wood, room + Vector3(.2, .8, -2.38), Vector3(1.8, 1.2, .1))
	for side in [-1.0, 1.0]:
		_box(b, wood, room + Vector3(.2 + side * 1.2, .3, -2.1), Vector3(.45, .6, .4), {"-y": null}, Vector2(2, 2), true)
	b.cylinder(ART.color(Color("e8c070")), _t(room.x + 1.4, .82, room.z - 2.1), .14, .3, 10, .08)
	_box(b, wood, room + Vector3(-1.45, .45, .4), Vector3(.5, .9, 1.4), {"-y": null}, Vector2(2, 2), true)
	_box(b, dark, room + Vector3(-1.4, 1.15, .4), Vector3(.35, .5, .6))
	_chair(b, room + Vector3(-1.0, 0, 1.6), PI * .75, ART.color(Color("5a7a6a")))
	_box(b, ART.color(Color("c88a3a")), room + Vector3(.95, 1.55, 2.3), Vector3(1.0, 1.1, .04))
	b.quad(b.atlas, room + Vector3(-.6, 2.35, 2.53), Vector3(.12, 0, 0), Vector3(0, .05, 0), ART.uv("light"))
	# Marquise sobre a calçada: laje, colunas e a faixa pintada com o nome.
	_box(b, white, Vector3(-5, 3.15, -.3), Vector3(22.6, .2, 2.4))
	for x in [-15.6, -10.0, -4.4, 1.2, 5.6]: _box(b, teal, Vector3(x, 1.55, .75), Vector3(.18, 3.1, .18), {"-y": null}, Vector2(2, 2), true)
	b.quad(b.atlas, Vector3(-5, 3.15, .92), Vector3(10.0, 0, 0), Vector3(0, .1, 0), ART.uv("motel_band"))
	_box(b, white, Vector3(-3.2, 3.08, -3.7), Vector3(18.6, .16, 5.4))
	# Recepção (entra a pé): balcão, quadro de chaves, banquinho, vaso, TV e o folheteiro.
	var lobby := Vector3(10.5, 0, -2.5)
	_room(b, roofs, lobby, Vector3(5.2, 3.0, 4.6), teal, inner, ART.detail("pool_tile", Color("b8a88a"), .6), ART.white_sheet(), -1.2)
	_window(b, lobby + Vector3(1.0, 1.6, 2.3 + .01), 2.0, 1.1)
	_box(b, wood, lobby + Vector3(.6, .55, -.4), Vector3(2.8, 1.1, .6), {"-y": null}, Vector2(2, 2), true)
	_box(b, ART.color(Color("d8c8a8")), lobby + Vector3(.6, 1.12, -.4), Vector3(2.9, .05, .7))
	_box(b, wood, lobby + Vector3(.6, 1.6, -2.2), Vector3(1.2, .8, .05))
	for k in 6:
		_box(b, ART.color(Color("d49a12")), lobby + Vector3(.2 + float(k % 3) * .4, 1.75 - float(k / 3) * .35, -2.14), Vector3(.05, .12, .03))
	b.cylinder(dark, _t(lobby.x + 2.0, .35, lobby.z - .9), .18, .7, 10)
	b.cylinder(ART.color(Color("8a5a3a")), _t(lobby.x - 2.1, .3, lobby.z - 1.8), .28, .6, 10, .22)
	b.cylinder(ART.color(Color("3e7a3a")), _t(lobby.x - 2.1, 1.0, lobby.z - 1.8), .45, .9, 8, .1)
	_box(b, dark, lobby + Vector3(-1.9, 2.1, -2.15), Vector3(.7, .45, .1))
	_box(b, ART.color(Color("e4e1d9")), lobby + Vector3(-2.3, .7, .6), Vector3(.3, 1.4, .4), {"-y": null})
	b.quad(b.atlas, lobby + Vector3(-1.2, 2.3, 2.33), Vector3(.14, 0, 0), Vector3(0, .06, 0), ART.uv("light"))
	# Máquina de refrigerante encostada na recepção, com a vitrine acesa à noite.
	var vend := Vector3(7.2, 0, .4)
	_box(b, ART.color(Color("b52a20")), vend + Vector3(0, .95, 0), Vector3(.9, 1.9, .8), {"+z": ART.uv("vending"), "-y": null}, Vector2(2, 2), true)
	# Piscina vazia (acima do chão, como as de motel de estrada), cercada, com escada e espreguiçadeiras.
	var pool := Vector3(13.0, 0, 7.0)
	_box(b, concrete, pool + Vector3(0, .07, 0), Vector3(11, .08, 8), {"-y": null}, Vector2(4, 4))
	_box(b, tile, pool + Vector3(0, .13, 0), Vector3(7.6, .04, 4.6), {"-y": null}, Vector2(1.2, 1.2))
	for side in [-1.0, 1.0]:
		_box(b, white, pool + Vector3(0, .35, side * 2.45), Vector3(8.0, .7, .3), {"-y": null}, Vector2(2, 2), true)
		_box(b, white, pool + Vector3(side * 3.95, .35, 0), Vector3(.3, .7, 4.6), {"-y": null}, Vector2(2, 2), true)
	for side in [-.25, .25]:
		_pipe(b, steel, pool + Vector3(2.9 + side, .1, 2.2), pool + Vector3(2.9 + side, 1.25, 2.6), .03)
	for k in 3: _box(b, ART.color(Color("6a5a3a")), pool + Vector3(-1.5 + float(k) * 1.3, .13, -1.0 + float(k % 2) * .9), Vector3(.25, .01, .15), {"-y": null})
	for k in 2:
		var lounge := pool + Vector3(-3.0 + float(k) * 2.0, 0, 3.4)
		b.box(white, _t(lounge.x, .35, lounge.z, 0, -.18), Vector3(.7, .06, 1.9))
		b.solid(_t(lounge.x, .3, lounge.z), Vector3(.7, .6, 1.9))
	var rail := ART.color(Color("8d9193"))
	var fence := [[pool + Vector3(-5.4, 0, -3.9), pool + Vector3(5.4, 0, -3.9)], [pool + Vector3(5.4, 0, -3.9), pool + Vector3(5.4, 0, 3.9)],
		[pool + Vector3(-5.4, 0, 3.9), pool + Vector3(-1.0, 0, 3.9)], [pool + Vector3(1.0, 0, 3.9), pool + Vector3(5.4, 0, 3.9)]]
	for run in fence:
		var a: Vector3 = run[0]
		var c: Vector3 = run[1]
		var count := maxi(1, roundi(a.distance_to(c) / 1.6))
		for i in count + 1:
			var p := a.lerp(c, float(i) / float(count))
			_box(b, rail, p + Vector3(0, .55, 0), Vector3(.05, 1.1, .05), {"-y": null})
		for h in [.5, 1.05]: _pipe(b, rail, a + Vector3(0, h, 0), c + Vector3(0, h, 0), .02, 4)
		var mid := (a + c) * .5
		b.solid(_t(mid.x, .55, mid.z), Vector3(maxf(absf(c.x - a.x), .1), 1.1, maxf(absf(c.z - a.z), .1)))
	# Palmeiras velhas (tronco inclinado e folhas em leque).
	for palm in [[Vector3(-19.5, 0, 2.0), .08], [Vector3(19.0, 0, 1.5), -.1]]:
		var base: Vector3 = palm[0]
		var lean: float = palm[1]
		var top := base + Vector3(lean * 30, 6.5, 0)
		_pipe(b, ART.color(Color("8a6a46")), base, top, .22, 7)
		for k in 7:
			var ang := TAU * float(k) / 7.0
			var tip := top + Vector3(cos(ang) * 2.4, -.9 - float(k % 2) * .3, sin(ang) * 2.4)
			b.box(ART.color(Color("6a8a3a")), Transform3D(_along(top, tip) * Basis(Vector3.UP, ang), (top + tip) * .5), Vector3(.7, top.distance_to(tip), .04), {"+y": null, "-y": null})
		b.solid(_t(base.x, 1.5, base.z), Vector3(.5, 3.0, .5))
	# Letreiro alto de neon na beira da estrada (duas faces), sobre dois postes.
	_post_sign(b, dark, Vector3(-21, 6.2, 17.5), Vector3(2.8, 5.6, .3), "motel_sign", 9.0)
	_box(b, concrete, Vector3(-21, .2, 17.5), Vector3(3.4, .4, .9), {"-y": null})
