extends RefCounted
## Acabamento dos veículos pesados (caminhões e empilhadeira). Os .scn da frota
## são fotografias achatadas dos modelos V1 e liam como caixas coloridas —
## "POBRES demais" (usuário, 28/09/2026). Em vez de regravar os .scn (que têm
## trabalho não commitado de outra sessão, e o passo de fixups não é idempotente
## entre versões), a peça extra é montada aqui, uma malha por modelo, em cache,
## e pendurada no modelo quando `FleetCatalog.create` o instancia.
##
## Só visual: nenhuma colisão, nada preso ao carro de elevação da empilhadeira
## (ele se move) nem às rodas (elas giram). Frente dos modelos em −Z.
const KIT := preload("res://world/city_look/CityPropKit.gd")

const IDS := ["port_forklift", "cargo_flatbed_truck", "american_dump_truck", "american_tanker_truck", "boxrunner", "towmaster"]

const CHROME := Color("c9ced2")
const DARK := Color("1d2226")
const RUBBER := Color("141618")
const STEEL := Color("59636a")
const PLATE := Color("8e959b")
const RED := Color("b3261e")
const WHITE := Color("ece9e1")
const AMBER := Color("f0a020")
const YELLOW := Color("e9b824")
const TAIL := Color("8f1712")
const GLASS := Color("22303a")

static var _meshes: Dictionary = {}

static func decorate(id: String, model: Node3D) -> void:
	if id not in IDS or model == null: return
	var mesh := mesh_for(id)
	if mesh == null: return
	var detail := MeshInstance3D.new()
	detail.name = "HeavyDetail"
	detail.mesh = mesh
	detail.material_override = KIT.material()
	detail.set_meta("heavy_detail", true)
	model.add_child(detail)
	_fenders(model)
	_tires(model)
	if id == "boxrunner": _boxrunner_fairing(model)


## Defletor do baú: no V1 é uma placa de 0,62 m de espessura girada 32°, que lia
## como chapa solta em cima da cabine. Vira uma carenagem em cunha do teto da
## cabine ao topo do baú, na mesma tinta.
static func _boxrunner_fairing(model: Node3D) -> void:
	for part in model.get_children():
		if not part is MeshInstance3D or not (part.mesh is BoxMesh): continue
		if part.position.distance_to(Vector3(0, 2.3, -2.15)) > .1 or absf(part.rotation_degrees.x - 32.0) > 3.0: continue
		var paint: Material = part.material_override if part.material_override else part.mesh.surface_get_material(0)
		part.visible = false
		var fairing := MeshInstance3D.new()
		fairing.name = "HeavyFairing"
		fairing.mesh = _wedge_mesh()
		fairing.material_override = paint
		model.add_child(fairing)
		return

static func _wedge_mesh() -> ArrayMesh:
	if _meshes.has("fairing"): return _meshes["fairing"]
	# Perfil (z, y): teto da cabine à frente, sobe até o topo do baú.
	var profile := [Vector2(-2.6, 1.97), Vector2(-1.57, 1.97), Vector2(-1.57, 2.74), Vector2(-1.85, 2.74)]
	var half := 1.0
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	var left: Array = []
	var right: Array = []
	for point in profile:
		left.append(Vector3(-half, point.y, point.x))
		right.append(Vector3(half, point.y, point.x))
	# Laterais (quadriláteros convexos) e faces entre os pontos do perfil.
	for face in [[left, true], [right, false]]:
		var v: Array = face[0]
		if face[1]:
			for tri in [[0, 1, 2], [0, 2, 3]]:
				t.add_vertex(v[tri[0]]); t.add_vertex(v[tri[1]]); t.add_vertex(v[tri[2]])
		else:
			for tri in [[0, 2, 1], [0, 3, 2]]:
				t.add_vertex(v[tri[0]]); t.add_vertex(v[tri[1]]); t.add_vertex(v[tri[2]])
	for i in profile.size():
		var j := (i + 1) % profile.size()
		t.add_vertex(left[i]); t.add_vertex(right[j]); t.add_vertex(right[i])
		t.add_vertex(left[i]); t.add_vertex(left[j]); t.add_vertex(right[j])
	t.generate_normals()
	var result := t.commit()
	_meshes["fairing"] = result
	return result


## Pneus: o V1 fez cilindros lisos e o caminhão "parecia não ter roda" (usuário,
## 28/09). Banda de rodagem com cravos alternados e flanco escuro, numa peça com a
## mesma marcação `wheel_center` do pneu: o `Vehicle` a pendura no mesmo pivô e ela
## gira e esterça junto.
static func _tires(model: Node3D) -> void:
	var done := {}
	for part in model.get_children():
		if not part is MeshInstance3D or not part.has_meta("wheel_radius") or part.get_meta("wheel_spins", true) == false: continue
		if not (part.mesh is CylinderMesh): continue
		var radius: float = part.get_meta("wheel_radius")
		var box: AABB = part.transform * part.get_aabb()
		if absf(box.size.y - radius * 2.0) > .06 or box.size.x < .1: continue
		var center: Vector3 = part.get_meta("wheel_center")
		if done.has(center): continue
		done[center] = true
		var tread := MeshInstance3D.new()
		tread.name = "HeavyTread"
		tread.mesh = _tread_mesh(radius, box.size.x)
		tread.material_override = KIT.material()
		tread.position = center
		tread.set_meta("wheel_center", center)
		tread.set_meta("wheel_radius", radius)
		tread.set_meta("wheel_spins", true)
		model.add_child(tread)

static func _tread_mesh(radius: float, width: float) -> ArrayMesh:
	var key := "tread_%.2f_%.2f" % [radius, width]
	if _meshes.has(key): return _meshes[key]
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	var lugs := maxi(14, int(TAU * radius / .12))
	for i in lugs:
		var turn := Basis(Vector3.RIGHT, TAU * i / lugs)
		# Cravos alternados de um lado e do outro do sulco central.
		var offset := width * (.2 if i % 2 == 0 else -.2)
		_box(t, turn * Vector3(offset, radius + .014, 0), Vector3(width * .5, .03, .07), Color("0b0c0d"), turn)
		_box(t, turn * Vector3(0, radius + .006, 0), Vector3(width * .96, .014, .05), Color("111315"), turn)
	# Flanco: anel escuro nas duas faces, entre a banda e o aro.
	var ring := 28
	for side in [-1.0, 1.0]:
		for i in ring:
			var turn := Basis(Vector3.RIGHT, TAU * i / ring)
			_box(t, turn * Vector3(side * (width * .5 + .004), radius * .82, 0), Vector3(.012, radius * .22, TAU * radius * .82 / ring + .01), Color("25292c"), turn)
			if i % 7 == 0:
				_box(t, turn * Vector3(side * (width * .5 + .008), radius * .84, 0), Vector3(.01, .04, .12), Color("5b6166"), turn)
	t.generate_normals()
	var result := t.commit()
	_meshes[key] = result
	return result


## Para-lama dianteiro do V1: um cilindro cheio maior que a roda, que engolia o
## pneu ("tem um cilindro nele"). Esconde o cilindro e põe um arco na mesma tinta
## (mesmo material, então a repintura do veículo continua valendo).
static func _fenders(model: Node3D) -> void:
	var wheels: Array = []
	for part in model.get_children():
		if part is MeshInstance3D and part.has_meta("wheel_radius") and part.mesh is CylinderMesh:
			var entry := [part.get_meta("wheel_center"), float(part.get_meta("wheel_radius"))]
			if entry not in wheels: wheels.append(entry)
	for part in model.get_children():
		if not part is MeshInstance3D or part.has_meta("wheel_center") or not (part.mesh is CylinderMesh): continue
		var box: AABB = part.transform * part.get_aabb()
		var center := box.get_center()
		for wheel in wheels:
			var axle: Vector3 = wheel[0]
			var radius: float = wheel[1]
			if absf(center.z - axle.z) > .25 or absf(center.x - axle.x) > .25 or center.y <= axle.y: continue
			if box.size.y < radius * 2.0 or box.size.z < radius * 2.0: continue
			var paint: Material = part.material_override if part.material_override else part.mesh.surface_get_material(0)
			part.visible = false
			var arch := MeshInstance3D.new()
			arch.name = "HeavyFender"
			arch.mesh = _fender_mesh(radius, box.size.x)
			arch.material_override = paint
			arch.position = Vector3(center.x, axle.y, axle.z)
			model.add_child(arch)
			break

static func _fender_mesh(radius: float, width: float) -> ArrayMesh:
	var key := "fender_%.2f_%.2f" % [radius, width]
	if _meshes.has(key): return _meshes[key]
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	var arc_radius := radius + .1
	var segments := 12
	# Arco de ~200°: cobre o topo da roda e desce um pouco à frente e atrás.
	for i in segments:
		var angle := lerpf(-1.75, 1.75, (i + .5) / segments)
		var turn := Basis(Vector3.RIGHT, angle)
		var step := 3.5 / segments * arc_radius + .02
		_box(t, turn * Vector3(0, arc_radius, 0), Vector3(width, .07, step), Color.WHITE, turn)
		# Aba externa arredondando a borda do para-lama.
		_box(t, turn * Vector3(0, arc_radius - .05, 0), Vector3(width + .04, .04, step), Color.WHITE, turn)
	t.generate_normals()
	var result := t.commit()
	_meshes[key] = result
	return result

static func mesh_for(id: String) -> ArrayMesh:
	if _meshes.has(id): return _meshes[id]
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	match id:
		"port_forklift": _forklift(t)
		"cargo_flatbed_truck":
			_rig_cab(t)
			_rig_rear(t, 4.0)
			_flatbed(t)
		"american_dump_truck":
			_rig_cab(t)
			_rig_rear(t, 4.0)
			_dump(t)
		"american_tanker_truck":
			_rig_cab(t)
			_rig_rear(t, 4.0)
			_tanker(t)
		"boxrunner": _boxrunner(t)
		"towmaster": _towmaster(t)
	t.generate_normals()
	var mesh := t.commit()
	_meshes[id] = mesh
	return mesh

# --- primitivas -------------------------------------------------------------

static func _box(t: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	KIT._rotated_box(t, center, size, color, basis)

## Cilindro entre dois pontos (tanques, cilindros hidráulicos, buzinas).
static func _tube(t: SurfaceTool, from: Vector3, to: Vector3, radius: float, color: Color, sides := 10) -> void:
	var axis := to - from
	var up := axis.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < .95 else Vector3.RIGHT).normalized()
	var other := up.cross(side).normalized()
	t.set_color(color)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := (side * cos(a0) + other * sin(a0)) * radius
		var p1 := (side * cos(a1) + other * sin(a1)) * radius
		# Parede.
		t.add_vertex(from + p0); t.add_vertex(to + p0); t.add_vertex(to + p1)
		t.add_vertex(from + p0); t.add_vertex(to + p1); t.add_vertex(from + p1)
		# Tampas.
		t.add_vertex(to); t.add_vertex(to + p1); t.add_vertex(to + p0)
		t.add_vertex(from); t.add_vertex(from + p0); t.add_vertex(from + p1)

## Faixa refletiva vermelho/branco ao longo de Z (norma de caminhão pesado).
static func _tape_z(t: SurfaceTool, x: float, y: float, z0: float, z1: float, height := .07) -> void:
	var cell := .3
	var count := int((z1 - z0) / cell)
	for i in count:
		var z := z0 + (i + .5) * cell
		_box(t, Vector3(x, y, z), Vector3(.012, height, cell * .96), RED if i % 2 == 0 else WHITE)

static func _tape_x(t: SurfaceTool, z: float, y: float, x0: float, x1: float, height := .07) -> void:
	var cell := .25
	var count := int((x1 - x0) / cell)
	for i in count:
		_box(t, Vector3(x0 + (i + .5) * cell, y, z), Vector3(cell * .96, height, .012), RED if i % 2 == 0 else WHITE)

## Retrovisor de caminhão: braço, moldura e espelho, com espelho convexo embaixo.
static func _mirror(t: SurfaceTool, side: float, cab_x: float, y: float, z: float) -> void:
	var out := cab_x + .3
	_box(t, Vector3(side * (cab_x + .15), y + .18, z), Vector3(.3, .035, .035), CHROME)
	_box(t, Vector3(side * (cab_x + .15), y - .22, z), Vector3(.3, .035, .035), CHROME)
	_box(t, Vector3(side * out, y, z), Vector3(.06, .58, .2), DARK)
	_box(t, Vector3(side * (out + .032), y + .04, z), Vector3(.012, .44, .15), CHROME)
	_box(t, Vector3(side * (out + .01), y - .38, z - .02), Vector3(.05, .16, .16), DARK)
	_box(t, Vector3(side * (out + .038), y - .38, z - .02), Vector3(.01, .12, .12), CHROME)

## Porta: frisos, maçaneta e degrau de alumínio.
static func _door(t: SurfaceTool, side: float, x: float, y0: float, y1: float, z0: float, z1: float) -> void:
	var face := side * (x + .006)
	for z in [z0, z1]:
		_box(t, Vector3(face, (y0 + y1) * .5, z), Vector3(.012, y1 - y0, .018), DARK)
	_box(t, Vector3(face, y0 + .02, (z0 + z1) * .5), Vector3(.012, .018, z1 - z0), DARK)
	_box(t, Vector3(side * (x + .02), y0 + (y1 - y0) * .55, z1 - .22), Vector3(.03, .045, .2), CHROME)

static func _mud_flap(t: SurfaceTool, side: float, x: float, z: float, top: float) -> void:
	_box(t, Vector3(side * x, top * .5 + .1, z), Vector3(.5, top - .2, .025), RUBBER)
	_box(t, Vector3(side * x, top, z), Vector3(.52, .05, .05), CHROME)

# --- caminhão americano (plataforma, basculante, tanque) --------------------

## Cabine comum: cabine x ±1,04 de y 0,63 a 1,98, z −2,03 a −0,61; capô até −3,9.
static func _rig_cab(t: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		_mirror(t, side, 1.04, 2.02, -1.9)
		_door(t, side, 1.04, .7, 1.95, -1.96, -.74)
		# Aletas de ventilação na lateral do capô.
		for i in 5:
			_box(t, Vector3(side * .745, 1.18, -3.45 + i * .2), Vector3(.012, .32, .06), DARK)
		# Faixa de acabamento cromada na base da cabine.
		_box(t, Vector3(side * 1.047, .68, -1.32), Vector3(.012, .05, 1.4), CHROME)
		# Luz de posição âmbar no para-lama dianteiro.
		_box(t, Vector3(side * 1.05, .98, -3.3), Vector3(.05, .06, .14), AMBER)
	# Para-sol sobre o para-brisa e buzinas a ar no teto.
	_box(t, Vector3(0, 2.52, -2.12), Vector3(1.95, .06, .34), DARK, Basis(Vector3.RIGHT, -.18))
	for x in [-.42, .42]:
		_tube(t, Vector3(x, 2.73, -1.25), Vector3(x, 2.73, -1.8), .05, CHROME, 8)
		_tube(t, Vector3(x, 2.73, -1.8), Vector3(x, 2.73, -1.92), .085, CHROME, 8)
	# Moldura cromada da grade, ornamento do capô, ganchos de reboque e faróis de neblina.
	_box(t, Vector3(0, 1.62, -4.03), Vector3(1.24, .05, .04), CHROME)
	_box(t, Vector3(0, .74, -4.03), Vector3(1.24, .05, .04), CHROME)
	for x in [-.62, .62]:
		_box(t, Vector3(x, 1.18, -4.03), Vector3(.05, .93, .04), CHROME)
	_box(t, Vector3(0, 1.55, -3.88), Vector3(.05, .1, .14), CHROME)
	for x in [-.55, .55]:
		_box(t, Vector3(x, .42, -4.15), Vector3(.08, .14, .12), RED)
	for x in [-.92, .92]:
		_box(t, Vector3(x, .6, -4.17), Vector3(.2, .12, .03), WHITE)
	# Escapamentos: protetor térmico perfurado e tampa de chuva inclinada.
	for side in [-1.0, 1.0]:
		_tube(t, Vector3(side * 1.03, 2.1, -.48), Vector3(side * 1.03, 2.75, -.48), .105, Color("aeb6bb"), 12)
		for y in [2.2, 2.35, 2.5, 2.65]:
			_tube(t, Vector3(side * 1.03, y, -.48), Vector3(side * 1.03, y + .03, -.48), .11, DARK, 12)
		_box(t, Vector3(side * 1.03, 3.2, -.42), Vector3(.16, .02, .18), DARK, Basis(Vector3.RIGHT, -.5))
		# Cintas do tanque de combustível e degrau em cima dele.
		for z in [-.12, .6]:
			_tube(t, Vector3(side * .92, .74, z), Vector3(side * .92, .74, z + .05), .275, STEEL, 14)
		_box(t, Vector3(side * .95, 1.01, .24), Vector3(.36, .03, .5), PLATE)
		# Moldura da janela lateral.
		_box(t, Vector3(side * 1.063, 2.15, -1.37), Vector3(.012, .7, .05), DARK)
		_box(t, Vector3(side * 1.063, 2.47, -1.37), Vector3(.012, .05, 1.06), DARK)
	# Limpadores de para-brisa.
	for x in [-.45, .35]:
		_box(t, Vector3(x, 1.86, -2.075), Vector3(.62, .025, .025), DARK, Basis(Vector3.BACK, .35))
	# Caixa de bateria cromada atrás do degrau esquerdo.
	_box(t, Vector3(-.95, .6, -.72), Vector3(.3, .36, .3), CHROME)

## Traseira comum: para-choque anti-encaixe, para-barros, lanternas e placa.
## `flaps`: os americanos têm o eixo traseiro colado na traseira; baú e guincho
## têm eixo recuado e põem o próprio para-barro atrás da roda.
static func _rig_rear(t: SurfaceTool, rear_z: float, flaps := true) -> void:
	_box(t, Vector3(0, .42, rear_z + .1), Vector3(2.0, .14, .1), STEEL)
	_tape_x(t, rear_z + .156, .42, -.95, .95, .09)
	for x in [-.7, .7]:
		_box(t, Vector3(x, .5, rear_z + .02), Vector3(.08, .2, .2), STEEL)
	for side in [-1.0, 1.0]:
		if flaps: _mud_flap(t, side, 1.0, rear_z - .1, .78)
		_box(t, Vector3(side * .8, .66, rear_z + .06), Vector3(.28, .1, .04), TAIL)
		_box(t, Vector3(side * .55, .66, rear_z + .06), Vector3(.1, .1, .04), AMBER)
	_box(t, Vector3(0, .62, rear_z + .07), Vector3(.34, .17, .02), WHITE)
	_box(t, Vector3(0, .62, rear_z + .075), Vector3(.28, .04, .01), DARK)

static func _flatbed(t: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		# Catracas de cinta sob a borda da plataforma, com a cinta enrolada.
		for i in 7:
			var z := -.2 + i * .62
			_box(t, Vector3(side * 1.16, .83, z), Vector3(.12, .12, .16), STEEL)
			_box(t, Vector3(side * 1.17, .83, z), Vector3(.13, .07, .09), YELLOW)
		_tape_z(t, side * 1.212, .96, -.4, 3.9)
		# Caixa de ferramentas em chapa xadrez entre o tanque e o eixo.
		_box(t, Vector3(side * .95, .7, 1.08), Vector3(.36, .38, .58), PLATE)
		_box(t, Vector3(side * 1.132, .82, 1.08), Vector3.ONE * .03 + Vector3(0, 0, .12), CHROME)
	# Grade de proteção da cabine: barras horizontais no quadro existente.
	for y in [1.15, 1.35, 1.55, 1.75]:
		_box(t, Vector3(0, y, -.43), Vector3(2.3, .035, .035), STEEL)
	# Correntes de amarração enroladas na frente da plataforma.
	for x in [-.6, .6]:
		_box(t, Vector3(x, 1.13, -.2), Vector3(.35, .09, .25), STEEL)

static func _dump(t: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		_tape_z(t, side * 1.21, 1.2, -.4, 3.9)
		# Pino de engate da tampa traseira.
		_box(t, Vector3(side * 1.12, 2.35, 3.98), Vector3(.16, .16, .16), STEEL)
	# Escada lateral na frente da caçamba e cilindro basculante aparente.
	for y in range(0, 5):
		_box(t, Vector3(-1.3, 1.25 + y * .28, -.36), Vector3(.05, .04, .3), STEEL)
	for z in [-.5, -.22]:
		_box(t, Vector3(-1.3, 1.8, z), Vector3(.04, 1.3, .04), STEEL)
	_tube(t, Vector3(0, .64, .4), Vector3(0, 1.0, .7), .12, CHROME)
	# Trava da tampa e lona enrolada no topo frontal.
	_box(t, Vector3(0, 2.1, 4.02), Vector3(.9, .08, .06), DARK)
	_tube(t, Vector3(-1.1, 2.6, -.42), Vector3(1.1, 2.6, -.42), .11, Color("3a5a3f"))

static func _tanker(t: SurfaceTool) -> void:
	# Bocas de visita no topo, ao longo da passarela.
	for z in [.25, 1.72, 3.2]:
		_tube(t, Vector3(0, 2.95, z), Vector3(0, 3.1, z), .24, STEEL, 12)
		_tube(t, Vector3(0, 3.1, z), Vector3(0, 3.14, z), .16, CHROME, 12)
	# Guarda-corpo rebatível da passarela.
	for side in [-1.0, 1.0]:
		_box(t, Vector3(side * .3, 3.3, 1.72), Vector3(.03, .03, 3.0), YELLOW)
		for z in [.3, 1.2, 2.2, 3.1]:
			_box(t, Vector3(side * .3, 3.17, z), Vector3(.03, .26, .03), YELLOW)
		# Porta-mangueira (tubo) sob o tanque e faixa refletiva.
		_tube(t, Vector3(side * 1.02, 1.02, .0), Vector3(side * 1.02, 1.02, 3.3), .09, STEEL)
		_tape_z(t, side * 1.09, 1.35, -.2, 3.7)
		# Placa de risco (losango) nas laterais.
		_box(t, Vector3(side * 1.1, 1.95, 1.72), Vector3(.012, .42, .42), AMBER, Basis(Vector3.RIGHT, PI * .25))
	# Losango de risco na traseira e válvulas de descarga.
	_box(t, Vector3(0, 1.85, 3.96), Vector3(.42, .42, .012), AMBER, Basis(Vector3.BACK, PI * .25))
	_box(t, Vector3(0, 1.85, 3.97), Vector3(.2, .05, .01), DARK)
	for x in [-.35, .35]:
		_tube(t, Vector3(x, .8, 3.7), Vector3(x, .8, 4.02), .07, CHROME)
		_box(t, Vector3(x, .8, 4.04), Vector3(.12, .12, .04), RED)

# --- baú urbano ---------------------------------------------------------------

## Cabine x ±1,075, y 0,53 a 1,98, z −3,28 a −1,63; baú x ±1,11, z −1,58 a 3,28.
static func _boxrunner(t: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		_mirror(t, side, 1.075, 1.85, -3.05)
		_door(t, side, 1.075, .6, 1.95, -3.1, -1.8)
		# Lanternas de posição âmbar no topo do baú e faixa de marca.
		for z in [-1.3, 0.0, 1.3, 2.6]:
			_box(t, Vector3(side * 1.12, 2.62, z), Vector3(.03, .06, .12), AMBER)
		_box(t, Vector3(side * 1.113, 1.62, .85), Vector3(.012, .32, 4.7), Color("2f6fa8"))
		_box(t, Vector3(side * 1.114, 1.4, .85), Vector3(.012, .06, 4.7), Color("e0892a"))
		_tape_z(t, side * 1.115, .78, -1.4, 3.1)
		# Saia lateral e para-barro.
		_mud_flap(t, side, .95, 2.85, .72)
	# Grade, faróis e para-choque cromado na frente da cabine.
	_box(t, Vector3(0, 1.0, -3.36), Vector3(1.3, .38, .03), DARK)
	for y in [.9, 1.0, 1.1]:
		_box(t, Vector3(0, y, -3.375), Vector3(1.26, .03, .02), CHROME)
	_box(t, Vector3(0, .45, -3.45), Vector3(2.2, .06, .04), CHROME)
	# Portas traseiras: dobradiças e travas verticais.
	for x in [-.97, .97]:
		for y in [1.0, 1.6, 2.2]:
			_box(t, Vector3(x, y, 3.30), Vector3(.08, .12, .03), STEEL)
	for x in [-.25, .25]:
		_box(t, Vector3(x, 1.65, 3.30), Vector3(.035, 1.8, .035), CHROME)
	_rig_rear(t, 3.25, false)
	_box(t, Vector3(0, .4, 3.45), Vector3(1.4, .06, .3), PLATE)

# --- guincho plataforma -------------------------------------------------------

## Cabine x ±1,1, y 0,55 a 2,0, z −3,37 a −1,52; plataforma y 0,92, z −1,47 a 3,37.
static func _towmaster(t: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		_mirror(t, side, 1.1, 1.85, -3.1)
		_door(t, side, 1.1, .62, 1.98, -3.2, -1.72)
		_tape_z(t, side * 1.13, .87, -1.3, 3.2)
		# Alavancas de comando da plataforma no lado do motorista e caixas de ferramenta.
		_box(t, Vector3(side * 1.12, .62, .95), Vector3(.05, .36, 1.1), PLATE)
		_box(t, Vector3(side * 1.15, .74, .95), Vector3(.03, .03, .9), CHROME)
		# Estrobos âmbar nos cantos traseiros e corrente de segurança amarela.
		_box(t, Vector3(side * 1.02, 1.02, 3.3), Vector3(.14, .1, .14), AMBER)
		for i in 6:
			_box(t, Vector3(side * .55, .95, 2.85 + i * .08), Vector3(.05, .04, .07), YELLOW)
	for i in 3:
		_box(t, Vector3(1.05, .75, .5 + i * .12), Vector3(.02, .16, .02), RED)
	# Calços de roda presos na plataforma e cabo do guincho até a frente.
	for x in [-.7, .7]:
		_box(t, Vector3(x, 1.04, 3.05), Vector3(.25, .18, .3), YELLOW)
	_box(t, Vector3(.51, 1.0, 1.0), Vector3(.03, .03, 4.2), DARK)
	# Grade e para-choque da cabine.
	_box(t, Vector3(0, 1.0, -3.42), Vector3(1.3, .36, .03), DARK)
	_box(t, Vector3(0, .5, -3.66), Vector3(2.2, .06, .04), CHROME)
	_rig_rear(t, 3.62, false)

# --- empilhadeira -------------------------------------------------------------

## Corpo x ±0,55, y 0,2 a 0,9, z −0,45 a 1,45; mastro em z ≈ −0,65; contrapeso até 1,73.
static func _forklift(t: SurfaceTool) -> void:
	# Mastro: correntes (elos alternados) e cilindros de elevação laterais. Presos
	# ao mastro fixo, não ao carro de garfos, que sobe e desce.
	for side in [-1.0, 1.0]:
		var x: float = side * .22
		for i in 19:
			var y := .55 + i * .08
			_box(t, Vector3(x, y, -.72), Vector3(.035 if i % 2 == 0 else .05, .07, .035 if i % 2 else .05), DARK)
		_tube(t, Vector3(x, 2.02, -.78), Vector3(x, 2.02, -.62), .07, STEEL)
		_tube(t, Vector3(side * .31, .42, -.55), Vector3(side * .31, 1.75, -.55), .045, CHROME, 8)
		_tube(t, Vector3(side * .31, .42, -.55), Vector3(side * .31, .8, -.55), .065, STEEL, 8)
		# Cilindro de inclinação do mastro, do chassi até a coluna.
		_tube(t, Vector3(side * .46, .62, -.2), Vector3(side * .44, .9, -.6), .04, CHROME, 8)
		# Mangueiras hidráulicas descendo pela coluna.
		_box(t, Vector3(side * .12, 1.3, -.62), Vector3(.025, 1.5, .025), RUBBER)
		# Estribo antiderrapante e faixa preta na lateral laranja.
		_box(t, Vector3(side * .6, .3, .25), Vector3(.14, .03, .4), PLATE)
		_box(t, Vector3(side * .552, .52, .55), Vector3(.012, .06, 1.7), DARK)
		# Alça de apoio na coluna traseira da proteção.
		_box(t, Vector3(side * .49, 1.05, 1.08), Vector3(.03, .5, .03), YELLOW)
	# Cilindro de GLP atrás do banco, com cintas e válvula.
	_tube(t, Vector3(-.36, 1.08, 1.28), Vector3(.36, 1.08, 1.28), .17, WHITE, 12)
	_tube(t, Vector3(.36, 1.08, 1.28), Vector3(.42, 1.08, 1.28), .06, CHROME, 8)
	for x in [-.22, .22]:
		_box(t, Vector3(x, 1.08, 1.28), Vector3(.04, .36, .36), DARK)
	_box(t, Vector3(0, .88, 1.28), Vector3(.8, .06, .3), DARK)
	# Contrapeso: zebrado de segurança, lanternas e pino de reboque.
	for i in 7:
		var x := -.52 + i * .17
		_box(t, Vector3(x, .52, 1.735), Vector3(.07, .5, .012), YELLOW, Basis(Vector3.BACK, .5))
	_box(t, Vector3(0, .52, 1.73), Vector3(1.16, .56, .006), RUBBER)
	for x in [-.46, .46]:
		_box(t, Vector3(x, .8, 1.745), Vector3(.14, .08, .02), TAIL)
	_box(t, Vector3(0, .3, 1.75), Vector3(.2, .12, .06), STEEL)
	# Painel com mostrador e retrovisores na proteção.
	_box(t, Vector3(0, 1.02, -.05), Vector3(.5, .18, .06), DARK, Basis(Vector3.RIGHT, -.4))
	_box(t, Vector3(.1, 1.04, -.085), Vector3(.12, .08, .01), GLASS, Basis(Vector3.RIGHT, -.4))
	for side in [-1.0, 1.0]:
		_box(t, Vector3(side * .56, 1.95, -.1), Vector3(.12, .03, .03), DARK)
		_box(t, Vector3(side * .63, 1.95, -.1), Vector3(.03, .14, .1), CHROME)
