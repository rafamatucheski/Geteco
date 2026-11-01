extends RefCounted
## Malha do interior (volante, painel, bancos, console, pedais, retrovisor, forro, cintos; ônibus,
## buggy e empilhadeira) montada por `mesh_for`, separada do VehicleInterior em 01/11 (Onda 2 do
## plano de divisão). Tudo estático, como o dono. `g` é o script do VehicleInterior (preload
## cíclico, como CityNightLamps faz com CityChunkDressing): o que testes leem continua lá (_meshes,
## _material, _alpha_material e as cores C_*, lidas por test_coupe_cabin) e é lido por `g.`. As
## ferramentas e malhas do volante (_wheel_*) e do forro (_alpha_tool) moram aqui; o dono mantém
## `mesh_for` como delegação de uma linha com a mesma assinatura.

const g := preload("res://gameplay/VehicleInterior.gd")
const PROP_KIT := preload("res://world/city_look/CityPropKit.gd")

static var _alpha_tool: SurfaceTool
## Volante em malha própria (ver `_steering_wheel`): ferramenta durante `mesh_for`, malha e quadro do cubo
## (no espaço do interior) por arquétipo.
static var _wheel_tool: SurfaceTool
static var _wheel_frame := Transform3D.IDENTITY
static var _wheel_meshes: Dictionary = {}
static var _wheel_frames: Dictionary = {}
static func mesh_for(id: String, s: Dictionary) -> ArrayMesh:
	if g._meshes.has(id): return g._meshes[id]
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	# Segunda superficie: o forro do teto, translucido, para nao esconder o motorista de cima.
	_alpha_tool = SurfaceTool.new()
	_alpha_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_alpha_tool.set_smooth_group(-1)
	_wheel_tool = SurfaceTool.new()
	_wheel_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_wheel_tool.set_smooth_group(-1)
	_wheel_frame = Transform3D.IDENTITY
	var wheel_tool := _wheel_tool
	match str(s.kind):
		"forklift": _forklift(t, s)
		"buggy": _buggy(t, s)
		"bus": _bus(t, s)
		_: _cabin(t, s)
	t.generate_normals()
	var mesh := t.commit()
	mesh.surface_set_material(0, g._interior_material())
	if _alpha_tool != null:
		_alpha_tool.generate_normals()
		_alpha_tool.commit(mesh)
		if mesh.get_surface_count() > 1:
			mesh.surface_set_material(1, g._interior_alpha_material())
	_alpha_tool = null
	_wheel_tool = null
	if _wheel_frame != Transform3D.IDENTITY:
		wheel_tool.generate_normals()
		var wheel := wheel_tool.commit()
		if wheel.get_surface_count() > 0:
			wheel.surface_set_material(0, g._interior_material())
			_wheel_meshes[id] = wheel
			_wheel_frames[id] = _wheel_frame
	g._meshes[id] = mesh
	return mesh

## Mesma caixa do kit da cidade (cantos, ordem dos triângulos e cor por vértice idênticos);
## as normais continuam saindo do generate_normals de mesh_for.
static func _box(t: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	PROP_KIT._rotated_box(t, center, size, color, basis)

static func _tube(t: SurfaceTool, from: Vector3, to: Vector3, radius: float, color: Color, sides := 6) -> void:
	var axis := to - from
	if axis.length() < .001: return
	var up := axis.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < .95 else Vector3.RIGHT).normalized()
	var other := up.cross(side).normalized()
	t.set_color(color)
	for i in sides:
		var p0 := (side * cos(TAU * i / sides) + other * sin(TAU * i / sides)) * radius
		var p1 := (side * cos(TAU * (i + 1) / sides) + other * sin(TAU * (i + 1) / sides)) * radius
		t.add_vertex(from + p0); t.add_vertex(to + p0); t.add_vertex(to + p1)
		t.add_vertex(from + p0); t.add_vertex(to + p1); t.add_vertex(from + p1)
		t.add_vertex(to); t.add_vertex(to + p1); t.add_vertex(to + p0)
		t.add_vertex(from); t.add_vertex(from + p0); t.add_vertex(from + p1)

## Base do plano do volante: X para a direita, Y no plano para cima, Z para o motorista.
static func _wheel_basis(tilt: float) -> Basis:
	return Basis(Vector3.RIGHT, Vector3(0, cos(tilt), -sin(tilt)), Vector3(0, sin(tilt), cos(tilt)))

## O aro, o miolo e os raios vão para uma malha própria (`_wheel_tool`, em volta do cubo e no plano do
## volante) que gira com a direção (`_steer_pose`); a coluna fica no interior. Antes o volante era parte da
## malha única e ficava parado com as mãos presas nele enquanto as rodas viravam.
static func _steering_wheel(t: SurfaceTool, hub: Vector3, radius: float, tilt: float, rim: Color, column_to: Vector3) -> void:
	var b := _wheel_basis(tilt)
	var w := _wheel_tool if _wheel_tool != null else t
	var center := Vector3.ZERO if _wheel_tool != null else hub
	var frame := Basis.IDENTITY if _wheel_tool != null else b
	if _wheel_tool != null: _wheel_frame = Transform3D(b, hub)
	var segments := 14
	var arc := TAU * radius / segments * 1.12
	var thickness := .036 if radius < .22 else .046
	for i in segments:
		var a := TAU * (i + .5) / segments
		var local_basis := frame * Basis(Vector3.BACK, a)
		_box(w, center + frame * Vector3(cos(a), sin(a), 0) * radius, Vector3(thickness, arc, thickness), rim, local_basis)
	# Miolo e três raios (T): esquerdo, direito e inferior.
	_box(w, center, Vector3(radius * .5, radius * .5, .05), g.C_TRIM, frame)
	_box(w, center + frame * Vector3(0, 0, .032), Vector3(radius * .26, radius * .26, .02), g.C_CHROME, frame)
	for a in [0.0, PI, PI * 1.5]:
		_box(w, center + frame * Vector3(cos(a), sin(a), 0) * radius * .5, Vector3(radius * .9, .04, .03), g.C_TRIM, frame * Basis(Vector3.BACK, a))
	_tube(t, hub - b.z * .04, column_to, .034, g.C_TRIM, 6)

## Banco com encosto inclinado, apoio de cabeça e laterais.
static func _seat(t: SurfaceTool, x: float, z: float, cush: float, recline: float, width: float, color: Color, headrest := true, tall := 0.0, seat_floor := -INF) -> void:
	# Cabines esportivas baixas precisam de almofada de assento rasa e trilhos acima do piso.
	# Modelos legados mantêm o pedestal original quando não há piso definido.
	var padding := minf(.14, maxf(.035, cush - seat_floor - .035))
	_box(t, Vector3(x, cush - padding*.5, z), Vector3(width, padding, .50), color)
	# Base do banco / trilho.
	var rail_bottom := maxf(cush - .20, seat_floor + .005)
	var rail_top := maxf(rail_bottom + .015, cush - padding - .008) if is_finite(seat_floor) else cush - .14
	_box(t, Vector3(x, (rail_bottom + rail_top)*.5, z), Vector3(width * .7, rail_top - rail_bottom, .40), g.C_TRIM)
	var tilt := Basis(Vector3.RIGHT, recline + .05)
	var base := Vector3(x, cush, z + .23)
	var back_h := .58 + tall
	_box(t, base + tilt * Vector3(0, back_h * .5, 0), Vector3(width, back_h, .11), color, tilt)
	for side in [-1.0, 1.0]:
		_box(t, base + tilt * Vector3(side * (width * .5 - .03), back_h * .46, -.07), Vector3(.07, back_h * .8, .09), g.C_SEAT_DARK, tilt)
		_box(t, Vector3(x + side * (width * .5 - .03), cush + .02, z - .05), Vector3(.07, .07, .40), g.C_SEAT_DARK)
	if headrest:
		_box(t, base + tilt * Vector3(0, back_h + .1, -.005), Vector3(width * .42, .17, .10), color.darkened(.08), tilt)
		for side in [-1.0, 1.0]:
			_tube(t, base + tilt * Vector3(side * width * .12, back_h - .02, 0), base + tilt * Vector3(side * width * .12, back_h + .04, 0), .012, g.C_CHROME, 4)

## Cinto de três pontos do motorista: a tira sai do ombro externo e desce em diagonal pela
## frente do peito até a fivela do lado do console.
static func _belt(t: SurfaceTool, s: Dictionary) -> void:
	var rec := float(s.rec) + .05
	var hip := Vector3(float(s.sx), float(s.floor) + float(s.hip), float(s.sz))
	var scale := float(s.scale)
	var d := Vector3(0, cos(rec), sin(rec))
	var n := Vector3(0, sin(rec), -cos(rec))
	var top := hip + d * .50 * scale + n * .17 * scale + Vector3(-.15, 0, 0) * scale
	var low := hip + d * .06 * scale + n * .19 * scale + Vector3(.13, 0, 0) * scale
	var mid := (top + low) * .5
	var axis := (low - top)
	var length := axis.length()
	var y_dir := axis / length
	var x_dir := Vector3(y_dir.y, -y_dir.x, 0).normalized()
	var z_dir := x_dir.cross(y_dir).normalized()
	_box(t, mid, Vector3(.05, length, .012), g.C_BELT, Basis(x_dir, y_dir, z_dir))
	_box(t, low + Vector3(.01, -.01, 0), Vector3(.06, .05, .03), g.C_CHROME)

## Cabine comum: carro, esportivo, SUV, picape, van e caminhão.
static func _cabin(t: SurfaceTool, s: Dictionary) -> void:
	var w := float(s.w)
	var sx := float(s.sx)
	var sz := float(s.sz)
	var floor_y := float(s.floor)
	var cush := float(s.cush)
	var belt := float(s.belt)
	var roof := float(s.roof)
	var wz0 := float(s.wz0)
	var wz1 := float(s.wz1)
	var rear := float(s.rear)
	var rec := float(s.rec)
	var kind := str(s.kind)
	var open_top := bool(s.open_top)
	var big := kind in ["truck", "van"]
	var seat_w := .52 if not big else .58
	var seat_color: Color = g.C_SEAT
	# Piso e túnel central.
	var floor_back := rear - .12
	_box(t, Vector3(0, floor_y - .01, (wz0 + floor_back) * .5), Vector3(w * 2 - .04, .03, floor_back - wz0), g.C_CARPET)
	# Painel: bloco do para-brisa até a coluna de direção, com topo na linha da cintura.
	var dash_top := belt - .03
	var dash_back := float(s.hub_z) - float(s.r) * .55 - .04
	var dash_front := wz0 + float(s.get("dash_front_inset", -.04))
	var dash_depth := maxf(dash_back - dash_front, float(s.get("dash_min_depth", .2)))
	_box(t, Vector3(0, (dash_top + floor_y) * .5, dash_front + dash_depth * .5), Vector3(w * 2 - .02, dash_top - floor_y, dash_depth), g.C_DASH)
	_box(t, Vector3(0, dash_top + .005, dash_front + dash_depth * .5), Vector3(w * 2 - .04, .02, dash_depth - .04), g.C_DASH_TOP)
	# Saídas de ar e alto-falante no topo do painel.
	for x in [sx * 1.0, sx * .35, -sx * .35, -sx * 1.0]:
		_box(t, Vector3(x, dash_top + .022, dash_front + .1), Vector3(.13, .012, .05), g.C_TRIM)
	_box(t, Vector3(0, dash_top + .022, dash_front + .13), Vector3(.18, .012, .07), g.C_TRIM)
	# Capelo do painel de instrumentos, com mostradores voltados para o motorista.
	var hub_z := float(s.hub_z)
	var cluster_z := float(s.get("cluster_z", dash_back - .05))
	var cluster_rise := float(s.get("cluster_rise", .06))
	var cluster_depth := float(s.get("cluster_depth", .22))
	var dial_z := cluster_z + cluster_depth * .5 + .004
	_box(t, Vector3(sx, dash_top + cluster_rise, cluster_z), Vector3(.46, .11, cluster_depth), g.C_TRIM, Basis(Vector3.RIGHT, .18))
	for dx in [-.11, .11]:
		_box(t, Vector3(sx + dx, dash_top + cluster_rise + .01, dial_z), Vector3(.13, .075, .012), g.C_DIAL, Basis(Vector3.RIGHT, .18))
	_box(t, Vector3(sx, dash_top + cluster_rise + .01, dial_z), Vector3(.05, .05, .012), g.C_AMBER, Basis(Vector3.RIGHT, .18))
	# Console de rádio e climatização, e luvas do passageiro.
	_box(t, Vector3(0, dash_top - .14, dash_back - .02), Vector3(.30, .26, .12), Color("2e3136"))
	_box(t, Vector3(0, dash_top - .08, dash_back + .045), Vector3(.24, .09, .01), Color("8b959c"))
	for kx in [-.08, 0.0, .08]:
		_box(t, Vector3(kx, dash_top - .19, dash_back + .045), Vector3(.045, .045, .02), g.C_CHROME)
	_box(t, Vector3(-sx, dash_top - .13, dash_back + .015), Vector3(.40, .012, .012), Color("0f1012"))
	_box(t, Vector3(-sx, dash_top - .27, dash_back + .015), Vector3(.40, .012, .012), Color("0f1012"))
	# Volante e coluna.
	var column_to := Vector3(sx, float(s.hub_y) - .30, hub_z - .18)
	_steering_wheel(t, Vector3(sx, float(s.hub_y), hub_z), float(s.r), float(s.tilt), g.C_TRIM, column_to)
	# Pedais (freio, acelerador e apoio do pé esquerdo).
	var pedal_z := sz - float(s.foot_dist) - .05
	for entry in [[sx - .13, .07, .05], [sx + .02, .05, .045], [sx + .15, .08, .04]]:
		_box(t, Vector3(entry[0], floor_y + .12, pedal_z), Vector3(entry[1], .015 + entry[2], .12), g.C_RUBBER, Basis(Vector3.RIGHT, .7))
	# Bancos dianteiros e cinto.
	_seat(t, sx, sz, cush, rec, seat_w, seat_color, true, .05 if big else 0.0, float(s.get("seat_floor", -INF)))
	_seat(t, -sx, sz, cush, rec, seat_w, seat_color, true, .05 if big else 0.0, float(s.get("seat_floor", -INF)))
	_belt(t, s)
	# Console central: túnel, câmbio, freio de mão e porta-copos.
	_box(t, Vector3(0, floor_y + .11, sz - .05), Vector3(.22, .22, .78), Color("23262a"))
	_box(t, Vector3(0, floor_y + .225, sz - .05), Vector3(.2, .02, .74), Color("30343a"))
	var shift_top := Vector3(0, floor_y + (.52 if kind == "truck" else .36), sz - .28)
	_tube(t, Vector3(0, floor_y + .23, sz - .22), shift_top, .014, g.C_CHROME, 5)
	_box(t, shift_top + Vector3(0, .02, 0), Vector3(.05, .05, .05), g.C_TRIM)
	_box(t, Vector3(0, floor_y + .26, sz + .12), Vector3(.17, .05, .08), g.C_TRIM, Basis(Vector3.RIGHT, -.35))
	for cx in [-.05, .05]:
		_box(t, Vector3(cx, floor_y + .235, sz + .22), Vector3(.06, .012, .06), g.C_RUBBER)
	# Bancos traseiros: banco corrido com três apoios de cabeça.
	if bool(s.rows) and rear - sz > 1.3 and not big and not open_top:
		var rz := minf(rear - .44, sz + .98)
		_box(t, Vector3(0, cush - .09, rz), Vector3(w * 2 - .16, .14, .50), seat_color)
		var tilt := Basis(Vector3.RIGHT, .16)
		_box(t, Vector3(0, cush + .26, rz + .24), Vector3(w * 2 - .16, .58, .10), seat_color, tilt)
		for hx in [-w * .5, 0.0, w * .5]:
			_box(t, Vector3(hx, cush + .62, rz + .225), Vector3(.18, .15, .09), seat_color.darkened(.08), tilt)
	elif big and kind == "van":
		# Cabine de van: banco do passageiro em dois lugares e divisória atrás.
		_box(t, Vector3(0, cush + .28, rear + .05), Vector3(w * 2 - .04, .7, .05), Color("3a3d42"))
	# Porta-luvas, painéis de porta e apoio de braço.
	for side in [-1.0, 1.0]:
		var cardx: float = side * (w - .015)
		_box(t, Vector3(cardx, (floor_y + belt - .12) * .5 + .02, (wz0 + floor_back) * .5 + .05), Vector3(.03, belt - floor_y - .1, floor_back - wz0 - .3), g.C_TRIM)
		_box(t, Vector3(cardx - side * .03, belt - .13, sz + .05), Vector3(.07, .05, .36), Color("3a3d42"))
		_box(t, Vector3(cardx - side * .02, belt - .04, (wz0 + floor_back) * .5 + .05), Vector3(.05, .03, floor_back - wz0 - .34), Color("2b2e33"))
	if open_top: return
	# Forro do teto sob o teto, com luz de cortesia; quebra-sóis e retrovisor interno.
	var roof_z0 := wz1 - .02
	var roof_z1 := minf(rear - .1, floor_back)
	# `rear` é a base do vidro traseiro. O forro plano e o acabamento dele
	# precisam parar na borda superior, antes de o vidro descer em direção ao porta-malas.
	roof_z1 = minf(roof_z1, float(s.rear_top) - .04)
	roof_z1 = minf(roof_z1, float(s.get("roof_rear", roof_z1)))
	if bool(s.get("roof_liner", true)):
		_box(_alpha_tool, Vector3(0, roof - .04, (roof_z0 + roof_z1) * .5), Vector3(w * 2 - .06, .03, roof_z1 - roof_z0), Color(g.C_ROOF, .30))
	_box(t, Vector3(0, roof - .058, sz + .1), Vector3(.14, .012, .09), Color("f0ecdc"))
	for vx in [sx, -sx]:
		_box(t, Vector3(vx, roof - .075, wz1 + .16), Vector3(.36, .018, .17), Color("a29b8b"))
	var mirror_top := Vector3(0, roof - .1, wz1 + .04)
	_tube(t, mirror_top, mirror_top + Vector3(0, -.06, .06), .012, g.C_TRIM, 4)
	_box(t, mirror_top + Vector3(0, -.09, .075), Vector3(.22, .06, .03), g.C_TRIM)
	_box(t, mirror_top + Vector3(0, -.09, .092), Vector3(.19, .045, .005), Color("8fa2ad"))
	# Colunas A e traseira (acabamento interno) — linhas escuras ao longo das janelas.
	var trim_x := float(s.get("roof_trim_x", w - .03))
	var trim_y := float(s.get("roof_trim_y", roof - .05))
	for side in [-1.0, 1.0]:
		_box(t, Vector3(side * trim_x, trim_y, (roof_z0 + roof_z1) * .5), Vector3(.05, .04, roof_z1 - roof_z0), g.C_TRIM)

## Ônibus: cabine do motorista alta, volante quase deitado, corredor com bancos duplos,
## barras de apoio e luminárias. Uma malha só para o veículo inteiro.
static func _bus(t: SurfaceTool, s: Dictionary) -> void:
	_cabin(t, s)
	var w := float(s.w)
	var floor_y := float(s.floor)
	var roof := float(s.roof)
	var sz := float(s.sz)
	var rear := float(s.rear)
	var seat_color := Color("3d6a8a")
	var z := sz + 1.5
	while z < rear - .6:
		# Dois lugares por lado do corredor: um junto da janela e outro junto do corredor.
		for side in [-1.0, 1.0]:
			for lane in [w - .27, .52]:
				_seat(t, side * float(lane), z, floor_y + .42, .0, .44, seat_color, false, .05)
		z += 1.05
	# Barras de apoio verticais e corrimão longitudinal no teto.
	for side in [-1.0, 1.0]:
		var rail_x: float = side * .12
		_tube(t, Vector3(rail_x, roof - .16, sz + 1.2), Vector3(rail_x, roof - .16, rear - .4), .022, g.C_CHROME, 5)
		var pz := sz + 1.2
		while pz < rear - .5:
			_tube(t, Vector3(rail_x, floor_y, pz), Vector3(rail_x, roof - .16, pz), .02, Color("d9a322"), 5)
			pz += 2.1
	# Luminárias de teto.
	var lz := sz + 1.0
	while lz < rear - .3:
		_box(t, Vector3(0, roof - .07, lz), Vector3(.5, .015, .16), Color("f3efe0"))
		lz += 1.5
	# Cofre / catraca junto ao motorista.
	_box(t, Vector3(float(s.sx) + .62, floor_y + .5, sz - .4), Vector3(.3, 1.0, .3), Color("2f3338"))
	# Banco traseiro corrido.
	_seat(t, 0.0, rear - .5, floor_y + .42, .0, w * 1.6, seat_color, false, .05)

## Buggy: dois bancos concha, volante, alavanca de câmbio e cintos; sem painel nem teto.
static func _buggy(t: SurfaceTool, s: Dictionary) -> void:
	var sx := float(s.sx)
	var sz := float(s.sz)
	var cush := float(s.cush)
	var floor_y := float(s.floor)
	_seat_shell(t, sx, sz, cush, Color("2d2924"))
	_seat_shell(t, -sx, sz, cush, Color("2d2924"))
	# Painel baixo e coluna de direção.
	var hub_z := float(s.hub_z)
	_box(t, Vector3(0, floor_y + .35, hub_z - .12), Vector3(1.0, .22, .18), g.C_DASH)
	_box(t, Vector3(sx, floor_y + .49, hub_z - .1), Vector3(.30, .06, .12), g.C_TRIM, Basis(Vector3.RIGHT, .3))
	for dx in [-.06, .06]:
		_box(t, Vector3(sx + dx, floor_y + .5, hub_z - .03), Vector3(.07, .05, .01), g.C_DIAL, Basis(Vector3.RIGHT, .3))
	var column_to := Vector3(sx, float(s.hub_y) - .3, hub_z - .2)
	_steering_wheel(t, Vector3(sx, float(s.hub_y), hub_z), float(s.r), float(s.tilt), g.C_TRIM, column_to)
	# Câmbio e freio de mão no túnel entre os bancos.
	_box(t, Vector3(0, floor_y + .16, sz - .1), Vector3(.2, .22, .8), Color("23262a"))
	_tube(t, Vector3(0, floor_y + .27, sz - .2), Vector3(0, floor_y + .46, sz - .32), .016, g.C_CHROME, 5)
	_box(t, Vector3(0, floor_y + .48, sz - .33), Vector3(.06, .06, .06), g.C_TRIM)
	# Pedais.
	var pedal_z := sz - float(s.foot_dist) - .06
	for x in [sx - .12, sx + .03, sx + .15]:
		_box(t, Vector3(x, floor_y + .1, pedal_z), Vector3(.07, .05, .13), g.C_RUBBER, Basis(Vector3.RIGHT, .7))
	_belt(t, s)

static func _seat_shell(t: SurfaceTool, x: float, z: float, cush: float, color: Color) -> void:
	_box(t, Vector3(x, cush - .08, z), Vector3(.42, .16, .48), color)
	var tilt := Basis(Vector3.RIGHT, .32)
	_box(t, Vector3(x, cush + .30, z + .30), Vector3(.42, .62, .11), color, tilt)
	_box(t, Vector3(x, cush + .68, z + .37), Vector3(.24, .16, .09), color.lightened(.06), tilt)
	for side in [-1.0, 1.0]:
		_box(t, Vector3(x + side * .2, cush + .08, z + .02), Vector3(.06, .2, .5), color.darkened(.1))

## Empilhadeira: coluna de direção estreita entre os joelhos, volante pequeno com manopla,
## painel, alavancas, pedais, capa do banco e cinto abdominal. A proteção superior e o
## banco são do modelo.
static func _forklift(t: SurfaceTool, s: Dictionary) -> void:
	var sz := float(s.sz)
	var floor_y := float(s.floor)
	var hub_z := float(s.hub_z)
	var hub_y := float(s.hub_y)
	# Capa do banco e apoio lombar por cima do estofado do modelo.
	_box(t, Vector3(0, float(s.cush) + .02, sz), Vector3(.5, .045, .48), g.C_SEAT_DARK)
	var lean := Basis(Vector3.RIGHT, .1)
	_box(t, Vector3(0, float(s.cush) + .40, sz + .15), Vector3(.46, .5, .04), g.C_SEAT_DARK, lean)
	# Pedestal do painel e coluna.
	_box(t, Vector3(0, floor_y + .17, hub_z - .28), Vector3(.24, .34, .16), Color("2a2d31"))
	_box(t, Vector3(0, hub_y - .27, hub_z - .12), Vector3(.30, .10, .20), g.C_DASH, Basis(Vector3.RIGHT, -.25))
	for dx in [-.07, .07]:
		_box(t, Vector3(dx, hub_y - .21, hub_z - .03), Vector3(.08, .06, .01), g.C_DIAL, Basis(Vector3.RIGHT, -.25))
	var column_to := Vector3(0, hub_y - .25, hub_z - .12)
	_steering_wheel(t, Vector3(0, hub_y, hub_z), float(s.r), float(s.tilt), g.C_TRIM, column_to)
	# Manopla do volante (spinner).
	var b := _wheel_basis(float(s.tilt))
	_box(t, Vector3(0, hub_y, hub_z) + b * Vector3(-float(s.r) * .8, float(s.r) * .35, .035), Vector3(.05, .05, .06), g.C_AMBER, b)
	# Pedais e piso antiderrapante.
	_box(t, Vector3(0, floor_y + .008, hub_z - .05), Vector3(.62, .012, .5), Color("3a3d42"))
	for x in [-.2, .2]:
		_box(t, Vector3(x, floor_y + .06, hub_z - .18), Vector3(.09, .04, .12), g.C_RUBBER, Basis(Vector3.RIGHT, .7))
	# Alavancas do hidráulico à direita e apoio de braço.
	for i in 3:
		var lx := .28 + i * .0
		var lz := sz - .34 + i * .11
		_tube(t, Vector3(lx, float(s.cush) + .12, lz), Vector3(lx - .02, float(s.cush) + .36, lz - .03), .012, g.C_CHROME, 5)
		_box(t, Vector3(lx - .02, float(s.cush) + .38, lz - .03), Vector3(.035, .035, .035), [g.C_AMBER, Color("c0392b"), Color("2e86c1")][i])
	_box(t, Vector3(.29, float(s.cush) + .08, sz - .22), Vector3(.1, .09, .5), g.C_TRIM)
	# Cinto abdominal.
	_box(t, Vector3(0, float(s.cush) + .16, sz - .02), Vector3(.5, .03, .014), g.C_BELT)
	_box(t, Vector3(0, float(s.cush) + .16, sz - .03), Vector3(.06, .05, .02), g.C_CHROME)
	# Luz de trabalho / girofle no console da proteção: pequeno painel de comandos.
	_box(t, Vector3(0, 1.98, sz - .5), Vector3(.24, .05, .1), g.C_TRIM)
