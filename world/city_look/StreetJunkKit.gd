extends RefCounted
## Malhas dos objetos soltos que sujam a rua de Harbor (StreetJunk): sacos de lixo de várias
## cores e tipos, pilhas, papelão, caixotes, caixas de peixe, tambores enferrujados, cordas,
## redes, pneus velhos, entulho e caçamba; na orla, guarda-sóis, cadeiras de praia e de
## plástico e mesa de bar. Pedido do jogador de 29/10: "as ruas de Harbor são muito limpas
## para uma cidade portuária".
##
## Mesma convenção do CityPropKit (uma ArrayMesh por tipo, origem no chão, frente para +Z, X
## ao longo do meio-fio), com uma diferença: o desgaste vem de UM atlas (harbor_junk_atlas.png,
## BC7 com mipmaps; gerado por tools/build_harbor_junk_atlas.py). Cada face aponta para o quadro
## do material dela (plástico de saco, papelão, madeira gasta, metal enferrujado, plástico
## desbotado, lona listrada...) e a cor do vértice e da instância tinge o quadro. Um material só
## para todas as peças novas: uma variante de shader (pré-aquecida no LateSurfacePrewarm) e
## um draw call por tipo e por chunk, como o resto do kit.
##
## Faces nos dois lados (cull desligado): lona de guarda-sol, folha de papelão e rede são de
## uma face só e precisam aparecer por baixo também; nas peças fechadas a face de trás fica
## escondida pela profundidade e não custa sombreamento.

const ATLAS := preload("res://assets/city_props/harbor_junk_atlas.png")

## Quadros do atlas (4 x 4), mesma ordem de tools/build_harbor_junk_atlas.py.
const TILES := {"bag": 0, "bag_clear": 1, "cardboard": 2, "rubber": 3, "wood_worn": 4, "wood_painted": 5,
	"metal_rust": 6, "metal_galv": 7, "plastic_faded": 8, "fabric_stripes": 9, "fabric_print": 10,
	"canvas_stripes": 11, "rope": 12, "net": 13, "rubble": 14, "litter": 15}
const GRID := 4
## Margem dentro do quadro: com mipmaps o quadro vizinho vazaria na borda.
const INSET := 0.05

const REFUSE_KINDS := ["bag_single", "bag_pile", "bag_torn", "cardboard", "refuse_heap"]
const PORT_KINDS := ["wood_crates", "fish_crates", "rusty_barrels", "rope_coil", "fishing_net", "loose_tires", "rubble", "rubble_skip"]
const SHORE_KINDS := ["beach_parasol", "beach_parasol_b", "beach_chairs", "plastic_chairs", "bar_table"]
const KINDS := ["bag_single", "bag_pile", "bag_torn", "cardboard", "refuse_heap", "wood_crates", "fish_crates", "rusty_barrels", "rope_coil",
	"fishing_net", "loose_tires", "rubble", "rubble_skip", "beach_parasol", "beach_parasol_b", "beach_chairs", "plastic_chairs", "bar_table"]

## Cor por cópia (multiplica vértice e atlas) e quanto cada eixo varia, como CityPropKit.VARIATION.
## Saco solto e mesa de bar mudam de cor de verdade (saco preto, azul, verde; jogo de mesa da
## marca amarela, vermelha ou branco); o resto só desbota um pouco para não repetir igual.
const FADED := [Color("ffffff"), Color("ece8de"), Color("e2e6e4"), Color("f2ead8")]
const VARIATION := {
	"bag_single": {"colors": [Color("3a3c40"), Color("2c2e32"), Color("3a3c40"), Color("27508f"), Color("3a6a3e"), Color("6a6d70"), Color("e8e4d8")], "scale": Vector3(0.18, 0.22, 0.18)},
	"bag_pile": {"colors": FADED, "scale": Vector3(0.12, 0.14, 0.12)},
	"bag_torn": {"colors": FADED, "scale": Vector3(0.1, 0.1, 0.1)},
	"cardboard": {"colors": [Color("ffffff"), Color("e6dccb"), Color("cfc2ad"), Color("bfb39f")], "scale": Vector3(0.1, 0.12, 0.1)},
	"refuse_heap": {"colors": FADED, "scale": Vector3(0.1, 0.12, 0.1)},
	"wood_crates": {"colors": [Color("ffffff"), Color("e6dccb"), Color("d6d0c4"), Color("c8d0c0")], "scale": Vector3(0.05, 0.06, 0.05)},
	"fish_crates": {"colors": FADED, "scale": Vector3(0.03, 0.04, 0.03)},
	"rusty_barrels": {"colors": [Color("ffffff"), Color("e8dccc"), Color("d8d4cc")], "scale": Vector3(0.03, 0.04, 0.03)},
	"rope_coil": {"colors": [Color("ffffff"), Color("e8dcc0"), Color("8fb0e0"), Color("f0a070"), Color("a8d0a8")], "scale": Vector3(0.12, 0.1, 0.12)},
	"fishing_net": {"colors": [Color("ffffff"), Color("c8dcd0"), Color("b8c8e0")], "scale": Vector3(0.1, 0.12, 0.1)},
	"loose_tires": {"colors": [Color("ffffff"), Color("e0dcd4")], "scale": Vector3(0.06, 0.04, 0.06)},
	"rubble": {"colors": [Color("ffffff"), Color("e6e0d4"), Color("d8d0c4")], "scale": Vector3(0.14, 0.18, 0.14)},
	"rubble_skip": {"colors": [Color("e07a2e"), Color("e3b02e"), Color("3d6fb0"), Color("b8352f"), Color("3f7a52"), Color("8a9396")], "scale": Vector3(0.02, 0.02, 0.02)},
	"beach_parasol": {"colors": FADED, "scale": Vector3(0.05, 0.05, 0.05)},
	"beach_parasol_b": {"colors": FADED, "scale": Vector3(0.05, 0.05, 0.05)},
	"beach_chairs": {"colors": FADED, "scale": Vector3(0.03, 0.03, 0.03)},
	"plastic_chairs": {"colors": [Color("f4f2ec"), Color("f4f2ec"), Color("c23b2e"), Color("e3b02e"), Color("2f7a55"), Color("2d6fb6")], "scale": Vector3(0.0, 0.0, 0.0)},
	"bar_table": {"colors": [Color("e8b52e"), Color("e8b52e"), Color("c8322b"), Color("f2f0ea"), Color("2f7a55")], "scale": Vector3(0.0, 0.0, 0.0)},
}

static var _material: StandardMaterial3D


## Material único das peças novas. Retido aqui (static) pela sessão inteira: nenhum chunk cria
## o seu, e o pré-aquecimento compila exatamente este.
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_texture = ATLAS
		_material.vertex_color_use_as_albedo = true
		# Cores escritas em hex sRGB, como as do CityPropKit.
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.86
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_material.resource_name = "StreetJunkAtlas"
	return _material


static func build(kind: String, t: SurfaceTool) -> void:
	match kind:
		"bag_single": _bag_single(t)
		"bag_pile": _bag_pile(t)
		"bag_torn": _bag_torn(t)
		"cardboard": _cardboard(t)
		"refuse_heap": _refuse_heap(t)
		"wood_crates": _wood_crates(t)
		"fish_crates": _fish_crates(t)
		"rusty_barrels": _rusty_barrels(t)
		"rope_coil": _rope_coil(t)
		"fishing_net": _fishing_net(t)
		"loose_tires": _loose_tires(t)
		"rubble": _rubble(t)
		"rubble_skip": _rubble_skip(t)
		"beach_parasol": _beach_parasol(t, "fabric_stripes")
		"beach_parasol_b": _beach_parasol(t, "fabric_print")
		"beach_chairs": _beach_chairs(t)
		"plastic_chairs": _plastic_chairs(t)
		"bar_table": _bar_table(t)


# --- UV no atlas ---

## (u, v) de 0 a 1 dentro do quadro `tile` para a coordenada do atlas.
static func atlas_uv(tile: String, uv: Vector2) -> Vector2:
	var index: int = TILES[tile]
	var cell := Vector2(index % GRID, floori(float(index) / GRID))
	var inner := Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0)) * (1.0 - 2.0 * INSET) + Vector2.ONE * INSET
	return (cell + inner) / float(GRID)


## Deslocamento determinístico dentro do quadro para cópias da mesma face não repetirem o desenho.
static func _offset(seed: int, span: Vector2) -> Vector2:
	var noise := fposmod(sin(float(seed) * 12.9898) * 43758.5453, 1.0)
	var other := fposmod(sin(float(seed) * 78.233) * 24634.6345, 1.0)
	return Vector2((1.0 - span.x) * noise, (1.0 - span.y) * other)


# --- Primitivas com UV ---

## Caixa como CityPropKit.box (mesma ordem de faces), com `basis` livre e UV por face:
## `tile_m` metros cabem num quadro inteiro; face maior que isso encolhe para caber.
static func box(t: SurfaceTool, center: Vector3, size: Vector3, color: Color, tile: String, basis := Basis(), tile_m := 1.0, seed := 0) -> void:
	var h := size * 0.5
	var local := []
	var corners := []
	for i in 8:
		var point := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		local.append(point)
		corners.append(center + basis * point)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	# Eixos (u, v) de cada face: v é a altura nas faces de lado, para o desenho ficar em pé.
	var axes := [[0, 1], [0, 1], [0, 2], [0, 2], [2, 1], [2, 1]]
	t.set_color(color)
	for f in faces.size():
		var face: Array = faces[f]
		var ua: int = axes[f][0]
		var va: int = axes[f][1]
		var span := Vector2(size[ua], size[va]) / tile_m
		var fit := 1.0 / maxf(1.0, maxf(span.x, span.y))
		span *= fit
		var shift := _offset(seed * 7 + f, span)
		var uvs := []
		for corner in face:
			var p: Vector3 = local[corner]
			var u := (p[ua] + h[ua]) / tile_m * fit
			var v := (h[va] - p[va]) / tile_m * fit
			uvs.append(atlas_uv(tile, Vector2(u, v) + shift))
		for index in [0, 1, 2, 0, 2, 3]:
			t.set_uv(uvs[index])
			t.add_vertex(corners[face[index]])


## Cilindro como CityPropKit.cylinder (paredes e tampa de cima), com eixo `basis.y`.
static func cylinder(t: SurfaceTool, base: Vector3, radius: float, height: float, color: Color, tile: String, sides := 10, top_radius := -1.0, basis := Basis(), cap := true, seed := 0) -> void:
	var top := radius if top_radius < 0.0 else top_radius
	t.set_color(color)
	var around := minf(1.0, TAU * radius / 1.2)
	var tall := minf(1.0, height / 1.0)
	var shift := _offset(seed, Vector2(around, tall))
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := base + basis * (d0 * radius)
		var b1 := base + basis * (d1 * radius)
		var t0 := base + basis * (d0 * top + Vector3.UP * height)
		var t1 := base + basis * (d1 * top + Vector3.UP * height)
		var u0 := float(i) / sides * around
		var u1 := float(i + 1) / sides * around
		var uv_b0 := atlas_uv(tile, Vector2(u0, tall) + shift)
		var uv_b1 := atlas_uv(tile, Vector2(u1, tall) + shift)
		var uv_t0 := atlas_uv(tile, Vector2(u0, 0.0) + shift)
		var uv_t1 := atlas_uv(tile, Vector2(u1, 0.0) + shift)
		t.set_uv(uv_b0); t.add_vertex(b0)
		t.set_uv(uv_b1); t.add_vertex(b1)
		t.set_uv(uv_t0); t.add_vertex(t0)
		t.set_uv(uv_b1); t.add_vertex(b1)
		t.set_uv(uv_t1); t.add_vertex(t1)
		t.set_uv(uv_t0); t.add_vertex(t0)
		if not cap: continue
		var center := base + basis * (Vector3.UP * height)
		var disc := minf(1.0, top * 2.0)
		t.set_uv(atlas_uv(tile, Vector2(0.5, 0.5) * disc + shift)); t.add_vertex(center)
		t.set_uv(atlas_uv(tile, (Vector2(cos(a0), sin(a0)) * 0.5 + Vector2(0.5, 0.5)) * disc + shift)); t.add_vertex(t0)
		t.set_uv(atlas_uv(tile, (Vector2(cos(a1), sin(a1)) * 0.5 + Vector2(0.5, 0.5)) * disc + shift)); t.add_vertex(t1)


## Anel (pneu, rolo de corda): toro de `segments` x `sides`, eixo `basis.y`. Mesma ordem de
## triângulos da parede do cilindro (normal para fora).
static func ring(t: SurfaceTool, center: Vector3, major: float, minor: float, color: Color, tile: String, basis := Basis(), segments := 14, sides := 6, squash := 1.0) -> void:
	t.set_color(color)
	var point := func(i: int, j: int) -> Vector3:
		var theta := TAU * float(i) / segments
		var phi := TAU * float(j) / sides
		var reach := major + minor * cos(phi)
		return center + basis * Vector3(cos(theta) * reach, minor * sin(phi) * squash, sin(theta) * reach)
	for i in segments:
		for j in sides:
			var p00: Vector3 = point.call(i, j)
			var p10: Vector3 = point.call(i + 1, j)
			var p01: Vector3 = point.call(i, j + 1)
			var p11: Vector3 = point.call(i + 1, j + 1)
			var u0 := float(i) / segments
			var u1 := float(i + 1) / segments
			var v0 := float(j) / sides
			var v1 := float(j + 1) / sides
			t.set_uv(atlas_uv(tile, Vector2(u0, v0))); t.add_vertex(p00)
			t.set_uv(atlas_uv(tile, Vector2(u1, v0))); t.add_vertex(p10)
			t.set_uv(atlas_uv(tile, Vector2(u0, v1))); t.add_vertex(p01)
			t.set_uv(atlas_uv(tile, Vector2(u1, v0))); t.add_vertex(p10)
			t.set_uv(atlas_uv(tile, Vector2(u1, v1))); t.add_vertex(p11)
			t.set_uv(atlas_uv(tile, Vector2(u0, v1))); t.add_vertex(p01)


## Volume mole (saco cheio, monte de entulho, rede embolada): o CityPropKit.blob com UV
## (u em volta, v da base ao topo) e tom por triângulo. `tip` puxa o polo (nó do saco).
static func blob(t: SurfaceTool, base: Vector3, radius: Vector2, height: float, color: Color, tile: String, sides := 7, variant := 0, tip := 0.0, roughness := 0.2) -> void:
	var rings := [[0.0, 0.92, -0.16], [0.48, 1.04, -0.04], [0.82, 0.72, 0.06]]
	var points := []
	for r in rings.size():
		var row := []
		for i in sides + 1:
			var k := i % sides
			var angle := TAU * (float(k) + 0.35 * sin(float(k * 3 + variant))) / sides + float(variant) * 0.9
			var wobble := 1.0 + roughness * sin(float(k * 7 + variant * 5 + r * 11) * 1.3)
			var reach: float = rings[r][1] * wobble
			var lift: float = rings[r][0] + (0.0 if r == 0 else roughness * 0.35 * sin(float(k * 5 + variant * 3)))
			row.append(base + Vector3(cos(angle) * radius.x * reach, height * lift, sin(angle) * radius.y * reach))
		points.append(row)
	var face := 0
	var around := minf(1.0, TAU * maxf(radius.x, radius.y) / 1.4)
	for r in rings.size() - 1:
		for i in sides:
			var l0: Vector3 = points[r][i]
			var l1: Vector3 = points[r][i + 1]
			var u0p: Vector3 = points[r + 1][i]
			var u1p: Vector3 = points[r + 1][i + 1]
			var ua := float(i) / sides * around
			var ub := float(i + 1) / sides * around
			var va := 1.0 - float(rings[r][0])
			var vb := 1.0 - float(rings[r + 1][0])
			t.set_color(_mottle(color, rings[r][2], face, variant)); face += 1
			t.set_uv(atlas_uv(tile, Vector2(ua, va))); t.add_vertex(l0)
			t.set_uv(atlas_uv(tile, Vector2(ub, va))); t.add_vertex(l1)
			t.set_uv(atlas_uv(tile, Vector2(ua, vb))); t.add_vertex(u0p)
			t.set_color(_mottle(color, rings[r][2], face, variant)); face += 1
			t.set_uv(atlas_uv(tile, Vector2(ub, va))); t.add_vertex(l1)
			t.set_uv(atlas_uv(tile, Vector2(ub, vb))); t.add_vertex(u1p)
			t.set_uv(atlas_uv(tile, Vector2(ua, vb))); t.add_vertex(u0p)
	var pole := base + Vector3.UP * height * (0.94 + tip)
	for i in sides:
		t.set_color(_mottle(color, rings[-1][2] + 0.04, face, variant)); face += 1
		var ua := float(i) / sides * around
		var ub := float(i + 1) / sides * around
		t.set_uv(atlas_uv(tile, Vector2((ua + ub) * 0.5, 0.0))); t.add_vertex(pole)
		t.set_uv(atlas_uv(tile, Vector2(ua, 0.18))); t.add_vertex(points[-1][i])
		t.set_uv(atlas_uv(tile, Vector2(ub, 0.18))); t.add_vertex(points[-1][i + 1])


## Folha deitada (lixo espalhado, papelão no chão, rede aberta), virada para cima, girada `yaw`.
static func sheet(t: SurfaceTool, center: Vector3, size: Vector2, color: Color, tile: String, yaw := 0.0, tilt := Basis(), seed := 0) -> void:
	var basis := Basis(Vector3.UP, yaw) * tilt
	var h := size * 0.5
	var corners := [Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, -h.y), Vector3(h.x, 0, h.y), Vector3(-h.x, 0, h.y)]
	var span := Vector2(minf(1.0, size.x), minf(1.0, size.y))
	var shift := _offset(seed, span)
	var uvs := [Vector2(0, 0), Vector2(span.x, 0), span, Vector2(0, span.y)]
	t.set_color(color)
	for index in [0, 1, 3, 1, 2, 3]:
		t.set_uv(atlas_uv(tile, uvs[index] + shift))
		t.add_vertex(center + basis * corners[index])


## Barra fina de `a` até `b` (perna de cadeira, vergalhão, armação).
static func bar(t: SurfaceTool, a: Vector3, b: Vector3, thickness: float, color: Color, tile: String) -> void:
	var direction := b - a
	var length := direction.length()
	if length < 0.001: return
	box(t, (a + b) * 0.5, Vector3(thickness, length, thickness), color, tile, Basis(Quaternion(Vector3.UP, direction / length)), 1.0)


## Tom por triângulo, como CityPropKit._mottle (copiado: o kit carrega este arquivo e a volta
## de preload entre os dois não precisa existir).
static func _mottle(color: Color, amount: float, face: int, variant: int) -> Color:
	var noise := fposmod(sin(float(face * 37 + variant * 101) * 12.9898) * 43758.5453, 1.0)
	var shade := amount + (noise - 0.6) * 0.14
	return color.lightened(shade) if shade > 0.0 else color.darkened(-shade)


# --- Lixo ---

## Saco amarrado: corpo estufado, nó puxado para cima e as duas pontas da amarração.
static func _bag(t: SurfaceTool, at: Vector3, radius: Vector2, height: float, color: Color, variant: int, tile := "bag") -> void:
	blob(t, at, radius, height, color, tile, 8, variant, 0.2, 0.16)
	var top := at + Vector3(0, height * 1.12, 0)
	for side in [-1.0, 1.0]:
		box(t, top + Vector3(side * 0.035, 0.03, 0), Vector3(0.05, 0.09, 0.025), color.darkened(0.08), tile, Basis(Vector3.BACK, side * 0.55))


static func _bag_single(t: SurfaceTool) -> void:
	# Vértice claro: a cor do saco (preto, azul, verde, cinza, branco) vem da instância.
	_bag(t, Vector3.ZERO, Vector2(0.27, 0.24), 0.5, Color("d6d6d4"), 1)


## Pilha de saída do lixo: dois pretos, um azul, um verde, um transparente com o lixo
## aparecendo, um deitado por cima e sacolinhas de mercado.
static func _bag_pile(t: SurfaceTool) -> void:
	for part in 8: _bag_pile_part(t, part)


## Peças da pilha na ordem de sempre (a malha inteira continua idêntica).
static func _bag_pile_part(t: SurfaceTool, part: int) -> void:
	match part:
		0: _bag(t, Vector3(-0.25, 0, -0.1), Vector2(0.3, 0.27), 0.55, Color("2c2e31"), 2)
		1: _bag(t, Vector3(0.2, 0, -0.15), Vector2(0.28, 0.25), 0.5, Color("37393d"), 5)
		2: _bag(t, Vector3(0.05, 0, 0.25), Vector2(0.26, 0.24), 0.46, Color("2f5f9e"), 7)
		3: _bag(t, Vector3(0.46, 0, 0.18), Vector2(0.24, 0.22), 0.42, Color("3a6a3e"), 3)
		4: _bag(t, Vector3(-0.46, 0, 0.24), Vector2(0.22, 0.2), 0.4, Color("ffffff"), 4, "bag_clear")
		5: blob(t, Vector3(-0.02, 0.36, -0.05), Vector2(0.32, 0.2), 0.24, Color("2c2e31"), "bag", 8, 9, 0.0, 0.2)
		6: _bag(t, Vector3(0.62, 0, -0.22), Vector2(0.12, 0.11), 0.2, Color("e8e6de"), 6)
		7: _bag(t, Vector3(-0.6, 0, -0.26), Vector2(0.11, 0.1), 0.18, Color("4a7ac0"), 8)


## Sacos soltos da pilha atropelada (playtest 30/10: "tem 4-5 sacolas, elas ficam coladas"): uma
## malha por saco, no mesmo lugar e com o mesmo material da pilha inteira, para cada uma virar um
## destroço próprio. O saco deitado por cima vai com o de baixo; as sacolinhas, com o vizinho.
## Montado uma vez (StreetPhysics._ready) e retido; o quadro do choque só reaproveita.
const PILE_PIECES := {"bag_pile": [[0, 5], [1], [2], [3, 6], [4, 7]]}
static var _pieces := {}

static func pieces(kind: String) -> Array:
	if _pieces.has(kind): return _pieces[kind]
	var result := []
	for group in PILE_PIECES.get(kind, []):
		var t := SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Mesmas opções de CityPropKit.mesh: mesma variante de shader da pilha inteira.
		t.set_material(material())
		t.set_smooth_group(-1)
		for part in group:
			match kind:
				"bag_pile": _bag_pile_part(t, part)
		t.generate_normals()
		result.append(t.commit())
	_pieces[kind] = result
	return result


## Saco rasgado (cachorro, catador): murcho, boca aberta mostrando o lixo, e o que caiu espalhado
## na frente: embalagens, latas, caixa de comida, garrafa e papel amassado.
static func _bag_torn(t: SurfaceTool) -> void:
	blob(t, Vector3.ZERO, Vector2(0.34, 0.28), 0.3, Color("2c2e31"), "bag", 8, 4, 0.05, 0.28)
	sheet(t, Vector3(0.02, 0.24, 0.12), Vector2(0.34, 0.22), Color("ffffff"), "litter", 0.2, Basis(Vector3.RIGHT, 0.45), 3)
	var spill := [[Vector3(0.1, 0.006, 0.52), Vector2(0.5, 0.36), 0.3], [Vector3(-0.38, 0.007, 0.42), Vector2(0.36, 0.3), 1.1],
		[Vector3(0.48, 0.008, 0.3), Vector2(0.3, 0.26), 2.0], [Vector3(-0.1, 0.009, 0.86), Vector2(0.26, 0.22), 0.7]]
	for i in spill.size():
		sheet(t, spill[i][0], spill[i][1], Color("ffffff"), "litter", spill[i][2], Basis(), i + 5)
	var cans := [[Vector3(0.32, 0.033, 0.62), Color("c0392b"), 0.4], [Vector3(-0.28, 0.033, 0.7), Color("c8ccd0"), 1.9], [Vector3(0.62, 0.033, 0.5), Color("2d6fb6"), 2.6]]
	for can in cans:
		box(t, can[0], Vector3(0.12, 0.065, 0.065), can[1], "metal_galv", Basis(Vector3.UP, can[2]), 0.3)
	box(t, Vector3(-0.5, 0.04, 0.12), Vector3(0.2, 0.08, 0.15), Color("e8e0d0"), "cardboard", Basis(Vector3.UP, 0.5), 0.4)
	box(t, Vector3(0.05, 0.035, 0.98), Vector3(0.26, 0.07, 0.07), Color("6f9f6a"), "plastic_faded", Basis(Vector3.UP, -0.7), 0.4)
	for spot in [Vector3(-0.2, 0, 0.55), Vector3(0.42, 0, 0.82), Vector3(-0.55, 0, 0.3)]:
		blob(t, spot, Vector2(0.06, 0.055), 0.06, Color("e6e2d8"), "plastic_faded", 5, int(spot.x * 10.0) + 4, 0.0, 0.35)


## Papelão de loja para o caminhão: folhas desmontadas no chão, caixa fechada com fita, caixa
## aberta com as abas para fora e uma molhada e amassada.
static func _cardboard(t: SurfaceTool) -> void:
	var tones := [Color("d0ac80"), Color("c09a6e"), Color("b08a60")]
	for i in 3:
		box(t, Vector3(0.12, 0.012 + i * 0.022, 0.05), Vector3(0.95, 0.02, 0.72), tones[i], "cardboard", Basis(Vector3.UP, 0.12 - i * 0.14), 0.95, i)
	box(t, Vector3(-0.46, 0.21, -0.08), Vector3(0.5, 0.4, 0.4), Color("c8a478"), "cardboard", Basis(Vector3.UP, 0.2), 0.6, 4)
	var open := Vector3(0.42, 0.07, 0.12)
	var size := Vector3(0.46, 0.34, 0.36)
	var turn := Basis(Vector3.UP, -0.25)
	var wall := Color("b8946a")
	box(t, open + turn * Vector3(0, size.y * 0.5, size.z * 0.5), Vector3(size.x, size.y, 0.012), wall, "cardboard", turn, 0.6, 5)
	box(t, open + turn * Vector3(0, size.y * 0.5, -size.z * 0.5), Vector3(size.x, size.y, 0.012), wall, "cardboard", turn, 0.6, 6)
	box(t, open + turn * Vector3(size.x * 0.5, size.y * 0.5, 0), Vector3(0.012, size.y, size.z), wall, "cardboard", turn, 0.6, 7)
	box(t, open + turn * Vector3(-size.x * 0.5, size.y * 0.5, 0), Vector3(0.012, size.y, size.z), wall, "cardboard", turn, 0.6, 8)
	box(t, open + turn * Vector3(0, 0.006, 0), Vector3(size.x, 0.012, size.z), wall.darkened(0.2), "cardboard", turn, 0.6, 9)
	for side in [-1.0, 1.0]:
		var flap := turn * Basis(Vector3.RIGHT, side * 0.9)
		box(t, open + turn * Vector3(0, size.y + 0.06, side * (size.z * 0.5 + 0.06)), Vector3(size.x, 0.16, 0.01), wall, "cardboard", flap, 0.6, 10)
	box(t, Vector3(-0.05, 0.07, 0.42), Vector3(0.5, 0.14, 0.34), Color("9c8466"), "cardboard", Basis(Vector3.UP, 0.6) * Basis(Vector3.BACK, 0.12), 0.6, 11)


## Monte de esquina: sacos de todas as cores, papelão, cadeira de plástico quebrada, caixote e
## lixo miúdo por baixo. É o "ponto de lixo" que a coleta ainda não passou.
static func _refuse_heap(t: SurfaceTool) -> void:
	sheet(t, Vector3(0.0, 0.004, 0.1), Vector2(1.8, 1.3), Color("d8d4cc"), "litter", 0.15, Basis(), 1)
	var bags := [[Vector3(-0.5, 0, -0.25), Vector2(0.32, 0.28), 0.56, Color("2c2e31")], [Vector3(0.0, 0, -0.32), Vector2(0.3, 0.27), 0.52, Color("37393d")],
		[Vector3(0.5, 0, -0.2), Vector2(0.28, 0.25), 0.48, Color("2f5f9e")], [Vector3(-0.3, 0, 0.22), Vector2(0.26, 0.24), 0.44, Color("3a6a3e")],
		[Vector3(0.25, 0, 0.2), Vector2(0.27, 0.24), 0.46, Color("2c2e31")], [Vector3(0.75, 0, 0.25), Vector2(0.2, 0.18), 0.34, Color("ffffff")]]
	for i in bags.size():
		_bag(t, bags[i][0], bags[i][1], bags[i][2], bags[i][3], i * 3 + 1, "bag_clear" if i == 5 else "bag")
	blob(t, Vector3(-0.18, 0.4, -0.2), Vector2(0.34, 0.22), 0.26, Color("2c2e31"), "bag", 8, 11, 0.0, 0.22)
	box(t, Vector3(-0.95, 0.2, 0.05), Vector3(0.45, 0.4, 0.38), Color("c8a478"), "cardboard", Basis(Vector3.UP, 0.4), 0.6, 2)
	box(t, Vector3(-0.85, 0.03, 0.5), Vector3(0.8, 0.02, 0.6), Color("b08a60"), "cardboard", Basis(Vector3.UP, -0.3) * Basis(Vector3.RIGHT, 0.05), 0.8, 3)
	# Cadeira de plástico quebrada, tombada de lado em cima do monte.
	var chair := Basis(Vector3.UP, 0.8) * Basis(Vector3.BACK, 1.2)
	var at := Vector3(0.45, 0.42, 0.05)
	box(t, at, Vector3(0.42, 0.03, 0.42), Color("ece9e0"), "plastic_faded", chair, 0.5, 4)
	box(t, at + chair * Vector3(0, 0.22, -0.2), Vector3(0.42, 0.4, 0.03), Color("ece9e0"), "plastic_faded", chair, 0.5, 5)
	for x in [-0.18, 0.18]: box(t, at + chair * Vector3(x, -0.2, 0.18), Vector3(0.035, 0.4, 0.035), Color("dcd8cc"), "plastic_faded", chair)
	box(t, Vector3(0.95, 0.17, -0.3), Vector3(0.5, 0.32, 0.36), Color("b8a080"), "wood_worn", Basis(Vector3.UP, -0.35), 0.5, 6)


# --- Porto e oficina ---

## Caixote de madeira: corpo de tábuas (o quadro tem as frestas) e uma ripa de reforço nas pontas.
static func _crate(t: SurfaceTool, center: Vector3, size: Vector3, color: Color, yaw: float, seed: int, tile := "wood_worn") -> void:
	var turn := Basis(Vector3.UP, yaw)
	box(t, center, size, color, tile, turn, 0.55, seed)
	for side in [-1.0, 1.0]:
		box(t, center + turn * Vector3(side * (size.x * 0.5 + 0.012), 0, 0), Vector3(0.025, size.y, 0.07), color.darkened(0.25), tile, turn, 0.5, seed + 1)


static func _wood_crates(t: SurfaceTool) -> void:
	_crate(t, Vector3(-0.3, 0.21, 0), Vector3(0.6, 0.42, 0.45), Color("c8b090"), 0.0, 1)
	_crate(t, Vector3(-0.28, 0.63, 0.02), Vector3(0.6, 0.42, 0.45), Color("b8a080"), 0.08, 2)
	_crate(t, Vector3(0.42, 0.19, 0.08), Vector3(0.55, 0.38, 0.42), Color("7d9cb2"), -0.2, 3, "wood_painted")
	box(t, Vector3(0.35, 0.016, -0.42), Vector3(0.62, 0.03, 0.12), Color("8a7458"), "wood_worn", Basis(Vector3.UP, 0.3), 0.6, 4)
	box(t, Vector3(0.55, 0.016, -0.3), Vector3(0.6, 0.03, 0.12), Color("9a8466"), "wood_worn", Basis(Vector3.UP, -0.2), 0.6, 5)


## Caixas plásticas de peixe empilhadas (azul, laranja, cinza), com as alças vazadas escuras.
static func _fish_crates(t: SurfaceTool) -> void:
	var stacks := [[Vector3(-0.36, 0, 0), [Color("2d6fb6"), Color("d8692b"), Color("2d6fb6"), Color("8a9396")]], [Vector3(0.38, 0, 0.06), [Color("d8692b"), Color("b23a2e")]]]
	for s in stacks.size():
		var base: Vector3 = stacks[s][0]
		var colors: Array = stacks[s][1]
		for i in colors.size():
			var yaw := 0.06 * float((i * 5 + s * 3) % 3 - 1)
			var turn := Basis(Vector3.UP, yaw)
			var center := base + Vector3(0.01 * float(i % 2), 0.12 + i * 0.245, 0)
			box(t, center, Vector3(0.62, 0.24, 0.42), colors[i], "plastic_faded", turn, 0.65, s * 10 + i)
			for side in [-1.0, 1.0]:
				box(t, center + turn * Vector3(side * 0.312, 0.05, 0), Vector3(0.01, 0.05, 0.16), Color("1d1f20"), "plastic_faded", turn)


## Tambor de aço: corpo, dois frisos e tampa mais escura; deitado quando `basis` gira o eixo.
static func _drum(t: SurfaceTool, base: Vector3, color: Color, basis := Basis(), seed := 0) -> void:
	cylinder(t, base, 0.29, 0.88, color, "metal_rust", 12, -1.0, basis, true, seed)
	for y in [0.29, 0.59]:
		cylinder(t, base + basis * Vector3(0, y, 0), 0.3, 0.03, color.darkened(0.25), "metal_rust", 12, -1.0, basis, false, seed + 1)
	box(t, base + basis * Vector3(0.14, 0.89, 0.05), Vector3(0.06, 0.02, 0.06), Color("3a3f41"), "metal_galv", basis, 0.2)


static func _rusty_barrels(t: SurfaceTool) -> void:
	_drum(t, Vector3(-0.32, 0, 0), Color("2c5a8a"), Basis(), 1)
	_drum(t, Vector3(0.3, 0, -0.12), Color("8e3a2a"), Basis(Vector3.UP, 0.7), 2)
	# Terceiro tombado na frente, o eixo deitado ao longo da calçada.
	_drum(t, Vector3(-0.35, 0.29, 0.52), Color("6d6a3a"), Basis(Vector3.BACK, -PI * 0.5), 3)


## Rolo de cabo de amarração: três voltas empilhadas, o miolo e a ponta solta; rolo menor ao lado.
static func _rope_coil(t: SurfaceTool) -> void:
	var rope := Color("d8c8a0")
	cylinder(t, Vector3.ZERO, 0.3, 0.02, rope.darkened(0.2), "rope", 10)
	for i in 3:
		ring(t, Vector3(0, 0.045 + i * 0.085, 0), 0.34 - i * 0.04, 0.045, rope, "rope", Basis(Vector3.UP, i * 0.7), 14, 5)
	var tail := [Vector3(0.36, 0.04, 0.0), Vector3(0.55, 0.035, 0.12), Vector3(0.7, 0.03, 0.3), Vector3(0.78, 0.03, 0.5)]
	for i in tail.size() - 1:
		bar(t, tail[i], tail[i + 1], 0.07, rope, "rope")
	for i in 2:
		ring(t, Vector3(0.55, 0.035 + i * 0.065, -0.4), 0.19 - i * 0.03, 0.035, Color("3a6fb0"), "rope", Basis(), 12, 5)


## Rede de pesca embolada com boias, aberta um pouco no chão, e um rolo de cabo.
static func _fishing_net(t: SurfaceTool) -> void:
	blob(t, Vector3(0, 0, 0), Vector2(0.55, 0.45), 0.32, Color("ffffff"), "net", 9, 2, 0.0, 0.3)
	blob(t, Vector3(0.45, 0, 0.15), Vector2(0.4, 0.35), 0.26, Color("e8f0ea"), "net", 8, 5, 0.0, 0.3)
	blob(t, Vector3(-0.42, 0, 0.2), Vector2(0.35, 0.3), 0.22, Color("dfe8e2"), "net", 8, 8, 0.0, 0.3)
	sheet(t, Vector3(0.1, 0.006, 0.6), Vector2(1.1, 0.5), Color("ffffff"), "net", 0.1, Basis(), 3)
	var floats := [[Vector3(0.1, 0.28, 0.12), Color("e8692b")], [Vector3(-0.3, 0.2, -0.15), Color("efe9da")], [Vector3(0.5, 0.22, 0.0), Color("e8692b")],
		[Vector3(-0.55, 0.02, 0.55), Color("efe9da")], [Vector3(0.55, 0.02, 0.7), Color("e8692b")], [Vector3(0.0, 0.02, 0.78), Color("efe9da")]]
	for f in floats.size():
		blob(t, floats[f][0], Vector2(0.075, 0.065), 0.11, floats[f][1], "plastic_faded", 6, f, 0.0, 0.1)
	ring(t, Vector3(-0.7, 0.03, -0.35), 0.2, 0.03, Color("c8b48a"), "rope", Basis(), 12, 5)


## Pneus velhos: um deitado, outro em cima e um em pé encostado nos dois.
static func _loose_tires(t: SurfaceTool) -> void:
	var rubber := Color("9a9a98")
	ring(t, Vector3(-0.3, 0.1, 0), 0.26, 0.1, rubber, "rubber", Basis(), 14, 6)
	ring(t, Vector3(-0.27, 0.3, 0.03), 0.26, 0.1, rubber.darkened(0.08), "rubber", Basis(Vector3.UP, 0.4), 14, 6)
	ring(t, Vector3(0.38, 0.35, 0.05), 0.26, 0.1, rubber, "rubber", Basis(Vector3.BACK, PI * 0.5 - 0.25), 14, 6)


# --- Obra ---

## Entulho de reforma: monte de restos, placas de concreto, tijolos, vergalhão e saco de cimento.
static func _rubble(t: SurfaceTool) -> void:
	blob(t, Vector3.ZERO, Vector2(0.8, 0.6), 0.38, Color("d4d0c8"), "rubble", 9, 3, 0.0, 0.3)
	var slabs := [[Vector3(-0.45, 0.2, 0.25), Vector3(0.45, 0.08, 0.3), Vector3(0.4, 0.3, 0.2)], [Vector3(0.35, 0.3, -0.1), Vector3(0.38, 0.1, 0.26), Vector3(-0.5, 0.9, 0.3)],
		[Vector3(0.1, 0.12, 0.55), Vector3(0.3, 0.07, 0.22), Vector3(0.2, -0.4, 0.1)], [Vector3(-0.2, 0.36, -0.25), Vector3(0.28, 0.12, 0.2), Vector3(0.6, 0.1, -0.5)]]
	for i in slabs.size():
		var turn := Basis.from_euler(slabs[i][2])
		box(t, slabs[i][0], slabs[i][1], Color("a8a49c").darkened(0.08 * float(i % 2)), "rubble", turn, 0.5, i)
	for i in 5:
		var spot := Vector3(-0.6 + i * 0.3, 0.05 + 0.06 * float(i % 2), 0.45 - 0.2 * float(i % 3))
		box(t, spot, Vector3(0.2, 0.06, 0.1), Color("b0603e"), "rubble", Basis(Vector3.UP, i * 0.9) * Basis(Vector3.BACK, 0.2 * float(i % 2)), 0.3, 10 + i)
	bar(t, Vector3(0.2, 0.2, 0.1), Vector3(0.7, 0.55, -0.35), 0.022, Color("7a4a2a"), "metal_rust")
	bar(t, Vector3(-0.1, 0.25, -0.1), Vector3(-0.75, 0.5, -0.4), 0.022, Color("7a4a2a"), "metal_rust")
	box(t, Vector3(0.75, 0.07, 0.35), Vector3(0.42, 0.13, 0.3), Color("d8d0c0"), "plastic_faded", Basis(Vector3.UP, -0.4), 0.5, 20)


## Caçamba de entulho (estacionária): caixa de aço aberta com as pontas inclinadas, aba
## reforçada em cima, sapatas, alças de içar e o entulho aparecendo por cima.
static func _rubble_skip(t: SurfaceTool) -> void:
	var paint := Color("ffffff")
	box(t, Vector3(0, 0.12, 0), Vector3(2.5, 0.06, 1.5), paint.darkened(0.3), "metal_rust", Basis(), 1.5, 1)
	for z in [-0.55, 0.55]: box(t, Vector3(0, 0.05, z), Vector3(2.6, 0.1, 0.12), Color("3a3f41"), "metal_galv", Basis(), 1.0, 2)
	for side in [-1.0, 1.0]:
		box(t, Vector3(0, 0.62, side * 0.75), Vector3(2.85, 1.0, 0.05), paint, "metal_rust", Basis(), 1.5, 3 + int(side))
		var slant := Basis(Vector3.BACK, side * 0.32)
		box(t, Vector3(side * 1.4, 0.62, 0), Vector3(0.05, 1.06, 1.5), paint, "metal_rust", slant, 1.5, 6 + int(side))
		box(t, Vector3(0, 1.14, side * 0.77), Vector3(3.2, 0.08, 0.1), paint.darkened(0.15), "metal_rust", Basis(), 1.5, 8)
		box(t, Vector3(side * 1.57, 1.14, 0), Vector3(0.1, 0.08, 1.6), paint.darkened(0.15), "metal_rust", Basis(), 1.5, 9)
		box(t, Vector3(side * 1.45, 0.85, 0.5), Vector3(0.14, 0.12, 0.08), Color("3a3f41"), "metal_galv", Basis(), 0.5)
		box(t, Vector3(side * 1.45, 0.85, -0.5), Vector3(0.14, 0.12, 0.08), Color("3a3f41"), "metal_galv", Basis(), 0.5)
		for x in [-0.8, 0.0, 0.8]:
			box(t, Vector3(x, 0.62, side * 0.79), Vector3(0.07, 0.9, 0.04), paint.darkened(0.12), "metal_rust", Basis(), 1.0, 10)
	blob(t, Vector3(0, 0.8, 0), Vector2(1.25, 0.62), 0.42, Color("d4d0c8"), "rubble", 10, 6, 0.0, 0.3)
	for i in 4:
		var spot := Vector3(-0.9 + i * 0.6, 1.05 + 0.06 * float(i % 2), 0.2 - 0.15 * float(i % 3))
		box(t, spot, Vector3(0.32, 0.08, 0.22), Color("a8a49c"), "rubble", Basis.from_euler(Vector3(0.3 * float(i % 2), i * 1.1, 0.25)), 0.5, 30 + i)
	bar(t, Vector3(0.6, 1.0, -0.3), Vector3(1.2, 1.45, -0.1), 0.03, Color("7a4a2a"), "metal_rust")
	box(t, Vector3(-0.5, 1.12, -0.3), Vector3(0.9, 0.04, 0.2), Color("b8a080"), "wood_worn", Basis(Vector3.UP, 0.4) * Basis(Vector3.BACK, 0.18), 0.9, 34)


# --- Orla ---

## Guarda-sol de praia: base de plástico com areia, haste inclinada e copa de oito gomos com aba.
## O desenho (listras ou estampa) vem do quadro; cada gomo usa o quadro inteiro de u (largura do
## gomo) e v (do topo à borda), então as listras abrem em leque como no tecido de verdade.
static func _beach_parasol(t: SurfaceTool, fabric: String) -> void:
	cylinder(t, Vector3.ZERO, 0.22, 0.13, Color("4a4d50"), "plastic_faded", 10, 0.18)
	var tilt := Basis(Vector3.RIGHT, -0.14) * Basis(Vector3.BACK, 0.06)
	var top := tilt * Vector3(0, 2.15, 0)
	box(t, tilt * Vector3(0, 1.08, 0), Vector3(0.035, 2.16, 0.035), Color("e8e8e0"), "metal_galv", tilt, 1.0)
	var sides := 8
	var radius := 1.15
	var apex := top + tilt * Vector3(0, 0.36, 0)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var p0 := top + tilt * (Vector3(cos(a0), 0, sin(a0)) * radius)
		var p1 := top + tilt * (Vector3(cos(a1), 0, sin(a1)) * radius)
		var d0 := p0 + tilt * Vector3(0, -0.12, 0)
		var d1 := p1 + tilt * Vector3(0, -0.12, 0)
		t.set_color(Color("ffffff"))
		# Mesma ordem do topo de cylinder(): normal para cima e para fora.
		t.set_uv(atlas_uv(fabric, Vector2(0.5, 0.0))); t.add_vertex(apex)
		t.set_uv(atlas_uv(fabric, Vector2(0.0, 0.88))); t.add_vertex(p0)
		t.set_uv(atlas_uv(fabric, Vector2(1.0, 0.88))); t.add_vertex(p1)
		t.set_uv(atlas_uv(fabric, Vector2(0.0, 1.0))); t.add_vertex(d0)
		t.set_uv(atlas_uv(fabric, Vector2(1.0, 1.0))); t.add_vertex(d1)
		t.set_uv(atlas_uv(fabric, Vector2(0.0, 0.88))); t.add_vertex(p0)
		t.set_uv(atlas_uv(fabric, Vector2(1.0, 1.0))); t.add_vertex(d1)
		t.set_uv(atlas_uv(fabric, Vector2(1.0, 0.88))); t.add_vertex(p1)
		t.set_uv(atlas_uv(fabric, Vector2(0.0, 0.88))); t.add_vertex(p0)
	box(t, apex + tilt * Vector3(0, 0.03, 0), Vector3(0.07, 0.07, 0.07), Color("e8e8e0"), "metal_galv", tilt, 0.2)


## Cadeira de praia de alumínio com lona listrada, reclinada; frente para +Z.
static func _beach_chair(t: SurfaceTool, at: Vector3, yaw: float) -> void:
	var turn := Basis(Vector3.UP, yaw)
	var frame := Color("dfe3e3")
	box(t, at + turn * Vector3(0, 0.22, 0.06), Vector3(0.5, 0.015, 0.46), Color("ffffff"), "canvas_stripes", turn * Basis(Vector3.RIGHT, 0.14), 0.6, 1)
	box(t, at + turn * Vector3(0, 0.5, -0.24), Vector3(0.5, 0.015, 0.6), Color("ffffff"), "canvas_stripes", turn * Basis(Vector3.RIGHT, 1.2), 0.6, 2)
	for x in [-0.27, 0.27]:
		bar(t, at + turn * Vector3(x, 0, 0.28), at + turn * Vector3(x, 0.3, 0.02), 0.025, frame, "metal_galv")
		bar(t, at + turn * Vector3(x, 0, -0.22), at + turn * Vector3(x, 0.78, -0.36), 0.025, frame, "metal_galv")
		bar(t, at + turn * Vector3(x, 0.35, -0.18), at + turn * Vector3(x, 0.35, 0.22), 0.03, frame, "metal_galv")


static func _beach_chairs(t: SurfaceTool) -> void:
	_beach_chair(t, Vector3(-0.42, 0, 0), 0.12)
	_beach_chair(t, Vector3(0.42, 0, 0.05), -0.1)
	# Isopor entre as duas e uma toalha jogada na frente.
	box(t, Vector3(0.02, 0.17, 0.52), Vector3(0.46, 0.32, 0.3), Color("f4f2ec"), "plastic_faded", Basis(Vector3.UP, 0.15), 0.5, 3)
	box(t, Vector3(0.02, 0.34, 0.52), Vector3(0.5, 0.04, 0.34), Color("2d6fb6"), "plastic_faded", Basis(Vector3.UP, 0.15), 0.5, 4)
	sheet(t, Vector3(-0.5, 0.006, 0.75), Vector2(0.55, 0.9), Color("ffffff"), "fabric_stripes", 1.2, Basis(), 5)


## Cadeira de plástico de bar (empilhável), frente para +Z; `arms` dá os braços da de boteco.
static func _plastic_chair(t: SurfaceTool, at: Vector3, basis: Basis, color: Color, arms := false, seed := 0) -> void:
	box(t, at + basis * Vector3(0, 0.44, 0), Vector3(0.44, 0.03, 0.42), color, "plastic_faded", basis, 0.5, seed)
	box(t, at + basis * Vector3(0, 0.66, -0.2), Vector3(0.44, 0.42, 0.03), color, "plastic_faded", basis * Basis(Vector3.RIGHT, -0.12), 0.5, seed + 1)
	for x in [-0.19, 0.19]:
		for z in [-0.18, 0.18]:
			bar(t, at + basis * Vector3(x * 1.12, 0, z * 1.12), at + basis * Vector3(x, 0.43, z), 0.035, color.darkened(0.08), "plastic_faded")
		if arms: box(t, at + basis * Vector3(x * 1.12, 0.62, -0.02), Vector3(0.04, 0.03, 0.4), color, "plastic_faded", basis, 0.5, seed + 2)


## Pilha de cadeiras de plástico na porta do bar e uma solta ao lado.
static func _plastic_chairs(t: SurfaceTool) -> void:
	for i in 5:
		_plastic_chair(t, Vector3(-0.25, i * 0.075, -0.02 * i), Basis(Vector3.UP, 0.03 * float(i % 2)), Color("f4f2ec"), false, i * 3)
	_plastic_chair(t, Vector3(0.45, 0, 0.18), Basis(Vector3.UP, -0.7), Color("f4f2ec"), false, 20)


## Jogo de boteco: mesa quadrada de plástico, quatro cadeiras com braço, garrafas, copos e o
## isopor. A cor da marca (amarelo, vermelho, branco, verde) vem da instância.
static func _bar_table(t: SurfaceTool) -> void:
	var plastic := Color("f4f2ec")
	box(t, Vector3(0, 0.72, 0), Vector3(0.72, 0.04, 0.72), plastic, "plastic_faded", Basis(), 0.8, 1)
	box(t, Vector3(0, 0.68, 0), Vector3(0.66, 0.06, 0.66), plastic.darkened(0.06), "plastic_faded", Basis(), 0.8, 2)
	for x in [-0.3, 0.3]:
		for z in [-0.3, 0.3]: bar(t, Vector3(x * 1.08, 0, z * 1.08), Vector3(x, 0.68, z), 0.045, plastic.darkened(0.08), "plastic_faded")
	for i in 4:
		var angle := PI * 0.5 * i + 0.12 * float(i % 2)
		var direction := Vector3(sin(angle), 0, cos(angle))
		# A cadeira olha para a mesa: frente (+Z local) para o centro.
		_plastic_chair(t, direction * 0.66, Basis(Vector3.UP, angle + PI), plastic, true, 10 + i * 3)
	for spot in [Vector3(-0.12, 0.74, 0.08), Vector3(0.15, 0.74, -0.1)]:
		cylinder(t, spot, 0.035, 0.24, Color("5a3212"), "plastic_faded", 6, 0.03)
		cylinder(t, spot + Vector3(0.12, 0, 0.1), 0.035, 0.09, Color("e8e4d6"), "plastic_faded", 6, 0.04)
	box(t, Vector3(0.82, 0.21, -0.62), Vector3(0.5, 0.42, 0.36), plastic, "plastic_faded", Basis(Vector3.UP, 0.3), 0.6, 30)
