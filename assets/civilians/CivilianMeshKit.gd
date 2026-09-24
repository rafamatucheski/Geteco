extends RefCounted
## Geometria dos pedestres civis, segmento por segmento do esqueleto.
##
## Cada segmento rígido (pelve, tronco, cabeça, braço, antebraço, coxa, canela,
## pé) é UMA malha lisa, com a roupa pintada por slot no vértice. A cor real de
## cada slot vem do `instance uniform` do shader, então a malha só depende do
## corte (biotipo, estilo de roupa, cabelo), não da cor: dezenas de pedestres
## reusam a mesma malha. O cache é estático e cresce só com cortes novos.
##
## Convenção: segmento pendurado em -Y a partir da própria articulação, frente
## em +Z (o `Actor` gira o visual em PI).

const SLOT_SKIN := 0
const SLOT_HAIR := 1
const SLOT_TOP := 2
const SLOT_INNER := 3
const SLOT_BOTTOM := 4
const SLOT_SHOE := 5
const SLOT_ACCENT := 6
const SLOT_SOLE := 7
const SLOT_EYE := 8
const SLOT_LIP := 9
const SLOT_BROW := 10
const SLOT_LENS := 11
const SLOT_METAL := 12

const SHADER := preload("res://assets/civilians/civilian_body.gdshader")
static var _meshes: Dictionary = {}
static var _material: ShaderMaterial
static var _double_sided: ShaderMaterial

static func material(double_sided := false) -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		# Saia e barra de vestido são cascas abertas: vistas de cima a 45° o
		# avesso aparece, então essa superfície usa um shader sem culling.
		var code := SHADER.code.replace("cull_back", "cull_disabled")
		var shader := Shader.new()
		shader.code = code
		_double_sided = ShaderMaterial.new()
		_double_sided.shader = shader
	return _double_sided if double_sided else _material

static func cached(key: String, build: Callable) -> ArrayMesh:
	if not _meshes.has(key): _meshes[key] = build.call()
	return _meshes[key]

static func cache_size() -> int:
	return _meshes.size()

## Acumulador de triângulos indexados com normal e slot por vértice.
class Builder:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var single_sided: Material
	var double_sided: Material

	func _vertex(point: Vector3, normal: Vector3, slot: int, shade: float) -> int:
		vertices.append(point)
		normals.append(normal)
		# Oclusão barata: a face voltada para baixo recebe menos luz do céu.
		var sky := clampf(normal.y * 0.5 + 0.5, 0.0, 1.0)
		colors.append(Color((slot + 0.5) / 16.0, shade * lerpf(0.74, 1.0, sky), 0.0, 1.0))
		return vertices.size() - 1

	## Elipsoide com normais analíticas. `basis` gira/inclina a peça.
	func ellipsoid(center: Vector3, radii: Vector3, slot: int, basis := Basis.IDENTITY, lon := 10, lat := 6, shade := 1.0) -> void:
		var first := vertices.size()
		for i in lat + 1:
			var v := PI * float(i) / lat
			var y := cos(v)
			var ring := sin(v)
			for j in lon + 1:
				var u := TAU * float(j) / lon
				var unit := Vector3(ring * sin(u), y, ring * cos(u))
				var local := unit * radii
				var normal := Vector3(unit.x / maxf(radii.x, 0.0001), unit.y / maxf(radii.y, 0.0001), unit.z / maxf(radii.z, 0.0001))
				_vertex(center + basis * local, (basis * normal).normalized(), slot, shade)
		for i in lat:
			for j in lon:
				var a := first + i * (lon + 1) + j
				var b := a + lon + 1
				# Godot: face da frente em sentido horário visto de fora.
				indices.append_array([a, a + 1, b, a + 1, b + 1, b])

	## Tubo ao longo de Y local. Cada anel: [y, rx, rz, slot, cz, square].
	## O slot do anel vale para a faixa até o anel seguinte. As faixas duplicam os
	## vértices da borda para a troca de cor ser nítida, mas as normais são as do
	## tubo inteiro, então o sombreamento continua liso atravessando a costura.
	func loft(rings: Array, slot_default: int, xform := Transform3D.IDENTITY, segments := 12, cap_top := true, cap_bottom := true, shade := 1.0) -> void:
		var count := rings.size()
		var points: Array[PackedVector3Array] = []
		for r in rings:
			var square: float = r[5] if r.size() > 5 else 2.0
			var cz: float = r[4] if r.size() > 4 else 0.0
			var ring := PackedVector3Array()
			for k in segments:
				var angle := TAU * float(k) / segments
				var s := sin(angle)
				var c := cos(angle)
				var px := signf(s) * pow(absf(s), 2.0 / square) * float(r[1])
				var pz := signf(c) * pow(absf(c), 2.0 / square) * float(r[2]) + cz
				ring.append(Vector3(px, float(r[0]), pz))
			points.append(ring)
		var ring_normals: Array[PackedVector3Array] = []
		for i in count:
			var list := PackedVector3Array()
			for k in segments:
				var around := points[i][(k + 1) % segments] - points[i][(k - 1 + segments) % segments]
				var along := points[mini(i + 1, count - 1)][k] - points[maxi(i - 1, 0)][k]
				var normal := along.cross(around).normalized()
				var outward := points[i][k] - Vector3(0, points[i][k].y, float(rings[i][4]) if rings[i].size() > 4 else 0.0)
				if normal.dot(outward) < 0: normal = -normal
				list.append(normal)
			ring_normals.append(list)
		var normal_basis := xform.basis.inverse().transposed()
		for i in count - 1:
			var slot: int = rings[i][3] if rings[i][3] >= 0 else slot_default
			var first := vertices.size()
			for row in [i, i + 1]:
				for k in segments + 1:
					var index: int = k % segments
					_vertex(xform * points[row][index], (normal_basis * ring_normals[row][index]).normalized(), slot, shade)
			for k in segments:
				var a := first + k
				var b := first + segments + 1 + k
				# Anéis descem em Y: (a, a+1, b) sai para fora com esse sentido.
				indices.append_array([a, b, a + 1, a + 1, b, b + 1] if float(rings[i + 1][0]) > float(rings[i][0]) else [a, a + 1, b, a + 1, b + 1, b])
		for cap in [[cap_top, 0], [cap_bottom, count - 1]]:
			if not cap[0]: continue
			var row: int = cap[1]
			var slot: int = rings[mini(row, count - 2)][3] if rings[mini(row, count - 2)][3] >= 0 else slot_default
			var upward := (float(rings[0][0]) > float(rings[count - 1][0])) == (row == 0)
			var axis := Vector3.UP if upward else Vector3.DOWN
			var center := Vector3(0, float(rings[row][0]), float(rings[row][4]) if rings[row].size() > 4 else 0.0)
			var n := (normal_basis * axis).normalized()
			var middle := _vertex(xform * center, n, slot, shade)
			var first := vertices.size()
			for k in segments: _vertex(xform * points[row][k], n, slot, shade)
			for k in segments:
				var a := first + k
				var b := first + (k + 1) % segments
				indices.append_array([middle, b, a] if upward else [middle, a, b])

	func commit(mesh: ArrayMesh = null, open_shell := false) -> ArrayMesh:
		if mesh == null: mesh = ArrayMesh.new()
		if vertices.is_empty(): return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, double_sided if open_shell else single_sided)
		return mesh

static func _builder() -> Builder:
	var b := Builder.new()
	b.single_sided = material(false)
	b.double_sided = material(true)
	return b

# --- Proporções ---------------------------------------------------------------
# Dimensões em metros, adulto de ~1,76 m. A cabeça é ~8% maior que a anatômica:
# na câmera ortográfica de 45° o pedestre tem 80–100 px e a cabeça é o que
# identifica a pessoa (cabelo, chapéu).
const THIGH := 0.42
const SHIN := 0.40
const UPPER_ARM := 0.29
const FOREARM := 0.25
const ANKLE_HEIGHT := 0.085

static func build_profile(female: bool, build: int) -> Dictionary:
	# build: 0 magro, 1 médio, 2 corpulento.
	var w := [0.93, 1.0, 1.1][build] as float
	if female:
		return {"waist": Vector2(.118, .092) * w, "hip": Vector2(.168, .118) * w, "chest": Vector2(.150, .105) * w,
			"shoulder": .162 * lerpf(1.0, w, .5), "belly": .0 if build < 2 else .03, "bust": true, "limb": .93 * lerpf(1.0, w, .6)}
	return {"waist": Vector2(.140, .100) * w, "hip": Vector2(.150, .108) * w, "chest": Vector2(.168, .114) * w,
		"shoulder": .186 * lerpf(1.0, w, .5), "belly": .0 if build < 2 else .045, "bust": false, "limb": 1.0 * lerpf(1.0, w, .6)}

# --- Segmentos -----------------------------------------------------------------

## Tronco: da cintura (sobrepõe a pelve) à base do pescoço. Pivô na cintura.
static func chest_mesh(p: Dictionary, top: int, backpack: bool, strap: int) -> ArrayMesh:
	var key := "chest|%s|%d|%s|%d" % [str(p), top, backpack, strap]
	return cached(key, func() -> ArrayMesh:
		var b := _builder()
		var waist: Vector2 = p.waist
		var ch: Vector2 = p.chest
		var sh: float = p.shoulder
		var bulk := 0.014 if top in [2, 3, 9] else (0.03 if top == 7 else 0.0)
		var hem: float = {2: -0.26, 3: -0.20, 7: -0.22, 9: -0.22}.get(top, -0.16)
		var body_slot := SLOT_TOP
		var rings := [
			[hem, waist.x + .018 + bulk, waist.y + .016 + bulk + p.belly * .6, body_slot, p.belly * .4, 2.6],
			[-0.02, waist.x + bulk, waist.y + bulk + p.belly, body_slot, p.belly * .5, 2.6],
			[0.12, ch.x + bulk, ch.y + bulk + p.belly * .4, body_slot, p.belly * .2, 2.7],
			[0.25, sh - .012 + bulk, ch.y + bulk - .004, body_slot, 0.0, 2.9],
			[0.33, sh - .02 + bulk, ch.y - .012 + bulk, body_slot, -.004, 2.6],
			[0.385, .105, .080, body_slot, -.01, 2.2],
			[0.415, .062, .058, body_slot, 0.0, 2.0],
		]
		b.loft(rings, SLOT_TOP, Transform3D.IDENTITY, 14)
		# Ombros (deltoides) e peito.
		for side in [-1.0, 1.0]:
			b.ellipsoid(Vector3(side * (sh - .024), .305, -.006), Vector3(.056 + bulk * .5, .05 + bulk * .5, .06 + bulk * .5), SLOT_TOP, Basis.IDENTITY, 10, 6)
			if p.bust:
				b.ellipsoid(Vector3(side * .058, .175, ch.y - .018), Vector3(.064, .058, .052), SLOT_TOP, Basis(Vector3.RIGHT, .35), 8, 5)
		if p.belly > 0.0:
			b.ellipsoid(Vector3(0, .02, waist.y + .01), Vector3(waist.x * .85, .13, .07), SLOT_TOP, Basis.IDENTITY, 10, 5)
		var front: float = ch.y + bulk
		match top:
			6, 8: # farda: gola, bolsos no peito, distintivo, platinas.
				b.loft([[.43, .07, .064, SLOT_TOP, -.01], [.385, .1, .086, SLOT_TOP, -.01]], SLOT_TOP, Transform3D.IDENTITY, 12, false, false, .9)
				for side in [-1.0, 1.0]:
					b.ellipsoid(Vector3(side * .07, .2, front - .003), Vector3(.045, .04, .014), SLOT_TOP, Basis.IDENTITY, 6, 4, .78)
					b.ellipsoid(Vector3(side * (sh - .05), .345, -.004), Vector3(.05, .012, .035), SLOT_TOP, Basis.IDENTITY, 6, 3, .8)
				b.ellipsoid(Vector3(-.07, .25, front + .004), Vector3(.022, .026, .008), SLOT_METAL, Basis.IDENTITY, 6, 4)
				if top == 8:
					# Colete balístico com bolsas de carregador.
					b.loft([[.3, sh - .03, ch.y + .05, SLOT_ACCENT, 0.0, 3.2], [.0, waist.x + .05, waist.y + .06, SLOT_ACCENT, 0.0, 3.2], [-.07, waist.x + .05, waist.y + .06, SLOT_ACCENT, 0.0, 3.2]], SLOT_ACCENT, Transform3D.IDENTITY, 14, true, true, .9)
					for x in [-.08, 0.0, .08]:
						b.ellipsoid(Vector3(x, .02, front + .07), Vector3(.034, .05, .025), SLOT_ACCENT, Basis.IDENTITY, 6, 4, .75)
			7: # casaco de bombeiro: gola alta e faixas refletivas.
				b.loft([[.45, .085, .08, SLOT_TOP], [.38, .12, .1, SLOT_TOP]], SLOT_TOP, Transform3D.IDENTITY, 12, false, false, .9)
				for y in [.08, -.3]:
					b.loft([[y + .025, waist.x + bulk + .02, waist.y + bulk + .02, SLOT_INNER, 0.0, 2.6], [y - .025, waist.x + bulk + .022, waist.y + bulk + .022, SLOT_INNER, 0.0, 2.6]], SLOT_INNER, Transform3D.IDENTITY, 14, false, false)
			9: # sobretudo: lapelas e camisa clara.
				b.ellipsoid(Vector3(0, .12, front - .004), Vector3(.045, .24, .02), SLOT_INNER, Basis.IDENTITY, 8, 6)
				for side in [-1.0, 1.0]:
					b.ellipsoid(Vector3(side * .06, .26, front), Vector3(.04, .13, .016), SLOT_TOP, Basis(Vector3.FORWARD, side * .38), 6, 4, .8)
			0: # camiseta: decote em U com pele.
				b.ellipsoid(Vector3(0, .372, .052), Vector3(.055, .032, .03), SLOT_SKIN, Basis(Vector3.RIGHT, -.5), 8, 4)
			1: # manga longa / suéter: gola canelada.
				b.loft([[.43, .066, .062, SLOT_TOP], [.395, .074, .068, SLOT_TOP]], SLOT_TOP, Transform3D.IDENTITY, 12, false, false, .86)
			2: # jaqueta aberta: camisa aparecendo e lapelas.
				b.ellipsoid(Vector3(0, .09, front - .006), Vector3(.052, .27, .022), SLOT_INNER, Basis.IDENTITY, 8, 6)
				for side in [-1.0, 1.0]:
					b.ellipsoid(Vector3(side * .06, .27, front - .002), Vector3(.035, .11, .016), SLOT_TOP, Basis(Vector3.FORWARD, side * .38), 6, 4, .82)
					b.ellipsoid(Vector3(side * .085, -.06, front - .004), Vector3(.045, .03, .014), SLOT_TOP, Basis.IDENTITY, 6, 3, .7)
				b.loft([[.44, .07, .066, SLOT_TOP, -.012], [.38, .10, .085, SLOT_TOP, -.012]], SLOT_TOP, Transform3D.IDENTITY, 12, false, false, .9)
			3: # moletom: capuz nas costas, bolso canguru e cordões.
				b.ellipsoid(Vector3(0, .36, -.075), Vector3(.12, .075, .075), SLOT_TOP, Basis(Vector3.RIGHT, .4), 10, 5, .88)
				b.ellipsoid(Vector3(0, -.075, front - .004), Vector3(.11, .055, .018), SLOT_TOP, Basis.IDENTITY, 8, 4, .8)
				for side in [-1.0, 1.0]:
					b.ellipsoid(Vector3(side * .025, .30, front + .004), Vector3(.006, .06, .006), SLOT_INNER, Basis.IDENTITY, 4, 3)
			4: # vestido: decote e alças no tom da peça.
				b.ellipsoid(Vector3(0, .37, .05), Vector3(.075, .04, .032), SLOT_SKIN, Basis(Vector3.RIGHT, -.55), 8, 4)
			5: # camisa polo por dentro da calça: gola e botões.
				b.loft([[.43, .072, .066, SLOT_TOP, -.01], [.385, .098, .084, SLOT_TOP, -.01]], SLOT_TOP, Transform3D.IDENTITY, 12, false, false, .92)
				for i in 3: b.ellipsoid(Vector3(0, .34 - i * .045, front + .003), Vector3(.009, .009, .005), SLOT_INNER, Basis.IDENTITY, 5, 3)
		if backpack:
			b.ellipsoid(Vector3(0, .17, -ch.y - .075), Vector3(.13, .17, .075), SLOT_ACCENT, Basis.IDENTITY, 10, 6)
			b.ellipsoid(Vector3(0, .25, -ch.y - .145), Vector3(.09, .06, .02), SLOT_ACCENT, Basis.IDENTITY, 8, 4, .75)
			for side in [-1.0, 1.0]:
				b.ellipsoid(Vector3(side * .085, .23, front - .004), Vector3(.022, .16, .012), SLOT_ACCENT, Basis(Vector3.FORWARD, side * -.08), 6, 5, .8)
				b.ellipsoid(Vector3(side * .09, .36, -.01), Vector3(.03, .02, .1), SLOT_ACCENT, Basis.IDENTITY, 6, 4, .8)
		if strap != 0:
			# Alça transversal da bolsa, do ombro oposto até o quadril do lado da bolsa.
			for z in [front + .002, -ch.y - .002]:
				b.ellipsoid(Vector3(0, .14, z), Vector3(.018, .30, .01), SLOT_ACCENT, Basis(Vector3.FORWARD, strap * .62), 6, 6, .78)
		return b.commit())

## Pelve: quadris, cinto e barra da blusa. Pivô na altura da pelve (0,94 m).
static func pelvis_mesh(p: Dictionary, top: int, bottom: int, bag: int) -> ArrayMesh:
	var key := "pelvis|%s|%d|%d|%d" % [str(p), top, bottom, bag]
	return cached(key, func() -> ArrayMesh:
		var b := _builder()
		var hip: Vector2 = p.hip
		var waist: Vector2 = p.waist
		var tucked := top in [5, 6, 8]
		var hem_slot := SLOT_BOTTOM if tucked else SLOT_TOP
		var skirt := bottom == 2 or top in [4, 7, 9]
		var lower_slot := SLOT_TOP if top == 4 else SLOT_BOTTOM
		var rings := [
			[.15, waist.x + .004, waist.y + .004 + p.belly * .5, hem_slot, p.belly * .3, 2.5],
			[.08, waist.x + .02, waist.y + .012 + p.belly * .3, SLOT_SHOE if tucked else hem_slot, p.belly * .15, 2.5],
			[.05, hip.x - .01, hip.y - .006, lower_slot if top != 2 else SLOT_TOP, 0.0, 2.6],
			[-.02, hip.x, hip.y, lower_slot, -.005, 2.6],
			[-.09, hip.x - .012, hip.y - .01, lower_slot, -.01, 2.4],
			[-.13, hip.x * .55, hip.y * .6, lower_slot, 0.0, 2.0],
		]
		b.loft(rings, SLOT_BOTTOM, Transform3D.IDENTITY, 14)
		# Glúteos dão volume de costas, visível na câmera alta.
		for side in [-1.0, 1.0]:
			b.ellipsoid(Vector3(side * .06, -.05, -hip.y + .045), Vector3(.068, .075, .05), lower_slot, Basis.IDENTITY, 8, 5)
		if tucked:
			b.ellipsoid(Vector3(0, .07, waist.y + .018), Vector3(.03, .02, .012), SLOT_METAL, Basis.IDENTITY, 6, 3)
		if bag != 0:
			b.ellipsoid(Vector3(bag * (hip.x + .045), -.02, .03), Vector3(.045, .105, .13), SLOT_ACCENT, Basis.IDENTITY, 8, 5)
			b.ellipsoid(Vector3(bag * (hip.x + .05), .06, .03), Vector3(.047, .03, .132), SLOT_ACCENT, Basis.IDENTITY, 8, 4, .75)
		var mesh := b.commit()
		if skirt:
			# Saia rodada até o joelho, casca aberta com avesso.
			var s := _builder()
			var length := -.40 if top == 4 else (-.3 if top == 7 else (-.38 if top == 9 else -.33))
			var skirt_slot := SLOT_TOP if top in [7, 9] else lower_slot
			s.loft([
				[.06, hip.x + .004, hip.y + .004, skirt_slot, 0.0, 2.3],
				[-.08, hip.x + .03, hip.y + .03, skirt_slot, 0.0, 2.2],
				[length, hip.x + .085, hip.y + .08, SLOT_INNER if top == 7 else skirt_slot, 0.0, 2.1],
				[length - .04, hip.x + .088, hip.y + .083, skirt_slot, 0.0, 2.1],
			], skirt_slot, Transform3D.IDENTITY, 16, false, false)
			s.commit(mesh, true)
		return mesh)

## Coxa: do quadril ao joelho.
static func thigh_mesh(p: Dictionary, bottom: int, top: int) -> ArrayMesh:
	var key := "thigh|%.3f|%d|%d" % [p.limb, bottom, top]
	return cached(key, func() -> ArrayMesh:
		var b := _builder()
		var k: float = p.limb
		var bare := (bottom == 2 or top == 4) and top not in [7, 9]
		var main := SLOT_SKIN if bare else SLOT_BOTTOM
		var shorts := bottom == 1
		var rings := [
			[.05, .082 * k, .088 * k, main],
			[-.04, .088 * k, .092 * k, main],
			[-.20, .078 * k, .082 * k, main if not shorts else SLOT_BOTTOM],
			[-.235, .077 * k, .081 * k, SLOT_SKIN if shorts else main],
			[-.36, .062 * k, .066 * k, SLOT_SKIN if shorts else main],
			[-.44, .056 * k, .06 * k, SLOT_SKIN if shorts else main],
		]
		if shorts:
			# Barra do short levemente afastada da perna.
			rings[2] = [-.215, .086 * k, .09 * k, SLOT_BOTTOM]
			rings[3] = [-.222, .072 * k, .076 * k, SLOT_SKIN]
		b.loft(rings, main, Transform3D.IDENTITY, 12)
		b.ellipsoid(Vector3(0, -THIGH, .006), Vector3(.058, .062, .064) * k, SLOT_SKIN if shorts or bare else main, Basis.IDENTITY, 8, 5)
		return b.commit())

## Canela: do joelho ao tornozelo, com meia/cano de bota.
static func shin_mesh(p: Dictionary, bottom: int, top: int, shoe: int) -> ArrayMesh:
	var key := "shin|%.3f|%d|%d|%d" % [p.limb, bottom, top, shoe]
	return cached(key, func() -> ArrayMesh:
		var b := _builder()
		var k: float = p.limb
		var bare := (bottom in [1, 2] or top == 4) and top not in [7, 9]
		var main := SLOT_SKIN if bare else SLOT_BOTTOM
		var ankle_slot := main
		if shoe == 1: ankle_slot = SLOT_SHOE
		elif bare and shoe == 0: ankle_slot = SLOT_SOLE
		var rings := [
			[.02, .056 * k, .06 * k, main],
			[-.09, .058 * k, .066 * k, main, -.008],
			[-.22, .047 * k, .05 * k, main if shoe != 1 else SLOT_SHOE, -.004],
			[-.31, .04 * k, .042 * k, ankle_slot],
			[-.40, .037 * k, .04 * k, ankle_slot],
		]
		if shoe == 1: rings[2][0] = -.25
		elif not bare:
			# Barra da calça cai sobre o sapato.
			rings[3] = [-.33, .046 * k, .05 * k, main]
			rings[4] = [-.40, .05 * k, .056 * k, main]
		if bottom == 3:
			rings[2] = [-.2, .062 * k, .066 * k, SLOT_INNER, -.004]
			rings.insert(3, [-.245, .058 * k, .062 * k, main])
		b.loft(rings, main, Transform3D.IDENTITY, 12)
		return b.commit())

## Pé: tênis (sola clara), bota ou sapato social. Pivô no tornozelo.
static func foot_mesh(shoe: int) -> ArrayMesh:
	return cached("foot|%d" % shoe, func() -> ArrayMesh:
		var b := _builder()
		var h := ANKLE_HEIGHT
		var sole_slot := SLOT_SOLE if shoe == 0 else SLOT_SHOE
		var bulk := 1.08 if shoe == 1 else (1.0 if shoe == 0 else .94)
		b.ellipsoid(Vector3(0, -.035, .05), Vector3(.05, .045, .125) * bulk, SLOT_SHOE, Basis(Vector3.RIGHT, .1), 10, 6)
		b.ellipsoid(Vector3(0, -.05, .12), Vector3(.047, .032, .06) * bulk, SLOT_SHOE, Basis.IDENTITY, 8, 5)
		b.ellipsoid(Vector3(0, -.005, -.005), Vector3(.045, .05, .055) * bulk, SLOT_SHOE, Basis.IDENTITY, 8, 5)
		b.ellipsoid(Vector3(0, -h + .012, .05), Vector3(.056, .016 if shoe == 0 else .011, .14) * bulk, sole_slot, Basis.IDENTITY, 10, 4, 1.0 if shoe == 0 else .5)
		if shoe == 0:
			# Cadarço/lingueta em tom claro.
			b.ellipsoid(Vector3(0, -.008, .075), Vector3(.022, .012, .045), SLOT_SOLE, Basis(Vector3.RIGHT, .45), 6, 3, .95)
		return b.commit())

## Braço: do ombro ao cotovelo.
static func upper_arm_mesh(p: Dictionary, top: int) -> ArrayMesh:
	var key := "uarm|%.3f|%d" % [p.limb, top]
	return cached(key, func() -> ArrayMesh:
		var b := _builder()
		var k: float = p.limb * (1.0 if not p.bust else .92)
		var bulk := .012 if top in [2, 3, 9] else (.024 if top == 7 else 0.0)
		var short := top in [0, 4, 5]
		var sleeve := SLOT_TOP
		var rings: Array
		if top == 4:
			rings = [[.03, .052 * k, .054 * k, SLOT_SKIN], [-.05, .05 * k, .052 * k, SLOT_SKIN], [-.2, .043 * k, .046 * k, SLOT_SKIN], [-.3, .038 * k, .041 * k, SLOT_SKIN]]
		elif short:
			rings = [[.03, .06 * k, .062 * k, sleeve], [-.06, .058 * k, .06 * k, sleeve], [-.13, .058 * k, .06 * k, sleeve], [-.135, .047 * k, .05 * k, SLOT_SKIN], [-.21, .044 * k, .047 * k, SLOT_SKIN], [-.3, .038 * k, .041 * k, SLOT_SKIN]]
		else:
			rings = [[.03, .058 * k + bulk, .06 * k + bulk, sleeve], [-.06, .056 * k + bulk, .058 * k + bulk, sleeve], [-.2, .049 * k + bulk, .052 * k + bulk, sleeve], [-.3, .045 * k + bulk, .048 * k + bulk, sleeve]]
		b.loft(rings, sleeve, Transform3D.IDENTITY, 12)
		b.ellipsoid(Vector3(0, -UPPER_ARM, 0), Vector3(.042, .045, .044) * k + Vector3.ONE * (0.0 if short or top == 4 else bulk), SLOT_SKIN if short or top == 4 else sleeve, Basis.IDENTITY, 8, 5)
		return b.commit())

## Antebraço + mão (pulso rígido). Palma voltada para o corpo.
static func forearm_mesh(p: Dictionary, top: int, side: float) -> ArrayMesh:
	var key := "farm|%.3f|%d|%d" % [p.limb, top, int(side)]
	return cached(key, func() -> ArrayMesh:
		var b := _builder()
		var k: float = p.limb * (1.0 if not p.bust else .9)
		var bulk := .012 if top in [2, 3, 9] else (.024 if top == 7 else 0.0)
		var bare := top in [0, 4, 5]
		var slot := SLOT_SKIN if bare else SLOT_TOP
		var rings := [
			[.01, .043 * k + bulk, .045 * k + bulk, slot],
			[-.08, .044 * k + bulk, .046 * k + bulk, slot],
			[-.2, .034 * k + bulk, .032 * k + bulk, slot],
			[-.215, .037 * k + bulk, .035 * k + bulk, slot if bare else SLOT_TOP],
			[-.235, .029 * k, .026 * k, SLOT_SKIN],
			[-.25, .028 * k, .025 * k, SLOT_SKIN],
		]
		b.loft(rings, slot, Transform3D.IDENTITY, 10)
		# Mão levemente fechada: palma, dedos curvados e polegar à frente.
		b.ellipsoid(Vector3(side * -.004, -.305, .006), Vector3(.024, .058, .044) * k, SLOT_SKIN, Basis(Vector3.RIGHT, -.12), 8, 5)
		b.ellipsoid(Vector3(side * -.012, -.35, .012), Vector3(.022, .032, .038) * k, SLOT_SKIN, Basis(Vector3.RIGHT, -.5), 6, 4, .95)
		b.ellipsoid(Vector3(side * -.018, -.29, .042), Vector3(.014, .036, .014) * k, SLOT_SKIN, Basis(Vector3.FORWARD, side * .3), 6, 4)
		return b.commit())

## Cabeça + pescoço + rosto + cabelo/chapéu. Pivô na base do pescoço.
## hair: 0 curto, 1 raspado, 2 topete, 3 comprido, 4 rabo de cavalo, 5 coque, 6 black power, 7 careca.
## hat: 0 nenhum, 1 boné, 2 gorro, 3 capacete de moto.
static func head_mesh(female: bool, hair: int, beard: int, hat: int, glasses: bool) -> ArrayMesh:
	var key := "head|%s|%d|%d|%d|%s" % [female, hair, beard, hat, glasses]
	return cached(key, func() -> ArrayMesh:
		var b := _builder()
		var nw := .052 if female else .058
		b.loft([[-.02, nw + .004, nw + .006, SLOT_SKIN], [.06, nw, nw + .002, SLOT_SKIN], [.12, nw - .004, nw - .002, SLOT_SKIN]], SLOT_SKIN, Transform3D.IDENTITY, 10, false, false)
		var c := Vector3(0, .165, .012)
		var r := Vector3(.096, .12, .11) if female else Vector3(.1, .122, .112)
		b.ellipsoid(c, r, SLOT_SKIN, Basis.IDENTITY, 14, 9)
		# Mandíbula/queixo: mais estreita e marcada nos homens.
		b.ellipsoid(Vector3(0, .1, .05), Vector3(.074, .058, .072) if female else Vector3(.082, .066, .078), SLOT_SKIN, Basis.IDENTITY, 10, 6)
		for side in [-1.0, 1.0]:
			b.ellipsoid(Vector3(side * .097, .16, .0), Vector3(.018, .034, .026), SLOT_SKIN, Basis.IDENTITY, 6, 4, .92)
			b.ellipsoid(Vector3(side * .037, .172, .107), Vector3(.018, .012, .008), SLOT_EYE, Basis.IDENTITY, 6, 4)
			b.ellipsoid(Vector3(side * .04, .198, .108), Vector3(.03, .008, .012), SLOT_BROW, Basis(Vector3.FORWARD, side * -.12), 6, 3)
			if glasses:
				b.ellipsoid(Vector3(side * .038, .172, .118), Vector3(.025, .018, .006), SLOT_LENS, Basis.IDENTITY, 8, 4)
				b.ellipsoid(Vector3(side * .085, .176, .06), Vector3(.004, .005, .055), SLOT_LENS, Basis.IDENTITY, 4, 3)
		if glasses: b.ellipsoid(Vector3(0, .176, .12), Vector3(.014, .004, .004), SLOT_LENS, Basis.IDENTITY, 4, 3)
		b.ellipsoid(Vector3(0, .145, .122), Vector3(.017, .03, .022), SLOT_SKIN, Basis(Vector3.RIGHT, -.25), 6, 4)
		b.ellipsoid(Vector3(0, .105, .115), Vector3(.03, .008, .009), SLOT_LIP, Basis.IDENTITY, 6, 3)
		match beard:
			1: b.ellipsoid(Vector3(0, .12, .116), Vector3(.034, .01, .012), SLOT_HAIR, Basis.IDENTITY, 6, 3)
			2: b.ellipsoid(Vector3(0, .092, .062), Vector3(.087, .07, .072), SLOT_HAIR, Basis.IDENTITY, 10, 6)
			3:
				b.ellipsoid(Vector3(0, .082, .085), Vector3(.045, .04, .045), SLOT_HAIR, Basis.IDENTITY, 8, 5)
				b.ellipsoid(Vector3(0, .12, .116), Vector3(.034, .01, .012), SLOT_HAIR, Basis.IDENTITY, 6, 3)
		var covered := hat != 0
		if hat == 3:
			b.ellipsoid(Vector3(0, .17, 0), Vector3(.152, .162, .152), SLOT_ACCENT, Basis.IDENTITY, 14, 8)
			b.ellipsoid(Vector3(0, .165, .1), Vector3(.12, .055, .07), SLOT_LENS, Basis.IDENTITY, 10, 5)
			b.ellipsoid(Vector3(0, .07, .085), Vector3(.1, .045, .06), SLOT_ACCENT, Basis.IDENTITY, 10, 5, .9)
			return b.commit()
		# Calota do cabelo: recuada na frente para deixar a testa, maior atrás e em cima.
		var crown := Vector3(0, .205, -.014)
		var crown_r := Vector3(.105, .105, .12)
		match hair:
			0: b.ellipsoid(crown, crown_r, SLOT_HAIR, Basis.IDENTITY, 12, 7)
			1: b.ellipsoid(crown + Vector3(0, -.006, .002), crown_r * Vector3(.975, .95, .965), SLOT_HAIR, Basis.IDENTITY, 12, 7, .9)
			2:
				b.ellipsoid(crown, crown_r, SLOT_HAIR, Basis.IDENTITY, 12, 7)
				if not covered: b.ellipsoid(Vector3(.02, .275, .055), Vector3(.075, .04, .06), SLOT_HAIR, Basis(Vector3.RIGHT, -.3), 8, 5)
			3:
				b.ellipsoid(crown + Vector3(0, .005, 0), crown_r * Vector3(1.04, 1.0, 1.02), SLOT_HAIR, Basis.IDENTITY, 12, 7)
				b.ellipsoid(Vector3(0, .1, -.07), Vector3(.108, .17, .065), SLOT_HAIR, Basis(Vector3.RIGHT, .08), 10, 6)
				for side in [-1.0, 1.0]:
					b.ellipsoid(Vector3(side * .088, .12, .0), Vector3(.03, .12, .075), SLOT_HAIR, Basis.IDENTITY, 8, 5)
			4:
				b.ellipsoid(crown, crown_r * Vector3(1.0, .98, 1.0), SLOT_HAIR, Basis.IDENTITY, 12, 7)
				b.ellipsoid(Vector3(0, .18, -.13), Vector3(.03, .03, .03), SLOT_ACCENT, Basis.IDENTITY, 6, 4)
				b.ellipsoid(Vector3(0, .11, -.155), Vector3(.036, .09, .036), SLOT_HAIR, Basis(Vector3.RIGHT, .25), 8, 5)
			5:
				b.ellipsoid(crown, crown_r * Vector3(1.0, .98, 1.0), SLOT_HAIR, Basis.IDENTITY, 12, 7)
				if not covered: b.ellipsoid(Vector3(0, .285, -.075), Vector3(.052, .046, .052), SLOT_HAIR, Basis.IDENTITY, 8, 5)
			6: b.ellipsoid(Vector3(0, .215, -.012), Vector3(.13, .12, .138), SLOT_HAIR, Basis.IDENTITY, 12, 7)
			7: b.ellipsoid(Vector3(0, .155, -.03), Vector3(.102, .06, .1), SLOT_HAIR, Basis(Vector3.RIGHT, -.35), 10, 5, .85)
		match hat:
			1: # boné
				b.ellipsoid(Vector3(0, .238, -.006), Vector3(.109, .075, .12), SLOT_ACCENT, Basis.IDENTITY, 12, 6)
				b.ellipsoid(Vector3(0, .222, .115), Vector3(.085, .011, .085), SLOT_ACCENT, Basis(Vector3.RIGHT, .12), 10, 3, .85)
			2: # gorro com dobra
				b.ellipsoid(Vector3(0, .232, -.012), Vector3(.112, .1, .124), SLOT_ACCENT, Basis.IDENTITY, 12, 7)
				b.loft([[.21, .113, .124, SLOT_ACCENT, -.012], [.17, .113, .125, SLOT_ACCENT, -.012]], SLOT_ACCENT, Transform3D.IDENTITY, 14, false, false, .82)
			4: # quepe de polícia: copa larga, faixa, pala e emblema.
				b.loft([[.29, .118, .13, SLOT_ACCENT, 0.0, 2.2], [.25, .112, .122, SLOT_ACCENT, 0.0, 2.2], [.215, .108, .118, SLOT_ACCENT]], SLOT_ACCENT, Transform3D.IDENTITY, 14, true, false)
				b.loft([[.225, .11, .12, SLOT_EYE, -.004], [.2, .108, .118, SLOT_EYE, -.004]], SLOT_EYE, Transform3D.IDENTITY, 14, false, false)
				b.ellipsoid(Vector3(0, .205, .115), Vector3(.08, .01, .06), SLOT_EYE, Basis(Vector3.RIGHT, .25), 10, 3)
				b.ellipsoid(Vector3(0, .255, .128), Vector3(.02, .022, .006), SLOT_METAL, Basis.IDENTITY, 6, 4)
			5: # capacete de bombeiro: domo com crista e aba larga caída atrás.
				b.ellipsoid(Vector3(0, .24, -.01), Vector3(.12, .11, .135), SLOT_ACCENT, Basis.IDENTITY, 12, 7)
				b.ellipsoid(Vector3(0, .31, -.01), Vector3(.02, .03, .12), SLOT_ACCENT, Basis.IDENTITY, 6, 4, .85)
				b.ellipsoid(Vector3(0, .19, -.04), Vector3(.17, .014, .2), SLOT_ACCENT, Basis(Vector3.RIGHT, -.18), 12, 3, .9)
				b.ellipsoid(Vector3(0, .25, .13), Vector3(.045, .04, .01), SLOT_METAL, Basis.IDENTITY, 6, 4)
			7: # fedora: copa com vinco, fita no tom `inner` e aba larga.
				b.loft([[.335, .082, .09, SLOT_ACCENT, -.01, 2.4], [.3, .1, .112, SLOT_ACCENT, -.01, 2.4], [.24, .112, .124, SLOT_INNER, -.01, 2.3], [.21, .113, .125, SLOT_ACCENT, -.01]], SLOT_ACCENT, Transform3D.IDENTITY, 14, true, false)
				b.ellipsoid(Vector3(0, .335, -.01), Vector3(.03, .012, .07), SLOT_ACCENT, Basis.IDENTITY, 6, 3, .7)
				b.ellipsoid(Vector3(0, .212, -.008), Vector3(.2, .012, .21), SLOT_ACCENT, Basis(Vector3.RIGHT, -.06), 14, 3, .9)
			6: # capacete tático com óculos de proteção.
				b.ellipsoid(Vector3(0, .225, -.01), Vector3(.125, .11, .135), SLOT_ACCENT, Basis.IDENTITY, 12, 7)
				b.ellipsoid(Vector3(0, .175, .1), Vector3(.085, .03, .03), SLOT_LENS, Basis.IDENTITY, 8, 4)
		return b.commit())
